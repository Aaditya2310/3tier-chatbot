variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "tritier"
}

variable "github_owner" {
  type        = string
  description = "GitHub user or org that owns the repo"
  default     = "Aaditya2310"
}

variable "github_repo" {
  type    = string
  default = "aws-3tier-chatbot-terraform"
}
