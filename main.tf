terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "6.7.0"
    }
  }
}

variable "project_id" { type = string }
variable "region" { type = string }

variable "keywords" {
  type    = string
  default = ""
}
variable "keywords_list" {
  type = list(string)
  default = [
    # Cloud / DevOps / Platform
    "kubernetes",
    "k8s",
    "docker",
    "container",
    "helm",
    "terraform",
    "infrastructure as code",
    "iac",
    "ansible",
    "ci/cd",
    "pipeline",
    "github actions",
    "jenkins",
    "gitlab ci",
    "gitops",
    "argo cd",
    "flux",
    "sre",
    "reliability",
    "incident",
    "on-call",
    "runbook",
    "observability",
    "monitoring",
    "logging",
    "prometheus",
    "grafana",
    "elk",
    "opentelemetry",
    "vpc",
    "networking",
    "load balancer",
    "reverse proxy",
    "nat",
    "firewall",

    # Backend / APIs / Distributed Systems
    "backend",
    "api",
    "rest",
    "graphql",
    "microservices",
    "distributed systems",
    "event-driven",
    "message queue",
    "kafka",
    "pubsub",
    "rabbitmq",
    "authentication",
    "authorization",
    "oauth",
    "oidc",
    "jwt",
    "caching",
    "redis",

    # Languages / Frameworks / Testing
    "python",
    "java",
    "javascript",
    "typescript",
    "sql",
    "spring boot",
    "django",
    "flask",
    "node.js",
    "react",
    "unit testing",
    "junit",
    "pytest",

    # Data / ML / MLOps
    "bigquery",
    "data pipeline",
    "etl",
    "elt",
    "airflow",
    "dag",
    "dbt",
    "spark",
    "databricks",
    "machine learning",
    "ml",
    "tensorflow",
    "pytorch",
    "feature engineering",
    "model deployment",
    "mlops",

    # Security / Compliance (especially useful for USAJOBS)
    "iam",
    "least privilege",
    "secrets manager",
    "key management",
    "kms",
    "devsecops",
    "security scanning",
    "vuln",
    "sbom",
    "nist",
    "fedramp",
    "fisma",
    "zero trust"
  ]
}

variable "storage_bucket_name" { type = string }
variable "workflow_name" { type = string }
variable "bq_load_job_id" { type = string }
variable "bq_query_job_id" { type = string }
variable "bq_dataset_id" { type = string }

variable "bq_raw_tables" {
  description = "Map of BigQuery tables to create"
  type = map(object({
    deletion_protection = optional(bool, true)
    schema_path         = optional(string)
    clustering          = optional(list(string), [])
    time_partitioning = optional(object({
      type          = string
      field         = optional(string)
      expiration_ms = optional(number)
    }))
  }))
}
variable "bq_transformed_tables" {
  description = "Map of BigQuery tables to create"
  type = map(object({
    deletion_protection = optional(bool, true)
    schema_path         = optional(string)
    clustering          = optional(list(string), [])
    time_partitioning = optional(object({
      type          = string
      field         = optional(string)
      expiration_ms = optional(number)
    }))
  }))
}

variable "common_labels" {
  type    = map(string)
  default = {}
}

variable "db_user" { type = string }
variable "db_name" { type = string }

variable "adzuna_country" { type = string }



variable "app_service_image" { type = string }
variable "app_service_name" { type = string }

variable "scraper_job_name" { type = string }
variable "scraper_image" { type = string }

variable "loader_job_name" { type = string }
variable "loader_image" { type = string }

variable "enable_cloudsql" {
  type    = bool
  default = true
}

variable "github_owner" { type = string }
variable "github_repo" { type = string }

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {}

locals {
  sa_scraper             = "serviceAccount:sa-scraper-runjob@${var.project_id}.iam.gserviceaccount.com"
  sa_loader              = "serviceAccount:sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
  sa_scraper_email       = "sa-scraper-runjob@${var.project_id}.iam.gserviceaccount.com"
  sa_loader_email        = "sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
  sa_scheduler           = "serviceAccount:sa-scheduler@${var.project_id}.iam.gserviceaccount.com"
  sa_manager             = "serviceAccount:sa-manager-infra@${var.project_id}.iam.gserviceaccount.com"
  sa_secret_manager      = "serviceAccount:sa-secret-manager@${var.project_id}.iam.gserviceaccount.com"
  sa_event_trigger       = "serviceAccount:sa-event-trigger@${var.project_id}.iam.gserviceaccount.com"
  sa_workflow            = "serviceAccount:sa-data-workflow@${var.project_id}.iam.gserviceaccount.com"
  sa_app_account         = "serviceAccount:sa-app-account@${var.project_id}.iam.gserviceaccount.com"
  sa_app_deployer        = "serviceAccount:sa-app-deployer@${var.project_id}.iam.gserviceaccount.com"
  sa_workflow_email      = "sa-data-workflow@${var.project_id}.iam.gserviceaccount.com"
  sa_event_trigger_email = "sa-event-trigger@${var.project_id}.iam.gserviceaccount.com"
  sa_app_account_email   = "sa-app-account@${var.project_id}.iam.gserviceaccount.com"
  sa_app_deployer_email  = "sa-app-deployer@${var.project_id}.iam.gserviceaccount.com"
  sa_scheduler_email     = "sa-scheduler@${var.project_id}.iam.gserviceaccount.com"
  sa_cloudbuild          = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

locals {
  non_secret_bq_env = {
    BQ_PROJECT_ID = var.project_id
    BQ_DATASET_ID = var.bq_dataset_id
  }
}

locals {
  project_roles_by_member = {
    (local.sa_scraper) = [
      "roles/vpcaccess.user",
      "roles/logging.logWriter"
    ]

    (local.sa_loader) = concat(
      [
        "roles/vpcaccess.user",
        "roles/logging.logWriter",
        "roles/bigquery.jobUser"
      ],
      var.enable_cloudsql ? ["roles/cloudsql.client"] : []
    )

    (local.sa_manager) = concat(
      [
        "roles/compute.networkAdmin",
        "roles/run.admin",
        "roles/bigquery.dataOwner",
        "roles/storage.admin",
        "roles/workflows.admin",
      ],
      var.enable_cloudsql ? ["roles/cloudsql.editor"] : []
    )

    (local.sa_secret_manager) = [
      "roles/secretmanager.secretAccessor",
      "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    ]

    (local.sa_event_trigger) = [
      "roles/eventarc.eventReceiver",
      "roles/workflows.invoker",
      "roles/pubsub.publisher"
    ]

    (local.sa_workflow) = [
      "roles/logging.logWriter",
      "roles/bigquery.jobUser",
      "roles/bigquery.dataEditor",
      "roles/run.viewer"
    ]

    (local.sa_app_account) = concat(
      [
        "roles/logging.logWriter",
      ],
      var.enable_cloudsql ? ["roles/vpcaccess.user", "roles/cloudsql.client"] : []
    )

    (local.sa_app_deployer) = [
      "roles/cloudbuild.editor"
    ]

    (local.sa_cloudbuild) = [
      "roles/artifactregistry.writer",
      "roles/run.developer",
      "roles/logging.logWriter",
    ]
  }

  project_iam_bindings = flatten([
    for member, roles in local.project_roles_by_member : [
      for r in roles : {
        member = member
        role   = r
      }
    ]
  ])
}

# Project-level bindings
resource "google_project_iam_member" "project_bindings" {
  for_each = {
    for b in local.project_iam_bindings :
    "${b.member}-${b.role}" => b
  }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  depends_on = [google_project_service.cloudresourcemanager]
}

# Enable deployer agent to access the application agent
resource "google_service_account_iam_member" "deployer_access_application_agent" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.sa_app_account_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa_app_deployer

  depends_on = [google_project_service.iam]
}

resource "google_service_account_iam_member" "cloudbuild_access_application_agent" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.sa_app_account_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa_cloudbuild

  depends_on = [google_project_service.iam]
}

