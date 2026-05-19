#!/usr/bin/env bash
# Build DHFR PLMC model_params from the DHFR.a3m alignment that ships with plmc_mcp.
#
# Output: plugin/example/DHFR/plmc/uniref100.model_params
#
# Prereqs: plmc:latest docker image (built from sibling repo plmc_mcp).
#   git clone https://github.com/MacromNex/plmc_mcp /tmp/plmc_mcp
#   cd /tmp/plmc_mcp && docker build -t plmc:latest .
#
# Usage (from this repo root):
#   bash plugin/example/scripts/build_plmc_model.sh /path/to/plmc_mcp
#
# /path/to/plmc_mcp must contain examples/DHFR.a3m and script/rm_a2m_query_gaps.py.

set -euo pipefail

PLMC_MCP="${1:?Usage: $0 <path-to-plmc_mcp-checkout>}"
[ -f "$PLMC_MCP/examples/DHFR.a3m" ] || { echo "FAIL: $PLMC_MCP/examples/DHFR.a3m not found"; exit 1; }

EXAMPLE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WS="$EXAMPLE_ROOT/DHFR"
mkdir -p "$WS/plmc" "$WS/.plmc_build"

# Step 1: A3M → raw A2M (reformat.pl via plmc docker)
cp "$PLMC_MCP/examples/DHFR.a3m" "$WS/.plmc_build/DHFR.a3m"
docker run --rm \
  -v "$WS/.plmc_build:/ws" \
  plmc:latest \
  /opt/conda/bin/reformat.pl a3m a2m \
    /ws/DHFR.a3m /ws/DHFR.raw.a2m

# Step 2: Remove query-gap columns (host-side python)
python3 "$PLMC_MCP/script/rm_a2m_query_gaps.py" \
  "$WS/.plmc_build/DHFR.raw.a2m" \
  "$WS/.plmc_build/DHFR.a2m"

# Step 3: Train PLMC model — output to plugin/example/DHFR/plmc/uniref100.model_params
docker run --rm \
  -v "$WS/.plmc_build:/inputs:ro" \
  -v "$WS/plmc:/output" \
  plmc:latest \
  /app/repo/plmc/bin/plmc \
    -o /output/uniref100.model_params \
    -c /output/uniref100.EC \
    -f query \
    -le 16.2 -lh 0.01 -m 200 -t 0.2 \
    -g /inputs/DHFR.a2m

[ -s "$WS/plmc/uniref100.model_params" ] || { echo "FAIL: plmc did not produce model_params"; exit 1; }
echo "OK: built $(du -h "$WS/plmc/uniref100.model_params" | cut -f1) model_params"
rm -rf "$WS/.plmc_build"
