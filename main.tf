terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.7.0"
    }
  }
}

variable "project_id" {type = string}
variable "region" {type = string}

variable "keywords" {type = string}
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

variable "storage_bucket_name" {type = string}
variable "workflow_name" {type = string}
variable "bq_load_job_id" {type = string}
variable "bq_query_job_id" {type = string}
variable "bq_dataset_id"  {type = string}

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

variable db_user  {type = string}
variable db_name  {type = string}

variable "adzuna_app_id"  {type = string}
variable "adzuna_key"     {type = string}
variable "adzuna_country" {type = string}  

variable "bls_key" {type = string}

variable "usajobs_user_email" {type = string}
variable "usajobs_key" {type = string}

variable "app_service_image" {type = string}
variable "app_service_name" {type = string}

variable "scraper_job_name" {type = string}
variable "scraper_image" {type = string}

variable "loader_job_name" {type = string}
variable "loader_image" {type = string}

variable "enable_cloudsql" {
  type    = bool
  default = true
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {}

locals {
  sa_scraper             = "serviceAccount:sa-scraper-runjob@${var.project_id}.iam.gserviceaccount.com"
  sa_loader              = "serviceAccount:sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
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
}

locals {
  non_secret_bq_env = {
    BQ_PROJECT_ID = var.project_id
    BQ_DATASET_ID = var.bq_dataset_id
    BQ_LOAD_JOB_ID = var.bq_load_job_id
  }
}
locals {
  non_secret_sql_env = {
    DB_NAME = var.db_name
    DB_USER = var.db_user
    INSTANCE_CONNECTION_NAME = google_sql_database_instance.private_db_instance.name
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
      "roles/artifactregistry.admin"
      ],
      var.enable_cloudsql ? ["roles/cloudsql.editor"] : []
    )

    (local.sa_secret_manager) = [
      "roles/secretmanager.secretAccessor",
      "roles/cloudkms.cryptoKeyEncrypterDecrypter"
    ]

    (local.sa_event_trigger) = [
      "roles/workflows.invoker",
      "roles/pubsub.publisher"
    ]

    (local.sa_workflow) = [
      "roles/logging.logWriter",
      "roles/bigquery.jobUser",
      "roles/bigquery.dataEditor"
    ]

    (local.sa_app_account) = concat (
      [
      "roles/logging.logWriter",
    ],
    var.enable_cloudsql ? ["roles/cloudsql.client"] : []
    )
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
}

# Enable deployer agent to access the application agent
resource "google_service_account_iam_member" "deployer_access_application_agent" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.sa_app_account_email}"
  role               = "roles/iam.serviceAccountUser"
  member             = local.sa_app_deployer
}

# Enable the Secret Manager API. GCP creates the service agent when this is enabled.
resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Configure KMS keyring.
resource "google_kms_key_ring" "secrets" {
  name     = "nazimz-keyring"
  location = var.region
}

# Configure the key for securing credentials.
resource "google_kms_crypto_key" "secrets" {
  name            = "nazimz-key"
  key_ring        = google_kms_key_ring.secrets.id
  rotation_period = "7776000s"
}

# Provision the Secret Manager service agent (the Google-managed SA that GCP
# creates automatically when the API is enabled). Using google_project_service_identity
# ensures the agent exists in state and exposes its email as a reference — safer
# than hard-coding the service-PROJECT_NUMBER@gcp-sa-secretmanager pattern.
resource "google_project_service_identity" "secretmanager_agent" {
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
  member        = "serviceAccount:${google_project_service_identity.secretmanager_agent.email}"
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
  bucket = var.storage_bucket_name
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
  dataset_id = var.bq_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = local.sa_loader
}

# Enable workflow agent to run loader job after data transformation.
resource "google_cloud_run_v2_job_iam_member" "workflow_invokes_loader" {
  project  = var.project_id
  location = var.region
  name     = var.loader_job_name
  role   = "roles/run.invoker"
  member = local.sa_workflow
}

# Enable access to bigquery password.
resource "google_secret_manager_secret_iam_member" "bigquery_accessor" {
  secret_id = google_secret_manager_secret.db_master_pwd.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_loader
}

