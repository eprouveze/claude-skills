---
name: deslop
description: >
  Remove AI writing patterns from content. Use when reviewing blog posts, marketing copy,
  emails, or any customer-facing text. Checks for 22 AI-tell patterns across phrasing,
  rhythm, and authenticity. Trigger phrases — "deslop this", "clean up AI writing", "check
  for AI patterns", "remove AI tells", "content quality check", "is this sloppy".
allowed-tools: Read, Edit, Grep, Glob
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
  filePattern: "*.mdx,*.md"
  priority: 50
---

# Deslop — AI Writing Pattern Removal

Strip AI-generated writing patterns from any content. Works on existing files or inline text.

## When to Use

- After drafting any customer-facing content (blog posts, emails, landing pages)
- During content QA, manual or automated
- When reviewing existing content for quality
- Before publishing or committing content

## The 22 AI-Tell Patterns

### Phrasing Flags

| # | Pattern | Example | Fix |
|---|---------|---------|-----|
| 1 | **Em-dashes** (max 5/file) | "AI tools — especially ChatGPT — are changing..." | Rewrite with commas, colons, or split into two sentences |
| 2 | **Corrective antithesis** | "It's not about X. It's about Y." / "Not X. But Y." | State your position directly without the false setup |
| 3 | **Dramatic pivot phrases** | "But here's the thing", "Here's the catch", "Here's what most people miss" | Cut entirely or use a natural transition |
| 4 | **Soft hedging** | "It's worth noting", "It's important to remember", "Something we've observed" | Say it directly — if it's worth noting, just note it |
| 5 | **AI-tell words** | delve, landscape, realm, tapestry, leverage (verb), paradigm, robust, utilize, synergy, elevate, foster, holistic, streamline, cutting-edge, game-changer, deep dive | Replace with plain English equivalents |
| 19 | **Negation framing** | "isn't just about X", "isn't simply", "it's not X, it's Y", "goes beyond merely", "more than just a" | State the positive claim directly — don't set up what something "isn't" before saying what it is |
| 20 | **"From X to Y" coverage spans** | "from startups to enterprises", "from beginners to experts", "from simple to complex" | Either commit to a specific audience or drop the qualifier |
| 21 | **"Whether X or Y" inclusivity** | "whether you're a developer or a designer", "whether you work in X or Y" | Pick your audience or trust them to self-select |

### Rhythm Flags

| # | Pattern | Example | Fix |
|---|---------|---------|-----|
| 6 | **Staccato repetition** | "Short sentence. Another short. One more short." (3+ consecutive short sentences) | Vary sentence length — mix short punches with longer context sentences |
| 7 | **Cookie-cutter paragraphs** | Every paragraph is exactly 3 sentences, same length | Match paragraph size to idea complexity — some ideas need 1 sentence, others need 5 |
| 8 | **Gift-wrapped endings** | "In summary...", "In conclusion...", "To sum up...", "The bottom line is..." | End with insight or forward-looking statement, not a recap |
| 9 | **Throat-clearing openers** | "Let's explore", "Let's unpack", "Let's dive in", "Let's take a closer look" | Start directly with the content — cut the throat-clearing entirely |
| 10 | **List-heavy structure** | Every section is a bullet list, no prose | Use prose for narrative flow, lists only for genuinely enumerable items |

### Authenticity Flags

| # | Pattern | Example | Fix |
|---|---------|---------|-----|
| 11 | **Perfect punctuation** | No fragments, no rule-breaking, reads like a textbook | Add deliberate fragments for punch. Break rules when they sound better. |
| 12 | **Copy-paste metaphors** | Same metaphor repeated identically 3+ times | Vary the language or trust readers to remember the concept |
| 13 | **Overexplaining** | "Email — a digital form of communication — has..." | Assume reader intelligence. Skip obvious definitions. |
| 14 | **Generic examples** | "Companies like [any company] are seeing results" | Use specific, insider-level details with sharp commentary |
| 15 | **Superlative stacking** | "Powerful, revolutionary, game-changing solution" | One strong claim > three weak ones |
| 16 | **False balance** | "While X has pros and cons..." (hedging every position) | Take a position. Strong writing commits. |
| 17 | **Transition word abuse** | "Moreover", "Furthermore", "Additionally", "However" starting every paragraph | Vary transitions or cut them — strong paragraphs connect through logic, not conjunctions |
| 18 | **Emoji/exclamation inflation** | "This is amazing! 🚀 Check it out! 🎉" | One exclamation per piece max. Zero emojis unless brand requires them. |

## How to Run

### On a single file

```
/deslop content/blog-posts/my-post.mdx
```

### On all blog posts in a project

```
/deslop --all
```

### Workflow

1. **Scan**: Read the file(s)
2. **Flag**: For each pattern, grep or manually identify violations
3. **Count**: Report violation counts per pattern
4. **Fix**: Apply fixes inline — preserve meaning, change delivery
5. **Verify**: Re-scan to confirm clean

