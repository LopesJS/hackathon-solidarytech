output "ngo_db_url_arn" {
  value = aws_secretsmanager_secret.ngo_db_url.arn
}

output "donation_db_url_arn" {
  value = aws_secretsmanager_secret.donation_db_url.arn
}

output "rds_password_arn" {
  value = aws_secretsmanager_secret.rds_password.arn
}
