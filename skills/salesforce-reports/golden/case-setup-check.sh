#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Golden case: setup --check-only reports the org reachable.
# Usage: ORG=<alias> ./case-setup-check.sh
set -euo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/scripts/sfreport.sh"
ORG="${ORG:?set ORG to a sandbox/scratch alias}"
out="$("$S" setup --org "$ORG" --check-only 2>&1)"
if echo "$out" | grep -q 'Analytics REST reachable'; then
  echo "PASS: setup check reachable"
else
  echo "FAIL: setup check did not confirm reachability"; echo "$out"; exit 1
fi
