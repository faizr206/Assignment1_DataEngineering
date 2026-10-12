# ENG2040 Assignment 1 — Data Acquisition to Model-Ready Dataset

Marketplace orders and delivery outcomes: a reproducible pipeline that turns the
supplied raw SQL extract into cleaned order data, business findings, and a
leakage-free feature table with delivery labels for a future late-delivery model.

Read `assignment_01_brief.pdf` for the task, assessment criteria, data notes and
expected outputs. The written report is in **`report.md`**.

## Reproduce everything with one command

```sh
bash run_pipeline.sh
```

This rebuilds `marketplace.sqlite` from `data/raw.sql`, executes
`notebook.ipynb` end-to-end, and (re)writes every file under `outputs/`.
The original SQL file is never modified. Total runtime is about a minute;
peak memory of the whole run stays well under 1 GB.

**Requirements:** Python 3.10+ with `pandas`, `numpy`, `matplotlib`,
`seaborn`, `xlrd`, `rapidfuzz`, and Jupyter/nbconvert
(`pip install nbconvert` if missing). No database server — SQLite is built in.

## Manual steps (what the script automates)

1. **Build the database** — `python3 setup_db.py` imports `data/raw.sql` into
   `marketplace.sqlite` without cleaning it. It will not overwrite an existing
   database; use `python3 setup_db.py --db another_name.sqlite` for a copy.
2. **Run the notebook** — open `notebook.ipynb` and run all cells (or run
   `python3 -m jupyter nbconvert --to notebook --execute --inplace notebook.ipynb`).
   Every executed SQL statement is inline in the notebook's `--sql` cells.

## Pipeline map (notebook section → inputs → outputs)

| step (notebook section) | inputs | outputs | row meaning / how to load |
|---|---|---|---|
| 1. Loading the Data | `data/raw.sql` → `marketplace.sqlite` | `order_raw_df` in memory: one row per order (20,000 rows) | one order per row; children (items, payments, reviews) aggregated to order grain first; every merge asserted row-count- and totals-preserving |
| 2. Data Quality and Cleaning | `order_raw_df` | `order_clean_df` (18,954 retained orders) + `outputs/cleaning_audit.csv` | retained orders have a logical date sequence; all 15 cleaning rules (R01–R15) are logged with records affected; nothing is dropped silently |
| 3. Exploratory Analysis | `order_clean_df` | label `delivered_after_estimate` + `outputs/analysis_summary.json`, `outputs/chart_data/*.csv` | labelled subset = 16,262 usable completed deliveries; answers to the three business questions with sensitivity checks |
| 4. Feature Engineering | `order_clean_df` + label | `outputs/features.csv`, `outputs/labels.csv`, `outputs/feature_dictionary.csv` | feature matrix: one row per retained order, approval-time information only; `order_id` is the join key (index), **not** a predictor. Load with `pd.read_csv("outputs/features.csv", index_col="order_id")` |
| 5. Reproducibility | all of the above | `outputs/resources.json`, `outputs/environment.txt`, `report.md`, this README | estimated vs measured resources per pipeline step; environment versions |

## Output files

| file | contents |
|---|---|
| `outputs/features.csv` | numerical feature table (18,954 × 81), index `order_id` |
| `outputs/labels.csv` | `delivered_after_estimate` per order; `NaN` = unlabelled (cancelled / unknown / unreliable outcomes, per the brief) |
| `outputs/feature_dictionary.csv` | meaning, dtype, derivation and missing-policy of every feature |
| `outputs/cleaning_audit.csv` | every cleaning rule (R01–R15), action, records affected, effect on results |
| `outputs/analysis_summary.json` | machine-readable results: label stats, Q1–Q3 answers, sensitivity table |
| `outputs/features_summary.json` | feature-table shape, dtypes, missing counts |
| `outputs/resources.json` | estimated vs measured runtime/memory per step; storage footprint |
| `outputs/environment.txt` | exact package versions |
| `outputs/chart_data/*.csv` | data behind every chart |

`labels.csv` and `features.csv` share the same `order_id` index, so
`features.join(labels, how="inner").dropna(subset=["delivered_after_estimate"])`
is the model-ready training matrix (16,262 labelled orders).

## The label

`delivered_after_estimate` is 1 for a usable completed delivery **after** the
estimated calendar date and 0 for on-time/early (delivery *on* the estimated
date counts as on time). Cancelled, unknown or unreliable outcomes stay
unlabelled (`NaN`). Timestamps use the recorded local clock; no UTC offset is
supplied.

## Dataset

Modified version of Olist's Brazilian E-Commerce Public Dataset, for
educational purposes only. Source licence: CC BY-NC-SA 4.0. Findings concern
this modified extract; associations do not establish causation.
