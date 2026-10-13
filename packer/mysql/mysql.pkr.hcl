packer {
  required_version = ">= 1.11.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.9, < 2.0.0"
    }
  }
}

locals {
  image_timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
}

source "amazon-ebs" "mysql" {
  profile       = var.aws_profile
  region        = var.aws_region
  instance_type = var.build_instance_type

  vpc_id    = var.build_vpc_id != "" ? var.build_vpc_id : null
  subnet_id = var.build_subnet_id != "" ? var.build_subnet_id : null

  associate_public_ip_address               = true
  temporary_security_group_source_public_ip = true
  ssh_username                              = "ubuntu"
  ssh_clear_authorized_keys                 = true

  source_ami_filter {
    filters = {
      architecture        = "x86_64"
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }

  ami_name        = "zipsai-mysql-${var.mysql_version}-x86-64-${local.image_timestamp}"
  ami_description = "Zipsai MySQL ${var.mysql_version} on Ubuntu 24.04 x86_64"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_type           = "gp3"
    volume_size           = 12
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name            = "zipsai-mysql-${var.mysql_version}-x86-64-${local.image_timestamp}"
    Project         = "zipsai"
    Environment     = "shared"
    ManagedBy       = "Packer"
    Architecture    = "x86_64"
    OperatingSystem = "Ubuntu-24.04"
    MySQLVersion    = var.mysql_version
  }

  run_tags = {
    Name        = "zipsai-packer-mysql-${local.image_timestamp}"
    Project     = "zipsai"
    Environment = "build"
    ManagedBy   = "Packer"
  }

  snapshot_tags = {
    Name         = "zipsai-mysql-${var.mysql_version}-x86-64-${local.image_timestamp}"
    Project      = "zipsai"
    Environment  = "shared"
    ManagedBy    = "Packer"
    MySQLVersion = var.mysql_version
  }
}

build {
  name    = "zipsai-mysql"
  sources = ["source.amazon-ebs.mysql"]

  provisioner "file" {
    source      = "files/my.cnf"
    destination = "/tmp/zipsai-my.cnf"
  }

  provisioner "file" {
    source      = "files/mysql.service.override.conf"
    destination = "/tmp/zipsai-mysql-service-override.conf"
  }

  provisioner "file" {
    source      = "files/apparmor-mysqld.local"
    destination = "/tmp/zipsai-apparmor-mysqld.local"
  }

  provisioner "file" {
    source      = "files/node_exporter.service"
    destination = "/tmp/zipsai-node-exporter.service"
  }

  provisioner "file" {
    source      = "files/mysqld_exporter.service"
    destination = "/tmp/zipsai-mysqld-exporter.service"
  }

  provisioner "shell" {
    environment_vars = ["MYSQL_VERSION=${var.mysql_version}"]
    script           = "scripts/install-mysql.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "NODE_EXPORTER_VERSION=${var.node_exporter_version}",
      "MYSQLD_EXPORTER_VERSION=${var.mysqld_exporter_version}",
    ]
    script = "scripts/install-exporters.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "MYSQL_VERSION=${var.mysql_version}",
      "NODE_EXPORTER_VERSION=${var.node_exporter_version}",
      "MYSQLD_EXPORTER_VERSION=${var.mysqld_exporter_version}",
    ]
    script = "scripts/verify-image.sh"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }
}
