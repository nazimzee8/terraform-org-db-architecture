#!/bin/bash
gcloud projects create nazimz-database
gcloud config set project nazimz-database
gcloud config configurations list
gcloud config configurations activate cloudshell-21976

gcloud iam service-accounts create sa-scraper-runjob \
	--display-name="Scraping Job Service Account" \
	--description="Service account used for automated scraping."

gcloud iam service-accounts create sa-db-loader \
	--display-name="Loading Data Service Account" \
	--description="Service account used for reading data from BigQuery and loading into private db."

gcloud iam service-accounts create sa-scheduler \
	--display-name="Job Scheduler Service Account" \
	--description="Service account triggering our scraping job to occur hourly."

gcloud iam service-accounts create sa-manager-infra \
	--display-name="Database Management Service Account" \
	--description="Service account used creating the network connections and managing the database."

gcloud iam service-accounts create sa-secret-manager \
	--display-name="Secret Manager Service Account" \
	--description="Service account used for managing secrets in Secret Manager for this ETL pipeline."

gcloud iam service-accounts create sa-data-workflow \
	--display-name="Data Workflow Service Account" \
	--description="Service account used for managing the data workflow for this ETL pipeline."

gcloud iam service-accounts create sa-app-account \
	--display-name="Application Account Service Account" \
	--description="Service account used for managing the streamlit app for this infrastructure."

gcloud iam service-accounts create sa-app-deployer \
	--display-name="Application Deployer Service Account" \
	--description="Service account used for deploying the service container hosting the streamlit app for this infrastructure."

gcloud projects get-iam-policy nazimz-database --format=json > policy.json

gcloud services enable secretmanager.googleapis.com

gcloud builds submit . --config=streamlit/cloudbuild.yaml --region=us-west2
gcloud builds submit . --config=loader/cloudbuild.yaml --region=us-west2
gcloud builds submit . --config=scraper/cloudbuild.yaml --region=us-west2

gcloud projects set-iam-policy nazimz-database policy.json
gcloud services enable run.googleapis.com vpcaccess.googleapis.com bigquery.googleapis.com storage.googleapis.com