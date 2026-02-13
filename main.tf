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

variable "bq_dataset_id"  {type = string}
variable "bq_table_id"    {type = string}

variable "adzuna_app_id"  {type = string}
variable "adzuna_key"     {type = string}
variable "adzuna_country" {type = string}  

variable usajobs_user_email {type = string}
variable "usajobs_key" {type = string}

variable "scraper_job_name" {type = string}
variable "scraper_image" {type = string}

variable "loader_job_name" {type = string}
variable "loader_image" {type = string}
variable "db_master_pwd" {type = string}

variable "enable_cloudsql" {
  type    = bool
  default = true
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  sa_scraper   = "serviceAccount:sa-scraper-runjob@${var.project_id}.iam.gserviceaccount.com"
  sa_loader    = "serviceAccount:sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
  sa_scheduler = "serviceAccount:sa-scheduler@${var.project_id}.iam.gserviceaccount.com"
  sa_manager   = "serviceAccount:sa-manager-infra@${var.project_id}.iam.gserviceaccount.com"
}

locals {
  non_secret_env = {
    BQ_PROJECT_ID = var.project_id
    BQ_DATASET_ID = var.bq_dataset_id
    BQ_TABLE_ID   = var.bq_table_id
    ADZUNA_COUNTRY   = var.adzuna_country
  }
}

locals {
  project_roles_by_member = {
    (local.sa_scraper) = [
      "roles/vpcaccess.user"
    ]

    (local.sa_loader) = concat(
      [
        "roles/vpcaccess.user",
        "roles/bigquery.jobUser",
      ],
      var.enable_cloudsql ? ["roles/cloudsql.client"] : []
    )

    (local.sa_manager) = [
      "roles/compute.networkAdmin",
      "roles/run.admin",
      "roles/config.admin",
      "roles/cloudkms.cryptoKeyEncrypter"
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

# Configure secret for user credentials for USAjobs
resource "google_secret_manager_secret" "usajobs_user_email" {
  project   = var.project_id
  secret_id = "usajobs_user_email"
  replication { 
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    } 
  }
}

# Configure secret for API Key received from USAJobs
resource "google_secret_manager_secret" "usajobs_api_key" {
  project   = var.project_id
  secret_id = "usajobs_api_key"
  replication { 
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    } 
  }
}

# Configure secret for App ID received from Adzuna
resource "google_secret_manager_secret" "adzuna_app_id" {
  project   = var.project_id
  secret_id = "adzuna_app_id"
  replication { 
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    } 
  }
}

# Configure secret for API Key received from Adzuna
resource "google_secret_manager_secret" "adzuna_api_key" {
  project   = var.project_id
  secret_id = "adzuna_api_key"
  replication { 
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    } 
  }
}

# Configure secret for bigquery password.
resource "google_secret_manager_secret" "db_master_pwd" {
  project   = var.project_id
  secret_id = "db_master_pwd"
  replication { 
    auto {
      customer_managed_encryption {
        kms_key_name = google_kms_crypto_key.secrets.id
      }
    } 
  }
}

# Role for scraper to write data to our cloud storage bucket.
resource "google_storage_bucket_iam_member" "scraper_bucket_writer" {
  bucket = var.storage_bucket_name
  role   = "roles/storage.objectCreator"
  member = local.sa_scraper
}

# Grant scraper service account encrypt/decrypt permissions on the crypto key
resource "google_kms_crypto_key_iam_member" "scraper_key_encrypter_decrypter" {
  crypto_key_id = google_kms_crypto_key.secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = local.sa_scraper
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

# Role for loader to read data from our big query dataset.
resource "google_bigquery_dataset_iam_member" "loader_dataset_viewer" {
  project    = var.project_id
  dataset_id = var.bq_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = local.sa_loader
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
  name = "nazimz-connector"
  region = var.region
  network = google_compute_network.vpc_network.self_link
  ip_cidr_range = google_compute_subnetwork.connector_subnet.ip_cidr_range
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

# CRITICAL: Removed the deny-all-egress firewall rule as it prevents Cloud SQL from functioning
# Cloud SQL requires egress connectivity for replication, backups, and Google API access
# Instead, rely on VPC design and Cloud SQL being private-only (no public IP)

# Configure the private database to host our cloud sql instance.
resource "google_sql_database" "database" {
  name     = "nazimz-private-sql-db"
  instance = google_sql_database_instance.private_db_instance.name
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
          for_each = local.non_secret_env
          content {
            name = env.key
            value = env.value
          }
        }

        # Secret credentials 
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
          name = "BQ_TABLE_ID" 
          value = var.bq_table_id 
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
resource "google_bigquery_dataset" "bq_dataset" {
  dataset_id = var.bq_dataset_id
  location = var.region
  description = "Dataset used for loading into private database"
  default_table_expiration_ms = 3600000
  labels = {
    env = "dev"
  }
  access {
    role = "READER"
    user_by_email = "sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
  }
  access {
    role = "WRITER"
    user_by_email = "sa-db-loader@${var.project_id}.iam.gserviceaccount.com"
  }
  access {
    role = "OWNER"
    user_by_email = "sa-manager-infra@${var.project_id}.iam.gserviceaccount.com"
  }
}
