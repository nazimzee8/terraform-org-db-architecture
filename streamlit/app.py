from __future__ import annotations

import html
import os

import altair as alt
import pandas as pd
import pymysql
import pymysql.cursors
import streamlit as st

APP_TITLE = 'Employment Atlas'
DEFAULT_DB_PORT = 3306
LABOR_LOOKBACK_MONTHS = 24
POSTING_LOOKBACK_MONTHS = 18
NUMERIC_RESULT_COLUMNS = {
    'value',
    'observations',
    'previous_value',
    'year_ago_value',
    'postings',
    'avg_salary_mid',
    'clearance_postings',
    'remote_postings',
}
DATE_RESULT_COLUMNS = {'month'}

NAV_ITEMS = [
    ('Introduction', 'introduction'),
    ('Key Insights', 'key-insights'),
    ('Labor Market Trends', 'labor-market-trends'),
    ('Job Posting Demand', 'job-posting-demand'),
    ('Market Tension', 'market-tension'),
    ('Salary & Work Conditions', 'salary-work-conditions'),
    ('Methodology', 'methodology'),
]


def resolve_db_config() -> dict[str, object]:
    missing = [name for name in ('DB_HOST', 'DB_NAME', 'DB_USER', 'DB_PASSWORD') if not os.getenv(name)]
    if missing:
        raise RuntimeError(f'Missing Cloud SQL environment variables: {", ".join(missing)}')
    return {
        'host': os.environ['DB_HOST'],
        'port': int(os.getenv('DB_PORT', str(DEFAULT_DB_PORT))),
        'database': os.environ['DB_NAME'],
        'user': os.environ['DB_USER'],
        'password': os.environ['DB_PASSWORD'],
    }


@st.cache_data(ttl=900, show_spinner=False)
def run_query(sql: str, params: tuple[object, ...] = ()) -> pd.DataFrame:
    config = resolve_db_config()
    conn = pymysql.connect(
        host=str(config['host']),
        port=int(config['port']),
        user=str(config['user']),
        password=str(config['password']),
        database=str(config['database']),
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=10,
        read_timeout=30,
        write_timeout=30,
    )
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return normalize_query_frame(pd.DataFrame(cur.fetchall()))
    finally:
        conn.close()


def normalize_query_frame(df: pd.DataFrame) -> pd.DataFrame:
    for column in DATE_RESULT_COLUMNS.intersection(df.columns):
        df[column] = pd.to_datetime(df[column], errors='coerce')
    for column in NUMERIC_RESULT_COLUMNS.intersection(df.columns):
        df[column] = pd.to_numeric(df[column], errors='coerce')
    return df


def escape(value: object, fallback: str = 'n/a') -> str:
    if value is None:
        return fallback
    try:
        if pd.isna(value):
            return fallback
    except Exception:
        pass
    return html.escape(str(value))


def fmt_int(value: object, fallback: str = 'n/a') -> str:
    try:
        if value is None or pd.isna(value):
            return fallback
        return f'{float(value):,.0f}'
    except Exception:
        return fallback


def fmt_pct(value: object, fallback: str = 'n/a') -> str:
    try:
        if value is None or pd.isna(value):
            return fallback
        return f'{float(value):,.1f}%'
    except Exception:
        return fallback


def fmt_money(value: object, fallback: str = 'n/a') -> str:
    try:
        if value is None or pd.isna(value):
            return fallback
        return f'${float(value):,.0f}'
    except Exception:
        return fallback


def fmt_signed(value: object, suffix: str = '', fallback: str = 'n/a') -> str:
    try:
        if value is None or pd.isna(value):
            return fallback
        value = float(value)
        sign = '+' if value >= 0 else ''
        return f'{sign}{value:,.0f}{suffix}'
    except Exception:
        return fallback


def fmt_date(value: object, fallback: str = 'n/a') -> str:
    try:
        if value is None or pd.isna(value):
            return fallback
        return pd.to_datetime(value).date().isoformat()
    except Exception:
        return fallback


def weighted_average(df: pd.DataFrame, value_col: str, weight_col: str) -> float | None:
    frame = df[[value_col, weight_col]].dropna()
    if frame.empty:
        return None
    total = frame[weight_col].sum()
    if total == 0:
        return float(frame[value_col].mean())
    return float((frame[value_col] * frame[weight_col]).sum() / total)


def empty_frame(columns: list[str]) -> pd.DataFrame:
    return pd.DataFrame(columns=columns)


