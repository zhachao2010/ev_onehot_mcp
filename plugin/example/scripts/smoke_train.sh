#!/usr/bin/env bash
# Smoke test: run ev_onehot train on the DHFR demo dataset (5-fold CV).
# Expects plugin/example/DHFR/plmc/uniref100.model_params to already exist (run
# plugin/example/scripts/build_plmc_model.sh first).
#
# Usage:
#   bash plugin/example/scripts/smoke_train.sh

set -euo pipefail

EXAMPLE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WS="$EXAMPLE_ROOT/DHFR"

[ -f "$WS/wt.fasta" ]                         || { echo "FAIL: missing wt.fasta"; exit 1; }
[ -f "$WS/data.csv" ]                         || { echo "FAIL: missing data.csv"; exit 1; }
[ -f "$WS/plmc/uniref100.model_params" ]      || {
    echo "FAIL: missing plmc/uniref100.model_params"
    echo "Run: bash plugin/example/scripts/build_plmc_model.sh /path/to/plmc_mcp"
    exit 1
}

# Cleanup previous artifacts so we can tell what's fresh
rm -f "$WS/ridge_model.joblib"

docker run --rm \
  -v "$WS:/data" \
  ev_onehot:latest \
  python /app/repo/ev_onehot/train.py /data --cross_val

[ -f "$WS/ridge_model.joblib" ] || { echo "FAIL: ridge_model.joblib not produced"; exit 1; }
echo
echo "OK: train smoke passed"
echo "  ridge_model.joblib = $(du -h "$WS/ridge_model.joblib" | cut -f1)"
