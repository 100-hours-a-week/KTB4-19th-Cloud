locals {
  image_cleanup_services = toset(["ai-api", "embedding"])
  image_cleanup_source   = base64encode(file("${path.module}/templates/cleanup-images.py"))
}

resource "aws_ssm_document" "image_cleanup" {
  for_each        = local.image_cleanup_services
  name            = "${var.name_prefix}-${each.key}-image-cleanup"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Remove unused AI images only; protect verified release and all containers"
    parameters = {
      Mode = { type = "String", default = "audit", allowedValues = ["audit", "apply"] }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "scopedImageCleanup"
      inputs = {
        timeoutSeconds = "300"
        runCommand = [join("\n", [
          "set -eu",
          "python3 - '${var.image_repository_urls[each.key]}' '${each.key}' '{{ Mode }}' <<'PY'",
          "import base64",
          "exec(compile(base64.b64decode('${local.image_cleanup_source}'), '<scoped-image-cleanup>', 'exec'))",
          "PY"
        ])]
      }
    }]
  })
  tags = var.common_tags
}

# No scheduled Association. Cleanup runs after a successful AI-owned CD.
# This guarded document remains available for explicit operator audit/recovery only.
