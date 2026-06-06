---
name: plan
description: >
  Research-first planning for any non-trivial task. Spawns parallel sub-agents to
  explore the codebase, checks past solutions and decisions, asks clarifying
  questions, then produces a structured plan stored in docs/plans/. Use when
  starting any non-trivial task: "plan this feature", "how should we approach...",
  "let's think through...", or before any multi-file change. Do NOT use for trivial
  single-file edits or questions that need no planning.
allowed-tools: Read, Glob, Grep, Bash, Agent, AskUserQuestion, TodoWrite
user-invocable: true
version: 0.1.0
last-updated: 2026-06-06
last-consolidated: 2026-06-06
metadata:
  author: Emmanuel Prouveze
  filePattern: "docs/plans/**"
---

# Plan — Research-First Task Planning

Transform feature descriptions, bug reports, or improvement ideas into well-structured, research-grounded implementation plans.

The governing principle: **80% planning and research, 20% execution.** A plan written from assumptions is worse than no plan — it lends false confidence to a wrong approach.

## When to use

Activate when:

- The user says "plan", "how should we", "let's think through", "what's the best approach"
- Starting any feature or change touching 3+ files
- The task involves unfamiliar parts of the codebase
- Before any architectural decision

## When not to use

- Trivial single-file edits where the approach is obvious — just do it
- Pure questions that need an answer, not a plan
- When the user has explicitly asked for speed over thoroughness on a small task

## Philosophy

**Never plan in the dark.** Every plan should be grounded in:

1. What the codebase actually looks like today — not assumptions
2. Existing patterns the project already uses
3. Past solutions to similar problems (check `docs/solutions/` and `docs/decisions/` if they exist)
4. Clarified requirements — not guesses
5. Known risks and constraints

## The planning process

### Phase 0: Idea refinement

Before researching, understand the request:

1. **Check for existing plans** — search `docs/plans/` for plans related to this feature. If one exists, present it and ask: continue from it, update it, or start fresh?
2. **Check for past solutions** — search `docs/solutions/`, `docs/decisions/`, or any project memory layer for previously solved similar problems.
3. **Classify the request** — feature, bug fix, refactor, or improvement?
4. **Gauge risk** — does this touch security, payments, auth, or external APIs? High-risk topics warrant external research in Phase 1.5.

If the request is vague, ask 1-2 refinement questions before launching research.

### Phase 1: Parallel research

Launch these research tracks **in parallel** using the Agent tool — they are independent and should not run sequentially. Tailor each prompt to the specific task.

#### Track A: Codebase exploration

Spawn a sub-agent to map the current state:

- Files that will be affected by this change (with paths)
- Existing patterns for similar functionality (with examples)
- Related code, tests, types, and utilities
- Technical debt in the affected areas

Have the agent return file paths and code excerpts for every finding, so the plan can reference real locations rather than guesses.

#### Track B: Learnings research

Spawn a second sub-agent (or search directly) to look through `docs/solutions/`, `docs/decisions/`, and any documented best-practices for:

- Previously solved similar problems
- Past decisions that constrain or inform this work
- Patterns documented as project conventions
- Known gotchas in the affected areas

#### Track C: Dependency check (when relevant)

For tasks involving external libraries, APIs, or integrations:

- Check current versions in `package.json` (or the project's manifest)
- Look for existing usage patterns in the codebase
- Identify potential conflicts or breaking changes

> **Optional: offload exploration to a second CLI model.** If you have a second
> coding CLI available (e.g. an OpenAI Codex CLI, a Gemini/Antigravity CLI, or any
> agent that can read the repo), you can delegate Track A or Track B to it to
> preserve the orchestrator's context window for synthesis. Pass it the task
> description plus the directories to explore, capture its findings to a temp file,
> then read and **spot-check 2-3 cited paths** (delegated models hallucinate paths)
> before folding the findings into the plan. This is a pure optimization — the core
> skill works entirely with the parallel sub-agents above.

### Phase 1.5: External research decision (conditional)

After local research completes, decide if external research is warranted:

| Signal | Action |
|--------|--------|
| High-risk topic (security, payments, APIs) | Research current best practices via web |
| Strong local patterns already exist | Skip external research |
| New library or framework feature | Check latest docs via web |
| Genuine uncertainty about the approach | Research alternatives via web |

### Phase 2: Ask clarifying questions

**Before producing any plan**, ask clarifying questions with AskUserQuestion. Good candidates:

- **Scope** — "Should this also handle [edge case]?"
- **Priority** — "What matters most: speed, robustness, or simplicity?"
- **Constraints** — "Any requirements I should know about that aren't in the codebase?"
- **Approach** — when multiple valid approaches exist, present them with tradeoffs

Only ask questions that would meaningfully change the plan. Skip if the task is already clear.

### Phase 3: Choose detail level

Match plan depth to task complexity:

**Minimal** (quick tasks, 3-5 files): problem statement · steps with file paths · success criteria.

**Standard** (typical features, 5-15 files): context from research · problem statement · proposed approach with rationale · step-by-step plan · technical considerations · acceptance criteria · risks and mitigations.

**Comprehensive** (large features, architectural changes, 15+ files): executive summary · detailed problem analysis · solution design with phases · alternatives considered (and why rejected) · technical specs · schema/migration plan · API contract changes · risk mitigations · testing strategy · extensibility notes.

### Phase 4: Write the plan

Create the plan at `docs/plans/YYYY-MM-DD-<type>-<descriptive-name>-plan.md`:

```markdown
# [Plan Title]

**Type:** feat | fix | refactor | chore | docs
**Date:** YYYY-MM-DD
**Status:** draft | approved | in-progress | completed

## Context
What we learned from research (key findings only, not a data dump).
Reference specific files and patterns discovered.

## Problem Statement
What needs to change and why.

## Proposed Approach
The chosen strategy and rationale (1-3 sentences).

## Implementation Steps

### Step 1: [Description]
- **Files:** `path/to/file.ts`
- **Changes:** What specifically changes
- **Depends on:** (nothing | Step N)

### Step 2: [Description]
...

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| [Risk] | [Impact] | [How we handle it] |

## Success Criteria
- [ ] What "done" looks like
- [ ] How we verify it works

## Out of Scope
Things we're deliberately NOT doing (and why).

## Research Notes
Key findings from the research phase. Reference `docs/solutions/` entries if relevant.
```

Valid filename examples:

- `2026-02-15-feat-export-pipeline-plan.md`
- `2026-02-15-fix-auth-redirect-plan.md`
- `2026-02-15-refactor-data-layer-plan.md`

Then create a TodoWrite task list from the implementation steps for real-time tracking.

### Phase 5: Present and get approval

Present the plan summary, then offer next steps:

1. **Approve and start working** — hand off to implementation
2. **Adjust the plan** — modify scope, approach, or steps
3. **Deepen research** — investigate specific areas further before committing
4. **Shelve for later** — keep the plan in `docs/plans/` for future reference

**Do NOT start coding until the user approves the plan.**

## Plan quality checklist

Before presenting, verify:

- [ ] Every step references specific files/locations discovered during research
- [ ] The approach follows existing codebase patterns (don't invent new ones without reason)
- [ ] Dependencies between steps are clear (what must happen before what)
- [ ] Success criteria are testable, not vague
- [ ] Nothing is assumed — anything uncertain was asked in Phase 2
- [ ] Past solutions have been checked for relevant patterns
- [ ] The plan file exists in `docs/plans/` with correct naming

## Anti-patterns

- **Planning without research.** Don't produce a plan from assumptions. Always explore first.
- **Over-planning.** A plan for a 3-step task should be 3 steps, not 15. Match plan complexity to task complexity.
- **Ignoring existing patterns.** If the codebase already does something similar, follow that pattern.
- **Asking obvious questions.** Don't ask "Should I write tests?" if the codebase already tests similar features — just include them.
- **Vague steps.** "Implement the feature" is not a step. "Add `generateExport` to `lib/export.ts` following the pattern in `lib/share.ts`" is a step.
- **Ignoring past solutions.** Always check for prior art before planning. Someone may have already solved this.

## Known gotchas

- **Delegated exploration hallucinates paths.** If you offload Track A/B to a second CLI model, always spot-check cited file paths against the real repo before trusting them.
- **Plans go stale mid-implementation.** Plans are living documents. If you discover something during implementation that invalidates the plan, stop, update the plan, and re-confirm with the user.
- **Conflicting patterns in research.** If research surfaces two competing patterns, present both with tradeoffs and let the user decide. Record the decision so the next plan doesn't relitigate it.

## Integration with other skills

- **After approval** — hand off to your implementation flow, or proceed directly for simpler tasks.
- **After completion** — capture what went well or poorly into your project's memory/solutions layer, so the next plan benefits.
- **Companion** — pair with an `evaluate-plan` pass to catch requirements the first draft silently dropped.
