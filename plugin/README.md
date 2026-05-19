# ev_onehot Docker quick reference

## Build image
```bash
docker build -f plugin/Dockerfile -t ev_onehot .
```
（国内环境如需手动下载依赖：把安装包放到 `dependency/`，再用 `Dockerfile.cn` 编译。）

## Inputs / Outputs separation

`train.py` 和 `pred.py` 现在都支持把 output 写到独立目录，跟 input 完全分开：

- `/inputs`：只读，含 `wt.fasta` / `data.csv` / `plmc/uniref100.model_params`
- `/outputs`：可写，承接 `ridge_model.joblib` (train 产物) + `<seq_file>_pred.csv` (predict 产物)

这样 train 的产物可以直接作为下游 predict 的 `--model-dir` 输入，工作流串得起来。

## 测试指令

### Train（推荐写法，output 分离到 /outputs）

```bash
docker run -it --rm \
    -v $input_dir:/inputs:ro \
    -v $output_dir:/outputs \
    ev_onehot:latest \
    python repo/ev_onehot/train.py /inputs --cross_val --output-dir /outputs
```

跑完 `$output_dir/ridge_model.joblib` 落地。

### Predict（用刚才训出来的 model）

```bash
docker run -it --rm \
    -v $input_dir:/inputs:ro \
    -v $output_dir:/outputs \
    ev_onehot:latest \
    python repo/ev_onehot/pred.py /inputs \
        --model-dir /outputs \
        --output-dir /outputs \
        --seq_path /inputs/data.csv
```

跑完 `$output_dir/data.csv_pred.csv` 落地。

### 端到端 smoke 脚本

```bash
bash plugin/example/run_docker.sh \
    $PWD/plugin/example/inputs \
    $PWD/plugin/example/outputs
```

脚本会顺序跑 train + predict，检查产物，所有输出落到 `$output_dir`。

## 向后兼容

如果不传 `--output-dir`，train 仍把模型写回 `data_dir`（即 /inputs），跟旧行为一致。
同样不传 `--model-dir` 时 predict 也从 `data_path` 找 `ridge_model.joblib`。

## 检查结果

```bash
cd $output_dir   # e.g. plugin/example/outputs
ls -lh ridge_model.joblib data.csv_pred.csv
head -3 data.csv_pred.csv
```
