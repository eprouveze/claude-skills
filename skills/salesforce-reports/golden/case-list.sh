#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Golden case: list returns a JSON array.
# Usage: ORG=<alias> ./case-list.sh
set -euo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/sfreport.sh"
ORG="${ORG:?set ORG to a sandbox/scratch alias}"
if "$S" list --org "$ORG" 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d,list) else 1)'; then
  echo "PASS: list returns a JSON array"
else
  echo "FAIL: list did not return a JSON array"; exit 1
fi