resource "google_service_account_iam_member" "cloudbuild_access_scraper_agent" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.sa_scraper_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa_cloudbuild

  depends_on = [google_project_service.iam]
}

resource "google_service_account_iam_member" "cloudbuild_access_loader_agent" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.sa_loader_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa_cloudbuild

  depends_on = [google_project_service.iam]
}

# Enable the Secret Manager API. GCP creates the service agent when this is enabled.
resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudkms" {
  project            = var.project_id
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {
  project            = var.project_id
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "logging" {
  project            = var.project_id
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

# Configure KMS keyring.
resource "google_kms_key_ring" "secrets" {
  name       = "nazimz-keyring"
  location   = "global"
  depends_on = [google_project_service.cloudkms]
}

# Configure the key for securing credentials.
resource "google_kms_crypto_key" "secrets" {
  name            = "nazimz-key"
  key_ring        = google_kms_key_ring.secrets.id
  rotation_period = "7776000s"
}

# Provision the Secret Manager service agent (the Google-managed SA that GCP
# creates automatically when the API is enabled). Using google_project_service_identity
# ensures the agent exists in state and exposes its email as a reference - safer
# than hard-coding the service-PROJECT_NUMBER@gcp-sa-secretmanager pattern.
resource "google_project_service_identity" "secretmanager_agent" {
  provider   = google-beta
  project    = var.project_id
  service    = "secretmanager.googleapis.com"
  depends_on = [google_project_service.secretmanager]
}

# Grant the Secret Manager service agent encrypt/decrypt rights on our CMEK key.
# All google_secret_manager_secret resources must depend on this binding so that
# GCP can wrap the DEK when a secret is first written.
resource "google_kms_crypto_key_iam_member" "secretmanager_cmek" {
  crypto_key_id = google_kms_crypto_key.secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-secretmanager.iam.gserviceaccount.com"
}

# Configure secret for API Key for BLS
resource "google_secret_manager_secret" "bls_api_key" {
  project   = var.project_id
  secret_id = "BLS_API_KEY"
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    }
  }
  depends_on = [google_kms_crypto_key_iam_member.secretmanager_cmek]
}

# Configure secret for user credentials for USAjobs
resource "google_secret_manager_secret" "usajobs_user_email" {
  project   = var.project_id
  secret_id = "USAJOBS_EMAIL"
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    }
  }
  depends_on = [google_kms_crypto_key_iam_member.secretmanager_cmek]
}

# Configure secret for API Key received from USAJobs
resource "google_secret_manager_secret" "usajobs_api_key" {
  project   = var.project_id
  secret_id = "USAJOBS_API_KEY"
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    }
  }
  depends_on = [google_kms_crypto_key_iam_member.secretmanager_cmek]
}

# Configure secret for App ID received from Adzuna
resource "google_secret_manager_secret" "adzuna_app_id" {
  project   = var.project_id
  secret_id = "ADZUNA_APP_ID"
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    }
  }
  depends_on = [google_kms_crypto_key_iam_member.secretmanager_cmek]
}

# Configure secret for API Key received from Adzuna
resource "google_secret_manager_secret" "adzuna_api_key" {
  project   = var.project_id
  secret_id = "ADZUNA_API_KEY"
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    }
  }
  depends_on = [google_kms_crypto_key_iam_member.secretmanager_cmek]
}

# Configure secret for bigquery password.
resource "google_secret_manager_secret" "db_master_pwd" {
  project   = var.project_id
  secret_id = "DB_MASTER_PWD"
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    }
  }
  depends_on = [google_kms_crypto_key_iam_member.secretmanager_cmek]
}

# Configure secret for sql database password.
resource "google_secret_manager_secret" "db_private_pwd" {
  project   = var.project_id
  secret_id = "DB_PASSWORD"
  replication {
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    }
  }
  depends_on = [google_kms_crypto_key_iam_member.secretmanager_cmek]
}

# Role for scraper to write data to our cloud storage bucket.
resource "google_storage_bucket_iam_member" "scraper_bucket_writer" {
  bucket = google_storage_bucket.ingestion_bucket.name
  role   = "roles/storage.objectCreator"
  member = local.sa_scraper
}

# Enable access to usajobs user email
resource "google_secret_manager_secret_iam_member" "scraper_bls_key_accessor" {
  secret_id = google_secret_manager_secret.bls_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_scraper
}

# Enable access to usajobs user email
resource "google_secret_manager_secret_iam_member" "scraper_usajobs_email_accessor" {
  secret_id = google_secret_manager_secret.usajobs_user_email.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_scraper
}

# Enable access to usajobs api key
resource "google_secret_manager_secret_iam_member" "scraper_usajobs_key_accessor" {
  secret_id = google_secret_manager_secret.usajobs_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_scraper
}

# Enable access to adzuna app id
resource "google_secret_manager_secret_iam_member" "scraper_adzuna_app_accessor" {
  secret_id = google_secret_manager_secret.adzuna_app_id.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_scraper
}

# Enable access to adzuna api key
resource "google_secret_manager_secret_iam_member" "scraper_adzuna_api_accessor" {
  secret_id = google_secret_manager_secret.adzuna_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_scraper
}

# Enable loader agent to read data from our big query dataset.
resource "google_bigquery_dataset_iam_member" "loader_dataset_viewer" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.employment_analytics.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = local.sa_loader
}

