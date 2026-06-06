---
name: update-machine
description: >
  Clean up, update, and upgrade this machine's package managers — Homebrew (formulae +
  casks), npm globals, and (when present) pipx and uv tools — safely and in parallel.
  Surveys what's outdated first, runs the safe upgrades, guards against known traps (a
  tool losing its CLI entrypoint on upgrade, a GUI app's binary shadowing a same-named
  CLI), and HOLDS session-critical cask updates (the terminal running the session, the
  VPN) for explicit confirmation. Use when the user says "update packages", "upgrade the
  machine", "clean up homebrew/npm", "update everything", "package cleanup", or
  "/update-machine".
allowed-tools: Bash, Read
user-invocable: true
version: 0.1.0
last-updated: 2026-06-06
last-consolidated: 2026-06-06
metadata:
  author: Emmanuel Prouveze
---

# /update-machine — Machine Package Update & Upgrade

Updates the package managers on the current Mac. The shape is always the same:
survey → safe upgrades → trap guards → report → confirm the disruptive casks.

It targets **Homebrew** (formulae + casks), **npm** globals, and — when they're installed —
**pipx** and **uv** tools. The Python managers are optional: every step that touches them is
guarded with `command -v`, so the skill runs cleanly on a machine that only has Homebrew + npm.

## Principles

- **Survey before mutating.** Always list what's outdated first and show it.
- **Parallelize independent managers.** brew / npm / pipx+uv don't depend on each other —
  run them as concurrent background jobs.
- **Run long upgrades in the background** (`run_in_background: true`), never blocking foreground.
- **Never auto-update session-critical casks.** The terminal running this session and the
  VPN must be confirmed by the user — updating them mid-session restarts the terminal or
  drops connectivity.
- **Verify, don't assume.** After upgrades, re-check `outdated` and the known traps.

## Step 1 — Survey (parallel, read-only)

Run these concurrently and show the user the combined picture. The `command -v` guards make
the optional managers no-ops when they aren't installed:

```bash
# Homebrew
brew --version && brew outdated                       # formulae + non-greedy casks
brew outdated --greedy --cask                         # auto-update casks (held by default)

# npm globals
node --version; npm --version; npm outdated -g

# python toolchain (optional — only if installed)
python3 --version
command -v pipx >/dev/null && { pipx --version; pipx list --short; }
command -v uv   >/dev/null && { uv --version;   uv tool list; }
```

Summarize: which managers are clean, which have updates, and **flag the greedy casks
separately** — they are NOT updated without confirmation (see Step 4).

## Step 2 — Safe upgrades (parallel background jobs)

Launch these as concurrent `run_in_background: true` Bash jobs. Pass the explicit package
list to `npm update -g` (names from Step 1) — do not blind-update.

```bash
# Job A — npm globals (explicit names from the outdated list)
npm update -g <pkg1> <pkg2> ...

# Job B — pipx + uv tools (only if installed)
command -v pipx >/dev/null && pipx upgrade-all
command -v uv   >/dev/null && uv tool upgrade --all   # see Step 3 trap: may silently remove a tool

# Job C — brew formulae + cleanup (NOT --greedy)
brew update && brew upgrade && brew cleanup
```

Wait for completion via the background-task notifications (do not chain `sleep`).

## Step 3 — Trap guards (verify after upgrade)

These are accumulated, real-world failures. Each one is a check that turns a past surprise
into a permanent guard. **When an upgrade silently breaks something on your machine, add a
new guard here** (see "Self-improvement" below) — that's the whole point of the skill.

