# council golden cases

Three structural cases. The skill passes if the run produces all expected output files
and the synthesis non-empty. Quality of the content is not asserted.

## Cases

- `01-five-seats/` — run a no-op question through all 5 seats. Expected files: theorist.md, validator.md, provocateur.md, diagnostician.md, field-engineer.md, synthesis.md.
- `02-missing-key/` — run without `KIMI_API_KEY`. Expected: 4 seat files + a noted absence in synthesis.
- `03-collab/` — run with `--collab`. Expected: r1/ subdir with 5 files, r2/ subdir with 5 files, synthesis.md.

Each case has a `question.md` and a `verify.sh` that checks file existence and minimum size.
