# model-scan golden cases

Three runs that exercise the driver script's main paths.

## Cases

- `01-all-providers/` — all keys present; expects ≥1 model from each configured provider.
- `02-missing-key/` — `OPENAI_API_KEY` unset; expects OpenAI rows absent and a `[skip]` line in stdout.
- `03-skip-docs/` — runs with `--skip-docs`; expects no new files under `docs/briefings/model-scan/docs/<today>/`.

Each case has a `run.sh` that invokes the driver with the right env shape, and an
`expected.txt` documenting the expected outcome.
