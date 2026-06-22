---
name: week-ahead
description: "Plan an AE's sales week across their whole Salesforce pipeline and deliver it as a Slack canvas DM. TRIGGER when: the user asks for a 'week ahead', a Monday-morning pipeline plan, a per-deal action plan across their open opportunities, or a sales planning brief built from Org62/Salesforce + Gmail + Slack. Works for any AE (self or on behalf of another), in any language, and can run as a visible /workflows fan-out. DO NOT TRIGGER when: the user wants a single-deal brief only (no whole-book scope), or wants to actually execute actions (this is read-only/planning only)."
license: MIT
compatibility: "Requires MCP connectors: Org62 (Salesforce Sobject-Read), google-workspace (Gmail/Drive), Slack. Read-only on all data sources."
metadata:
  version: "1.0"
---

# week-ahead: AE pipeline planner → Slack canvas

Plan the week across **one AE's** active Salesforce pipeline and deliver it as a **Slack canvas DM**. For each open
opportunity the skill gathers context from **Org62 (Salesforce) + Gmail + Slack + Google Drive** (and any sibling
deal a next-step cross-links to), separates **agreed / recommended / CRM-hygiene** actions with *who·when·why·how*,
and assembles a scannable canvas with links so every claim is one click from its source.

**Generic by design:** any AE (run as yourself or on behalf of another), any fiscal window, **any canvas language**
(auto-detected by default). It is a **planning brief, not an executor** — read-only on all data sources; it only
writes its own canvas, the self-DM, and channel-map updates.

## Files in this skill
- **`context.md`** — the full spec. **Read it first, every run.** SOQL queries, Org62 custom-field cheat-sheet,
  the four-source gather pattern, channel-map logic, language handling, action framework, canvas formatting rules,
  and the read-only contract.
- **`week-ahead.workflow.js`** — the workflow version (visible `/workflows` fan-out). Launch via the `Workflow` tool.
- **`channel-map.example.json`** — template for the opp Id → Slack channel(s) cache. Copy it to `channel-map.json`
  (which is **gitignored** — it holds real channel IDs + account names = customer data) and let the run append
  channels it resolves. Never commit the populated `channel-map.json` to a public repo.
- **`prompt-ja.md`** — Japanese-language version of the run prompt (for Japanese-speaking AEs).

## How to run

**Step 1 — read `context.md`** (the spec). Then **confirm four parameters in one line** (defaults in parens), and proceed:
1. **Whose book** — the session owner, or a named AE? *(default: the session owner; ask once if ambiguous)*
2. **Window** — which close dates? *(default: this fiscal quarter + the next two)*
3. **Filter** — forecast/stage scope, or a quick slice like "top 5 by amount" / "Commit only"? *(default: Commit/Best Case/Pipeline · Stage 02–05)*
4. **Canvas language** — *(default: `auto` — match the language the deals live in)*

**Step 2 — choose the execution mode:**
- **Visible fan-out (recommended for a live audience or large books):** launch the bundled workflow so the per-opp /
  per-source agents show up in `/workflows`:
  ```
  Workflow({
    scriptPath: "<skill dir>/week-ahead.workflow.js",
    args: {
      ae: { name: "<AE name>", ownerId: "<18-char User Id>" },  // omit → runs as the session owner
      scope: "top 5 by amount",          // optional filter override
      window: "this + next 2 quarters",  // optional window override
      language: "auto",                  // or "Japanese", "English", …
      skillDir: "<skill dir>",           // REQUIRED so context.md + channel-map.json resolve
      artifactDir: "<abs/path>"          // optional — where the run log + per-opp dossiers land.
                                         //   default: "$(pwd)/.week-ahead" (resolved at write time)
    }
  })
  ```
  `<skill dir>` is this skill's own directory (where this SKILL.md lives). Then open `/workflows` to watch:
  **Pull → Gather (per opp: `org62` → `gmail` ∥ `slack` ∥ `drive`) → Synthesize → Canvas → Persist**.
- **Inline (no workflow UI):** follow the run prompt in `week-ahead-prompt.md` directly — same spec, executed as
  normal sub-agents. Use `prompt-ja.md` for a Japanese-speaking AE.

**Step 3 — deliver.** The run builds the canvas, DMs it to the session owner, and confirms in chat: parameters used,
# opps, gross + weighted pipeline, # actions owed this week, and the canvas link.

## Guardrails (read-only contract)
Do **not** post to any deal channel, send email, book meetings, or write to Org62/Salesforce. The only writes are the
AE's own Slack canvas, the self-DM of it, appending resolved channels to `channel-map.json` (in the skill dir), and
the skill's own audit artifacts in `<artifactDir>` (the run log + per-opp dossiers — see "Artifacts" below). If a
Slack channel is unmapped, **don't guess** — collect it and batch-ask once, then append the answer to
`channel-map.json`. (In an unattended workflow run, unresolved channels are noted "pending" rather than blocking.)

## Artifacts (per-run audit + per-opp cache)
Every run writes to `<artifactDir>` — defaults to **`<cwd>/week-ahead/`** (a visible folder in the directory you
invoked from) so each project's artifacts live with the project. Override via `args.artifactDir` for a fixed path.
Layout: one **subfolder per run**, plus a top-level `runs.jsonl` index:

```
<artifactDir>/                                 # e.g. ~/Dev/my-project/week-ahead/
  README.md                                    # explains layout (auto-written if missing)
  runs.jsonl                                   # top-level index — one JSONL line per run with {ts, ae, folder, totals, canvasUrl}
  <YYYY-MM-DD>-<AE-Name>/                      # per-run subfolder, e.g. 2026-06-21-Jane-Doe/
    recap.md                                   # human-readable front page (canvas link, totals, top deals, known issues)
    canvas.md                                  # rendered canvas markdown — verbatim local snapshot
    canvas-meta.json                           # canvas ID, URL, title, char/line/🔴 counts
    run.jsonl                                  # full audit record for THIS run (one line — all metadata)
    dossiers/<oppId>.json                      # per-opp dossier: full raw text (org62/gmail/slack/drive) + synth
    logs/                                      # postmortems / diagnostic notes (only when something went sideways)
    evidence/                                  # raw inputs (only when a one-shot test was used to rebuild a phase)
```

Re-running the same AE on the same day overwrites the subfolder (the canvas URL in Slack persists independently).
For multiple runs per day, append a counter to the folder name or pass an explicit `artifactDir` per run.

The dossier files are **the cache** — full text from all 4 sources + the synthesizer's structured output, so the
next run can read prior runs' findings and skip re-fetching stable old content (planned: tier-2 hot/cold split).
These are local-only and **gitignored** at the skill level — never pushed to the public repo. If your project cwd
has its own git repo, add `week-ahead/` to its `.gitignore`. Customer/business content stays on the machine that
ran it.

## Notes
- **Org62 is heavily customized** — the skill uses `Next_Steps__c` / `SE_Next_Steps__c` / `sfbase__ACV__c` (not the
  standard fields) and `getObjectSchema` to verify. If pointed at a different org, re-verify field names first.
