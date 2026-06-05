---
name: battle
description: >
  Benchmark AI model combinations on the same coding task. Runs Claude, Gemini CLI,
  Codex CLI, Kimi (Moonshot API), and DeepSeek (OpenAI-compatible API) solo and in pairs,
  then scores each on tokens, cost, wall time, and output quality. Produces a leaderboard
  to inform future model selection. Use when asked to "battle", "benchmark models",
  "compare models", "which model is best", "pair programming battle", or "/battle".
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, Agent, TodoWrite
user-invocable: true
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
---

# /battle — Pair-Programming Model Battle

Run the same coding task across different AI model combinations and score each
on **time**, **tokens**, **cost**, and **quality** to find the optimal setup.

## When to Use

- User says "battle", "benchmark", "compare models", "which model combo is best"
- Before committing to a model strategy for a large project
- To validate whether multi-LLM delegation actually outperforms single-model
- Manual: `/battle <task description>`

## Contestants

### Solo Runs

| ID | Label | How It Runs |
|----|-------|-------------|
| C  | **Claude Solo** | Claude writes code directly (native tools) — Opus 4.7 |
| G  | **Gemini Solo** | Gemini CLI generates code — gemini-2.5-pro |
| X  | **Codex Solo (gpt-5.5)** | Codex CLI default — `codex exec --model gpt-5.5` |
| X5 | **Codex Solo (gpt-5.5)** | Codex CLI premium — `codex exec --model gpt-5.5` |
| K  | **Kimi Solo** | Moonshot K2.6 via API curl — needs `KIMI_API_KEY` |
| D  | **DeepSeek Solo** | DeepSeek-v4-flash via OpenAI-compatible API — needs `DEEPSEEK_API_KEY` |

### Delegation Combos (from `/codex-write` pattern)

| ID | Label | How It Runs |
|----|-------|-------------|
| CG | **Claude + Gemini** | Claude architects, Gemini generates, Claude reviews |
| CX | **Claude + Codex** | Claude architects, Codex generates, Claude reviews |
| GX | **Gemini + Codex** | Gemini generates, Codex reviews |
| CGX | **All Three** | Claude architects, Gemini + Codex generate in parallel, Claude judges |

### Pair-Session Combos (from `/pair-session` styles)

| ID | Label | How It Runs |
|----|-------|-------------|
| PS-CX | **Pair: Claude+Codex Standard** | Claude builds, Codex reviews each change (turn-by-turn) |
| PS-CG | **Pair: Claude+Gemini Standard** | Claude builds, Gemini reviews each change (turn-by-turn) |
| PP-CX | **Ping-Pong: Claude+Codex** | Codex writes test → Claude implements → swap (TDD) |
| PP-CG | **Ping-Pong: Claude+Gemini** | Gemini writes test → Claude implements → swap (TDD) |
| SS-CX | **Strong-Style: Codex leads** | Codex proposes approach → Claude implements exactly |
| SS-CG | **Strong-Style: Gemini leads** | Gemini proposes approach → Claude implements exactly |

### Quick vs Full Battle

| Mode | Flag | Contestants | Use When |
|------|------|-------------|----------|
| **Quick** | `--quick` or `-q` | Solo only: C, G, X | Fast comparison, model selection |
| **Standard** | (default) | Solo + Delegation: C, G, X, CG, CX, GX, CGX | Evaluating delegation vs solo |
| **Full** | `--full` or `-f` | All 13 contestants | Complete benchmark including pair-session styles |

Default is **standard** (7 contestants). Use `--full` to include pair-session combos
(adds ~15 min per pair-session contestant due to turn-by-turn protocol).

## IMMEDIATE ACTION

### Step 0: Parse Task

Extract the coding task from the user's input after `/battle`.

If no task provided, ask:
> What coding task should I benchmark across models? (e.g., "Write a rate limiter middleware", "Refactor checkout to support multi-currency")

The task MUST be:
- Self-contained (completable without external dependencies)
- Measurable (produces code that can be evaluated)
- Non-trivial (enough complexity to differentiate models)

