---
name: update-machine
description: Update and clean package managers across macOS (Homebrew, npm globals, pipx, uv) and Linux (APT, npm globals, pipx, uv), locally or across the fleet via SSH. Use on 'update packages', 'upgrade the machine', 'clean up homebrew/npm', 'update everything', 'package cleanup'.
allowed-tools: Bash, Read
user-invocable: true
version: 0.7.0
last-updated: 2026-09-20
last-consolidated: 2026-06-13
metadata:
  author: Emmanuel Prouveze
---

# /update-machine — Machine Package Update & Upgrade

Updates package managers on macOS (Homebrew, npm globals, pipx, uv) or Linux (APT, npm globals, pipx, uv), either locally or dispatched across the fleet via SSH. The shape is always the same:
survey → safe upgrades → trap guards → report → confirm disruptive casks / reboots.

On **macOS**, it targets **Homebrew** (formulae + casks), **npm** globals, and optional **pipx** / **uv** tools.
On **Linux** (Debian/Ubuntu), it targets **APT** (`apt-get upgrade`), **npm** globals, and optional **pipx** / **uv** tools.
Every step that touches optional managers is guarded with `command -v`.

## Principles

- **Survey before mutating.** Always list what's outdated first and show it.
- **Parallelize independent managers.** brew / npm / pipx+uv don't depend on each other —
  run them as concurrent background jobs.
- **Run long upgrades in the background** (`run_in_background: true`), never blocking foreground.
- **Never auto-update session-critical casks.** The terminal running this session and the
  VPN must be confirmed by the user — updating them mid-session restarts the terminal or
  drops connectivity.
- **Verify, don't assume.** After upgrades, re-check `outdated` and the known traps.
- **Check headroom before downloading gigabytes.** A full disk doesn't fail loudly — it
  *corrupts* installs mid-write (see Step 0). Never start upgrades on a near-full volume.

## Step 0 — Preflight: disk space (gate, do this first)

`brew upgrade` and `npm update -g` download and unpack to the boot volume. On a near-full
disk they fail with **ENOSPC partway through a write**, leaving a half-installed package
behind a staging name (observed in the wild: an interrupted `@openai/codex` install left a
broken `.codex-2dE5FEfu` symlink in the npm global bin, so `codex` resolved to nothing). A
full disk is the single most damaging precondition for this skill — gate on it.

```bash
df -h /                                   # human-readable; eyeball the Capacity column
df -P / | awk 'NR==2 {print "used "$5" — avail "$4}'
```

- **< ~5 GB free (or ≥ 95% used): STOP.** Do not run upgrades. Surface the top consumers and
  recommend reclaiming space first (caches are the usual culprit — Claude `vm_bundles`,
  idle CI runner `_work`, browser caches, puppeteer/Chromium downloads):

  ```bash
  du -sh ~/Library/Caches/* 2>/dev/null | sort -rh | head -10
  brew cleanup -s            # reclaim old formula/cask downloads (safe, frees the brew cache)
  npm cache verify           # prune a corrupted/oversized npm cache
  ```

  Re-check `df -h /` and only proceed once there's comfortable headroom.
- **≥ ~10 GB free: proceed** to Step 1.

> This volume may be APFS with `Dev` symlinked to an external disk — `df -h /` reports the
> **boot** volume, which is what brew/npm write to. Don't be reassured by free space on the
> external.

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

> **Tap-trust noise (Homebrew 6.0+).** Brew now prints `Warning: The following taps are not
> trusted` for third-party taps and threatens to "ignore" their formulae. In practice it still
> **upgrades already-installed bottles** from those taps — the trust gate only blocks
> *discovering new* formulae (verified 2026-06-13: `supabase/tap` + `cloudflare/cloudflare`
> upgraded cleanly despite the warning; nothing was held back). So during an upgrade the
> warning is alarming clutter, not a silent skip — don't panic when you see it. Silence it once
> for taps you recognize, rather than blanket-disabling the check:
> ```bash
> brew tap                                                              # list taps; eyeball them
> brew trust cloudflare/cloudflare oven-sh/bun stripe/stripe-cli supabase/tap   # trust known-good org taps
> ```
> Do **not** set `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` — that kills the check globally and brew
> warns it's being removed anyway.

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

