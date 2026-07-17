output "cluster_name"        { value = module.eks.cluster_name }
output "cluster_endpoint"    { value = module.eks.cluster_endpoint }
output "rds_endpoint"        { value = module.rds.endpoint }
output "ecr_urls"            { value = module.ecr.repository_urls }
output "donations_queue_url" { value = module.sqs.donations_queue_url }
output "velero_bucket"       { value = aws_s3_bucket.velero.bucket }
output "oidc_provider_arn"   { value = module.eks.oidc_provider_arn }
