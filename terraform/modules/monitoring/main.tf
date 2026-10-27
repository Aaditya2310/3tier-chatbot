# Monitoring: one private EC2 instance running Prometheus + Grafana in Docker.
#   Prometheus -> discovers ASG instances via the EC2 API, scrapes /metrics inside the VPC
#   Grafana    -> Prometheus (app metrics) + CloudWatch (ALB/RDS/ASG) on one pane
#   Alarms     -> CloudWatch alarms -> SNS -> email (they keep working even if this box dies)
data "aws_region" "current" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  region   = data.aws_region.current.region
  mon_root = "${path.module}/../../../monitoring"
}

resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "grafana_password" {
  name  = "/${var.ssm_prefix}/grafana_admin_password"
  type  = "SecureString"
  value = random_password.grafana.result
}

# ---------- IAM ----------
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name               = "${var.name}-monitoring"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "monitoring" {
  statement {
    sid       = "PrometheusEC2Discovery"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeAvailabilityZones"]
    resources = ["*"]
  }
  statement {
    sid = "GrafanaCloudWatchRead"
    actions = [
      "cloudwatch:GetMetricData", "cloudwatch:ListMetrics", "cloudwatch:GetMetricStatistics",
      "cloudwatch:DescribeAlarms", "ec2:DescribeRegions", "tag:GetResources",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "ReadGrafanaPassword"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.grafana_password.arn]
  }
}

resource "aws_iam_role_policy" "monitoring" {
  role   = aws_iam_role.monitoring.id
  policy = data.aws_iam_policy_document.monitoring.json
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.name}-monitoring"
  role = aws_iam_role.monitoring.name
}

# ---------- config files shipped through cloud-init (gzipped to stay under 16 KB) ----------
data "cloudinit_config" "monitoring" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      write_files = [
        {
          path    = "/opt/mon/prometheus/prometheus.yml"
          content = templatefile("${local.mon_root}/prometheus/prometheus.aws.yml.tpl", { region = local.region, project = var.name })
        },
        {
          path    = "/opt/mon/grafana/provisioning/datasources/prometheus.yml"
          content = file("${local.mon_root}/grafana/provisioning/datasources/prometheus.yml")
        },
        {
          path    = "/opt/mon/grafana/provisioning/datasources/cloudwatch.yml"
          content = replace(file("${local.mon_root}/grafana/provisioning/datasources/cloudwatch.yml"), "$${region}", local.region)
        },
        {
          path    = "/opt/mon/grafana/provisioning/dashboards/provider.yml"
          content = file("${local.mon_root}/grafana/provisioning/dashboards/provider.yml")
        },
        {
          path    = "/opt/mon/grafana/provisioning/dashboards/app.json"
          content = file("${local.mon_root}/grafana/provisioning/dashboards/app.json")
        },
        {
          path = "/opt/mon/grafana/provisioning/dashboards/aws.json"
          content = templatefile("${local.mon_root}/grafana/provisioning/dashboards/aws.json.tpl", {
            alb_dimension = var.alb_arn_suffix
            tg_dimension  = var.target_group_arn_suffix
            db_identifier = var.db_identifier
            asg_name      = var.asg_name
          })
        },
      ]
    })
  }

  part {
    content_type = "text/x-shellscript"
    content      = <<-SH
      #!/bin/bash
      set -euo pipefail
      dnf install -y docker
      systemctl enable --now docker
      GF_PASS=$(aws ssm get-parameter --region ${local.region} --name "${aws_ssm_parameter.grafana_password.name}" --with-decryption --query Parameter.Value --output text)
      docker network create mon || true
      docker volume create prom-data
      docker run -d --name prometheus --network mon --restart always -p 9090:9090 \
        -v /opt/mon/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
        -v prom-data:/prometheus \
        prom/prometheus:v2.55.1 --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.retention.time=7d
      docker run -d --name grafana --network mon --restart always -p 3000:3000 \
        -e GF_SECURITY_ADMIN_PASSWORD="$GF_PASS" -e GF_USERS_ALLOW_SIGN_UP=false \
        -v /opt/mon/grafana/provisioning:/etc/grafana/provisioning:ro \
        grafana/grafana:11.3.1
    SH
  }
}

resource "aws_instance" "monitoring" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.monitoring_sg_id]
  iam_instance_profile        = aws_iam_instance_profile.monitoring.name
  user_data_base64            = data.cloudinit_config.monitoring.rendered
  user_data_replace_on_change = true # config change = fresh instance (Prometheus data is disposable here)

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # Grafana container uses the instance role via IMDS
  }

  root_block_device {
    volume_size = 15
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "${var.name}-monitoring" }
  # New AL2023 AMIs would otherwise force-replace this instance on every plan.
  lifecycle { ignore_changes = [ami] }
}

# ---------- CloudWatch alarms -> email ----------
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email" # AWS sends a confirmation email you must click
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.name}-target-5xx"
  alarm_description   = "App returned more than 5 server errors in 5 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching" # no traffic is not an outage
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.name}-unhealthy-hosts"
  alarm_description   = "At least one target failing ALB health checks for 2 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.target_group_arn_suffix }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-rds-cpu"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.name}-rds-free-storage"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_identifier }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648 # 2 GiB
  comparison_operator = "LessThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
