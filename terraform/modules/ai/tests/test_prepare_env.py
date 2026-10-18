import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("prepare_env", Path(__file__).parents[1] / "templates" / "prepare-env.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PrepareEnvironmentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.base_patch = patch.object(MODULE, "BASE", self.base)
        self.base_patch.start()
        self.addCleanup(self.base_patch.stop)
        self.addCleanup(self.temp.cleanup)

    def manifest(self, role, secrets):
        (self.base / "deployment.json").write_text(json.dumps({
            "service": role, "runtime_parameter": "/test/runtime", "region": "test",
            "secret_parameters": secrets,
        }))

    def test_api_credentials_and_mode(self):
        self.manifest("ai-api", {"LLM_API_KEY": "/test/key", "QDRANT_ADMIN_API_KEY": "/test/qdrant"})
        values = {key: "test-value" for key in [
            "QDRANT_URL", "EMBEDDING_API_URL", "S3_BUCKET", "LLM_MODEL", "VLM_MODEL"
        ]}
        values["LLM_BASE_URL"] = "https://example.invalid/v1"
        def fake_get(name, region, secure=False):
            return "fake-secret-only" if secure else json.dumps(values)
        with patch.object(MODULE, "get_parameter", side_effect=fake_get):
            MODULE.main("abcdef0")
        output = self.base / "runtime.env.next"
        self.assertEqual(output.stat().st_mode & 0o777, 0o600)
        self.assertIn('AI_API_IMAGE_TAG="abcdef0"', output.read_text())
        self.assertIn('LLM_API_KEY="fake-secret-only"', output.read_text())

    def test_invalid_tag_before_fetch(self):
        self.manifest("embedding", {})
        with patch.object(MODULE, "get_parameter") as fetch:
            with self.assertRaises(ValueError):
                MODULE.main("latest")
            fetch.assert_not_called()

    def test_reject_secret_in_general_json(self):
        self.manifest("embedding", {})
        with patch.object(MODULE, "get_parameter", return_value='{"LLM_API_KEY":"fake"}'):
            with self.assertRaises(ValueError):
                MODULE.main("abcdef0")

    def test_qdrant_admin_and_read_only_required(self):
        self.manifest("qdrant", {})
        with patch.object(MODULE, "get_parameter", return_value="{}"):
            with self.assertRaises(ValueError):
                MODULE.main("")

    def test_langfuse_public_string_and_secret_secure_string(self):
        self.manifest("embedding", {"LANGFUSE_SECRET_KEY": "/test/langfuse/secret-key"})
        manifest = self.base / "deployment.json"
        config = json.loads(manifest.read_text())
        config["runtime_parameters"] = {
            "LANGFUSE_PUBLIC_KEY": "/test/langfuse/public-key",
            "LANGFUSE_BASE_URL": "/test/langfuse/base-url",
        }
        manifest.write_text(json.dumps(config))
        def fake_cli(args, **kwargs):
            name = args[args.index("--name") + 1]
            parameters = {
                "/test/runtime": ("String", "{}"),
                "/test/langfuse/public-key": ("String", "pk-test"),
                "/test/langfuse/base-url": ("String", "https://example.invalid"),
                "/test/langfuse/secret-key": ("SecureString", "sk-test"),
            }
            kind, value = parameters[name]
            self.assertEqual("--with-decryption" in args, kind == "SecureString")
            return json.dumps({"Parameter": {"Type": kind, "Value": value}})
        with patch.object(MODULE.subprocess, "check_output", side_effect=fake_cli):
            MODULE.main("abcdef0")
        output = (self.base / "runtime.env.next").read_text()
        self.assertIn('LANGFUSE_PUBLIC_KEY="pk-test"', output)
        self.assertIn('LANGFUSE_SECRET_KEY="sk-test"', output)

    def test_missing_parameter_blocks_deployment_not_infra(self):
        self.manifest("embedding", {"LANGFUSE_SECRET_KEY": "/missing/key"})
        def fake_get(name, region, secure=False):
            if secure:
                raise subprocess.CalledProcessError(254, ["aws", "ssm", "get-parameter"])
            return "{}"
        with patch.object(MODULE, "get_parameter", side_effect=fake_get):
            with self.assertRaises(subprocess.CalledProcessError):
                MODULE.main("abcdef0")
        self.assertFalse((self.base / "runtime.env.next").exists())

    def test_reject_multiline(self):
        with self.assertRaises(ValueError):
            MODULE.dotenv({"KEY": "line1\nline2"})

    @unittest.skipUnless(shutil.which("docker"), "Docker CLI required for Compose parsing")
    def test_compose_dotenv_round_trip(self):
        templates = Path(__file__).parents[1].parents[2] / "compose" / "ai"
        probes = ["dollar$hash#quote'backslash\\tail", "ends\\", "quote\\'end"]
        for role in ["ai-api", "embedding", "qdrant"]:
            source = (templates / f"compose-{role}.yml.tftpl").read_text()
            source = source.replace("${repository_url}", "example.invalid/test")
            source = source.replace("${aws_region}", "ap-northeast-2").replace("${log_group}", "/test")
            source = source.replace("${qdrant_version}", "v1.19.1").replace("$${", "${")
            compose = self.base / "compose.yaml"
            compose.write_text(source)
            for probe in probes:
                env = {
                    "AI_API_IMAGE_TAG": "abcdef0", "EMBEDDING_IMAGE_TAG": "abcdef0",
                    "LLM_API_KEY": probe, "QDRANT_ADMIN_API_KEY": probe,
                    "QDRANT_READ_ONLY_API_KEY": probe, "QUOTE_PROBE": probe,
                }
                (self.base / "runtime.env").write_text(MODULE.dotenv(env))
                result = subprocess.run([
                    "docker", "compose", "--env-file", str(self.base / "runtime.env"),
                    "-f", str(compose), "config", "--format", "json",
                ], text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, "Compose dotenv parsing failed")
                parsed = json.loads(result.stdout)
                # Canonical Compose output escapes dollars for re-parsing.
                rendered = parsed["services"][role]["environment"]["QUOTE_PROBE"]
                self.assertEqual(rendered.replace("$$", "$"), probe)
                aliases = ["LLM_API_KEY", "OPENROUTER_API_KEY", "QDRANT_API_KEY"] if role == "ai-api" else []
                if role == "qdrant":
                    aliases = ["QDRANT__SERVICE__API_KEY", "QDRANT__SERVICE__READ_ONLY_API_KEY"]
                for key in aliases:
                    self.assertEqual(parsed["services"][role]["environment"][key].replace("$$", "$"), probe)


if __name__ == "__main__":
    unittest.main()
