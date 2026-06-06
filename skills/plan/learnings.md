# plan — learnings log

Append-only. Dated entries. Each entry gets one of three fates on consolidation: **apply**
(promote into SKILL.md body), **capture** (keep here), **dismiss**.

Consolidate weekly OR when this file exceeds ~100 bullets.

## Format

```
## YYYY-MM-DD — <one-line context>
- <observation>
- <natural-language critique: "When X, naive approach produces Y because Z — do W instead">
```

## 2026-06-06 — seeded
- Skill published to the claude-skills collection.
- Core is research-first planning via parallel sub-agents; delegating codebase exploration to
  a second CLI model is an optional context-saving enhancement, not a dependency.
- When delegating exploration, always spot-check 2-3 cited paths — delegated models hallucinate
  file paths that look plausible but don't exist.
