output "vpc_id" {
  description = "ID da VPC do lab"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = module.networking.private_subnet_ids
}

output "ecs_cluster_name" {
  description = "Nome do cluster ECS"
  value       = module.ecs.cluster_name
}

output "alb_dns_name" {
  description = "DNS do ALB — endpoint público dos microsserviços"
  value       = module.ecs.alb_dns_name
}

output "rds_endpoint" {
  description = "Endpoint do PostgreSQL"
  value       = module.rds.endpoint
  sensitive   = true
}

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR"
  value       = module.ecr.repository_urls
}

output "donations_queue_url" {
  description = "URL da fila SQS de doações"
  value       = module.sqs.donations_queue_url
}

output "dlq_url" {
  description = "URL da Dead Letter Queue"
  value       = module.sqs.dlq_url
}

output "volunteer_table_name" {
  description = "Nome da tabela DynamoDB de voluntários"
  value       = module.dynamodb.volunteer_matches_table_name
}

output "donation_events_table_name" {
  description = "Nome da tabela DynamoDB de eventos de doações"
  value       = module.dynamodb.donation_events_table_name
}
