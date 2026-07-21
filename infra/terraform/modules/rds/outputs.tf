output "instance_id" { value = aws_db_instance.postgres.identifier }

output "endpoint" {
  value = aws_db_instance.postgres.address
}

output "port" {
  value = aws_db_instance.postgres.port
}

output "db_name" {
  value = aws_db_instance.postgres.db_name
}

output "username" {
  value = aws_db_instance.postgres.username
}

output "password" {
  value     = aws_db_instance.postgres.password
  sensitive = true
}
