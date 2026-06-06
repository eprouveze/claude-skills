---
name: pair-session
description: |
  AI pair programming with Claude (builder) and a second model (advisor). The human
  observes and can intervene. Three styles: standard (Claude builds → advisor reviews),
  ping-pong (TDD-style alternation), and strong-style (advisor proposes → Claude
  implements). Use when asked for "pair session", "claude codex pair", "ai pair
  programming", or "/pair-session".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
---

# /pair-session - Claude-Codex AI Pair Programming

Two AI agents collaborate on coding tasks: Claude builds, Codex reviews and advises.
The human observes and can intervene when needed.

## CRITICAL: Authentication

Codex CLI MUST use `chatgpt` auth mode (ChatGPT Business subscription).
**NEVER use an API key.** Verify before starting:

```bash
grep -q '"auth_mode": "chatgpt"' ~/.codex/auth.json && echo "OK" || echo "ERROR: Not using ChatGPT auth"
```

If not authenticated, tell the user to run `! codex login` (interactive).

## Command Syntax

```
/pair-session build <task description>              # Standard: Claude builds, advisor reviews
/pair-session build --style ping-pong <task>        # TDD: alternating test/implement
/pair-session build --style strong <task>           # Strong-style: advisor proposes, Claude implements
/pair-session build --advisor gemini <task>         # Use Gemini instead of Codex
/pair-session build -s pp -a g <task>               # Short: ping-pong with Gemini
/pair-session pause                                 # Pause for human input
/pair-session redirect <new direction>              # Change focus mid-session
/pair-session end                                   # End session, generate summary
```

## Pairing Styles

| Style | Flag | Flow | Best For |
|-------|------|------|----------|
| **Standard** | (default) | Claude builds → Advisor reviews | General development |
| **Ping-Pong** | `--style ping-pong` or `-s pp` | One writes test → Other implements → swap | TDD, high-quality code |
| **Strong-Style** | `--style strong` or `-s strong` | Advisor proposes → Claude implements | Learning, knowledge transfer |

## Advisor Selection

Three advisors are available:
- **Codex (default)**: OpenAI gpt-5.5 via Codex CLI — subscription-based. Pass `--codex-model gpt-5.5` for the sharper Diagnostician model (slower, ~2× cost).
- **Gemini**: Google gemini-3.1-pro via Antigravity CLI (`agy`) — subscription-based. `agy` replaces the sunset Gemini CLI on consumer plans as of 2026-06-18; enterprise plans may still ship `gemini`. The `--advisor gemini` flag stays (it names the model seat, not the binary).
- **DeepSeek-v4** (optional): via OpenAI-compatible API at `api.deepseek.com` — needs `DEEPSEEK_API_KEY`. Strong field-engineer voice (web-fresh, ready-to-paste artifacts, tabular).

Use `--advisor gemini` or `-a g` to switch advisors. `--advisor deepseek` / `-a d` for DeepSeek.

## Simple Task Warning

Before starting a session, evaluate task complexity:

```
/pair-session build fix typo in README

⚠️  SIMPLE TASK WARNING
━━━━━━━━━━━━━━━━━━━━━━━
This task appears simple enough for solo work.
Pair programming optimizes for QUALITY over SPEED on complex tasks.

Research shows pairing on simple tasks:
- Reduces productivity without quality benefit
- Uses 2x resources for minimal gain

Recommended for pairing:
- Multi-file changes
- Architectural decisions
- Security-sensitive code
- Complex algorithms
- Unfamiliar codebases

Continue with pair session anyway? [y/N]
```

**Complexity signals (proceed without warning if 2+ present):**
- Task mentions multiple files
- Task involves security, auth, payments
- Task requires architectural decisions
- Task touches unfamiliar code
- User explicitly requests pairing

---

## Ping-Pong TDD Mode (`--style ping-pong`)

Test-driven alternation pattern from extreme programming. Research shows TDD + pairing
is "perfect companions" — tests define contracts, partner implements.

### Protocol

```
┌─────────────────────────────────────────────────────────────┐
│  PING-PONG TDD CYCLE                                        │
│                                                             │
│  1. Claude writes failing test (RED)                        │
│     └─→ Advisor reviews test design                         │
│                                                             │
│  2. Advisor suggests implementation approach                │
│     └─→ Claude implements minimum code to pass (GREEN)      │
│                                                             │
│  3. Claude writes next failing test (RED)                   │
│     └─→ Advisor reviews + may suggest refactor              │
│                                                             │
│  4. Advisor reviews accumulated code                        │
│     └─→ Claude refactors if needed (REFACTOR)               │
│                                                             │
│  Repeat until task complete                                 │
└─────────────────────────────────────────────────────────────┘
```

