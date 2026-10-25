# Case studies: validating the spike detector

The spike detector (v1, `marts.mart_monthly_vehicle_component`) was tested against real NHTSA actions: did it flag the problem **before** the recall or investigation, or only **after** (an "echo" from news or recall letters)?

## Scorecard

| Case | Official action | Result | Lead time |
|---|---|---|---|
| Polestar 2 rearview camera | Recall 25V280000, reported Apr 25, 2025 | ✅ early warning | ~7 weeks |
| Tesla Model 3/Y phantom braking | Investigation PE22002, opened Feb 16, 2022 | ✅ early warning (weekly view) | ~2 weeks |
| Tesla Model 3/Y front suspension | Investigation PE26006, opened Jul 29, 2026 | ❌ echo only | none |

**Takeaway:** public complaints catch some defects early, but not ones that surface mainly through other sources (manufacturer data). Complaints should be one input, not the only one.

---

## 1. Polestar 2 rearview camera ✅

| Date | Event |
|---|---|
| Jun 26, 2024 | Recall 24V477000: Polestar 2 rearview camera software, ~25.8K vehicles, influenced by ODI |
| **Mar 2025** | 🚩 **Detector flags spike:** 23 complaints vs. baseline 3.7 |
| **Apr 25, 2025** | **Recall 25V280000 reported:** camera image may not display, ~27.8K vehicles, influenced by ODI |
| Jun 20, 2025 | Owners notified |
| Jun 2025 | 🚩 Burst: 114 complaints (z = 17.3) |
| Jul 2025 | 126 complaints |
| Sep 15, 2025 | Recall 25V615000: same issue, same ~27.8K vehicles, influenced by ODI |

**What it shows**
- The small March spike came **~7 weeks before** the recall: a genuine early warning
- The big June burst landed the month owners got recall letters: mostly an **echo**
- The same vehicles were recalled again in September → the fix didn't work. June–July complaints may partly be "fix failed" reports (check the text).
- All three camera recalls were influenced by NHTSA's defects office (ODI)
- In EDA I'd spotted July 2025 by hand; the detector found the burst started in **June**

**Weakness revealed: baseline contamination.** After June, the 12-month mean baseline jumped (5 → 14 → 24 → 28), absorbing the spike. July only scored z = 3.5 because June inflated its baseline.

---

## 2. Tesla phantom braking ✅

Investigation **PE22002**, "Unexpected Brake Activation," opened **Feb 16, 2022**, coded **FORWARD COLLISION AVOIDANCE**.

Monthly detector: Model Y (84 vs. 1.5, z = 62.8) and Model 3 (113 vs. 2.4) SERVICE BRAKES flagged in **Feb 2022**, the same month as the probe. Too coarse to tell lead vs. echo.

Weekly view (Model 3 + Y, SERVICE BRAKES + FORWARD COLLISION AVOIDANCE):

| Week of | Complaints |
|---|---|
| Nov 2021 – Jan 2022 | ~5–28/week (≈10 typical) |
| **Jan 31, 2022** | **233** 🚩 |
| Feb 7 | 52 |
| **Feb 14** | **272** ← probe opened Feb 16 |
| Feb 21 | 93 |
| March | back toward 12–61 |

**What it shows**
- The surge came **~2 weeks before** the probe opened; a weekly detector would have flagged it
- Monthly granularity hid the lead time
- **Label mismatch:** owners filed under SERVICE BRAKES (the symptom); NHTSA coded FORWARD COLLISION AVOIDANCE (the system). Exact component matching would miss this case.
- Same component, two models, same month → shared-platform signal
- Caveat: a 20× one-week jump may be driven by media coverage (verify press timing)

---

## 3. Tesla front suspension ❌

Investigation **PE26006**, "Lower Lateral Link detachment," opened **Jul 29, 2026**. Covers 2018–2020 Model 3 and 2021–2023 Model Y; NHTSA cited 156 reports.

Monthly detector (all model years): Model 3 flagged **Jul 2026** (13 vs. 4.4); Model Y flagged **Aug 2026** (41 vs. 10.4).

Weekly view, affected model years only:
| Period | Complaints/week |
|---|---|
| Apr – mid-Jul 2026 | 1–6 (flat) |
| **Week of Jul 27** | **19** ← probe opened Jul 29 |
| Week of Aug 3 | 25 |
| mid-Aug onward | 8 → 2 |

**What it shows**
- No buildup before the probe → the jump is an **echo**
- A monthly flag only exists after the month ends: the July flag would be computed Aug 1, after the probe opened
- Grouping all model years diluted the signal (the probe targets specific years)
- NHTSA's 156 reports far exceed what's visible in public complaints → evidence came mostly from other sources (likely manufacturer data), or owners filed under other labels (e.g., STEERING, UNKNOWN OR OTHER). The second is something NLP on text could catch.

---

## Improvements identified (→ spike detector v2)

| Case | Lesson | v2 change |
|---|---|---|
| Polestar | spike inflates its own baseline | rolling median, or exclude flagged months from baseline |
| Phantom braking | monthly hides a 2-week lead | weekly granularity |
| Suspension | mixing model years dilutes signal; monthly flags arrive late | group by model-year range; flag weekly |
| Phantom braking | owners vs. NHTSA use different component labels | match by make + model + time window; component as soft match; NLP topics |
| Top-20 spikes | z-scores explode when baseline ≈ 0 (e.g., Audi A4: 11 vs. 0.08) | rank by excess complaints or a count model (Poisson) |

## Other top spikes worth checking against recalls/investigations
Tesla Model Y BACK OVER PREVENTION (Dec 2024), Chevy Bolt EV FUEL/PROPULSION (Jul 2021; likely the battery-fire recall), Jeep Wrangler ENGINE + POWER TRAIN (Oct 2025), GMC Canyon EXTERIOR LIGHTING (Aug 2024), Honda Pilot ENGINE (Jun 2022), Hyundai Palisade + Santa Fe SEATS (Mar 2026), Toyota Sienna Hybrid SEATS (Dec 2025), Kia EV9 ELECTRICAL (Sep 2024).

## Interview version
> "I validated the detector against three real NHTSA cases. It flagged two before official action: a Polestar camera issue about seven weeks before the recall, and Tesla phantom braking about two weeks before the investigation. It missed a 2026 Tesla suspension probe because that signal mostly wasn't in public complaints, which tells me complaints should be one input alongside manufacturer data. Each case also exposed a specific weakness, which drove my v2 design."
