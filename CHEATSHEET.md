# ev_onehot — CLI / Docker cheatsheet

EV+OneHot Ridge 回归 fitness predictor（Hsu et al. 2022, *Nat Biotechnol*）。CPU 跑得动，不需 GPU。

**先决条件**：已有 plmc 产出的 `*.model_params`（见 `../plmc_mcp/CHEATSHEET.md`）。

---

## 输入文件契约

无论 CLI 还是 Docker，data_dir 都必须长这样：

```
<data_dir>/
├── data.csv               # 列: seq, log_fitness
├── wt.fasta               # 单条 WT 序列
└── plmc/
    └── uniref100.model_params   # plmc 训出来的 Potts 模型参数（文件名可改）
```

- `data.csv` 的 `seq` 列必须跟 `wt.fasta` **同长度**
- `log_fitness` 越大越好（log enrichment ratio 之类）
- predict 时 data_dir 还必须有 `ridge_model.joblib`（训练阶段产物）

---

## 方案 1：纯 CLI（host 上有 conda）

```bash
# 仓库根目录
cd /path/to/ev_onehot_mcp

# 一次性装环境
mamba create -p ./env python=3.10 pip -y
./env/bin/pip install -r requirements.txt
./env/bin/pip install --ignore-installed fastmcp

# Train — 5 折交叉验证
./env/bin/python repo/ev_onehot/train.py /path/to/data_dir --cross_val

# Train — train/test split (seed=1)
./env/bin/python repo/ev_onehot/train.py /path/to/data_dir -s 1

# Predict (data_dir 内必须有 ridge_model.joblib)
./env/bin/python repo/ev_onehot/pred.py /path/to/data_dir \
    --seq_path /path/to/sequences_to_score.csv
```

**train.py 关键产物**：`ridge_model.joblib` 直接写到 `data_dir`。
stdout 打印：

- 5-fold: `Average Spearman correlation over 5 folds: 0.xxx ± 0.xxx`
- split: `Spearman correlation on test set: 0.xxx`

**pred.py 关键产物**：`{seq_path}_pred.csv`（hard-coded：跟输入 csv 同目录、文件名后缀 `_pred.csv`）。`pred_fitness` 列即模型打分。

---

## 方案 2：Docker

### 2.1 Build 镜像

```bash
cd /path/to/ev_onehot_mcp
docker build -t ev_onehot:latest .
```

镜像内布局：`/app/repo/ev_onehot/{train.py,pred.py}`，base 是 `python:3.10-slim`，无 GPU 依赖。

### 2.2 Train

```bash
# host 上 /data/job/ 是工作目录，必含 data.csv + wt.fasta + plmc/
mkdir -p /data/job/output

docker run --rm \
  -v /data/job:/data \
  -v /data/job/output:/output \
  ev_onehot:latest \
  python /app/repo/ev_onehot/train.py /data --cross_val
```

跑完检查 `/data/job/ridge_model.joblib`。完整 bundle = `ridge_model.joblib` + `wt.fasta` + `plmc/uniref100.model_params`。

### 2.3 Predict

```bash
# 训练产物 bundle 在 /data/bundle/, 待预测 csv 在 /data/job/sequences.csv
mkdir -p /data/job/output

docker run --rm \
  -v /data/bundle:/model:ro \
  -v /data/job:/data \
  -v /data/job/output:/output \
  ev_onehot:latest \
  python /app/repo/ev_onehot/pred.py /model \
    --seq_path /data/sequences.csv
```

`/data/bundle/` 必含：

```
/data/bundle/
├── ridge_model.joblib
├── wt.fasta
└── plmc/uniref100.model_params
```

跑完检查 `/data/job/sequences.csv_pred.csv`（pred.py 把 `_pred.csv` 写在输入 csv 同目录）。

### 2.4 把镜像送到服务器

```bash
docker save ev_onehot:latest | gzip > /tmp/ev_onehot.tar.gz
scp /tmp/ev_onehot.tar.gz server:~/
ssh server "gunzip -c ~/ev_onehot.tar.gz | docker load"
```

---

## 端到端：plmc → ev_onehot 串联示例

详见 `../plmc_mcp/CHEATSHEET.md` 末尾的 "ev_onehot 端到端串联" 段。