# Enable workflow agent to run loader job after data transformation.
resource "google_cloud_run_v2_job_iam_member" "workflow_invokes_loader" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.loader_job.name
  role     = "roles/run.invoker"
  member   = local.sa_workflow
}

# Enable loader access to the Cloud SQL user password.
resource "google_secret_manager_secret_iam_member" "bigquery_accessor" {
  secret_id = google_secret_manager_secret.db_private_pwd.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_loader
}

# Enable Streamlit access to the Cloud SQL user password.
resource "google_secret_manager_secret_iam_member" "app_db_password_accessor" {
  secret_id = google_secret_manager_secret.db_private_pwd.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_app_account
}

# Role for scheduler can invoke only our scraper job.
resource "google_cloud_run_v2_job_iam_member" "scheduler_invokes_scraper" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.scraper_job.name
  role     = "roles/run.invoker"
  member   = local.sa_scheduler
}

# Enable Cloud Scheduler API
resource "google_project_service" "cloudscheduler" {
  project            = var.project_id
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

# Monthly trigger: fires on the 1st of every month at 06:00 ET
resource "google_cloud_scheduler_job" "monthly_scraper_trigger" {
  name             = "monthly-scraper-trigger"
  region           = var.region
  description      = "Invokes the scraper Cloud Run job on the 1st of every month at 06:00 ET"
  schedule         = "0 6 1 * *"
  time_zone        = "America/New_York"
  attempt_deadline = "320s"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${var.scraper_job_name}:run"
    oauth_token {
      service_account_email = local.sa_scheduler_email
    }
  }

  depends_on = [
    google_project_service.cloudscheduler,
    google_cloud_run_v2_job_iam_member.scheduler_invokes_scraper
  ]
}

# Enable Compute Engine API for VPC, firewall, Cloud NAT, and private service access resources.
resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}
# Creating the VPC network to host our public and private subnets.
resource "google_compute_network" "vpc_network" {
  name                    = "nazimz-db-network"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.compute]
}

# Create the private subnet within our VPC.
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "private-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc_network.self_link
  ip_cidr_range            = "10.0.0.0/24"
  private_ip_google_access = true
}

# Create the connector subnet within our VPC.
resource "google_compute_subnetwork" "connector_subnet" {
  name          = "connector-subnet"
  region        = var.region
  network       = google_compute_network.vpc_network.self_link
  ip_cidr_range = "10.0.1.0/28"
}

# Create the VPC connector to connect our Cloud Run jobs to our VPC.
resource "google_vpc_access_connector" "connector" {
  name           = "nazimz-connector"
  region         = var.region
  min_throughput = 200
  max_throughput = 300

  subnet {
    name       = google_compute_subnetwork.connector_subnet.name
    project_id = var.project_id
  }

  depends_on = [google_project_service.vpcaccess]
}

# Create the Cloud Router for our Cloud NAT
resource "google_compute_router" "router" {
  name    = "router-nat"
  region  = var.region
  network = google_compute_network.vpc_network.self_link
}

# Configure the Cloud NAT gateway
resource "google_compute_router_nat" "nat_gateway" {
  name   = "nat-config"
  router = google_compute_router.router.name
  region = google_compute_router.router.region

  # Automatically allocate external IP addresses
  nat_ip_allocate_option = "AUTO_ONLY"

  # CRITICAL FIX: Apply NAT to all subnets in the VPC
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Enable connection from our VPC network to Google's service network that has Cloud SQL.
resource "google_project_service" "service_networking" {
  project            = var.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_global_address" "private_service_range" {
  name          = "private-service-access-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
  depends_on              = [google_project_service.service_networking]
}

# The DB_PASSWORD secret value is intentionally managed outside Terraform so it
# does not land in Terraform state. A latest version must exist before apply.
data "google_secret_manager_secret_version_access" "db_password" {
  project = var.project_id
  secret  = google_secret_manager_secret.db_private_pwd.secret_id
  version = "latest"
}


# Create user for the SQL database
resource "google_sql_user" "users" {
  name     = var.db_user
  instance = google_sql_database_instance.private_db_instance.name
  password = data.google_secret_manager_secret_version_access.db_password.secret_data
}


# CRITICAL: Removed the deny-all-egress firewall rule as it prevents Cloud SQL from functioning
# Cloud SQL requires egress connectivity for replication, backups, and Google API access
# Instead, rely on VPC design and Cloud SQL being private-only (no public IP)

# Configure the private database to host our cloud sql instance.
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.private_db_instance.name
}

# Configure the private cloud sql database within the private subnet.
resource "google_sql_database_instance" "private_db_instance" {
  name             = "nazimz-private-sql-instance"
  database_version = "MYSQL_8_0"
  region           = var.region
  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.self_link
    }
  }
  deletion_protection = true
  depends_on          = [google_service_networking_connection.private_vpc_connection, google_project_service.cloudsql]
}

# Configure the service to host the streamlit application.
resource "google_cloud_run_v2_service" "streamlit-app" {
  name                = var.app_service_name
  location            = var.region
  deletion_protection = false

  template {
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    service_account       = local.sa_app_account_email

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    scaling {
      min_instance_count = 1
    }

    containers {
      image = var.app_service_image

      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.private_db_instance.private_ip_address
      }
      env {
        name  = "DB_NAME"
        value = var.db_name
      }
      env {
        name  = "DB_USER"
        value = var.db_user
      }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_private_pwd.secret_id
            version = "latest"
          }
        }
      }
      ports {
        container_port = 8080
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }
      startup_probe {
        http_get {
          path = "/_stcore/health"
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  depends_on = [
    google_project_service.run,
    google_secret_manager_secret_iam_member.app_db_password_accessor,
    google_vpc_access_connector.connector,
    google_sql_database.database
  ]
}

# Enable all Users public access to streamlit app.
resource "google_cloud_run_v2_service_iam_member" "streamlit_public_access" {
  project  = var.project_id
  location = var.region
  name     = var.app_service_name
  member   = "allUsers"
  role     = "roles/run.invoker"

  depends_on = [google_cloud_run_v2_service.streamlit-app]
}

# Enable Artifact Registry API
resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud Build API
resource "google_project_service" "cloudbuild" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudsql" {
  project            = var.project_id
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "vpcaccess" {
  project            = var.project_id
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "workflows" {
  project            = var.project_id
  service            = "workflows.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "bigquery" {
  project            = var.project_id
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}
resource "google_project_service" "pubsub" {
  project            = var.project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

# Create Artifact Registry for docker image for scraper job
resource "google_artifact_registry_repository" "scraper_repo" {
  location      = var.region
  repository_id = "scraper-docker-img"
  description   = "Docker image repository for scraper Cloud Run job."
  format        = "DOCKER"
  depends_on    = [google_project_service.artifactregistry]
}

# Create Artifact Registry for docker image for loader job
resource "google_artifact_registry_repository" "loader_repo" {
  location      = var.region
  repository_id = "loader-docker-img"
  description   = "Docker image repository for loader Cloud Run job."
  format        = "DOCKER"
  depends_on    = [google_project_service.artifactregistry]
}

# Create Artifact Registry for docker image to host streamlit app
resource "google_artifact_registry_repository" "streamlit_repo" {
  location      = var.region
  repository_id = "streamlit-docker-img"
  description   = "Docker image repository for streamlit app."
  format        = "DOCKER"

  # Keep tags mutable so :latest can move to the newest Streamlit build.
  docker_config {
    immutable_tags = false
  }

  depends_on = [google_project_service.artifactregistry]
}

# Enable deployer agent to write docker image to streamlit repo
resource "google_artifact_registry_repository_iam_member" "viewer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.streamlit_repo.name
  role       = "roles/artifactregistry.writer"
  member     = local.sa_app_deployer
}

# Enable deployer agent to write docker image to scraper repo
resource "google_artifact_registry_repository_iam_member" "scraper_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.scraper_repo.name
  role       = "roles/artifactregistry.writer"
  member     = local.sa_app_deployer
}

# Enable deployer agent to write docker image to loader repo
resource "google_artifact_registry_repository_iam_member" "loader_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.loader_repo.name
  role       = "roles/artifactregistry.writer"
  member     = local.sa_app_deployer
}

