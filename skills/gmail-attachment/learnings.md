# gmail-attachment — learnings log

Append-only. Dated entries. Each entry gets one of three fates on consolidation: **apply**
(promote into SKILL.md body), **capture** (keep here), **dismiss**.

Consolidate weekly OR when this file exceeds ~100 bullets.

## Format

```
## YYYY-MM-DD — <one-line context>
- <observation>
- <natural-language critique: "When X, naive approach produces Y because Z — do W instead">
```

## 2026-06-17 — seeded from the failed-send incident

- First publication. The skill was created after a real-world failure: a 26 KB Markdown
  file was sent with a truncated base64 payload because the model "summarized" the
  content into a placeholder. Recipient got a 5 KB garbled file. Recovery required a
  follow-up "Correction" email.
- The MCP `path` field was tried three different ways (host absolute, `/tmp`, project
  relative). All failed with the same "Path does not exist" error pointing at the MCP's
  sandbox. This is the load-bearing reason the skill exists.
- Persona send (`from_name = "Lex (pour Emmanuel Prouveze)"`) worked on the very first
  attempt and survived the recovery flow. Worth keeping in mind for chief-of-staff
  patterns.
- Validated MIME: `text/markdown` accepted by Gmail and rendered as expected attachment.