@st.cache_data(ttl=900, show_spinner=False)
def load_labor_monthly(months: int = LABOR_LOOKBACK_MONTHS) -> pd.DataFrame:
    sql = """
    WITH monthly AS (
      SELECT
        CAST(DATE_FORMAT(f.observation_date, '%%Y-%%m-01') AS DATE) AS month,
        COALESCE(NULLIF(TRIM(s.supersector_code), ''), NULLIF(TRIM(f.supersector_code), ''), 'ALL') AS sector_code,
        COALESCE(NULLIF(TRIM(m.metric_name), ''), NULLIF(TRIM(f.metric_id), ''), 'Other') AS metric_name,
        COALESCE(NULLIF(TRIM(m.metric_category), ''), NULLIF(TRIM(f.metric_id), ''), 'OTHER') AS metric_category,
        AVG(CAST(f.observation_value AS DECIMAL(18, 4))) AS value,
        COUNT(*) AS observations
      FROM fact_labor_observation f
      LEFT JOIN curated_bls_series s ON f.bls_series_id = s.bls_series_id
      LEFT JOIN curated_labor_metric m ON COALESCE(s.metric_id, f.metric_id) = m.metric_id
      WHERE f.observation_date >= DATE_SUB(CURDATE(), INTERVAL %s MONTH)
      GROUP BY 1, 2, 3, 4
    )
    SELECT
      month, sector_code, metric_name, metric_category, value, observations,
      LAG(value) OVER (PARTITION BY sector_code, metric_name ORDER BY month) AS previous_value,
      LAG(value, 12) OVER (PARTITION BY sector_code, metric_name ORDER BY month) AS year_ago_value
    FROM monthly
    ORDER BY month, sector_code, metric_name
    """
    return run_query(sql, (months,))


@st.cache_data(ttl=900, show_spinner=False)
def load_postings_rollup(months: int = POSTING_LOOKBACK_MONTHS) -> pd.DataFrame:
    sql = """
    WITH base AS (
      SELECT
        CAST(DATE_FORMAT(f.posted_date, '%%Y-%%m-01') AS DATE) AS month,
        COALESCE(NULLIF(TRIM(f.source_id), ''), 'unknown') AS source_id,
        COALESCE(NULLIF(TRIM(i.industry_name), ''), NULLIF(TRIM(f.industry_id), ''), 'Unmapped') AS industry_label,
        COALESCE(NULLIF(TRIM(o.occupation_title), ''), NULLIF(TRIM(f.occupation_id), ''), 'Unmapped') AS occupation_label,
        COALESCE(NULLIF(TRIM(f.remote_type), ''), 'Unknown') AS remote_type,
        COALESCE(NULLIF(TRIM(f.work_schedule), ''), 'Unknown') AS work_schedule,
        COALESCE(NULLIF(TRIM(l.state_code), ''), 'Unknown') AS state_code,
        CASE
          WHEN f.salary_min IS NOT NULL AND f.salary_max IS NOT NULL THEN (CAST(f.salary_min AS DECIMAL(18, 4)) + CAST(f.salary_max AS DECIMAL(18, 4))) / 2
          WHEN f.salary_min IS NOT NULL THEN CAST(f.salary_min AS DECIMAL(18, 4))
          WHEN f.salary_max IS NOT NULL THEN CAST(f.salary_max AS DECIMAL(18, 4))
          ELSE NULL
        END AS salary_mid,
        CASE WHEN f.security_clearance_required THEN 1 ELSE 0 END AS clearance_flag,
        CASE WHEN LOWER(COALESCE(f.remote_type, '')) LIKE '%%remote%%' THEN 1 ELSE 0 END AS remote_flag
      FROM fact_job_posting f
      LEFT JOIN dim_industry i ON f.industry_id = i.industry_id
      LEFT JOIN dim_occupation o ON f.occupation_id = o.occupation_id
      LEFT JOIN dim_location l ON f.location_id = l.location_id
      WHERE f.posted_date >= DATE_SUB(CURDATE(), INTERVAL %s MONTH)
    )
    SELECT
      month, source_id, industry_label, occupation_label, remote_type, work_schedule, state_code,
      COUNT(*) AS postings, AVG(salary_mid) AS avg_salary_mid,
      SUM(clearance_flag) AS clearance_postings,
      SUM(remote_flag) AS remote_postings
    FROM base
    GROUP BY 1, 2, 3, 4, 5, 6, 7
    ORDER BY month, postings DESC
    """
    return run_query(sql, (months,))


def safe_load(loader, empty_columns: list[str]) -> tuple[pd.DataFrame, str | None]:
    try:
        return loader(), None
    except Exception as exc:
        return empty_frame(empty_columns), str(exc)


def choose_default_sector(labor: pd.DataFrame) -> str | None:
    if labor.empty or 'sector_code' not in labor:
        return None
    sectors = labor['sector_code'].dropna().astype(str).unique().tolist()
    if not sectors:
        return None
    if 'ALL' in sectors:
        return 'ALL'
    coverage = labor.groupby('sector_code', dropna=False)['observations'].sum().sort_values(ascending=False)
    return str(coverage.index[0]) if not coverage.empty else sectors[0]


def latest_metric_value(labor: pd.DataFrame, metric_name: str, sector_code: str | None) -> pd.Series | None:
    if labor.empty:
        return None
    frame = labor[labor['metric_name'] == metric_name].copy()
    if frame.empty:
        return None
    if sector_code is not None:
        selected = frame[frame['sector_code'] == sector_code].copy()
        if not selected.empty:
            frame = selected
    frame['month'] = pd.to_datetime(frame['month'], errors='coerce')
    frame = frame.dropna(subset=['month']).sort_values('month')
    return frame.iloc[-1] if not frame.empty else None