# Role for scheduler can invoke only our scraper job.
resource "google_cloud_run_v2_job_iam_member" "scheduler_invokes_scraper" {
  project  = var.project_id
  location = var.region
  name     = var.scraper_job_name
  role   = "roles/run.invoker"
  member = local.sa_scheduler
}

# Creating the VPC network to host our public and private subnets.
resource "google_compute_network" "vpc_network" {
  name = "nazimz-db-network"
  auto_create_subnetworks = false
  routing_mode = "REGIONAL"
}

# Create the private subnet within our VPC.
resource "google_compute_subnetwork" "private_subnet" {
  name = "private-subnet"
  region = var.region
  network = google_compute_network.vpc_network.self_link
  ip_cidr_range = "10.0.0.0/24"
  private_ip_google_access = true
}

# Create the connector subnet within our VPC.
resource "google_compute_subnetwork" "connector_subnet" {
  name = "connector-subnet"
  region = var.region
  network = google_compute_network.vpc_network.self_link
  ip_cidr_range = "10.0.1.0/28"
}

# Create the VPC connector to connect our Cloud Run jobs to our VPC.
resource "google_vpc_access_connector" "connector" {
  name   = "nazimz-connector"
  region = var.region
  subnet {
    name       = google_compute_subnetwork.connector_subnet.name
    project_id = var.project_id
  }
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
  project = var.project_id
  service = "servicenetworking.googleapis.com"
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
  depends_on = [google_project_service.service_networking]
}

# Enable access to SQL database password.
resource "google_secret_manager_secret_iam_member" "database_accessor" {
  secret_id = google_secret_manager_secret.db_private_pwd.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.sa_app_account
}

# Create user for the SQL database
resource "google_sql_user" "users" {
  name     = var.db_user
  instance = google_sql_database_instance.private_db_instance.name
  password = google_secret_manager_secret.db_private_pwd.secret_id
}


# CRITICAL: Removed the deny-all-egress firewall rule as it prevents Cloud SQL from functioning
# Cloud SQL requires egress connectivity for replication, backups, and Google API access
# Instead, rely on VPC design and Cloud SQL being private-only (no public IP)

# Configure the private database to host our cloud sql instance.
resource "google_sql_database" "database" {
  name     = "nazimz-private-sql-db"
  instance = google_sql_database_instance.private_db_instance.name
}

# Configure the private cloud sql database within the private subnet.
resource "google_sql_database_instance" "private_db_instance" {
  name = "nazimz-private-sql-instance"
  database_version = "MYSQL_8_0"
  region = var.region
  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled = false
      private_network = google_compute_network.vpc_network.self_link
    }
  }
  deletion_protection = true
  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Configure the service to host the streamlit application.
resource "google_cloud_run_v2_service" "streamlit-app" {
  name     = var.app_service_name
  location = var.region

  template {
    containers {
      image = var.app_service_image
      dynamic "env" {
          for_each = local.non_secret_db_env
          content {
            name = env.key
            value = env.value
          }
        }
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret = google_secret_manager_secret.db_private_pwd.secret_id
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
      }
    }
  }
}

# Enable Artifact Registry API
resource "google_project_service" "artifactregistry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Create Artifact Registry for docker image to host streamlit app
resource "google_artifact_registry_repository" "streamlit_repo {
  location      =  var.region
  repository_id = "streamlit-docker-img"
  description   = "Docker image repository for streamlit app."
  format        = "DOCKER"
  
  # Optional: prevent tag overwrites in production
  docker_config {
    immutable_tags = true
  }

  depends_on = [google_project_service.artifactregistry]
}

# Enable deployer agent to write docker image to streamlit repo
resource "google_artifact_registry_repository_iam_member" "viewer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.streamlit_repo.name
  role       = "roles/artifactregistry.writer"
  member     = sa.sa_app_deployer
}

# Enable deployer agent to run the Cloud Run service for streamlit app
resource "google_cloud_run_v2_service_iam_member" "deployer_runs_service" {
  project  = var.project_id
  location = var.region
  name     = var.app_service_name
  role   = "roles/run.developer"
  member = local.sa_app_deployer
}

