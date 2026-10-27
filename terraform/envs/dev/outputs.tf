output "app_url" {
  value = "http://${module.app.alb_dns_name}"
}

output "asg_name" { value = module.app.asg_name }
output "image_param_name" { value = module.app.image_param_name }
output "monitoring_instance_id" { value = module.monitoring.instance_id }

output "grafana_tunnel_command" {
  description = "Run this, then open http://localhost:3000 (user: admin)"
  value       = "aws ssm start-session --region ${var.region} --target ${module.monitoring.instance_id} --document-name AWS-StartPortForwardingSession --parameters portNumber=3000,localPortNumber=3000"
}

output "grafana_password_command" {
  value = "aws ssm get-parameter --region ${var.region} --name /${local.ssm_prefix}/grafana_admin_password --with-decryption --query Parameter.Value --output text"
}
