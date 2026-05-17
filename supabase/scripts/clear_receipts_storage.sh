#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_REF_DEFAULT="gaseuxsieddlksxtdliq"
PROJECT_REF="${SUPABASE_PROJECT_REF:-$PROJECT_REF_DEFAULT}"
BUCKET="${SUPABASE_RECEIPTS_BUCKET:-receipts}"

usage() {
  cat <<'EOF'
Delete disposable receipt storage for pre-launch development.

Usage:
  ./supabase/scripts/clear_receipts_storage.sh [--delete-bucket]

Behavior:
  - With SUPABASE_SERVICE_ROLE_KEY: calls the Supabase Storage API to empty the
    receipts bucket. With --delete-bucket, deletes the empty bucket too.
  - Without SUPABASE_SERVICE_ROLE_KEY: falls back to Supabase CLI recursive
    object deletion against the linked project.

Environment variables:
  SUPABASE_SERVICE_ROLE_KEY  Optional service-role key for Storage API cleanup.
  SUPABASE_ACCESS_TOKEN      Optional Supabase access token for CLI fallback.
  SUPABASE_PROJECT_REF       Optional project ref (defaults to gaseuxsieddlksxtdliq).
  SUPABASE_RECEIPTS_BUCKET   Optional bucket name (defaults to receipts).
EOF
}

DELETE_BUCKET=false
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ "${1:-}" == "--delete-bucket" ]]; then
  DELETE_BUCKET=true
elif [[ -n "${1:-}" ]]; then
  usage
  exit 2
fi

cd "$ROOT_DIR"

if [[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
  BASE_URL="https://${PROJECT_REF}.supabase.co/storage/v1"
  AUTH_HEADER="Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}"
  APIKEY_HEADER="apikey: ${SUPABASE_SERVICE_ROLE_KEY}"

  echo "[storage-cleanup] Emptying bucket ${BUCKET}"
  curl --fail --silent --show-error \
    --request POST \
    --header "$AUTH_HEADER" \
    --header "$APIKEY_HEADER" \
    "${BASE_URL}/bucket/${BUCKET}/empty"
  echo

  if [[ "$DELETE_BUCKET" == true ]]; then
    echo "[storage-cleanup] Deleting bucket ${BUCKET}"
    curl --fail --silent --show-error \
      --request DELETE \
      --header "$AUTH_HEADER" \
      --header "$APIKEY_HEADER" \
      "${BASE_URL}/bucket/${BUCKET}"
    echo
  fi

  exit 0
fi

if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  npx --yes supabase login --token "$SUPABASE_ACCESS_TOKEN" --workdir "$ROOT_DIR" >/dev/null
fi

echo "[storage-cleanup] SUPABASE_SERVICE_ROLE_KEY not set; using linked Supabase CLI"
if ! npx --yes supabase storage rm -r "ss:///${BUCKET}" --experimental --linked --workdir "$ROOT_DIR"; then
  cat <<'EOF'
[storage-cleanup] Storage cleanup needs credentials.
Provide one of:
  - SUPABASE_SERVICE_ROLE_KEY (recommended; also supports --delete-bucket), or
  - SUPABASE_ACCESS_TOKEN for the Supabase CLI fallback.
EOF
  exit 1
fi

if [[ "$DELETE_BUCKET" == true ]]; then
  cat <<'EOF'
[storage-cleanup] Bucket deletion requires SUPABASE_SERVICE_ROLE_KEY.
Rerun with:
  SUPABASE_SERVICE_ROLE_KEY=... ./supabase/scripts/clear_receipts_storage.sh --delete-bucket
EOF
fi
