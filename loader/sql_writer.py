import pymysql
import pymysql.cursors

TABLE_COLUMNS = {
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
    "fact_labor_observation": ["labor_observation_id", "bls_series_id", "time_id", "source_id", "metric_id", "observation_value", "observation_date", "source_series_key", "seasonal_adjustment_flag", "supersector_code", "calendar_date", "year", "month", "period_type"],
    "fact_job_posting": ["job_posting_id", "source_id", "source_posting_key", "posting_url", "job_title", "job_description", "employment_type", "remote_type", "posted_time_id", "closing_time_id", "location_id", "employer_id", "occupation_id", "industry_id", "salary_min", "salary_max", "salary_currency", "salary_interval", "required_experience_level", "source_status", "security_clearance_required", "work_schedule", "posted_date"],
}
PRIMARY_KEYS = {
    "dim_source_system": ["source_id"],
    "dim_time_period": ["time_id"],
    "dim_location": ["location_id"],
    "dim_occupation": ["occupation_id"],
    "dim_industry": ["industry_id"],
    "dim_employer": ["employer_id"],
    "xref_occupation": ["xref_occupation_id"],
    "xref_industry": ["xref_industry_id"],
    "curated_labor_metric": ["metric_id"],
    "curated_bls_series": ["bls_series_id"],
    "fact_labor_observation": ["labor_observation_id"],
    "fact_job_posting": ["job_posting_id"],
}
UPSERT_ORDER = [
    "dim_source_system",
    "dim_time_period",
    "dim_location",
    "dim_occupation",
    "dim_industry",
    "dim_employer",
    "xref_occupation",
    "xref_industry",
    "curated_labor_metric",
    "curated_bls_series",
    "fact_labor_observation",
    "fact_job_posting",
]


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