### Turn Structure

**Turn A: Claude writes test**
```
### CLAUDE WRITES TEST (RED)

I'm adding a test for the retry utility's timeout behavior:

```typescript
test('aborts after timeout exceeded', async () => {
  const slowFn = () => new Promise(r => setTimeout(r, 5000))
  await expect(retry(slowFn, { timeout: 100 })).rejects.toThrow('timeout')
})
```

This test will fail because we haven't implemented timeout yet.
Running: `npm test -- --grep "aborts after timeout"`
Result: FAIL ✗
```

**Turn B: Advisor reviews test + suggests implementation**
```
### ADVISOR REVIEWS TEST

APPROVE test design. Good edge case coverage.

Suggested implementation approach:
- Add `timeout` option to RetryOptions interface
- Wrap each attempt in Promise.race with timeout
- Throw typed TimeoutError for better catch handling

Proceed with implementation.
```

**Turn C: Claude implements (GREEN)**
```
### CLAUDE IMPLEMENTS (GREEN)

Implementing advisor's suggested approach:
[code implementation]

Running: `npm test -- --grep "aborts after timeout"`
Result: PASS ✓
```

### Benefits of Ping-Pong

- Forces test-first thinking
- Each agent reviews the other's work
- Natural rhythm prevents one agent dominating
- Tests serve as executable specification

---

## Strong-Style Mode (`--style strong`)

"For an idea to go from your head to the computer, it must go through someone else's hands."
— Llewellyn Falco

In strong-style, the **advisor proposes**, Claude **implements**. This maximizes knowledge
transfer — Claude learns the advisor's patterns by implementing them.

### Protocol

```
┌─────────────────────────────────────────────────────────────┐
│  STRONG-STYLE PAIRING                                       │
│                                                             │
│  1. Advisor proposes approach + pseudo-code                 │
│     └─→ "Here's how I'd structure this..."                  │
│                                                             │
│  2. Claude implements exactly as proposed                   │
│     └─→ No deviation without explicit discussion            │
│                                                             │
│  3. Claude can ask clarifying questions                     │
│     └─→ "Should this handle null or throw?"                 │
│                                                             │
│  4. Advisor reviews implementation                          │
│     └─→ Confirms matches intent, suggests refinements       │
│                                                             │
│  Repeat until task complete                                 │
└─────────────────────────────────────────────────────────────┘
```

### Turn Structure

**Turn A: Advisor proposes (Claude requests proposal)**
```
### REQUESTING ADVISOR PROPOSAL

Task: Add rate limiting to API routes

Advisor, please propose your approach. Describe:
1. Architecture/pattern to use
2. Key implementation details
3. Files to modify
4. Any gotchas to watch for
```

