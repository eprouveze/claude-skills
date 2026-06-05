# battle golden cases

Three benchmark prompts of varying complexity. The skill passes if each contestant
produces non-empty output, the leaderboard ranks them, and per-contestant cost/time
metrics are recorded.

## Cases

- `01-rate-limiter/` — "Implement a token-bucket rate limiter middleware in <language>".
- `02-refactor-checkout/` — "Refactor the attached checkout function to support multi-currency".
- `03-write-tests/` — "Write a comprehensive test suite for the attached parser".

Each case has a `task.md` and a `verify.sh` checking that the battle report exists and
ranks all available contestants.
