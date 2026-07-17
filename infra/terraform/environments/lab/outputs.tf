output "alb_dns_name" {
  description = "URL do Application Load Balancer — use para testar os endpoints"
  value       = module.ecs.alb_dns_name
}

output "ecr_urls" {
  description = "URLs dos repositórios ECR para push das imagens"
  value       = module.ecr.repository_urls
}

output "rds_endpoint" {
  description = "Endpoint do RDS PostgreSQL"
  value       = module.rds.endpoint
  sensitive   = true
}

output "sqs_queue_url" {
  description = "URL da fila SQS"
  value       = module.sqs.queue_url
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB"
  value       = module.dynamodb.table_name
}

output "ecs_cluster_name" {
  description = "Nome do cluster ECS"
  value       = module.ecs.cluster_name
}