def monthly_series(labor: pd.DataFrame, metric_name: str, sector_code: str | None) -> pd.DataFrame:
    if labor.empty:
        return empty_frame(['month', 'value'])
    frame = labor[labor['metric_name'] == metric_name].copy()
    if frame.empty:
        return empty_frame(['month', 'value'])
    if sector_code is not None:
        selected = frame[frame['sector_code'] == sector_code].copy()
        if not selected.empty:
            frame = selected
    frame['month'] = pd.to_datetime(frame['month'], errors='coerce')
    frame = frame.dropna(subset=['month', 'value']).sort_values('month')
    return frame[['month', 'value', 'previous_value', 'year_ago_value', 'sector_code']].copy() if not frame.empty else empty_frame(['month', 'value'])


def aggregate_monthly_postings(postings: pd.DataFrame) -> pd.DataFrame:
    if postings.empty:
        return empty_frame(['month', 'postings', 'remote_postings', 'clearance_postings', 'avg_salary_mid'])
    frame = postings.copy()
    frame['month'] = pd.to_datetime(frame['month'], errors='coerce')
    frame = frame.dropna(subset=['month'])
    monthly = frame.groupby('month', as_index=False).agg(
        postings=('postings', 'sum'),
        remote_postings=('remote_postings', 'sum'),
        clearance_postings=('clearance_postings', 'sum'),
    ).sort_values('month')
    salary = frame.dropna(subset=['avg_salary_mid']).groupby('month').apply(lambda g: weighted_average(g, 'avg_salary_mid', 'postings')).reset_index(name='avg_salary_mid')
    monthly = monthly.merge(salary, on='month', how='left')
    monthly['remote_share'] = monthly['remote_postings'] / monthly['postings']
    monthly['clearance_share'] = monthly['clearance_postings'] / monthly['postings']
    monthly['postings_change'] = monthly['postings'].diff()
    return monthly


def aggregate_dimension(postings: pd.DataFrame, column: str, min_postings: int = 1) -> pd.DataFrame:
    if postings.empty or column not in postings:
        return empty_frame([column, 'postings', 'remote_postings', 'clearance_postings', 'avg_salary_mid'])
    frame = postings.copy()
    grouped = frame.groupby(column, dropna=False, as_index=False).agg(
        postings=('postings', 'sum'),
        remote_postings=('remote_postings', 'sum'),
        clearance_postings=('clearance_postings', 'sum'),
    ).sort_values('postings', ascending=False)
    salary = frame.dropna(subset=['avg_salary_mid']).groupby(column).apply(lambda g: weighted_average(g, 'avg_salary_mid', 'postings')).reset_index(name='avg_salary_mid')
    grouped = grouped.merge(salary, on=column, how='left')
    grouped['remote_share'] = grouped['remote_postings'] / grouped['postings']
    grouped['clearance_share'] = grouped['clearance_postings'] / grouped['postings']
    return grouped[grouped['postings'] >= min_postings]


def line_chart(df: pd.DataFrame, x: str, y: str, y_title: str) -> alt.Chart:
    if df.empty:
        return alt.Chart(pd.DataFrame({x: [], y: []})).mark_line()
    return alt.Chart(df).mark_line(point=True).encode(
        x=alt.X(f'{x}:T', title=None),
        y=alt.Y(f'{y}:Q', title=y_title),
        tooltip=[alt.Tooltip(f'{x}:T', title='Month'), alt.Tooltip(f'{y}:Q', title=y_title, format=',.1f')],
    ).properties(height=280)


def bar_chart(df: pd.DataFrame, category: str, value: str) -> alt.Chart:
    if df.empty:
        return alt.Chart(pd.DataFrame({category: [], value: []})).mark_bar()
    return alt.Chart(df).mark_bar(color='#b86b45').encode(
        y=alt.Y(f'{category}:N', sort='-x', title=None),
        x=alt.X(f'{value}:Q', title=None),
        tooltip=[alt.Tooltip(f'{category}:N', title='Label'), alt.Tooltip(f'{value}:Q', title='Value', format=',.1f')],
    ).properties(height=max(180, 26 * min(len(df), 12)))


