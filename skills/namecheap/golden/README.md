# namecheap golden cases

Five fixed inputs with expected response shapes. Run against sandbox before any
production change to the script.

## Setup

1. Run `scripts/nc_api.sh --setup` with sandbox credentials (`NAMECHEAP_USE_SANDBOX=true`).
2. Whitelist your IPv4 at namecheap.com → Profile → Tools → API Access.
3. From this directory, run each `case-*.sh` script and diff against the matching `.expected.txt`.

## Cases

- `case-check-available.sh` — check a random-string `.com` (expected: `Available="true"`).
- `case-check-unavailable.sh` — check `google.com` (expected: `Available="false"`).
- `case-pricing-com.sh` — get pricing for `.com` REGISTER (expected: prices > 0 for years 1..10).
- `case-list-empty.sh` — list domains on a fresh sandbox account (expected: 0 rows).
- `case-bad-credentials.sh` — call with a wrong key (expected: ERROR status, error number 1010102 or similar).

Each case prints PASS/FAIL based on the simplest possible check.