**Trap A — `uv tool upgrade` silently removes a tool that drops its CLI entrypoint.**
A package whose newer version no longer exposes a console script gets *uninstalled* by
`uv tool upgrade --all` (observed in the wild with e.g. `crewai`: "No executables are
provided... removing tool"). After the upgrade, diff `uv tool list` against Step 1. If a tool
vanished and you still want it, reinstall pinned to the last working version:

```bash
# example — substitute the tool and version that vanished
uv tool install 'crewai==0.119.0'   # restore prior working state
uv tool list                         # confirm it's back
```

**Trap B — a Homebrew cask re-links a binary that collides with a same-named CLI elsewhere
on PATH.** A GUI app installed via cask can drop a binary into `/opt/homebrew/bin/` that
shadows a CLI of the same name living in `~/.local/bin/` (or vice-versa). This was observed
with the antigravity desktop app's `agy` binary shadowing the standalone `agy` CLI. After any
update that touches a known-colliding name, confirm the right one still wins on PATH:

```bash
# example — substitute the colliding command name
which agy                  # MUST resolve to the CLI you expect (e.g. ~/.local/bin/agy)
agy --version              # confirm it's the CLI, not the GUI app's binary
```

If `which` resolves to the wrong path, the GUI binary shadowed your CLI — anything that
shells out to it will break. The fix is PATH ordering, not deletion.

## Step 4 — Greedy casks (CONFIRM, never auto-run)

`brew outdated --greedy --cask` lists auto-updating GUI apps. **Do not update these without
asking.** Classify each:

- **Session-critical — HOLD and warn:** the terminal app running this session (e.g. `warp`,
  `iterm2`, `ghostty`) and the VPN/mesh-network client (e.g. `tailscale-app`). Updating
  restarts the terminal (kills the session) or drops the network. Recommend running these
  between sessions.
- **Safe to offer:** fonts, IDEs, and other non-session apps (e.g. `font-*`, an editor).

Present the list, recommend holding the session-critical ones, and only run what the user
approves:

```bash
brew upgrade --cask <approved-cask-1> <approved-cask-2>
```

## Step 5 — Report

Show a compact table: manager · result · notable version bumps. Call out:
- Any CLI whose version bump only takes effect **next launch** — a CLI upgraded mid-session
  keeps running the old version until you restart it (the terminal/session host is the
  common case).
- Any tool restored in Step 3.
- Which casks were held back and why.

## Notes

- Install this as a **global** skill (`~/.claude/skills/update-machine/`) so it's reachable
  from any project.
- It targets the **local** machine only. If you run several machines, run the skill in a
  session on each host — don't assume one machine's state matches another (`~/.claude/skills/`
  is per-machine unless you sync it yourself).
- Standalone binaries installed outside a package manager (e.g. a CLI dropped into
  `~/.local/bin/`) are NOT caught by brew / npm / uv. Self-update them directly with whatever
  update command they ship (e.g. `<tool> update`).

## Self-improvement

The mechanics of this skill are trivial — anyone can type `brew upgrade`. **The value is the
accumulated trap-guards in Step 3.** Each guard is a tax someone already paid: the time a
`uv tool upgrade --all` silently uninstalled a working tool because its new version dropped
the console script; the hour lost when a GUI app's binary shadowed a same-named CLI and every
script that shelled out to it started failing. Those guards turn one-time pain into a
permanent, automatic check.

So treat the skill as a living checklist. **Every time an upgrade silently breaks something,
add a new guard to Step 3** before you forget how you fixed it. The pattern is always the
same:

1. **Snapshot before** — capture the relevant state pre-upgrade (`uv tool list`,
   `npm ls -g --depth=0`, `which <cmd>`, a `--version`, a working invocation).
2. **Upgrade** — run the normal Step 2 jobs.
3. **Diff after** — compare against the snapshot. What disappeared? What now resolves to a
   different path? What stopped responding to `--version`?
4. **Restore / flag** — pin-reinstall the regressed tool, fix PATH ordering, or surface the
   breakage to the user — then **write the check down as a new Trap in Step 3** so the next
   upgrade catches it automatically.

A guard added the day something breaks costs a minute. The same breakage rediscovered from
scratch six months later costs an afternoon. Pay the minute.