def render_css() -> None:
    st.markdown(
        '''
        <style>
        .stApp { background: linear-gradient(180deg, #f7eee4 0%, #efe3d4 100%); color: #2f1e14; }
        .block-container { padding-top: 1rem; padding-bottom: 2rem; max-width: 1200px; }
        .top-nav { position: sticky; top: 0.4rem; z-index: 1000; display: flex; flex-wrap: wrap; gap: 0.55rem; justify-content: center; padding: 0.8rem 1rem; margin-bottom: 1rem; background: rgba(255, 248, 241, 0.85); border: 1px solid rgba(47, 30, 20, 0.12); backdrop-filter: blur(16px); border-radius: 999px; }
        .top-nav a { color: #2f1e14; text-decoration: none; padding: 0.42rem 0.8rem; border-radius: 999px; border: 1px solid transparent; }
        .top-nav a:hover { background: rgba(184, 107, 69, 0.08); border-color: rgba(184, 107, 69, 0.18); }
        .hero-shell, .section-shell, .stat-card, .insight-card, .architecture-card { border: 1px solid rgba(47, 30, 20, 0.1); background: rgba(255, 251, 247, 0.82); box-shadow: 0 20px 50px rgba(71, 44, 25, 0.10); }
        .hero-shell { display: grid; grid-template-columns: 1.3fr 0.9fr; gap: 1rem; padding: 1.4rem; border-radius: 28px; }
        .hero-title { font-family: Georgia, serif; font-size: clamp(2.4rem, 5vw, 4.4rem); line-height: 0.95; margin: 0.35rem 0 0.6rem; }
        .hero-text, .section-subtitle { color: #715743; line-height: 1.65; }
        .section-shell { margin-top: 1.3rem; padding: 1.25rem; border-radius: 28px; }
        .section-title { font-family: Georgia, serif; font-size: clamp(1.7rem, 3vw, 2.3rem); margin: 0 0 0.2rem; }
        .kicker { letter-spacing: 0.18em; text-transform: uppercase; font-size: 0.74rem; color: #8d5b40; font-weight: 700; }
        .stat-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(170px, 1fr)); gap: 0.85rem; margin-top: 1rem; }
        .stat-card { padding: 1rem; border-radius: 20px; }
        .stat-label { font-size: 0.74rem; text-transform: uppercase; letter-spacing: 0.16em; color: #8d5b40; margin-bottom: 0.2rem; }
        .stat-value { font-size: 1.5rem; font-weight: 700; }
        .stat-note { color: #715743; font-size: 0.88rem; line-height: 1.45; }
        .insight-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(270px, 1fr)); gap: 0.9rem; }
        .insight-card { padding: 1rem; border-radius: 22px; }
        .insight-card ul { margin: 0; padding-left: 1.1rem; color: #715743; line-height: 1.55; }
        .architecture-card { padding: 1.1rem; border-radius: 24px; }
        .pipeline-step { display: flex; justify-content: space-between; gap: 0.6rem; padding: 0.72rem 0.9rem; border-radius: 16px; background: rgba(184, 107, 69, 0.08); border: 1px solid rgba(184, 107, 69, 0.16); }
        .mini-pill { display: inline-block; padding: 0.28rem 0.55rem; margin-right: 0.35rem; margin-bottom: 0.35rem; border-radius: 999px; background: rgba(184, 107, 69, 0.1); border: 1px solid rgba(184, 107, 69, 0.16); font-size: 0.8rem; }
        @media (max-width: 860px) { .hero-shell { grid-template-columns: 1fr; } .top-nav { border-radius: 20px; } }
        </style>
        ''',
        unsafe_allow_html=True,
    )


def render_nav() -> None:
    st.markdown('<div class="top-nav">' + ''.join(f'<a href="#{anchor}">{label}</a>' for label, anchor in NAV_ITEMS) + '</div>', unsafe_allow_html=True)


def stat_cards(cards: list[dict[str, str]]) -> None:
    html_cards = []
    for card in cards:
        html_cards.append(f'''<div class="stat-card"><div class="stat-label">{escape(card.get('label'))}</div><div class="stat-value">{escape(card.get('value'))}</div><div class="stat-note">{escape(card.get('note'))}</div></div>''')
    st.markdown('<div class="stat-grid">' + ''.join(html_cards) + '</div>', unsafe_allow_html=True)


def insight_cards_html(title: str, items: list[str]) -> str:
    body = ''.join(f'<li>{escape(item)}</li>' for item in items)
    return f'<div class="insight-card"><h4>{escape(title)}</h4><ul>{body}</ul></div>'


def build_snapshot(labor: pd.DataFrame, postings: pd.DataFrame) -> dict[str, object]:
    sector_code = choose_default_sector(labor)
    unemployment = latest_metric_value(labor, 'Unemployment Rate', sector_code)
    employment = latest_metric_value(labor, 'Nonfarm Employment Level', sector_code)
    monthly_postings = aggregate_monthly_postings(postings)
    latest_postings = monthly_postings.iloc[-1] if not monthly_postings.empty else None
    prev_postings = monthly_postings.iloc[-2] if len(monthly_postings) > 1 else None
    return {
        'sector_code': sector_code,
        'unemployment_value': None if unemployment is None else unemployment['value'],
        'unemployment_previous': None if unemployment is None else unemployment['previous_value'],
        'employment_value': None if employment is None else employment['value'],
        'employment_previous': None if employment is None else employment['previous_value'],
        'current_postings': None if latest_postings is None else latest_postings['postings'],
        'previous_postings': None if prev_postings is None else prev_postings['postings'],
        'remote_share': None if latest_postings is None else latest_postings['remote_postings'] / latest_postings['postings'],
        'avg_salary_mid': None if latest_postings is None else latest_postings['avg_salary_mid'],
        'jobs_added_change': None if employment is None else (employment['value'] - employment['previous_value'] if employment['previous_value'] is not None else None),
        'latest_labor_month': labor['month'].max() if not labor.empty else None,
        'latest_posting_month': postings['month'].max() if not postings.empty else None,
        'sector_count': int(labor['sector_code'].nunique()) if not labor.empty and 'sector_code' in labor else 0,
        'source_count': int(postings['source_id'].nunique()) if not postings.empty and 'source_id' in postings else 0,
        'state_count': int(postings['state_code'].replace('Unknown', pd.NA).dropna().nunique()) if not postings.empty and 'state_code' in postings else 0,
    }


