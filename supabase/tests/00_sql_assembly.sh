#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

[[ -d supabase/sql ]] || fail "canonical SQL source directory supabase/sql exists"
[[ -x supabase/scripts/build_schema.sh ]] || fail "schema build script is executable"

./supabase/scripts/build_schema.sh --check || fail "baseline migration is generated from supabase/sql/*.sql"

schema_lines="$(wc -l < supabase/schema.sql | tr -d ' ')"
[[ "$schema_lines" -le 80 ]] || fail "supabase/schema.sql is a small pointer, not a monolithic schema"

grep -q "supabase/sql" supabase/schema.sql || fail "supabase/schema.sql points maintainers to split SQL sources"

echo "ok - SQL source assembly contract holds"
