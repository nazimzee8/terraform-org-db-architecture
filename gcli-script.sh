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

gcloud projects get-iam-policy nazimz-database --format=json > policy.json

gcloud projects set-iam-policy nazimz-database policy.json

gcloud services enable secretmanager.googleapis.com

gcloud secrets create db-password \
  --replication-policy="automatic"

echo -n "nazimz-db-passwd" > db-credentials.txt | gcloud secrets versions add db-password --data-file=db-credentials.txt

gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:sa-db-loader@nazimz-database.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"


