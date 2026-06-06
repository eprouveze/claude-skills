# crawl — learnings log

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
- Works zero-setup in direct-fetch-only mode; the Cloudflare Browser Rendering tier activates
  only when CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_BR_TOKEN are set, and is tried first under
  `--tier all` because it handles JS/SPA/WAF pages the direct tier can't.
- Some origins block Cloudflare's egress IPs too — both tiers can fail; keep a non-CF fallback
  (official docs API, GitHub README, search) ready for those.
