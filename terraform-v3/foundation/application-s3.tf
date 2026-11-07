locals {
  application_s3_access = {
    resident-api = {
      prefixes = ["conversations/*", "documents/*"]
      actions  = ["s3:GetObject", "s3:PutObject"]
    }
    manager-api = {
      prefixes = ["conversations/*", "documents/*"]
      actions  = ["s3:GetObject", "s3:PutObject"]
    }
    ai-api = {
      prefixes = ["documents/*"]
      actions  = ["s3:GetObject"]
    }
  }

  application_s3_identities = {
    for pair in setproduct(keys(data.aws_s3_bucket.uploads), keys(local.application_s3_access)) :
    "${pair[0]}-${pair[1]}" => {
      namespace       = pair[0]
      service_account = "${pair[1]}-sa"
      prefixes        = local.application_s3_access[pair[1]].prefixes
      actions         = local.application_s3_access[pair[1]].actions
    }
  }
}

resource "aws_iam_role" "application_s3" {
  for_each = local.application_s3_identities

  name = "v3-${each.key}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = {
          "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.v3.arn
          "aws:RequestTag/kubernetes-namespace"       = each.value.namespace
          "aws:RequestTag/kubernetes-service-account" = each.value.service_account
        }
      }
    }]
  })
  tags = local.v3_tags
}

resource "aws_iam_role_policy" "application_s3" {
  for_each = local.application_s3_identities

  name = "application-upload-objects"
  role = aws_iam_role.application_s3[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = each.value.actions
      Resource = [for prefix in each.value.prefixes : "${data.aws_s3_bucket.uploads[each.value.namespace].arn}/${prefix}"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "application_s3" {
  for_each = local.application_s3_identities

  cluster_name    = aws_eks_cluster.v3.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.application_s3[each.key].arn
  tags            = local.v3_tags

  depends_on = [aws_iam_role_policy.application_s3]
}
