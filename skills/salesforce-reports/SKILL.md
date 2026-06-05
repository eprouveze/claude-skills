---
name: salesforce-reports
description: >
  Create, clone, read, run, and delete Salesforce Reports from the command line via the
  Analytics REST API, driven by the Salesforce CLI (`sf`). Org-agnostic — works against any
  org you've authed with `sf`. Includes a `--setup` flow (installs the sf CLI if missing,
  saves a default org/API version, and an optional Global Company filter for GAM roles).
  Use when the user says "create a Salesforce report", "clone a report", "generate a report
  via sf CLI", "list/run/delete reports", "report API", or "Analytics REST reports".
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion
user-invocable: true
version: 0.1.0
last-updated: 2026-06-06
last-consolidated: 2026-06-06
metadata:
  author: Emmanuel Prouveze
  argument-hint: "[setup|list|types|get|run|create|clone|delete] [args]"
---

# Salesforce Reports

Manage Salesforce **Reports** (the analytics object, not deploy/package "report" status
commands) from the CLI. There is no native `sf report create` command — report CRUD lives
in the **Analytics REST API** (`/services/data/vXX.0/analytics/reports`). This skill wraps
that API through `sf api request rest`, which is the only path that authenticates correctly
with the CLI's (masked) access token.

Everything routes through one script: `scripts/sfreport.sh`.

## Quick start

```bash
S=~/.claude/skills/salesforce-reports/scripts/sfreport.sh

"$S" setup --org org62        # installs sf CLI if missing, saves config, checks auth
"$S" list                     # all reports you can see
"$S" types                    # report types (the 'type' you pass to create)
"$S" get  <id> --describe     # a report's metadata (filters, columns, format)
"$S" run  <id>                # run synchronously, return rows
"$S" clone --from <id> --name "Copy of X"   # most reliable way to create a report
"$S" create --type <apiName> --name "New"   # empty report of a report type
"$S" delete <id> --yes        # delete (HTTP 204 on success)
"$S" --help                   # full reference
```

The script picks its target org from: `--org` flag → saved config (`setup`) → the sf CLI's
configured `target-org`.

## Setup

`sfreport.sh setup` is the front door:

1. **sf CLI presence.** If `sf` is missing, setup offers to install it (npm → Homebrew →
   yarn, whichever is present). Non-interactively it installs without prompting.
2. **Default org + API version.** Saved to `~/.config/claude-skills/salesforce-reports.env`
   so you don't repeat `--org` every call. API version defaults to `62.0` (Analytics REST is
   stable there).
3. **Auth check.** Confirms the Analytics REST endpoint is reachable; on failure it prints
   the `sf org login web` command to run.
4. **Global Company filter (GAM roles only — optional).** See below.

Non-interactive form for scripts/CI:

```bash
"$S" setup --org myorg --api 62.0 --check-only      # check, don't write config
"$S" setup --org myorg --global-company "NTT, Inc." --gc-column Account.Global_Company__c
```

## Global Company filter (GAM roles)

A **Global Account Manager** scopes reports to a single global parent account. This skill
can re-point that filter on any clone so you don't hand-edit metadata:

```bash
"$S" clone --from <id> --name "NTT Pipeline" \
      --gc "NTT, Inc." --gc-column Account.Global_Company__c
```

Configure a default once at `setup` (`GLOBAL_COMPANY` + `GC_COLUMN_DEFAULT`) and every clone
inherits it; override per-call with `--gc` / `--gc-column`. Resolution order for the value:
`--gc` arg → `$GLOBAL_COMPANY` (env or saved config).

**This is GAM-specific.** Any other role can ignore it entirely — leave both blank at setup
and the skill never touches report filters. To discover the right column on a report:

```bash
"$S" get <id> --describe | python3 -c \
  'import sys,json;[print(f["column"]) for f in json.load(sys.stdin)["reportMetadata"]["reportFilters"]]'
```

## How creation actually works

Two create paths, in order of reliability:

- **Clone (recommended).** `POST /analytics/reports?cloneId=<id>` with the source report's
  full `reportMetadata` (renamed). The skill fetches `/describe`, renames, optionally
  re-points the Global Company filter, and POSTs. This always yields a working report with
  columns and groupings already in place.
- **Bare create.** `POST /analytics/reports` with a minimal `reportMetadata` naming a
  `reportType`. Produces an *empty* report (no columns) — only useful as a stub you finish
  in the UI. Use `types` to find a valid `reportType` api name.

## Known gotchas

- **Clone still needs a metadata body.** `POST ...?cloneId=<id>` with a bare `{}` returns
  `BAD_REQUEST: "there is no metadata"`. You must POST the full `reportMetadata`. The skill
  handles this by fetching `/describe` first.
- **`sf api request rest` DELETE is finicky.** A plain `-X DELETE` errors
  `No 'mode' found in 'body' entry`; `-b ''` and `--body '{...}'` don't help; an object-shaped
  `header` errors `keyValPair.map is not a function`. The working form (used internally) is
  `-f <envelope.json>` with `header` as an **array** of `"k:v"` strings and
  `body: {"mode":"raw","raw":""}`.
- **Don't curl with the CLI token.** `sf org display [--verbose]` returns a *masked* 54-char
  access token; curl with it gives `INVALID_AUTH_HEADER`. Always go through `sf api request
  rest`, which authenticates internally.
- **API version.** Defaults to `62.0`. The CLI's default data API may be higher (e.g. 67.0)
  but Analytics REST report CRUD is verified on 62.0; bump with `--api` only if you've tested.

## Anti-patterns

- **`sf data delete record --sobject Report`** — fails with `INSUFFICIENT_ACCESS_OR_READONLY`
  even when the Analytics DELETE succeeds; the SObject path enforces different rights. Delete
  reports via the Analytics endpoint (`sfreport.sh delete`).
- **Hardcoding an org alias.** The skill is org-agnostic; pass `--org` or save one via
  `setup`. Don't bake `org62` into callers.
- **Treating `sf commands | grep report` hits as report CRUD.** Those are package/deploy
  *status* commands (`package version report`, `project deploy report`). Unrelated.
- **Bare-create then expecting data.** A `create` without columns is empty by design — clone
  when you want a usable report.

## Validated patterns

- Clone → verify returned 18-char Id → use/delete. Verified on org62: create HTTP 200,
  delete HTTP 204, post-delete `get` → `NOT_FOUND`.
- `setup --check-only` as a CI/pre-flight gate before any report automation.
- GAM scoping by re-pointing one `reportFilters` entry on clone, rather than rebuilding the
  report — preserves columns, groupings, and report type.

## Self-improvement

This skill ships with a lightweight feedback loop (`learnings.md`). Adopt or ignore — the
skill works without it.

Trigger a review when:

- The user corrects a created/cloned report's filter, name, or scope (strongest signal — log
  immediately; 2–3 corrections on the same theme → promote to the body).
- The sf CLI changes its body/auth handling (e.g. the DELETE envelope bug gets fixed — the
  `case-delete-envelope.sh` golden case is the canary).
- A new Analytics REST behavior or error code surfaces.
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.

Consolidation pass (5–10 min, weekly or threshold-driven): each `learnings.md` entry gets one
fate — **apply** (merge into Known gotchas / Anti-patterns / Validated patterns), **capture**
(leave in the log), or **dismiss** (delete). Bump `last-consolidated:` in frontmatter. Golden
cases that previously passed and now fail are the loudest signal to consolidate early.

Golden cases live in `golden/` — run `ORG=<sandbox> golden/run-all.sh` before changing the
script.
