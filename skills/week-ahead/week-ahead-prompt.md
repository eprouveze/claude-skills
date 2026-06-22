# week-ahead — pipeline planner (the prompt)

> Paste the block below into Claude Code with **Org62 (Salesforce) + Gmail + Slack** MCP connectors active. It plans
> the week across **one AE's** pipeline and delivers it as a Slack canvas DM. Works for **any AE**, run as **yourself
> or on behalf of another AE**, in **any language**. All technical detail — queries, Org62 field rules, channel
> logic, language handling, canvas formatting — lives in **[`context.md`](context.md)**; keep this prompt lean.

---

## THE PROMPT (copy from here)

You are my sales-planning assistant. **First read `context.md` in this skill's folder** — it is the full spec
(parameters, exact SOQL, Org62 custom-field rules, channel-map logic, language handling, action framework, canvas
formatting). Follow it. Produce a "week ahead" across an AE's active pipeline and deliver it as a Slack canvas DM.

**Before running, confirm these four parameters in one line (use the defaults unless I say otherwise), then go:**
1. **Whose book** — mine (the session owner) or a named AE? *(Default: ask once if unclear; otherwise me.)*
2. **Window** — which close dates? *(Default: this fiscal quarter + the next two.)*
3. **Filter** — forecast/stage scope or a quick slice? *(Default: Commit/Best Case/Pipeline · Stage 02–05. I may say "top 5 by amount" or "Commit only".)*
4. **Canvas language** — what language should the canvas be written in? *(Default: `auto` — match the language the deals actually live in.)*

Then:
1. **Pull the book** with Query 1 (resolve the AE's OwnerId — `getUserInfo` for me, or look up the named AE).
2. **For each opp, gather four sources in parallel** — Org62 (trajectory, next steps, open activities, contacts,
   and any sibling the next-steps cross-link to) first, then **Gmail ∥ Slack ∥ Drive concurrently**. One sub-agent
   per opp; within each, fan out per source. If a Slack channel is unmapped, don't guess — collect it and **batch-ask
   me once** at the end, then append answers to `channel-map.json`.
3. **Determine the actions ahead** — separate **agreed** (owed) from **recommended** (judgment) from **CRM-hygiene**
   (Org62 updates — never skip these), each with **who / when / why / how** and a link. Flag stale next-steps.
4. **Build the canvas** in the chosen language — pipeline summary (gross + weighted) → "Do first this week" → hygiene
   flag → per-deal sections. Follow the canvas formatting + 🔴 discipline rules in `context.md` (no duplicate title;
   blank line before tables; 🔴 only for owed-this-week, and the count must reconcile with the summary).
5. **Deliver** — DM the canvas to me, then confirm in chat: the parameters used, # opps, gross + weighted pipeline,
   # actions owed this week, and the canvas link.

This is a planning brief, **not an executor**. The canvas *recommends* actions — it does not carry them out. Do not
post to any deal channel, send email, book meetings, or write to Org62. The AE decides and acts.

(end of prompt)

---

## Running it as a workflow (the visible fan-out)

To watch the per-opp / per-source fan-out live in `/workflows`, launch the bundled workflow instead of pasting the
prompt. It encodes the same spec from `context.md`:

```
Workflow({
  scriptPath: "<this skill dir>/week-ahead.workflow.js",
  args: {
    ae: { name: "<AE name>", ownerId: "<18-char User Id>" },  // omit to run as the session owner
    scope: "top 5 by amount",        // optional
    window: "this + next 2 quarters", // optional
    language: "auto",                // or "Japanese", "English", …
    skillDir: "<this skill dir>"     // so context.md + channel-map.json resolve
  }
})
```

Then open `/workflows` to watch: **Pull → Gather (per-opp: `org62` → `gmail` ∥ `slack` ∥ `drive`) → Synthesize → Canvas**.

---

*Japanese version of this prompt: [`prompt-ja.md`](prompt-ja.md). Operator notes, the MCP-vs-`sf` rationale, the
channel-map schema, and the full lesson list are in [`context.md`](context.md).*