def build_job_seeker_insights(labor: pd.DataFrame, postings: pd.DataFrame, snapshot: dict[str, object]) -> list[str]:
    items: list[str] = []
    if snapshot['remote_share'] is not None:
        items.append(f"Remote-friendly roles make up {fmt_pct(snapshot['remote_share'] * 100)} of the latest posting sample.")
    if snapshot['avg_salary_mid'] is not None:
        items.append(f"The latest blended salary signal sits near {fmt_money(snapshot['avg_salary_mid'])}, which is useful for quick screening.")
    if snapshot['current_postings'] is not None and snapshot['previous_postings'] is not None:
        delta = float(snapshot['current_postings']) - float(snapshot['previous_postings'])
        direction = 'rose' if delta >= 0 else 'fell'
        items.append(f"Posting volume {direction} by {fmt_signed(delta)} month over month, so momentum matters as much as headline size.")
    if snapshot['sector_code'] is not None:
        unemployment = latest_metric_value(labor, 'Unemployment Rate', snapshot['sector_code'])
        if unemployment is not None and unemployment['previous_value'] is not None:
            delta = float(unemployment['value']) - float(unemployment['previous_value'])
            items.append(f"Sector code {escape(snapshot['sector_code'])} moved {fmt_signed(delta, suffix=' pts')} in unemployment rate versus the prior month.")
    return items[:4] or ['The current BigQuery sample is still thin, but the dashboard will surface seeker signals as soon as the warehouse fills in.']


def build_policy_insights(labor: pd.DataFrame, postings: pd.DataFrame, snapshot: dict[str, object]) -> list[str]:
    items: list[str] = []
    if snapshot['unemployment_value'] is not None and snapshot['unemployment_previous'] is not None:
        delta = float(snapshot['unemployment_value']) - float(snapshot['unemployment_previous'])
        direction = 'up' if delta >= 0 else 'down'
        items.append(f"Unemployment is {direction} {fmt_signed(delta, suffix=' pts')} in the tracked sector, which is a signal to watch for slack or tightening.")
    if snapshot['current_postings'] is not None and snapshot['previous_postings'] is not None:
        delta = float(snapshot['current_postings']) - float(snapshot['previous_postings'])
        items.append(f"Posting volume changed by {fmt_signed(delta)} month over month, and the gap with labor movement is what matters for policy response.")
    if snapshot['jobs_added_change'] is not None:
        items.append(f"Employment level changed by {fmt_signed(snapshot['jobs_added_change'])} versus the prior month, which makes demand-versus-employment spread visible.")
    if not postings.empty and 'industry_label' in postings:
        unmapped_share = float((postings['industry_label'].astype(str) == 'Unmapped').mean())
        if unmapped_share > 0.5:
            items.append('Industry mapping is still thin in the posting stream, so the next ETL pass should prioritize the industry bridge.')
    return items[:4] or ['The current warehouse sample is not yet rich enough for a strong policy read, which is a data-model gap rather than a visualization problem.']


def render_hero(snapshot: dict[str, object]) -> None:
    st.markdown('''
    <div id="introduction"></div>
    <div class="hero-shell">
      <div>
        <div class="kicker">Employment intelligence</div>
        <div class="hero-title">A labor-market story built from official statistics and live job demand.</div>
        <div class="hero-text">This dashboard is served from Cloud SQL. The ETL path uses BLS labor observations, job-posting intake, Cloud Run, Eventarc, Workflows, and BigQuery transforms before the serving tables power the narrative view.</div>
        <div class="hero-text">Use the anchored navigation to jump between the introduction, key insights, and analytics sections. If a mapped dimension is missing, the app will show the gap rather than inventing a sector label.</div>
      </div>
      <div class="architecture-card">
        <div class="kicker">Pipeline</div>
        <div style="display:grid;gap:0.65rem;margin-top:0.8rem;">
          <div class="pipeline-step"><span>1. Source intake</span><span>BLS + job posts</span></div>
          <div class="pipeline-step"><span>2. BigQuery transforms</span><span>Modeled facts</span></div>
          <div class="pipeline-step"><span>3. Cloud SQL serving</span><span>Private MySQL</span></div>
          <div class="pipeline-step"><span>4. Streamlit presentation</span><span>Cloud Run</span></div>
        </div>
      </div>
    </div>
    ''', unsafe_allow_html=True)
    stat_cards([
        {'label': 'Latest unemployment rate', 'value': fmt_pct(snapshot['unemployment_value']), 'note': f"Tracked sector: {snapshot['sector_code'] or 'ALL'}"},
        {'label': 'Latest employment level', 'value': fmt_int(snapshot['employment_value']), 'note': 'Current BLS-derived observation'},
        {'label': 'Current postings', 'value': fmt_int(snapshot['current_postings']), 'note': 'Latest monthly posting rollup'},
        {'label': 'Remote share', 'value': fmt_pct((snapshot['remote_share'] or 0) * 100) if snapshot['remote_share'] is not None else 'n/a', 'note': 'Share of the latest posting sample'},
    ])


