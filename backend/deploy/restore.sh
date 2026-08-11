#!/usr/bin/env bash
# Put a backup back. Run as root on the VPS:
#
#   deploy/restore.sh /var/lib/budgetbox/backups/daily/20260805-000500.tar.gz
#
# A restore that has never been run is a hope, not a backup — so this is
# deliberately short enough to trust, and it never destroys what it replaces.
set -euo pipefail

ARCHIVE="${1:?usage: restore.sh <archive.tar.gz>}"
DB="${BBX_DB_PATH:-/var/lib/budgetbox/budgetbox.db}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

tar -xzf "$ARCHIVE" -C "$STAGE"
SNAP="$(find "$STAGE" -name budgetbox.db -maxdepth 2 | head -1)"
[ -n "$SNAP" ] || { echo "no budgetbox.db inside $ARCHIVE" >&2; exit 1; }

# Prove the file is sound *before* anything is moved aside.
sqlite3 "$SNAP" "PRAGMA integrity_check;" | head -1 | grep -qx ok \
  || { echo "archive is corrupt; nothing changed" >&2; exit 1; }
echo "integrity ok — $(sqlite3 "$SNAP" 'SELECT COUNT(*) FROM txns') transactions"

systemctl stop budgetbox

# The current book is moved, never deleted: a restore of the wrong archive
# must be undoable too.
if [ -f "$DB" ]; then
  ASIDE="$DB.replaced-$(date -u +%Y%m%d-%H%M%S)"
  mv "$DB" "$ASIDE"
  rm -f "$DB-wal" "$DB-shm"
  echo "previous book kept at $ASIDE"
fi

install -o budgetbox -g budgetbox -m 640 "$SNAP" "$DB"
systemctl start budgetbox
sleep 2
curl -fsS http://127.0.0.1:"${BBX_PORT:-8787}"/healthz && echo " restore ok"