# Enable deployer agent to run the Cloud Run service for streamlit app
resource "google_cloud_run_v2_service_iam_member" "deployer_runs_service" {
  project  = var.project_id
  location = var.region
  name     = var.app_service_name
  role     = "roles/run.developer"
  member   = local.sa_app_deployer
}

# Configure firewall rule that only accepts inbound traffic from connector subnet.
resource "google_compute_firewall" "enable_traffic_to_db" {
  name      = "enable-traffic-to-db"
  network   = google_compute_network.vpc_network.self_link
  direction = "INGRESS"
  priority  = 1000

  source_ranges = [google_compute_subnetwork.connector_subnet.ip_cidr_range]

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }
}

# Configure the Cloud Run job to scrape data from the Internet.
resource "google_cloud_run_v2_job" "scraper_job" {
  name                = var.scraper_job_name
  location            = var.region
  deletion_protection = false
  template {
    task_count = 1
    template {
      service_account = "sa-scraper-runjob@${var.project_id}.iam.gserviceaccount.com"
      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress    = "ALL_TRAFFIC"
      }
      containers {
        image = var.scraper_image

        dynamic "env" {
          for_each = local.non_secret_bq_env
          content {
            name  = env.key
            value = env.value
          }
        }

        # Secret credentials 
        env {
          name = "BLS_API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.bls_api_key.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "USAJOBS_API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.usajobs_api_key.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "ADZUNA_APP_ID"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.adzuna_app_id.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "ADZUNA_APP_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.adzuna_api_key.secret_id
              version = "latest"
            }
          }
        }
        env {
          name = "USAJOBS_USER_EMAIL"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.usajobs_user_email.secret_id
              version = "latest"
            }
          }
        }

        env {
          name  = "INGESTION_BUCKET"
          value = google_storage_bucket.ingestion_bucket.name
        }
        env {
          name  = "ADZUNA_COUNTRY"
          value = var.adzuna_country
        }
        env {
          name  = "KEYWORDS"
          value = join(",", var.keywords_list)
        }
        volume_mounts {
          name       = "gcs-volume"
          mount_path = "/gcs"
        }
      }
      volumes {
        name = "gcs-volume"
        gcs {
          bucket    = google_storage_bucket.ingestion_bucket.name
          read_only = false
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image]
  }

  depends_on = [
    google_project_service.run,
    google_storage_bucket_iam_member.scraper_bucket_writer,
    google_vpc_access_connector.connector
  ]
}

# Enable eventarc API.
resource "google_project_service" "eventarc" {
  project            = var.project_id
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
}

# Provision the Eventarc service agent so its email is available as a reference.
resource "google_project_service_identity" "eventarc_agent" {
  provider   = google-beta
  project    = var.project_id
  service    = "eventarc.googleapis.com"
  depends_on = [google_project_service.eventarc]
}

# Eventarc service agent needs storage.buckets.get to validate the bucket when
# creating a GCS-sourced trigger. roles/storage.legacyBucketReader covers this.
resource "google_storage_bucket_iam_member" "eventarc_bucket_reader" {
  bucket     = google_storage_bucket.ingestion_bucket.name
  role       = "roles/storage.legacyBucketReader"
  member     = "serviceAccount:${google_project_service_identity.eventarc_agent.email}"
  depends_on = [google_project_service_identity.eventarc_agent]
}
# Allow Cloud Storage direct events to publish through Eventarc Pub/Sub transport.
data "google_storage_project_service_account" "gcs_account" {
  project    = var.project_id
  depends_on = [google_project_service.storage]
}

resource "google_project_iam_member" "gcs_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"

  depends_on = [
    google_project_service.pubsub,
    google_project_service.storage
  ]
}

# Configure an Eventarc trigger for the Cloud Storage Bucket when data is added to the bucket.
resource "google_eventarc_trigger" "bucket_trigger" {
  name     = "gcs-bucket-trigger"
  location = var.region

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  # Ensure matching_criteria includes bucket name
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.ingestion_bucket.name
  }

  event_data_content_type = "application/json"
  service_account         = local.sa_event_trigger_email

  # Destination is a workflow that sends the trigger to our Cloud Storage Bucket
  destination {
    workflow = google_workflows_workflow.etl_workflow.id
  }
  depends_on = [
    google_project_service.eventarc,
    google_project_service.pubsub,
    google_project_iam_member.gcs_pubsub_publisher,
    google_storage_bucket_iam_member.event_bucket_retrieval,
    google_storage_bucket_iam_member.eventarc_bucket_reader,
    google_workflows_workflow.etl_workflow
  ]
}

# Enable EventArc to read and retrieve data from GCS Bucket
resource "google_storage_bucket_iam_member" "event_bucket_retrieval" {
  bucket = google_storage_bucket.ingestion_bucket.name
  role   = "roles/storage.objectViewer"
  member = local.sa_event_trigger
}

