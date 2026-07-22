output "cluster_name" { 
  value = aws_ecs_cluster.main.name 
}

output "cluster_arn" { 
  value = aws_ecs_cluster.main.arn 
}

output "service_names" { 
  value = { for k, v in aws_ecs_service.services : k => v.name }
}

output "alb_dns_name" {
  description = "DNS público do ALB — use para testar os endpoints"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  value = aws_lb.main.arn
}

output "target_group_arns" {
  description = "ARNs dos Target Groups por serviço"
  value       = { for k, v in aws_lb_target_group.services : k => v.arn }
}
