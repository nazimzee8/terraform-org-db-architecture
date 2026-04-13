# PRD: Employment Analytics Terraform Configuration

## 1. Product Context

This Terraform project provisions the Google Cloud foundation for an employment analytics platform in project `nazimz-database`, region `us-west2`. The platform ingests labor-market and job-posting data, stages raw files in Cloud Storage, transforms data in BigQuery, mirrors analytics-serving data into a private Cloud SQL MySQL database, and serves a Streamlit dashboard on Cloud Run.

The current intended data path is:

1. Cloud Scheduler invokes the scraper Cloud Run job.
2. The scraper calls BLS, USAJOBS, and Adzuna APIs and writes raw files to `gs://nazimz-db-bucket/raw/...`.
3. Eventarc listens for finalized GCS objects and invokes Workflows.
4. Workflows loads the matching raw file into BigQuery, calls the source-specific BigQuery stored procedure, then invokes the loader Cloud Run job.
5. The loader reads BigQuery modeled facts and dimensions and upserts them into Cloud SQL.
6. The Streamlit Cloud Run service reads analytics from Cloud SQL using private VPC access.

## 2. Terraform Configuration Summary

Primary Terraform inputs are defined in `terraform.tfvars`:

- Project: `nazimz-database`
- Region: `us-west2`
- Storage bucket: `nazimz-db-bucket`
- BigQuery dataset: `employment_analytics`
- Workflow: `nazimz-etl-workflow`
- Cloud SQL database: `nazimz-private-sql-db`
- Cloud SQL user: `nazimz`
- Streamlit service: `streamlit-app-service`
- Scraper job: `monthly-scraper-job`
- Loader job: `monthly-loader-job`
- GitHub source: `nazimzee8/terraform-org-db-architecture`

Terraform manages the following major subsystems:

- APIs: Secret Manager, Artifact Registry, Cloud Build, Cloud Run, Cloud SQL Admin, Serverless VPC Access, Workflows, BigQuery, Cloud Storage, Cloud Scheduler, Eventarc, Pub/Sub, Compute Engine, Cloud KMS, Cloud Logging, Cloud Resource Manager, IAM, and Service Networking.
- Network: custom VPC, private subnet, connector subnet, Serverless VPC Access connector, Cloud Router, Cloud NAT, private service access range, and Service Networking peering for private Cloud SQL.
- Security: KMS key ring and crypto key for Secret Manager CMEK, Secret Manager service agent KMS binding, project IAM bindings for runtime service accounts, Secret Manager accessors, bucket IAM, BigQuery dataset IAM, and Cloud Run invoker grants. Runtime service accounts are referenced by Terraform but were originally created outside Terraform with the gcloud bootstrap script.
- Storage and analytics: ingestion bucket, BigQuery raw tables, transformed dimension/fact tables, and BigQuery stored procedures for BLS, USAJOBS, and Adzuna transformations.
- Compute: Cloud Run service for Streamlit, Cloud Run jobs for scraper and loader, Scheduler trigger, Eventarc trigger, and Workflows orchestration.
- CI/CD: three Cloud Build triggers for scraper, loader, and Streamlit source folders.

## 3. Service Account Bootstrap Context

The runtime service accounts were created outside the Terraform configuration by the repository bootstrap script `gcli-script.sh`, using `gcloud iam service-accounts create`. Terraform then references those existing service accounts through `locals` and manages IAM bindings, invoker permissions, Secret Manager access, bucket access, BigQuery dataset access, and Cloud Run service-account usage around them.

This is an important ownership boundary: the current `main.tf` expects these service accounts to already exist and does not contain `google_service_account` resources to create them.

Service accounts created by `gcli-script.sh`:

| Service account | Bootstrap purpose | Terraform/runtime usage |
| --- | --- | --- |
| `sa-scraper-runjob@nazimz-database.iam.gserviceaccount.com` | Automated scraping job identity | Scraper Cloud Run job; reads source API secrets and writes to the ingestion bucket |
| `sa-db-loader@nazimz-database.iam.gserviceaccount.com` | BigQuery-to-private-database loader identity | Loader Cloud Run job; reads BigQuery, reads `DB_PASSWORD`, connects to Cloud SQL through VPC access |
| `sa-scheduler@nazimz-database.iam.gserviceaccount.com` | Scheduler trigger identity | Cloud Scheduler OAuth identity used to invoke the scraper job |
| `sa-manager-infra@nazimz-database.iam.gserviceaccount.com` | Infrastructure management identity | Receives broad admin roles for network, Cloud SQL, BigQuery, storage, Run, Workflows, and Artifact Registry operations |
| `sa-secret-manager@nazimz-database.iam.gserviceaccount.com` | Secret management identity | Receives Secret Manager and KMS permissions for secret-management workflows |
| `sa-data-workflow@nazimz-database.iam.gserviceaccount.com` | ETL orchestration identity | Workflows service account; reads GCS, writes BigQuery, invokes/polls the loader job |
| `sa-app-account@nazimz-database.iam.gserviceaccount.com` | Streamlit application runtime identity | Streamlit Cloud Run service; reads `DB_PASSWORD` and connects to Cloud SQL through VPC access |
| `sa-app-deployer@nazimz-database.iam.gserviceaccount.com` | Streamlit deployer identity | Deployer identity for application Cloud Build / Cloud Run deployment workflows |

Bootstrap commands are in `gcli-script.sh`, including project creation/configuration, the service-account creation commands, initial API enables, and early Cloud Build submissions. Because these identities are external prerequisites, a fresh project must run or replace that bootstrap step before Terraform can apply successfully.

Recommended validation commands:

```powershell
cmd /c gcloud iam service-accounts list --project=nazimz-database --format="table(email,displayName)"
cmd /c gcloud iam service-accounts describe sa-scraper-runjob@nazimz-database.iam.gserviceaccount.com --project=nazimz-database
cmd /c gcloud iam service-accounts describe sa-db-loader@nazimz-database.iam.gserviceaccount.com --project=nazimz-database
cmd /c gcloud iam service-accounts describe sa-data-workflow@nazimz-database.iam.gserviceaccount.com --project=nazimz-database
cmd /c gcloud iam service-accounts describe sa-app-account@nazimz-database.iam.gserviceaccount.com --project=nazimz-database
```

## 4. Secrets And Manual Secret Manager Context

Terraform creates the Secret Manager secret containers and grants service accounts access, but sensitive secret values are expected to be manually added as Secret Manager versions in Google Cloud. The provided Google Cloud console screenshot confirms the project has manually configured Secret Manager entries for the source API credentials, database passwords, GitHub token context, and related legacy/external secrets. This keeps the secret payloads out of Terraform configuration and avoids storing them in Terraform state.

Secret Manager context:

| Secret ID | Purpose | Runtime consumer / Terraform status |
| --- | --- | --- |
| `BLS_API_KEY` | API key for BLS requests | `sa-scraper-runjob` via `BLS_API_KEY` env var |
| `USAJOBS_EMAIL` | USAJOBS user email header | `sa-scraper-runjob` via `USAJOBS_USER_EMAIL` env var |
| `USAJOBS_API_KEY` | USAJOBS API key header | `sa-scraper-runjob` via `USAJOBS_API_KEY` env var |
| `ADZUNA_APP_ID` | Adzuna application ID | `sa-scraper-runjob` via `ADZUNA_APP_ID` env var |
| `ADZUNA_API_KEY` | Adzuna API key | `sa-scraper-runjob` via `ADZUNA_APP_KEY` env var |
| `DB_PASSWORD` | Cloud SQL user password and application DB password | `sa-db-loader`, `sa-app-account`, and Terraform `google_sql_user` data lookup |
| `DB_MASTER_PWD` | Legacy/unused DB password container in current config | No active runtime reference after the Cloud SQL serving update |
| `GITHUB_PAT` | Manually configured GitHub token context | External CI/CD/bootstrap context; not directly injected into the current Cloud Run runtimes |
| `USA_API_KEY` | Manually configured external/legacy API key context visible in Secret Manager | No active runtime reference in the current Terraform-managed Cloud Run env contract |

