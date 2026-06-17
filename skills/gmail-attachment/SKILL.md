---
name: gmail-attachment
description: >
  Send (or draft) a Gmail message with one or more file attachments via the
  google-workspace MCP. Use whenever the user asks to email a file, attach a document,
  send a PDF / markdown / spreadsheet by mail. Trigger phrases — "email this file to X",
  "send by mail with the doc attached", "envoie ce fichier par mail", "joindre en pièce
  jointe". The MCP's documented `path` field is sandboxed and silently fails on host
  paths; this skill enforces the only working route (base64 `content` + `filename`) and
  documents the size envelope.
allowed-tools: Bash, Read
version: 0.1.1
last-updated: 2026-06-17
last-consolidated: 2026-06-17
metadata:
  author: Emmanuel Prouveze
  priority: 50
---

# gmail-attachment — Send Gmail with attachments via google-workspace MCP

## Why this skill exists

The `google-workspace` MCP runs in its own filesystem sandbox (typically
`/app/app/external/servers/`). The `attachments` parameter accepts two shapes:

| Shape | Status | Why |
|---|---|---|
| `{path: "/Users/.../file.pdf"}` | ❌ Always fails | The MCP looks for the path inside its sandbox. Host paths don't exist there. The error message ("Path does not exist") is misleading because the path *does* exist — just not where the MCP can see it. Copying to `/tmp` doesn't help — `/tmp` isn't shared either. Project-relative paths fail too. |
| `{content: "<base64>", filename: "..."}` | ✅ Works | Content is sent inline; the MCP doesn't need to read host disk. |

