#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run every golden case. Usage: ORG=<alias> [SOURCE_ID=<id>] ./run-all.sh
set -uo pipefail
cd "$(dirname "$0")"
ORG="${ORG:?set ORG to a sandbox/scratch alias}"
pass=0 fail=0
for c in case-setup-check.sh case-list.sh case-delete-envelope.sh case-create-delete-roundtrip.sh; do
  [[ -f "$c" ]] || continue
  echo "=== $c ==="
  if ORG="$ORG" SOURCE_ID="${SOURCE_ID:-}" bash "$c"; then ((pass++)); else ((fail++)); fi
  echo
done
echo "golden: ${pass} passed, ${fail} failed"
[[ $fail -eq 0 ]]
