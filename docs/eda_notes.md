# EDA notes

Source notebook: `notebooks/01_eda.ipynb` (DuckDB over the raw NHTSA files).

## 0. Data sources

From [NHTSA Datasets and APIs](https://www.nhtsa.gov/nhtsa-datasets-and-apis):

| File | Contents |
|---|---|
| `COMPLAINTS_RECEIVED_2020-2024.txt` | 418,884 rows |
| `COMPLAINTS_RECEIVED_2025-2026.txt` | 207,099 rows (through Oct 21, 2026) |
| `FLAT_RCL_POST_2010.txt` | recalls since 2010, 246,638 rows |
| `FLAT_INV.txt` | NHTSA investigations, 154,439 rows |
| `CMPL.txt`, `RCL.txt`, `INV.txt` | data dictionaries (column definitions) |

**Format:** tab-separated, no header row, all dates `YYYYMMDD`. Column names come from the dictionaries.

**Raw-file check:** `awk` confirmed every row in both complaint files has exactly 51 columns, so there are no broken lines.

### Key facts from the data dictionary (`CMPL.txt`)
- **ODINO repeats across components.** One complaint can be several rows (one per component). Count `DISTINCT ODINO`, not rows.
- **CMPLID is updateable** between file versions, so it's not a stable key.
- **Since 2021, blank Y/N fields show as `N` and blank numbers show as `0`.** A zero might mean "unknown."
- `YEARTXT = 9999` means unknown model year.
- `VEHICLE_OPERATOR` (added Apr 2026) is a name field → treat as PII and drop.
- File includes tires, equipment, and child seats → filter `PROD_TYPE = 'V'` for vehicles.
- Three dates: `FAILDATE` (incident), `DATEA` (added to file), `LDATE` (received by NHTSA). **Use `LDATE` for trends**, since that's when the agency knew. Using `FAILDATE` would leak information the agency didn't have yet.

---

## 1. Quick profile

**Why:** check size, column contents, and missingness before analysis.

- **625,983 rows × 52 columns** (51 + `filename`)
- Core fields are 0% null: ODINO, make, model, year, component, crash, fire, injuries, LDATE, complaint text
- `LDATE` runs Jan 1, 2020 → Oct 21, 2026, matching the files downloaded
- Everything loaded as text (`all_varchar`), so numeric min/max sort alphabetically (ODINO min > max). Types are cast later, in dbt.

**Data quality issues → cleaning rules**
- `FAILDATE` min is 1917 → impossible dates exist
- `YEARTXT` max 9999 (unknown code)
- `INJURED` / `DEATHS` max 99 → only 5 rows each, data errors
- `VEH_SPEED` max 999 → sentinel
- `STATE` has 66 values including `00`; `STATE_OF_INCIDENT` includes `AA`
- `"redundant"` prefix on some manufacturer/model names (retired names)
- Junk values: model `!MX-5`, complaint text `...`
- Non-English text (a city written in Chinese characters)

**Mostly empty (>90% null) → dropped:** tire fields, child-seat fields, vehicle-spec fields (cylinders, drive train, fuel, transmission), purchase/manufacture dates, occurrences, all dealer fields (also PII-ish).
**Kept but sparse:** `MILES` (71% null), `VEH_SPEED` (47% null).

**Interesting:** `VEHICLE_OPERATOR` is 99.99% null and its few values are autonomous-vehicle operators (Zoox, Avride), not people. The newest field is tracking robotaxi fleets.

---

## 2. Complaints vs. rows

- **430,755 unique complaints** across 625,983 rows → **1.45 rows per complaint**
- Counting rows would **overcount complaints by ~45%**
- `SUMMARIZE`'s approximate unique count (402,844) was ~7% low → use exact counts for anything reported
- Example: complaint 11633475 (2024 Buick Envista) = ELECTRICAL SYSTEM + VEHICLE SPEED CONTROL rows

| Components per complaint | Complaints | % |
|---|---|---|
| 1 | 293,293 | 68.1 |
| 2 | 80,653 | 18.7 |
| 3 | 56,063 | 13.0 |
| 4+ | 746 | 0.2 |

Sharp drop after 3 → likely a 3-component limit on the online form (hypothesis; 4+ cases may come from other channels).

**Product type:** vehicles = 429,070 complaints (99.6%), tires 2,822, equipment 2,272, child seats 1,269, null 6. These sum to more than 430,755 → ~4.7K complaints mix product types, so **filter rows, not whole complaints**. The 6 nulls were hidden by rounding in `SUMMARIZE` (showed 0.00%).

---

## 3. Trends over time

*(vehicles only, distinct complaints, by month received)*

- **COVID dip:** April 2020 fell below 3K (from ~6.5K) → the data tracks real-world driving
- **~70% growth** from the 2021–22 low (~3.5–4K/month) to ~6.5–7K/month in 2026
- Possible end-of-year seasonal dips
- Busiest months: Jul 2025 (7,248), Mar 2026 (7,136), Aug 2026 (7,014)
- **Oct 2026 (4,520) is a partial month** (data through Oct 21), not a real decline

**Implication:** the baseline keeps rising, so a fixed threshold would fire more and more just from overall growth. Spike detection must compare each series to **its own rolling baseline**.

---

## 4. What gets complained about

**Makes:** Ford ~80K (2× next), Chevrolet ~37K, Honda ~36K, Hyundai ~28K, Jeep ~25K, Toyota ~24K, Kia ~24K … Tesla ~12.5K (12th, despite much lower sales).
Ford's lead is consistent with its record 2025 recall year (146 campaigns).

**Models:** Ford F-150 ~13.7K, **Ford Escape ~13K** (nearly ties the F-150 despite far lower sales; NHTSA opened an Escape door investigation in 2026), Explorer ~10K, RAM 1500 ~9K. Discontinued Fusion/Focus still in top 20 → vehicle age matters.

**Components (top-level, % of vehicle complaints):**
| Component | Complaints | % |
|---|---|---|
| ENGINE | 92,770 | 21.6 |
| ELECTRICAL SYSTEM | 79,092 | 18.4 |
| POWER TRAIN | 63,439 | 14.8 |
| **UNKNOWN OR OTHER** | **61,271** | **14.3** |
| STEERING | 39,865 | 9.3 |
| SERVICE BRAKES | 35,736 | 8.3 |
| FORWARD COLLISION AVOIDANCE | 22,304 | 5.2 |

- **1 in 7 complaints has no useful component label**, and "ELECTRICAL SYSTEM" is a huge vague bucket → **the main justification for NLP on complaint text**
- Duplicate labels: ENGINE vs. ENGINE AND ENGINE COOLING → standardize
- Driver-assist (forward collision avoidance) is top 10 → software-era failure types

**What drove the busiest months:** no single defect. The top vehicle × component pair is only ~2% of a spike month's volume → **defect signals live at the vehicle × component level, not in national totals.**
- **Chronic:** F-150 POWER TRAIN tops all three spike months and is escalating (150 → 165 → 221)
- **Acute bursts:** Polestar 2 BACK OVER PREVENTION (126 in Jul 2025), Hyundai Ioniq 5 ELECTRICAL (87 in Mar 2026)
- **Split labels hide signal:** Escape ENGINE (134) + ENGINE AND ENGINE COOLING (65) = 199 in Jul 2025, more than the #1 pair
- **Sister vehicles split one problem:** Aug 2026 GMC Sierra (119) + Chevy Silverado (99) + GMC Yukon (63) ENGINE = 281 → also aggregate by manufacturer + component (possibly related to GM's 2025 V8 engine recall, verify)

**Limitation:** raw counts favor popular vehicles. A fair comparison needs complaints per vehicle sold, which this data doesn't include.

---

## 5. Severity

*(per complaint; INJURED/DEATHS = 99 excluded)*

| Crash | Fire | Medical attention | Injury | Death |
|---|---|---|---|---|
| 3.85% | 1.62% | 1.68% | 2.45% | 0.07% |

**Highest crash rates (components with 2,000+ complaints):**
| Component | Crash % | Injury % |
|---|---|---|
| AIR BAGS | 22.4 | 16.8 |
| VEHICLE SPEED CONTROL | 12.5 | 4.9 |
| SEAT BELTS | 10.8 | 10.5 |
| FORWARD COLLISION AVOIDANCE | 10.1 | 4.5 |
| SERVICE BRAKES | 9.7 | 3.8 |
| LANE DEPARTURE | 7.0 | 2.6 |
| BACK OVER PREVENTION | 6.6 | 1.2 |

- Air bags / seat belts are high partly by selection (people file after crashes)
- **4 of the top 8 are driver-assist / software systems**, while high-volume ENGINE and ELECTRICAL don't appear → **volume ≠ danger**; weight detection by severity
- SEATS: low crash rate (3.1%) but 9.8% injury and the highest fire rate (2.8%)
- UNKNOWN OR OTHER has a 2.3% fire rate → dangerous complaints hide in coarse labels

**Vehicle speed control drill-down:**
- ~95% of complaints (15,661) have no subcomponent label
- ACCELERATOR PEDAL subcomponent: 35.3% crash rate
- Tesla Model 3 (613, 17.9% crash) and Model Y (586, 19.3%) rank #2–3 after F-150 (726, 6.3%)
- **Subaru Forester: 46.8% crash rate**; Honda CR-V 26.0%; RAM 2500 has 439 complaints but 0.9% crash rate (volume ≠ danger again)

**Reading Forester crash complaints:** a consistent *reported* pattern of sudden acceleration at low speed while parking, despite braking. Invisible in labels → what NLP clustering should surface.
Caution: sudden-acceleration complaints have historically often been attributed to pedal misapplication. Complaints are unverified claims.

**Caveats:** severity fields are self-reported and unverified; crash victims are more likely to file.

---

## 6. Recalls and investigations tables (first look)

**Recalls (`raw.recalls`):** one row per campaign × model year × component. Dedupe by `campno`.
Key fields: `campno`, `rcdate` (reported to NHTSA), `odate` (owners notified), `compname` (same naming system as complaints), `influenced_by` (`MFR` = automaker, `ODI` = NHTSA defects office), `potaff` (vehicles affected), `desc_defect`.

**Investigations (`raw.investigations`):** one row per investigation × vehicle-year. Note the column is `make`, not `maketxt` (names differ by file → standardize in staging).
Key fields: `nhtsa` (ID; prefix = type: DP petition, PE preliminary evaluation, EA engineering analysis, RQ/AQ recall/audit query), `odate` (opened), `cdate` (closed), `campno` (resulting recall → links investigations to recalls), `subject`, `summary`.

Recent Tesla investigations are mostly software / driver-assist (FSD, Smart Summon, school-zone speeding, Cybercab certification) → "why now" evidence from NHTSA's own records.

---

## Text preprocessing notes (for NLP)
- Mixed ALL-CAPS and normal case → lowercase
- Two writing styles: first-person complaints vs. NHTSA hotline summaries ("THE CONTACT OWNS A…")
- Tags like `TL*` and `*TR` → strip
- `CDESCR` capped at 2,048 characters; some entries are junk (`...`)