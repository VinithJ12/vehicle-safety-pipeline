# Project progress

**Project:** Vehicle safety early-warning pipeline
**Goal:** Ingest NHTSA vehicle complaints, recalls, and investigations; clean and model them; flag vehicle × component combinations where complaints are spiking, ideally before official action (recall or NHTSA investigation).

**Client framing:** NHTSA's Office of Defects Investigation (ODI). The decision the tool supports: *which emerging issues should we look at first?*

---

## Problem statement

NHTSA receives tens of thousands of vehicle complaints a year. Buried in them are early signs of dangerous defects, but patterns only show up across many complaints, which a person reading them one at a time won't see. Complaint volume is rising (~70% since 2021–22), software and driver-assist failures are a growing share of dangerous complaints, and NHTSA's staff shrank after the 2025 cuts. This pipeline collects and organizes complaints automatically and flags vehicles where a problem is suddenly spiking, so investigators know where to look first.

---

## Architecture (current)

```
NHTSA bulk files (complaints, recalls, investigations)
        │  src/load_raw.py  (DuckDB → Postgres, dictionary-driven columns, row-count reconciliation)
        ▼
Postgres (Docker)  ── raw schema ── raw.complaints / raw.recalls / raw.investigations
        │  dbt
        ▼
staging schema ── stg_complaints   (typed, cleaned, vehicles only, 1 row per complaint × component)
        │  dbt
        ▼
marts schema ── mart_monthly_vehicle_component   (zero-filled monthly series, 12-month rolling baseline, spike flag)
```

**Planned:** Prefect orchestration, NLP topic clustering, Dash dashboard, daily incremental API pulls, supervised recall-prediction model (stretch).

---

## Status

### Done
- [x] GitHub repo, `.gitignore` (data, `.env`, dbt build folders), `requirements.txt`
- [x] Downloaded NHTSA bulk files: complaints 2020–2026, recalls (post-2010), investigations, data dictionaries
- [x] Profiled raw files (`awk`): every row has the expected column count, no broken lines
- [x] EDA notebook (`notebooks/01_eda.ipynb`) with DuckDB: profile, complaints vs. rows, trends, top makes/models/components, severity → see `eda_notes.md`
- [x] Postgres 17 in Docker Compose, credentials in `.env` (not committed), `.env.example` template
- [x] `src/load_raw.py`: loads all 3 datasets into `raw` schema; column names parsed from NHTSA dictionaries; exact row-count reconciliation
- [x] dbt project (`transform/`): `stg_complaints` + `mart_monthly_vehicle_component`, 9 data tests passing
- [x] Spike detector v1 validated against 3 real NHTSA cases → see `case_studies.md`

### Load results (all reconcile exactly)
| Table | Rows | Columns |
|---|---|---|
| raw.complaints | 625,983 | 51 |
| raw.recalls | 246,638 | 29 |
| raw.investigations | 154,439 | 11 |
| staging.stg_complaints | 617,409 | (vehicles only) |
| marts.mart_monthly_vehicle_component | 217,427 | |

Full rebuild (`dbt run`) takes ~26 seconds.

### Next
- [ ] NLP: cluster complaint text (TF-IDF + K-Means baseline → sentence embeddings + BERTopic)
- [ ] Prefect flow: load → dbt run → dbt test, with retries and logging
- [ ] Dash dashboard: flagged vehicles, trends, drill-down to complaints
- [ ] Spike detector v2 (weekly, model-year groups, robust baseline) → see `decisions.md`
- [ ] `stg_recalls`, `stg_investigations` + automated spike evaluation (early warning / echo / unexplained)
- [ ] README + architecture diagram (draw.io)
- [ ] Stretch: supervised recall-prediction model; daily incremental API extract

### Schedule (interview Thursday)
- **Sun:** NLP clustering + Prefect
- **Mon:** Dash dashboard
- **Tue:** README, diagram, supervised model if time
- **Wed:** interview prep only

---

## How to run

```bash
# 1. environment
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env            # then set your own password

# 2. database
docker compose up -d
docker compose ps               # wait for (healthy)

# 3. download NHTSA files into data/bulk/ (see eda_notes.md for the list), then load
python src/load_raw.py

# 4. transform + test
cd transform
set -a && source ../.env && set +a
dbt run && dbt test
```
