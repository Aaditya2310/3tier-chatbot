output "instance_id" { value = aws_instance.monitoring.id }
output "grafana_password_param" { value = aws_ssm_parameter.grafana_password.name }
output "alerts_topic_arn" { value = aws_sns_topic.alerts.arn }