### Parallelize further — the read-only probes belong HERE, not after

The three jobs above are not the only concurrency available. **While they run, fire the
read-only Step 3 probes concurrently** — they touch nothing the upgrades write, and running
them up front means you often diagnose the failure before the job that hits it reports:

- the Caskroom orphan/drift survey (Traps D/E/J),
- the puppeteer-husk scan (Step 0b),
- the `command -v` PATH-resolution baseline (Trap B/C) — capture this *before* the upgrade so
  the after-diff has something to compare against.

Ratified by Emmanuel 2026-09-11 during a live run, where the pre-scan had already identified
the exact husk directory that the npm job then failed on — the fix was known the moment the
error arrived.

**What cannot be parallelized:** Homebrew takes a global lock, so two `brew` processes block
each other — formulae and casks never overlap, and `brew update` must precede `brew upgrade`.
Only `brew cleanup` is separable from that chain.

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

**Trap C — an interrupted npm global install leaves a broken/staging symlink.** If a
`npm update -g` was killed mid-write (ENOSPC from a full disk is the classic cause — see
Step 0), the global bin can end up with a dangling link or a temp staging name (observed:
`.codex-2dE5FEfu` instead of `codex`). The package looks "installed" to `npm ls -g` but the
command resolves to nothing. After the npm job, confirm each updated CLI actually runs:

```bash
# The PATH line is NOT optional — see the warning below it.
export PATH="/opt/homebrew/bin:$(npm prefix -g)/bin:$PATH"
npm ls -g --depth=0                       # should list real names, no .<pkg>-XXXXXX staging entries
ls -la "$(npm prefix -g)/bin" | grep -iE '\.[a-z-]+-[A-Za-z0-9]{6,}$'   # flag staging-name leftovers
for c in codex claude vercel; do command -v "$c" >/dev/null && "$c" --version || echo "MISSING: $c"; done
```

**The check's own harness is a false-positive generator — get these two things right or it
lies to you** (both burned a real run on 2026-08-07, reporting `codex` MISSING on the M4 when
it was installed, working, and had just been upgraded to 0.147.0):

1. **PATH.** npm globals live in `$(npm prefix -g)/bin` (here: `~/.npm-global/bin`), which a
   non-interactive `ssh host '...'` does NOT inherit. Running the loop with only
   `/opt/homebrew/bin` on PATH reports every npm-installed CLI as MISSING. Export the PATH
   line above first, and remember `ssh host 'bash -lc "..."'` is not enough on its own —
   `npm` itself may be off PATH before you can call `npm prefix -g`, so hardcode the known
   prefix in remote one-liners.
2. **Version flags differ.** `ffmpeg` takes `-version`, not `--version`, and prints nothing
   for the latter — which reads as a broken binary. Before concluding a tool is broken,
   confirm you invoked it the way that tool expects.

A false MISSING is worse than no check: it looks like evidence, and it sends you repairing
something that was never broken. Verify the harness before you believe the harness.

If a CLI is genuinely missing or points at a staging name, reinstall it explicitly
(`npm install -g <pkg>@latest`) — the staging leftover is safe to remove first.

**Trap D — a stale staged copy in the Caskroom wastes GBs *and* blocks the upgrade.** Brew
keeps the staged `.app` under `/opt/homebrew/Caskroom/<cask>/<version>/`. When a cask upgrade
dies partway, or when an app self-updates outside brew, the old staged copy is orphaned: it is
never cleaned by `brew cleanup`, it is invisible to every disk survey that looks at `~`, and
its presence makes the next upgrade fail with a confusing message. Observed 2026-08-07:
`google-chrome` held **1.34 GB** of Chrome 148 while the real app had self-updated to 151, and
the upgrade failed on it. Check it on every run, especially when disk is tight:

