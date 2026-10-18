# 실제 Import는 검토한 plan의 apply 승인 이후에만 실행한다.
import {
  to = aws_instance.production
  id = "i-06c0ca0d997f03792"
}
import {
  to = aws_instance.rehearsal
  id = "i-0e87dade1272d42cc"
}
import {
  to = aws_security_group.production
  id = "sg-0a4b86875aa8535b7"
}
import {
  to = aws_security_group.rehearsal
  id = "sg-0b5cb3cd96f3313a6"
}
import {
  to = aws_vpc_security_group_ingress_rule.production_https_self
  id = "sgr-01d4b268b4780a96b"
}
import {
  to = aws_vpc_security_group_ingress_rule.production_https
  id = "sgr-03ecbee3df0b173ba"
}
import {
  to = aws_vpc_security_group_ingress_rule.production_http
  id = "sgr-058c07ced34e8fb60"
}
import {
  to = aws_vpc_security_group_egress_rule.production
  id = "sgr-0efc0ac5a38d45a26"
}
import {
  to = aws_vpc_security_group_ingress_rule.rehearsal_http
  id = "sgr-0228654df3aa9b487"
}
import {
  to = aws_vpc_security_group_egress_rule.rehearsal
  id = "sgr-0b45be13c9aace2b3"
}
import {
  to = aws_iam_role.production
  id = "zipsai-prod-ec2-role"
}
import {
  to = aws_iam_role.rehearsal
  id = "zipsai-load-test-ec2-role"
}
import {
  to = aws_iam_instance_profile.production
  id = "zipsai-prod-ec2-profile"
}
import {
  to = aws_iam_instance_profile.rehearsal
  id = "zipsai-load-test-ec2-role"
}
import {
  to = aws_iam_role_policy_attachment.production_cloudwatch
  id = "zipsai-prod-ec2-role/arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
import {
  to = aws_iam_role_policy_attachment.production_ssm
  id = "zipsai-prod-ec2-role/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
import {
  to = aws_iam_role_policy_attachment.production_logs
  id = "zipsai-prod-ec2-role/arn:aws:iam::929368845727:policy/Zipsai-WriteCloudWatchLogs"
}
import {
  to = aws_iam_role_policy_attachment.production_runtime
  id = "zipsai-prod-ec2-role/arn:aws:iam::929368845727:policy/zipsai-prod-ec2-runtime"
}
import {
  to = aws_iam_role_policy_attachment.rehearsal_cloudwatch
  id = "zipsai-load-test-ec2-role/arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
import {
  to = aws_iam_role_policy_attachment.rehearsal_ssm
  id = "zipsai-load-test-ec2-role/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
import {
  to = aws_iam_role_policy_attachment.rehearsal_ecr
  id = "zipsai-load-test-ec2-role/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
import {
  to = aws_iam_role_policy.rehearsal_observability
  id = "zipsai-load-test-ec2-role:zipsai-load-test-observability"
}
import {
  to = aws_iam_role_policy.rehearsal_s3
  id = "zipsai-load-test-ec2-role:zipsai-load-test-s3-access"
}
import {
  to = aws_eip.production
  id = "eipalloc-0ebf1098aefdb27ec"
}
import {
  to = aws_eip_association.production
  id = "eipassoc-082769bab6c98b344"
}
