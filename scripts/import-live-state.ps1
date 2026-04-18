[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$ProjectId = "nazimz-database",
  [string]$Region = "us-west2",
  [string]$BucketName = "nazimz-db-bucket",
  [string]$DatasetId = "employment_analytics",
  [string]$NetworkName = "nazimz-db-network",
  [string]$SqlInstance = "nazimz-private-sql-instance",
  [string]$SqlDatabase = "nazimz-private-sql-db",
  [string]$SqlUser = "nazimz",
  [string]$TerraformBin = $env:TERRAFORM_BIN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Resolve-Bin($name, $fallback = $null) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if ($fallback -and (Test-Path -LiteralPath $fallback)) { return $fallback }
  return $null
}

if (-not $TerraformBin) {
  $TerraformBin = Resolve-Bin "terraform" "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Hashicorp.Terraform_Microsoft.Winget.Source_8wekyb3d8bbwe\terraform.exe"
}
$GcloudBin = Resolve-Bin "gcloud.cmd"
if (-not $GcloudBin) { $GcloudBin = Resolve-Bin "gcloud" }
$BqBin = Resolve-Bin "bq.cmd"
if (-not $BqBin) { $BqBin = Resolve-Bin "bq" }

if (-not $TerraformBin) { throw "Terraform was not found. Set TERRAFORM_BIN to terraform.exe." }
if (-not $GcloudBin) { throw "gcloud.cmd was not found. Install Google Cloud CLI first." }

function Run($bin, [string[]]$argv, [switch]$Quiet) {
  if ($Quiet) { & $bin @argv *> $null } else { & $bin @argv }
  return $LASTEXITCODE -eq 0
}

function Out($bin, [string[]]$argv) {
  $output = & $bin @argv 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $output) { return $null }
  return (($output | Select-Object -First 1) -as [string]).Trim()
}

function In-State($address) {
  return Run $TerraformBin @("state", "show", "-no-color", $address) -Quiet
}

function Import-IfExists($address, $id, [scriptblock]$exists) {
  if (In-State $address) {
    Write-Host "SKIP tracked: $address"
    return
  }
  if (-not (& $exists)) {
    Write-Host "SKIP missing: $address"
    return
  }
  Write-Host "IMPORT: $address <= $id"
  & $TerraformBin import $address $id
  if ($LASTEXITCODE -ne 0) { Write-Warning "Import failed for $address using id $id"; return }
}

function Gcloud-Exists([string[]]$argv) { return Run $GcloudBin $argv -Quiet }
function Bq-Exists($id) {
  if (-not $BqBin) { Write-Warning "bq.cmd not found; skipping $id"; return $false }
  return Run $BqBin @("show", "--format=none", $id) -Quiet
}

$services = @{
  "google_project_service.artifactregistry" = "artifactregistry.googleapis.com"
  "google_project_service.bigquery" = "bigquery.googleapis.com"
  "google_project_service.cloudbuild" = "cloudbuild.googleapis.com"
  "google_project_service.cloudkms" = "cloudkms.googleapis.com"
  "google_project_service.cloudresourcemanager" = "cloudresourcemanager.googleapis.com"
  "google_project_service.cloudscheduler" = "cloudscheduler.googleapis.com"
  "google_project_service.cloudsql" = "sqladmin.googleapis.com"
  "google_project_service.compute" = "compute.googleapis.com"
  "google_project_service.eventarc" = "eventarc.googleapis.com"
  "google_project_service.iam" = "iam.googleapis.com"
  "google_project_service.logging" = "logging.googleapis.com"
  "google_project_service.pubsub" = "pubsub.googleapis.com"
  "google_project_service.run" = "run.googleapis.com"
  "google_project_service.secretmanager" = "secretmanager.googleapis.com"
  "google_project_service.service_networking" = "servicenetworking.googleapis.com"
  "google_project_service.storage" = "storage.googleapis.com"
  "google_project_service.vpcaccess" = "vpcaccess.googleapis.com"
  "google_project_service.workflows" = "workflows.googleapis.com"
}
foreach ($entry in $services.GetEnumerator()) {
  $svc = $entry.Value
  Import-IfExists $entry.Key "$ProjectId/$svc" { Gcloud-Exists @("services", "list", "--enabled", "--project=$ProjectId", "--filter=config.name=$svc", "--format=value(config.name)") }
}

Import-IfExists "google_kms_key_ring.secrets" "projects/$ProjectId/locations/global/keyRings/nazimz-keyring" { Gcloud-Exists @("kms", "keyrings", "describe", "nazimz-keyring", "--location=global", "--project=$ProjectId") }
Import-IfExists "google_kms_crypto_key.secrets" "projects/$ProjectId/locations/global/keyRings/nazimz-keyring/cryptoKeys/nazimz-key" { Gcloud-Exists @("kms", "keys", "describe", "nazimz-key", "--keyring=nazimz-keyring", "--location=global", "--project=$ProjectId") }

