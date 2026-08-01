#!/usr/bin/env bash
# Deploy on the VPS: pull, sync deps, migrate, restart. Run as the budgetbox user
# from /opt/budgetbox/backend.
set -euo pipefail

cd "$(dirname "$0")/.."

git pull --ff-only
uv sync --frozen
uv run budgetbox db upgrade
sudo systemctl restart budgetbox
sleep 1
curl -fsS http://127.0.0.1:8000/healthz && echo " deploy ok"
