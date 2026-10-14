#!/bin/sh
# ENG2040 Assignment 1 - one-command reproduction of every pipeline output.
#
# Rebuilds the SQLite database from the supplied data/raw.sql, executes
# notebook.ipynb end-to-end, and (re)writes everything under outputs/.
#
# Usage:   bash run_pipeline.sh
set -e
cd "$(dirname "$0")"

echo "==> 0/3 checking dependencies"
python3 - <<'EOF'
import sys
missing = []
for mod in ("pandas", "numpy", "matplotlib", "seaborn", "xlrd", "rapidfuzz",
            "sklearn", "shap"):
    try:
        __import__(mod)
    except ImportError:
        missing.append(mod)
if missing or sys.version_info < (3, 10):
    raise SystemExit(
        f"Python 3.10+ required (found {sys.version.split()[0]}); "
        f"missing packages: {', '.join(missing) or 'none'}"
    )
print("    dependencies OK")
EOF

echo "==> 1/3 rebuilding marketplace.sqlite from data/raw.sql"
# setup_db.py refuses to overwrite an existing database, and a fresh
# reproduction must start from the untouched raw file.
rm -f marketplace.sqlite
python3 setup_db.py

echo "==> 2/3 executing notebook.ipynb end-to-end"
rm -rf outputs
python3 -m jupyter nbconvert --to notebook --execute --inplace notebook.ipynb \
    --ExecutePreprocessor.timeout=1800

echo "==> 3/3 done"
echo "    outputs/  features.csv, labels.csv, feature_dictionary.csv,"
echo "              cleaning_audit.csv, analysis_summary.json,"
echo "              features_summary.json, shap_importance.csv,"
echo "              shap_summary.json, shap_beeswarm.png, resources.json,"
echo "              environment.txt, chart_data/, and the executed notebook."
