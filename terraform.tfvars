project_id            = "nazimz-database"
region                = "us-west2"
storage_bucket_name   = "nazimz-db-bucket"
workflow_name         = "nazimz-etl-workflow"
bq_dataset_id         = "employment_analytics"
bq_load_job_id        = "bq-load-job"
bq_query_job_id       = "bq-query-job"
common_labels = {
  env        = "dev"
  system     = "employment-pipeline"
  managed_by = "terraform"
}
bq_raw_tables = {
  raw_bls_observation = {
    deletion_protection = true
    schema_path         = "schemas/raw_bls_observation.json"
    time_partitioning = {
      type  = "DAY"
      field = "ingested_at"
    }
  }

  raw_usajobs_posting = {
    deletion_protection = true
    schema_path         = "schemas/raw_usajobs_posting.json"
    time_partitioning = {
      type  = "DAY"
      field = "retrieved_at"
    }
  }

  raw_adzuna_posting = {
    deletion_protection = true
    schema_path         = "schemas/raw_adzuna_posting.json"
    time_partitioning = {
      type  = "DAY"
      field = "retrieved_at"
    }
  }
}
bq_transformed_tables = {
    dim_source_system = {
    deletion_protection = true
    schema_path         = "schemas/dim_source_system.json"
  }

  dim_time_period = {
    deletion_protection = true
    schema_path         = "schemas/dim_time_period.json"
  }

  dim_location = {
    deletion_protection = true
    schema_path         = "schemas/dim_location.json"
    clustering          = ["state_code", "country_code"]
  }

  dim_occupation = {
    deletion_protection = true
    schema_path         = "schemas/dim_occupation.json"
  }

  dim_industry = {
    deletion_protection = true
    schema_path         = "schemas/dim_industry.json"
  }

  dim_employer = {
    deletion_protection = true
    schema_path         = "schemas/dim_employer.json"
  }

  xref_occupation = {
    deletion_protection = true
    schema_path         = "schemas/xref_occupation.json"
  }

  xref_industry = {
    deletion_protection = true
    schema_path         = "schemas/xref_industry.json"
  }

  curated_labor_metric = {
    deletion_protection = true
    schema_path         = "schemas/curated_labor_metric.json"
  }

  curated_bls_series = {
    deletion_protection = true
    schema_path         = "schemas/curated_bls_series.json"
  }

  fact_labor_observation = {
    deletion_protection = true
    schema_path         = "schemas/fact_labor_observation.json"
    clustering          = ["bls_series_id"]
    time_partitioning = {
      type  = "MONTH"
      field = "observation_date"
    }
  }

  fact_job_posting = {
    deletion_protection = true
    schema_path         = "schemas/fact_job_posting.json"
    clustering          = ["source_id", "occupation_id", "location_id"]
    time_partitioning = {
      type  = "DAY"
      field = "posted_date"
    }
  }
}

db_name = "nazimz-private-sql-db"
db_user = "nazimz"
app_service_image     = ""
app_service_name      = "streamlit-app-service"
scraper_job_name      = "monthly-scraper-job"
scraper_image         = ""
loader_job_name       = "monthly-loader-job" 
loader_image          = ""
adzuna_country        = "us"
enable_cloudsql       = true
