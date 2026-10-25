# Decision log

Format: options → choice → why → tradeoff → would revisit if.

---

## 1. Data source: bulk files vs. API
**Options:** NHTSA API only · bulk flat files only · both
**Chose:** bulk files for backfill and exploration; API for daily incremental updates (planned)
**Why:** the API needs a specific make + model + year per request, so it can't answer "show me everything" without thousands of calls. Bulk files give full history in one download.
**Tradeoff:** two ingestion paths to maintain
**Revisit if:** NHTSA adds a bulk/incremental API endpoint

## 2. Vehicle scope
**Options:** pick ~12 vehicles up front · explore all data first
**Chose:** explore everything first, then scope based on EDA
**Why:** let the data (volume, investigations, case studies) drive which vehicles to feature, rather than guessing

## 3. Transformation approach
**Options:** ETL (clean in Python, load clean) · ELT (load raw, clean in SQL) · hybrid
**Chose:** hybrid ELT. Python does light loading; all cleaning happens in SQL (dbt) inside Postgres.
**Why:** keeps an untouched raw copy, so cleaning bugs can be fixed without re-downloading; audit trail matters for federal data
**Tradeoff:** more tables, plus a new tool (dbt)
**Revisit if:** data got big enough that loading raw first became too slow or costly

## 4. Database: Postgres vs. DuckDB
**Chose:** DuckDB for ad-hoc EDA; Postgres as the pipeline's system of record
**Why:** DuckDB is fast for one person exploring files. Postgres is a server that multiple tools (dbt, Prefect, Dash) can connect to at once, is what production systems run, and is named in the target job description.

## 5. Running Postgres: Docker Compose
**Why:** reproducible (anyone runs `docker compose up` and gets the same database), easy to reset, named volume keeps data across restarts, health check confirms readiness
**Secrets:** credentials in `.env` (git-ignored); `.env.example` template committed

## 6. Loading: fail loudly, never drop silently
- Read every column as text (`all_varchar`) on load; cast types later in dbt where I control it
- Rejected `ignore_errors=true`: it silently skips bad rows. In a federal pipeline, silently losing records is worse than failing.
- Every load reconciles row counts against line counts in the source files (exact match required)
- Disabled quote handling (`quote=''`) since the files are unquoted; stray `"` in complaint text can't break row boundaries
- Column names parsed from NHTSA's data dictionaries (with a check that fields are numbered 1..N and match the file's column count) instead of hardcoded lists
- Idempotent: drop and recreate raw tables each run; `_source_file` and `_loaded_at` metadata columns for audit

## 7. Transforms: dbt vs. plain SQL scripts
**Chose:** dbt
**Why:** automatic build order from `ref()`, built-in data tests, lineage docs, version-controlled SQL
**Layers:** `raw` → `staging` (typed, cleaned) → `marts` (analysis-ready)

## 8. Which date to use for trends
**Chose:** `LDATE` (date NHTSA received the complaint)
**Why:** that's when the agency actually knew. Using `FAILDATE` (incident date) would let a model "see" complaints before NHTSA did → data leakage. `FAILDATE` also has impossible values (1917).

## 9. Counting unit
**Chose:** `COUNT(DISTINCT complaint_id)`, never row counts
**Why:** complaints span multiple component rows; counting rows overcounts by ~45%

## 10. Product filter
**Chose:** keep rows where `PROD_TYPE = 'V'` (row-level, not complaint-level)
**Why:** ~4.7K complaints mix vehicle and non-vehicle components; dropping whole complaints would lose their vehicle rows

## 11. Cleaning rules (in `stg_complaints`)
Driven by EDA findings: safe casts (`pg_input_is_valid`), strip `"redundant"` name prefixes, model year 9999 → null, injuries/deaths = 99 → null, speed > 200 → null, failure dates before 1990 or after received date → null, invalid state codes → null, merge ENGINE AND ENGINE COOLING into ENGINE, drop mostly-empty and PII columns (dealer info, vehicle operator).
**Grain:** one row per complaint × component, key `complaint_component_id` (unique test passes → no exact duplicates in NHTSA data).

## 12. Spike detection v1
**Options:** fixed threshold · national totals · per-series rolling baseline · ML anomaly detection
**Chose:** per make × model × component, monthly, trailing 12-month mean + standard deviation (excluding the current month)
**Spike rule:** ≥ 6 months of history AND ≥ 10 complaints AND complaints > mean + 3 × max(std, 1)
**Why:**
- national totals hide defects (top pair is only ~2% of a spike month)
- the overall baseline rises ~70%, so fixed thresholds break
- zero-fill missing months so baselines aren't inflated; start each series at its first complaint so launches don't look like spikes
- only series with 30+ total complaints (too noisy otherwise)
- simple and explainable first
**Tradeoff:** see v2 below

## 13. Evaluation approach
**Chose:** validate flags against real recalls (`rcdate`, `odate`) and NHTSA investigations (`odate`)
**Labels:** early warning (spike before official action) · echo (spike after recall/news) · unexplained (no matching action: emerging issue or false positive)
**Metric ideas:** share of recalls/investigations preceded by a spike; lead time in weeks
**Lesson:** match by make + model + time window; component as soft match (owners and NHTSA label differently)

## 14. Spike detection v2 (planned, from case studies)
- **Weekly** granularity (monthly hid a 2-week lead and flagged too late)
- **Model-year groups** (mixing years diluted the Tesla suspension signal)
- **Robust baseline:** rolling median or exclude flagged months (Polestar spike contaminated its own baseline)
- **Rank by excess complaints** or a Poisson model (z-scores explode when baseline ≈ 0)
- Also aggregate by **manufacturer + component** (sister vehicles split one problem)
- Track multi-month **trend** (gradual ramps, like F-150 powertrain, hide under a rising baseline)
- Weight by **severity** (high-volume components aren't the most dangerous)

## 15. NLP approach (planned)
**Options:** TF-IDF + K-Means · sentence embeddings + BERTopic
**Plan:** baseline first, then upgrade; compare
**Why NLP at all:** 14% of complaints are UNKNOWN OR OTHER, 18% ELECTRICAL SYSTEM, 95% of speed-control complaints lack a subcomponent, and label mismatches hid signals in validation

## 16. Dashboard: Dash
**Options:** Power BI · Streamlit · Dash · Flask · Shiny
**Chose:** Dash
**Why:** Python-native, built for data dashboards, named in the job description; already used Power BI and Streamlit elsewhere, so this adds range. Flask would require building the frontend by hand; Shiny is mainly R.

## 17. Orchestration: Prefect (planned)
**Options:** Prefect · Airflow · cron
**Chose:** Prefect
**Why:** pure Python decorators, light setup, built-in retries, logging, and run-history UI. Same DAG concepts as Airflow, much less setup for a solo project.
