#!/usr/bin/env python3
"""Regenerate example/DHFR/data.csv from a deterministic seed.

Run from repo root:
    python example/scripts/generate_demo_data.py

Produces a synthetic single-mutant scan over DHFR (158 aa) with random
log_fitness values in [-2, 0.5]. Numbers are NOT meaningful — they exist
only to exercise the ev_onehot training pipeline end-to-end.
"""
import csv
import random
from pathlib import Path

WT = (
    "MISLIAALAVDRVIGMENAMPWNLPADLAWFKRNTLNKPVIMGRHTWESIGRPLPGRKNI"
    "ILSSQPGTDDRVTWVKSVDEAIAACGDVPEIMVIGGGRVYEQFLPKAQKLYLTHIDAEVE"
    "GDTHFPDYEPDDWESVFSEFHDADAQNSHSYCFEILERR"
)
# 20 standard AA — must be subset of util.is_valid_seq's "MRHKDESTNQCUGPAVIFYWLO"
AA_POOL = "MRHKDESTNQCGPAVIFYWL"

N_VARIANTS = 39
SEED = 42

random.seed(SEED)

rows = [("seq", "log_fitness"), (WT, "0.000")]
seen = {WT}
attempts = 0
while len(rows) < N_VARIANTS + 2 and attempts < 500:
    attempts += 1
    pos = random.randint(0, len(WT) - 1)
    wt_aa = WT[pos]
    mut_aa = random.choice(AA_POOL)
    if mut_aa == wt_aa:
        continue
    mut_seq = WT[:pos] + mut_aa + WT[pos + 1:]
    if mut_seq in seen:
        continue
    seen.add(mut_seq)
    lf = random.uniform(-2.0, 0.5)
    rows.append((mut_seq, f"{lf:.3f}"))

out_path = Path(__file__).resolve().parent.parent / "DHFR" / "data.csv"
with open(out_path, "w", newline="") as f:
    csv.writer(f).writerows(rows)

print(f"wrote {len(rows) - 1} rows to {out_path}")
print(f"  WT length = {len(WT)}")
print(f"  seed = {SEED}, AA pool = {len(AA_POOL)} symbols")
