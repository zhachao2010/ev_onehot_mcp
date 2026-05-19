# ev_onehot 代码阅读指南（数据流视角）

本指南从「数据怎么流经代码」的角度带你快速熟悉 `repo/ev_onehot/`，以及 `src/` 这层 MCP wrapper 是怎么包它的。

约定：本文里的 **`repo/`** 指 `repo/ev_onehot/`，**`src/`** 指 `src/tools/`。

---

## 1. 仓库分层

```
ev_onehot_mcp/
├── repo/ev_onehot/         ← 论文原始代码（train.py / pred.py / predictor.py / couplings_model.py / util.py）
│                              这是 PDAgent / CLI / Docker 实际跑的"算法层"
├── src/                    ← FastMCP wrapper（上游自带的 MCP）
│   ├── server.py           ← 入口：把 train.py 和 pred.py 的 MCP 子树挂到主 server
│   └── tools/              ← 把 repo/ 函数包成 @mcp.tool；多了几个"低阶工具"（细粒度训练 / 耦合分析）
├── examples/               ← 样例数据（？无 —— 只有 README 里说 `example/LanM/` 但实际不在 repo 里）
├── Dockerfile              ← python:3.10-slim + 装 repo/ 依赖 + src/ + 默认 CMD 跑 src/server.py
└── CHEATSHEET.md           ← CLI / Docker 调用样例
```

**关键认知**：
- `repo/` 里 5 个文件就是论文方法的全部代码，**约 1500 行**（其中 `couplings_model.py` 1100 行是 EVcouplings 项目的子集，做 Potts 模型的 numba 加速实现）
- `src/` 是上游写的 FastMCP server，**约 2300 行**。PDAgent 实际**不用**这层 —— PDAgent wrapper 直接调 `repo/` 的 CLI 脚本（`docker run ... python /app/repo/ev_onehot/train.py ...`）
- 想搞懂这个项目就读 `repo/`；想了解上游 MCP 接口设计就读 `src/`

---

## 2. 数据流（核心）

### 2.1 输入

```
<data_dir>/
├── wt.fasta                        ← 1 条 WT 序列
├── data.csv                        ← N 条变体 + log_fitness 标签
└── plmc/uniref100.model_params     ← Potts 模型参数（plmc 训出来的二进制）
```

### 2.2 Train 流（`python repo/ev_onehot/train.py <data_dir> [--cross_val | -s <seed>]`）

```
                       train.py:main
                       ───────────────
                              │
              read data.csv (pd.read_csv)
                              │
              filter is_valid_seq  (util.py — 长度+合法 AA 字符)
                              │
                ┌─────────────┴─────────────┐
        --cross_val ?                       (else: train-test split)
        5 fold KFold                        train_test_split(test_size=0.2)
                              │
                              ▼
                  train_test_eval(train, test)
                  ──────────────────────────
                              │
            ┌─────────────────┴─────────────────┐
            ▼                                   ▼
   train_predictor(data_dir, train, save_path, reg_coef='CV')
            │
            ▼
   JointPredictor(data_dir, [EVPredictor, OnehotRidgePredictor], 'ev+onehot')
            │
            ├─ EVPredictor 初始化:
            │      load CouplingsModel(plmc/uniref100.model_params)
            │      load wt.fasta
            │      validate: WT 序列每个位点 == model.target_seq    ← 不匹配直接 raise
            │
            ├─ OnehotRidgePredictor 初始化（轻量，只记 reg_coef=1.0）
            │
            ▼
   JointPredictor.train(seqs, labels):  
            │
            ├─ seq2feat(seqs)  ← 关键：拼接两组特征
            │   ┌── EVPredictor.seq2feat(seqs):
            │   │     用 CouplingsModel.delta_hamiltonian 算每条 seq 的 ΔH → shape (N, 1)
            │   │     再除以 sqrt(reg_coef=1e-8) 放大（Ridge 等价于反向缩小正则强度）
            │   │
            │   └── OnehotRidgePredictor.seq2feat(seqs):
            │         util.seqs_to_onehot → shape (N, L*24)
            │         除以 sqrt(reg_coef=1.0)
            │   
            │   concat → X shape (N, 1 + L*24)
            │
            ├─ CV 调优 JointPredictor 自己的 reg_coef：
            │     for rc in [0.1, 1, 10, 100, 1000]:
            │         sklearn Ridge(alpha=rc).cross_val_score(X, labels, cv=5, spearman)
            │     pick best
            │
            └─ Ridge(alpha=best_rc).fit(X, labels) → self.model
                              │
                              ▼
            predictor.save_model() → ridge_model.joblib 写到 data_dir
                              │
                              ▼
            test['pred_fitness'] = predictor.predict(test_seqs)
            spearman(pred, test_log_fitness)  → print
```

