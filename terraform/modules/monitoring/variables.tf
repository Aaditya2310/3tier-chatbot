variable "name" { type = string }
variable "ssm_prefix" { type = string }
variable "subnet_id" { type = string }
variable "monitoring_sg_id" { type = string }
variable "alb_arn_suffix" { type = string }
variable "target_group_arn_suffix" { type = string }
variable "db_identifier" { type = string }
variable "asg_name" { type = string }

variable "instance_type" {
  type        = string
  description = "t3.small: Prometheus + Grafana together are tight on 1 GB"
  default     = "t3.small"
}

variable "alert_email" {
  type    = string
  default = ""
}