```bash
du -sm /opt/homebrew/Caskroom/* 2>/dev/null | sort -rn | head -10   # orphaned staged apps
brew list --cask --versions <cask>                                   # what brew THINKS is installed
defaults read "/Applications/<App>.app/Contents/Info.plist" CFBundleShortVersionString  # what IS installed
```

If the real app's version is **ahead of** brew's record, the app self-updates itself (Chrome,
some Electron apps) and brew is not the update channel. Removing the orphaned staged copy
reclaims the space. Know the trade-off before you do: without the staged copy,
`brew uninstall --cask` can no longer remove that app cleanly. For a self-updating,
one-command-reinstallable app that is usually worth GBs; decide, don't default.

**Trap E — a failed cask upgrade needs triage, not a retry.** The two messages mean different
things and have different fixes. Re-running the upgrade fixes neither:

| Message | Meaning | Fix |
|---|---|---|
| `It seems there is already an App at '.../Caskroom/<cask>/<old-version>/X.app'` | orphaned staged copy from a dead run or a self-update (Trap D) | remove the stale staged dir, then upgrade |
| `It seems the App source '/Applications/X.app' is not there` | the app was deleted or moved **outside** brew, so brew tracks a ghost | reconcile: either reinstall the cask, or `brew uninstall --cask X --force` to drop the dangling record |

**Before dropping a ghost record, check whether a project actually needs the app.** Observed
2026-08-07: `libreoffice` looked like dead weight and its record was removed, but
`ai-deck-translator/worker/preview.py` shells out to `soffice --headless --convert-to png` to
render the watermarked preview. Grep the fleet for the binary name (not the app name) before
concluding it is unused, and include working dirs outside `~/Dev`:

```bash
grep -rlniE "soffice|<binary>" ~/Dev ~/Documents/Dev --include="*.{ts,js,py,sh,json,yml}" 2>/dev/null | grep -v node_modules
```

**Step 0b — post-ENOSPC forensics (run whenever the disk was recently near-full).** A full
disk does not only fail the run in progress; it leaves **corrupt husks from earlier runs** that
persist, never self-heal, and error on every later install. They are recognisable by being
implausibly small for what they claim to be. Observed 2026-08-07, after the volume had been at
2 GB free: two puppeteer browser dirs of **1 MB each with no working executable**, which failed
`npm update -g` for `resume-cli` on a run where the disk was no longer even the problem.

```bash
# a "browser" that is 1 MB is a husk, not a browser
for d in ~/.cache/puppeteer/*/*; do
  printf "%s MB %s executables  %s\n" "$(du -sm "$d" | cut -f1)" "$(find "$d" -type f -perm -u+x | wc -l)" "$d"
done
```

Delete husks so the tool re-downloads on demand. Then re-run the manager that failed — its
error was a symptom of the old ENOSPC, not of anything wrong today.

**Trap G — `npm update -g` is ONE transaction: a single package's postinstall failure
silently rolls back every other package.** Observed 2026-09-11 (MacBook Air): seven packages
were passed to `npm update -g`; `resume-cli`'s bundled puppeteer postinstall failed on an
ENOSPC husk (Step 0b), and npm rolled the whole tree back — `@openai/codex`, `vercel`,
`wrangler`, `npm` itself, all left at their old versions. **The command still exited 0** and
the pipeline printed a plausible-looking upgrade log, so the run reads as a success. Never
report an npm upgrade from the job's exit code. Diff the actual tree:

```bash
export PATH="/opt/homebrew/bin:$(npm prefix -g)/bin:$PATH"
npm ls -g --depth=0          # compare against the Step 1 snapshot — versions must have MOVED
```

If versions are unchanged, scroll the log for `npm error` above the summary line, fix the
root cause (usually a husk or a native-build failure in ONE package), and re-run the whole
list. Corollary: when one package is chronically fragile, upgrade it in its own job so it
cannot take the other six down with it.

