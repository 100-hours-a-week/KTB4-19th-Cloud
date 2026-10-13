import {
  for_each = local.ecr_repositories

  to = aws_ecr_repository.service[each.key]
  id = each.value
}

import {
  to = aws_route53_zone.public
  id = "Z0887629CNID03PL4131"
}

import {
  to = aws_route53_record.mx
  id = "Z0887629CNID03PL4131_zipsai.co.kr_MX"
}

import {
  to = aws_s3_bucket.uploads
  id = "zipsai-prod-uploads"
}

import {
  to = aws_s3_bucket_public_access_block.uploads
  id = "zipsai-prod-uploads"
}

import {
  to = aws_s3_bucket_ownership_controls.uploads
  id = "zipsai-prod-uploads"
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.uploads
  id = "zipsai-prod-uploads"
}

import {
  to = aws_s3_bucket_cors_configuration.uploads
  id = "zipsai-prod-uploads"
}

import {
  to = aws_s3_bucket_policy.uploads
  id = "zipsai-prod-uploads"
}

