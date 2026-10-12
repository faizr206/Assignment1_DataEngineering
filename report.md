# From Raw SQL to a Model-Ready Dataset
### ENG2040 Assignment 1 — Marketplace Orders and Delivery Outcomes

## 1. Background and goal

The operations team wants to identify orders at risk of late delivery **as soon as they are
approved**. This report documents the pipeline that takes the supplied raw SQL extract to that
goal in four stages: (1) an efficient, verified assembly of the eight source tables into one row
per order; (2) profiled, fully logged cleaning that produces reliable orders and a binary
delivery label; (3) an exploratory analysis answering the three business questions about
delivery delays, with sensitivity checks; and (4) a leakage-free numerical feature table with
matching order IDs and labels, ready for a future prediction model. Every stage is
reproducible with one command (`bash run_pipeline.sh`), and every pipeline step writes its
output data under `outputs/`.

Throughout, the brief's constraints are treated as hard rules: `delivered_after_estimate` is 1
only for a usable completed delivery after the estimated calendar date; delivery **on** the
estimated date is on time; cancelled, unknown or unreliable outcomes remain unlabelled; and
payments, final status, shipment/delivery events, reviews and `shipping_limit_date` are never
used as predictors. All findings concern this modified extract of Olist's Brazilian e-commerce
dataset; associations do not establish causation.

## 2. Data acquisition and assembly

### 2.1 What the tables and keys represent

The extract contains eight tables. `orders` is the fact table — one row per order, keyed by
`order_id`, with the order's lifecycle timestamps (purchase, approval, carrier handover,
customer delivery, estimated delivery) and its final status. `customers` holds one row per
order–address pair: `customer_id` joins to `orders`, while `customer_unique_id` identifies the
same person across orders. Three child tables attach to orders at higher grain:
`order_items` (one row per purchased item, sequenced by `order_item_id`, referencing
`product_id` and `seller_id`), `order_payments` (one row per payment record, sequenced by
`payment_sequential` — an order can pay in several records), and `order_reviews` (one row per
review; an order can collect several). Dimension tables are `products`, `sellers` and
`category_translation` (a lookup from Portuguese category names to English).

### 2.2 Assembly strategy and verification

Because the child tables repeat `order_id`, a naive join would multiply order rows. Each child
is therefore **aggregated to order grain first** and then merged left onto `orders`: reviews
deduplicated by keeping the latest review per order; payments aggregated to count, total,
maximum installments and distinct payment types; items joined to products and sellers, then
aggregated to 25 order-level statistics (item and seller counts, price/freight totals and
distribution summaries, product dimensions, seller geography). The result is one row per
order with no record loss.

Verification is explicit. Primary-key uniqueness and referential integrity were checked in
SQL before assembly: all `order_id` keys are unique, and item/payment/review children have no
orphan rows. The checks did surface real defects: 769 orders point at `customer_id`s that do
not exist in `customers` (which is why 1,064 assembled orders carry no customer
location), `order_items` references 910 products and 893 sellers missing from their
dimension tables, and 25 `review_id`s appear on more than one row. Every merge asserts that
the row count stays at exactly 20,000, and totals are reconciled to the raw tables:
`sum(payment_value)` matches the aggregate to 0.00, item price and freight totals match to
floating-point precision, and `sum(item_count)` equals the 22,662 raw item rows exactly.

### 2.3 Efficiency

Each table is read exactly once with a plain `SELECT *`; all aggregation happens in pandas on
order-grain frames. The alternative — pushing the `GROUP BY` work into SQL — would ship fewer
rows out of the database, but the aggregates are needed as pandas frames for cleaning anyway,
and the workload is small: the database is 24.4 MB on disk and all in-memory frames together
occupy about 54 MB, so the simple approach costs seconds and a few tens of MB.
Section 5 compares a-priori estimates against measurements for every step; the estimates were
within a factor of roughly two of the measurements, which is sufficient to confirm that no
step is a resource risk at this scale.

## 3. Data quality and cleaning

### 3.1 Profiling findings

