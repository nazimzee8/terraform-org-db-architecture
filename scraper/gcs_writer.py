import io
import json
import logging
from datetime import datetime, timezone

from google.cloud import storage

logger = logging.getLogger(__name__)


def upload_to_gcs(bucket_name: str, object_path: str, data: bytes, content_type: str) -> None:
    """Upload in-memory bytes to GCS. No local disk I/O."""
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_path)
    blob.upload_from_file(io.BytesIO(data), content_type=content_type)
    log_entry = {
        "severity": "INFO",
        "message": "GCS upload successful",
        "bucket": bucket_name,
        "object": object_path,
        "bytes": len(data),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    print(json.dumps(log_entry))