### 2.3 Predict 流（`python repo/ev_onehot/pred.py <data_dir> --seq_path <csv>`）

```
                       pred.py:main
                       ─────────────
                              │
         seq_df = pd.read_csv(seq_path)   ← 须有 'seq' 列（可配 --seq_col）
                              │
                              ▼
         load_predictor(data_dir):
            │
            ├─ JointPredictor(data_dir, [EVPredictor, OnehotRidgePredictor], 'ev+onehot')
            │   （EVPredictor 重新 load CouplingsModel + wt.fasta，验证）
            │
            └─ predictor.load_model()  ← joblib.load(data_dir/ridge_model.joblib)
                              │
                              ▼
         test_pred = predictor.predict(seq_df['seq'].values)
            │
            ├─ seq2feat(seqs):  同 train，但 reg_coef 已经从 joblib 里恢复
            │
            └─ self.model.predict(X)  → np.ndarray (N,)
                              │
                              ▼
         seq_df['pred_fitness'] = test_pred
         seq_df.to_csv(f'{seq_path}_pred.csv')   ← **hard-coded** 输出位置
            │
            ▼
         (可选) 若 csv 含 log_fitness 列：打印 spearman
```

---

## 3. 文件 / 函数索引

### 3.1 `repo/ev_onehot/util.py`（128 行）—— 通用工具

| 符号 | 类型 | 作用 |
|---|---|---|
| `aa_to_int`, `int_to_aa` | dict | 22 种 AA + start/stop/gap 的整数编码（共 26 个 token） |
| `is_valid_seq(seq, max_len=2000)` | fn | 长度 < 2000 且只含 22 种合法 AA。train.py 用它筛掉不合规变体 |
| `aa_seq_to_int(s)` | fn | `[start_token, *aa_ints, stop_token]` |
| `spearman(y_pred, y_true)` | fn | scipy spearmanr，方差太小返 0（避免 NaN） |
| `ndcg(y_pred, y_true)` | fn | sklearn ndcg_score，标准化 y_true 后调 |
| `auroc(y_pred, y_true, y_cutoff=1.0)` | fn | 用 `y_true >= cutoff` 做二分类 AUROC |
| `format_seq(seq, stop=False)` | fn | 调用 `aa_seq_to_int` 并可选去掉 stop |
| `format_batch_seqs(seqs)` | fn | 批量 + zero-pad 到最长长度 → ndarray (N, maxlen) |
| **`seqs_to_onehot(seqs)`** | fn | **OnehotRidgePredictor 的特征**：先 batch encode，再展平成 (N, maxlen × 24) 的二值矩阵。注意：是 maxlen，不是 WT len —— 如果输入有插入则维度会爆 |
| `get_wt_seq(mutation_descriptions)` | fn | 从 `[A12T, R45K, ...]` 反推 WT 序列（用 placeholder `?` 填空，矛盾就 assert） |
| **`seq2mutation(seq, model, offset=1)`** | fn | 把变体 seq 跟 `model.target_seq` 比对，返回 `[(pos, wt_aa, mut_aa), ...]` |
| **`seq2effect(seqs, model, offset=1)`** | fn | **EVPredictor 的特征**：对每条 seq 调 `seq2mutation` → `model.delta_hamiltonian(mutations)` → ΔH 标量 → shape (N,) |
| `mutant2seq(mut, wt, offset)` | fn | 把 `A12T:R45K` 反向写成 full seq |