resource "google_workflows_workflow" "etl_workflow" {
  provider        = google-beta
  name            = var.workflow_name
  region          = var.region
  description     = "GCS -> BigQuery raw load -> BigQuery transform -> Cloud Run loader -> Cloud SQL"
  service_account = local.sa_workflow_email
  call_log_level  = "LOG_ERRORS_ONLY"

  user_env_vars = {
    PROJECT_ID       = var.project_id
    BQ_DATASET_ID    = var.bq_dataset_id
    BQ_LOCATION      = "US"
    INGESTION_BUCKET = google_storage_bucket.ingestion_bucket.name

    RAW_BLS_TABLE     = "raw_bls_observation"
    RAW_USAJOBS_TABLE = "raw_usajobs_posting"
    RAW_ADZUNA_TABLE  = "raw_adzuna_posting"

    LOADER_JOB_NAME   = var.loader_job_name
    LOADER_JOB_REGION = var.region
  }

  source_contents = <<-YAML
  main:
    params: [event]
    steps:
      - init:
          assign:
            - project_id: $${sys.get_env("PROJECT_ID")}
            - dataset_id: $${sys.get_env("BQ_DATASET_ID")}
            - bq_location: $${sys.get_env("BQ_LOCATION")}
            - expected_bucket: $${sys.get_env("INGESTION_BUCKET")}
            - loader_job_name: $${sys.get_env("LOADER_JOB_NAME")}
            - loader_job_region: $${sys.get_env("LOADER_JOB_REGION")}

            - bucket: $${event.data.bucket}
            - object_name: $${event.data.name}
            - source_uri: $${"gs://" + event.data.bucket + "/" + event.data.name}

      - validate_bucket:
          switch:
            - condition: $${bucket != expected_bucket}
              raise: '$${"Unexpected bucket received: " + bucket}'

      - route_file:
          switch:
            - condition: $${text.match_regex(object_name, "^raw/bls/.*\\.csv$")}
              next: set_bls_config
            - condition: $${text.match_regex(object_name, "^raw/usajobs/.*\\.json$")}
              next: set_usajobs_config
            - condition: $${text.match_regex(object_name, "^raw/adzuna/.*\\.json$")}
              next: set_adzuna_config
          next: unsupported_file

      - unsupported_file:
          raise: '$${"Unsupported object path: " + object_name}'

      - set_bls_config:
          assign:
            - raw_table: $${sys.get_env("RAW_BLS_TABLE")}
            - source_format: "CSV"
            - skip_leading_rows: 1
            - transform_sql: $${"CALL `" + project_id + "." + dataset_id + ".sp_transform_bls`();"}
          next: start_load_job

      - set_usajobs_config:
          assign:
            - raw_table: $${sys.get_env("RAW_USAJOBS_TABLE")}
            - source_format: "NEWLINE_DELIMITED_JSON"
            - skip_leading_rows: 0
            - transform_sql: $${"CALL `" + project_id + "." + dataset_id + ".sp_transform_usajobs`();"}
          next: start_load_job

      - set_adzuna_config:
          assign:
            - raw_table: $${sys.get_env("RAW_ADZUNA_TABLE")}
            - source_format: "NEWLINE_DELIMITED_JSON"
            - skip_leading_rows: 0
            - transform_sql: $${"CALL `" + project_id + "." + dataset_id + ".sp_transform_adzuna`();"}
          next: start_load_job

      - start_load_job:
          call: googleapis.bigquery.v2.jobs.insert
          args:
            projectId: $${project_id}
            body:
              jobReference:
                location: $${bq_location}
              configuration:
                load:
                  sourceUris:
                    - $${source_uri}
                  destinationTable:
                    projectId: $${project_id}
                    datasetId: $${dataset_id}
                    tableId: $${raw_table}
                  sourceFormat: $${source_format}
                  skipLeadingRows: $${skip_leading_rows}
                  writeDisposition: "WRITE_APPEND"
          result: load_job

      - poll_load_job:
          call: googleapis.bigquery.v2.jobs.get
          args:
            projectId: $${project_id}
            jobId: $${load_job.jobReference.jobId}
            location: $${bq_location}
          result: load_status

      - check_load_job:
          switch:
            - condition: $${load_status.status.state == "DONE" and not("errorResult" in load_status.status)}
              next: start_transform_job
            - condition: $${load_status.status.state == "DONE" and ("errorResult" in load_status.status)}
              raise: $${load_status.status.errorResult}
          next: wait_before_retry_load

      - wait_before_retry_load:
          call: sys.sleep
          args:
            seconds: 5
          next: poll_load_job

      - start_transform_job:
          call: googleapis.bigquery.v2.jobs.insert
          args:
            projectId: $${project_id}
            body:
              jobReference:
                location: $${bq_location}
              configuration:
                query:
                  useLegacySql: false
                  query: $${transform_sql}
          result: transform_job

      - poll_transform_job:
          call: googleapis.bigquery.v2.jobs.get
          args:
            projectId: $${project_id}
            jobId: $${transform_job.jobReference.jobId}
            location: $${bq_location}
          result: transform_status

      - check_transform_job:
          switch:
            - condition: $${transform_status.status.state == "DONE" and not("errorResult" in transform_status.status)}
              next: run_loader_job
            - condition: $${transform_status.status.state == "DONE" and ("errorResult" in transform_status.status)}
              raise: $${transform_status.status.errorResult}
          next: wait_before_retry_transform

      - wait_before_retry_transform:
          call: sys.sleep
          args:
            seconds: 5
          next: poll_transform_job

      - run_loader_job:
          call: googleapis.run.v2.projects.locations.jobs.run
          args:
            name: $${"projects/" + project_id + "/locations/" + loader_job_region + "/jobs/" + loader_job_name}
            body:
              overrides:
                containerOverrides:
                  - env:
                      - name: "BQ_DATASET_ID"
                        value: $${dataset_id}
                      - name: "TRIGGER_OBJECT"
                        value: $${object_name}
                      - name: "RAW_TABLE"
                        value: $${raw_table}
          result: loader_execution
          next: poll_loader_operation

      - poll_loader_operation:
          call: googleapis.run.v2.projects.locations.operations.get
          args:
            name: $${loader_execution.name}
          result: loader_status

      - check_loader_operation:
          switch:
            - condition: $${("done" in loader_status) and loader_status.done and not("error" in loader_status)}
              next: done
            - condition: $${("done" in loader_status) and loader_status.done and ("error" in loader_status)}
              raise: $${loader_status.error}
          next: wait_before_retry_loader

      - wait_before_retry_loader:
          call: sys.sleep
          args:
            seconds: 5
          next: poll_loader_operation

      - done:
          return:
            message: "ETL pipeline completed successfully"
            source_uri: $${source_uri}
            raw_table: $${raw_table}
            load_job_id: $${load_job.jobReference.jobId}
            transform_job_id: $${transform_job.jobReference.jobId}
            loader_execution_name: $${loader_execution.name}
  YAML

  depends_on = [
    google_project_service.workflows,
    google_storage_bucket.ingestion_bucket
  ]
}

