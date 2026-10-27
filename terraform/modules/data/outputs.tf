output "db_identifier" { value = aws_db_instance.this.identifier }
output "db_endpoint" { value = aws_db_instance.this.endpoint }
output "database_url_param_arn" { value = aws_ssm_parameter.database_url.arn }
output "database_url_param_name" { value = aws_ssm_parameter.database_url.name }
