---
name: brief
description: >
  Project-aware session briefing. Loads project-intel, decisions log, deferred actions,
  and known-issues files before any work, so Claude starts with project context instead
  of cold. Use at session start, before any task, or when the user says "/brief", "brief
  me", "what should I know", "catch me up".
allowed-tools: Read, Glob, Grep, Bash
user-invocable: true
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
---

# /brief — Project-Aware Session Briefing

Build a synthesized briefing of the project so Claude knows what the project IS, how it
works, and what to avoid before doing anything else.

## Optional delegation mode

If the project has `.claude/llm-mode.json` and its `mode` is `"multi"`, delegate the heavy
doc reading to a cheaper CLI (Antigravity CLI — `agy`, previously the Gemini CLI — is a
common pick). Only pull the result back to synthesize. If the file is absent or mode is
`"single"`, run the standard path. If the delegated call fails, fall back to standard
silently.

Example delegated call:

```bash
# `agy` (Antigravity CLI) replaces the sunset Gemini CLI on consumer plans as of
# 2026-06-18; enterprise plans may still use the legacy `gemini` binary. The model
# identifier (`gemini-3-pro`) is unchanged.
#
# Note: piping into `agy` already provides stdin, so the `</dev/null` gotcha that
# applies to bare `agy -p "..."` doesn't bite here. For non-piped scripted calls
# elsewhere, always write `agy -p "<prompt>" </dev/null`.
echo "You are a research analyst. I am about to work on: $TASK.

Review the attached documentation and output a Pre-Task Briefing:
1. WATCH OUT — past mistakes, forbidden patterns, known issues
2. HARD CONSTRAINTS — non-negotiable rules
3. PROJECT CONTEXT — what this project IS, tech stack, capabilities
4. STRATEGIC CONTEXT — goals, audience, positioning
5. RELATED WORK — existing content, features, or code that overlaps
6. RECOMMENDATIONS — specific suggestions

Cite source file paths. Omit empty sections." | \
  agy -m gemini-3-pro -p "" @.claude/project-intel.md @docs/ > .brief-temp.md
```

## Standard load order

Execute these reads in parallel where possible:

### Tier 1 — always load

1. **Project intel** — `.claude/project-intel.md` in the project directory. If it's missing,
   flag it: "No project-intel.md — operating with limited project context."
2. **Failure atlas / known issues** — whatever the project uses (`docs/memory/failure-atlas.md`,
   `docs/known-issues.md`, etc.). Skip silently if absent.
3. **CLAUDE.md** — project-level `.claude/CLAUDE.md` or `CLAUDE.md` for conventions.
4. **Feedback files** — anything loaded via a memory index in the project.

### Tier 2 — project history

5. **Decisions log** — `docs/decisions/log.md` (last 10 entries).
6. **Recent session topics** — `docs/sessions/topics/*.md` if the project uses that pattern.
7. **Deferred actions** — `docs/deferred-actions.md`.

### Tier 3 — cross-project (only when the workspace contains multiple projects)

8. **Capabilities index** — what each sibling project can do.
9. **Topic graph** — shared topics, decisions, and capability pointers.
10. **Last-session marker** — the timestamp of the previous session so the "since last
    session" section is accurate.

## Project detection

1. If CWD is inside a known project directory → that's the project.
2. If CWD is a workspace root with multiple projects → ask which one.
3. If the user mentioned a project name → load that one.
4. Otherwise → ask.

## Scoring (for ranking briefing items)

```
score(item) = utility × recency × relevance × (1 − suppression)
```

| Item type                                  | Utility |
| ------------------------------------------ | ------- |
| Mistake relevant to today's work           | 1.0     |
| Decision made since last session           | 0.9     |
| Deferred action due within 48h             | 0.85    |
| Low-confidence topic for current project   | 0.7     |
| Cross-project capability opportunity       | 0.5     |

| Recency      | Weight |
| ------------ | ------ |
| Today        | 1.0    |
| This week    | 0.8    |
| This month   | 0.5    |
| Older        | 0.2    |

| Relevance              | Weight |
| ---------------------- | ------ |
| Current project        | 1.0    |
| Any active project     | 0.5    |
| Universal              | 0.3    |

| Suppression (spaced repetition) | Weight |
| ------------------------------- | ------ |
| Surfaced last session           | 0.8    |
| 2 sessions ago                  | 0.4    |
| 3+ sessions ago                 | 0.0    |

The point of suppression is to avoid repeating the same warning every session.

## Output format

Generate a synthesized narrative. Do not dump raw file contents.

```markdown
## Session briefing — YYYY-MM-DD

### Project: <name>
<one-line summary from project-intel: what it is, tech stack, current state>

### Mistakes to avoid
- <trigger> → <prevention rule> (from: <evidence>)

### Since last session
- <decision/change>: <what> because <why>

### Expiring soon
- <deferred action> due <date>: <description>
- Flag OVERDUE items prominently

### Confidence gaps
- <topic>: <what's uncertain and how to verify>

### Cross-project opportunities
- <project A> could use <capability> from <project B>

### Context
- <top 3 relevant session topic summaries>
```

Return at most 10 items total across all sections. Omit empty sections. Always include the
project-intel one-liner — that is how the briefing proves it knows the project.

## Documentation discovery (when project-intel is missing)

If `.claude/project-intel.md` doesn't exist:

1. Glob `docs/**/*.md` and `content/**/*.md`.
2. Read `CLAUDE.md` for conventions.
3. Check `docs/feedback/`, `docs/content-review/`, `docs/plans/`.
4. Check `.claude/skills/` to learn what the project can do.
5. Flag the user: "This project is missing project-intel.md — consider creating one."

## Known gotchas

- **Dumping raw file contents instead of synthesizing.** The whole point of /brief is to
  pre-digest the project state. If the output looks like cat'd files, the skill failed.
- **Forgetting suppression.** Without the spaced-repetition step, every session shows the
  same three warnings. Users tune the briefing out fast.
- **Loading too much.** Capping at 10 items keeps the briefing scannable. Anything longer
  competes with the actual task for attention.

## Anti-patterns

- Generating a briefing without first checking that the project files exist. An empty
  briefing is more useful than a hallucinated one — flag the missing files.
- Treating every project the same. The Tier-2 file names are conventions; not every project
  has them. Skip what's missing instead of inventing it.

## Validated patterns

- Briefings under 200 words get read. Briefings over 500 words get skimmed.
- The "since last session" section is the most-used part. Spend extra care making the
  diff accurate.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The user explicitly corrects a briefing item (strongest signal — log immediately; 2–3
  corrections on the same theme → promote to body).
- A golden case that previously passed starts failing.
- A novel input category recurs across sessions.
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.
- The Claude model version changes.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