# Enable workflow agent to retrieve data from Google Cloud Storage Bucket
resource "google_storage_bucket_iam_member" "workflow_bucket_reader" {
  bucket = google_storage_bucket.ingestion_bucket.name
  role   = "roles/storage.objectViewer"
  member = local.sa_workflow
}

# Enable workflow agent to read, write, and create datasets for the BigQuery dataset
resource "google_bigquery_dataset_iam_member" "workflow_dataset_user" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.employment_analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.sa_workflow
}

# Configure the cloud storage bucket for our scraper job to send the data to.
resource "google_storage_bucket" "ingestion_bucket" {
  name          = var.storage_bucket_name
  location      = var.region
  storage_class = "STANDARD"
  force_destroy = false
  versioning {
    enabled = true
  }

  depends_on = [google_project_service.storage]
}

# Configure the Cloud Run job to load data from bigquery to our private database.
resource "google_cloud_run_v2_job" "loader_job" {
  name                = var.loader_job_name
  location            = var.region
  deletion_protection = false
  template {
    task_count = 1
    template {
      service_account = "sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress    = "PRIVATE_RANGES_ONLY"
      }
      containers {
        image = var.loader_image
        env {
          name  = "BQ_PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "BQ_DATASET_ID"
          value = var.bq_dataset_id
        }
        env {
          name  = "DB_HOST"
          value = google_sql_database_instance.private_db_instance.private_ip_address
        }
        env {
          name  = "DB_NAME"
          value = var.db_name
        }
        env {
          name  = "DB_USER"
          value = var.db_user
        }
        env {
          name = "DB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_private_pwd.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image]
  }

  depends_on = [
    google_project_service.run,
    google_bigquery_dataset_iam_member.loader_dataset_viewer,
    google_secret_manager_secret_iam_member.bigquery_accessor,
    google_vpc_access_connector.connector,
    google_sql_database.database
  ]
}


# Configure our bigquery dataset for data transformation.
resource "google_bigquery_dataset" "employment_analytics" {
  dataset_id  = var.bq_dataset_id
  location    = "US"
  description = "Dataset used for loading into private database"
  labels = {
    env = "dev"
  }
  depends_on = [google_project_service.bigquery]
  access {
    role          = "READER"
    user_by_email = "sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
  }
  access {
    role          = "WRITER"
    user_by_email = "sa-data-workflow@${var.project_id}.iam.gserviceaccount.com"
  }
  access {
    role          = "OWNER"
    user_by_email = "sa-manager-infra@${var.project_id}.iam.gserviceaccount.com"
  }
}

resource "google_bigquery_table" "raw_tables" {
  for_each   = var.bq_raw_tables
  project    = var.project_id
  dataset_id = google_bigquery_dataset.employment_analytics.dataset_id
  table_id   = each.key

  deletion_protection = each.value.deletion_protection
  labels              = var.common_labels

  schema     = each.value.schema_path != null ? file(each.value.schema_path) : null
  clustering = length(each.value.clustering) > 0 ? each.value.clustering : null

  dynamic "time_partitioning" {
    for_each = each.value.time_partitioning != null ? [each.value.time_partitioning] : []
    content {
      type          = time_partitioning.value.type
      field         = try(time_partitioning.value.field, null)
      expiration_ms = try(time_partitioning.value.expiration_ms, null)
    }
  }
}
resource "google_bigquery_table" "transformed_tables" {
  for_each   = var.bq_transformed_tables
  project    = var.project_id
  dataset_id = google_bigquery_dataset.employment_analytics.dataset_id
  table_id   = each.key

  deletion_protection = each.value.deletion_protection
  labels              = var.common_labels

  schema     = each.value.schema_path != null ? file(each.value.schema_path) : null
  clustering = length(each.value.clustering) > 0 ? each.value.clustering : null

  dynamic "time_partitioning" {
    for_each = each.value.time_partitioning != null ? [each.value.time_partitioning] : []
    content {
      type          = time_partitioning.value.type
      field         = try(time_partitioning.value.field, null)
      expiration_ms = try(time_partitioning.value.expiration_ms, null)
    }
  }
}

# Stored procedures called by the Workflow transform step.
# Full transformation SQL to be developed alongside the Python backend.
resource "google_bigquery_routine" "sp_transform_bls" {
  dataset_id      = google_bigquery_dataset.employment_analytics.dataset_id
  routine_id      = "sp_transform_bls"
  routine_type    = "PROCEDURE"
  language        = "SQL"
  definition_body = <<-SQL
    BEGIN
      -- 1. Populate dim_source_system
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_source_system` T
      USING (SELECT 'bls' AS source_id, 'Bureau of Labor Statistics' AS source_name) S
      ON T.source_id = S.source_id
      WHEN NOT MATCHED THEN INSERT (source_id, source_name) VALUES (S.source_id, S.source_name);

      -- 2. Populate curated_labor_metric from series metadata
      MERGE `${var.project_id}.${var.bq_dataset_id}.curated_labor_metric` T
      USING (
        SELECT DISTINCT
          CASE WHEN source_series_key LIKE 'LN%' THEN 'unemployment_rate'
               WHEN source_series_key LIKE 'CES%' THEN 'nonfarm_employment'
               ELSE 'other' END AS metric_id,
          CASE WHEN source_series_key LIKE 'LN%' THEN 'Unemployment Rate'
               WHEN source_series_key LIKE 'CES%' THEN 'Nonfarm Employment Level'
               ELSE 'Other' END AS metric_name,
          CASE WHEN source_series_key LIKE 'LN%' THEN 'Percent'
               WHEN source_series_key LIKE 'CES%' THEN 'Thousands of Persons'
               ELSE NULL END AS unit_of_measure,
          CASE WHEN source_series_key LIKE 'LN%' THEN 'UNEMPLOYMENT_RATE'
               WHEN source_series_key LIKE 'CES%' THEN 'EMPLOYMENT_LEVEL'
               ELSE NULL END AS metric_category
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_bls_observation`
      ) S ON T.metric_id = S.metric_id
      WHEN NOT MATCHED THEN INSERT (metric_id, metric_name, unit_of_measure, metric_category)
        VALUES (S.metric_id, S.metric_name, S.unit_of_measure, S.metric_category);

      -- 3. Populate dim_time_period
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_time_period` T
      USING (
        SELECT DISTINCT
          CONCAT(CAST(observation_year AS STRING), '-', observation_period) AS time_id,
          DATE(observation_year, CAST(SUBSTR(observation_period, 2) AS INT64), 1) AS calendar_date,
          observation_year AS year,
          CAST(SUBSTR(observation_period, 2) AS INT64) AS month,
          'MONTH' AS period_type
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_bls_observation`
        WHERE observation_period LIKE 'M%'
      ) S ON T.time_id = S.time_id
      WHEN NOT MATCHED THEN
        INSERT (time_id, calendar_date, year, month, period_type)
        VALUES (S.time_id, S.calendar_date, S.year, S.month, S.period_type);

      -- 4. Populate curated_bls_series
      MERGE `${var.project_id}.${var.bq_dataset_id}.curated_bls_series` T
      USING (
        SELECT DISTINCT
          source_series_key AS bls_series_id,
          source_series_key,
          CASE WHEN source_series_key LIKE 'LN%' THEN 'unemployment_rate'
               WHEN source_series_key LIKE 'CES%' THEN 'nonfarm_employment'
               ELSE 'other' END AS metric_id,
          SUBSTR(source_series_key, 4, 2) AS supersector_code,
          CASE WHEN source_series_key LIKE 'LNS%' THEN TRUE ELSE FALSE END AS seasonal_adjustment_flag
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_bls_observation`
      ) S ON T.bls_series_id = S.bls_series_id
      WHEN NOT MATCHED THEN
        INSERT (bls_series_id, source_series_key, metric_id, supersector_code, seasonal_adjustment_flag)
        VALUES (S.bls_series_id, S.source_series_key, S.metric_id, S.supersector_code, S.seasonal_adjustment_flag);

      -- 5. Populate fact_labor_observation
      MERGE `${var.project_id}.${var.bq_dataset_id}.fact_labor_observation` T
      USING (
        SELECT
          GENERATE_UUID() AS labor_observation_id,
          r.source_series_key AS bls_series_id,
          CONCAT(CAST(r.observation_year AS STRING), '-', r.observation_period) AS time_id,
          'bls' AS source_id,
          CASE WHEN r.source_series_key LIKE 'LN%' THEN 'unemployment_rate'
               WHEN r.source_series_key LIKE 'CES%' THEN 'nonfarm_employment'
               ELSE 'other' END AS metric_id,
          r.observation_value,
          DATE(r.observation_year, CAST(SUBSTR(r.observation_period, 2) AS INT64), 1) AS observation_date
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_bls_observation` r
        WHERE r.observation_period LIKE 'M%'
      ) S ON T.bls_series_id = S.bls_series_id AND T.time_id = S.time_id
      WHEN NOT MATCHED THEN
        INSERT (labor_observation_id, bls_series_id, time_id, source_id, metric_id, observation_value, observation_date)
        VALUES (S.labor_observation_id, S.bls_series_id, S.time_id, S.source_id, S.metric_id, S.observation_value, S.observation_date);
    END
  SQL
  depends_on      = [google_bigquery_table.transformed_tables]
}

