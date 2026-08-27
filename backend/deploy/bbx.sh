#!/usr/bin/env bash
# Run a budgetbox CLI command on the VPS with the *service's* environment.
#
# /etc/budgetbox/env is a systemd EnvironmentFile: systemd loads it for the
# units and for nothing else. A CLI command run by hand without it falls back
# to Settings' defaults — and `db_path` defaults to a *relative*
# 'budgetbox.db', so the command quietly opens a new, empty database in the
# working directory instead of the real book. An import run that way would
# pour years of history into a file nothing ever reads.
#
# So: never call the CLI directly on the VPS. Call it through this.
#
#   sudo /opt/budgetbox/backend/deploy/bbx.sh music connect-url
#   sudo /opt/budgetbox/backend/deploy/bbx.sh music poll
#   sudo /opt/budgetbox/backend/deploy/bbx.sh token issue phone
set -euo pipefail

ENV_FILE=${BBX_ENV_FILE:-/etc/budgetbox/env}
APP_DIR=${BBX_APP_DIR:-/opt/budgetbox/backend}
UV=${BBX_UV:-/usr/local/bin/uv}
RUN_AS=${BBX_USER:-budgetbox}

if [[ ! -r $ENV_FILE ]]; then
  echo "bbx: cannot read $ENV_FILE — run this with sudo." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

if [[ -z ${BBX_DB_PATH:-} ]]; then
  echo "bbx: $ENV_FILE sets no BBX_DB_PATH; refusing to touch a default-path" \
       "database. Add BBX_DB_PATH=/var/lib/budgetbox/budgetbox.db and retry." >&2
  exit 1
fi

cd "$APP_DIR"

if [[ $(id -un) == "$RUN_AS" ]]; then
  exec "$UV" run budgetbox "$@"
fi

# sudo -E keeps the BBX_*/UV_* vars. HOME matters because uv caches under it
# and sudo would otherwise hand over the caller's home: prefer the value the
# env file sets, fall back to the service user's passwd home.
if [[ -z ${HOME:-} || $(id -un) == root ]]; then
  HOME=$(getent passwd "$RUN_AS" | cut -d: -f6)
fi
exec sudo -E -u "$RUN_AS" env "HOME=$HOME" "$UV" run budgetbox "$@"