Profiling found problems in four categories. **Consistency:** `order_status` mixed casing
(e.g. `DELIVERED` vs `delivered`, 783 rows re-cased), and both customer and seller states
arrived with mixed casing *and* stray whitespace (`" MA  "` vs `"MA"`), which would silently
split one state into several groups. **Units:** Appendix B specifies that `payment_value` is
in centavos; the raw totals were converted to BRL so money is comparable with price and
freight. **Invalid values:** 1,031 review scores outside the defined 1–5 range,
924 negative payment totals, 368 negative freight and 342 negative price
totals — amounts that cannot be real charges. **Structure:** 142 orders have no item
rows at all, 1,960 ZIP prefixes are not five digits, and 1,046 orders have
contradictory date sequences (e.g. delivered before approved).

### 3.2 Cleaning rules and audit trail

Every rule is logged in `outputs/cleaning_audit.csv` (15 rules, R01–R15); the main ones:

| rule | issue | action | records |
|---|---|---|---|
| | R01 | Several review rows per order | kept latest review per order | 113 review rows |
| R02 | order_status casing inconsistent | normalised to lowercase | 783 rows |
| R03 | payment_value in centavos (Appendix B) | converted to BRL | all orders |
| R04 | review_score outside 1-5 | set to missing | 1,031 rows |
| R05-R06 | Negative payment / freight / price totals | set to missing | 924 / 368 / 342 rows |
| R07 | Extreme item price (> R$10,000) | flagged, kept | 409 orders |
| R08 | Invalid ZIP prefix (not 5 digits) | set to missing | 1,960 orders |
| R09 | City spelling / accents inconsistent | fuzzy-matched to IBGE list | 1,062 unmatched |
| R10 | Illogical date sequence | excluded from delay analysis | 1,046 orders |
| R11 | Order with no item rows | kept, unlabelled | 142 orders |
| R13 | Missing customer location | kept | 1,064 orders |
| R14 | Missing optional catalogue fields | kept — never an exclusion reason | — | |

The guiding principle is **flag and keep rather than delete**. A missing optional catalogue
field alone never makes an order unusable (R14). Negative monetary values are set to missing
rather than kept in averages, and extreme prices (e.g. R$55,000 for a single item) are flagged
but retained, since high-ticket orders may be genuine. The single hard exclusion is logical:
1,046 orders whose date sequences are contradictory are removed from the *delay analysis*
(`order_clean_df`, 18,954 retained orders), because any delay computed from them would be
meaningless. Everything else stays in the table.

### 3.3 The delivery label

`delivered_after_estimate` follows the brief exactly. A **usable completed delivery** requires
status `delivered`, item rows present, and both delivery and estimated dates. The comparison
is on **calendar dates**, not raw timestamps: the estimated date is stored at 00:00, so a
same-day-evening delivery must not count as late (delivery on the estimated date is on
time). Of 18,954 retained orders, 16,262 (85.8%) receive a label — 1,105 late
(1) and 15,157 on time or early (0). The remaining 2,692 (14.2%) stay unlabelled, mostly
because their status is not `delivered` (2,045 rows) or a delivery/estimated date is
missing (1,184 rows). Unlabelling rather than dropping keeps every exclusion traceable
and avoids pretending cancelled orders are evidence about delivery speed.

### 3.4 Impact of unresolved issues

- Rates are estimated on the labelled subset only. If unlabelled orders' (unknown) outcomes
  differed systematically from labelled ones, the true late rate would shift; the sensitivity
  analysis in Section 4.4 bounds how far alternative definitions move it (6.4%–8.2%).
- 1,064 orders lack customer location; they count toward overall rates but not the
  state ranking.
- The set-to-missing repairs (1,031 review scores, 924 payments, 368 freight,
  342 price totals) affect monetary and review features only — never the delivery label.
- The 769 orphaned order→customer links cannot be repaired from the data; they reduce state
  coverage by roughly five percentage points and are a candidate question for the data owner.

## 4. Exploratory analysis

### 4.1 Q1 — How often are orders late, and how long are the delays?

**6.8% of labelled orders arrive after the estimated date** — 1,105 of 16,262. The
distribution is strongly left-skewed: most completed deliveries actually arrive *before* the
estimate. When orders are late, they are late by **7 days** at the median, 10.6
days on average, 22 days at the 90th percentile, and up to 188 days in the worst case;
44.6% of late orders slip by more than a week. Operationally this means late deliveries are
rare but *long*: the problem is not a one-day slippage spread thinly, it is a small tail of
severely late orders.