resource "google_bigquery_routine" "sp_transform_usajobs" {
  dataset_id      = google_bigquery_dataset.employment_analytics.dataset_id
  routine_id      = "sp_transform_usajobs"
  routine_type    = "PROCEDURE"
  language        = "SQL"
  definition_body = <<-SQL
    BEGIN
      -- 1. Populate dim_source_system
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_source_system` T
      USING (SELECT 'usajobs' AS source_id, 'USAJobs' AS source_name) S
      ON T.source_id = S.source_id
      WHEN NOT MATCHED THEN INSERT (source_id, source_name) VALUES (S.source_id, S.source_name);

      -- 2. Populate dim_employer from USAJobs raw_payload
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_employer` T
      USING (
        SELECT DISTINCT
          TO_HEX(MD5(JSON_VALUE(raw_payload, '$.OrganizationName'))) AS employer_id,
          JSON_VALUE(raw_payload, '$.OrganizationName') AS employer_name,
          'federal' AS employer_type
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_usajobs_posting`
        WHERE JSON_VALUE(raw_payload, '$.OrganizationName') IS NOT NULL
      ) S ON T.employer_id = S.employer_id
      WHEN NOT MATCHED THEN INSERT (employer_id, employer_name, employer_type)
        VALUES (S.employer_id, S.employer_name, S.employer_type);

      -- 3. Populate dim_location from USAJobs raw_payload
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_location` T
      USING (
        SELECT DISTINCT
          TO_HEX(MD5(JSON_VALUE(raw_payload, '$.PositionLocation[0].LocationName'))) AS location_id,
          JSON_VALUE(raw_payload, '$.PositionLocation[0].CountryCode') AS country_code,
          JSON_VALUE(raw_payload, '$.PositionLocation[0].CountrySubDivisionCode') AS state_code,
          JSON_VALUE(raw_payload, '$.PositionLocation[0].LocationName') AS city_name
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_usajobs_posting`
        WHERE JSON_VALUE(raw_payload, '$.PositionLocation[0].LocationName') IS NOT NULL
      ) S ON T.location_id = S.location_id
      WHEN NOT MATCHED THEN INSERT (location_id, country_code, state_code, city_name)
        VALUES (S.location_id, S.country_code, S.state_code, S.city_name);

      -- 4. Populate fact_job_posting from USAJobs raw_payload
      MERGE `${var.project_id}.${var.bq_dataset_id}.fact_job_posting` T
      USING (
        SELECT
          GENERATE_UUID() AS job_posting_id,
          source_id,
          source_posting_key,
          JSON_VALUE(raw_payload, '$.PositionURI') AS posting_url,
          JSON_VALUE(raw_payload, '$.PositionTitle') AS job_title,
          JSON_VALUE(raw_payload, '$.QualificationSummary') AS job_description,
          JSON_VALUE(raw_payload, '$.PositionSchedule[0].Name') AS work_schedule,
          TO_HEX(MD5(JSON_VALUE(raw_payload, '$.OrganizationName'))) AS employer_id,
          TO_HEX(MD5(JSON_VALUE(raw_payload, '$.PositionLocation[0].LocationName'))) AS location_id,
          SAFE_CAST(JSON_VALUE(raw_payload, '$.PositionRemuneration[0].MinimumRange') AS NUMERIC) AS salary_min,
          SAFE_CAST(JSON_VALUE(raw_payload, '$.PositionRemuneration[0].MaximumRange') AS NUMERIC) AS salary_max,
          JSON_VALUE(raw_payload, '$.PositionRemuneration[0].CurrencyCode') AS salary_currency,
          JSON_VALUE(raw_payload, '$.PositionRemuneration[0].RateIntervalCode') AS salary_interval,
          CASE
            WHEN JSON_VALUE(raw_payload, '$.UserArea.Details.SecurityClearance') IS NOT NULL
             AND JSON_VALUE(raw_payload, '$.UserArea.Details.SecurityClearance') NOT IN ('None', '0', 'Not Required')
            THEN TRUE ELSE FALSE
          END AS security_clearance_required,
          DATE(TIMESTAMP(JSON_VALUE(raw_payload, '$.PublicationStartDate'))) AS posted_date
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_usajobs_posting`
        WHERE source_posting_key IS NOT NULL
      ) S ON T.source_id = S.source_id AND T.source_posting_key = S.source_posting_key
      WHEN NOT MATCHED THEN
        INSERT (job_posting_id, source_id, source_posting_key, posting_url, job_title, job_description,
                work_schedule, employer_id, location_id, salary_min, salary_max, salary_currency,
                salary_interval, security_clearance_required, posted_date)
        VALUES (S.job_posting_id, S.source_id, S.source_posting_key, S.posting_url, S.job_title,
                S.job_description, S.work_schedule, S.employer_id, S.location_id, S.salary_min,
                S.salary_max, S.salary_currency, S.salary_interval, S.security_clearance_required,
                S.posted_date);
    END
  SQL
  depends_on      = [google_bigquery_table.transformed_tables]
}

resource "google_bigquery_routine" "sp_transform_adzuna" {
  dataset_id      = google_bigquery_dataset.employment_analytics.dataset_id
  routine_id      = "sp_transform_adzuna"
  routine_type    = "PROCEDURE"
  language        = "SQL"
  definition_body = <<-SQL
    BEGIN
      -- 1. Populate dim_source_system
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_source_system` T
      USING (SELECT 'adzuna' AS source_id, 'Adzuna' AS source_name) S
      ON T.source_id = S.source_id
      WHEN NOT MATCHED THEN INSERT (source_id, source_name) VALUES (S.source_id, S.source_name);

      -- 2. Populate dim_employer from Adzuna raw_payload
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_employer` T
      USING (
        SELECT DISTINCT
          TO_HEX(MD5(JSON_VALUE(raw_payload, '$.company.display_name'))) AS employer_id,
          JSON_VALUE(raw_payload, '$.company.display_name') AS employer_name
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_adzuna_posting`
        WHERE JSON_VALUE(raw_payload, '$.company.display_name') IS NOT NULL
      ) S ON T.employer_id = S.employer_id
      WHEN NOT MATCHED THEN INSERT (employer_id, employer_name)
        VALUES (S.employer_id, S.employer_name);

      -- 3. Populate dim_location from Adzuna raw_payload
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_location` T
      USING (
        SELECT DISTINCT
          TO_HEX(MD5(JSON_VALUE(raw_payload, '$.location.display_name'))) AS location_id,
          'US' AS country_code,
          CAST(NULL AS STRING) AS state_code,
          JSON_VALUE(raw_payload, '$.location.display_name') AS city_name
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_adzuna_posting`
        WHERE JSON_VALUE(raw_payload, '$.location.display_name') IS NOT NULL
      ) S ON T.location_id = S.location_id
      WHEN NOT MATCHED THEN INSERT (location_id, country_code, state_code, city_name)
        VALUES (S.location_id, S.country_code, S.state_code, S.city_name);

      -- 4. Populate fact_job_posting from Adzuna raw_payload
      MERGE `${var.project_id}.${var.bq_dataset_id}.fact_job_posting` T
      USING (
        SELECT
          GENERATE_UUID() AS job_posting_id,
          source_id,
          source_posting_key,
          JSON_VALUE(raw_payload, '$.redirect_url') AS posting_url,
          JSON_VALUE(raw_payload, '$.title') AS job_title,
          JSON_VALUE(raw_payload, '$.description') AS job_description,
          JSON_VALUE(raw_payload, '$.contract_time') AS work_schedule,
          TO_HEX(MD5(JSON_VALUE(raw_payload, '$.company.display_name'))) AS employer_id,
          TO_HEX(MD5(JSON_VALUE(raw_payload, '$.location.display_name'))) AS location_id,
          SAFE_CAST(JSON_VALUE(raw_payload, '$.salary_min') AS NUMERIC) AS salary_min,
          SAFE_CAST(JSON_VALUE(raw_payload, '$.salary_max') AS NUMERIC) AS salary_max,
          'USD' AS salary_currency,
          'year' AS salary_interval,
          FALSE AS security_clearance_required,
          DATE(TIMESTAMP(JSON_VALUE(raw_payload, '$.created'))) AS posted_date
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_adzuna_posting`
        WHERE source_posting_key IS NOT NULL
      ) S ON T.source_id = S.source_id AND T.source_posting_key = S.source_posting_key
      WHEN NOT MATCHED THEN
        INSERT (job_posting_id, source_id, source_posting_key, posting_url, job_title, job_description,
                work_schedule, employer_id, location_id, salary_min, salary_max, salary_currency,
                salary_interval, security_clearance_required, posted_date)
        VALUES (S.job_posting_id, S.source_id, S.source_posting_key, S.posting_url, S.job_title,
                S.job_description, S.work_schedule, S.employer_id, S.location_id, S.salary_min,
                S.salary_max, S.salary_currency, S.salary_interval, S.security_clearance_required,
                S.posted_date);
    END
  SQL
  depends_on      = [google_bigquery_table.transformed_tables]
}

# Cloud Build Triggers

resource "google_cloudbuild_trigger" "scraper_trigger" {
  name            = "scraper-build-deploy"
  location        = "global"
  project         = var.project_id
  service_account = "projects/${var.project_id}/serviceAccounts/${local.sa_app_deployer_email}"

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$"
    }
  }

  included_files = ["scraper/**"]
  filename       = "scraper/cloudbuild.yaml"

  depends_on = [
    google_project_service.cloudbuild,
    google_service_account_iam_member.cloudbuild_access_scraper_agent
  ]
}

resource "google_cloudbuild_trigger" "loader_trigger" {
  name            = "loader-build-deploy"
  location        = "global"
  project         = var.project_id
  service_account = "projects/${var.project_id}/serviceAccounts/${local.sa_app_deployer_email}"

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$"
    }
  }

  included_files = ["loader/**"]
  filename       = "loader/cloudbuild.yaml"

  depends_on = [
    google_project_service.cloudbuild,
    google_service_account_iam_member.cloudbuild_access_loader_agent
  ]
}

resource "google_cloudbuild_trigger" "streamlit_trigger" {
  name            = "streamlit-build-deploy"
  location        = "global"
  project         = var.project_id
  service_account = "projects/${var.project_id}/serviceAccounts/${local.sa_app_deployer_email}"

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = "^main$"
    }
  }

  included_files = ["streamlit/**"]
  filename       = "streamlit/cloudbuild.yaml"

  depends_on = [
    google_project_service.cloudbuild,
    google_service_account_iam_member.cloudbuild_access_application_agent
  ]
}

