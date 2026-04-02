import os
import pymysql
import pandas as pd
import streamlit as st

# --- lazy connection (initialized on first query, not at import time) --------
_conn = None


def _get_conn():
    global _conn
    if _conn is None or not _conn.open:
        _conn = pymysql.connect(
            host=os.environ["DB_HOST"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            database=os.environ["DB_NAME"],
            port=int(os.getenv("DB_PORT", 3306)),
            cursorclass=pymysql.cursors.DictCursor,
        )
    return _conn


# --- data functions ----------------------------------------------------------
@st.cache_data(ttl=3600)
def fetch_labor_trends():
    conn = _get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT
                observation_date,
                metric_id,
                bls_series_id,
                observation_value
            FROM fact_labor_observation
            ORDER BY observation_date DESC
            LIMIT 1000
            """
        )
        rows = cur.fetchall()
    return pd.DataFrame(rows)


@st.cache_data(ttl=3600)
def fetch_job_postings():
    conn = _get_conn()
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT
                job_title,
                source_id,
                posted_date,
                salary_min,
                salary_max,
                work_schedule
            FROM fact_job_posting
            ORDER BY posted_date DESC
            LIMIT 500
            """
        )
        rows = cur.fetchall()
    return pd.DataFrame(rows)


# --- UI ----------------------------------------------------------------------
st.set_page_config(page_title="Employment Analytics", layout="wide")
st.title("Employment Analytics Dashboard")

tab1, tab2 = st.tabs(["Labor Trends", "Job Postings"])

with tab1:
    st.subheader("BLS Labor Observations")
    try:
        df = fetch_labor_trends()
        if df.empty:
            st.info("No labor data available yet.")
        else:
            metrics = df["metric_id"].unique().tolist()
            selected = st.selectbox("Metric", metrics)
            filtered = df[df["metric_id"] == selected].copy()
            filtered["observation_date"] = pd.to_datetime(filtered["observation_date"])
            filtered = filtered.sort_values("observation_date")
            st.line_chart(filtered.set_index("observation_date")["observation_value"])
            st.dataframe(filtered, use_container_width=True)
    except Exception as e:
        st.error(f"Could not load labor trends: {e}")

with tab2:
    st.subheader("Job Postings")
    try:
        df = fetch_job_postings()
        if df.empty:
            st.info("No job postings available yet.")
        else:
            sources = ["All"] + sorted(df["source_id"].dropna().unique().tolist())
            source = st.selectbox("Source", sources)
            if source != "All":
                df = df[df["source_id"] == source]
            st.dataframe(df, use_container_width=True)
    except Exception as e:
        st.error(f"Could not load job postings: {e}")