$secrets = @{
  "google_secret_manager_secret.adzuna_api_key" = "ADZUNA_API_KEY"
  "google_secret_manager_secret.adzuna_app_id" = "ADZUNA_APP_ID"
  "google_secret_manager_secret.bls_api_key" = "BLS_API_KEY"
  "google_secret_manager_secret.db_master_pwd" = "DB_MASTER_PWD"
  "google_secret_manager_secret.db_private_pwd" = "DB_PASSWORD"
  "google_secret_manager_secret.usajobs_api_key" = "USAJOBS_API_KEY"
  "google_secret_manager_secret.usajobs_user_email" = "USAJOBS_EMAIL"
}
foreach ($entry in $secrets.GetEnumerator()) {
  $secret = $entry.Value
  Import-IfExists $entry.Key "projects/$ProjectId/secrets/$secret" { Gcloud-Exists @("secrets", "describe", $secret, "--project=$ProjectId") }
}

$repos = @{
  "google_artifact_registry_repository.loader_repo" = "loader-docker-img"
  "google_artifact_registry_repository.scraper_repo" = "scraper-docker-img"
  "google_artifact_registry_repository.streamlit_repo" = "streamlit-docker-img"
}
foreach ($entry in $repos.GetEnumerator()) {
  $repo = $entry.Value
  Import-IfExists $entry.Key "projects/$ProjectId/locations/$Region/repositories/$repo" { Gcloud-Exists @("artifacts", "repositories", "describe", $repo, "--location=$Region", "--project=$ProjectId") }
}

Import-IfExists "google_storage_bucket.ingestion_bucket" $BucketName { Gcloud-Exists @("storage", "buckets", "describe", "gs://$BucketName", "--project=$ProjectId") }

Import-IfExists "google_compute_network.vpc_network" "projects/$ProjectId/global/networks/$NetworkName" { Gcloud-Exists @("compute", "networks", "describe", $NetworkName, "--project=$ProjectId") }
Import-IfExists "google_compute_subnetwork.private_subnet" "projects/$ProjectId/regions/$Region/subnetworks/private-subnet" { Gcloud-Exists @("compute", "networks", "subnets", "describe", "private-subnet", "--region=$Region", "--project=$ProjectId") }
Import-IfExists "google_compute_subnetwork.connector_subnet" "projects/$ProjectId/regions/$Region/subnetworks/connector-subnet" { Gcloud-Exists @("compute", "networks", "subnets", "describe", "connector-subnet", "--region=$Region", "--project=$ProjectId") }
Import-IfExists "google_vpc_access_connector.connector" "projects/$ProjectId/locations/$Region/connectors/nazimz-connector" { Gcloud-Exists @("compute", "networks", "vpc-access", "connectors", "describe", "nazimz-connector", "--region=$Region", "--project=$ProjectId") }
Import-IfExists "google_compute_router.router" "projects/$ProjectId/regions/$Region/routers/router-nat" { Gcloud-Exists @("compute", "routers", "describe", "router-nat", "--region=$Region", "--project=$ProjectId") }
Import-IfExists "google_compute_router_nat.nat_gateway" "$Region/router-nat/nat-config" { Gcloud-Exists @("compute", "routers", "nats", "describe", "nat-config", "--router=router-nat", "--region=$Region", "--project=$ProjectId") }
Import-IfExists "google_compute_global_address.private_service_range" "projects/$ProjectId/global/addresses/private-service-access-range" { Gcloud-Exists @("compute", "addresses", "describe", "private-service-access-range", "--global", "--project=$ProjectId") }
Import-IfExists "google_service_networking_connection.private_vpc_connection" "projects/$ProjectId/global/networks/$NetworkName`:servicenetworking.googleapis.com" { Gcloud-Exists @("services", "vpc-peerings", "list", "--network=$NetworkName", "--project=$ProjectId", "--format=value(network)") }
Import-IfExists "google_compute_firewall.enable_traffic_to_db" "projects/$ProjectId/global/firewalls/enable-traffic-to-db" { Gcloud-Exists @("compute", "firewall-rules", "describe", "enable-traffic-to-db", "--project=$ProjectId") }

Import-IfExists "google_sql_database_instance.private_db_instance" "projects/$ProjectId/instances/$SqlInstance" { Gcloud-Exists @("sql", "instances", "describe", $SqlInstance, "--project=$ProjectId") }
Import-IfExists "google_sql_database.database" "projects/$ProjectId/instances/$SqlInstance/databases/$SqlDatabase" { Gcloud-Exists @("sql", "databases", "describe", $SqlDatabase, "--instance=$SqlInstance", "--project=$ProjectId") }
Import-IfExists "google_sql_user.users" "$ProjectId/$SqlInstance//$SqlUser" { Gcloud-Exists @("sql", "users", "list", "--instance=$SqlInstance", "--project=$ProjectId", "--filter=name=$SqlUser", "--format=value(name)") }

