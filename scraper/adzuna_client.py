import json
import os
import uuid
from datetime import datetime, timezone

import requests

ADZUNA_BASE_URL = "https://api.adzuna.com/v1/api/jobs/{country}/search/{page}"
MAX_PAGES_PER_KEYWORD = 20
RESULTS_PER_PAGE = 50


def fetch(app_id: str, app_key: str, country: str, keywords: list[str]) -> bytes:
    """Fetch Adzuna job postings for all keywords and return NDJSON bytes."""
    seen_ids: set[str] = set()
    retrieved_at = datetime.now(timezone.utc).isoformat()
    lines: list[bytes] = []

    for keyword in keywords:
        for page in range(1, MAX_PAGES_PER_KEYWORD + 1):
            url = ADZUNA_BASE_URL.format(country=country, page=page)
            params = {
                "app_id": app_id,
                "app_key": app_key,
                "results_per_page": RESULTS_PER_PAGE,
                "what": keyword,
                "content-type": "application/json",
            }
            response = requests.get(url, params=params, timeout=60)
            if response.status_code == 404:
                break
            response.raise_for_status()
            data = response.json()

            results = data.get("results", [])
            if not results:
                break

            for job in results:
                job_id = str(job.get("id", ""))
                if not job_id or job_id in seen_ids:
                    continue
                seen_ids.add(job_id)

                record = {
                    "raw_adzuna_id": str(uuid.uuid4()),
                    "source_id": "adzuna",
                    "source_posting_key": job_id,
                    "retrieved_at": retrieved_at,
                    "raw_payload": json.dumps(job),
                }
                lines.append(json.dumps(record).encode("utf-8"))

    return b"\n".join(lines)
