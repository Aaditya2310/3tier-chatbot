terraform {
  required_version = ">= 1.10" # 1.10+ for native S3 state locking (no DynamoDB table)
  required_providers {
    aws       = { source = "hashicorp/aws", version = "~> 6.0" }
    random    = { source = "hashicorp/random", version = "~> 3.6" }
    cloudinit = { source = "hashicorp/cloudinit", version = "~> 2.3" }
  }

  # Fill in the bucket from `terraform output state_bucket` in terraform/bootstrap.
  # Backend blocks can't use variables, so pass it at init time instead:
  #   terraform init -backend-config="bucket=tritier-tfstate-<account-id>"
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = var.project, Environment = var.env, ManagedBy = "terraform" }
  }
}