def render_key_insights(job_seeker: list[str], policy: list[str]) -> None:
    st.markdown(f'''
    <div id="key-insights"></div>
    <div class="section-shell">
      <div class="kicker">Key insights</div>
      <h2 class="section-title">Signals that matter for people and policy</h2>
      <div class="section-subtitle">The app splits the narrative into two lenses: what job seekers can act on immediately, and what policymakers should watch for structural imbalance.</div>
      <div class="insight-grid">{insight_cards_html('For job seekers', job_seeker)}{insight_cards_html('For policymakers', policy)}</div>
    </div>
    ''', unsafe_allow_html=True)


def render_labor_section(labor: pd.DataFrame, snapshot: dict[str, object]) -> None:
    st.markdown('<div id="labor-market-trends"></div><div class="section-shell"><div class="kicker">Labor market trends</div><h2 class="section-title">Employment movement over time</h2><div class="section-subtitle">This section follows the BLS-derived labor series. Sector codes are surfaced exactly as modeled; if the sector bridge is incomplete, the app will say so and keep the chart readable.</div>', unsafe_allow_html=True)
    if labor.empty:
        st.info('No labor observations were returned from BigQuery yet.')
        st.markdown('</div>', unsafe_allow_html=True)
        return
    sector_options = sorted(labor['sector_code'].dropna().astype(str).unique().tolist())
    if 'ALL' in sector_options:
        sector_options = ['ALL'] + [s for s in sector_options if s != 'ALL']
    selected_sector = st.selectbox('Sector code', sector_options, index=0 if sector_options else 0)
    unemployment = monthly_series(labor, 'Unemployment Rate', selected_sector)
    employment = monthly_series(labor, 'Nonfarm Employment Level', selected_sector)
    if not employment.empty:
        employment = employment.copy()
        employment['jobs_added'] = employment['value'].diff()
    col1, col2 = st.columns(2)
    with col1:
        st.caption('Unemployment rate')
        st.altair_chart(line_chart(unemployment, 'month', 'value', 'Rate'), use_container_width=True)
    with col2:
        st.caption('Jobs added from employment level change')
        if employment.empty:
            st.info('No employment-level series is available for this sector.')
        else:
            st.altair_chart(alt.Chart(employment.dropna(subset=['jobs_added'])).mark_bar(color='#b86b45').encode(x=alt.X('month:T', title=None), y=alt.Y('jobs_added:Q', title='Change'), tooltip=[alt.Tooltip('month:T', title='Month'), alt.Tooltip('jobs_added:Q', title='Jobs added', format=',.1f')]).properties(height=280), use_container_width=True)
    latest_employment = labor[labor['metric_name'] == 'Nonfarm Employment Level'].copy()
    if not latest_employment.empty:
        latest_employment['month'] = pd.to_datetime(latest_employment['month'], errors='coerce')
        latest_rows = latest_employment.sort_values('month').groupby('sector_code', as_index=False).tail(1).sort_values('value', ascending=False).head(8).rename(columns={'sector_code': 'sector', 'value': 'employment_level'})
        st.caption('Latest employment levels across tracked sector codes')
        st.altair_chart(bar_chart(latest_rows, 'sector', 'employment_level'), use_container_width=True)
    st.markdown('</div>', unsafe_allow_html=True)


def render_posting_section(postings: pd.DataFrame) -> None:
    st.markdown('<div id="job-posting-demand"></div><div class="section-shell"><div class="kicker">Job posting demand</div><h2 class="section-title">Where demand is appearing first</h2><div class="section-subtitle">The posting rollup carries source, industry, occupation, location, remote type, schedule, salary, and clearance signals. If the mapping is sparse, the app keeps the raw labels visible instead of blending them away.</div>', unsafe_allow_html=True)
    if postings.empty:
        st.info('No posting records were returned from BigQuery yet.')
        st.markdown('</div>', unsafe_allow_html=True)
        return
    monthly = aggregate_monthly_postings(postings)
    if not monthly.empty:
        st.caption('Posting volume over time')
        st.altair_chart(line_chart(monthly, 'month', 'postings', 'Postings'), use_container_width=True)
    source_summary = aggregate_dimension(postings, 'source_id')
    industry_summary = aggregate_dimension(postings, 'industry_label')
    state_summary = aggregate_dimension(postings, 'state_code')
    remote_summary = aggregate_dimension(postings, 'remote_type')
    schedule_summary = aggregate_dimension(postings, 'work_schedule')
    c1, c2 = st.columns(2)
    with c1:
        st.caption('Posting source mix')
        st.altair_chart(bar_chart(source_summary.head(8), 'source_id', 'postings'), use_container_width=True)
    with c2:
        top_industries = industry_summary[industry_summary['industry_label'] != 'Unmapped'].head(8)
        st.caption('Top industry labels')
        if top_industries.empty:
            st.info('Industry labels are still unmapped in the current posting feed.')
        else:
            st.altair_chart(bar_chart(top_industries.rename(columns={'industry_label': 'label'}), 'label', 'postings'), use_container_width=True)
    c3, c4 = st.columns(2)
    with c3:
        st.caption('Geographic demand by state')
        state_rows = state_summary[state_summary['state_code'] != 'Unknown'].head(10)
        if state_rows.empty:
            st.info('No state-level location data is available yet.')
        else:
            st.altair_chart(bar_chart(state_rows, 'state_code', 'postings'), use_container_width=True)
    with c4:
        st.caption('Remote and schedule mix')
        work_mix = pd.concat([
            remote_summary.assign(group='remote type', label=remote_summary['remote_type']),
            schedule_summary.assign(group='schedule', label=schedule_summary['work_schedule']),
        ], ignore_index=True)[['group', 'label', 'postings']]
        st.altair_chart(alt.Chart(work_mix).mark_bar(color='#8d5b40').encode(x=alt.X('postings:Q', title=None), y=alt.Y('label:N', sort='-x', title=None), color=alt.Color('group:N', title=None), tooltip=[alt.Tooltip('group:N', title='Category'), alt.Tooltip('label:N', title='Label'), alt.Tooltip('postings:Q', title='Postings', format=',.0f')]).properties(height=280), use_container_width=True)
    st.markdown('</div>', unsafe_allow_html=True)



