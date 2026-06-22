# context.md — week-ahead reference (read this first)

Technical reference for the **week-ahead** pipeline planner. The prompt stays lean; the queries, field rules,
channel logic, language handling, and formatting gotchas live here. Every agent reads this before running.

> **Generic by design.** This skill works for **any AE in Salesforce**, run as **yourself or on behalf of another
> AE**, producing the canvas in **whatever language fits the deal**. The org-specific bits (custom field names, the
> seeded channel map) are captured below as the *defaults for this org instance* — they are the knowledge the skill
> carries, not limits on who it serves.

---

## Why Org62 via the MCP connector (not the `sf` CLI)
Use **`mcp__Org62-Sobject-Read__soqlQuery`**, **`getObjectSchema`**, and **`getUserInfo`** — not the `sf` CLI:
- **Read-only by design** — the Sobject-Read connector can't write, matching this skill's read-only rule. `sf` can update/delete prod.
- **Structured JSON straight into context** — no shell parsing, text-tables, or exit-code handling.
- **No local setup** — works headless; `sf` needs a logged-in org alias on the box.
- **One access model** — Gmail + Slack are MCP too, so sub-agents share one calling convention; easy to parallelize.
- **Schema introspection** — `getObjectSchema` lets the agent confirm a field exists *before* asserting it's empty.
  This is how the `NextStep` → `Next_Steps__c` bug was caught. If unsure a field exists, call it first.

`sf` CLI stays a fallback when a task genuinely needs it (a field the connector doesn't expose, or local ad-hoc work
that *wants* write access) — but the MCP connector is the default for this read-only, multi-source run.

---

## Parameters — resolve these up front, confirm in one line, then go
The skill confirms four things before launching the run. Sensible defaults in **bold**:

