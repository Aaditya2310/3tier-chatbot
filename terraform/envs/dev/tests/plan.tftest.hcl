# Offline plan test: mocks AWS so CI (or you) can check module wiring with no account.
# Run: terraform init -backend=false && terraform test
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-south-1a", "ap-south-1b", "ap-south-1c"] }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-south-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  initial_image = "adisru/tritier-chatops:latest"
}

run "nat_instance_default" {
  command = plan

  assert {
    condition     = length(module.network.app_subnet_ids) == 2 && length(module.network.db_subnet_ids) == 2
    error_message = "Expected 2 app and 2 db subnets"
  }
}

run "nat_gateway_mode" {
  command = plan
  variables { nat_mode = "gateway" }
}

run "rejects_bad_nat_mode" {
  command = plan
  variables { nat_mode = "magic" }
  expect_failures = [var.nat_mode]
}
