from google.cloud import bigquery


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
        WHERE f.observation_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
    """
    job = client.query(sql)
    return [dict(row) for row in job.result()]


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
        WHERE posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
    """
    job = client.query(sql)
    return [dict(row) for row in job.result()]


def read(project: str, dataset: str, raw_table: str) -> list[dict]:
    """Route to the correct query based on raw_table name."""
    client = bigquery.Client(project=project)
    if raw_table == "raw_bls_observation":
        return query_bls(client, project, dataset)
    elif raw_table in ("raw_usajobs_posting", "raw_adzuna_posting"):
        return query_job_postings(client, project, dataset)
    else:
        raise ValueError(f"Unknown raw_table: {raw_table}")
