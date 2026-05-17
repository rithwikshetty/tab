#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_REF_DEFAULT="gaseuxsieddlksxtdliq"

usage() {
  cat <<'EOF'
Recreate Supabase database aggressively for pre-launch development.

Usage:
  ./supabase/scripts/recreate_db.sh

Behavior:
  1) If SUPABASE_DB_URL is set, applies destructive teardown + schema to that DB.
  2) Else if SUPABASE_ACCESS_TOKEN + SUPABASE_DB_PASSWORD are set, links to
     SUPABASE_PROJECT_REF (or default project ref) and applies destructive SQL.
  3) Else applies destructive SQL to the currently linked database.

Environment variables:
  SUPABASE_DB_URL         Optional direct Postgres URL (percent-encoded).
  SUPABASE_ACCESS_TOKEN   Optional Supabase personal access token.
  SUPABASE_DB_PASSWORD    Optional database password for link.
  SUPABASE_PROJECT_REF    Optional project ref (defaults to gaseuxsieddlksxtdliq).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

cd "$ROOT_DIR"

SUPABASE_CMD=(npx --yes supabase)
QUERY_ARGS=(db query --workdir "$ROOT_DIR")
TEARDOWN_FILE="$ROOT_DIR/supabase/scripts/destructive_teardown.sql"
SCHEMA_FILE="$ROOT_DIR/supabase/schema.sql"

apply_files() {
  echo "[recreate-db] Applying destructive teardown"
  "${SUPABASE_CMD[@]}" "${QUERY_ARGS[@]}" -f "$TEARDOWN_FILE" "$@"
  echo "[recreate-db] Applying canonical schema"
  "${SUPABASE_CMD[@]}" "${QUERY_ARGS[@]}" -f "$SCHEMA_FILE" "$@"
}

if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
  echo "[recreate-db] Recreating database via SUPABASE_DB_URL"
  apply_files --db-url "$SUPABASE_DB_URL"
  exit 0
fi

if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" && -n "${SUPABASE_DB_PASSWORD:-}" ]]; then
  PROJECT_REF="${SUPABASE_PROJECT_REF:-$PROJECT_REF_DEFAULT}"
  echo "[recreate-db] Linking to project $PROJECT_REF"
  "${SUPABASE_CMD[@]}" login --token "$SUPABASE_ACCESS_TOKEN" --workdir "$ROOT_DIR" >/dev/null
  "${SUPABASE_CMD[@]}" link --project-ref "$PROJECT_REF" --password "$SUPABASE_DB_PASSWORD" --workdir "$ROOT_DIR"
fi

echo "[recreate-db] Recreating linked database"
if ! apply_files --linked; then
  cat <<'EOF'
[recreate-db] Linked recreate failed.
Provide one of:
  - SUPABASE_DB_URL (recommended for CI/non-interactive usage), or
  - SUPABASE_ACCESS_TOKEN + SUPABASE_DB_PASSWORD (+ optional SUPABASE_PROJECT_REF)
Then rerun the script.
EOF
  exit 1
fi
