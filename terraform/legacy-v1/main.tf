# Existing AWS configuration; reviewed Import-only baseline.
# Security-group rules and IAM policies owned by other roots are intentionally excluded.



resource "aws_iam_instance_profile" "production" {
  name = "zipsai-prod-ec2-profile"
  path = "/"
  role = "zipsai-prod-ec2-role"
  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
    Project     = "zipsai"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_instance_profile" "rehearsal" {
  name = "zipsai-load-test-ec2-role"
  path = "/"
  role = "zipsai-load-test-ec2-role"
  tags = {}

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "production" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  description           = null
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = "zipsai-prod-ec2-role"
  path                  = "/"
  permissions_boundary  = null
  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
    Project     = "zipsai"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role" "rehearsal" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  description           = "Allows EC2 instances to call AWS services on your behalf."
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = "zipsai-load-test-ec2-role"
  path                  = "/"
  permissions_boundary  = null
  tags                  = {}

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "rehearsal_observability" {
  name = "zipsai-load-test-observability"
  policy = jsonencode({
    Statement = [{
      Action = ["cloudwatch:PutMetricData"]
      Condition = {
        StringEquals = {
          "cloudwatch:namespace" = "Zipsai/LoadTest"
        }
      }
      Effect   = "Allow"
      Resource = "*"
      Sid      = "PublishLoadTestContainerMetrics"
      }, {
      Action   = ["logs:CreateLogGroup"]
      Effect   = "Allow"
      Resource = "*"
      Sid      = "WriteLoadTestLogs"
      }, {
      Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = "arn:aws:logs:ap-northeast-2:929368845727:log-group:/zipsai/load-test/*"
      Sid      = "WriteLoadTestServiceLogs"
    }]
    Version = "2012-10-17"
  })
  role = "zipsai-load-test-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "rehearsal_s3" {
  name = "zipsai-load-test-s3-access"
  policy = jsonencode({
    Statement = [{
      Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
      Effect   = "Allow"
      Resource = "arn:aws:s3:::zipsai-load-test-uploads"
      Sid      = "ListLoadTestUploadBucket"
      }, {
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "arn:aws:s3:::zipsai-load-test-uploads/*"
      Sid      = "ReadWriteLoadTestUploadObjects"
    }]
    Version = "2012-10-17"
  })
  role = "zipsai-load-test-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "production_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = "zipsai-prod-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "production_logs" {
  policy_arn = "arn:aws:iam::929368845727:policy/Zipsai-WriteCloudWatchLogs"
  role       = "zipsai-prod-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "production_runtime" {
  policy_arn = "arn:aws:iam::929368845727:policy/zipsai-prod-ec2-runtime"
  role       = "zipsai-prod-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "production_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = "zipsai-prod-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "rehearsal_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = "zipsai-load-test-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "rehearsal_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "zipsai-load-test-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "rehearsal_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = "zipsai-load-test-ec2-role"

  lifecycle {
    prevent_destroy = true
  }
}



resource "aws_security_group" "production" {
  description            = "Allow HTTP and HTTPS access to the V1 service"
  name                   = "zipsai-prod-service-f51dcdcb986080adcba5f88592"
  region                 = "ap-northeast-2"
  revoke_rules_on_delete = null
  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
    Name        = "zipsai-prod-service-sg"
    Project     = "zipsai"
  }
  vpc_id = "vpc-0e01c25a55f10f584"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_security_group" "rehearsal" {
  description            = "Zipsai load test EC2 - SSM only"
  name                   = "zipsai-load-test-sg"
  region                 = "ap-northeast-2"
  revoke_rules_on_delete = null
  tags                   = {}
  vpc_id                 = "vpc-0e01c25a55f10f584"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "production" {
  cidr_ipv4                    = "0.0.0.0/0"
  cidr_ipv6                    = null
  description                  = "Allow outbound access for AWS services and external APIs"
  from_port                    = null
  ip_protocol                  = "-1"
  prefix_list_id               = null
  referenced_security_group_id = null
  region                       = "ap-northeast-2"
  security_group_id            = "sg-0a4b86875aa8535b7"
  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
    Project     = "zipsai"
  }
  to_port = null

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "rehearsal" {
  cidr_ipv4                    = "0.0.0.0/0"
  cidr_ipv6                    = null
  description                  = null
  from_port                    = null
  ip_protocol                  = "-1"
  prefix_list_id               = null
  referenced_security_group_id = null
  region                       = "ap-northeast-2"
  security_group_id            = "sg-0b5cb3cd96f3313a6"
  tags                         = null
  to_port                      = null

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "production_http" {
  cidr_ipv4                    = "0.0.0.0/0"
  cidr_ipv6                    = null
  description                  = "Allow HTTP access to Nginx"
  from_port                    = 80
  ip_protocol                  = "tcp"
  prefix_list_id               = null
  referenced_security_group_id = null
  region                       = "ap-northeast-2"
  security_group_id            = "sg-0a4b86875aa8535b7"
  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
    Project     = "zipsai"
  }
  to_port = 80

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "production_https" {
  cidr_ipv4                    = "0.0.0.0/0"
  cidr_ipv6                    = null
  description                  = "Allow HTTPS access to Nginx"
  from_port                    = 443
  ip_protocol                  = "tcp"
  prefix_list_id               = null
  referenced_security_group_id = null
  region                       = "ap-northeast-2"
  security_group_id            = "sg-0a4b86875aa8535b7"
  tags = {
    Environment = "prod"
    ManagedBy   = "Terraform"
    Project     = "zipsai"
  }
  to_port = 443

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "production_https_self" {
  cidr_ipv4                    = null
  cidr_ipv6                    = null
  description                  = null
  from_port                    = 443
  ip_protocol                  = "tcp"
  prefix_list_id               = null
  referenced_security_group_id = "sg-0a4b86875aa8535b7"
  region                       = "ap-northeast-2"
  security_group_id            = "sg-0a4b86875aa8535b7"
  tags                         = null
  to_port                      = 443

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rehearsal_http" {
  cidr_ipv4                    = "0.0.0.0/0"
  cidr_ipv6                    = null
  description                  = null
  from_port                    = 80
  ip_protocol                  = "tcp"
  prefix_list_id               = null
  referenced_security_group_id = null
  region                       = "ap-northeast-2"
  security_group_id            = "sg-0b5cb3cd96f3313a6"
  tags                         = null
  to_port                      = 80

  lifecycle {
    prevent_destroy = true
  }
}
