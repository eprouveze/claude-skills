# salesforce-reports golden cases

Fixed inputs with expected outcomes. Run against a **sandbox or scratch org** before any
production change to `scripts/sfreport.sh`. Each case prints PASS/FAIL.

## Setup

1. `scripts/sfreport.sh setup --org <your-sandbox-alias>` (auth via `sf org login web` first).
2. From this directory: `ORG=<your-sandbox-alias> ./run-all.sh`
   (or run individual `case-*.sh` scripts, passing `ORG`).

## Cases

- `case-setup-check.sh` — `setup --check-only` reports auth OK against the org.
  Expected: contains `Analytics REST reachable`.
- `case-list.sh` — `list` returns a JSON array (the user can always see ≥0 reports).
  Expected: stdout parses as a JSON list.
- `case-create-delete-roundtrip.sh` — clone a source report, confirm a 18-char Id is
  returned, delete it (HTTP 204), confirm a follow-up `get` returns `NOT_FOUND`.
  Expected: all three steps pass. **This is the load-bearing case** — it exercises the
  two CLI gotchas (clone-needs-metadata, delete-needs-envelope) end to end.
- `case-delete-envelope.sh` — regression guard: a raw `sf api request rest -X DELETE`
  on any report id MUST fail with `No 'mode' found in 'body' entry`. If this ever
  *stops* failing, the CLI bug was fixed upstream and `sf_rest DELETE` can be
  simplified — log it in `learnings.md` and consolidate.

## When a golden case that used to pass starts failing

That is the loudest signal to run a consolidation pass on `learnings.md` — usually it
means the sf CLI changed its body/auth handling or the Analytics API version moved.
