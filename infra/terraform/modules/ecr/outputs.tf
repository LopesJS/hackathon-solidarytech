output "repository_urls" {
  description = "URLs completas dos repositórios ECR por serviço"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

output "repository_arns" {
  value = { for k, v in aws_ecr_repository.services : k => v.arn }
}

output "registry_base" {
  description = "Hostname do registry (account.dkr.ecr.region.amazonaws.com) — use no módulo ECS"
  value       = length(aws_ecr_repository.services) > 0 ? split("/", values(aws_ecr_repository.services)[0].repository_url)[0] : ""
}
