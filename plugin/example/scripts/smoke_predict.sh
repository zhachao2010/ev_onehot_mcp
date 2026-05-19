#!/usr/bin/env bash
# Smoke test: run ev_onehot predict on the DHFR demo dataset.
# Expects smoke_train.sh to have produced plugin/example/DHFR/ridge_model.joblib first.
#
# Usage:
#   bash plugin/example/scripts/smoke_predict.sh

set -euo pipefail

EXAMPLE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WS="$EXAMPLE_ROOT/DHFR"

[ -f "$WS/ridge_model.joblib" ] || {
    echo "FAIL: missing ridge_model.joblib"
    echo "Run: bash plugin/example/scripts/smoke_train.sh"
    exit 1
}

# Predict on the same data.csv (smoke; in real use seq_path is held-out data)
rm -f "$WS/data.csv_pred.csv"

docker run --rm \
  -v "$WS:/data" \
  ev_onehot:latest \
  python /app/repo/ev_onehot/pred.py /data --seq_path /data/data.csv

[ -f "$WS/data.csv_pred.csv" ] || { echo "FAIL: data.csv_pred.csv not produced"; exit 1; }
n=$(($(wc -l < "$WS/data.csv_pred.csv") - 1))
echo
echo "OK: predict smoke passed — $n predictions in data.csv_pred.csv"
head -3 "$WS/data.csv_pred.csv"
