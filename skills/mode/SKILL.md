---
name: mode
description: >
  Toggle between single-LLM (Claude-only) and multi-LLM (delegate to Gemini, Codex, or
  other CLIs) modes. Shows current mode, available external CLIs, delegation stats, and
  logs. Use when the user says "switch to multi", "use Gemini", "delegation status", "how
  many delegations", or "token savings". Subcommands: `/mode` (status), `/mode multi`,
  `/mode single`, `/mode stats`, `/mode reset`.
allowed-tools: Bash, Read, Write
user-invocable: true
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
---

# /mode — LLM Routing Switch

Manage delegation across a multi-LLM setup. The pattern: Claude orchestrates, judges,
reviews, and surgically fixes; cheaper or specialized CLIs handle the heavy lifting.

| Layer | Typical CLI | Strength |
| ----- | ----------- | -------- |
| Heavy reading | Antigravity CLI (`agy`) | Large context window, fast cold reads. Replaces the Gemini CLI on consumer plans as of 2026-06-18; enterprise plans may still ship `gemini`. |
| Heavy writing | Codex CLI | High-throughput code generation |
| Surgical web search | Perplexity API (or others) | Live docs, breaking changes |

Other skills in this collection read `.claude/llm-mode.json` to decide whether to delegate.
When mode is `single`, every skill runs natively in Claude.

## Route by argument

Parse the argument after `/mode`:

- No args → **show status**
- `multi` → **switch to multi**
- `single` → **switch to single**
- `stats` → **show delegation log**
- `reset` → **reset to defaults**

## Show status (default)

Read `.claude/llm-mode.json` and display:

```
## LLM Mode: <MULTI / SINGLE>

### Delegation targets (in multi mode)
  READING (Antigravity CLI / agy):  [available / not found]
  WRITING (Codex CLI):              [available / not found]
  WEB SEARCH (Perplexity):          [key set / key missing]

### Delegation stats
  Total:     N successful delegations
  Failed:    N (X% failure rate)
  Last:      YYYY-MM-DD HH:MM via <skill>

Switch with: /mode multi  or  /mode single
Full log:    /mode stats
```

To populate the display:

1. Read `.claude/llm-mode.json` for mode and stats.
2. Check `agy --version` for Antigravity CLI. Fall back to `gemini --version` for enterprise plans still on the legacy binary.
3. Check `codex --version` for Codex CLI.
4. Check `$PERPLEXITY_API_KEY` (or your provider's env var) for web search.
5. Count entries in `.claude/delegation.log` for the totals.

If `.claude/llm-mode.json` doesn't exist, show `Mode: SINGLE (default — no config file yet)`.

## Switch to multi

1. Verify the Google delegate CLI is installed and authenticated. Prefer Antigravity CLI
   (`agy`); fall back to the legacy `gemini` binary for enterprise plans.

   ```bash
   # Antigravity CLI (consumer + new enterprise).
   # The `</dev/null` redirect is mandatory: `agy -p "..."` deadlocks waiting for
   # TTY input even when a prompt arg is supplied.
   agy --version 2>/dev/null \
     || gemini --version 2>/dev/null

   agy -p "Reply with exactly: OK" </dev/null 2>/dev/null \
     || gemini -p "Reply with exactly: OK" -o text 2>/dev/null
   ```

   If the auth check fails, abort with installation/auth instructions. For `agy`,
   the install command is `curl -fsSL https://antigravity.google/cli/install.sh | bash`.

2. Update `.claude/llm-mode.json`: set `mode` to `"multi"`, update `updated_at` to the
   current ISO timestamp.
3. Append to `.claude/delegation.log`:

   ```
   YYYY-MM-DDTHH:MM:SSZ | mode | ok | 0s | Switched to multi-LLM mode
   ```

4. Check Codex CLI and Perplexity availability non-blockingly. Report each as
   "available" or "not found / key missing" in the confirmation.

## Switch to single

1. Update `.claude/llm-mode.json`: set `mode` to `"single"`, refresh `updated_at`.
2. Log: `... | mode | ok | 0s | Switched to single-LLM mode`.
3. Confirm: "Switched to single-LLM mode. All skills using Claude natively."

## Show delegation log

Read `.claude/delegation.log` and show the last 20 entries plus summary stats: total,
failure rate, average duration on success, most-delegated skill.

## Reset

1. Write a fresh `.claude/llm-mode.json` with defaults (single mode, zeroed stats).
2. Clear `.claude/delegation.log` (keep any header comments).
3. Confirm.

## Delegation logging protocol

Other skills that delegate should follow this protocol:

After a successful delegation:

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | <skill> | ok | <duration>s | <notes>" \
  >> .claude/delegation.log
```

Also increment `stats.delegations_total` and update `stats.last_delegation` in
`.claude/llm-mode.json`.

On failure:

```bash
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | <skill> | fail | <duration>s | <reason>" \
  >> .claude/delegation.log
```

Increment `stats.delegations_failed`.

## Schema for `.claude/llm-mode.json`

```json
{
  "mode": "single",
  "updated_at": "2026-06-04T00:00:00Z",
  "stats": {
    "delegations_total": 0,
    "delegations_failed": 0,
    "last_delegation": null
  }
}
```

## Known gotchas

- **Multi mode without authenticated CLIs silently falls back to Claude.** That can mask
  a real problem — the user thinks they're saving tokens but every delegation is failing.
  The status display surfaces both auth state and recent failure rate for this reason.
- **The log file grows unboundedly.** Rotate or truncate it before it crosses ~10k lines
  or the stats view gets slow.
- **Mode is per-project.** Each project has its own `.claude/llm-mode.json`. Setting it
  in one project does not affect siblings.
- **`agy -p "<prompt>"` requires `</dev/null`.** Without the stdin redirect, Antigravity
  CLI waits on a TTY even when a prompt arg is given. The probe in "Switch to multi"
  uses the canonical `agy -p "..." </dev/null` form; mirror it in every other call site.

## Anti-patterns

- Flipping to multi mode for a quick win, then forgetting to switch back when the
  delegated CLIs go stale. Add the status check to a `/brief`-style routine.
- Trusting `delegations_total` as a token-savings proxy. The skills that delegate know
  their own savings; the mode skill just tracks counts.

## Validated patterns

- Logging both success and failure (rather than just success) keeps the failure-rate
  metric honest. A 30% failure rate is a signal that the auth or model config needs
  attention.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The status display is wrong about CLI availability (the detection command needs
  updating).
- A new external CLI joins the routing pattern.
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
