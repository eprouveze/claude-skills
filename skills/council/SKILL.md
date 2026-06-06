---
name: council
description: >
  5-model strategic advisory. Ask the same question to five different LLM seats in
  parallel, save each response to a persistent file, then synthesize a recommendation.
  Each seat is locked to a role (Theorist, Validator, Provocateur, Diagnostician, Field
  Engineer) so the responses disagree by design instead of converging by accident.
  Use when the user says "ask the council", "get opinions", "council on", "what do they
  all think", "multi-model opinion", or wants strategic input from multiple LLMs before
  making a decision.
allowed-tools: Bash, Read, Write, Agent, Glob
user-invocable: true
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
  filePattern: "docs/council-sessions/**"
---

# Council — 5-Model Strategic Advisory

Ask the same question to five LLM seats, each locked to a thinking role, then have the
orchestrator (Claude) synthesize. Quality matters more than latency or cost (~$0.50–$1.00
per call, 60–180s wall time).

## The five seats

| Seat            | Default model               | Role                                                                 |
| --------------- | --------------------------- | -------------------------------------------------------------------- |
| Theorist        | Gemini 3 Pro (or 2.5 Pro)   | Research-grounded, framework-driven, lateral alternatives            |
| Validator       | gpt-5.5 + xhigh reasoning   | Eval methodology, defensible cases, instruction-following            |
| Provocateur     | Moonshot Kimi K2.6          | Challenges premises, surfaces uncomfortable truths                   |
| Diagnostician   | gpt-5.5 + xhigh reasoning   | Names the mechanism, cites stratified evidence, commits to action    |
| Field Engineer  | DeepSeek-v4 (R1 reasoning)  | Ready-to-paste artifacts, tabular root-cause analysis, iterative     |

The orchestrator (whichever model is running the skill) does the Blue Hat synthesis pass.
Including the orchestrator as a seat would be self-querying.

Each seat is overridable via environment variables — see "Configuration" below.

## Preparation protocol

The brief IS the work. Budget 15–30 minutes assembling it before launching any seats.

1. Research the topic. If your stack has a memory/recall layer, query it first.
2. Read the full source material. Read the article, not a summary. Read the code, not a
   description of it.
3. Pull relevant data — analytics, metrics, anything that changes the question.
4. Steel-man both sides before writing the brief, so the council isn't anchored on yours.

Write the question to `docs/council-sessions/YYYY-MM-DD-<slug>/question.md`. The file should
contain: decision required, why now, full source material, performance data, historical
context, the case for, the case against, alternatives, specific numbered questions,
constraints.

Ground rules:

- Never send a summary. Seats form opinions from primary sources.
- Always include data. No data = the session is not ready.
- Steel-man both sides to prevent anchoring bias.
- Ask specific questions, not "what do you think?".

## Execution

1. Extract the question from the argument or conversation context. If none, ask the user.
2. Create the output directory: `docs/council-sessions/YYYY-MM-DD-<slug>/`. `<slug>` is the
   first 5 words of the question, lowercase, hyphenated, max 50 chars.
3. Write the brief to `question.md` in that directory.
4. Copy the question to a temp file (`/tmp/council-question-<timestamp>.txt`) to avoid
   shell-argument-length limits.
5. Launch all five seats in parallel via the Agent tool. Each agent reads the temp file,
   invokes its model via the CLI listed in "Provider invocation" below, and writes the full
   response to the matching file.
6. Verify all five output files exist and have content (>200 chars each). Note any failures.
7. Synthesize. Read all five responses and write `synthesis.md`.
8. Present the synthesis. Delete the temp file.

## Output structure

```
docs/council-sessions/YYYY-MM-DD-<slug>/
  question.md       — the brief that was sent to every seat
  theorist.md       — Theorist response
  validator.md      — Validator response
  provocateur.md    — Provocateur response
  diagnostician.md  — Diagnostician response
  field-engineer.md — Field Engineer response
  synthesis.md      — consensus + disagreements + recommendation
```

## Synthesis template

```markdown
# Council Synthesis — <date>

## Question
<one-sentence statement of the decision>

## Consensus
- <points where 4+ seats agree>

## Disagreements
| Topic | Theorist | Validator | Provocateur | Diagnostician | Field Engineer |
| ----- | -------- | --------- | ----------- | ------------- | -------------- |
| ...   |          |           |             |               |                |

## Recommendation
<the orchestrator's synthesis based on all five inputs + own judgment>

## Seat summaries
- Theorist: <one line>
- Validator: <one line>
- Provocateur: <one line>
- Diagnostician: <one line>
- Field Engineer: <one line>
```

## Provider invocation

