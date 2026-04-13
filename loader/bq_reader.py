from google.cloud import bigquery

LABOR_LOOKBACK_MONTHS = 24
POSTING_LOOKBACK_MONTHS = 18
DIMENSION_TABLES = {
    "dim_source_system": ["source_id", "source_name"],
    "dim_time_period": ["time_id", "calendar_date", "year", "quarter", "month", "week", "period_type"],
    "dim_location": ["location_id", "country_code", "state_code", "city_name", "postal_code", "metro_code", "latitude", "longitude"],
    "dim_occupation": ["occupation_id", "standard_system", "standard_code", "occupation_title"],
    "dim_industry": ["industry_id", "classification_system", "industry_code", "industry_name"],
    "dim_employer": ["employer_id", "employer_name", "normalized_employer_name", "employer_type"],
    "xref_occupation": ["xref_occupation_id", "source_id", "source_occupation_code", "source_occupation_title", "occupation_id"],
    "xref_industry": ["xref_industry_id", "source_id", "source_industry_code", "source_industry_name", "industry_id"],
    "curated_labor_metric": ["metric_id", "metric_name", "unit_of_measure", "metric_category"],
    "curated_bls_series": ["bls_series_id", "source_series_key", "metric_id", "industry_id", "occupation_id", "location_id", "seasonal_adjustment_flag", "supersector_code", "area_type", "notes"],
}


def _query(client: bigquery.Client, sql: str) -> list[dict]:
    job = client.query(sql)
    return [dict(row) for row in job.result()]


def query_dimension(client: bigquery.Client, project: str, dataset: str, table: str, columns: list[str]) -> list[dict]:
    column_sql = ",\n            ".join(f"`{column}`" for column in columns)
    id_column = columns[0]
    sql = f"""
        SELECT
            {column_sql}
        FROM `{project}.{dataset}.{table}`
        WHERE `{id_column}` IS NOT NULL
    """
    return _query(client, sql)


def query_bls(client: bigquery.Client, project: str, dataset: str) -> list[dict]:
    """Query recent BLS labor observations joined with series and time dimension."""
    sql = f"""
        SELECT
            f.labor_observation_id,
            f.bls_series_id,
            f.time_id,
            f.source_id,
            f.metric_id,
            CAST(f.observation_value AS FLOAT64) AS observation_value,
            f.observation_date,
            s.source_series_key,
            s.seasonal_adjustment_flag,
            s.supersector_code,
            t.calendar_date,
            t.year,
            t.month,
            t.period_type
        FROM `{project}.{dataset}.fact_labor_observation` f
        LEFT JOIN `{project}.{dataset}.curated_bls_series` s
            ON f.bls_series_id = s.bls_series_id
        LEFT JOIN `{project}.{dataset}.dim_time_period` t
            ON f.time_id = t.time_id
        WHERE f.observation_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {LABOR_LOOKBACK_MONTHS} MONTH)
    """
    return _query(client, sql)


def query_job_postings(client: bigquery.Client, project: str, dataset: str) -> list[dict]:
    """Query recent job postings from fact_job_posting."""
    sql = f"""
        SELECT
            job_posting_id,
            source_id,
            source_posting_key,
            posting_url,
            job_title,
            job_description,
            employment_type,
            remote_type,
            posted_time_id,
            closing_time_id,
            location_id,
            employer_id,
            occupation_id,
            industry_id,
            CAST(salary_min AS FLOAT64) AS salary_min,
            CAST(salary_max AS FLOAT64) AS salary_max,
            salary_currency,
            salary_interval,
            required_experience_level,
            source_status,
            security_clearance_required,
            work_schedule,
            posted_date
        FROM `{project}.{dataset}.fact_job_posting`
        WHERE posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL {POSTING_LOOKBACK_MONTHS} MONTH)
    """
    return _query(client, sql)


def read(project: str, dataset: str, raw_table: str) -> dict[str, list[dict]]:
    """Return a Cloud SQL serving snapshot for the dashboard."""
    client = bigquery.Client(project=project)
    if raw_table not in ("raw_bls_observation", "raw_usajobs_posting", "raw_adzuna_posting"):
        raise ValueError(f"Unknown raw_table: {raw_table}")

    snapshot = {
        table: query_dimension(client, project, dataset, table, columns)
        for table, columns in DIMENSION_TABLES.items()
    }
    snapshot["fact_labor_observation"] = query_bls(client, project, dataset)
    snapshot["fact_job_posting"] = query_job_postings(client, project, dataset)
    return snapshot
