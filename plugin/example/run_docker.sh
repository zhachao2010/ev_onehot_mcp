input_dir=$1 # /home/zhac/github/ev_onehot_mcp/plugin/example/inputs  <wt.fasta, plmc/uniref100.model_params, data.csv>
output_dir=$2 # /home/zhac/github/ev_onehot_mcp/plugin/example/outputs <ridge_model.joblib, data_pred.csv>

# Cleanup previous artifacts so we can tell what's fresh
mkdir -p "$output_dir"
rm -f "$output_dir/ridge_model.joblib" "$output_dir/data.csv_pred.csv"

# Input file preparing
[ -f "$input_dir/wt.fasta" ] || { echo "FAIL: missing wt.fasta"; exit 1; }
[ -f "$input_dir/plmc/uniref100.model_params" ] || { echo "FAIL: missing plmc/uniref100.model_params"; exit 1; }

# Train — writes ridge_model.joblib to /outputs (NOT to /inputs)
docker run -it --rm \
    -v "$input_dir:/inputs:ro" \
    -v "$output_dir:/outputs" \
    ev_onehot:latest \
    python repo/ev_onehot/train.py /inputs --cross_val --output-dir /outputs

[ -f "$input_dir/data.csv" ] || { echo "FAIL: missing data.csv"; exit 1; }
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
