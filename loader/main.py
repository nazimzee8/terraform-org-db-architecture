import os
import sys

import bq_reader
import sql_writer


def main() -> int:
    project = os.environ["BQ_PROJECT_ID"]
    dataset = os.environ["BQ_DATASET_ID"]
    raw_table = os.environ["RAW_TABLE"]
    db_host = os.environ["DB_HOST"]
    db_name = os.environ["DB_NAME"]
    db_user = os.environ["DB_USER"]
    db_password = os.environ["DB_PASSWORD"]

    print(f"Loader starting: project={project} dataset={dataset} raw_table={raw_table}")

    try:
        print(f"Querying BigQuery for {raw_table}...")
        snapshot = bq_reader.read(project, dataset, raw_table)
        total_rows = sum(len(rows) for rows in snapshot.values())
        print(f"BigQuery returned {total_rows} rows across {len(snapshot)} serving tables")
    except Exception as exc:
        print(f"ERROR [BigQuery read]: {exc}", file=sys.stderr)
        return 1

    try:
        print(f"Writing {total_rows} rows to Cloud SQL ({db_host}/{db_name})...")
        written = sql_writer.write(db_host, db_name, db_user, db_password, raw_table, snapshot)
        print(f"Loader complete: {written} rows upserted")
    except Exception as exc:
        print(f"ERROR [Cloud SQL write]: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