**Turn B: Advisor proposes**
```
### ADVISOR PROPOSES

I'd implement this using express-rate-limit middleware:

1. Create `src/middleware/rateLimiter.ts`
2. Use sliding window algorithm (more fair than fixed)
3. Key by IP + authenticated user ID (prevents single-IP abuse)
4. Store in Redis for multi-instance support

Pseudo-code:
```typescript
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 min
  max: 100,
  keyGenerator: (req) => req.user?.id || req.ip,
  store: new RedisStore({ client: redis })
})
```

Apply to `/api/*` routes. Return 429 with Retry-After header.
```

**Turn C: Claude implements**
```
### CLAUDE IMPLEMENTS

Implementing advisor's proposal exactly:
[code implementation following the pseudo-code]

Question before proceeding: Should the rate limit be configurable
per-route, or global? Your proposal shows global.
```

### When to Use Strong-Style

- Learning a new codebase (let Codex guide Claude through patterns)
- Unfamiliar domain (let domain expert lead)
- Knowledge transfer is the primary goal
- When advisor has specific expertise Claude lacks

---

## Build Mode Protocol

When invoked with `/pair-session build <task>`:

### Phase 1: Session Setup

1. Check advisor CLI availability:
   ```bash
   # For Codex (default)
   codex --version 2>/dev/null || echo "UNAVAILABLE"
   grep -q '"auth_mode": "chatgpt"' ~/.codex/auth.json && echo "OK" || echo "AUTH_ERROR"

   # For Gemini (if --advisor gemini) — `agy` first, legacy `gemini` as enterprise fallback.
   # When invoking `agy` non-interactively, always use `agy -p "<prompt>" </dev/null`;
   # without the stdin redirect, `agy` deadlocks waiting on a TTY.
   agy --version 2>/dev/null \
     || gemini --version 2>/dev/null \
     || echo "UNAVAILABLE"
   ```

2. Create session state file:
   ```bash
   SESSION_ID="pair-$(date +%Y%m%d-%H%M%S)"
   SESSION_FILE=".context/pair-sessions/${SESSION_ID}.json"
   mkdir -p .context/pair-sessions
   ```

3. Initialize session state (JSON in `.context/pair-sessions/`)

4. **Load Context Preamble (Layer 1)** — loaded ONCE, reused every turn:
   ```bash
   # Read brand.json for conventions, framework, terminology
   cat .claude/brand.json 2>/dev/null

   # Read project-intel.md for tech stack (first 80 lines)
   head -80 .claude/project-intel.md 2>/dev/null
   ```

   Build a compact preamble (~300-500 words) containing:
   - `PROJECT:` description from brand.json
   - `FRAMEWORK:` type, language, styling
   - `CONVENTIONS:` list from brand.json
   - `TERMINOLOGY:` use/avoid pairs
   - `TECH CONTEXT:` first 20 key lines from project-intel.md

   Store the preamble in `session.context_preamble` for reuse.

5. **Load Failure Atlas** — critical/high severity prevention rules:
   ```bash
   cat docs/memory/failure-atlas.md 2>/dev/null | head -100
   ```
   Extract top 5 critical/high entries as `KNOWN RISKS` section.

### Phase 1.5: Context Strategy

**Two layers ensure the advisor reviews against project standards:**

| Layer | When | What | Size |
|-------|------|------|------|
| **Layer 1: Preamble** | Session start (once) | brand.json + project-intel.md + failure atlas | ~500 words |
| **Layer 2: Per-Turn** | Each turn (Claude curates) | Relevant existing code, recent decisions, touched files | ~200 words |

**Layer 2 is Claude's responsibility.** Before each advisor review, Claude:
1. Reads the files being modified to extract existing patterns
2. Checks if any decisions log entries are relevant
3. Includes only what's needed for THIS specific review

**Why not inject everything?** Token budget. Multi-agent uses ~15x tokens vs single.
The advisor doesn't need the full failure atlas — just the 3 entries relevant to
the current code change.

### Phase 2: Turn-Taking Loop

Each cycle follows this pattern:

**Turn A: Claude Proposes**
1. Analyze the task or current state
2. Propose an approach or code change
3. **Prepare code context for advisor** (IMPORTANT):
   - Read the file(s) being modified
   - Extract ~20-30 lines of surrounding context around each change
   - Note any related files (imports, types, callers) that affect the review
   - Format as shown below
4. Write the proposal to session state:
   ```json
   {
     "turn": 1,
     "agent": "claude",
     "type": "proposal",
     "content": "<approach description>",
     "code_changes": [{"file": "path", "action": "create|edit|delete"}],
     "timestamp": "<ISO>"
   }
   ```
5. Display proposal clearly with `### CLAUDE PROPOSES` header

### Code Context Format (for advisor)

When sending code to the advisor, use this structure:

```
## File: src/utils/retry.ts (EDIT)

### Existing Code (relevant section)
```typescript
// Lines 15-45 — the function being modified
export async function fetchWithTimeout(url: string, options?: RequestInit) {
  const controller = new AbortController()
  // ... existing implementation
}
```

### Proposed Change
```diff
- const controller = new AbortController()
+ const controller = new AbortController()
+ const timeoutId = setTimeout(() => controller.abort(), options?.timeout ?? 30000)
```

### Related Context
- Called by: src/api/client.ts (3 call sites)
- Imports AbortController from globals (no change needed)
```

**Why this format?**
- Advisor sees the code BEFORE the change (catches "you're breaking existing behavior")
- Diff shows exactly what's changing
- Related context catches ripple effects

**What NOT to send:**
- Full file contents (token waste)
- Unrelated files
- Build artifacts, lock files, generated code

**Turn B: Codex Reviews**
1. Build context-rich prompt for advisor:
   ```
   You are reviewing code proposed by another AI (Claude).
   Your role is to find issues, suggest improvements, and catch edge cases.
   Be specific and constructive. Review against the project's conventions.

   ## Project Context (for reviewer)
   PROJECT: <from brand.json>
   FRAMEWORK: <from brand.json>
   CONVENTIONS:
   - <convention 1>
   - <convention 2>
   TERMINOLOGY:
   - Use "X" not "Y"
   KNOWN RISKS:
   - <relevant failure atlas entry>

   ## This Turn's Context
   <existing code patterns in modified files>
   <relevant recent decision, if any>

   TASK: <task description>

   PROPOSED APPROACH:
   <Claude's proposal>

   CODE CHANGES:
   <git diff or file contents>

   Respond with ONE of:
   1. APPROVE — changes look good (include any minor suggestions)
   2. CONCERNS — issues to address (list them specifically)
   3. ALTERNATIVE — you have a better approach (explain why)
   4. QUESTION — you need clarification before reviewing (ask specifically)

   If you need clarification, use QUESTION. Claude will answer, then you continue reviewing.
   Reference project conventions when relevant.
   ```

2. Execute Codex review:
   ```bash
   CODEX_RESPONSE=$(codex exec "<context prompt>" \
     -s read-only \
     -c 'model_reasoning_effort="xhigh"' \
     --json 2>/dev/null)
   ```

3. Parse JSONL response and extract message:
   ```bash
   echo "$CODEX_RESPONSE" | python3 -c "
   import sys,json
   for line in sys.stdin:
       try:
           d=json.loads(line)
           if 'agent_message' in d: print(d['agent_message'])
           elif 'message' in d: print(d['message'])
       except: pass
   "
   ```

4. Save Codex session ID for follow-ups:
   ```bash
   CODEX_SID=$(echo "$CODEX_RESPONSE" | python3 -c "
   import sys,json
   for line in sys.stdin:
       try:
           d=json.loads(line)
           if 'session_id' in d: print(d['session_id']); break
       except: pass
   ")
   ```

5. Display advisor response with `### ADVISOR REVIEWS` header — **NEVER editorialize**

6. **Handle QUESTION responses** (Q&A sub-loop):
   If advisor responds with QUESTION:
   ```
   ### ADVISOR ASKS
   > What happens if `options.timeout` is 0? Is that intentional infinite timeout
   > or should it be treated as "use default"?
   ```

   Claude answers the question:
   ```
   ### CLAUDE ANSWERS
   Good question. A timeout of 0 would mean "abort immediately" which isn't useful.
   I'll treat 0 as "use default" (30000ms). Updating the code to:
   `options?.timeout || 30000` (falsy check, not nullish)
   ```

   Then resume the advisor session for continued review:
   ```bash
   codex exec resume "$CODEX_SID" "<Claude's answer + any code updates>" \
     -s read-only -c 'model_reasoning_effort="xhigh"' --json
   ```

   The advisor can ask multiple questions. Loop until advisor gives
   APPROVE/CONCERNS/ALTERNATIVE. Cap at 3 questions to prevent infinite loops.

   **Log each Q&A exchange** in the session conversation with type: "question"

**Turn C: Claude Responds**
Based on Codex feedback:
- **If APPROVE**: Implement the code, commit changes
- **If CONCERNS**: Address each concern or document disagreement with reasoning
- **If ALTERNATIVE**: Evaluate and either adopt, reject with reasoning, or propose hybrid

**Disagreement Protocol**:
When Claude overrides Codex, MUST document:
```
### DISAGREEMENT LOGGED
Codex suggested: <suggestion>
Claude's decision: <decision>
Reasoning: <why Claude disagrees>
```

### Phase 3: Code Implementation

After approval or documented disagreement:

1. Implement the code changes using Edit/Write tools
2. Run verification (if applicable):
   ```bash
   npm run type-check 2>/dev/null || echo "SKIP"
   npm run lint 2>/dev/null || echo "SKIP"
   ```
3. Show diff to human: `git diff --stat`
4. Continue to next iteration or complete

### Phase 4: Session Completion

When task is complete or `/pair-session end` is invoked:

1. Generate session summary
2. Save session log to `pair-sessions/YYYY-MM-DD-<slug>.md`:
   ```markdown
   ---
   date: YYYY-MM-DD
   session_id: <id>
   task: <description>
   style: standard|ping-pong|strong
   turns: <count>
   duration: <minutes>
   outcome: completed|paused|redirected
   knowledge_items: <count>
   ---

   # Pair Session: <task>

   ## Summary
   <what was accomplished>

   ## Key Decisions
   <list of decisions made>

   ## Advisor Contributions
   <improvements suggested by advisor>

   ## Knowledge Transferred
   <insights gained during session — see below>

   ## Full Transcript
   <turn-by-turn log>
   ```

## Knowledge Transfer Log

Track insights learned during the session. This captures the *real value* of pairing
beyond just code produced.

### When to Log

Log a knowledge transfer when:
- Advisor catches a gotcha you didn't know about
- A pattern or technique is explained
- A convention is clarified
- A tool/library usage tip is shared
- An edge case reveals something new

### Format

```json
{
  "turn": 4,
  "source": "codex",
  "insight": "Full jitter is better than additive jitter for exponential backoff",
  "category": "pattern"
}
```

### Categories

| Category | Description | Example |
|----------|-------------|---------|
| `pattern` | Design pattern or architectural approach | "Use sliding window for rate limiting" |
| `gotcha` | Common mistake or edge case | "setTimeout returns immediately if delay is 0" |
| `technique` | Implementation technique | "Use Promise.race for timeout handling" |
| `convention` | Project or industry convention | "Always return Retry-After header with 429" |
| `tool` | Tool or library tip | "Use --json flag with codex exec for parsing" |

### Session Summary Example

```markdown
## Knowledge Transferred

### From Codex (3 items)
- **[pattern]** Full jitter (random * cap) is better than additive jitter for
  exponential backoff — reduces collision probability by 3-4x under load
- **[gotcha]** A timeout of 0 means "abort immediately" not "no timeout" —
  use nullish check, not falsy check
- **[technique]** AbortSignal integration: use `{ once: true }` option on
  addEventListener to prevent listener leaks

### From Claude (1 item)
- **[convention]** This codebase uses Zod for all API validation — advisor
  initially suggested manual validation
```

### Why Track This

1. **Proves pairing value** — not just code, but learning
2. **Builds institutional knowledge** — insights can be added to failure atlas
3. **Identifies gaps** — frequent gotchas suggest documentation needs
4. **Measures advisor quality** — which advisor teaches more?
3. Update session state to `status: "completed"`
4. Display summary to human

## Human Intervention

**Pause**: When `/pair-session pause` is detected or human sends a message:
- Save current state
- Wait for human input
- Resume with human's guidance

**Redirect**: When `/pair-session redirect <direction>`:
- Log the redirect in session
- Adjust task focus
- Continue with new direction

## Fallback Mode

If selected advisor CLI is unavailable:
```
### WARNING: [Codex|Antigravity (agy)] CLI unavailable
Running in Claude-only mode. Install advisor CLI for full pair programming:

  # For Codex (default):
  npm install -g @openai/codex && codex login

  # For Gemini seat — Antigravity CLI (`agy`), the replacement for the sunset
  # Gemini CLI on consumer plans as of 2026-06-18. Enterprise plans may still
  # use `gemini` directly.
  curl -fsSL https://antigravity.google/cli/install.sh | bash && agy login
```
Continue with Claude implementing and self-reviewing (reduced effectiveness).

Alternatively, try the other advisor with `--advisor gemini` or `--advisor codex`.

## Context Summarization

After 10 turns, summarize older turns to prevent context exhaustion:
1. Keep last 5 turns in full
2. Summarize turns 1-N as "Previous context: <summary>"
3. Log full transcript to session file

## Timeouts

- Codex CLI calls: 300 seconds (5 minutes)
- Session maximum: 60 minutes before auto-pause

## Golden rules

1. **Advisor output is verbatim.** Never editorialize. Show the raw response.
2. **Document disagreements.** When Claude overrides the advisor, log the reasoning.
3. **Human can always intervene.** Check for pause or redirect between turns.
4. **Persist state.** The session can resume after an interruption.
5. **Graceful degradation.** If the advisor CLI fails, continue in Claude-only mode and
   surface the failure.

## Known gotchas

- **Auth drift.** Codex CLI's auth token can expire mid-session. The pre-flight check
  catches it at the start but not at minute 45. If a turn fails with an auth error,
  pause, prompt the user to re-auth, and resume.
- **Strong-style + a chatty advisor produces "advisor monologue".** If the advisor's
  proposal is longer than 200 lines, ask it to compress before Claude implements.
- **Context drift over long sessions.** After ~10 turns the advisor loses earlier
  context. The summarization step is mandatory, not optional.
- **`agy -p "<prompt>"` without `</dev/null` deadlocks.** Antigravity CLI waits on
  a TTY for stdin even when a prompt arg is given. Use `agy -p "<prompt>" </dev/null`
  in every scripted call site; the version probe in Phase 1 is the only `agy`
  invocation without it and it doesn't take a `-p` arg.

## Anti-patterns

- Treating the advisor's review as gospel. The whole point of pairing is that the two
  models disagree. Claude is allowed to push back.
- Running pair-session for tasks that fit in a single Claude call. The overhead is
  real; reserve pairing for non-trivial work.

## Validated patterns

- Ping-pong style produces the highest test coverage of the three. Strong-style produces
  the cleanest design when there's a clear "shape" but messy details.
- Standard style is the right default for unfamiliar territory.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The user repeatedly overrides the advisor on the same kind of question (the style or
  the advisor model is mismatched).
- A new advisor CLI joins the matrix.
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.
- A CLI vendor ships a breaking change.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
