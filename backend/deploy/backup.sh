#!/usr/bin/env bash
# Nightly backup. Runs as the budgetbox user from budgetbox-backup.service.
#
# Three layers, cheapest first:
#   1. a consistent snapshot on the box          (survives a bad migration)
#   2. a readable archive beside it              (survives BudgetBox itself)
#   3. a copy in object storage off the box      (survives the VPS)
#
# Only layer 3 needs credentials. Without them the first two still run, so a
# half-configured box is still a backed-up box.
set -euo pipefail

DB="${BBX_DB_PATH:-/var/lib/budgetbox/budgetbox.db}"
ROOT="${BBX_BACKUP_DIR:-/var/lib/budgetbox/backups}"
KEEP_DAILY="${BBX_KEEP_DAILY:-30}"
KEEP_MONTHLY="${BBX_KEEP_MONTHLY:-120}"   # ten years of first-of-month copies
STAMP="$(date -u +%Y%m%d-%H%M%S)"
DAY="$(date -u +%d)"

WORK="$ROOT/daily/$STAMP"
mkdir -p "$WORK"

# 1. Consistent snapshot. VACUUM INTO is safe against a live, serving DB and
#    also compacts, so the copy is smaller than the original.
sqlite3 "$DB" "VACUUM INTO '$WORK/budgetbox.db'"

# 2. The same facts in formats that outlive this codebase.
/usr/bin/env python3 /opt/budgetbox/backend/deploy/bbx-archive.py \
  "$WORK/budgetbox.db" "$WORK"

# One compressed file per night, then drop the working directory.
tar -C "$ROOT/daily" -czf "$ROOT/daily/$STAMP.tar.gz" "$STAMP"
rm -rf "$WORK"

# The first of the month is kept for years rather than weeks. Point-in-time
# recovery matters more the older a mistake is: noticing in March that
# something broke in January is exactly when dailies have already rotated.
if [ "$DAY" = "01" ]; then
  mkdir -p "$ROOT/monthly"
  cp "$ROOT/daily/$STAMP.tar.gz" "$ROOT/monthly/$STAMP.tar.gz"
fi

# 3. Off the box, if configured. rclone reads its own config; the remote is
#    expected to be called `r2`.
if [ -n "${BBX_BACKUP_REMOTE:-}" ] && command -v rclone >/dev/null 2>&1; then
  rclone copy "$ROOT/daily/$STAMP.tar.gz" "$BBX_BACKUP_REMOTE/daily/" --quiet
  if [ "$DAY" = "01" ]; then
    rclone copy "$ROOT/monthly/$STAMP.tar.gz" "$BBX_BACKUP_REMOTE/monthly/" --quiet
  fi
  # Mirror the local retention window upstream.
  rclone delete "$BBX_BACKUP_REMOTE/daily/" --min-age "${KEEP_DAILY}d" --quiet || true
fi

# Retention, local. `-mtime +N` and a fixed glob keep this from ever matching
# something that is not one of ours.
find "$ROOT/daily"   -maxdepth 1 -name '*.tar.gz' -mtime "+$KEEP_DAILY"   -delete
find "$ROOT/monthly" -maxdepth 1 -name '*.tar.gz' -mtime "+$((KEEP_MONTHLY * 31))" -delete 2>/dev/null || true

echo "backup ok: $ROOT/daily/$STAMP.tar.gz ($(du -h "$ROOT/daily/$STAMP.tar.gz" | cut -f1))"
