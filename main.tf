# main.tf file

# Define the required provider and version constraint
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

variable "storage_bucket_name" {type = string}

variable "bq_dataset_id" {type = string}

variable "scraper_job_name" {type = string}

variable "loader_job_name" {type = string}

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
  project_roles_by_member = {
    (local.sa_scraper) = [
      "roles/vpcaccess.user",
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
      "roles/config.admin"
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

# Role for scraper to write data to our cloud storage bucket.
resource "google_storage_bucket_iam_member" "scraper_bucket_writer" {
  bucket = var.storage_bucket_name
  role   = "roles/storage.objectCreator"
  member = local.sa_scraper
}

# Role for loader to read data from our big query dataset.
resource "google_bigquery_dataset_iam_member" "loader_dataset_viewer" {
  project    = var.project_id
  dataset_id = var.bq_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = local.sa_loader
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

# Create the connector subnet within our VPC." 
resource "google_compute_subnetwork" "connector_subnet" {
  name = "connector-subnet"
  region = var.region
  network = google_compute_network.vpc_network.self_link
  ip_cidr_range = "10.0.1.0/28"
}

resource "google_vpc_access_connector" "connector" {
  name = "nazimz-connector"
  region = var.region
  network = google_compute_network.vpc_network.self_link
  ip_cidr_range = google_compute_subnetwork.connector_subnet.ip_cidr_range
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
resource "google_sql_database_instance" "private-db-instance" {
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

# Configure fire wall to reject all egress traffic from private database.
resource "google_compute_firewall" "deny_all_egress_db" {
  name = "deny-all-egress-db"
  network = google_compute_network.vpc_network.id
  direction = "EGRESS"
  priority = 1000

  destination_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
    ports = ["0-65535"]
  }
}

# Configure the private database to host our cloud sql instance.
resource "google_sql_database" "database" {
  name = "nazimz-private-sql-db"
  instance = google_sql_database_instance.private-db-instance
}

# Configure the Cloud Run job to scrape data from the Internet.
resource "google_cloud_run_v2_job" "scraper_job" {
  name = var.scraper_job_name
  location = var.region
  template {
    task_count = 1
    template {
      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress = "ALL_TRAFFIC"
      }
      containers {
        image = 
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
  depends_on = google_storage_bucket_iam_member.scraper_bucket_writer
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
      service_account = "serviceAccount:sa-db-loader@nazimz-database.iam.gserviceaccount.com"
      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress = "PRIVATE_RANGES_ONLY"
      }
      containers {
        image = 

        env { name = "BQ_DATASET_ID" value = var.bq_dataset_id }
        env { name = "BQ_TABLE_ID" value = "job_keyword_signals" }
        env { name = "DB_HOST" value = google_sql_database_instance.private_db.private_ip_address }
        env { name = "DB_NAME" value = "jobs_db" }
        env { name = "DB_USER" value = "loader_user" }
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
    iam_member =  "serviceAccount:sa-db-loader@nazimz-database.iam.gserviceaccount.com"
  }
  access {
    role = "WRITER"
    iam_member =  "serviceAccount:sa-db-loader@nazimz-database.iam.gserviceaccount.com"
  }
  access {
    role = "OWNER"
    iam_member = "serviceAccount:sa-manager-infra@nazimz-database.iam.gserviceaccount.com"
  }
}