1. **Whose book (the AE).** Either **the session owner** (call `getUserInfo` → that User's Id) or a **named AE**
   (look them up: `SELECT Id, Name FROM User WHERE Name LIKE '%<name>%' AND IsActive = true`). Use that `OwnerId`.
2. **Window.** Default = **this fiscal quarter + the next two (3 quarters total)**. Generic + self-adjusting SOQL:
   `(CloseDate = THIS_FISCAL_QUARTER OR CloseDate = NEXT_N_FISCAL_QUARTERS:2)` — this respects whatever fiscal
   calendar the org is configured for. If the operator wants a different window ("this quarter only", "next 2",
   an explicit date range), honor it. *(Fallback if the fiscal literals look off: compute an explicit `CloseDate >=
   … AND CloseDate <= …` range. This org's FY is Feb–Jan: Q1 Feb-Apr, Q2 May-Jul, Q3 Aug-Oct, Q4 Nov-Jan.)*
3. **Forecast + stage filter.** Default = **Forecast ∈ Commit / Best Case / Pipeline** (exclude Omitted) and
   **Stage 02–05** (exclude 00/01 unqualified and any `Dead%`/`Lost`/`Closed`). Operator may say "Commit only",
   "top 5 by amount", etc.
4. **Canvas language.** Default = **`auto`** (see "Canvas language" below). Operator may force a language
   ("write it in Japanese / English").

State the resolved parameters in one line (AE · window · filter · language), then proceed.

---

## Query 1 — pull the book
`<OWNER_ID>` = the resolved AE's User Id; the `CloseDate` clause = the resolved window.
```sql
SELECT Id, Name, StageName, Amount, ExpectedRevenue, CurrencyIsoCode, CloseDate,
       ForecastCategoryName, Probability, Next_Steps__c, SE_Next_Steps__c,
       LastActivityDate, Account.Name, Owner.Name, Type
FROM Opportunity
WHERE OwnerId = '<OWNER_ID>'
  AND IsClosed = false
  AND ForecastCategoryName IN ('Commit','Best Case','Pipeline')
  AND (StageName LIKE '02%' OR StageName LIKE '03%' OR StageName LIKE '04%' OR StageName LIKE '05%')
  AND (CloseDate = THIS_FISCAL_QUARTER OR CloseDate = NEXT_N_FISCAL_QUARTERS:2)
ORDER BY Amount DESC
```

## Query 2 — per-opp open activities (one parent at a time)
`OpenActivity` is **not** a top-level object. Subquery `OpenActivities`, one parent, with the mandated sort + LIMIT:
```sql
SELECT Id, (SELECT Subject, ActivityDate, Status, IsTask, Owner.Name
            FROM OpenActivities ORDER BY ActivityDate ASC, LastModifiedDate DESC LIMIT 50)
FROM Opportunity WHERE Id = '<oppId>'
```

---

## Org62 field cheat-sheet (verified — this org is heavily customized)
| Need | Use | NOT |
|---|---|---|
| Next step (AE) | `Next_Steps__c` | `NextStep` (null on real deals) |
| Next step (SE) | `SE_Next_Steps__c` | — |
| ACV | `sfbase__ACV__c` | `Calculated_ACV__c` (doesn't exist) |
| Deal value (planning) | `Amount` | — (`IsSplit=true` is normal; the AE works the whole deal) |
| Weighted forecast | `ExpectedRevenue` (= Amount × Probability) | — |
| Open tasks/events | subquery `OpenActivities` (LIMIT + `ActivityDate ASC, LastModifiedDate DESC`, 1 parent) | top-level `OpenActivity` |
| Compelling event | `Compelling_Event__c` | — |
| Risks / close plan | `Red_Flags__c`, `Close_Plan__c` | — |
| Fiscal calendar | Feb–Jan (Q2 = May-Jul) | calendar quarters |

> If you run this skill against a different org, verify these names with `getObjectSchema` first — custom fields vary.

---

## Canvas language (auto by default)
The canvas should read naturally to **the AE who receives it**, in the language the deal actually lives in.
- **`auto`** (default): write the canvas prose in the **dominant language of the deal's own content** — the
  Org62 next-steps, Slack threads, and customer emails. If those are mostly Japanese, write the canvas in Japanese;
  if mostly English, English. Tiebreak: the AE's own locale / the script their name is written in.
- **Explicit**: if the operator names a language, write the whole canvas in it.
- **Always keep verbatim regardless of language:** proper nouns (people, companies, product names), Org62 field
  names (`Next_Steps__c` etc.), amounts/dates, and all URLs/links. Translate the *narrative*, not the *data*.
- The structure (summary → do-first → hygiene → per-deal) and the 🔴 marker stay the same in every language.

---

## The four context sources per opp — fan out, don't serialize
**Parallelize on two levels.** (1) One sub-agent per opp (across opps). (2) **Within each opp, the four sources are
independent — gather them concurrently.** The pattern that wins:
- **Step A (Org62 first, alone):** the opp record + `OpportunityContactRole` give you the **contact emails** and
  any **sibling cross-link** — both are *inputs* the Gmail/Slack/Drive searches need. So Org62 runs first.
- **Step B (Gmail ∥ Slack ∥ Drive, all at once):** once you have contacts + account + sibling, fire these in
  parallel — as **separate per-source sub-sub-agents** (Gmail agent, Slack agent, Drive agent). In the workflow this
  is a nested `parallel([...])` inside each opp's gather; one-per-source agents also make the `/workflows` tree show
  the real fan-out (≈4 boxes per opp, not 1).
- Do **not** run the sources sequentially within one agent — a serial gather wastes ~60% of wall-clock
  (~4–5 min/opp vs ~1–2 min/opp concurrent).

1. **Org62 — trajectory, next steps & open work** *(run first; feeds the others)*
   - `OpportunityHistory` (last ~10, `ORDER BY CreatedDate DESC`) → how Amount / Stage / CloseDate moved.
   - Read `Next_Steps__c` and `SE_Next_Steps__c`. **If either just cross-links to another opp Id/URL, go read
     that sibling** (its Stage, Amount, IsClosed, `Next_Steps__c`, Slack channel). `Dead - Duplicate` ⇒ no live
     action here; an active big sibling (e.g. a parent RFP) ⇒ this deal rides on that program — summarize it.
   - Open activities via **Query 2**.
   - Primary `Contact`s via `OpportunityContactRole` → names/titles/emails. **These emails drive the Gmail search** —
     don't fall back to a domain-only search.
2. **Gmail — recent customer comms** *(needs Step-A contacts)*. **Start precise, broaden only on empty:**
   - **First:** the actual contact emails, `newer_than:90d` (`(from:a@x OR to:a@x OR from:b@y OR to:b@y) newer_than:90d`).
   - **Then:** a deal-keyword query (product/opp name + account), e.g. `"<account>" <product> newer_than:90d`.
   - **Never** open with a domain-only query (`from:<corp>.com newer_than:90d`) — on a big account that returns the
     whole company's mail and tells you nothing. **No customer email in 90 days is itself a finding** — say so.
3. **Slack — the deal's channel(s).** See the channel-map section below. (Search by the 18-char opp Id first, then
   product/exec keywords.)
4. **Google Drive — decks, proposals, ROI models, SOWs** *(needs Step-A account + product terms)*. **Precision rules:**
   - **Narrow-first, AND the account with a deal-specific term:** `name contains '<product>'` or
     `name contains '<account>' and name contains '<product>'`. **Never** search the bare account name alone — it
     matches the whole global-account corpus and the backend errors out ("Backend unavailable").
   - **For broad keyword searches, always add a `mimeType` filter** (`…presentation` for decks, `…document` for docs,
     `…spreadsheet` for pricing models).
   - **Try the opp Id in full-text** (`fullText contains '006…'`) — deck footers/notes sometimes carry it.
   - **Author is a *ranking* signal, not a filter** — decks come from SEs, product specialists, and partners too.
     Surface AE/contact-authored docs first, but include others.
   - On 0 results broaden by **one** term; on "Backend unavailable" *narrow* (fewer `OR`s, more `AND`s). Don't skip
     Drive silently — "no relevant deck found" is a valid, stated outcome.
5. **Sibling deals** (from the §1 cross-link) — read the sibling's Org62 record + Slack channel too.

---

## Channel map (`channel-map.json`, in the skill directory)
Key = 18-char opp Id; value lists **one or more** channels, each tagged `dedicated | account | sibling | program | weak`.
A deal can legitimately have several relevant channels — keep them all.
- **In the map:** read each channel's last ~2 weeks.
- **Not in the map — don't guess.** First try to resolve precisely by searching Slack for the **opp record Id / URL**,
  then the deal name; only auto-map a channel whose messages clearly discuss THIS deal. If still unsure, add it to a
  **"missing channels" list** and keep going (gather everything else so the opp isn't blocked). After all opps are
  processed, **surface the missing channels in one batch and ask** (show opp name + account). When the operator
  replies, **append each `oppId → [channels]` to `channel-map.json`** (preserve existing channels), then read them
  and fold in. Building the canvas while waiting is fine — mark those opps "Slack channel pending" and update on reply.
- *(Workflow note: an unattended workflow run can't pause to ask — it records missing channels in the dossier and the
  canvas notes "channel pending" rather than blocking. The interactive prompt does the batch-ask.)*

---

## Actions — agreed vs recommended vs hygiene (who / when / why / how)
Every opp must produce actions in (at least) these three kinds:
- **Agreed** — already committed in Org62 (`Next_Steps__c`, `SE_Next_Steps__c`, open Tasks, scheduled Events) or in
  comms (a reply promised, a meeting said to be set). These are owed. **If a recorded next-step is past-dated, flag
  it stale** rather than presenting it as current.
- **Recommended** — your judgment of what *should* happen next, given the trajectory + risks from Slack/Gmail/siblings.
- **CRM-hygiene (Org62 update) actions — DO NOT SKIP.** Updating Org62 *is* an action, not just a flag. For **every**
  opp where any of these is true, emit a concrete "update Org62" action naming the field + what it should say:
  - `Next_Steps__c` is **empty, past-dated/stale, or just a cross-link** to a sibling (write the real next step + date).
  - `SE_Next_Steps__c` is empty while an SE is engaged.
  - `Close_Plan__c`, `Compelling_Event__c`, or `Red_Flags__c` is blank on a Commit/Best-Case deal.
  - `CloseDate` looks stale vs the trajectory, or Stage/Forecast disagree with what Slack/Gmail show.
  Read-only: phrase as "I update Org62 with X", never auto-write.
- For each action: **who** (the AE or a named teammate — SE, Deal Desk, exec sponsor, partner) · **when** (a concrete
  date or "this week / before the next milestone") · **why** (one line, tied to a risk/milestone) · **how** (reply to
  a customer email, set a meeting with the DM, ask the SE to prep a demo, refresh the specific stale Org62 field,
  draft a deck, escalate in Slack…) — with the relevant **link** in the *how* cell.
- **Who-attribution discipline (lesson from an early run; see `logs/`).** The AE is the person named in
  the parameters at run start (`Opportunity.OwnerId` = their User Id). Their "who" label is `<AE name>` or
  `<AE name> (AE)`. **They are the ONLY person tagged "(AE)" in the entire canvas.** Every action's "who" defaults
  to the AE unless it genuinely belongs to someone else — in which case use their actual name + role tag
  (`Tanaka (SE)`, `Ichimaru (Manager)`, `Yann (GAM)`, `<Partner Co.> rep`). **The session owner (whoever launched the
  skill) is not necessarily the AE** — could be the AE themselves, could be their GAM, manager, or another colleague
  running the plan on the AE's behalf. They appear in source data (Slack/Gmail/Org62) because of their
  organizational role, NOT because they own the AE's actions. Do not promote them into action ownership. If the
  Gather stage surfaces the session owner heavily (they're a GAM for a big account, an exec sponsor across the book,
  etc.), label them with their real role tag — never "(AE)".

---

## Canvas formatting (critical)
- Title (set by the create call): **"Week Ahead — <AE name> — <date>"** (translate "Week Ahead" if the canvas
  language isn't English). **The create call already sets this title — do NOT also write it as an H1 first body line,
  or you get a DUPLICATE title.** The body's first element is the pipeline summary.
- **Tables render fine, but you MUST put a blank line between any heading/bold line and the table**, one row per line,
  standard `| col | col |` header + `|---|---|` separator. No blank line ⇒ the table collapses into one block.
- **Publishing a large canvas (≥~30KB) — CHUNK, never one full-body call (lesson from an early fresh run).**
  A single `slack_create_canvas` with the whole ~80-120KB markdown as `content` **times out** — on BOTH MCP sets
  (`mcp__slack__*` and `mcp__plugin_slack_slack__*`). The agent never reaches Slack. Instead: split the markdown at
  deal boundaries (lines that are only `---`) into chunks ≤~16KB → `slack_create_canvas` with the FIRST chunk
  (pipeline summary + nav table + hygiene) → then `slack_update_canvas` `action:"append"` for each remaining deal
  section, **one chunk per call, in order**. Never concatenate chunks (that re-creates the timeout). Prefer the
  `mcp__plugin_slack_slack__*` tool set. A small canvas (< ~30KB) can still go in a single create call.
- Do canvas edits sequentially, never in parallel — parallel section edits race → `internal_error`. (The chunked
  append above is sequential by construction: await each call before the next.)
- Keep it scannable — read with coffee, not studied.
- Structure: pipeline summary (N opps, **gross total** + **weighted total** ΣExpectedRevenue, # actions owed this week) →
  "Do first this week" (2–4 highest-leverage) → book-wide hygiene flag (state of `Next_Steps__c`, Events/Tasks, email
  recency) → per opp (most urgent/largest first): header `Stage · Forecast (Prob%) · Amount · Close date` + Org62 link
  + channel chip(s) · **What moved** · **Open risks** · **Actions ahead** table `Action · Who · When · Why · How`
  with 🔴 on owed-this-week.
- **🔴 placement (lesson from an early canvas — body had 13 🔴 but summary said 8):** 🔴 appears
  **once per action**, **only** in the per-deal "Actions ahead" tables. The top "Do first this week" table is a
  navigation summary listing 2–4 of the same actions in compact form (Action · Who · When · Deal) — it does NOT
  carry 🔴 markers, because every row in it is this-week-priority by definition (the marker would double-count and
  break the summary-count reconciliation). Final 🔴 count in the body MUST equal the summary's "# actions owed this
  week" — count them and reconcile before finalizing.
- **🔴 discipline (do not flag everything).** 🔴 = an action the AE **personally owes AND must act on THIS week**. Cap
  ~**1–2 per deal and ~8 total** — if everything is urgent, nothing is. A stale-deal hygiene cleanup is real work but
  rarely a 🔴-this-week; reserve 🔴 for compelling events, deadlines, and replies owed now. **The "# actions owed this
  week" in the summary MUST equal the actual count of 🔴 markers in the body** — count and reconcile before finishing.
- **Where the 🔴 reconciliation happens (lesson from an early run; see `logs/`).** In the **workflow**
  path, the workflow code itself caps `mineThisWeek` to ≤2/deal and ≤8 total **before** the canvas agent runs — the
  canvas agent's job is **rendering only** (mineThisWeek:true ⇒ 🔴, else blank; the count is passed in pre-computed).
  Reason: when the canvas agent had to do the cap math from a 9-deal, 11-marker book, it burned its whole window in
  prose chain-of-thought and got killed at the harness deadline before issuing a single `slack_create_canvas` call —
  three retries in a row. In the **inline** path (operator's main agent driving), do the cap math **outside** the
  canvas-build step — decide which 🔴 survive in your own reasoning, then issue the create call as your first non-Read
  tool action. **Tool-call first, debate after.**
- **The OTHER canvas-stall cause (2026-06-22): the publish payload itself.** Even with rendering-only + pre-computed
  🔴, the fresh run stalled a 5th time — the agent rendered the full ~120KB canvas but the single `slack_create_canvas`
  call with that whole body **timed out before returning** (true on both MCP sets). Fix = the chunked create+append in
  "Canvas formatting" above. Net: the canvas step has TWO independent failure modes — (1) doing cap math inline (fixed
  by pre-reconciling upstream), and (2) emitting the whole canvas as one tool argument (fixed by chunking). Both must
  be avoided or the step hangs.

## Links — every claim should be one click from its source (DO NOT SKIP)
The canvas is a launchpad, not a summary. When a finding rests on a specific artifact, **link that exact artifact**:
- **Org62 opp** — every per-deal header links to `https://org62.lightning.force.com/lightning/r/Opportunity/<18-id>/view`. Siblings too.
- **Slack** — channel chips `![](#CHANNELID)`; for a specific evidence message (milestone, price decision, vendor risk) deep-link its permalink.
- **Gmail** — link the actual thread (`https://mail.google.com/mail/u/0/#all/<threadId>`) for "awaiting my reply" / "latest inbound ask".
- **Google Drive / Slides / Docs** — link any referenced (or to-be-drafted) deck/proposal by its Drive URL.
- In **Actions ahead**, the **how** cell carries the action's link (the email to reply to, the channel to post in, the
  Org62 record to edit, the deck to update) — so each owed action is directly actionable.
- If a source genuinely has no link ("no customer email in 90 days"), say so plainly rather than omitting it.

---

## Hard-won lessons (do not regress)
1. **Org62 is heavily customized — never trust standard fields.** Use the cheat-sheet; `getObjectSchema` if unsure.
2. **Window is generic** — fiscal-quarter literals (this + next 2) self-adjust to the run date; explicit range as fallback.
3. **Cross-links are pointers, not dead ends** — follow them to the sibling opp + channel.
4. **One opp can have several relevant Slack channels** — keep them all.
5. **Gmail: real contact emails, precise-first, 90-day window.** "No email in 90 days" is a finding. Never domain-only.
6. **Drive: narrow-first, never the bare account name; mimeType filter; author ranks not filters.**
7. **`OpenActivities` is a subquery**, one parent, mandated sort + LIMIT (Query 2).
8. **Canvas: no duplicate title; blank line before every table; atomic edits; 🔴 count must reconcile.**
9. **Gather fans out per source** (Org62 recon → Gmail ∥ Slack ∥ Drive) — never serial.

---

## Artifacts (run index + per-run subfolder + per-opp dossier cache) — Persist phase
At the end of every run, the **Persist phase** writes the skill's own audit + cache artifacts. These writes do NOT
violate the read-only contract (same category as the channel-map append). Root: **`<artifactDir>`**, defaulting to
**`<cwd>/week-ahead/`** (a *visible* folder in the directory the run was invoked from). Override via
`args.artifactDir` (workflow) or by setting `artifactDir` in the inline prompt path.

Layout — **one subfolder per run** plus a top-level index:

```
<artifactDir>/                                # e.g. ~/Dev/my-project/week-ahead/
  README.md                                   # explains layout (auto-written if missing)
  runs.jsonl                                  # APPENDED — one line per run, points to its folder
  <YYYY-MM-DD>-<AE-Name>/                     # PER-RUN subfolder (e.g. 2026-06-21-Jane-Doe/)
    recap.md                                  # human-readable front page (canvas link, totals, top deals, known issues)
    canvas.md                                 # rendered canvas markdown — verbatim local snapshot
    canvas-meta.json                          # canvas_id, url, title, char/line/🔴 counts
    run.jsonl                                 # ONE-line JSONL with full audit record for this run
    dossiers/<oppId>.json                     # per-opp dossier — overwritten if same AE-same-day
    logs/                                     # postmortems / diagnostic notes (only if applicable)
```

**Run folder naming**: `<YYYY-MM-DD>-<AE-slug>` (AE name slugified — lowercase letters/digits, hyphens for spaces).
Re-running the same AE on the same day overwrites the folder; the canvas URL in Slack persists independently.

**Top-level index** (`runs.jsonl`, append-only): one JSONL line per run with
`{ts, ae, aeOwnerId, folder, oppCount, gross, weighted, canvasUrl}` — enough to find the per-run subfolder for any
past run.

**Per-run manifest** (`<run-folder>/run.jsonl`, single line, overwrite-if-rerun): full audit record —
`{ts, ae, aeOwnerId, scope, language, oppCount, synthesized, gross, weighted, oppIds, artifactDir, canvasUrl,
redCount, redReconciled, redDroppedFromCap, channelsRead, missingChannels, wroteToDataSources:false}`.
Pointers + counts, no source content — for "what ran / why did it say X / did the guardrail hold", not a data store.

**Per-opp dossier** (`<run-folder>/dossiers/<oppId>.json`, one file per opp): full content —
`{oppId, oppName, account, capturedAt, pullSnapshot, sources: {org62, gmail, slack, drive}, synth}`. The four source
fields hold the **full text** the per-source gather agents produced (Gmail thread digests, Slack channel reads,
Drive findings, Org62 trajectory + activities + contacts); `synth` holds that opp's structured SYNTH_SCHEMA output
(headerLine, whatMoved, risks, agreed/recommended/hygiene actions, links). This is the **cache** next week's run
reads to skip re-fetching stable old content — read prior `dossiers/<oppId>.json` BEFORE gathering and reuse
anything older than ~30 days verbatim (planned tier-2: hot/cold split with explicit timestamps).

**Privacy:** `<artifactDir>` may hold customer email bodies, Slack messages, and similar. It is local-only.
`week-ahead/` is gitignored at the skill level and should be added to the project's `.gitignore` if the project has
one. **Never push the per-opp dossier files to a public repo.**

## Read-only contract
This is a **planning brief, not an executor**. It *recommends* actions (who/when/why/how); the AE decides and acts.
Do **not** post to any deal channel, send email, book meetings, or write to Org62/Salesforce. The only writes the
skill makes are its **own** artifacts: the AE's Slack canvas, the self-DM of that canvas, appending resolved channels
to `channel-map.json` in the skill dir, and the Persist phase's `runs.jsonl` + `<run-folder>/run.jsonl` +
`<run-folder>/dossiers/<oppId>.json` files in `<artifactDir>` (default `<cwd>/week-ahead/`).
