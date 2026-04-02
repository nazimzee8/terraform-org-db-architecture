import csv
import io
import json
import os
import uuid
from datetime import datetime, timezone

import requests

BLS_API_URL = "https://api.bls.gov/publicAPI/v2/timeseries/data/"

BLS_SERIES = [
    "LNS14000000",   # National unemployment rate (U-3, seasonally adjusted)
    "LNU04032231",   # Professional & business services unemployment
    "LNU04023557",   # Manufacturing unemployment
    "CES0000000001", # Total nonfarm payroll
    "CES2000000001", # Construction employment
    "CES3000000001", # Manufacturing employment
    "CES4142000001", # Trade, transport & warehousing employment
    "CES5000000001", # Information sector employment
    "CES5500000001", # Financial activities employment
    "CES6000000001", # Professional & business services employment
    "CES6500000001", # Education & health services employment
    "CES7000000001", # Leisure & hospitality employment
    "CES9000000001", # Government employment
]

HEADER = [
    "raw_bls_id",
    "source_id",
    "source_series_key",
    "observation_year",
    "observation_period",
    "observation_value",
    "footnotes_json",
    "ingested_at",
    "raw_payload",
]


def fetch(api_key: str) -> bytes:
    """Fetch BLS data for all series and return CSV bytes."""
    end_year = datetime.now(timezone.utc).year
    start_year = end_year - 10  # BLS API v2 limit: max 10 years per request

    payload = {
        "seriesid": BLS_SERIES,
        "startyear": str(start_year),
        "endyear": str(end_year),
        "registrationkey": api_key,
    }
    response = requests.post(BLS_API_URL, json=payload, timeout=60)
    response.raise_for_status()
    result = response.json()

    if result.get("status") != "REQUEST_SUCCEEDED":
        raise RuntimeError(f"BLS API error: {result.get('message', result)}")

    ingested_at = datetime.now(timezone.utc).isoformat()
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=HEADER)
    writer.writeheader()

    for series in result.get("Results", {}).get("series", []):
        series_key = series["seriesID"]
        series_payload_str = json.dumps(series)
        for obs in series.get("data", []):
            footnotes = json.dumps(obs.get("footnotes", []))
            writer.writerow({
                "raw_bls_id": str(uuid.uuid4()),
                "source_id": "bls",
                "source_series_key": series_key,
                "observation_year": obs.get("year"),
                "observation_period": obs.get("period"),
                "observation_value": obs.get("value"),
                "footnotes_json": footnotes,
                "ingested_at": ingested_at,
                "raw_payload": series_payload_str,
            })

    return buf.getvalue().encode("utf-8")
