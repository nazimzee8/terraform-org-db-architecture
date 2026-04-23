import os
import sys
from datetime import datetime, timezone

import bls_client
import usajobs_client
import adzuna_client
import gcs_writer


def main() -> int:
    task_index = int(os.environ.get("CLOUD_RUN_TASK_INDEX", "0"))

    bucket = os.environ["INGESTION_BUCKET"]
    today = datetime.now(timezone.utc).strftime("%Y%m%d")

    if task_index == 0:
        # BLS
        bls_api_key = os.environ["BLS_API_KEY"]
        try:
            print("Fetching BLS data...")
            data = bls_client.fetch(bls_api_key)
            gcs_writer.upload_to_gcs(bucket, f"raw/bls/bls_{today}.csv", data, "text/csv")
            print(f"BLS: uploaded {len(data)} bytes")
        except Exception as exc:
            print(f"ERROR [BLS]: {exc}", file=sys.stderr)
            return 1

    elif task_index == 1:
        # USAJobs
        api_key  = os.environ["USAJOBS_API_KEY"]
        email    = os.environ["USAJOBS_USER_EMAIL"]
        keywords = [k.strip() for k in os.environ.get("KEYWORDS", "").split(",") if k.strip()]
        try:
            print("Fetching USAJobs data...")
            data = usajobs_client.fetch(api_key, email, keywords)
            gcs_writer.upload_to_gcs(bucket, f"raw/usajobs/usajobs_{today}.json", data, "application/x-ndjson")
            print(f"USAJobs: uploaded {len(data)} bytes")
        except Exception as exc:
            print(f"ERROR [USAJobs]: {exc}", file=sys.stderr)
            return 1

    elif task_index == 2:
        # Adzuna
        app_id   = os.environ["ADZUNA_APP_ID"]
        app_key  = os.environ["ADZUNA_APP_KEY"]
        country  = os.environ.get("ADZUNA_COUNTRY", "us")
        keywords = [k.strip() for k in os.environ.get("KEYWORDS", "").split(",") if k.strip()]
        try:
            print("Fetching Adzuna data...")
            data = adzuna_client.fetch(app_id, app_key, country, keywords)
            gcs_writer.upload_to_gcs(bucket, f"raw/adzuna/adzuna_{today}.json", data, "application/x-ndjson")
            print(f"Adzuna: uploaded {len(data)} bytes")
        except Exception as exc:
            print(f"ERROR [Adzuna]: {exc}", file=sys.stderr)
            return 1

    else:
        print(f"Unknown CLOUD_RUN_TASK_INDEX={task_index}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
