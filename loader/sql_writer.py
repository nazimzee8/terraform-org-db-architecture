import pymysql
import pymysql.cursors


def _get_connection(host: str, db_name: str, user: str, password: str) -> pymysql.Connection:
    return pymysql.connect(
        host=host,
        user=user,
        password=password,
        database=db_name,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=10,
    )


def upsert_bls_rows(conn: pymysql.Connection, rows: list[dict]) -> int:
    if not rows:
        return 0
    sql = """
        INSERT INTO fact_labor_observation
            (labor_observation_id, bls_series_id, time_id, source_id, metric_id,
             observation_value, observation_date, source_series_key,
             seasonal_adjustment_flag, supersector_code, calendar_date, year, month, period_type)
        VALUES
            (%(labor_observation_id)s, %(bls_series_id)s, %(time_id)s, %(source_id)s,
             %(metric_id)s, %(observation_value)s, %(observation_date)s, %(source_series_key)s,
             %(seasonal_adjustment_flag)s, %(supersector_code)s, %(calendar_date)s,
             %(year)s, %(month)s, %(period_type)s)
        ON DUPLICATE KEY UPDATE
            observation_value = VALUES(observation_value),
            metric_id = VALUES(metric_id)
    """
    with conn.cursor() as cur:
        cur.executemany(sql, rows)
    conn.commit()
    return len(rows)


def upsert_job_posting_rows(conn: pymysql.Connection, rows: list[dict]) -> int:
    if not rows:
        return 0
    sql = """
        INSERT INTO fact_job_posting
            (job_posting_id, source_id, source_posting_key, posting_url, job_title,
             job_description, employment_type, remote_type, posted_time_id, closing_time_id,
             location_id, employer_id, occupation_id, industry_id, salary_min, salary_max,
             salary_currency, salary_interval, required_experience_level, source_status,
             security_clearance_required, work_schedule, posted_date)
        VALUES
            (%(job_posting_id)s, %(source_id)s, %(source_posting_key)s, %(posting_url)s,
             %(job_title)s, %(job_description)s, %(employment_type)s, %(remote_type)s,
             %(posted_time_id)s, %(closing_time_id)s, %(location_id)s, %(employer_id)s,
             %(occupation_id)s, %(industry_id)s, %(salary_min)s, %(salary_max)s,
             %(salary_currency)s, %(salary_interval)s, %(required_experience_level)s,
             %(source_status)s, %(security_clearance_required)s, %(work_schedule)s,
             %(posted_date)s)
        ON DUPLICATE KEY UPDATE
            job_title = VALUES(job_title),
            salary_min = VALUES(salary_min),
            salary_max = VALUES(salary_max),
            source_status = VALUES(source_status)
    """
    with conn.cursor() as cur:
        cur.executemany(sql, rows)
    conn.commit()
    return len(rows)


def write(host: str, db_name: str, user: str, password: str, raw_table: str, rows: list[dict]) -> int:
    """Connect and upsert rows into the appropriate Cloud SQL table."""
    conn = _get_connection(host, db_name, user, password)
    try:
        if raw_table == "raw_bls_observation":
            return upsert_bls_rows(conn, rows)
        else:
            return upsert_job_posting_rows(conn, rows)
    finally:
        conn.close()
