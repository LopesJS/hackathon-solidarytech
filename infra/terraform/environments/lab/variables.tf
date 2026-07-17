variable "aws_region" {
  description = "AWS region for the lab environment"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "solidarytech"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "lab"
}

variable "owner" {
  description = "Team owner of these resources"
  type        = string
  default     = "devops"
}

variable "image_tag" {
  description = "Docker image tag to deploy (use git SHA in CI/CD)"
  type        = string
  default     = "latest"
}