### Step 1: Pre-Flight Checks

```bash
# 1. Check working tree is clean
DIRTY=$(git status --porcelain 2>/dev/null | head -5)
if [ -n "$DIRTY" ]; then
  echo "DIRTY_TREE"
fi

# 2. Check available models
GEMINI_AVAILABLE=false
if which gemini >/dev/null 2>&1; then
  GEMINI_AVAILABLE=true
fi

CODEX_AVAILABLE=false
if which codex >/dev/null 2>&1; then
  if codex --help >/dev/null 2>&1; then
    CODEX_AVAILABLE=true
  fi
fi

# 3. Create battle workspace
BATTLE_ID=$(date +%Y%m%d-%H%M%S)
BATTLE_DIR=".claude/battles/$BATTLE_ID"
mkdir -p "$BATTLE_DIR"

# 4. Create a worktree per contestant (each gets a full repo copy)
BATTLE_BRANCH_PREFIX="battle/$BATTLE_ID"
CURRENT_SHA=$(git rev-parse HEAD)

for CONTESTANT in claude gemini codex claude-gemini claude-codex gemini-codex all-three; do
  BRANCH="${BATTLE_BRANCH_PREFIX}/${CONTESTANT}"
  git branch "$BRANCH" "$CURRENT_SHA"
  git worktree add "$BATTLE_DIR/$CONTESTANT" "$BRANCH" --quiet
done

echo "BATTLE_ID=$BATTLE_ID"
echo "GEMINI=$GEMINI_AVAILABLE"
echo "CODEX=$CODEX_AVAILABLE"
echo "WORKTREES=$(ls -d $BATTLE_DIR/*/)"
```

**If dirty tree:** Stash or commit first — worktrees are created from HEAD, so
uncommitted changes won't be visible to contestants. Warn the user.

**Each contestant gets a full, isolated copy of the repo** as a git worktree.
They can create, edit, and delete any files. Changes are captured as git commits
on their battle branch (`battle/<id>/<contestant>`).

**Determine contestant lineup** based on available CLIs:

| Available | Contestants |
|-----------|-------------|
| Both CLIs | All 7: C, G, X, CG, CX, GX, CGX |
| Only Gemini | 3: C, G, CG |
| Only Codex | 3: C, X, CX |
| Neither | 1: C only (no battle possible — inform user) |

If only Claude is available, tell the user:
> No external CLIs found. Install `gemini` and/or `codex` to run battles.
> - Gemini: `npm install -g @anthropic-ai/gemini-cli` or check docs
> - Codex: `npm install -g @openai/codex`

### Step 2: Build the Battle Prompt

Create a **model-agnostic prompt** that all contestants receive identically.
Since each contestant has a full worktree, the prompt tells them to make real edits:

```
## Task
[USER'S TASK DESCRIPTION]

## Requirements
- Make all necessary edits directly in this repository
- Create new files as needed, edit existing files, write tests
- Follow the existing codebase conventions (check CLAUDE.md, package.json, existing patterns)
- Commit your work when done (single commit with descriptive message)

## Working Directory
You are in an isolated copy of the repository. Edit freely — this is your workspace.
```

**No context inlining needed** — every contestant has the full repo via their worktree.
They can read any file, grep for patterns, check existing implementations.

### Step 3: Run the Battles

Each contestant works in their own worktree (`$BATTLE_DIR/<contestant>/`).
They make real multi-file edits and commit their work.

**Run independent contestants in parallel** using subagents.

#### 3a. Claude Solo (C) — Agent in worktree

Launch an Agent with `isolation: "worktree"` or run directly in the battle worktree:

```
cd $BATTLE_DIR/claude
# Claude makes real edits using native tools (Read, Edit, Write, Bash)
# When done, commit all changes:
git add -A && git commit -m "battle: claude solo — [TASK]"
```

Measure wall-clock time from agent launch to commit.

#### 3b. Gemini Solo (G) — CLI in worktree