### 3.2 `repo/ev_onehot/predictor.py`（130 行）—— 预测器类层级

```
BaseRegressionPredictor
  ├── OnehotRidgePredictor   reg_coef=1.0     seq2feat = seqs_to_onehot
  ├── EVPredictor            reg_coef=1e-8    seq2feat = seq2effect[:, None]
  └── JointPredictor         reg_coef='CV'    seq2feat = concat(p.seq2feat / sqrt(p.reg_coef))
```

| 符号 | 类型 | 作用 |
|---|---|---|
| `REG_COEF_LIST = [0.1, 1, 10, 100, 1000]` | const | JointPredictor CV 搜索网格 |
| `read_fasta(filename, return_ids=False)` | fn | Bio.SeqIO 简单封装 |
| **`BaseRegressionPredictor`** | class | `train` / `predict` / `save_model` / `load_model` 的基类。train 支持 `'CV'` 自动调正则 |
| `BaseRegressionPredictor.train(seqs, labels)` | method | seq2feat → 可选 5-fold spearman CV 选 alpha → 最终 fit |
| `BaseRegressionPredictor.predict(seqs)` | method | 若 model 未训过，返回随机数（**注意**） |
| `BaseRegressionPredictor.save_model()` | method | `joblib.dump(self.model, data_path/ridge_model.joblib)` |
| `BaseRegressionPredictor.load_model()` | method | 对应 load |
| **`OnehotRidgePredictor`** | class | 简单 onehot + Ridge。**重写 seq2feat = seqs_to_onehot** |
| **`EVPredictor`** | class | 加载 `CouplingsModel` + `wt.fasta`，**做兼容性 check**（WT 每位 == model.target_seq；不匹配 raise ValueError） |
| `EVPredictor.seq2score(seqs)` | method | 调 `seq2effect` 拿 ΔH 标量 |
| `EVPredictor.seq2feat(seqs)` | method | `seq2score(seqs)[:, None]`（变成单列特征） |
| `EVPredictor.predict_unsupervised(seqs)` | method | 直接用 ΔH 当 fitness 预测（不需要训过 Ridge） |
| **`JointPredictor`** | class | 把多个 predictor 的特征 concat。把每组特征除以 `sqrt(p.reg_coef)`，**等价于每组单独有不同正则强度**（数学技巧） |
| `JointPredictor.seq2feat(seqs)` | method | concat features，shape (N, sum(feat_dims)) |

### 3.3 `repo/ev_onehot/couplings_model.py`（1104 行）—— Potts 模型

这是从 EVcouplings 项目摘出来的 `CouplingsModel`。**numba JIT 加速**是它的性能要害。

| 符号 | 类型 | 作用 |
|---|---|---|
| `_hamiltonians(sequences, J_ij, h_i)` | @jit fn | 给一批 seq 算 H = Σh + ΣJ。返回 (N, 3)：[total, J 部分, h 部分] |
| `_single_mutant_hamiltonians(target_seq, J_ij, h_i)` | @jit fn | 算所有单点突变 ΔH，返回 (L, 21, 3) |
| `_delta_hamiltonian(pos, subs, target_seq, J_ij, h_i)` | @jit fn | 多位点突变 ΔH（J_ij 含交叉项） |
| **`CouplingsModel`** | class | 读 plmc 二进制 `.model_params`，提供 `delta_hamiltonian(mutations)` / `hamiltonians(seqs)` / `single_mutant_hamiltonians()` |
| `CouplingsModel.target_seq` | attr | plmc 训练用的 focus 序列（query） |
| `CouplingsModel.index_map` | attr | dict：focus 序列位置 → model 内部 0-indexed 位点 |
| `CouplingsModel.delta_hamiltonian(mutations)` | method | 输入 `[(pos, wt_aa, mut_aa), ...]` → ΔH。`util.seq2effect` 内部调用它 |
| `CouplingsModel.alphabet` | attr | 字符表，通常是 `'-ACDEFGHIKLMNPQRSTVWY'`（21 字符含 gap） |

