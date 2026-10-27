variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "tritier"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "nat_mode" {
  type        = string
  description = "\"instance\" (cheap, default) or \"gateway\" (managed NAT Gateway)"
  default     = "instance"
  validation {
    condition     = contains(["gateway", "instance"], var.nat_mode)
    error_message = "nat_mode must be \"gateway\" or \"instance\"."
  }
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "initial_image" {
  type        = string
  description = "e.g. adisru/tritier-chatops:latest — only used on first apply"
}

variable "app_min_size" {
  type    = number
  default = 2
}

variable "app_max_size" {
  type    = number
  default = 4
}

variable "certificate_arn" {
  type    = string
  default = ""
}

variable "alert_email" {
  type    = string
  default = ""
}