### Automated Checks (greppable)

These patterns can be detected with grep/regex:

```bash
# Em-dashes (count, max 5)
grep -c '—' "$FILE"

# Corrective antithesis
grep -iE "(It'?s not about|Not [A-Z].*\. But |Not [A-Z].*\. It'?s )" "$FILE"

# Dramatic pivots
grep -iE "(But here'?s the (thing|catch|kicker|reality)|Here'?s what (most|many|few))" "$FILE"

# Soft hedging
grep -iE "(It'?s worth (noting|mentioning|remembering)|It'?s important to (note|remember|understand)|Something (we'?ve|I'?ve) observed)" "$FILE"

# AI-tell words
grep -iE "\b(delve|landscape|realm|tapestry|leverage[sd]?|paradigm|robust|utilize[sd]?|synergy|elevate[sd]?|foster|holistic|streamline[sd]?|cutting-edge|game-?changer|deep dive)\b" "$FILE"

# Gift-wrapped endings
grep -iE "^(In (summary|conclusion)|To sum up|The bottom line|All in all|Ultimately,)" "$FILE"

# Throat-clearing
grep -iE "^(Let'?s (explore|unpack|dive|take a closer|break down|look at)|In this (article|post|guide|section))" "$FILE"

# Transition word abuse (at paragraph start)
grep -iE "^(Moreover|Furthermore|Additionally|Consequently|Nevertheless|Nonetheless)" "$FILE"

# Negation framing (#19)
grep -iE "\b(isn'?t just|isn'?t simply|not just about|goes beyond merely|more than just a)\b" "$FILE"

# "From X to Y" coverage spans (#20)
grep -iE "from (startups?|beginners?|small|large|simple|complex|novice|expert)" "$FILE"

# "Whether X or Y" inclusivity (#21)
grep -iE "whether you'?re? (a |an )?\w+" "$FILE"
```

### Manual Checks (require human judgment)

- Staccato repetition (consecutive short sentences)
- Cookie-cutter paragraphs (uniform length)
- Perfect punctuation (no fragments or rule-breaking)
- Copy-paste metaphors (same metaphor repeated)
- Overexplaining (defining obvious terms)
- Generic examples (vague company references)
- Superlative stacking (multiple weak adjectives)
- False balance (hedging every position)
- **#22 Tricolon / rule of threes** — compulsive 3-part parallel lists ("fast, reliable, and scalable" / "we researched, analyzed, and synthesized"). 2 instances = fine, 4+ = pattern flag.

## Severity Levels

| Level | Action | Patterns |
|-------|--------|----------|
| **BLOCK** | Must fix before publish | AI-tell words, em-dashes >5, throat-clearing, gift-wrapped endings |
| **WARN** | Should fix, not blocking | Corrective antithesis, dramatic pivots, soft hedging, transition abuse, negation framing (#19), coverage spans (#20), inclusivity framing (#21) |
| **NOTE** | Improve if time allows | Staccato, cookie-cutter, perfect punctuation, overexplaining, tricolon overuse (#22) |

## Integration

- **Automated QA pipelines**: Run the greppable checks as a pre-publish gate.
- **Content-creator skills**: Reference this skill in a final quality checklist.
- **Manual review**: Use the full 22-pattern checklist before publishing.
- **Existing content audit**: Run across older posts to find and fix legacy violations.

## Known gotchas

- **The grep checks are noisy on technical writing.** "Robust" is a legitimate engineering
  word; "leverage" is a legitimate lever-based metaphor. Treat hits as candidates to
  reconsider, not auto-deletes.
- **Em-dash count alone is misleading.** A long technical post can earn 8–10 em-dashes
  legitimately; a 600-word blog post should rarely have more than 3.
- **Bulk rewrites flatten voice.** Apply the fixes one pattern at a time on a draft, not
  all at once. Reviewers can spot a globally rewritten draft.

## Anti-patterns

- Treating the pattern list as a banned-words list. The patterns are *tells*, not slurs.
  The fix is rewriting the sentence, not deleting the word.
- Running deslop on the first draft. Pattern detection works best after the author has
  already done one human pass.

## Validated patterns

- The "negation framing" check (#19) catches the highest-volume tell — most AI-written
  drafts hit it within the first 100 words.
- Severity levels (BLOCK / WARN / NOTE) work better than a flat list for triage.

## Credit

Patterns adapted from Tahi's "12 Red Flags of AI Writing" (mooch.agency, Feb 2026) and
Jejomar Contawe's "The Single Most Prevalent AI Writing Tell" (Medium, Feb 2026), plus
six additional patterns observed in the wild.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The user explicitly disagrees with a fix (strongest signal — log immediately; 2–3
  corrections on the same pattern → promote to body or adjust the pattern).
- A novel AI-writing tell starts appearing across multiple drafts.
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.
- A new model generation changes the writing tells (e.g., new go-to phrases).

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns, or add a new
  pattern to the list.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