> 想完全读懂 1100 行不必：**90% 的使用面只用到 `delta_hamiltonian` 一个方法**（被 `util.seq2effect` 调）。numba 那几个 `_xxx` 函数是性能内核，类方法是 Python 层包装。第一次读直接看 class `__init__`（怎么读 plmc 二进制）+ `delta_hamiltonian` 即可。

### 3.4 `repo/ev_onehot/train.py`（92 行）—— CLI 入口

| 符号 | 作用 |
|---|---|
| `train_predictor(data_dir, train, save_path, predictor_name, reg_coef)` | 实例化 JointPredictor + train + save_model |
| `train_test_eval(data_df, train, test, data_dir)` | 调 train_predictor，然后 predict test → 算 spearman → 打印 |
| `main(args)` | 1) read data.csv 2) 可选 filter is_valid 3) `--cross_val` 走 5-fold KFold 各 fold 调 train_test_eval / 否则 `--test_data_path` 用指定 test / 否则 random split | 
| `parse_args()` | argparse：`data_dir`（位置参数）、`--cross_val`、`-s` seed、`--test_size`、`--ignore_gaps` |

**CLI stdout 提示词**（runner.py 用正则抓这两行）：
- `Spearman correlation on test set: 0.xxx` （每折/单次）
- `Average Spearman correlation over 5 folds: 0.xxx ± 0.xxx`（CV 总结）

### 3.5 `repo/ev_onehot/pred.py`（64 行）—— CLI 入口

| 符号 | 作用 |
|---|---|
| `load_predictor(data_path, predictor_name='ev+onehot')` | JointPredictor + load_model |
| `main(args)` | 读 csv → load_predictor → predict → 写 `{seq_path}_pred.csv`；若 csv 含 `log_fitness` 额外打印 spearman |
| `parse_args()` | `data_path`、`--seq_path`、`--seq_col seq`、`--ignore_gaps` |

---

## 4. `src/` MCP wrapper 速览（**PDAgent 不用，仅供了解上游接口设计**）

```
src/server.py
  ├── mount tools/train.py::train_mcp        ← 暴露 @mcp.tool ev_onehot_train_fitness_predictor
  ├── mount tools/pred.py::pred_mcp          ← 暴露 @mcp.tool ev_onehot_predict_fitness
  └── （tools/predictor.py + tools/couplings_model.py 还暴露了一堆**低阶** tools）
```

### 4.1 高阶 tools（`src/tools/train.py` + `src/tools/pred.py`）

跟 CLI 一一对应：
- `ev_onehot_train_fitness_predictor` → 等价 `python train.py <data_dir> [--cross_val | -s <seed>]`
- `ev_onehot_predict_fitness` → 等价 `python pred.py <data_dir> --seq_path <csv>`

### 4.2 低阶 tools（`src/tools/predictor.py`）

把 `BaseRegressionPredictor` 拆成三个独立 tool，**让 LLM 也能直接训单个预测器**：
- `train_onehot_predictor` — 只训 OnehotRidgePredictor
- `train_ev_predictor` — 只训 EVPredictor
- `train_joint_predictor` — 等价高阶版

### 4.3 耦合分析 tools（`src/tools/couplings_model.py`）

