#!/usr/bin/env python3
"""Read existing SSM values locally. Never print configuration or credentials."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

BASE = Path("/opt/zipsai")


def get_parameter(name, region, secure=False):
    args = ["aws", "ssm", "get-parameter", "--region", region, "--name", name, "--output", "json"]
    if secure:
        args.append("--with-decryption")
    result = json.loads(subprocess.check_output(args, stderr=subprocess.DEVNULL))
    if secure and result["Parameter"]["Type"] != "SecureString":
        raise ValueError("Secret path must reference a SecureString")
    if not secure and result["Parameter"]["Type"] == "SecureString":
        raise ValueError("Put SecureString paths in the secret map")
    return result["Parameter"]["Value"]


def dotenv(values):
    lines = []
    for key, value in sorted(values.items()):
        if not re.fullmatch(r"[A-Z][A-Z0-9_]*", key) or not isinstance(value, str):
            raise ValueError("Invalid runtime variable")
        if any(c in value for c in "\n\r\x00"):
            raise ValueError("Runtime values must be single-line")
        # Escape Compose interpolation and double-quoted dotenv metacharacters.
        escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "$$")
        lines.append(f'{key}="{escaped}"')
    return "\n".join(lines) + "\n"


def main(tag):
    config = json.loads((BASE / "deployment.json").read_text())
    role = config["service"]
    if role != "qdrant" and not re.fullmatch(r"[0-9a-f]{7}", tag):
        raise ValueError("Choose an explicit SHA7 tag")
    values = json.loads(get_parameter(config["runtime_parameter"], config["region"]))
    for key, path in config.get("runtime_parameters", {}).items():
        if key in {"QDRANT_URL", "EMBEDDING_API_URL", "S3_BUCKET", "AWS_REGION"}:
            raise ValueError("Use the new host infrastructure addresses, not legacy endpoint parameters")
        values[key] = get_parameter(path, config["region"])
    forbidden = {"LLM_API_KEY", "OPENROUTER_API_KEY", "QDRANT_API_KEY", "QDRANT_ADMIN_API_KEY", "QDRANT_READ_ONLY_API_KEY", "QDRANT__SERVICE__API_KEY", "LANGFUSE_SECRET_KEY"}
    if forbidden.intersection(values):
        raise ValueError("Store secret values in SecureString, not runtime JSON")
    for key, path in config["secret_parameters"].items():
        values[key] = get_parameter(path, config["region"], secure=True)
        if not values[key]:
            raise ValueError("Required secret is empty")
    if role == "ai-api":
        for key in ["QDRANT_URL", "EMBEDDING_API_URL", "S3_BUCKET", "LLM_BASE_URL", "LLM_MODEL", "VLM_MODEL", "LLM_API_KEY"]:
            if not values.get(key):
                raise ValueError("Complete required AI settings before deployment")
        if not values["LLM_BASE_URL"].startswith("https://"):
            raise ValueError("External model endpoint requires HTTPS")
        values["AI_API_IMAGE_TAG"] = tag
    elif role == "embedding":
        values["EMBEDDING_IMAGE_TAG"] = tag
    elif not values.get("QDRANT_ADMIN_API_KEY") or not values.get("QDRANT_READ_ONLY_API_KEY"):
        raise ValueError("Configure Qdrant authentication before deployment")
    target = BASE / "runtime.env.next"
    descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        stream.write(dotenv(values))
    os.chmod(target, 0o600)


if __name__ == "__main__":
    try:
        main(sys.argv[1] if len(sys.argv) > 1 else "")
    except Exception:
        print("AI runtime preparation failed: check required settings and SSM access.", file=sys.stderr)
        sys.exit(1)
