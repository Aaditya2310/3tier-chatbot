# Data tier: RDS Postgres in the isolated DB subnets.
resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.db_subnet_ids
}

# Letters + digits only so the password is safe inside a connection URL.
# Note: this value IS stored in Terraform state — that's why the state bucket is
# private and encrypted. RDS-managed secrets (manage_master_user_password) avoid
# that, at the cost of Secrets Manager billing.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.instance_class

  allocated_storage     = 20
  max_allocated_storage = 30 # storage autoscaling ceiling
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "chatops"
  username = "chatops"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Portfolio settings so `terraform destroy` works in one go. In production:
  # deletion_protection = true and skip_final_snapshot = false.
  deletion_protection = false
  skip_final_snapshot = true
}

# The app reads this at boot. The DB password never touches GitHub or user-data.
resource "aws_ssm_parameter" "database_url" {
  name  = "/${var.ssm_prefix}/database_url"
  type  = "SecureString"
  value = "postgresql+psycopg://${aws_db_instance.this.username}:${random_password.db.result}@${aws_db_instance.this.endpoint}/${aws_db_instance.this.db_name}"
}