# Configure firewall rule that only accepts inbound traffic from connector subnet.
resource "google_compute_firewall" "enable_traffic_to_db" {
  name = "enable-traffic-to-db"
  network = google_compute_network.vpc_network.self_link
  direction = "INGRESS"
  priority = 1000

  source_ranges = [google_compute_subnetwork.connector_subnet.ip_cidr_range]

  allow {
    protocol = "tcp"
    ports = ["3306"]
  }
}

# Configure the Cloud Run job to scrape data from the Internet.
resource "google_cloud_run_v2_job" "scraper_job" {
  name = var.scraper_job_name
  location = var.region
  template {
    task_count = 1
    template {
      service_account = "sa-scraper-runjob@${var.project_id}.iam.gserviceaccount.com"
      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress = "ALL_TRAFFIC"
      }
      containers {
        image = var.scraper_image
        
        dynamic "env" {
          for_each = local.non_secret_bq_env
          content {
            name = env.key
            value = env.value
          }
        }

        # Secret credentials 
        env {
          name = "BLS_API_KEY"
          value_source {
            secret_key_ref {
              secret = google_secret_manager_secret.bls_api_key.secret_id
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
          name = "INGESTION_BUCKET"
          value = google_storage_bucket.ingestion_bucket.name
        }
        volume_mounts {
          name = "gcs-volume"
          mount_path = "/gcs"
        }
      }
      volumes {
        name = "gcs-volume"
        gcs {
          bucket = google_storage_bucket.ingestion_bucket.name
          read_only = false
        }
      }
    }
  }
  depends_on = [google_storage_bucket_iam_member.scraper_bucket_writer]
}

# Enable eventarc API. 
resource "google_project_service" "eventarc" {
  service = "eventarc.googleapis.com"
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
    value     = var.storage_bucket_name
  }

  event_data_content_type = "application/json"
  service_account         = local.sa_event_trigger_email

  # Destination is a workflow that sends the trigger to our Cloud Storage Bucket
  destination {
    workflow = google_workflows_workflow.etl_workflow.id
  }
  depends_on = [
    google_workflows_workflow.etl_workflow
  ]
}

# Enable EventArc to read and retrieve data from GCS Bucket
resource "google_storage_bucket_iam_member" "event_bucket_retrieval" {
  bucket = var.storage_bucket_name
  role   = "roles/storage.objectViewer"
  member = local.sa_event_trigger
}

resource "google_workflows_workflow" "etl_workflow" {
  name                = var.workflow_name
  region              = var.region
  description         = "GCS -> BigQuery raw load -> BigQuery transform -> Cloud Run loader -> Cloud SQL"
  service_account     = local.sa_workflow_email
  call_log_level      = "LOG_ERRORS_ONLY"
  deletion_protection = false

  user_env_vars = {
    PROJECT_ID        = var.project_id
    BQ_DATASET_ID     = var.bq_dataset_id
    BQ_LOCATION       = "US"
    INGESTION_BUCKET  = google_storage_bucket.ingestion_bucket.name

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
              raise: $${"Unexpected bucket received: " + bucket}

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
          raise: $${"Unsupported object path: " + object_name}

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
    google_storage_bucket.ingestion_bucket
  ]
}

# Enable workflow agent to retrieve data from Google Cloud Storage Bucket
resource "google_storage_bucket_iam_member" "workflow_bucket_reader" {
  bucket = var.storage_bucket_name
  role   = "roles/storage.objectViewer"
  member = local.sa_workflow
}

# Enable workflow agent to read, write, and create datasets for the BigQuery dataset
resource "google_bigquery_dataset_iam_member" "workflow_dataset_user" {
  project    = var.project_id
  dataset_id = var.bq_dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = local.sa_workflow
}


# Configure the cloud storage bucket for our scraper job to send the data to.
resource "google_storage_bucket" "ingestion_bucket" {
  name = var.storage_bucket_name
  location = var.region
  storage_class = "STANDARD"
  force_destroy = false
  versioning {
    enabled = true
  }
}

