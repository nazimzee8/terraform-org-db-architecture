import io
import json
import os
import uuid
from datetime import datetime, timezone

import requests

USAJOBS_API_URL = "https://data.usajobs.gov/api/search"


def fetch(api_key: str, user_email: str, keywords: list[str]) -> bytes:
    """Fetch USAJobs postings for all keywords and return NDJSON bytes."""
    headers = {
        "Authorization-Key": api_key,
        "User-Agent": user_email,
        "Host": "data.usajobs.gov",
    }

    seen_ids: set[str] = set()
    retrieved_at = datetime.now(timezone.utc).isoformat()
    lines: list[bytes] = []

    for keyword in keywords:
        page = 1
        total_fetched = 0
        total_available = None

        while True:
            params = {
                "Keyword": keyword,
                "ResultsPerPage": 500,
                "Page": page,
                "Fields": "Min",
            }
            response = requests.get(USAJOBS_API_URL, headers=headers, params=params, timeout=60)
            response.raise_for_status()
            data = response.json()

            search_result = data.get("SearchResult", {})
            if total_available is None:
                total_available = int(search_result.get("SearchResultCountAll", 0))

            items = search_result.get("SearchResultItems", [])
            if not items:
                break

            for item in items:
                descriptor = item.get("MatchedObjectDescriptor", {})
                posting_id = descriptor.get("MatchedObjectId") or item.get("MatchedObjectId")
                if not posting_id or posting_id in seen_ids:
                    continue
                seen_ids.add(posting_id)

                record = {
                    "raw_usajobs_id": str(uuid.uuid4()),
                    "source_id": "usajobs",
                    "source_posting_key": posting_id,
                    "retrieved_at": retrieved_at,
                    "raw_payload": json.dumps(descriptor),
                }
                lines.append(json.dumps(record).encode("utf-8"))

            total_fetched += len(items)
            if total_fetched >= total_available:
                break
            page += 1

    return b"\n".join(lines)
