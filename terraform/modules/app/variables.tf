variable "name" { type = string }
variable "ssm_prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "app_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "app_sg_id" { type = string }
variable "database_url_param_name" { type = string }

variable "initial_image" {
  type        = string
  description = "Image used on first apply. After that, CI owns the value in SSM."
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "min_size" {
  type    = number
  default = 2 # one per AZ, so losing an AZ doesn't take the app down
}

variable "max_size" {
  type    = number
  default = 4
}

variable "requests_per_target" {
  type        = number
  description = "Target-tracking goal: ALB requests per instance per minute"
  default     = 300
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN. Empty = HTTP only."
  default     = ""
}

variable "llm_provider" {
  type    = string
  default = "rule-based"
}
