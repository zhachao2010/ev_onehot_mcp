# DHFR demo dataset

Minimal smoke-test data for ev_onehot. Files here are deliberately tiny so the
whole pipeline runs in seconds (CPU only, no GPU). **Numbers are synthetic** —
the `log_fitness` values were generated with `random.seed(42)` from
`plugin/example/scripts/generate_demo_data.py`, so do **not** read the predictions
as a real fitness landscape.

## Contents

| File | Lines | What |
|---|---|---|
| `wt.fasta` | 4 | DHFR query sequence (158 aa), shared with `plmc_mcp/examples/DHFR.a3m` |
| `data.csv` | 41 | 1 WT row + 39 single-point mutants, columns `seq, log_fitness` |
| `plmc/uniref100.model_params` | ❌ | **Not shipped** — see "Building PLMC params" below |

## Why no `plmc/uniref100.model_params`?

PLMC's binary Potts model is **20–200 MB** per protein and is uniquely derived
from the MSA + plmc training run. Committing it to git would bloat history and
isn't reproducible without the upstream `plmc` binary. So this folder only
ships the *inputs* needed to build it.

## Building PLMC params (one-time setup)

You need the sibling `plmc_mcp` repository checked out for the `DHFR.a3m`
alignment + the `rm_a2m_query_gaps.py` helper. From the **ev_onehot_mcp repo
root**:

```bash
# Get plmc_mcp + build its docker image (once)
git clone https://github.com/MacromNex/plmc_mcp /tmp/plmc_mcp
cd /tmp/plmc_mcp && docker build -t plmc:latest .

# Build DHFR's model_params into plugin/example/DHFR/plmc/
cd /path/to/ev_onehot_mcp
bash plugin/example/scripts/build_plmc_model.sh /tmp/plmc_mcp
```

End state:

```
plugin/example/DHFR/
├── wt.fasta
├── data.csv
└── plmc/
    ├── uniref100.model_params    ← ~50 MB, built from DHFR.a3m
    └── uniref100.EC              ← PLMC pair-coupling side product
```

## Run the smoke tests

```bash
# Build ev_onehot image once
docker build -t ev_onehot:latest .

# Train: 5-fold CV; should print "Average Spearman correlation over 5 folds: ..."
bash plugin/example/scripts/smoke_train.sh

# Predict: scores the same 40 rows; should produce data.csv_pred.csv
bash plugin/example/scripts/smoke_predict.sh
```

Total wall time on a laptop CPU: **~10 seconds** (small alignment → fast
ΔH calculation; 39 examples → tiny Ridge fit).

## What success looks like

`smoke_train.sh` end of output:

```
INFO     | __main__:<module>:NN - Data path /data -----
Spearman correlation on test set: -0.xxx
... (5 folds)
Average Spearman correlation over 5 folds: -0.xxx ± 0.xxx
OK: train smoke passed
  ridge_model.joblib = 384K
```

The correlation will be **near zero or negative** because `log_fitness` is
random noise — this is expected. We're verifying the pipeline runs, not
that the model is accurate.

`smoke_predict.sh`:

```
OK: predict smoke passed — 40 predictions in data.csv_pred.csv
,seq,log_fitness,pred_fitness
0,MISL...,0.000,-0.123
1,MISL...,-0.146,-0.456
```

The `pred_fitness` column is what the model produced.
