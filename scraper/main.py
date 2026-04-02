import os
import sys
from datetime import datetime, timezone

import bls_client
import usajobs_client
import adzuna_client
import gcs_writer


def main() -> int:
    # Env vars injected by Cloud Run (plain values + Secret Manager refs)
    bucket = os.environ["INGESTION_BUCKET"]
    bls_api_key = os.environ["BLS_API_KEY"]
    usajobs_api_key = os.environ["USAJOBS_API_KEY"]
    usajobs_user_email = os.environ["USAJOBS_USER_EMAIL"]
    adzuna_app_id = os.environ["ADZUNA_APP_ID"]
    adzuna_app_key = os.environ["ADZUNA_APP_KEY"]
    adzuna_country = os.environ.get("ADZUNA_COUNTRY", "us")
    keywords_raw = os.environ.get("KEYWORDS", "")
    keywords = [k.strip() for k in keywords_raw.split(",") if k.strip()]

    today = datetime.now(timezone.utc).strftime("%Y%m%d")
    success = True

    # --- BLS ---
    try:
        print("Fetching BLS data...")
        bls_data = bls_client.fetch(bls_api_key)
        gcs_writer.upload_to_gcs(
            bucket,
            f"raw/bls/bls_{today}.csv",
            bls_data,
            "text/csv",
        )
        print(f"BLS: uploaded {len(bls_data)} bytes")
    except Exception as exc:
        print(f"ERROR [BLS]: {exc}", file=sys.stderr)
        success = False

    # --- USAJobs ---
    try:
        print("Fetching USAJobs data...")
        usajobs_data = usajobs_client.fetch(usajobs_api_key, usajobs_user_email, keywords)
        gcs_writer.upload_to_gcs(
            bucket,
            f"raw/usajobs/usajobs_{today}.json",
            usajobs_data,
            "application/x-ndjson",
        )
        print(f"USAJobs: uploaded {len(usajobs_data)} bytes")
    except Exception as exc:
        print(f"ERROR [USAJobs]: {exc}", file=sys.stderr)
        success = False

    # --- Adzuna ---
    try:
        print("Fetching Adzuna data...")
        adzuna_data = adzuna_client.fetch(adzuna_app_id, adzuna_app_key, adzuna_country, keywords)
        gcs_writer.upload_to_gcs(
            bucket,
            f"raw/adzuna/adzuna_{today}.json",
            adzuna_data,
            "application/x-ndjson",
        )
        print(f"Adzuna: uploaded {len(adzuna_data)} bytes")
    except Exception as exc:
        print(f"ERROR [Adzuna]: {exc}", file=sys.stderr)
        success = False

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
