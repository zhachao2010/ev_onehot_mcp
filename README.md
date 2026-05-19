# EV+OneHot MCP Server

**Fitness prediction combining evolutionary coupling and one-hot encoding via Docker**

An MCP (Model Context Protocol) server for protein fitness prediction with 2 core tools:
- Train a Ridge regression fitness model combining evolutionary (EV) features and one-hot encoding
- Predict fitness for new protein sequences using a trained model

> **关于代码组织**
> - **`repo/ev_onehot/`** —— 论文原始算法代码（`train.py` / `pred.py` / `predictor.py` / `couplings_model.py` / `util.py`），是真正"工作"的层
> - **`src/`** —— 早期的 FastMCP wrapper，把 `repo/` 封装成 MCP tools
>   - **状态：deprecated** —— 仍可用于 standalone "Quick Start with Docker" 方式（下面 §1 / §2 这两节）
>   - PDAgent / 其他下游集成已改为**直接调 `repo/` 的 CLI 脚本**（`docker run ... python /app/repo/ev_onehot/train.py ...`），不依赖 `src/`
>   - 新功能不再添加到 `src/`，bug 也只接收 critical 级修复
> - 看代码从哪开始：[`CODE_READING.md`](./CODE_READING.md)
> - CLI / Docker 调用样例：[`CHEATSHEET.md`](./CHEATSHEET.md)

## Quick Start with Docker

### Approach 1: Pull Pre-built Image from GitHub

The fastest way to get started. A pre-built Docker image is automatically published to GitHub Container Registry on every release.

```bash
# Pull the latest image
docker pull ghcr.io/macromnex/ev_onehot_mcp:latest

# Register with Claude Code (runs as current user to avoid permission issues)
claude mcp add ev_onehot -- docker run -i --rm --user `id -u`:`id -g` -v `pwd`:`pwd` ghcr.io/macromnex/ev_onehot_mcp:latest
```

**Note:** Run from your project directory. `` `pwd` `` expands to the current working directory.

**Requirements:**
- Docker
- Claude Code installed

That's it! The EV+OneHot MCP server is now available in Claude Code.

---

### Approach 2: Build Docker Image Locally

Build the image yourself and install it into Claude Code. Useful for customization or offline environments.

```bash
# Clone the repository
git clone https://github.com/MacromNex/ev_onehot_mcp.git
cd ev_onehot_mcp

# Build the Docker image
docker build -t ev_onehot_mcp:latest .

# Register with Claude Code (runs as current user to avoid permission issues)
claude mcp add ev_onehot -- docker run -i --rm --user `id -u`:`id -g` -v `pwd`:`pwd` ev_onehot_mcp:latest
```

**Note:** Run from your project directory. `` `pwd` `` expands to the current working directory.

**Requirements:**
- Docker
- Claude Code installed
- Git (to clone the repository)

**About the Docker Flags:**
- `-i` — Interactive mode for Claude Code
- `--rm` — Automatically remove container after exit
- `` --user `id -u`:`id -g` `` — Runs the container as your current user, so output files are owned by you (not root)
- `-v` — Mounts your project directory so the container can access your data

---

## Verify Installation

After adding the MCP server, you can verify it's working:

```bash
# List registered MCP servers
claude mcp list

# You should see 'ev_onehot' in the output
```

In Claude Code, you can now use all 2 EV+OneHot tools:
- `ev_onehot_train_fitness_predictor`
- `ev_onehot_predict_fitness`

---

## Next Steps

- **Detailed documentation**: See [detail.md](detail.md) for comprehensive guides on:
  - Available MCP tools and parameters
  - Local Python environment setup (alternative to Docker)
  - Data format requirements
  - Example workflows and use cases
  - Model architecture details

---

## Usage Examples

Once registered, you can use the EV+OneHot tools directly in Claude Code. Here are some common workflows:

### Example 1: Train a Fitness Model

```
I have a PLMC model in /path/to/plmc/ directory and training data at /path/to/data.csv with wild-type sequence /path/to/wt.fasta. Can you train an ev+onehot fitness model using ev_onehot_train_fitness_predictor with 5-fold cross-validation and save to /path/to/model/?
```

### Example 2: Predict Fitness for New Sequences

```
I have a trained ev+onehot model in /path/to/model/ and new sequences in /path/to/new_sequences.csv. Can you predict fitness for all sequences using ev_onehot_predict_fitness and save the predictions to /path/to/predictions/?
```

### Example 3: Full Fitness Modeling Workflow

```
I have experimental fitness data for subtilisin variants at /path/to/subtilisin/data.csv, wild-type at /path/to/subtilisin/wt.fasta, and a PLMC model at /path/to/subtilisin/plmc/. Please train an ev+onehot model with cross-validation and report the Spearman correlation performance.
```

---

## Troubleshooting

**Docker not found?**
```bash
docker --version  # Install Docker if missing
```

**Claude Code not found?**
```bash
# Install Claude Code
npm install -g @anthropic-ai/claude-code
```

**PLMC model required?**
- This tool requires a pre-trained PLMC model in the model directory
- Use the `plmc_mcp` to generate PLMC models from MSA files

---

## License

Research use — see original repository for details