```bash
cd "$BATTLE_DIR/gemini"
START_G=$(date +%s%N)

gemini -p "$BATTLE_PROMPT" 2>"$BATTLE_DIR/gemini-stderr.txt"

END_G=$(date +%s%N)
TIME_G=$(( (END_G - START_G) / 1000000 ))
echo "$TIME_G" > "$BATTLE_DIR/gemini-time_ms.txt"

# Commit whatever Gemini produced
git -C "$BATTLE_DIR/gemini" add -A
git -C "$BATTLE_DIR/gemini" commit -m "battle: gemini solo — [TASK]" --allow-empty
```

#### 3c. Codex Solo (X) — CLI in worktree

```bash
cd "$BATTLE_DIR/codex"
START_X=$(date +%s%N)

codex -m gpt-5.5 --full-auto "$BATTLE_PROMPT" 2>"$BATTLE_DIR/codex-stderr.txt"

END_X=$(date +%s%N)
TIME_X=$(( (END_X - START_X) / 1000000 ))
echo "$TIME_X" > "$BATTLE_DIR/codex-time_ms.txt"

# Commit whatever Codex produced
git -C "$BATTLE_DIR/codex" add -A
git -C "$BATTLE_DIR/codex" commit -m "battle: codex solo — [TASK]" --allow-empty
```

#### 3d. Pair Combinations (CG, CX, GX)

Each pair works in a single shared worktree. The delegation pattern:

**Claude + Gemini (CG):** in `$BATTLE_DIR/claude-gemini/`
1. Claude reads the repo, architects a detailed spec
2. Gemini executes the spec in the worktree (via CLI)
3. Claude reviews, makes surgical fixes if needed
4. Commit the result

**Claude + Codex (CX):** in `$BATTLE_DIR/claude-codex/`
1. Claude architects the spec
2. Codex executes in the worktree (via `codex --full-auto`)
3. Claude reviews, fixes
4. Commit

**Gemini + Codex (GX):** in `$BATTLE_DIR/gemini-codex/`
1. Gemini generates in the worktree
2. Codex reviews and patches
3. Commit

#### 3e. All Three (CGX) — in `$BATTLE_DIR/all-three/`

1. Claude architects a detailed spec
2. Gemini + Codex each generate solutions (use separate temp branches if needed)
3. Claude merges the best parts into the all-three worktree
4. Commit the final result

#### 3f. Pair-Session Contestants (Full mode only)

These use the `/pair-session` protocol — real turn-by-turn collaboration in
the contestant's worktree. Each pair-session contestant gets its own worktree
(create additional worktrees: `battle/$BATTLE_ID/ps-cx`, etc.).

**PS-CX / PS-CG — Standard Pair:**
1. Claude proposes approach (Turn A from pair-session protocol)
2. Advisor reviews with APPROVE/CONCERNS/ALTERNATIVE (Turn B)
3. Claude addresses feedback and implements in worktree (Turn C)
4. Repeat for 2-3 iterations until advisor approves
5. Commit the final result

**PP-CX / PP-CG — Ping-Pong TDD:**
1. Claude writes a failing test in the worktree
2. Advisor suggests implementation approach
3. Claude implements minimum code to pass
4. Claude writes next test, advisor reviews
5. Continue until task complete (cap at 5 cycles)
6. Commit all tests + implementation

**SS-CX / SS-CG — Strong-Style:**
1. Send task to advisor, ask for architecture + pseudo-code
2. Claude implements exactly as proposed in the worktree
3. Advisor reviews implementation fidelity
4. Commit the final result

