# ─── SECRET: DATABASE_URL ngo-service ────────────────────────────────────────
resource "aws_secretsmanager_secret" "ngo_db_url" {
  name                    = "${var.project}/${var.environment}/ngo-service/database-url"
  description             = "PostgreSQL connection string for ngo-service"
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, { Service = "ngo-service" })
}

resource "aws_secretsmanager_secret_version" "ngo_db_url" {
  secret_id     = aws_secretsmanager_secret.ngo_db_url.id
  secret_string = var.ngo_database_url
}

# ─── SECRET: DATABASE_URL donation-service ───────────────────────────────────
resource "aws_secretsmanager_secret" "donation_db_url" {
  name                    = "${var.project}/${var.environment}/donation-service/database-url"
  description             = "PostgreSQL connection string for donation-service"
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, { Service = "donation-service" })
}

resource "aws_secretsmanager_secret_version" "donation_db_url" {
  secret_id     = aws_secretsmanager_secret.donation_db_url.id
  secret_string = var.donation_database_url
}

# ─── SECRET: RDS Master Password ─────────────────────────────────────────────
resource "aws_secretsmanager_secret" "rds_password" {
  name                    = "${var.project}/${var.environment}/rds/master-password"
  description             = "RDS master password"
  recovery_window_in_days = var.recovery_window_days

  tags = merge(var.tags, { Service = "rds" })
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id     = aws_secretsmanager_secret.rds_password.id
  secret_string = var.rds_password
}
