# =============================================================================
# ENVIRONMENT: gcp
# GKE (Google Kubernetes Engine) — terceira nuvem para multicloud estratégico.
# Usado para workloads de analytics e volunteer-service em cenário multicloud.
# =============================================================================

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "solidarytech-tfstate-gcp"
    prefix = "gcp/terraform"
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

locals {
  common_labels = {
    project     = "solidarytech"
    environment = "gcp-dr"
    managed_by  = "terraform"
    phase       = "hackathon-phase5"
  }
}

# ─── VPC ──────────────────────────────────────────────────────────────────────
resource "google_compute_network" "main" {
  name                    = "solidarytech-gcp-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "gke" {
  name          = "solidarytech-gke-subnet"
  ip_cidr_range = "10.30.0.0/24"
  region        = var.gcp_region
  network       = google_compute_network.main.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.31.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.32.0.0/20"
  }
}

# ─── GKE Autopilot (sem gerenciar nós — custo por pod) ───────────────────────
resource "google_container_cluster" "main" {
  name     = "solidarytech-gcp-gke"
  location = var.gcp_region

  enable_autopilot = true   # Autopilot: sem nodes para gerenciar

  network    = google_compute_network.main.name
  subnetwork = google_compute_subnetwork.gke.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  resource_labels = local.common_labels
}

# ─── Artifact Registry ────────────────────────────────────────────────────────
resource "google_artifact_registry_repository" "main" {
  location      = var.gcp_region
  repository_id = "solidarytech"
  format        = "DOCKER"
  description   = "Docker images para SolidaryTech no GCP"
  labels        = local.common_labels
}

# ─── Cloud SQL (PostgreSQL) ───────────────────────────────────────────────────
resource "google_sql_database_instance" "postgres" {
  name             = "solidarytech-gcp-postgres"
  database_version = "POSTGRES_16"
  region           = var.gcp_region
  deletion_protection = false

  settings {
    tier = "db-f1-micro"   # Menor instância para DR

    backup_configuration {
      enabled            = true
      point_in_time_recovery_enabled = true
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }

    user_labels = local.common_labels
  }
}