# Configure the Cloud Run job to load data from bigquery to our private database.
resource "google_cloud_run_v2_job" "loader_job" {
  name = var.loader_job_name
  location = var.region
  template {
    task_count = 1
    template {
      service_account = "sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress = "PRIVATE_RANGES_ONLY"
      }
      containers {
        image = var.loader_image
        env {
          name = "BQ_PROJECT_ID" 
          value = var.project_id
        }
        env { 
          name = "BQ_DATASET_ID" 
          value = var.bq_dataset_id 
        }
        env {
          name = "DB_HOST" 
          value = google_sql_database_instance.private_db_instance.private_ip_address 
        }
        env { 
          name = "DB_NAME" 
          value = "jobs_db" 
        }
        env { 
          name = "DB_USER" 
          value = "loader_user" 
        }
        env {
          name = "DB_PASSWORD"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_master_pwd.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }
}


# Configure our bigquery dataset for data transformation.
resource "google_bigquery_dataset" "employment_analytics" {
  dataset_id  = var.bq_dataset_id
  location    = "US"
  description = "Dataset used for loading into private database"
  labels = {
    env = "dev"
  }
  access {
    role = "READER"
    user_by_email = "sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
  }
  access {
    role = "WRITER"
    user_by_email = "sa-data-workflow@${var.project_id}.iam.gserviceaccount.com"
  }
  access {
    role = "OWNER"
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

  schema = each.value.schema_path != null ? file(each.value.schema_path) : null
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

  schema = each.value.schema_path != null ? file(each.value.schema_path) : null
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
  dataset_id   = google_bigquery_dataset.employment_analytics.dataset_id
  routine_id   = "sp_transform_bls"
  routine_type = "PROCEDURE"
  language     = "SQL"
  definition_body = <<-SQL
    BEGIN
      -- Populate dim_time_period from raw_bls_observation
      MERGE `${var.project_id}.${var.bq_dataset_id}.dim_time_period` T
      USING (
        SELECT DISTINCT
          CONCAT(CAST(observation_year AS STRING), '-', observation_period) AS time_id,
          DATE(observation_year, CAST(SUBSTR(observation_period, 2) AS INT64), 1) AS calendar_date,
          observation_year AS year,
          CAST(SUBSTR(observation_period, 2) AS INT64) AS month
        FROM `${var.project_id}.${var.bq_dataset_id}.raw_bls_observation`
        WHERE observation_period LIKE 'M%'
      ) S ON T.time_id = S.time_id
      WHEN NOT MATCHED THEN
        INSERT (time_id, calendar_date, year, month, period_type)
        VALUES (S.time_id, S.calendar_date, S.year, S.month, 'MONTH');

      -- Populate curated_bls_series and fact_labor_observation
      -- (full mapping to be completed with Python scraper field names)
    END
  SQL
  depends_on = [google_bigquery_table.transformed_tables]
}

resource "google_bigquery_routine" "sp_transform_usajobs" {
  dataset_id   = google_bigquery_dataset.employment_analytics.dataset_id
  routine_id   = "sp_transform_usajobs"
  routine_type = "PROCEDURE"
  language     = "SQL"
  definition_body = <<-SQL
    BEGIN
      -- Populate dim_employer, dim_occupation, dim_location from raw_usajobs_posting
      -- Populate fact_job_posting
      -- (full mapping to be completed with Python scraper field names)
      SELECT 1;
    END
  SQL
  depends_on = [google_bigquery_table.transformed_tables]
}

resource "google_bigquery_routine" "sp_transform_adzuna" {
  dataset_id   = google_bigquery_dataset.employment_analytics.dataset_id
  routine_id   = "sp_transform_adzuna"
  routine_type = "PROCEDURE"
  language     = "SQL"
  definition_body = <<-SQL
    BEGIN
      -- Populate dim_employer, dim_occupation, dim_location from raw_adzuna_posting
      -- Populate fact_job_posting
      -- (full mapping to be completed with Python scraper field names)
      SELECT 1;
    END
  SQL
  depends_on = [google_bigquery_table.transformed_tables]
}