def render_market_tension(labor: pd.DataFrame, postings: pd.DataFrame, snapshot: dict[str, object]) -> None:
    st.markdown('<div id="market-tension"></div><div class="section-shell"><div class="kicker">Market tension</div><h2 class="section-title">Comparing labor movement with posting demand</h2><div class="section-subtitle">This is the closest proxy to a supply-demand read in the current model. It normalizes postings and employment levels so the visual tells the story even when the units differ.</div>', unsafe_allow_html=True)
    if labor.empty or postings.empty:
        st.info('Both labor and posting data are needed for the tension view.')
        st.markdown('</div>', unsafe_allow_html=True)
        return
    default_sector = snapshot['sector_code'] or choose_default_sector(labor)
    labor_employment = monthly_series(labor, 'Nonfarm Employment Level', default_sector)
    if labor_employment.empty:
        st.info('No employment-level series is available for the selected sector.')
        st.markdown('</div>', unsafe_allow_html=True)
        return
    labor_employment = labor_employment.copy()
    labor_employment['month'] = pd.to_datetime(labor_employment['month'], errors='coerce')
    labor_employment = labor_employment.dropna(subset=['month', 'value']).sort_values('month')
    labor_employment['employment_index'] = labor_employment['value'] / labor_employment['value'].iloc[0] * 100
    monthly_postings = aggregate_monthly_postings(postings)
    monthly_postings = monthly_postings.copy()
    monthly_postings['posting_index'] = monthly_postings['postings'] / monthly_postings['postings'].iloc[0] * 100
    combined = labor_employment[['month', 'employment_index']].merge(monthly_postings[['month', 'posting_index']], on='month', how='inner')
    if combined.empty:
        st.info('The current date ranges do not overlap cleanly enough to compare trends.')
    else:
        chart = alt.Chart(combined.melt('month', var_name='series', value_name='index')).mark_line(point=True).encode(x=alt.X('month:T', title=None), y=alt.Y('index:Q', title='Index (first month = 100)'), color=alt.Color('series:N', title=None), tooltip=[alt.Tooltip('month:T', title='Month'), alt.Tooltip('series:N', title='Series'), alt.Tooltip('index:Q', title='Index', format=',.1f')]).properties(height=300)
        st.altair_chart(chart, use_container_width=True)
    labor_change = labor_employment[['month', 'value']].copy()
    labor_change['employment_change'] = labor_change['value'].diff()
    tension_table = labor_change.merge(monthly_postings[['month', 'postings', 'postings_change']], on='month', how='inner')
    if not tension_table.empty:
        latest = tension_table.iloc[-1]
        st.caption(f"Latest comparison: employment changed {fmt_signed(latest['employment_change'])} while postings changed {fmt_signed(latest['postings_change'])}.")
        st.dataframe(tension_table[['month', 'employment_change', 'postings', 'postings_change']].tail(8), use_container_width=True)
    st.markdown('</div>', unsafe_allow_html=True)



