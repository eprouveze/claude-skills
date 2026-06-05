---
name: codex-write
description: >
  Delegate heavy code generation to Codex CLI while Claude orchestrates, reviews, and
  surgically fixes. Use for any task involving 50+ lines of new code, boilerplate
  generation, test writing, or large refactors. Claude acts as lead engineer; Codex
  acts as developer. Multi-LLM aware — checks `.claude/llm-mode.json` before delegating
  and falls back to direct write if Codex is unavailable.
allowed-tools: Bash, Read, Edit, Write, Glob, Grep
user-invocable: true
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
---

# Codex CLI Code Delegation

You are the Lead Engineer. Codex is your Developer. Your job is to:
1. **Architect** — decide what needs to be built and how it fits the codebase
2. **Delegate** — hand Codex a precise, context-rich prompt
3. **Review** — verify the output meets project standards
4. **Fix** — surgically correct any issues with your native tools

You NEVER delegate blindly. You always understand the architecture first, then delegate the typing.

## When to Use

**Manual:** `/codex-write Refactor the checkout API route to support multi-currency`

**Good candidates for delegation:**
- New component/page creation (boilerplate-heavy)
- Test file generation (repetitive patterns)
- API route scaffolding
- Large refactors with clear before/after specs
- Migration scripts
- Data transformation utilities

**Keep in Claude (do NOT delegate):**
- Architectural decisions
- Security-sensitive code (auth, payments, API keys)
- Complex business logic requiring deep context
- Surgical fixes (<20 lines)

## Multi-LLM Mode Check

1. Read `.claude/llm-mode.json` — if `mode` is `"multi"`, proceed with Codex delegation
2. If `mode` is `"single"` or file doesn't exist, write the code yourself
3. If Codex delegation fails at any point, take over and write the code yourself

## IMMEDIATE ACTION

### Step 0: Load Project Context

Load core memory sources to include in the Codex prompt:

```bash
# Brand config (framework, conventions, terminology)
cat .claude/brand.json 2>/dev/null || echo "NO_BRAND_CONFIG"

# Failure atlas — known mistakes to avoid
cat docs/memory/failure-atlas.md 2>/dev/null || echo "NO_FAILURE_ATLAS"

# Recent decisions — architectural context
tail -80 docs/decisions/log.md 2>/dev/null || echo "NO_DECISIONS_LOG"
```

If brand.json is found, extract `framework`, `conventions`, and `terminology` fields for the prompt template.

**Failure-atlas integration:** Scan the project's failure atlas (or equivalent known-issues
doc) for entries whose trigger pattern matches the current task. If a match is found,
include the relevant prevention rule in the Codex prompt as a hard constraint.

**History-aware context (optional):** If the project has a memory/recall layer, query it for
the task's domain (a module that had past bugs, a pattern that was debated) and include the
top 2–3 results in the Codex prompt under a `## Known history` section. Skip this for
greenfield tasks with no project history.

### Step 1: Pre-Flight Checks

```bash
# 1. Check working tree is clean
DIRTY=$(git status --porcelain 2>/dev/null | head -5)
if [ -n "$DIRTY" ]; then
  echo "DIRTY_TREE"
  echo "$DIRTY"
fi

# 2. Check Codex CLI is available
codex --version 2>/dev/null || echo "CODEX_NOT_FOUND"

# 3. Record safety point
git rev-parse HEAD
```

**If dirty tree:** STOP. Tell user: "Uncommitted changes. Codex requires clean working tree. Commit first or shall I write directly?"

**If Codex not found:** Fall back to writing code yourself. No error to user.

### Step 2: Build the Prompt

A bad prompt wastes tokens. A great prompt produces production-ready code on first try.

**Prompt Structure:**

```
You are working on a [FRAMEWORK] application.

## Project Context
[PULL FROM brand.json IF AVAILABLE, OTHERWISE INFER FROM CODEBASE]

## Conventions
[PULL FROM brand.json conventions, OR READ FROM CLAUDE.md / existing code patterns]

## Terminology
[PULL FROM brand.json terminology, IF ANY]

## Known Mistakes — DO NOT REPEAT
[MATCHING FAILURE ATLAS ENTRIES: prevention rules as hard constraints]

## Known History
[TOP 2-3 /recall RESULTS IF RELEVANT, OTHERWISE OMIT THIS SECTION]

## Task
[INSERT SPECIFIC TASK DESCRIPTION]

## Files to Modify/Create
[LIST SPECIFIC FILES AND WHAT CHANGES IN EACH]

## Existing Code Reference
[PASTE RELEVANT EXISTING CODE PATTERNS]
```

