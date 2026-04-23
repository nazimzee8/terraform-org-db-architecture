import json
import os
import random
import sys
import time
import uuid
from datetime import datetime, timezone

import requests

ADZUNA_BASE_URL = "https://api.adzuna.com/v1/api/jobs/{country}/search/{page}"
MAX_PAGES_PER_KEYWORD = 20
RESULTS_PER_PAGE = 50

_RATE_LIMIT_RETRIES = 3
_RATE_LIMIT_BASE_DELAY = 60   # seconds; full-jitter applied on each retry
_PAGE_DELAY = 1.0             # seconds between page requests (baseline throttle)


def _get_page(session: requests.Session, url: str, params: dict) -> requests.Response | None:
    """GET one page. Retries with full-jitter exponential backoff on 429.
    Returns None when retries are exhausted."""
    delay = _RATE_LIMIT_BASE_DELAY
    for attempt in range(_RATE_LIMIT_RETRIES + 1):
        response = session.get(url, params=params, timeout=60)
        if response.status_code == 429:
            if attempt < _RATE_LIMIT_RETRIES:
                jittered = random.uniform(0, delay)
                print(
                    f"Adzuna rate limited (attempt {attempt + 1}/{_RATE_LIMIT_RETRIES}),"
                    f" retrying in {jittered:.1f}s...",
                    flush=True,
                )
                time.sleep(jittered)
                delay *= 2
                continue
            print(
                f"WARNING: Adzuna rate limit exhausted after {_RATE_LIMIT_RETRIES} retries,"
                " skipping remaining pages for this keyword.",
                file=sys.stderr,
            )
            return None
        if response.status_code == 404:
            return response  # caller checks 404
        response.raise_for_status()
        return response
    return None  # unreachable; satisfies type checker


def fetch(app_id: str, app_key: str, country: str, keywords: list[str]) -> bytes:
    """Fetch Adzuna job postings for all keywords and return NDJSON bytes."""
    seen_ids: set[str] = set()
    retrieved_at = datetime.now(timezone.utc).isoformat()
    lines: list[bytes] = []

    session = requests.Session()

    for keyword in keywords:
        for page in range(1, MAX_PAGES_PER_KEYWORD + 1):
            if page > 1:
                time.sleep(_PAGE_DELAY)

            url = ADZUNA_BASE_URL.format(country=country, page=page)
            params = {
                "app_id": app_id,
                "app_key": app_key,
                "results_per_page": RESULTS_PER_PAGE,
                "what": keyword,
                "content-type": "application/json",
            }

            response = _get_page(session, url, params)
            if response is None:           # rate limit exhausted
                break
            if response.status_code == 404:
                break

            results = response.json().get("results", [])
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