Manual secret version requirement:

- A `latest` version of `DB_PASSWORD` must exist before `terraform plan/apply`, because `main.tf` reads it with `data.google_secret_manager_secret_version_access.db_password` to create the Cloud SQL user password.
- API credentials must also have `latest` versions before the scraper job is run, because Cloud Run injects those secrets at runtime.

Example manual creation commands:

```powershell
cmd /c gcloud secrets versions add BLS_API_KEY --project=nazimz-database --data-file=bls_api_key.txt
cmd /c gcloud secrets versions add USAJOBS_EMAIL --project=nazimz-database --data-file=usajobs_email.txt
cmd /c gcloud secrets versions add USAJOBS_API_KEY --project=nazimz-database --data-file=usajobs_api_key.txt
cmd /c gcloud secrets versions add ADZUNA_APP_ID --project=nazimz-database --data-file=adzuna_app_id.txt
cmd /c gcloud secrets versions add ADZUNA_API_KEY --project=nazimz-database --data-file=adzuna_api_key.txt
cmd /c gcloud secrets versions add DB_PASSWORD --project=nazimz-database --data-file=db_password.txt
# Optional external/bootstrap context only, when used by your manual workflows:
cmd /c gcloud secrets versions add GITHUB_PAT --project=nazimz-database --data-file=github_pat.txt
```

Use local files that contain only the secret value and do not commit those files. The retrieval point for application code is not the local file: runtime retrieval happens through Cloud Run Secret Manager env var injection, and Terraform only reads `DB_PASSWORD` from Secret Manager to configure the Cloud SQL user.

## 5. Data And Serving Requirements

BigQuery remains the transformation warehouse. Terraform creates raw source tables, transformed dimension/fact tables, and stored procedures:

- Raw tables: `raw_bls_observation`, `raw_usajobs_posting`, `raw_adzuna_posting`
- Dimensions and lookups: `dim_source_system`, `dim_time_period`, `dim_location`, `dim_occupation`, `dim_industry`, `dim_employer`, `xref_occupation`, `xref_industry`, `curated_labor_metric`, `curated_bls_series`
- Facts: `fact_labor_observation`, `fact_job_posting`
- Procedures: `sp_transform_bls`, `sp_transform_usajobs`, `sp_transform_adzuna`

Cloud SQL is the Streamlit serving database. The loader mirrors the BigQuery dimensional serving model into Cloud SQL and uses these dashboard windows:

- Labor observations: last 24 months
- Job postings: last 18 months

