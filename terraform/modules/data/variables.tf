variable "name" { type = string }
variable "ssm_prefix" { type = string }
variable "db_subnet_ids" { type = list(string) }
variable "db_sg_id" { type = string }

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "multi_az" {
  type        = bool
  description = "Standby in the second AZ. Roughly doubles RDS cost."
  default     = false
}
