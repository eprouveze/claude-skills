# keyword-research — learnings log

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
- Google Trends has no official API and no key — the `google-trends-api` package scrapes public
  endpoints and is rate-limited. A blocked request returns HTML, surfacing as a JSON-parse error;
  back off and retry rather than treating it as "0 interest".
- Keywords across different batches of 5 are normalized to different baselines — never compare
  absolute ranks across batch boundaries.