The skill assumes CLI access to the underlying providers. Use whichever wrapper you
prefer — Codex CLI for OpenAI, Antigravity CLI (`agy`) for Google (replaces the sunset
Gemini CLI on consumer plans as of 2026-06-18; enterprise plans may still use the
legacy `gemini` binary), curl for the OpenAI-compatible endpoints (Moonshot, DeepSeek).
Model identifiers like `gemini-3-pro` are unaffected by the CLI rename and resolve
under `agy` directly. When scripting `agy`, use `agy -p "<prompt>" </dev/null` — the
stdin redirect is mandatory or `agy` deadlocks on TTY input. Example for Moonshot:

```bash
curl -s https://api.moonshot.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $KIMI_API_KEY" \
  -d "$(jq -n --rawfile q /tmp/council-question.txt \
      '{model:"kimi-k2.6",messages:[{role:"user",content:$q}],temperature:1}')" \
  | jq -r '.choices[0].message.content' > theorist.md
```

The Agent tool should run the curl inside its sandbox and write the result via the Write
tool so the file lands in the right session directory.

## Configuration

Environment variables (all optional — defaults are picked to maximize each seat):

| Variable                   | Default                      | Purpose                              |
| -------------------------- | ---------------------------- | ------------------------------------ |
| `COUNCIL_THEORIST_MODEL`   | `gemini-3-pro` (fallback 2.5)| Theorist model                       |
| `COUNCIL_VALIDATOR_MODEL`  | `gpt-5.5`                    | Validator model                      |
| `COUNCIL_VALIDATOR_EFFORT` | `xhigh`                      | Reasoning effort: low/medium/high/xhigh |
| `COUNCIL_PROVOCATEUR_MODEL`| `kimi-k2.6`                  | Provocateur model                    |
| `COUNCIL_DIAGNOSTICIAN_MODEL` | `gpt-5.5`                 | Diagnostician model                  |
| `COUNCIL_DIAGNOSTICIAN_EFFORT`| `xhigh`                   | Reasoning effort                     |
| `COUNCIL_ENGINEER_MODEL`   | `deepseek-v4`                | Field Engineer model                 |
| `COUNCIL_ENGINEER_THINKING`| `1`                          | DeepSeek R1 reasoning toggle         |
| `KIMI_API_KEY`             | —                            | Required for Provocateur             |
| `DEEPSEEK_API_KEY`         | —                            | Required for Field Engineer          |

Codex CLI and Antigravity CLI (`agy`) auth in their usual config files (ChatGPT
subscription auth or Google subscription auth). API keys are only needed for Moonshot
and DeepSeek. `GEMINI_API_KEY` is unchanged — Google did not rename the env var.

## Collaborative mode (`--collab`)

Two rounds. R1 is the parallel single-shot pass above. After R1, the orchestrator reads all
five R1 responses and writes a per-seat R2 prompt containing the other seats' positions and
specific challenges. R2 runs in parallel like R1. The synthesis then weights R2 positions
more heavily than R1 (seats have seen each other's arguments and can update).

Use `--collab` for high-stakes decisions where the R1 disagreement is large and worth
spending another pass on.

## When to use

- Strategic decisions: architecture, pricing, positioning
- Format/design choices where the trade-off space is non-obvious
- Risk assessment before committing to a major change
- Tiebreakers between two options that look equivalent
- Diverse-perspective research questions

## When not to use

- Tactical questions with a clear right answer (a single capable model is faster)
- Anything where you wouldn't act on the answer anyway
- Pure factual lookups (use a search tool)

## Known gotchas

- **Kimi thinking ON often hurts Provocateur quality.** Locking the model into a reasoning
  trace before the first token makes it commit to the wrong framing. Default is OFF.
- **Steel-manning bias.** If you only steel-man the side you already agree with, the council
  will mirror your bias. The "case against" must be at least as strong as the "case for".
- **Empty responses.** A seat occasionally returns ~50 chars of "I cannot answer" filler.
  Check file size before synthesizing; if any seat returns <200 chars, retry that seat
  before falling back to a 4-seat synthesis with a noted absence.
- **Rate limits on the OpenAI-compatible endpoints.** Moonshot and DeepSeek throttle hard
  on parallel calls from the same IP. If both seats fail simultaneously, serialize them.

## Anti-patterns

- Sending a summary instead of the source material. The seats then synthesize your summary,
  not the underlying truth.
- "What do you think?" prompts. The seats default to bland consensus on open-ended
  prompts. Ask numbered, decision-shaped questions.
- Asking the same question every week. Council output is for decisions, not check-ins.

## Validated patterns

- The disagreement matrix in the synthesis is often more useful than the recommendation
  itself. The places the seats split signal where the real bet is.
- Pasting the entire source document, not a description of it, is the single biggest
  quality lever.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works without it.

Trigger a review when:

- The user explicitly corrects a recommendation (strongest signal — log immediately; 2–3
  corrections on the same theme → promote to body).
- A golden case that previously passed starts failing.
- A novel input category recurs across sessions.
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers (loads when it shouldn't, or fails to load when it should — usually
  means the `description:` field needs work).
- A council seat's underlying model gets a major version bump.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each learnings entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns.
- Capture = leave in the log for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
