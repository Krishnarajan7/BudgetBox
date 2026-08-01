#!/usr/bin/env bash
# Nightly encrypted logical backup (independent of Litestream): VACUUM INTO,
# age-encrypt with the PUBLIC key (private key lives only on the Mac), upload,
# clean up. Wire to a systemd timer or call from budgetbox-daily.service.
set -euo pipefail

BACKUP_DIR=/var/lib/budgetbox/backups
AGE_RECIPIENT="age1REPLACE_WITH_YOUR_PUBLIC_KEY"
BUCKET="s3://budgetbox-backups/nightly" # rclone/aws-cli remote

mkdir -p "$BACKUP_DIR"
cd /opt/budgetbox/backend

uv run budgetbox backup --out-dir "$BACKUP_DIR"
latest=$(ls -t "$BACKUP_DIR"/budgetbox-*.db | head -1)
age -r "$AGE_RECIPIENT" -o "$latest.age" "$latest"
rm "$latest"

# Upload however you like; rclone shown:
rclone copy "$latest.age" "$BUCKET"
# Keep 14 local encrypted copies.
ls -t "$BACKUP_DIR"/*.age | tail -n +15 | xargs -r rm
