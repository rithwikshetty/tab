#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<'EOF'
Recreate Supabase database aggressively for pre-launch development.

Usage:
  ./supabase/scripts/recreate_db.sh

Behavior:
  1) Builds the generated schema from supabase/sql/*.sql.
  2) If SUPABASE_DB_URL is set, applies destructive teardown + schema to that DB.
  3) Else if SUPABASE_ACCESS_TOKEN + SUPABASE_DB_PASSWORD are set, links to
     SUPABASE_PROJECT_REF and applies destructive SQL.
  4) Else applies destructive SQL to the currently linked database.

Environment variables:
  SUPABASE_DB_URL         Optional direct Postgres URL (percent-encoded).
  SUPABASE_ACCESS_TOKEN   Optional Supabase personal access token.
  SUPABASE_DB_PASSWORD    Optional database password for link.
  SUPABASE_PROJECT_REF    Required when linking with access token + password.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.env.local" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.local"
  set +a
fi

SUPABASE_CMD=(npx --yes supabase)
QUERY_ARGS=(db query --workdir "$ROOT_DIR")
TEARDOWN_FILE="$ROOT_DIR/supabase/scripts/destructive_teardown.sql"
BUILD_SCHEMA_SCRIPT="$ROOT_DIR/supabase/scripts/build_schema.sh"
GENERATED_SCHEMA_FILE="$ROOT_DIR/supabase/.temp/generated_schema.sql"

apply_files() {
  mkdir -p "$(dirname "$GENERATED_SCHEMA_FILE")"
  echo "[recreate-db] Building schema from supabase/sql"
  "$BUILD_SCHEMA_SCRIPT" --out "$GENERATED_SCHEMA_FILE"
  echo "[recreate-db] Applying destructive teardown"
  "${SUPABASE_CMD[@]}" "${QUERY_ARGS[@]}" -f "$TEARDOWN_FILE" "$@"
  echo "[recreate-db] Applying generated schema"
  "${SUPABASE_CMD[@]}" "${QUERY_ARGS[@]}" -f "$GENERATED_SCHEMA_FILE" "$@"
}

if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
  echo "[recreate-db] Recreating database via SUPABASE_DB_URL"
  apply_files --db-url "$SUPABASE_DB_URL"
  exit 0
fi

if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" && -n "${SUPABASE_DB_PASSWORD:-}" ]]; then
  if [[ -z "${SUPABASE_PROJECT_REF:-}" ]]; then
    echo "[recreate-db] SUPABASE_PROJECT_REF is required when linking with SUPABASE_ACCESS_TOKEN + SUPABASE_DB_PASSWORD." >&2
    exit 1
  fi
  PROJECT_REF="$SUPABASE_PROJECT_REF"
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
  - SUPABASE_ACCESS_TOKEN + SUPABASE_DB_PASSWORD + SUPABASE_PROJECT_REF
Then rerun the script.
EOF
  exit 1
fi
