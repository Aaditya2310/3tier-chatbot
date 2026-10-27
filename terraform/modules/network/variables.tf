variable "name" { type = string }
variable "region" { type = string }

variable "cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "nat_mode" {
  type        = string
  description = "\"gateway\" (managed, pricier) or \"instance\" (t4g.nano, cheap, self-managed)"
  default     = "instance"
  validation {
    condition     = contains(["gateway", "instance"], var.nat_mode)
    error_message = "nat_mode must be \"gateway\" or \"instance\"."
  }
}