Without this skill, the natural reflex is to pass `path` (it's the documented field). It
always fails, and the failure mode is misleading. This skill enforces the working route
and documents the practical size envelope so you don't paste 80 KB of base64 into a tool
call and watch it get truncated.

## When to use

Trigger on any request that involves emailing a file:
- "email this PDF to X@example.com"
- "envoie ce fichier par mail à Y"
- "send the report as an attachment"
- "draft an email with the doc attached"

Use this skill **before** reaching for `mcp__google-workspace__send_gmail_message` or
`mcp__google-workspace__draft_gmail_message` directly when an attachment is involved.

Do NOT use for: emails without attachments, attaching Drive files (use sharing instead),
attaching content the user pasted inline (no file involved).

## The procedure

### 1. Confirm intent

Before sending, confirm:
- Recipient address(es)
- Subject and body (or have the user provide them)
- File(s) to attach — get absolute host path(s)
- `from_name` if the message should appear from a persona

For irreversible actions (send vs draft), default to **draft** unless the user explicitly
said "send". Show the prepared call before executing.

### 2. Encode each file to base64

```bash
base64 -i "<absolute-host-path>" | tr -d '\n' > /tmp/__attach_<slug>.b64
wc -c /tmp/__attach_<slug>.b64    # sanity-check size
```

`tr -d '\n'` strips the line wrapping that `base64` adds by default — Gmail rejects
wrapped base64 inside JSON.

### 3. Read the encoded content into context

Use the Read tool on the `.b64` file. The Read tool returns the full content on one line
with a `1\t` line-number prefix that you must strip (the actual content starts after the
tab character).

**Size envelope.** The base64 is ~1.37× the original size. The reliable ceiling is
**much lower than you'd think** — empirically, a 34.5 KB encoded payload timed out
mid-call ("API Error: The operation timed out"). Plan conservatively.

| Original file size | Encoded size | Recommendation |
|---|---|---|
| ≤ 15 KB | ≤ 20 KB | Inline `content` works reliably |
| 15–30 KB | 20–40 KB | Inline `content` may time out — verify by checking sent mail |
| > 30 KB | > 40 KB | **Don't try inline.** Use the draft-and-attach-manually escape hatch (below) or share via Drive |

### Escape hatch — draft + manual attach

When the file is too large for reliable inline send:

1. Create a Gmail **draft** (no attachment) via
   `mcp__google-workspace__draft_gmail_message` with the full body text.
2. Tell the user: "draft created — open it in Gmail web UI and attach
   `<filename>` from `<host-path>` before sending".
3. Done. Costs one manual step, avoids both the timeout and the truncation trap.

This is often the *right* choice even when inline would work, because it keeps the
human in the loop on the irreversible action (the actual send).

### 4. Build and execute the MCP call

```
mcp__google-workspace__send_gmail_message(
  to = "...",
  subject = "...",
  body = "...",
  from_name = "...",                     # optional, persona
  attachments = [{
    "filename":  "<original-filename-with-extension>",
    "content":   "<full base64 string, no line-number prefix, no wrapping>",
    "mime_type": "<correct mime>"        # see table below
  }]
)
```

For drafts, use `mcp__google-workspace__draft_gmail_message` with the identical signature.

### 5. Verify

After execution, check the returned message ID. If sending a corrected version of an
earlier message, mention that the previous one should be ignored. For high-stakes sends,
search sent mail to confirm delivery and, where possible, ask the recipient to confirm
the attachment opened.

## MIME type cheat sheet

| Extension | MIME |
|---|---|
| `.pdf` | `application/pdf` |
| `.md` | `text/markdown` |
| `.txt` | `text/plain` |
| `.docx` | `application/vnd.openxmlformats-officedocument.wordprocessingml.document` |
| `.xlsx` | `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` |
| `.pptx` | `application/vnd.openxmlformats-officedocument.presentationml.presentation` |
| `.csv` | `text/csv` |
| `.png` | `image/png` |
| `.jpg` / `.jpeg` | `image/jpeg` |
| `.zip` | `application/zip` |
| (unknown) | `application/octet-stream` |

## Multi-file pattern

Encode each file separately, then combine into the array:

```
attachments = [
  {"filename": "report.pdf", "content": "<b64-1>", "mime_type": "application/pdf"},
  {"filename": "data.csv",   "content": "<b64-2>", "mime_type": "text/csv"},
]
```

Don't zip silently — the user expects discrete files.

## Known gotchas

- **The `path` field is a trap.** It is documented in the MCP schema but always fails for
  host files. Treat it as nonexistent.
- **`base64` macOS default wraps lines** at 76 chars. Without `tr -d '\n'`, the JSON-side
  base64 is invalid and the Gmail API rejects the attachment. Always strip newlines.
- **Read tool prefix.** The tool prepends `<line-number>\t` to every line of file output.
  When you copy the content into a tool call, you must drop that prefix. Including it
  produces invalid base64 and the email gets sent with a corrupt attachment — silently.
- **Tool-call truncation by you, not the MCP.** Above ~80 KB of inline content, the model
  is tempted to "summarize" or "truncate for safety". This is the most common failure
  mode. If the original file is large, **draft** rather than send, or share via Drive.

## Anti-patterns

- ❌ Falling back to `path` after a `content` failure. The MCP fails again the same way;
  you've just doubled the spend.
- ❌ Pasting "<full base64 here, ~26 KB, omitted>" or any other placeholder into the
  `content` field. The recipient receives a truncated/garbled file. This actually
  happened in early use — the cost is a follow-up "correction" email and a small loss of
  credibility.
- ❌ Using URL-safe base64 (`-_` alphabet). The MCP expects standard base64. `base64 -i`
  on macOS produces standard.
- ❌ Mixing `path` and `content` in the same attachment object. Pick one (always
  `content`).

## Validated patterns

- **Encode → Read → Inline `content`.** Verified via a successful send of a ~26 KB
  Markdown file that returned a Gmail message ID and arrived intact.
- **Failure recovery flow** when the first send went out with a truncated attachment:
  send a brief follow-up titled "Correction — <original subject>", open with one line
  asking the recipient to ignore the previous mail, attach the correct file via this
  skill.
- **Persona sending** via `from_name = "Lex (pour Emmanuel Prouveze)"` works as expected
  — the recipient sees the persona, replies route to the authenticated account.

## Self-improvement

Append observations to `learnings.md` whenever:
- A new MIME type is encountered
- The size envelope shifts (different model, different runtime)
- A new failure mode appears (e.g., unicode filenames, multi-recipient quirks)
- The MCP schema changes

Consolidate weekly, or when `learnings.md` crosses ~100 bullets. On consolidation, each
entry gets one of: **apply** (promote into the SKILL body), **capture** (keep in the
log), **dismiss**.

## See also

- For Drive sharing instead of attaching:
  `mcp__google-workspace__manage_drive_access`.
- For inline images in HTML body: not currently supported by the
  `google-workspace` MCP. Use a Drive link.