**Trap H — a root-owned cask displaces your live app BEFORE it discovers it needs sudo.**
Apps whose own updater installs privileged (Chrome via Keystone is the canonical case) end up
`root:wheel` in `/Applications`. `brew upgrade` moves the existing app to the Caskroom backup
path *first*, and only then runs its write test — so when sudo cannot prompt (any
non-interactive session, this skill included) the upgrade aborts with the app already moved:

```
==> Backing up App 'Google Chrome.app' to '/opt/homebrew/Caskroom/google-chrome/<old>/'
==> Removing App '/Applications/Google Chrome.app'
Error: ... `/usr/bin/sudo -E -- touch ...` exited with 1.
sudo: a terminal is required to read the password
```

Brew does restore it, but **verify rather than assume** — and never leave this unchecked:

```bash
ls -d "/Applications/<App>.app" || echo "DISPLACED — recover from Caskroom backup"
"/Applications/<App>.app/Contents/MacOS/<App>" --version    # it must actually launch
sudo -n true 2>/dev/null && echo "sudo OK" || echo "sudo NEEDS password — cannot fix here"
```

When sudo needs a password, **do not attempt the cask upgrade at all** — surface it and have
Emmanuel run `! brew reinstall --cask <cask>` in the session, where sudo can prompt. Check the
real on-disk version first: a self-updater is usually already current (Trap J), so this is
metadata re-sync, not a genuine update, and it is not worth risking the displacement.

**Trap I — pipx/uv tools break when their underlying `python@3.x` formula moves.** Brew
upgrading `python@3.12` (etc.) can leave pipx/uv venvs pointing at a python that brew
relocated or unlinked, so the tool's shim fails with a dyld/`No such file` error even though
`uv tool list` still shows it. After a python formula bump, re-point the venvs:

```bash
command -v pipx >/dev/null && pipx reinstall-all     # rebuilds venvs against current python
command -v uv   >/dev/null && uv tool upgrade --all --reinstall   # forces venv rebuild
```

**Trap J — a self-updating cask drifts out of sync and blocks its own brew upgrade.** Apps
that update themselves (Chrome is the canonical case; also many Electron apps) bump their
on-disk version independently of Homebrew. Brew's Caskroom metadata goes stale, and the next
`brew upgrade` of that cask fails with `It seems there is already an App at '.../<old-ver>/<App>.app'`
— the app dir exists (and the app is often *running*). The app itself is current and fine;
brew's bookkeeping is wrong, and the cask shows **perpetually "outdated"**, failing the same
way every run (observed 2026-06-13: Chrome self-updated to 149.x, brew still recorded 148.x and
errored). Detect by comparing the real version against brew's record:

```bash
# a cask that STAYS in `brew outdated` after a clean-looking run → suspect self-update drift
defaults read "/Applications/Google Chrome.app/Contents/Info.plist" CFBundleShortVersionString  # real version on disk
ls /opt/homebrew/Caskroom/google-chrome/                                                         # what brew thinks
```

If the on-disk version is ≥ brew's record, the app already updated itself — only brew's
metadata needs re-syncing. Re-adopt it **when the app is closed** (`reinstall` replaces a
running app, which is disruptive — treat it like the session-critical casks in Step 4 and
confirm/defer rather than doing it unattended):

```bash
brew reinstall --cask google-chrome   # re-syncs brew metadata to the self-updated app; app must be closed
```

