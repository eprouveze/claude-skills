#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Golden regression guard: a RAW `sf api request rest -X DELETE` must still fail
# with the body-envelope error. If it ever passes, the CLI bug was fixed upstream
# and sf_rest()'s DELETE branch can be simplified — log it in learnings.md.
# Usage: ORG=<alias> ./case-delete-envelope.sh
set -euo pipefail
ORG="${ORG:?set ORG to a sandbox/scratch alias}"
API="${SF_API_VERSION:-62.0}"
# A syntactically valid but almost-certainly-nonexistent id; we only care that the
# CLI rejects the *request shape* before it ever reaches the server.
out="$(sf api request rest "/services/data/v${API}/analytics/reports/00O000000000000AAA" \
        -X DELETE -o "$ORG" 2>&1 || true)"
if echo "$out" | grep -q "No 'mode' found in 'body' entry"; then
  echo "PASS: raw DELETE still requires the -f envelope (gotcha intact)"
else
  echo "ATTENTION: raw DELETE no longer errors on body envelope — CLI may be fixed."
  echo "  Output: $out"
  echo "  -> simplify sf_rest() DELETE branch and log in learnings.md"
  exit 1
fi