Import-IfExists "google_cloud_run_v2_service.streamlit-app" "projects/$ProjectId/locations/$Region/services/streamlit-app-service" { Gcloud-Exists @("run", "services", "describe", "streamlit-app-service", "--region=$Region", "--project=$ProjectId") }
Import-IfExists "google_cloud_run_v2_job.scraper_job" "projects/$ProjectId/locations/$Region/jobs/monthly-scraper-job" { Gcloud-Exists @("run", "jobs", "describe", "monthly-scraper-job", "--region=$Region", "--project=$ProjectId") }
Import-IfExists "google_cloud_run_v2_job.loader_job" "projects/$ProjectId/locations/$Region/jobs/monthly-loader-job" { Gcloud-Exists @("run", "jobs", "describe", "monthly-loader-job", "--region=$Region", "--project=$ProjectId") }
Import-IfExists "google_workflows_workflow.etl_workflow" "projects/$ProjectId/locations/$Region/workflows/nazimz-etl-workflow" { Gcloud-Exists @("workflows", "describe", "nazimz-etl-workflow", "--location=$Region", "--project=$ProjectId") }
Import-IfExists "google_eventarc_trigger.bucket_trigger" "projects/$ProjectId/locations/$Region/triggers/gcs-bucket-trigger" { Gcloud-Exists @("eventarc", "triggers", "describe", "gcs-bucket-trigger", "--location=$Region", "--project=$ProjectId") }
Import-IfExists "google_cloud_scheduler_job.monthly_scraper_trigger" "projects/$ProjectId/locations/$Region/jobs/monthly-scraper-trigger" { Gcloud-Exists @("scheduler", "jobs", "describe", "monthly-scraper-trigger", "--location=$Region", "--project=$ProjectId") }

Import-IfExists "google_bigquery_dataset.employment_analytics" "projects/$ProjectId/datasets/$DatasetId" { Bq-Exists "$ProjectId`:$DatasetId" }
foreach ($table in @("raw_bls_observation", "raw_usajobs_posting", "raw_adzuna_posting")) {
  Import-IfExists "google_bigquery_table.raw_tables[`"$table`"]" "projects/$ProjectId/datasets/$DatasetId/tables/$table" { Bq-Exists "$ProjectId`:$DatasetId.$table" }
}
foreach ($table in @("dim_source_system", "dim_time_period", "dim_location", "dim_occupation", "dim_industry", "dim_employer", "xref_occupation", "xref_industry", "curated_labor_metric", "curated_bls_series", "fact_labor_observation", "fact_job_posting")) {
  Import-IfExists "google_bigquery_table.transformed_tables[`"$table`"]" "projects/$ProjectId/datasets/$DatasetId/tables/$table" { Bq-Exists "$ProjectId`:$DatasetId.$table" }
}
Import-IfExists "google_bigquery_routine.sp_transform_bls" "projects/$ProjectId/datasets/$DatasetId/routines/sp_transform_bls" { Bq-Exists "$ProjectId`:$DatasetId.sp_transform_bls" }
Import-IfExists "google_bigquery_routine.sp_transform_usajobs" "projects/$ProjectId/datasets/$DatasetId/routines/sp_transform_usajobs" { Bq-Exists "$ProjectId`:$DatasetId.sp_transform_usajobs" }
Import-IfExists "google_bigquery_routine.sp_transform_adzuna" "projects/$ProjectId/datasets/$DatasetId/routines/sp_transform_adzuna" { Bq-Exists "$ProjectId`:$DatasetId.sp_transform_adzuna" }

foreach ($trigger in @(
  @{ Address = "google_cloudbuild_trigger.scraper_trigger"; Name = "scraper-build-deploy" },
  @{ Address = "google_cloudbuild_trigger.loader_trigger"; Name = "loader-build-deploy" },
  @{ Address = "google_cloudbuild_trigger.streamlit_trigger"; Name = "streamlit-build-deploy" }
)) {
  $triggerId = Out $GcloudBin @("builds", "triggers", "list", "--project=$ProjectId", "--region=$Region", "--filter=name=$($trigger.Name)", "--format=value(id)")
  if ($triggerId) {
    Import-IfExists $trigger.Address "projects/$ProjectId/locations/$Region/triggers/$triggerId" { $true }
  } else {
    Write-Host "SKIP missing: $($trigger.Address)"
  }
}

Write-Host "Live resource import pass complete. Run terraform plan next and review any remaining creates/updates."




