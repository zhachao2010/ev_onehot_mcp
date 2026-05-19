#!/usr/bin/env bash
# Smoke run of the ev_onehot pipeline with clean input/output separation.
#
# Inputs (read-only mount at /inputs):
#   data.csv                       — seq, log_fitness training data
#   wt.fasta                       — wild-type protein sequence
#   plmc/uniref100.model_params    — Potts model from plmc
#
# Outputs (writable mount at /outputs):
#   ridge_model.joblib             — train output
#   data.csv_pred.csv              — predict output
#
# Usage:
#   bash plugin/example/run_docker.sh <input_dir> <output_dir>
#
# Example:
#   bash plugin/example/run_docker.sh \
#     $PWD/plugin/example/inputs \
#     $PWD/plugin/example/outputs
set -euo pipefail

input_dir="${1:?Usage: $0 <input_dir> <output_dir>}"
output_dir="${2:?Usage: $0 <input_dir> <output_dir>}"

# Cleanup previous artifacts so we can tell what's fresh
mkdir -p "$output_dir"
rm -f "$output_dir/ridge_model.joblib" "$output_dir/data.csv_pred.csv"

# Input file preparing
[ -f "$input_dir/wt.fasta" ] || { echo "FAIL: missing wt.fasta"; exit 1; }
[ -f "$input_dir/data.csv" ] || { echo "FAIL: missing data.csv"; exit 1; }
[ -f "$input_dir/plmc/uniref100.model_params" ] || { echo "FAIL: missing plmc/uniref100.model_params"; exit 1; }

# Train — writes ridge_model.joblib to /outputs (NOT to /inputs)
docker run -it --rm \
    -v "$input_dir:/inputs:ro" \
    -v "$output_dir:/outputs" \
    ev_onehot:latest \
    python repo/ev_onehot/train.py /inputs --cross_val --output-dir /outputs

[ -f "$output_dir/ridge_model.joblib" ] || { echo "FAIL: ridge_model.joblib not produced in /outputs"; exit 1; }

# Predict — reads model from /outputs, writes predictions back to /outputs.
# data_path remains /inputs (for wt.fasta + plmc/), but --model-dir steers
# load_model to /outputs.
docker run -it --rm \
    -v "$input_dir:/inputs:ro" \
    -v "$output_dir:/outputs" \
    ev_onehot:latest \
    python repo/ev_onehot/pred.py /inputs \
        --model-dir /outputs \
        --output-dir /outputs \
        --seq_path /inputs/data.csv

# Check result
[ -f "$output_dir/data.csv_pred.csv" ] || { echo "FAIL: data.csv_pred.csv not produced in /outputs"; exit 1; }
n=$(($(wc -l < "$output_dir/data.csv_pred.csv") - 1))
echo
echo "OK: predict passed — $n predictions in $output_dir/data.csv_pred.csv"