### 4.2 Q2 — How does the promised window relate to lateness?

Bucketing labelled orders by the promised window (approval → estimated delivery date):

| promised window | labelled orders | late rate |
|---|---|---|
| | 1-7 days | 290 | 16.6% |
| 8-14 days | 1,915 | 5.0% |
| 15-21 days | 4,086 | 7.1% |
| 22-28 days | 5,640 | 7.6% |
| 29-42 days | 3,617 | 5.9% |
| >42 days | 402 | 1.7% | |

Orders promised a week or less are late 16.6% of the time — roughly three times the
overall rate — while orders promised more than 42 days almost never arrive late
(1.7%). The relationship is monotone in the tails but not strictly in the middle;
the linear point-biserial correlation is weak (-0.032) precisely because the effect
concentrates at short windows. Two cautions: the estimated date is set by the marketplace
*at approval* and already absorbs known difficulty, so this is an association, not evidence
that longer windows cause fewer delays; and 312 labelled orders without an approval
timestamp drop out of this view.

### 4.3 Q3 — Where do late rates concentrate across customer states?

Among states with at least 30 labelled orders (95% Wilson confidence intervals):

| state | labelled orders | late rate | 95% CI |
|---|---|---|---|
| | CE | 182 | 17.6% | 12.7%-23.8% |
| MA | 120 | 17.5% | 11.7%-25.3% |
| AL | 70 | 17.1% | 10.1%-27.6% |
| PE | 225 | 15.6% | 11.4%-20.9% |
| PI | 73 | 15.1% | 8.6%-25.0% |
| BA | 500 | 12.0% | 9.4%-15.1% |
| PA | 136 | 11.8% | 7.4%-18.3% | |

The overall rate is 6.8%. **CE** leads at 17.6% with an interval entirely
above the overall rate, followed by **MA** (17.5%) and **AL** (17.1%). The pattern
is regional: the top of the ranking is dominated by Northern/Northeastern states, consistent
with longer, more fragile logistics corridors. Operations should investigate **CE first**,
with MA and AL next; states below n = 30 (e.g. RR at 22.2%, but only 9 orders) are shown in
the chart with wide intervals and should not yet drive decisions.

### 4.4 Data-quality sensitivity and confidence

The headline late rate was recomputed under four alternative definitions: comparing raw
timestamps instead of calendar dates (same-day-afternoon deliveries count as late), reincluding
the date-illogical orders, relaxing the usability requirement to status + dates, and
additionally requiring a carrier handover date. The estimate moves within **6.4%–8.2%**, and
the top-five state ranking is identical under the base and the most inclusionary variant, so
the conclusions are not artefacts of one arbitrary choice. Confidence is quantified by the
Wilson intervals above — differences within overlapping intervals (e.g. CE vs MA) should be
treated as indicative — and by the labelled share: conclusions rest on 16,262 labelled
orders, 85.8% of the analysis set. Per the brief, these are associations in this modified
extract and do not establish causation.

## 5. Feature engineering

The feature table (`outputs/features.csv`) has **18,954 rows and 81 features**, one row per
retained order, using only information available at approval. Order IDs live in the table
index as a join key — they are not predictors — and labels are delivered separately in
`outputs/labels.csv`, sharing the same index; 16,262 rows carry a reliable label.

**Representation.** Numerical quantities pass through as floats with consistent units: money
in BRL (after the centavos fix), weight in grams, volume in cm³. Categorical variables: the
27 customer states and ~26 seller states become one-hot binary columns (`int8`, 52 columns)
with dedicated `_nan` indicators, so missing geography is visible rather than silently
dropped; customer city (thousands of levels) is frequency-encoded to avoid a sparse
one-hot explosion; the raw ZIP prefix is dropped because as a number it implies a fake
ordering and duplicates geography already carried by state and city. Date/time fields are
reduced to approval-relative numbers, with hour, weekday and month encoded **cyclically**
(sin/cos) so that 23:00 and 00:00 are nearby on the feature circle.

**New features.** `promised_window_days` (estimated date − approval) is the flagship, coming
straight from the Q2 finding; `purchase_to_approval_hours` captures approval friction;
`freight_ratio` (freight relative to basket value) and `price_per_item` capture shipping
intensity and basket composition; `volume_cm3` and weights proxy handling effort;
`seller_customer_same_state` proxies short-haul routes; `customer_city_freq` separates
metropolitan from remote customers; `items_missing` and `weight_missing` flag structural
absences, because a missing catalogue record may itself predict delay.

