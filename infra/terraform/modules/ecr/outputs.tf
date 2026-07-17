output "repository_urls" {
  description = "URLs dos repositórios ECR por serviço"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}
output "repository_arns" {
  value = { for k, v in aws_ecr_repository.services : k => v.arn }
}