def render_salary_section(postings: pd.DataFrame) -> None:
    st.markdown('<div id="salary-work-conditions"></div><div class="section-shell"><div class="kicker">Salary & work conditions</div><h2 class="section-title">Pay, flexibility, and hiring conditions</h2><div class="section-subtitle">This section pulls the strongest compensation and work-condition signals from the postings stream. It shows where compensation is strongest, where remote work is concentrated, and where clearance requirements are common.</div>', unsafe_allow_html=True)
    if postings.empty:
        st.info('No posting data is available yet for salary analysis.')
        st.markdown('</div>', unsafe_allow_html=True)
        return
    occupation_summary = aggregate_dimension(postings, 'occupation_label', min_postings=5)
    salary_rows = occupation_summary.dropna(subset=['avg_salary_mid']).sort_values('avg_salary_mid', ascending=False).head(10)
    if salary_rows.empty:
        st.info('Salary values are too sparse to rank occupations yet.')
    else:
        st.caption('Highest weighted salary signals by occupation label')
        st.altair_chart(bar_chart(salary_rows.rename(columns={'occupation_label': 'label', 'avg_salary_mid': 'salary'}), 'label', 'salary'), use_container_width=True)
    comp = aggregate_dimension(postings, 'source_id').sort_values('remote_share', ascending=False).head(8)
    c1, c2 = st.columns(2)
    with c1:
        st.caption('Remote share by source')
        st.altair_chart(alt.Chart(comp).mark_bar(color='#b86b45').encode(x=alt.X('remote_share:Q', title='Remote share'), y=alt.Y('source_id:N', sort='-x', title=None), tooltip=[alt.Tooltip('source_id:N', title='Source'), alt.Tooltip('remote_share:Q', title='Remote share', format='.1%')]).properties(height=280), use_container_width=True)
    with c2:
        st.caption('Clearance share by source')
        st.altair_chart(alt.Chart(comp).mark_bar(color='#8d5b40').encode(x=alt.X('clearance_share:Q', title='Clearance share'), y=alt.Y('source_id:N', sort='-x', title=None), tooltip=[alt.Tooltip('source_id:N', title='Source'), alt.Tooltip('clearance_share:Q', title='Clearance share', format='.1%')]).properties(height=280), use_container_width=True)
    schedule_summary = aggregate_dimension(postings, 'work_schedule')
    if not schedule_summary.empty:
        st.caption('Work schedule mix')
        st.altair_chart(bar_chart(schedule_summary.rename(columns={'work_schedule': 'label'}), 'label', 'postings'), use_container_width=True)
    st.markdown('</div>', unsafe_allow_html=True)



def render_methodology(labor: pd.DataFrame, postings: pd.DataFrame, db_host: str, db_name: str, errors: dict[str, str]) -> None:
    st.markdown('<div id="methodology"></div><div class="section-shell"><div class="kicker">Methodology</div><h2 class="section-title">How the dashboard is assembled</h2><div class="section-subtitle">The app reads from Cloud SQL over the private VPC path. The serving tables are loaded from the BigQuery transformation layer, and unmapped labels remain explicit while the warehouse bridges mature.</div>', unsafe_allow_html=True)
    stat_cards([
        {'label': 'Labor freshness', 'value': fmt_date(labor['month'].max() if not labor.empty else None), 'note': f'Rows: {fmt_int(len(labor))}'},
        {'label': 'Posting freshness', 'value': fmt_date(postings['month'].max() if not postings.empty else None), 'note': f'Rows: {fmt_int(len(postings))}'},
        {'label': 'Sector coverage', 'value': fmt_int(labor['sector_code'].nunique() if not labor.empty else 0), 'note': 'Unique sector codes in the BLS rollup'},
        {'label': 'State coverage', 'value': fmt_int(postings['state_code'].replace('Unknown', pd.NA).dropna().nunique() if not postings.empty else 0), 'note': 'States surfaced from the posting stream'},
    ])
    st.markdown(f'<div style="margin-top: 1rem;"><span class="mini-pill">Cloud SQL host: {escape(db_host)}</span><span class="mini-pill">Database: {escape(db_name)}</span><span class="mini-pill">Private MySQL serving</span><span class="mini-pill">Cloud Run VPC connector</span></div>', unsafe_allow_html=True)
    if errors:
        st.warning('Some datasets could not be queried. The app will keep rendering with the data that is available.')
        for label, message in errors.items():
            st.caption(f'{label}: {message}')
    st.markdown('<div style="margin-top: 1rem; color: #715743; line-height: 1.65;">The warehouse model feeds the Cloud SQL serving tables for labor trends, posting demand, salaries, work conditions, industry labels, occupation labels, and location coverage.</div>', unsafe_allow_html=True)
    st.markdown('</div>', unsafe_allow_html=True)



def main() -> None:
    st.set_page_config(page_title=APP_TITLE, page_icon=':briefcase:', layout='wide', initial_sidebar_state='collapsed')
    render_css()
    render_nav()
    labor_cols = ['month', 'sector_code', 'metric_name', 'metric_category', 'value', 'observations', 'previous_value', 'year_ago_value']
    posting_cols = ['month', 'source_id', 'industry_label', 'occupation_label', 'remote_type', 'work_schedule', 'state_code', 'postings', 'avg_salary_mid', 'clearance_postings', 'remote_postings']
    errors: dict[str, str] = {}
    try:
        db_config = resolve_db_config()
        db_host = str(db_config['host'])
        db_name = str(db_config['database'])
    except Exception as exc:
        db_host = 'unknown'
        db_name = 'unknown'
        errors['database'] = str(exc)

    if errors:
        labor = empty_frame(labor_cols)
        postings = empty_frame(posting_cols)
    else:
        labor, labor_error = safe_load(lambda: load_labor_monthly(), labor_cols)
        postings, postings_error = safe_load(lambda: load_postings_rollup(), posting_cols)
        if labor_error:
            errors['labor'] = labor_error
        if postings_error:
            errors['postings'] = postings_error

    snapshot = build_snapshot(labor, postings)
    render_hero(snapshot)
    render_key_insights(build_job_seeker_insights(labor, postings, snapshot), build_policy_insights(labor, postings, snapshot))
    render_labor_section(labor, snapshot)
    render_posting_section(postings)
    render_market_tension(labor, postings, snapshot)
    render_salary_section(postings)
    render_methodology(labor, postings, db_host, db_name, errors)


if __name__ == '__main__':
    main()