**Leakage control.** The banned inputs — payments, final status, delivery events, reviews,
`shipping_limit_date`, and anything derived from them (e.g. `actually_delivered`) — are
enumerated in the notebook and asserted absent from the feature table before it is saved;
every column is checked numeric; the index is unique and row-counted against the retained
set. Missing values remain `NaN` (never zero-filled) with explicit flags, keeping uncertainty
visible; imputation is deliberately left to the modelling stage. `min_price` was dropped as
redundant with average/max price; the full dictionary of all 81 features with meaning,
derivation and missing policy is in `outputs/feature_dictionary.csv`.

## 6. Reproducibility and resources

`bash run_pipeline.sh` rebuilds the database from `data/raw.sql` and executes the notebook
end-to-end, regenerating every file under `outputs/`; the notebook contains all executed SQL
inline, and the README maps each step to its inputs, outputs, row meaning and loading
instructions. Environment versions are pinned in `outputs/environment.txt`.

Estimated versus measured resources per pipeline step (estimates made a priori from row
counts and column types; measurement scope: runtime over the whole step, memory as peak
Python allocations inside the step, session RSS covers the whole kernel):

| step | est. runtime | measured | est. memory | measured peak |
|---|---|---|---|---|
| | load orders (20k x 8 text cols) | 0.3 s | 0.06 s | 6 MB | 14.6 MB |
| load + dedup reviews (20k rows) | 0.6 s | 0.12 s | 8 MB | 12.6 MB |
| load + aggregate payments (21k rows) | 0.4 s | 0.06 s | 4 MB | 8.1 MB |
| load + aggregate items (23k rows, 2 joins) | 1.2 s | 0.14 s | 18 MB | 20.4 MB |
| assemble one row per order (3 left joins on 20k) | 0.5 s | 0.08 s | 16 MB | 19.5 MB |
| build feature table (19k x ~90) | 0.3 s | 0.00 s | 10 MB | 2.7 MB | |

Runtime estimates were conservative by roughly an order of magnitude — every step completes
in well under a second — and memory estimates were accurate within a factor of two. Whole-
session peak RSS was 540 MB, dominated by the interpreter and libraries rather than
the data itself. Saved storage totals:

| file | size |
|---|---|
| | `marketplace.sqlite` | 24.4 MB |
| `outputs/features.csv` | 7.4 MB |
| `outputs/labels.csv` | 0.7 MB |
| `outputs/feature_dictionary.csv` | 9 kB |
| `outputs/analysis_summary.json` | 6 kB |
| `outputs/features_summary.json` | 4 kB |
| `outputs/chart_data/q3_state_late_rates.csv` | 2 kB |
| `outputs/cleaning_audit.csv` | 2 kB |
| `outputs/chart_data/q1_delay_histogram.csv` | 0 kB |
| `outputs/chart_data/q2_window_late_rates.csv` | 0 kB |
| `outputs/environment.txt` | 0 kB | |

The resource picture confirms the Section 2 judgement: at 20k orders the pipeline is trivial
in absolute terms, so clarity and auditability were optimised over micro-efficiency, while
the estimates-vs-measurements discipline demonstrates the measurements would catch any
regression if the extract grew.

## 7. Limitations

The extract is a modified sample: 20,000 orders over 2016–2018, not the full marketplace, so
absolute rates should not be extrapolated. 14.2% of retained orders cannot be labelled; the
labelled subset skews toward completed, date-consistent deliveries, and although the
sensitivity analysis bounds the headline rate, unlabelled orders' counterfactual outcomes are
unknowable from this data. Customer geography suffers 1,064 missing locations and 1,062
cities that could not be confidently matched to the IBGE municipality list; state-level
findings exclude those orders. Catalogue gaps (weight, dimensions, photos) are optional
fields and are flagged rather than imputed. Finally, all associations — window length,
geography, basket composition — describe this extract; they motivate where operations should
look first, but they do not establish causal levers. The feature table is deliberately
restricted to approval-time information and was verified free of the brief's banned inputs,
so a prediction model built on it will not leak post-approval outcomes.