Streamlit should not query BigQuery directly. It receives Cloud SQL connection data through `DB_HOST`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD`, connects through the Serverless VPC Access connector, and joins Cloud SQL dimension tables for metric names, sector codes, industry labels, occupation labels, and state coverage.

## 6. Cloud Build Triggers And Deployment Behavior

Terraform declares three GitHub Cloud Build triggers. All three watch pushes to the `main` branch of `nazimzee8/terraform-org-db-architecture`, scoped by changed file paths.

| Terraform resource | Cloud Build trigger name | Path filter | Build config | Target |
| --- | --- | --- | --- | --- |
| `google_cloudbuild_trigger.scraper_trigger` | `scraper-build-deploy` | `scraper/**` | `scraper/cloudbuild.yaml` | Deploys image to `monthly-scraper-job` |
| `google_cloudbuild_trigger.loader_trigger` | `loader-build-deploy` | `loader/**` | `loader/cloudbuild.yaml` | Deploys image to `monthly-loader-job` |
| `google_cloudbuild_trigger.streamlit_trigger` | `streamlit-build-deploy` | `streamlit/**` | `streamlit/cloudbuild.yaml` | Deploys mutable `:latest` image to `streamlit-app-service` |

Each Cloud Build config has three steps:

1. Build a Docker image.
2. Push the image to Artifact Registry.
3. Update the Cloud Run job or service with the new image when `_DEPLOY=true`.

Current deployment behavior: all three YAML files now set `_DEPLOY=true` by default. The Streamlit build config intentionally pushes and deploys mutable `:latest` even if an existing console-created trigger overrides `_TAG` with `$SHORT_SHA`; it also accepts uppercase `_DEPLOY=TRUE` from that trigger.

Required trigger substitution intent for automatic deployment:

- `scraper-build-deploy`: `_DEPLOY=true`, `_JOB_NAME=monthly-scraper-job`, `_REGION=us-west2`, `_IMAGE_URI=us-west2-docker.pkg.dev/nazimz-database/scraper-docker-img/scraper`
- `loader-build-deploy`: `_DEPLOY=true`, `_JOB_NAME=monthly-loader-job`, `_REGION=us-west2`, `_IMAGE_URI=us-west2-docker.pkg.dev/nazimz-database/loader-docker-img/loader`
- `streamlit-build-deploy`: `_DEPLOY=true`, `_TAG=latest`, `_SERVICE_NAME=streamlit-app-service`, `_REGION=us-west2`, `_IMAGE_URI=us-west2-docker.pkg.dev/nazimz-database/streamlit-docker-img/streamlit`

Use `_DEPLOY=false` only for an intentional build-only run where the image should be pushed but Cloud Run should not be updated. Streamlit intentionally uses a mutable `:latest` tag, so the Artifact Registry repository must keep `immutable_tags=false`.

## 7. Acceptance Criteria

Infrastructure is ready when:

- `terraform validate` passes.
- `terraform plan -var-file=terraform.tfvars` shows only intended changes.
- `DB_PASSWORD` has an enabled `latest` Secret Manager version before apply.
- Cloud SQL Admin, Workflows, Eventarc, Pub/Sub, Compute Engine, Cloud KMS, Cloud Logging, IAM, Cloud Resource Manager, and the other Terraform-declared APIs are enabled.
- Cloud SQL instance, database, and user exist.
- Scraper and loader Cloud Run jobs exist in `us-west2`.
- Eventarc trigger and Workflows workflow exist and target the ingestion bucket and loader job.
- Streamlit Cloud Run revision is Ready and has Cloud SQL env vars, not the old BigQuery-only env contract.

Data path is ready when:

- Scraper writes BLS, USAJOBS, and Adzuna raw objects to the ingestion bucket.
- Workflows loads the raw object into BigQuery, runs the correct transform procedure, invokes the loader job, and polls the loader operation to success.
- Cloud SQL contains fact and dimension rows for the 24-month labor and 18-month posting serving windows.
- Streamlit dashboard values and freshness metadata come from Cloud SQL tables.

Recommended read-only validation commands:

```powershell
terraform validate
terraform plan -var-file=terraform.tfvars
cmd /c gcloud services list --enabled --project=nazimz-database
cmd /c gcloud secrets versions list DB_PASSWORD --project=nazimz-database
cmd /c gcloud run jobs describe monthly-scraper-job --region=us-west2 --project=nazimz-database
cmd /c gcloud run jobs describe monthly-loader-job --region=us-west2 --project=nazimz-database
cmd /c gcloud run services describe streamlit-app-service --region=us-west2 --project=nazimz-database
cmd /c gcloud workflows describe nazimz-etl-workflow --location=us-west2 --project=nazimz-database
cmd /c gcloud eventarc triggers describe gcs-bucket-trigger --location=us-west2 --project=nazimz-database
cmd /c gcloud sql instances describe nazimz-private-sql-instance --project=nazimz-database
```
