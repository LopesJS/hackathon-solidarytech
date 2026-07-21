# =============================================================================
# MODULE: ecr
# Repositórios ECR para os três microsserviços SolidaryTech.
# Inclui lifecycle policy para manter apenas as últimas N imagens.
# =============================================================================

terraform {
  required_providers {
    aws = { source = "hashicorp/aws"
    version = "~> 5.0" }
  }
}

locals {
  services = ["ngo-service", "donation-service", "volunteer-service"]
}

resource "aws_ecr_repository" "services" {
  for_each             = toset(local.services)
  name                 = "${var.project}/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true   # Trivy/ECR scan automático
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = "${var.project}/${each.key}"
    Service = each.key
    Layer   = "registry"
  })
}

# Manter apenas as últimas 10 imagens por repositório (FinOps)
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter ultimas ${var.max_images} imagens tagged"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType   = "imageCountMoreThan"
          countNumber = var.max_images
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remover imagens untagged com mais de 7 dias"
        selection = {
          tagStatus = "untagged"
          countType = "sinceImagePushed"
          countUnit = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
