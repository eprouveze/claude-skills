---
name: model-scan
description: >
  Scan LLM provider APIs for available models, fetch official docs for specs (parameters,
  context windows, capabilities, pricing), save timestamped doc snapshots, and optionally
  update a project's `CLAUDE.md` model table. Use when the user asks about current models
  or wants to refresh the model list — "scan models", "refresh models", "what models are
  available", "update model table", "model pricing", "check model IDs".
allowed-tools: Bash, Read, Edit, Glob, Grep, WebFetch, WebSearch
user-invocable: true
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
---

# Model Scan

Query LLM provider APIs, fetch official documentation for specs, and produce a structured
model report. Useful for keeping a project's model-selection table current as providers
ship new models and adjust pricing.

This skill assumes a driver script at `scripts/model-scan.ts` that does the actual API
calls and doc parsing. A minimal reference driver is bundled in `scripts/model-scan.ts` —
extend it with the providers and parsing rules your project needs.

## Approval gate — curated table changes

A project's `CLAUDE.md` "Current AI Model IDs" table is typically a curated selection that
directly affects which models are used in production code. **Any change to the recommended
set requires explicit user approval.** The driver script auto-updates the table from its
`selectRecommendedModels()` list, but when the recommended set should change (new model
added, model removed, provider added/dropped):

1. Show the user what changed and why.
2. Wait for explicit approval before writing to CLAUDE.md.
3. Never silently add or remove providers from the curated table.

## Route by argument

- `/model-scan` (no args) → run the script with `--update-claude-md`, display results,
  then review saved docs for any TBD fields.
- `/model-scan list` → run without `--update-claude-md`, display results only.
- `/model-scan fast` → run with `--skip-docs --update-claude-md` (uses cached docs).

### Phase 1: Run the scanner

```bash
cd "$(git rev-parse --show-toplevel)" && npx tsx scripts/model-scan.ts --update-claude-md
```

If your driver lives somewhere else (e.g. `~/.local/bin/model-scan.ts`), update the
invocation to match. Run `scripts/model-scan.ts --help` for the driver's own flags.

### Phase 2: Fill TBD fields

Provider docs often hide spec data behind JS-rendered pages that the driver can't parse
cleanly. For any TBD fields:

1. Look for a Context7-style docs index if your project has one.
2. Otherwise use WebSearch to find the model's spec page, then WebFetch to extract.
3. Check saved doc snapshots in `docs/briefings/model-scan/docs/YYYY-MM-DD/` for older
   data that might fill the gap.
4. Update the fallback tables in `scripts/model-scan.ts` so future runs have the value.
5. Re-run the script for a clean report.

> Codex variants (`gpt-5.3-codex` vs `gpt-5.3`) are distinct models with different
> training, pricing, and capabilities. Look up each one individually.

### Phase 3: Summarize

After the script completes:

1. Count models found across providers.
2. List providers that were skipped (missing API keys).
3. List remaining TBD fields.
4. Note where data came from per model (the `data_sources` field tracks this).
5. Confirm the `CLAUDE.md` update if `--update-claude-md` was used.

## Driver contract

`scripts/model-scan.ts` is expected to:

- Read provider API keys from environment variables.
- Hit each provider's `/models` (or equivalent) endpoint.
- Fetch documentation pages and save timestamped snapshots to
  `docs/briefings/model-scan/docs/YYYY-MM-DD/`.
- Parse capabilities, context windows, and pricing from the snapshots.
- Merge data with a fallback pricing table for graceful degradation.
- Emit JSON to `docs/briefings/model-scan/YYYY-MM-DD.json`.
- Optionally rewrite the `CLAUDE.md` "Current AI Model IDs" table when
  `--update-claude-md` is passed.

The bundled reference driver demonstrates the contract for OpenAI, Anthropic, and Google
Gemini. Add other providers (Perplexity, Moonshot, DeepSeek, xAI, etc.) by following the
same shape.

## Fields collected per model

| Field                          | Typical source                                  |
| ------------------------------ | ----------------------------------------------- |
| Model ID                       | Provider API                                    |
| Pricing (input/output per 1M)  | Docs parsing → fallback table                   |
| Context window                 | API → docs parsing                              |
| Max output tokens              | API → docs parsing                              |
| Capabilities                   | Docs parsing → API                              |
| Parameter ranges (temp, top_p) | API → docs parsing                              |
| Knowledge cutoff               | Docs parsing                                    |
| Docs URL                       | Per-provider mapping in the driver              |

## Output layout

- **Console** — pricing/context/params/capabilities table with TBD warnings.
- **JSON** — `docs/briefings/model-scan/YYYY-MM-DD.json` (full structured data).
- **Doc snapshots** — `docs/briefings/model-scan/docs/YYYY-MM-DD/*.txt`.
- **`CLAUDE.md`** — updated "Current AI Model IDs" table when the flag is passed.

## Staleness rule

Any skill or script referencing a model ID should check the latest scan first. If the most
recent JSON is more than 7 days old, run `/model-scan` to refresh before relying on the
data. Pricing and model availability move fast.

## Prerequisites

- Node.js 20+
- `tsx` (`npm install -g tsx`)
- API keys (as env vars) for each provider the driver hits

The reference driver looks for:

| Variable             | Required to scan |
| -------------------- | ---------------- |
| `OPENAI_API_KEY`     | OpenAI           |
| `ANTHROPIC_API_KEY`  | Anthropic        |
| `GEMINI_API_KEY`     | Google Gemini    |

Missing keys cause the affected provider to be skipped, not the whole run to fail.

> **Gemini CLI → Antigravity CLI rename (2026-06-18).** The user-facing binary for
> the Google seat is now `agy` on consumer plans; enterprise plans may keep `gemini`.
> The API endpoint (`generativelanguage.googleapis.com/v1beta/models`) and
> `GEMINI_API_KEY` env var are unchanged, so the scanner itself needs no edits.
> `CLI_EXTRAS` in the driver lists `agy` alongside Codex CLI and Claude Code for
> reference; downstream tooling should treat both `agy` and the legacy `gemini`
> binary as valid Google delegates.

## Known gotchas

- **Doc parsers are fragile.** Providers reshuffle their docs every few months. When TBDs
  start appearing for a provider that previously worked, update the regex/selectors in
  the driver before treating the value as "really missing".
- **Auto-updating `CLAUDE.md` is destructive.** The driver replaces the model table
  region wholesale. Make sure the project commits the diff before re-running with
  `--update-claude-md`.
- **Pricing in fallback tables drifts.** Fallback prices are last-known-good — verify
  against the latest doc snapshot before relying on a fallback hit in a budget
  calculation.

## Anti-patterns

- Auto-applying CLAUDE.md changes without showing the user the diff. The approval gate
  exists for a reason.
- Treating Codex variants as identical to their base models. They aren't.
- Running with `--skip-docs` repeatedly and forgetting to refresh — the cached snapshot
  goes stale silently.

## Validated patterns

- The `data_sources` field per model is the most-used debugging hook. When a value looks
  wrong, the source tells you which step to fix.
- Saving timestamped doc snapshots, rather than just parsing them in-memory, makes
  bisecting provider doc changes possible later.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- A provider doc change breaks parsing for a whole provider (the regex/selectors need
  work).
- A new provider becomes worth scanning.
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.
- The driver script's CLI changes shape.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns or update the
  driver-script contract above.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
