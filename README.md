# Claude Skills

> 🇯🇵 日本語版: [README.ja.md](README.ja.md) ・ かんたんインストール手順（git不要）: [INSTALL.ja.md](INSTALL.ja.md)

A collection of practical Claude Code skills built around multi-LLM workflows,
plan/coverage checking, content quality, and domain ops. MIT licensed.

These are skills the author uses daily, cleaned up for public consumption. They are not
polished products — they are working tools with rough edges, shipped with a feedback loop
so the rough edges get filed down over time.

## New here?

A **skill** is a folder of plain-text instructions that Claude Code reads and follows.
You trigger one by typing its name with a slash — `/council`, `/deslop`, `/plan`. Some
skills also ship a small helper script.

To use any of these you need [Claude Code](https://docs.claude.com/en/docs/claude-code/overview)
installed. The prompt-only skills then work right away — no terminal, no git, no keys. A few
call an extra tool, key, or model; the [next table](#what-each-skill-needs) says which. New to
the idea of skills? See the official
[Agent Skills guide](https://docs.claude.com/en/docs/claude-code/skills).

Want to just try one? Pick a ✅ skill in the table below and follow
[the easy install](#the-easy-way-no-command-line) — those need nothing beyond Claude Code.

## What's inside

| Skill              | What it does                                                                          |
| ------------------ | ------------------------------------------------------------------------------------- |
| `battle`           | Benchmark AI model combinations on the same coding task. Solo + pair + leaderboard.   |
| `brief`            | Project-aware session briefing. Loads project-intel, decisions, deferred actions.     |
| `codex-write`      | Delegate heavy code generation to Codex CLI while Claude orchestrates and reviews.    |
| `council`          | Five-model strategic advisory with role-locked seats and a synthesis pass.            |
| `crawl`            | Tiered web fetcher → clean markdown. Direct fetch (zero-setup) + optional Cloudflare. |
| `deslop`           | Strip 22 common AI-writing tells from drafts (em-dashes, gift-wrapped endings, etc.). |
| `evaluate-plan`    | Coverage check on an implementation plan against its source requirements.             |
| `gmail-attachment` | Send Gmail with file attachments via the google-workspace MCP — the route that works. |
| `keyword-research` | Google Trends interest + related queries for SEO and content prioritization.          |
| `mode`             | Toggle single-LLM vs multi-LLM routing for skills that support delegation.            |
| `model-scan`       | Scan provider APIs and docs to keep a project's model table current.                  |
| `namecheap`        | Domain management via Namecheap's XML API (check, register, DNS, transfer, renew).    |
| `pair-session`     | AI pair programming: Claude builds, a second model advises. Three styles.             |
| `plan`             | Research-first planning: parallel sub-agents explore the codebase, then a plan doc.   |
| `salesforce-reports` | Create/clone/run/delete Salesforce Reports via the Analytics REST API + `sf` CLI.   |
| `second-opinion`   | Independent code review via Codex CLI. Review, challenge, and consult modes.          |
| `update-machine`   | Safe parallel package sweep (brew/npm/pipx/uv) with accumulated upgrade-trap guards.  |

## What each skill needs

Most need nothing beyond Claude Code. A few call another model, a key, or a Node package.

| Skill | Claude Code alone? | For the full thing |
| --- | --- | --- |
| `brief`, `deslop`, `evaluate-plan`, `mode`, `plan` | ✅ | — |
| `crawl` | ✅ basic | Node (`npx tsx`); Cloudflare keys for JS-heavy pages |
| `update-machine` | ✅ | the package managers you already use (brew/npm/pipx/uv) |
| `battle` | ◑ partial | Antigravity + Codex CLI to benchmark the full model field |
| `council` | ◑ partial | access to the other models (their CLIs or API keys) |
| `pair-session` | ◑ partial | a second-model CLI (Antigravity or Codex) |
| `codex-write`, `second-opinion` | — | Codex CLI |
| `keyword-research` | — | Node + the `google-trends-api` package |
| `model-scan` | — | provider API keys, plus Node |
| `namecheap` | — | a Namecheap API key |
| `salesforce-reports` | — | the `sf` CLI and a Salesforce org |
| `gmail-attachment` | — | the `google-workspace` MCP, authenticated to your Gmail |

✅ works as-is &middot; ◑ works, but better with extra models &middot; — needs the listed setup first

## Installation

### The easy way (no command line)

You don't need git, or even a terminal.

**Option A — let Claude Code install it.** Open Claude Code and ask:

> Install the `council` skill from https://github.com/eprouveze/claude-skills

Claude Code can fetch the files and put them in the right place for you. Swap `council` for
whichever skill you want.

**Option B — download the ZIP.**

1. Click the green **Code** button near the top of
   [this page](https://github.com/eprouveze/claude-skills), then **Download ZIP**
   (direct link: [main.zip](https://github.com/eprouveze/claude-skills/archive/refs/heads/main.zip)).
2. Unzip it.
3. Copy the folder of the skill you want — for example `skills/council` — into your skills
   folder: `~/.claude/skills/` for all projects, or `.claude/skills/` inside one project.
4. Restart Claude Code.

### With git (for developers)

**Global (all projects):**

```bash
git clone https://github.com/eprouveze/claude-skills.git ~/.claude/skills-source
# Symlink or copy individual skills into ~/.claude/skills/
ln -s ~/.claude/skills-source/skills/council ~/.claude/skills/council
```

**Per-project:**

```bash
git clone https://github.com/eprouveze/claude-skills.git
cp -r claude-skills/skills/council .claude/skills/council
```

After installation, restart Claude Code so the skill catalog refreshes.

Skills with their own scripts include a `--setup` flow:

```bash
~/.claude/skills/namecheap/scripts/nc_api.sh --setup
~/.claude/skills/model-scan/scripts/model-scan.ts --setup   # via `npx tsx`
~/.claude/skills/salesforce-reports/scripts/sfreport.sh setup   # installs sf CLI if missing
npx tsx ~/.claude/skills/crawl/scripts/crawl.ts --setup   # optional Cloudflare creds
```

## Before you run

These are real tools, not toys — a few can spend money or change things on your systems:

- `namecheap` can **register, transfer, and renew domains**, which bills your account.
- `salesforce-reports` can **delete** reports in your Salesforce org.
- `update-machine` upgrades packages installed on your machine.

Treat them like any code off the internet: skim the skill's `SKILL.md` and any script under
its `scripts/` folder before running. Every script accepts `--help`, and credential setup
writes to `~/.config/claude-skills/<skill>.env` — never into the skill source.

## Per-skill quick start

- **battle** — `/battle Write a token-bucket rate limiter middleware`. Runs every
  available model and pair. See `skills/battle/SKILL.md`.
- **brief** — `/brief`. Loads project context for the current working directory. See
  `skills/brief/SKILL.md`.
- **codex-write** — `/codex-write Refactor the checkout route to support multi-currency`.
  Delegates to Codex CLI. See `skills/codex-write/SKILL.md`.
- **council** — `/council Should we migrate from REST to GraphQL?`. Five-seat advisory
  with synthesis. See `skills/council/SKILL.md`.
- **crawl** — `npx tsx skills/crawl/scripts/crawl.ts "https://example.com"`. Direct fetch
  works with no setup; run `... --setup` (or set `CLOUDFLARE_*` env vars) to enable the
  JS-rendering tier. See `skills/crawl/SKILL.md`.
- **deslop** — `/deslop content/blog/my-post.mdx`. Scans for 22 AI-tell patterns. See
  `skills/deslop/SKILL.md`.
- **evaluate-plan** — `/evaluate-plan @prd.md`. Coverage report. See
  `skills/evaluate-plan/SKILL.md`.
- **gmail-attachment** — `/gmail-attachment Email this PDF to alice@example.com`.
  Encodes the file and sends through the `google-workspace` MCP using the only working
  route (inline base64). See `skills/gmail-attachment/SKILL.md`.
- **keyword-research** — `npm i google-trends-api`, then
  `npx tsx skills/keyword-research/scripts/keyword-research.ts --keywords "a, b, c"`. See
  `skills/keyword-research/SKILL.md`.
- **mode** — `/mode`, `/mode multi`, `/mode stats`. See `skills/mode/SKILL.md`.
- **model-scan** — `/model-scan`. Refreshes the model table. See
  `skills/model-scan/SKILL.md`.
- **namecheap** — `/namecheap check example.com,example.net`. See
  `skills/namecheap/SKILL.md`.
- **pair-session** — `/pair-session build Refactor the auth module`. See
  `skills/pair-session/SKILL.md`.
- **plan** — `/plan Add multi-currency support to checkout`. Parallel research, then a
  structured plan in `docs/plans/`. See `skills/plan/SKILL.md`.
- **salesforce-reports** — `scripts/sfreport.sh setup --org myorg`, then `... list` /
  `... clone --from <id> --name "Copy"` / `... delete <id> --yes`. Org-agnostic; optional
  GAM Global Company filter. See `skills/salesforce-reports/SKILL.md`.
- **second-opinion** — `/second-opinion review`. See `skills/second-opinion/SKILL.md`.
- **update-machine** — `/update-machine`. Surveys + safely upgrades brew/npm/pipx/uv,
  holding session-critical casks for confirmation. See `skills/update-machine/SKILL.md`.

## Conventions

- **`--help` and `--setup`** — every shipped script accepts `--help`; scripts that need
  config accept `--setup` (writes to `~/.config/claude-skills/<skill>.env` where it
  applies).
- **SPDX headers** — every script carries `# SPDX-License-Identifier: MIT`.
- **Env vars over config files** — credentials live in env vars, not in skill source.
  `--setup` flows write them to `~/.config/claude-skills/<skill>.env` so the user does not
  have to remember the names.
- **Frontmatter** — every `SKILL.md` includes `version`, `last-updated`, and
  `last-consolidated`. Bump `version` on body changes; refresh `last-consolidated` after a
  learnings consolidation pass.
- **Tone** — explain-the-why over MUST/NEVER imperatives. Specific, factual, no hype.

## How these skills self-improve

Each skill ships with a lightweight feedback loop. Adopt it or ignore it — the skills
work either way.

The pattern, in three pieces:

1. **`learnings.md` sidecar** per skill. An append-only log of observations and
   corrections, dated, one paragraph each. When a user corrects an output, that
   correction lands here.
2. **Consolidation pass** (weekly or when the log crosses ~100 bullets). Each entry gets
   one fate: **apply** (merge into the SKILL.md body under Known gotchas, Anti-patterns,
   or Validated patterns), **capture** (leave it in the log), or **dismiss** (delete).
   Bump `last-consolidated:` in frontmatter.
3. **Golden cases** for skills with crisp pass/fail criteria (`namecheap`, `model-scan`,
   `evaluate-plan`, `council`, `battle`). When a golden case that previously passed starts
   failing, that is a signal that consolidation needs to happen sooner rather than later.

Triggers to consolidate: explicit user correction (2–3 on the same theme is the loudest
signal), a novel input category recurring, the underlying model version changing, or a
breaking change in an external CLI the skill calls — including vendor renames (e.g., the
Gemini CLI → Antigravity CLI (`agy`) transition in May 2026, applied across this repo in
[v0.1.1: agy migration]).

The pattern is intentionally minimal. It does not require a runtime, a database, or any
tooling beyond text files. Edit `learnings.md` by hand; consolidate by hand; trust the
SKILL.md body as the source of truth.

## Related

- **[heartbeat](https://github.com/eprouveze/heartbeat)** — an autonomous work loop for a
  Claude Code session: it wakes itself, reads ground truth, advances one item per tick
  inside a hard envelope, and queues anything irreversible to a human. It's a separate repo
  rather than a skill here because it's a small runtime system (a tick-protocol skill plus a
  launcher, board template, durability check, and an off-machine liveness watchdog).

## Contributing

Adding a skill:

1. Create `skills/<name>/SKILL.md` with frontmatter: `name`, `description`,
   `allowed-tools`, `version`, `last-updated`, `last-consolidated`.
2. If the skill calls an external CLI or API, vendor any helper scripts under
   `skills/<name>/scripts/`. Add SPDX headers and a `--help` flag at minimum.
3. Include sections for Known gotchas, Anti-patterns, Validated patterns, and a
   Self-improvement section pointing at `learnings.md`.
4. Create `skills/<name>/learnings.md` from the template (see any existing skill).
5. If the skill has clear pass/fail criteria, add `skills/<name>/golden/` with a
   `README.md` describing the cases.

Editing an existing skill: bump `version`, update `last-updated`, log the rationale in
that skill's `learnings.md` if the change came from an observation.

## License

MIT. See [LICENSE](LICENSE). Copyright Emmanuel Prouveze.

## Credits

The self-improvement pattern is adapted from prior work by others — MindStudio's
`learnings.md` pattern, ChristopherA's bootstrap-skill gist (the rule-bloat warning),
Reflexion (verbal self-reflection), DSPy/BootstrapFewShot + MIPROv2 (gated promotion +
reserved baseline), and GEPA (natural-language critique over examples). The synthesis
above is mine; the underlying ideas are not.