The unattended cron variant should **not** fight self-updaters: either skip them or rely on
`HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS=1` (brew's default already skips most) and let the app
keep itself current. Flag the drift in the report; don't force-reinstall a running app.

**Trap K (Linux) — Pending reboot / kernel upgrade (`/var/run/reboot-required`).**
An APT upgrade on Debian/Ubuntu often installs a new kernel, systemd, or libc that triggers a
reboot requirement. On headless servers, jump hosts (like `imac-node`), or VPS nodes (like `worker-h`),
**NEVER reboot automatically**. Check `/var/run/reboot-required` after upgrades:
```bash
if [ -f /var/run/reboot-required ]; then
  echo "REBOOT REQUIRED: $(cat /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' ')"
fi
```
Flag this in the final report for planned maintenance.

**Trap L (Linux) — Daemon and tunnel continuity.**
Linux nodes frequently host production tunnels (`cloudflared`), docker containers, or watchdog
crons (`fleet-watchdogs`). Package upgrades (e.g. openssh, glibc, network stack) must not disrupt
active daemons:
```bash
for s in cloudflared docker tailscaled; do
  systemctl is-active "$s" 2>/dev/null && echo "$s: ACTIVE" || true
done
```
Verify active daemons still run after package installation.

**Trap M (Remote Fleet Execution) — Non-interactive SSH PATH starvation.**
A non-interactive SSH session (`ssh host '...'`) does not source `.zprofile` or `.bash_profile`.
Tools installed in `~/.npm-global/bin`, `~/.local/bin`, or `/opt/homebrew/bin` will appear missing
unless explicitly added to PATH. Every remote execution script or one-liner MUST start with:
```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
```

## Step 3.5 — Auth-gated & self-hosting CLIs (next-launch, never force-restart)

Some CLIs are upgraded by the npm/brew jobs above but must NOT be treated as "live" the
instant they bump:

- **The Claude Code CLI** (`@anthropic-ai/claude-code`) that may be *running this very
  session*. A mid-session upgrade does NOT change the running binary — it takes effect on the
  **next** `claude` launch. Report the new version, but never kill the session to apply it.
- **Auth-token CLIs** (`codex`, `vercel`, `gh`, cloud CLIs). The upgrade is mechanical, but do
  not run any `login`/auth flow as part of an unattended update — surface "re-auth may be
  needed" instead of attempting it.

```bash
claude --version 2>/dev/null              # confirm the bump landed; old version keeps running until relaunch
```

> The unattended cron variant of this skill (`weekly-machine-update.sh`) deliberately skips
> the Claude CLI and anything auth-gated for exactly this reason. The interactive skill may
> upgrade them but reports them as **next-launch**.

## Step 3.6 — Capability-surface probe (MANDATORY after any CLI upgrade)

A version bump is not the signal you care about — a **capability surface** change is. Steps
3 and 3.5 confirm a CLI still *exists* and reports a new `--version`. Neither notices that the
new version **gained or lost a flag or a subcommand**. That gap has already cost real money.

> **The case this step exists for.** The memory `agy-no-noninteractive-entry`, written against
> `agy` v1.0.1 in May 2026, asserted agy had **no headless `-p`** and **no `--model` flag**.
> Both became false in v1.1.x. The memory was never re-tested for **64 days**, and because it
> asserted the capability was absent, it vetoed reaching for the paid Google AI subscription —
> so a research harness fell back to a metered `GEMINI_API_KEY` and burned it into 429 quota
> errors. The memory's own last line said "re-test after each agy update": a note addressed to
> a human who never arrived. This step is that human, mechanised.
> (Verified 2026-07-26 on M4: `agy 1.1.7` advertises `-p`, `--print`, `--prompt`, `--model`,
> `--effort` and a `models` subcommand.)

Run the probe **after** Step 2/3 complete, for every managed CLI:

```bash
~/.claude/scripts/cli-capability-probe.py            # probe all, diff vs last snapshot
~/.claude/scripts/cli-capability-probe.py --cli agy  # one CLI
~/.claude/scripts/cli-capability-probe.py --json     # machine-readable (cron/heartbeat)
```

It captures, per CLI (`agy`, `claude`, `codex`, `vercel`, `supabase`, `gh`): resolved PATH,
`--version`, and the normalised set of **flags + subcommands** parsed from `--help`, then diffs
against the previous snapshot. Snapshots live in **`~/.cli-capability/`** — deliberately
outside `~/.claude`, so a repo sync can never clobber machine state (raw help text is kept
under `~/.cli-capability/raw/` for inspection).

**Exit codes:** `0` = no surface change · `10` = surface changed · `1` = probe error.

### Reconciliation — the part that is not optional

When the probe reports `*** SURFACE CHANGED ***`, do **not** just note it in the report.
**A gained capability invalidates every memory, rule, or workaround that asserts it is absent.**

For any *gained* flag or subcommand the probe now runs the first step for you: it greps
`~/.claude/projects/*/memory/`, `~/.claude/rules/`, `~/.claude/skills/` and `~/.claude/docs/`
for lines that mention the CLI (or a newly-gained token) **and** read as an assertion of
absence ("no", "can't", "lacks", "unsupported", …), and prints them under `claim scan:`.
Disable with `--no-claim-scan`; in `--json` mode the hits land in each diff's `absence_claims`,
alongside `claim_scan_status` (`skipped` | `complete` | `truncated` | `partial_error`) — an empty
`absence_claims` only means "clean" when the status is `complete`.

**Know what that scan is: a regex grep, not comprehension.** It over-reports (any negated
sentence near the CLI name matches) and it can under-report — a claim phrased without a
negation word, stored outside `~/.claude`, or living only in an Anamnesis memory or a project
`project-intel.md` will not appear. Output is capped at 12 hits. Treat it as a shortlist,
never as "nothing to reconcile".

So, for each added flag/subcommand:

```bash
# 1. Read the claim-scan hits (plus your own grep if none of them looks like the claim).
grep -ril '<cli-name>' ~/.claude/projects/*/memory/ ~/.claude/rules/ ~/.claude/skills/ ~/.claude/docs/

# 2. Any claim of the form "X has no <flag>", "X can't run headless",
#    "X has no --model", "must use <paid/metered fallback> because X lacks Y"?

# 3. Re-TEST the claim against the new binary before believing either side.
#    e.g.  agy -p 'reply with OK' --model <id>
```

- Claim now false → **update the memory/rule in the same session**, and say so in the Step 5
  report. Don't leave a corrected claim only in conversation; it evaporates.
- A **removed** flag is the mirror failure: some script still passes it and will start failing.
  `grep -r '<removed-flag>' ~/.claude/scripts ~/Dev` before moving on.
- A **changed path** (`PATH SHADOWING RISK` in the output) is Trap B in Step 3 — a cask
  re-linked a binary over your CLI. Fix PATH ordering.

Any memory that says "re-test after each update" is a **defect in this skill**, not a note to a
human. Convert it into a probe entry (add the CLI to `MANAGED` in the script) so the next
upgrade re-tests it automatically.

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
- **Any capability-surface change from Step 3.6** — list added/removed flags and subcommands,
  and state explicitly which memories/rules you reconciled (or "none asserted absence").
- Which casks were held back and why.

## Step 6 — Vulnerability scan (`brew vulns`, optional but recommended)

Homebrew 6.0 added **`brew vulns`** — a subcommand (shipped in the official `homebrew/brew-vulns`
tap) that checks your *installed* packages against known CVE advisories. This is the security
payoff of the upgrade: not just "is brew current" but "does anything I have installed have a
known vulnerability." Run it at the end of an update so the report reflects the freshly-upgraded
state.

```bash
# First run only: tap it (official Homebrew-org tap → trusted by default under 6.0 tap-trust)
brew tap | grep -qx 'homebrew/brew-vulns' || brew tap homebrew/brew-vulns
brew vulns                                   # scan installed formulae/casks for known CVEs
```

- **Clean scan:** note it in the Step 5 report ("vulns: 0 known CVEs") and move on.
- **Hits:** surface each vulnerable package + advisory and recommend the fix (usually a
  `brew upgrade <pkg>`, occasionally an uninstall if there's no patched version yet). Do **not**
  auto-remove anything — flag it, let the user decide.

> This step is read-only and safe to run unattended. It is the natural home for the
> fleet-security probe tracked on cockpit card `c-3bf14a86` — once validated here, the same
> `brew vulns` call belongs in `weekly-machine-update.sh` and a heartbeat probe across M4/M2/VPS.

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
