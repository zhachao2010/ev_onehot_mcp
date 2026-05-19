FROM python:3.10-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git gcc g++ wget \
    && rm -rf /var/lib/apt/lists/*

COPY . /app/ev_onehot

WORKDIR /app/ev_onehot

# requirements
RUN pip install --no-cache-dir -r requirements.txt

CMD ["python", "src/repo/ev_onehot/train.py"]
