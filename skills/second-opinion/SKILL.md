---
name: second-opinion
description: |
  Get a second opinion from OpenAI's Codex CLI. Default model is gpt-5.5. Three
  modes: review (pass/fail code review on the current diff), challenge (adversarial
  pass — try to break it), consult (multi-turn Q&A with session persistence). Uses
  ChatGPT subscription auth, not an API key. Use when asked for "second opinion",
  "codex review", "adversarial review", "challenge this code", "cross-model review",
  or "/second-opinion".
allowed-tools:
  - Bash
  - Read
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
---

# /second-opinion — Cross-LLM Review via Codex CLI

Get an independent review from OpenAI via the Codex CLI. Three modes for different needs:
quick pass/fail review, adversarial break-it pass, or multi-turn consultation.

## Authentication

Codex CLI uses `chatgpt` auth mode (ChatGPT subscription), not an API key. API-key auth
also works but burns tokens against your OpenAI bill; the subscription path is free at the
margin and is what this skill assumes. Verify before running:

```bash
grep -q '"auth_mode": "chatgpt"' ~/.codex/auth.json && echo "OK: Using ChatGPT subscription" || echo "ERROR: Not using ChatGPT auth"
```

If not authenticated, tell the user to run `! codex login` (interactive).

## Mode Detection

Parse user input to determine mode:

| Input | Mode |
|-------|------|
| `/second-opinion review` | Review |
| `/second-opinion challenge` or `/second-opinion challenge security` | Challenge |
| `/second-opinion <any question>` | Consult |
| `/second-opinion` (no args) | Auto-detect: if uncommitted changes exist → Review, else → Consult |

## Mode 1: Review (pass/fail code review)

Reviews the current diff against the base branch.

```bash
cd <project-root>
codex review --base HEAD~1 -c 'model_reasoning_effort="xhigh"' 2>/dev/null
```

Or against a specific base:
```bash
codex review --base main -c 'model_reasoning_effort="xhigh"' 2>/dev/null
```

**Output handling:**
- Present Codex's output verbatim inside a `### CODEX SAYS` section
- Look for `[P1]` markers in the output — these are critical findings
- If P1 found: verdict is **FAIL** with list of critical issues
- If no P1: verdict is **PASS**
- Add token count and comparison note if Claude's `/review` already ran

**Timeout:** 300 seconds (5 minutes). If it times out, say "Diff may be too large or API is slow."

## Mode 2: Challenge (adversarial)

Try to break the code. Finds edge cases, race conditions, security holes.

```bash
cd <project-root>
DIFF=$(git diff HEAD~1)
codex exec "You are an adversarial code reviewer. Your job is to BREAK this code. Find edge cases, race conditions, security vulnerabilities, error handling gaps, and failure modes. Be aggressive and thorough. Here is the diff:\n\n$DIFF" \
  -s read-only \
  -c 'model_reasoning_effort="xhigh"' \
  --json 2>/dev/null
```

If the user specifies a focus domain (e.g., `/second-opinion challenge security`):
```bash
codex exec "You are a security auditor. Find injection vectors, auth bypasses, SSRF, XSS, CSRF, and data exposure in this diff:\n\n$DIFF" \
  -s read-only \
  -c 'model_reasoning_effort="xhigh"' \
  --json 2>/dev/null
```

**Output handling:**
- Parse JSONL output: extract `agent_message` and `reasoning` fields
- Present ALL findings verbatim — never summarize or editorialize
- Group by severity if Codex provides severity markers

## Mode 3: Consult (multi-turn Q&A)

Ask Codex anything with session persistence for follow-ups.

**First question:**
```bash
cd <project-root>
RESULT=$(codex exec "<user's question>" \
  -s read-only \
  -c 'model_reasoning_effort="xhigh"' \
  --json 2>/dev/null)
echo "$RESULT"
```

Save session ID for follow-ups:
```bash
SESSION_ID=$(echo "$RESULT" | python3 -c "
import sys,json
for line in sys.stdin:
    try:
        d=json.loads(line)
        if 'session_id' in d: print(d['session_id']); break
    except: pass
" 2>/dev/null)
if [[ -n "$SESSION_ID" ]]; then
  mkdir -p .context
  echo "$SESSION_ID" > .context/codex-session-id
fi
```

**Follow-up questions:**
```bash
SESSION_ID=$(cat .context/codex-session-id 2>/dev/null)
if [[ -n "$SESSION_ID" ]]; then
  codex exec resume "$SESSION_ID" "<follow-up question>" \
    -s read-only \
    -c 'model_reasoning_effort="xhigh"' \
    --json 2>/dev/null
else
  # No session — start fresh
  codex exec "<question>" -s read-only -c 'model_reasoning_effort="xhigh"' --json 2>/dev/null
fi
```

## Golden Rules

1. **Never editorialize Codex's output.** Show it verbatim in a `### CODEX SAYS` block.
2. **Never use API key auth.** Always verify `chatgpt` auth mode before running.
3. **Always use `-s read-only`** for challenge and consult modes (sandbox).
4. **Always use `model_reasoning_effort="xhigh"`** for maximum reasoning depth.
5. **Timeout is 300s** on all Bash calls to Codex.
6. **Compare, don't compete.** If Claude already reviewed the same code, note where Codex agrees or disagrees — both perspectives are valuable.

## Error Handling

| Error | Fix |
|-------|-----|
| `codex: command not found` | `npm install -g @openai/codex` |
| Auth failure / token expired | User runs `! codex login` |
| Timeout (300s) | Diff too large or API slow — try with smaller scope |
| Empty response | Check stderr: `codex exec "test" 2>&1` |
| Session resume fails | Delete `.context/codex-session-id`, start fresh |

## Cost

When authenticated against ChatGPT subscription, there is no per-token API cost — calls
draw from the subscription quota. If you are on API-key auth, expect normal token billing
(xhigh reasoning is roughly 2× the cost of medium).

## Known gotchas

- **Editorializing Codex's output buries the point.** The whole value of a second opinion
  is that it disagrees with the first. Show Codex's output verbatim inside a `### CODEX
  SAYS` block and let the human read both.
- **Sandbox mode matters.** Always use `-s read-only` for challenge and consult modes.
  Without it, Codex can write to the working tree.
- **Session resume can fail silently.** If the saved session ID is stale, `codex exec
  resume` returns nothing. Detect "no output" and fall back to a fresh session.

## Anti-patterns

- Running `/second-opinion` and ignoring the result when it disagrees with Claude. The
  purpose of the skill is to surface disagreement. If both models are going to be filtered
  through the same hand, you might as well not run it.
- Using `--model gpt-5.5` (the heavier model) on trivial questions. The slower path is
  worth it for hard prompts — for everything else, the default is fine.

## Validated patterns

- For diff review, running `codex review --base <baseline>` and grepping for `[P1]` markers
  is a reliable pass/fail signal.
- For challenge mode, naming a domain (`challenge security`, `challenge concurrency`) gives
  much sharper output than the generic prompt.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The user explicitly disagrees with the review or challenge output (strongest signal —
  log immediately; 2–3 corrections on the same theme → promote to body).
- A novel input category recurs across sessions.
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.
- The Codex CLI ships a breaking change.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