**Execution:** Run pair-session contestants sequentially (they're interactive).
Capture the full session transcript in `$BATTLE_DIR/<contestant>-transcript.md`.

**Token tracking for pair-sessions:** Sum all CLI calls (each turn = 1 Codex/Gemini
invocation). Record total turns and total estimated tokens across all turns.

### Step 4: Measure Metrics

For each contestant, capture metrics from their worktree's git diff:

```bash
CURRENT_SHA=$(git rev-parse HEAD)  # the common ancestor

for CONTESTANT in claude gemini codex claude-gemini claude-codex gemini-codex all-three; do
  DIR="$BATTLE_DIR/$CONTESTANT"
  if [ -d "$DIR/.git" ] || [ -f "$DIR/.git" ]; then
    # Time (captured during execution)
    TIME=$(cat "$BATTLE_DIR/${CONTESTANT}-time_ms.txt" 2>/dev/null || echo "N/A")

    # Diff stats from the worktree
    DIFF_STAT=$(git -C "$DIR" diff "$CURRENT_SHA" --stat 2>/dev/null)
    FILES_CHANGED=$(git -C "$DIR" diff "$CURRENT_SHA" --name-only 2>/dev/null | wc -l | tr -d ' ')
    LINES_ADDED=$(git -C "$DIR" diff "$CURRENT_SHA" --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
    LINES_REMOVED=$(git -C "$DIR" diff "$CURRENT_SHA" --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')

    # Save metrics
    echo "time_ms=$TIME" > "$BATTLE_DIR/${CONTESTANT}-metrics.txt"
    echo "files_changed=$FILES_CHANGED" >> "$BATTLE_DIR/${CONTESTANT}-metrics.txt"
    echo "lines_added=$LINES_ADDED" >> "$BATTLE_DIR/${CONTESTANT}-metrics.txt"
    echo "lines_removed=$LINES_REMOVED" >> "$BATTLE_DIR/${CONTESTANT}-metrics.txt"

    # Save the full diff for judging
    git -C "$DIR" diff "$CURRENT_SHA" > "$BATTLE_DIR/${CONTESTANT}-diff.patch"
    git -C "$DIR" diff "$CURRENT_SHA" --name-only > "$BATTLE_DIR/${CONTESTANT}-files.txt"
  fi
done
```

**The diff is the deliverable.** Judges evaluate the actual multi-file patch, not a text blob.
Use `$BATTLE_DIR/<contestant>-diff.patch` for anonymized judging in Step 5.

### Step 5: Quality Scoring — Multi-Model Judging Panel

**CRITICAL: Never let a model judge its own output.** Research shows LLM self-evaluation
has correlated blind spots ("grading your own homework"). Use a judging panel where
each model evaluates outputs it did NOT generate.

#### 5a. Anonymized Single-Judge Approach

Claude judges ALL outputs. The key: **anonymize everything.**

1. Strip model names — label outputs as "Output A", "Output B", "Output C", etc.
2. Randomize order — don't always present Claude's output first
3. Same judge = consistent scoring rubric across all contestants
4. Add one-line bias disclaimer in report: *"All outputs scored by Claude (anonymized). Correlated blind spots possible."*

**Why this works:** Claude is stateless — it has no memory of having generated
any particular output. With anonymized labels, there's no way to self-favor.
The `/evaluate-plan` checklist further minimizes subjectivity (binary: requirement
covered or not).

**Optional cross-validation:** If Gemini/Codex CLIs are available, run them as
secondary judges on the same anonymized outputs. Flag disagreements in the report.

#### 5b. Pairwise Comparison (preferred over point-wise scoring)

Research shows pairwise comparison aligns with human judgment at 85% (vs ~70% for
absolute scoring). Instead of scoring each output independently:

```
Compare Output A vs Output B for the task: [TASK]

Which output is better? Consider:
1. Correctness — does it work? Logic errors? Edge cases?
2. Completeness — all requirements met?
3. Code quality — clean, idiomatic, readable?
4. Error handling — graceful failures? Validation?
5. Performance — efficient? No obvious bottlenecks?
6. Security — no injection vectors? Safe defaults?

Respond with:
WINNER: A or B or TIE
CONFIDENCE: high/medium/low
REASONING: <1-2 sentences per dimension>
```

Run all pairwise matchups. Convert to Elo-style ranking.

#### 5c. Point-Wise Scoring (fallback / supplement)

When pairwise isn't feasible (too many contestants), use point-wise with
the non-generating model as judge. Score on 7 dimensions (1-10):

| Dimension | What to Evaluate |
|-----------|-----------------|
| **Correctness** | Does the code work? Logic errors? Edge cases handled? |
| **Completeness** | Does it fulfill all requirements? Missing pieces? |
| **Code Quality** | Clean, readable, idiomatic? Good naming? |
| **Error Handling** | Graceful failures? Input validation? |
| **Performance** | Efficient algorithms? No obvious bottlenecks? |
| **Security** | No injection vectors? Safe defaults? |
| **First-Attempt Pass** | Did it work without iteration? (binary: 10 or 0) |

**Scoring rules:**
- Judge receives ANONYMIZED output (labeled "Output A", "Output B", etc.)
- Be strict — don't inflate scores
- Deduct for: syntax errors (-3), missing requirements (-2 per), poor naming (-1), no error handling (-2)
- Bonus for: elegant solutions (+1), beyond-requirements quality (+1)

#### 5d. Echo Chamber Detection

**Watch for rapid agreement between models.** If two models produce nearly identical
output, flag it — this may indicate data contamination or convergent training, not
genuine quality.

```
ECHO CHAMBER WARNING: Contestants [X] and [Y] produced >90% similar output.
Scores may be inflated. Consider running with a different task.
```

Track disagreement rate across judging rounds. Declining disagreement correlates
with declining quality (sycophancy effect).

#### 5e. Integrate with `/evaluate-plan` for Requirements Coverage

Use the `/evaluate-plan` skill to objectively measure how well each contestant's
output fulfills the original task requirements. This replaces subjective quality
judgment with a structured coverage score.

**How it works for battles:**

1. The battle task description IS the source document (Phase 1 of evaluate-plan)
2. Extract every discrete requirement from the task into a checklist (Phase 2)
3. For each contestant's output, evaluate coverage:
   - ✅ Covered: requirement explicitly implemented
   - 🟡 Partial: mentioned but incomplete
   - ❌ Missing: not addressed at all
   - ⚠️ Misinterpreted: implemented but doesn't match intent
4. **Coverage Score** = `(Covered + 0.5 * Partial) / Total * 100`

This gives each contestant an objective **Requirements Coverage %** that feeds
directly into the Efficiency Score calculation as the Quality component.

**Why this is better than subjective 1-10 scoring:**
- Same rubric applied identically to all contestants
- Binary checklist items are harder to bias than holistic scores
- Coverage gaps are visible and auditable
- Aligns with research showing coverage-first evaluation recovers 20-40% of missed requirements

#### 5f. Statistical Validity

**Single runs are noise.** For reliable results:
- Run each configuration **3+ times** on the same task
- Report **mean and variance** (not just best score)
- Differences below **3 percentage points** are infrastructure noise (per Anthropic's research)
- Document token budgets, time limits, and tool access for reproducibility

### Step 6: Cost Estimation

| Model | Cost Basis |
|-------|-----------|
| **Claude** | API token pricing (input + output tokens) |
| **Gemini** | Free tier / API pricing |
| **Codex (gpt-5.5)** | ChatGPT Business subscription (effectively $0 marginal) |

For combinations, sum the costs of each model used.

Estimate tokens from character count:
- Input tokens: length of prompt / 4
- Output tokens: length of output / 4
- Claude Opus: ~$15/M input, ~$75/M output
- Gemini Pro: ~$1.25/M input, ~$5/M output
- GPT-5.4 via subscription: $0 marginal (flat monthly fee)

### Step 7: Generate Battle Report

```markdown
## Battle Report — [TASK DESCRIPTION]

**Battle ID:** [BATTLE_ID]
**Date:** [DATE]
**Models Available:** Claude + Gemini + Codex (or subset)

---

### Leaderboard

| Rank | Contestant | Quality | Time | Est. Cost | Efficiency Score |
|------|-----------|---------|------|-----------|-----------------|
| 1    | [BEST]    | 85%     | 12s  | $0.02     | 94              |
| 2    | ...       | 80%     | 8s   | $0.00     | 88              |
| ...  | ...       | ...     | ...  | ...       | ...             |

**Primary metric: Cost-Per-Correct-Solution (CPCS)**
= Total cost / (Quality% / 100). Lower is better.
A $0.05 run at 90% quality (CPCS = $0.056) beats a $0.02 run at 30% quality (CPCS = $0.067).

**Efficiency Score** = (Quality% × 0.5) + (Speed_normalized × 0.15) + (Cost_normalized × 0.15) + (First_attempt_pass × 0.2)

Weights: Quality (50%), first-attempt pass rate (20%), speed (15%), cost (15%).
First-attempt correctness matters because failed attempts double token spend.

---

### Detailed Scores

#### Claude Solo
- **Quality:** 45/60 (75%) — Correctness: 8, Completeness: 9, Quality: 7, Errors: 6, Perf: 8, Security: 7
- **Time:** 15,200ms
- **Est. Cost:** $0.03
- **Notes:** [Strengths and weaknesses observed]

#### Gemini Solo
...

#### Codex Solo
...

#### Claude + Gemini
...

#### Claude + Codex
...

#### All Three
...

---

### Head-to-Head Comparison

| Dimension | Claude | Gemini | Codex | C+G | C+X | CGX |
|-----------|--------|--------|-------|-----|-----|-----|
| Correctness | 8 | 7 | 8 | 9 | 9 | 9 |
| Completeness | 9 | 7 | 8 | 9 | 9 | 10 |
| Quality | 7 | 8 | 6 | 8 | 7 | 8 |
| Error Handling | 6 | 5 | 7 | 7 | 8 | 8 |
| Performance | 8 | 7 | 7 | 8 | 8 | 8 |
| Security | 7 | 6 | 7 | 8 | 8 | 8 |
| **Total** | **45** | **40** | **43** | **49** | **49** | **51** |

---

### Key Insights

1. **Best overall:** [Winner] — [Why]
2. **Best quality/cost ratio:** [Contestant] — [Why]
3. **Fastest:** [Contestant] — [Time]
4. **Cheapest quality:** [Contestant] — [Cost at acceptable quality]
5. **Diminishing returns:** [Whether adding more models helps significantly]

---

### Recommendation

For **this type of task** ([task category]):
- **Best single model:** [Model] — use when speed matters
- **Best pair:** [Pair] — use when quality matters
- **Skip:** [Combo] — overhead not worth the quality gain

### Raw Data

Battle directory: `$BATTLE_DIR`
```

### Step 8: Save Battle History

Append to `.claude/battle-history.jsonl`:

```bash
echo '{"id":"'$BATTLE_ID'","date":"'$(date -Iseconds)'","task":"[TASK]","winner":"[WINNER]","scores":{"claude":45,"gemini":40,"codex":43,"claude-gemini":49,"claude-codex":49,"all-three":51},"recommendation":"[REC]"}' >> .claude/battle-history.jsonl
```

This accumulates over time to build a model performance profile across task types.

### Step 9: Update Model Strategy (Optional)

If the user has run 3+ battles, analyze `battle-history.jsonl` to produce
aggregate recommendations:

```markdown
## Aggregate Model Strategy (N battles)

| Task Type | Recommended Combo | Avg Quality | Avg Cost |
|-----------|-------------------|-------------|----------|
| Boilerplate | Codex Solo | 78% | $0.00 |
| Complex Logic | Claude Solo | 85% | $0.04 |
| Refactoring | Claude + Codex | 88% | $0.02 |
| Tests | Gemini Solo | 80% | $0.00 |
```

### Step 10: Apply Winner (Optional)

After the report, ask the user:

> Winner is **[contestant]** with [quality]% quality. Apply their changes to main? (Y/n)

If yes — **merge the winner's worktree branch**:
```bash
WINNER_BRANCH="battle/$BATTLE_ID/<winner>"
git merge "$WINNER_BRANCH" --no-edit
```

If no, the worktrees and branches remain for future reference.

### Step 11: Cleanup

After the battle (whether winner is applied or not):

```bash
# Remove all worktrees
for CONTESTANT in claude gemini codex claude-gemini claude-codex gemini-codex all-three; do
  git worktree remove "$BATTLE_DIR/$CONTESTANT" --force 2>/dev/null
done

# Delete battle branches (keep winner's if merged)
for CONTESTANT in claude gemini codex claude-gemini claude-codex gemini-codex all-three; do
  BRANCH="battle/$BATTLE_ID/$CONTESTANT"
  if [ "$CONTESTANT" != "$WINNER" ]; then
    git branch -D "$BRANCH" 2>/dev/null
  fi
done

# Keep diffs and metrics in $BATTLE_DIR for the historical record
# The .patch files, metrics, and transcripts persist even after worktree removal
```

**Ask before cleanup.** Some users may want to inspect loser worktrees before removal.
Offer: "Clean up battle worktrees? (Y/n) — diffs and metrics are preserved either way."

## Fairness Rules

1. **Identical prompts.** Every contestant gets the exact same prompt text.
2. **No warm-up advantage.** Claude Solo runs AFTER generating the prompt (not while building it).
3. **Blind scoring.** Evaluate code quality without bias toward any model.
4. **Honest failures.** If a model fails or times out, record it — don't retry to give it a second chance.
5. **No cherry-picking.** Run ALL available contestants, not just the ones you expect to win.

## Anti-Patterns

- **Biased judging.** Claude is the judge — acknowledge this bias in the report. Note: "Claude scored its own output; take with appropriate skepticism."
- **Skipping slow models.** If a model is slow, that's a data point, not a reason to skip.
- **Over-optimizing prompts for one model.** The prompt must be model-agnostic.
- **Comparing apples to oranges.** All contestants must attempt the same task scope.
- **Running battles on trivial tasks.** "Hello world" won't differentiate models. Tasks need complexity.
- **Ignoring cost.** A 2% quality improvement at 10x the cost isn't worth it.

## Integration Points

- **With `/pair-session`:** PS/PP/SS contestants use pair-session protocol directly (standard, ping-pong, strong-style)
- **With `/codex-write`:** CX combo uses the same delegation pattern
- **With `/review`:** Quality scoring uses similar multi-perspective analysis
- **With `/second-opinion`:** Codex invocation follows the same CLI patterns
- **With `/brief`:** Run before battle to load project context for the prompt
- **With `.claude/battle-history.jsonl`:** Accumulates data for strategy decisions

## Error Handling

| Error | Action |
|-------|--------|
| Gemini CLI unavailable | Skip G, CG, GX, CGX contestants. Note in report. |
| Codex CLI unavailable | Skip X, CX, GX, CGX contestants. Note in report. |
| Model timeout (>300s) | Record as DNF. Score: 0. Time: 300000ms. |
| Empty diff (no changes) | Score: 0 across all dimensions. Note in report. |
| Syntax errors in output | Don't fix. Score correctness lower. |
| Worktree creation fails | Fall back to `git stash` + branch checkout pattern |
| Worktree cleanup fails | `git worktree prune` to clean stale entries |

## Cost Notes

- **Claude:** Metered per token via API. Opus ~$15/$75 per M tokens in/out.
- **Gemini:** Free tier generous. Pro pricing ~$1.25/$5 per M tokens.
- **Codex:** ChatGPT Business subscription = $0 marginal cost per battle.
- **Pair combos:** Sum of individual model costs.
- Running all 7 contestants on a medium task costs roughly $0.10–0.30 total.

## Known gotchas

- **Claude judging Claude's output is biased.** The skill flags this in the report. For
  battles where Claude's score is the decision driver, run the judging step with a
  different model.
- **First-run bias on cached models.** Some CLIs return faster on the second invocation
  of the same prompt. Randomize contestant order across runs.
- **`git worktree` can leak across battles** if a run fails mid-way. `git worktree prune`
  every few battles.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The leaderboard winner conflicts with hands-on experience (the scoring rubric needs work).
- A new model joins the matrix (add a contestant row, refresh the pricing notes).
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.
- A CLI vendor ships a breaking change.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns, or adjust the
  scoring rubric.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
