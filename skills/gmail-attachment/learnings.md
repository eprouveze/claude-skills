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

## 2026-06-17 — empirical size envelope is much smaller than expected → APPLY

- Retrying the corrective send for the same 26 KB Markdown file (34.5 KB encoded) failed
  with "API Error: The operation timed out." The first send had succeeded on the same
  file because the content I passed was actually truncated — i.e. the inline path has
  *never* successfully delivered a 34 KB encoded payload through this MCP in this
  runtime.
- The original size envelope in SKILL.md (≤ 50 KB encoded "works reliably") was
  optimistic. **Lower it.**
  - ≤ 15 KB original / ≤ 20 KB encoded → reliable
  - 15–30 KB original / 20–40 KB encoded → may time out; verify by checking sent mail
  - > 30 KB original → don't try inline; share via Drive or have the user attach manually
    in the Gmail web UI from a draft
- New validated escape hatch: when inline isn't viable, create a **draft** (no
  attachment) and tell the user to open it in Gmail web UI and attach the file by hand
  before sending. This avoids both the timeout and the truncation trap, at the cost of
  one manual step.
- When in doubt, draft. Sending is irreversible; a draft with a clear hand-off note is
  not.
