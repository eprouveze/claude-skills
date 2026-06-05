#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Golden case: clone -> verify id -> delete (204) -> verify NOT_FOUND.
# Usage: ORG=<alias> SOURCE_ID=<reportId> ./case-create-delete-roundtrip.sh
# SOURCE_ID defaults to a report the runner must be able to read; override it.
set -euo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/sfreport.sh"
ORG="${ORG:?set ORG to a sandbox/scratch alias}"
SOURCE_ID="${SOURCE_ID:?set SOURCE_ID to a readable report Id in that org}"
NAME="ZZ_GOLDEN_ROUNDTRIP_DELETE_ME"

fail() { printf 'FAIL: %s\n' "$*"; exit 1; }

out="$("$S" clone --from "$SOURCE_ID" --name "$NAME" --org "$ORG" 2>&1)"
id="$(printf '%s' "$out" | sed -n 's/.*Created report: \([0-9A-Za-z]\{15,18\}\).*/\1/p' | head -1)"
[[ -n "$id" ]] || fail "clone did not return a report Id. Output: $out"
printf '  cloned -> %s\n' "$id"

del="$("$S" delete "$id" --yes --org "$ORG" 2>&1)"
echo "$del" | grep -q '204' || fail "delete did not return HTTP 204. Output: $del"
printf '  deleted (204)\n'

gone="$("$S" get "$id" --describe --org "$ORG" 2>&1 || true)"
echo "$gone" | grep -q 'NOT_FOUND' || fail "report still exists after delete. Output: $gone"
printf '  verified NOT_FOUND\n'

echo "PASS: create-delete roundtrip"
