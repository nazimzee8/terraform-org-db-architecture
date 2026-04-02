---
name: employment-analytics-streamlit
description: Build or revise the warm, editorial Streamlit employment analytics app for this repo; use when implementing the BigQuery-first dashboard, anchored navigation, sector and labor-market insights, or the app's narrative/visual system.
---

# Employment Analytics Streamlit

Use this skill when building the Streamlit employment analytics app. The product should feel warm, editorial, and inviting, while still presenting credible labor-market analytics for job seekers and policymakers.

## Summary

- Build a single-page Streamlit experience with anchored navigation, not a tab-heavy admin UI.
- Use BigQuery as the analytics source of truth.
- Keep the narrative on the homepage: why the project exists, how the pipeline works, and what the data says.
- Separate insights for job seekers and policymakers.
- Do not invent sector-level claims unless the data model supports the join path.

## Visual Direction

- Aim for the mood of a polished editorial portfolio page: generous whitespace, warm neutrals, soft gradients, and large serif-style headlines paired with clean body text.
- Use a sticky top nav with section anchors for `Introduction`, `Key Insights`, `Labor Market Trends`, `Job Posting Demand`, `Market Tension`, `Salary & Work Conditions`, and `Methodology`.
- Prefer a few strong sections over many small widgets.
- Use cards, subtle depth, and restrained motion or staggered reveal effects if available.
- Keep the mobile layout readable and stacked; the page must not collapse into a cramped dashboard.

## Page Architecture

1. `Hero / Introduction`
   - Explain the purpose of the project in plain language.
   - Briefly describe the infrastructure pipeline: ingestion, storage, modeling, analytics delivery.
   - Show a small set of trusted snapshot KPIs only when the underlying metrics are available.

2. `Key Insights`
   - Two narrative lanes: `For Job Seekers` and `For Policymakers`.
   - Render 3 to 5 concise takeaways per lane.
   - Keep the text data-driven and time-aware.

3. `Labor Market Trends`
   - Official labor-statistics views over time.
   - Unemployment, employment growth, and related metrics when the grain is valid.

4. `Job Posting Demand`
   - Posting volume over time, source mix, and top categories.
   - Use industry, occupation, location, remote type, and work schedule dimensions where supported.

5. `Market Tension`
   - Compare postings with labor indicators only at matched grains.
   - Surface divergence, concentration, and mismatch signals.

6. `Salary & Work Conditions`
   - Salary bands, remote share, work schedule mix, and clearance-required share.

7. `Methodology`
   - Data sources, freshness, caveats, and what is not yet modeled.

## Data Contracts

BigQuery tables and views should be treated as the source of truth.

- `fact_labor_observation`
  - Grain: one observation per metric, series, and date.
  - Required fields: `observation_date`, `metric_id`, `bls_series_id`, `observation_value`.
- `fact_job_posting`
  - Grain: one row per posting.
  - Required fields: `posted_date`, `source_id`, `job_title`, `salary_min`, `salary_max`, `salary_currency`, `salary_interval`, `employment_type`, `remote_type`, `work_schedule`, `location_id`, `industry_id`, `occupation_id`.
- `dim_industry`, `dim_occupation`, `dim_location`, `dim_employer`, `dim_time_period`, `curated_labor_metric`, `curated_bls_series`
  - Use these for readable labels and consistent grouping.

If sector-level analytics are not fully modeled, show a clear fallback rather than guessing.

## Dashboard Inventory

- `Latest snapshot`: top-line KPIs and short context.
- `Trend line`: official labor indicators over time.
- `Demand line`: job posting volume over time.
- `Source mix`: compare USAJobs and Adzuna where applicable.
- `Sector / occupation mix`: top categories and change over time when mapping exists.
- `Tension view`: postings versus labor indicators.
- `Compensation view`: salary distributions and intervals.
- `Work conditions view`: remote, clearance, and schedule mix.

Prefer Altair or Plotly for charts. Keep charts readable, minimal, and consistent.

## Insight Generation Rules

- Job seeker insights should emphasize where demand is rising, where pay is strongest, where remote work is more common, and where competition may be easing or intensifying.
- Policymaker insights should emphasize structural mismatch, persistent weakness, demand concentration, and divergence between official labor data and live postings.
- Always derive insight text from ranked metrics, deltas, or thresholds. Never hardcode generic commentary.
- If a comparison is not statistically or structurally valid, omit it.
- Label derived metrics clearly, especially when they combine postings and official labor data.

## Streamlit Implementation Rules

- Use a single app entrypoint with section-render functions and shared query helpers.
- Cache BigQuery reads with `st.cache_data`.
- Query at the final analytic grain in BigQuery where possible; do not build large joins client-side.
- Use `st.markdown(..., unsafe_allow_html=True)` for the shell CSS and anchor targets.
- Keep the nav sticky and the hero section visually dominant.
- Handle missing data gracefully with short fallback text and empty-state cards.
- Keep the app read-only.
- If any dashboard depends on a missing mart or mapping, show a blocked/not-yet-available state instead of fabricating a result.

## Acceptance Criteria

- The page opens as a single, coherent editorial experience.
- The sticky nav scrolls to each section correctly.
- The introduction explains the project and the infrastructure behind it.
- Key insights are split between job seekers and policymakers.
- Charts and summaries reflect the actual BigQuery data model.
- Unsupported sector analytics are clearly labeled or deferred.
- The layout remains readable on desktop and mobile.
