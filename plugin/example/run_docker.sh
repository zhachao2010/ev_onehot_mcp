input_dir=$1 # /home/zhac/github/ev_onehot_mcp/plugin/example/inputs
output_dir=$2 # /home/zhac/github/ev_onehot_mcp/plugin/example/outputs

# Cleanup previous artifacts so we can tell what's fresh
rm -f "$input_dir/ridge_model.joblib"

# train file preparing
[ -f "$input_dir/wt.fasta" ] || { echo "FAIL: missing wt.fasta"; exit 1; }
[ -f "$input_dir/plmc/uniref100.model_params" ] || { echo "FAIL: missing plmc/uniref100.model_params"; exit 1; }

# train
docker run -it --rm  \
    -v $input_dir:/inputs \
    -v $output_dir:/outputs \
    ev_onehot:latest \
    python repo/ev_onehot/train.py /inputs --cross_val

# predict file preparing
[ -f "$input_dir/data.csv" ] || { echo "FAIL: missing data.csv"; exit 1; }
[ -f "$input_dir/ridge_model.joblib" ] || { echo "FAIL: ridge_model.joblib not produced"; exit 1; }

# predict
docker run -it --rm  \
    -v $input_dir:/inputs \
    -v $output_dir:/outputs \
    ev_onehot:latest \
    python repo/ev_onehot/pred.py /inputs --seq_path /inputs/data.csv

# check result
[ -f "$input_dir/data.csv_pred.csv" ] || { echo "FAIL: data.csv_pred.csv not produced"; exit 1; }
n=$(($(wc -l < "$input_dir/data.csv_pred.csv") - 1))
echo
echo "OK: predict passed — $n predictions in data_pred.csv"