**How to build the prompt:**

1. **Read the files** that will be modified or serve as patterns
2. **Extract the relevant pattern.** Find an existing similar file and include it as reference.
3. **Be hyper-specific.** Don't say "add authentication" — say exactly what pattern to follow.
4. **Include file paths.** Tell Codex exactly which files to create or modify.
5. **Include type information.** If specific types are needed, include the definitions.

### Step 3: Execute Codex

```bash
START_TIME=$(date +%s)
SAFETY_COMMIT=$(git rev-parse HEAD)

codex exec \
  -m gpt-5.5 \
  -s workspace-write \
  "[THE PROMPT]" \
  2>&1 | tee .codex_output.log

CODEX_EXIT=$?
DURATION=$(($(date +%s) - START_TIME))
```

**Critical flags:**
- `-m gpt-5.5` — flagship model, 1050K context (subscription)
- `-s workspace-write` — allows file writes
- NEVER use `-s danger-full-access` unless user explicitly requests
- NEVER pass auth flags — Codex handles its own auth

**For long prompts** (>2000 chars), use stdin:
```bash
echo "THE LONG PROMPT" | codex exec -m gpt-5.5 -s workspace-write - 2>&1 | tee .codex_output.log
```

### Step 4: Verification Pipeline (4 Layers)

**Layer 1: Exit Code** — non-zero → go to fallback

**Layer 2: Diff Review**
```bash
git diff --stat
git diff
```
Check: right files modified, reasonable scope, no unexpected files.

**Layer 3: Type Check**
```bash
npm run type-check 2>&1 | tail -20
```
Claude fixes type errors surgically with Edit tool.

**Layer 4: Claude Review** — read diff and evaluate conventions, security, terminology, complexity.

If issues found in Layer 4, fix surgically with Edit. Do NOT re-run Codex.

### Step 5: Fallback Cascade

When Codex fails or produces unusable output:

```bash
git checkout -- .
git clean -fd
```

Then write the code yourself. Tell user: "Codex delegation didn't produce usable output. Writing directly."

**Fallback triggers:**
- Exit code != 0
- Empty diff
- Diff touches >3x expected files
- >10 new type errors
- Security issues detected

### Step 6: Post-Execution

**Log the delegation** (append to `.claude/delegation.log`):
```
YYYY-MM-DDTHH:MM:SSZ | codex-write | ok | Ns | [short task description]
```

**Report to user:**
```
## Codex Delegation: [Task]

### Result: [Success / Partial (Claude fixed N issues) / Fallback (Claude wrote directly)]

### Files Changed
- path/to/file.ts — [what changed]

### Verification
- Type check: [pass / N issues fixed]
- Convention review: [pass / N issues fixed]
```

## Known gotchas

- **Codex on a dirty tree mixes changes.** Always commit or stash first. The skill's
  pre-flight check catches this, but only if you let it.
- **`workspace-write` lets Codex create files anywhere in the project.** Review the diff
  before trusting it — Codex sometimes adds adjacent files you didn't ask for.
- **Long prompts hit shell-argument limits.** Use the stdin path for anything over ~2,000
  characters.

## Anti-patterns

- Delegating without reading the surrounding code first. The prompt then describes the task
  but not the context, and Codex invents patterns that don't fit.
- Re-running Codex to fix Codex output. Take over with surgical Edits instead — Codex's
  second pass is usually worse, not better.
- Delegating security-sensitive code (auth, payments, data access). Keep those in
  Claude's hands.

## Validated patterns

- Pasting an existing file as a "do it like this" reference is the single biggest quality
  lever in the prompt.
- Layer-4 (Claude review) catches more issues than Layer-3 (type check). Don't skip it.

## Integration

- After plan approval, heavy coding steps go to `/codex-write`.
- Run a project-briefing skill before delegation to surface constraints for the prompt.
- Run a deeper review skill after the diff lands.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The user explicitly disagrees with a delegated change (strongest signal — log
  immediately; 2–3 corrections on the same theme → promote to body).
- Codex repeatedly produces unusable output for a given pattern (the prompt template is
  the problem).
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.
- The Codex CLI ships a breaking change.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
