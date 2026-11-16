#!/usr/bin/env bash
# lint-schemas.sh — Verify dist schemas are safe to upload to Konnect.
#
# Konnect rejects schemas containing: require, ngx., custom_validator,
# or custom_entity_check (substring match, including comments).
# The schema sandbox also fails on ngx globals at load time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}/dist"

FORBIDDEN='require\s*\(|ngx\.|custom_validator|custom_entity_check'
FAILED=0

for schema in "$DIST"/*/schema.lua; do
  if grep -En "$FORBIDDEN" "$schema"; then
    echo "[lint] FAIL: $schema contains forbidden pattern(s)" >&2
    FAILED=1
  else
    echo "[lint] OK:   $schema"
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "[lint] Schema lint failed. Fix the issues above before uploading to Konnect." >&2
  exit 1
fi

echo "[lint] All schemas clean."
