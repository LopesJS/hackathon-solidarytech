output "gke_cluster_name"      { value = google_container_cluster.main.name }
output "artifact_registry_url" { value = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/solidarytech" }
output "postgres_connection"   { value = google_sql_database_instance.postgres.connection_name }