def ensure_schema(conn: pymysql.Connection) -> None:
    statements = [
        """
        CREATE TABLE IF NOT EXISTS dim_source_system (
            source_id VARCHAR(64) NOT NULL,
            source_name VARCHAR(255) NOT NULL,
            PRIMARY KEY (source_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS dim_time_period (
            time_id VARCHAR(32) NOT NULL,
            calendar_date DATE NULL,
            year INT NULL,
            quarter INT NULL,
            month INT NULL,
            week INT NULL,
            period_type VARCHAR(32) NULL,
            PRIMARY KEY (time_id),
            KEY idx_time_calendar_date (calendar_date)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS dim_location (
            location_id VARCHAR(64) NOT NULL,
            country_code VARCHAR(16) NULL,
            state_code VARCHAR(32) NULL,
            city_name VARCHAR(255) NULL,
            postal_code VARCHAR(32) NULL,
            metro_code VARCHAR(64) NULL,
            latitude DOUBLE NULL,
            longitude DOUBLE NULL,
            PRIMARY KEY (location_id),
            KEY idx_location_state_country (state_code, country_code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS dim_occupation (
            occupation_id VARCHAR(64) NOT NULL,
            standard_system VARCHAR(64) NULL,
            standard_code VARCHAR(64) NULL,
            occupation_title VARCHAR(255) NULL,
            PRIMARY KEY (occupation_id),
            KEY idx_occupation_code (standard_system, standard_code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS dim_industry (
            industry_id VARCHAR(64) NOT NULL,
            classification_system VARCHAR(64) NULL,
            industry_code VARCHAR(64) NULL,
            industry_name VARCHAR(255) NULL,
            PRIMARY KEY (industry_id),
            KEY idx_industry_code (classification_system, industry_code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS dim_employer (
            employer_id VARCHAR(64) NOT NULL,
            employer_name VARCHAR(255) NULL,
            normalized_employer_name VARCHAR(255) NULL,
            employer_type VARCHAR(64) NULL,
            PRIMARY KEY (employer_id),
            KEY idx_employer_name (normalized_employer_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS xref_occupation (
            xref_occupation_id VARCHAR(64) NOT NULL,
            source_id VARCHAR(64) NULL,
            source_occupation_code VARCHAR(128) NULL,
            source_occupation_title VARCHAR(255) NULL,
            occupation_id VARCHAR(64) NULL,
            PRIMARY KEY (xref_occupation_id),
            KEY idx_xref_occupation_source (source_id, source_occupation_code),
            KEY idx_xref_occupation_id (occupation_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS xref_industry (
            xref_industry_id VARCHAR(64) NOT NULL,
            source_id VARCHAR(64) NULL,
            source_industry_code VARCHAR(128) NULL,
            source_industry_name VARCHAR(255) NULL,
            industry_id VARCHAR(64) NULL,
            PRIMARY KEY (xref_industry_id),
            KEY idx_xref_industry_source (source_id, source_industry_code),
            KEY idx_xref_industry_id (industry_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS curated_labor_metric (
            metric_id VARCHAR(128) NOT NULL,
            metric_name VARCHAR(255) NULL,
            unit_of_measure VARCHAR(128) NULL,
            metric_category VARCHAR(128) NULL,
            PRIMARY KEY (metric_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS curated_bls_series (
            bls_series_id VARCHAR(64) NOT NULL,
            source_series_key VARCHAR(64) NULL,
            metric_id VARCHAR(128) NULL,
            industry_id VARCHAR(64) NULL,
            occupation_id VARCHAR(64) NULL,
            location_id VARCHAR(64) NULL,
            seasonal_adjustment_flag BOOLEAN NULL,
            supersector_code VARCHAR(32) NULL,
            area_type VARCHAR(64) NULL,
            notes TEXT NULL,
            PRIMARY KEY (bls_series_id),
            KEY idx_bls_metric_sector (metric_id, supersector_code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS fact_labor_observation (
            labor_observation_id VARCHAR(64) NOT NULL,
            bls_series_id VARCHAR(64) NULL,
            time_id VARCHAR(32) NULL,
            source_id VARCHAR(64) NULL,
            metric_id VARCHAR(128) NULL,
            observation_value DECIMAL(18, 4) NULL,
            observation_date DATE NULL,
            source_series_key VARCHAR(64) NULL,
            seasonal_adjustment_flag BOOLEAN NULL,
            supersector_code VARCHAR(32) NULL,
            calendar_date DATE NULL,
            year INT NULL,
            month INT NULL,
            period_type VARCHAR(32) NULL,
            PRIMARY KEY (labor_observation_id),
            UNIQUE KEY uq_labor_series_time (bls_series_id, time_id),
            KEY idx_labor_observation_date (observation_date),
            KEY idx_labor_metric_sector (metric_id, supersector_code)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
        """
        CREATE TABLE IF NOT EXISTS fact_job_posting (
            job_posting_id VARCHAR(64) NOT NULL,
            source_id VARCHAR(64) NULL,
            source_posting_key VARCHAR(255) NULL,
            posting_url TEXT NULL,
            job_title TEXT NULL,
            job_description MEDIUMTEXT NULL,
            employment_type VARCHAR(128) NULL,
            remote_type VARCHAR(128) NULL,
            posted_time_id VARCHAR(32) NULL,
            closing_time_id VARCHAR(32) NULL,
            location_id VARCHAR(64) NULL,
            employer_id VARCHAR(64) NULL,
            occupation_id VARCHAR(64) NULL,
            industry_id VARCHAR(64) NULL,
            salary_min DECIMAL(18, 2) NULL,
            salary_max DECIMAL(18, 2) NULL,
            salary_currency VARCHAR(16) NULL,
            salary_interval VARCHAR(32) NULL,
            required_experience_level VARCHAR(128) NULL,
            source_status VARCHAR(128) NULL,
            security_clearance_required BOOLEAN NULL,
            work_schedule VARCHAR(128) NULL,
            posted_date DATE NULL,
            PRIMARY KEY (job_posting_id),
            UNIQUE KEY uq_job_source_key (source_id, source_posting_key),
            KEY idx_job_posted_date (posted_date),
            KEY idx_job_source (source_id),
            KEY idx_job_market_dims (occupation_id, industry_id, location_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """,
    ]
    with conn.cursor() as cur:
        for statement in statements:
            cur.execute(statement)
    conn.commit()


def _q(identifier: str) -> str:
    return f"`{identifier}`"


def upsert_rows(conn: pymysql.Connection, table: str, rows: list[dict]) -> int:
    if not rows:
        return 0
    columns = TABLE_COLUMNS[table]
    keys = set(PRIMARY_KEYS[table])
    insert_columns = ", ".join(_q(column) for column in columns)
    value_columns = ", ".join(f"%({column})s" for column in columns)
    update_columns = [column for column in columns if column not in keys]
    update_sql = ",\n            ".join(f"{_q(column)} = VALUES({_q(column)})" for column in update_columns)
    sql = f"""
        INSERT INTO {_q(table)}
            ({insert_columns})
        VALUES
            ({value_columns})
        ON DUPLICATE KEY UPDATE
            {update_sql}
    """
    clean_rows = [{column: row.get(column) for column in columns} for row in rows]
    with conn.cursor() as cur:
        cur.executemany(sql, clean_rows)
    conn.commit()
    return len(clean_rows)


def write(host: str, db_name: str, user: str, password: str, raw_table: str, snapshot: dict[str, list[dict]]) -> int:
    """Connect and upsert a BigQuery serving snapshot into Cloud SQL."""
    conn = _get_connection(host, db_name, user, password)
    try:
        ensure_schema(conn)
        written = 0
        for table in UPSERT_ORDER:
            written += upsert_rows(conn, table, snapshot.get(table, []))
        return written
    finally:
        conn.close()
