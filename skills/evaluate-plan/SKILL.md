---
name: evaluate-plan
description: >
  Evaluate an implementation plan against its source requirements (PRD, spec, or user request)
  to identify gaps, dropped features, and lost intent. Use when the user says "evaluate plan",
  "verify plan", "check the plan", "what did it miss", "plan coverage", or "validate plan".
allowed-tools: Read, Glob, Grep, Bash, Agent, TodoWrite
user-invocable: true
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
  argument-hint: <path-to-source-document>
---

# Evaluate Plan

Systematically verify that an AI-generated implementation plan fully covers its source requirements.

**Context**: First-pass plans silently drop ~20-40% of explicit requirements. A structured coverage
check recovers most gaps. This skill forces a coverage-first second pass.

## Phase 1: Identify the Source of Truth

Locate the document(s) the plan was built from:

- A PRD, spec, feature brief, or user story set
- An intent document or voice transcript
- The original user request in this conversation
- A file path provided as argument (e.g., `evaluate plan against @prd.md`)

If multiple sources exist, treat them as a combined requirement set.

**If no explicit document exists**: reconstruct the requirement set from the user's messages
in the current conversation. Quote the original requests.

> **Rule**: The source document is the authority. If something is in the source but not the
> plan, it is a gap — regardless of whether the plan's approach seems reasonable without it.

## Phase 2: Extract Requirements Inventory

Read the source and extract every discrete requirement into a flat checklist:

| Category | What to Extract |
|----------|----------------|
| **Functional features** | Every capability, behavior, or feature described |
| **Interaction behaviors** | Click, hover, drag, dismiss, keyboard, gesture behaviors |
| **UX / emotional intent** | How it should *feel*, experience goals, tone |
| **Visual requirements** | Layout, styling, animations, responsive behaviors |
| **Data & state** | What data is shown, stored, transformed, persisted |
| **Error & edge cases** | Empty states, fallbacks, timeouts, validation |
| **Integration points** | APIs, external services, auth, notifications |
| **Non-functional** | Performance targets, accessibility, platform support |
| **"Why" context** | Rationale or motivation — intent behind features |

**Extraction rules:**
- One requirement per line — do not bundle related items
- Preserve original language where possible
- Feelings and experiences are requirements
- Implicit requirements count (e.g., "like Spotlight" implies global hotkey, float-above, escape-to-dismiss)
- Do not merge for convenience — "user management" is not one requirement; break it into registration, login, password reset, roles, etc.

## Phase 3: Evaluate Coverage

For each requirement, search the plan and assign a status:

| Status | Meaning | Criteria |
|--------|---------|----------|
| ✅ Covered | Explicitly addressed | Plan describes how this will be implemented |
| 🟡 Partial | Mentioned but incomplete | Plan references it but lacks specifics or only covers part |
| ❌ Missing | Not in the plan | No mention, no inference, completely absent |
| ⚠️ Misinterpreted | Present but wrong | Plan addresses something that doesn't match source intent |

## Phase 4: Coverage Report

### 4a. Summary

```
COVERAGE REPORT
===============
Source: [document name(s) or "conversation context"]
Plan:   [plan name or "current plan in conversation"]
Total requirements: [N]

  ✅ Covered:         [n] ([%])
  🟡 Partial:         [n] ([%])
  ❌ Missing:          [n] ([%])
  ⚠️ Misinterpreted:   [n] ([%])

Coverage Score: [X]%
```

**Score formula**: `(Covered + 0.5 * Partial) / Total * 100`
Misinterpreted items count as 0 (same as Missing).

### 4b. Missing & Misinterpreted Items (sorted by impact)

```
❌ [Requirement summary]
   Source: "[exact quote from source]"
   Impact: High / Medium / Low
   Why it matters: [one sentence]
```

### 4c. Partial Coverage Items

```
🟡 [Requirement summary]
   Covered: [what the plan addresses]
   Gap:     [what's left out]
```

### 4d. Top Gaps (prioritized shortlist)

List the **5-10 highest-impact gaps** most likely to produce a noticeably incomplete build.

## Phase 5: Replan

After presenting the report:

1. **If coverage >= 95%**: Report the score. Note any remaining gaps as "acknowledged ambiguities."
   Ask if the user wants them addressed.
2. **If coverage < 95%**: Ask "Should I update the plan to address these gaps?"
3. When replanning:
   - Integrate missing items into the existing plan structure (not as an appendix)
   - Preserve everything already covered
   - Add specific implementation notes for previously missing items
   - Flag genuinely ambiguous items that need user clarification

## Phase 6: Re-evaluate

After patching the plan, run Phases 2-4 again on the updated plan.

| Pass | Expected Coverage | What Gets Found |
|------|-------------------|-----------------|
| Plan (no evaluation) | ~60-80% | -- |
| After 1st evaluation + replan | ~90-95% | Core features, interaction behaviors, UX details |
| After 2nd evaluation + replan | ~95-100% | Subtle intent, edge cases, ambiguous specs |

**Stop when**: coverage >= 95% OR remaining gaps are items the user acknowledges as intentionally unspecified.

## Known gotchas

- **The plan's framing is not the source of truth.** Plans often restructure requirements in
  a way that sounds complete but drops items. Always check against the source.
- **Implicit requirements get missed.** "Like Spotlight" implies a global hotkey, float-above,
  escape-to-dismiss, fuzzy search — extract them.
- **"Why" context is a requirement too.** If the plan drops the rationale, downstream
  decisions get made without it.

## Anti-patterns

- Treating one pass as enough. First-pass plans drop 20–40% of explicit requirements;
  re-evaluation after replanning catches the long tail.
- Merging related items for convenience. "User management" is not one requirement — break
  it into registration, login, password reset, roles, etc.
- Scoring on the plan's vocabulary instead of the source's. If the source says "feels like
  Spotlight" and the plan says "command palette UI", do not declare that covered without
  checking the specific behaviors implied by "Spotlight".

## Validated patterns

- The score formula (Covered + 0.5×Partial) / Total × 100 calibrates well across plan
  sizes. 95% is the practical ceiling — below 90% almost always indicates a real gap, not
  a counting artifact.
- Sorting missing items by impact, not by source order, is the single biggest readability
  win in the report.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The user explicitly disagrees with a coverage call (strongest signal — log immediately;
  2–3 corrections on the same theme → promote to body).
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
