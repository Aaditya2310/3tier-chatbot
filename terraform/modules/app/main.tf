# App tier: ALB (public subnets) -> Auto Scaling Group of Docker hosts (private app subnets).
data "aws_region" "current" {}
data "aws_caller_identity" "me" {}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  param_arn_prefix = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.me.account_id}:parameter/${var.ssm_prefix}"
}

# CI writes the image tag here; instances read it at boot. Terraform creates it once
# and then ignores the value, so `terraform apply` never rolls back a deploy.
resource "aws_ssm_parameter" "image" {
  name  = "/${var.ssm_prefix}/app/image"
  type  = "String"
  value = var.initial_image
  lifecycle { ignore_changes = [value] }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.ssm_prefix}/app"
  retention_in_days = 7
}

# ---------- IAM for instances ----------
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-app"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# SSM Session Manager: shell access with no SSH keys, no port 22, no bastion.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadOwnParameters"
    actions   = ["ssm:GetParameter"]
    resources = ["${local.param_arn_prefix}/*"]
  }
  statement {
    sid       = "ShipContainerLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "app" {
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-app"
  role = aws_iam_role.app.name
}

# ---------- Load balancer ----------
resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  subnets                    = var.public_subnet_ids
  security_groups            = [var.alb_sg_id]
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.name}-app"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  deregistration_delay = 30 # default 300s makes every deploy slow

  health_check {
    # /health, not /ready: if RDS blips, a DB-checking health check would mark EVERY
    # instance unhealthy and the ASG would replace the whole fleet for nothing.
    path                = "/health"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

locals { https = var.certificate_arn != "" }

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.https ? "redirect" : "forward"
    target_group_arn = local.https ? null : aws_lb_target_group.app.arn
    dynamic "redirect" {
      for_each = local.https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = local.https ? 1 : 0
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# /metrics must never be public. Prometheus scrapes instances directly inside the VPC.
resource "aws_lb_listener_rule" "block_metrics" {
  listener_arn = local.https ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
  priority     = 10
  condition {
    path_pattern { values = ["/metrics", "/metrics/*"] }
  }
  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

# ---------- Launch template + ASG ----------
resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-app-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile { arn = aws_iam_instance_profile.app.arn }
  vpc_security_group_ids = [var.app_sg_id]

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only: blocks SSRF-style credential theft
    http_put_response_hop_limit = 2          # containers need 2 hops to reach IMDS
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 10
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    region             = data.aws_region.current.region
    image_param        = aws_ssm_parameter.image.name
    database_url_param = var.database_url_param_name
    log_group          = aws_cloudwatch_log_group.app.name
    llm_provider       = var.llm_provider
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.name}-app", Role = "${var.name}-app" } # Role tag = Prometheus discovery
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${var.name}-app"
  vpc_zone_identifier       = var.app_subnet_ids
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.min_size
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB" # replace instances the ALB considers unhealthy, not just dead VMs
  health_check_grace_period = 180   # time for dnf + docker pull before health checks count

  enabled_metrics = ["GroupInServiceInstances", "GroupDesiredCapacity", "GroupPendingInstances", "GroupTerminatingInstances"]

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # Changing the launch template rolls instances one batch at a time.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 180
    }
  }

  lifecycle { ignore_changes = [desired_capacity] } # owned by the scaling policy

  tag {
    key                 = "Name"
    value               = "${var.name}-app"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "requests_per_target" {
  name                   = "${var.name}-req-per-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = var.requests_per_target
  }
}