直接调用 `CouplingsModel` 的研究型 tool：
- `evmutation_load_model` — 加载并返回 metadata
- `evmutation_calculate_mutation_effects` — 多点突变 ΔH
- `evmutation_compute_couplings` — 抽 J_ij 子矩阵
- `evmutation_visualize_landscape` — 单点突变热图

> PDAgent 没接入这些低阶 tool。要接的话改 wrapper builder 把 `src/server.py` 的内层 tools 抽出来当独立 entry point。

---

## 5. 推荐阅读顺序

第一次读这个项目时按这个顺序最省脑力：

1. **`repo/ev_onehot/util.py`**（短小）→ 了解 AA 编码、`seqs_to_onehot`、`seq2effect` 这俩**特征工程**怎么算
2. **`repo/ev_onehot/predictor.py`**（130 行）→ 看 3 个 Predictor 类的 `seq2feat` 怎么写，看 `JointPredictor` 怎么把特征 concat 起来给 Ridge
3. **`repo/ev_onehot/train.py`** + **`pred.py`**（短小）→ 看 CLI 怎么把上面的类用起来
4. （**可选**）`repo/ev_onehot/couplings_model.py` 的 `class CouplingsModel.__init__` + `delta_hamiltonian` —— 知道 ΔH 怎么算就行，其他 numba 内核不用关心
5. （**可选**）`src/tools/predictor.py` + `src/tools/couplings_model.py` —— 想做更细粒度 MCP 接口设计时再看

完整路径再串一遍：

```
data.csv (seq, log_fitness)
        │
   util.is_valid_seq                 ← 筛
        │
   train.py.main                     ← KFold or split
        │
   predictor.JointPredictor.train    ← 关键入口
        │
   seq2feat = concat([
       EVPredictor.seq2feat = seq2effect(seqs, CouplingsModel) → ΔH       (1 dim)
       OnehotRidgePredictor.seq2feat = seqs_to_onehot(seqs)               (L*24 dims)
   ])
        │
   sklearn Ridge.fit(X, labels)      ← 简单线性
        │
   joblib.dump → ridge_model.joblib
```

整个项目的精髓就这条数据流；剩下的都是支撑代码。

---

## 6. 常见坑

1. **`seqs_to_onehot` 维度依赖 batch 最长**：onehot 维度 = `maxlen × 24`，不是 `WT_len × 24`。如果 batch 里有插入（比 WT 长），test/train 的特征维度可能不一致 → Ridge 报 shape mismatch。**约定输入 seq 都跟 WT 同长**（CHEATSHEET 也强调）。
2. **`EVPredictor` 严格校验 WT vs PLMC model**：plmc 的 focus 序列必须跟 `wt.fasta` 逐位置一致；不一致直接 `raise ValueError`。这是为了防止你拿一个 PLMC model 配错蛋白。
3. **`pred.py` 输出位置 hard-coded**：写到 `{seq_path}_pred.csv` —— 跟输入 csv 同目录。docker 模式下要确保该目录可写（PDAgent wrapper 把 `inputs/` 挂成 r/w 就是为此）。
4. **`BaseRegressionPredictor.predict` 在 model 未训过时返回随机数**：是个静默 fallback 而不是 raise —— 测试时如果忘了 `load_model()` 又调 `predict()`，会拿到 garbage 但不会报错。
5. **`reg_coef` 的多层语义**：
   - `EVPredictor.reg_coef=1e-8` 是给 `JointPredictor.seq2feat` 的**缩放因子**（除以 sqrt 等价放大特征 ≈ 等价于 Ridge 用极小 alpha，几乎不正则化 EV 那一维）
   - `OnehotRidgePredictor.reg_coef=1.0` 同理（onehot 正常正则）
   - `JointPredictor.reg_coef='CV'` 是 Ridge **真正的** alpha，CV 调
   - 不要把这三个混淆
6. **`util.seqs_to_onehot` 用 24 个 token 维度但实际只用到 ~22**：start/stop/`-` 的位置也展平进去。无害但占内存。
