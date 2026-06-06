---
name: crawl
description: >
  Fetch web pages that may be JS-rendered or bot-protected, returning clean markdown
  or HTML. Works zero-setup with a direct HTTP fetch; if you supply your own Cloudflare
  Browser Rendering credentials it uses a managed headless browser that renders JS and
  bypasses most WAFs. Use when a plain fetch returns 403, when a page is a JS-rendered
  SPA, or when you need reliable markdown extraction from a URL. Triggers on 'crawl this
  page', 'fetch this URL', 'scrape this site', 'get the content from this page', 'this
  page is blocked', or when a normal fetch fails on a URL.
allowed-tools: Bash, Read, Write
user-invocable: true
version: 0.1.0
last-updated: 2026-06-06
last-consolidated: 2026-06-06
metadata:
  author: Emmanuel Prouveze
  argument-hint: "<url> [options]"
---

# /crawl — Tiered Web Page Fetcher

Fetch web pages that may be JS-rendered or bot-protected, and return clean markdown (or raw
HTML). It has two tiers: a **direct HTTP fetch** that needs zero configuration, and
**Cloudflare Browser Rendering** — a managed headless Chromium that renders JavaScript,
follows redirects, and bypasses most WAFs — which activates only when you supply your own
Cloudflare credentials.

The bundled script is `scripts/crawl.ts` (run with `npx tsx`).

## Requirements

**Out of the box (no setup):** the direct-fetch tier needs only Node.js and `tsx`
(`npm install -g tsx`). It handles static HTML, many simple pages, and
`.md`/`.md.txt`/`.txt` endpoints. JS-rendered SPAs and bot-protected pages will fail this
tier — that's expected, and where the Cloudflare tier comes in.

**Optional — bring your own Cloudflare Browser Rendering (recommended for JS/SPA/blocked
pages):** Cloudflare's Browser Rendering REST API runs a real headless Chromium in their
network. It's a per-account API — there's no shared endpoint, so you supply **your own**
account ID and token via environment variables:

| Variable | Required for | What it is |
|---|---|---|
| `CLOUDFLARE_ACCOUNT_ID` | CF tier | Your Cloudflare account ID (32-char hex) |
| `CLOUDFLARE_BR_TOKEN` | CF tier | An API token scoped to **Account → Browser Rendering → Edit** |

Setup:
1. Sign in at `https://dash.cloudflare.com` and copy your **Account ID** (right sidebar).
2. Create an API token at `https://dash.cloudflare.com/profile/api-tokens` with the
   **Account → Browser Rendering → Edit** permission. Copy it once — it isn't shown again.
3. Export both (shell rc, or a `.env` file in your home dir — the script auto-loads `~/.env`):
   ```bash
   export CLOUDFLARE_ACCOUNT_ID="your-account-id"
   export CLOUDFLARE_BR_TOKEN="your-api-token"
   ```

> Cloudflare Browser Rendering docs: `https://developers.cloudflare.com/browser-rendering/rest-api/`
> The free plan includes a daily quota; higher volume needs a Workers Paid plan.

If the Cloudflare variables are unset, the CF tier is skipped automatically and the skill
operates in direct-fetch-only mode.

## Usage

### From the CLI

```bash
# Single URL → markdown to stdout
npx tsx scripts/crawl.ts "https://example.com"

# Save to file (writes YAML frontmatter + content)
npx tsx scripts/crawl.ts "https://example.com" --save ./output.md

# Get HTML instead of markdown
npx tsx scripts/crawl.ts "https://example.com" --format html

# Force a tier: cf = Cloudflare only, direct = no CF (e.g. a known plain-text endpoint)
npx tsx scripts/crawl.ts "https://example.com" --tier cf
npx tsx scripts/crawl.ts "https://example.com/llms.txt" --tier direct

# Batch mode (one URL per line; output dir for --save)
npx tsx scripts/crawl.ts --batch urls.txt --save ./output/

# JSON output (for scripting)
npx tsx scripts/crawl.ts "https://example.com" --json

# Add a short LLM-generated summary (needs GEMINI_API_KEY — see below)
npx tsx scripts/crawl.ts "https://example.com" --summarize
```

### From TypeScript (import into another script)

```typescript
import { crawl } from "./scripts/crawl.ts";

const result = await crawl("https://example.com", { format: "markdown" });
if (result.content && !result.error) {
  // result.content is the markdown string
} else {
  // result.error / result.blocked tell you what went wrong
}
```

### Options

| Flag | Values | Default | Notes |
|---|---|---|---|
| `--format` | `markdown` \| `html` | `markdown` | Output format |
| `--tier` | `all` \| `cf` \| `direct` | `all` | Which tiers to try |
| `--save` | path | — | File (single) or directory (batch) |
| `--batch` | file | — | One URL per line; `#` lines ignored |
| `--json` | — | off | Emit a JSON `CrawlResult` instead of raw content |
| `--summarize` | — | off | Append a 2–3 sentence LLM summary |

## How it works

Two tiers. With the default `--tier all`:

1. **Cloudflare Browser Rendering** is tried **first** when credentials are set — it renders
   JS, bypasses most WAFs, follows redirects, and returns markdown or HTML. If the
   `CLOUDFLARE_*` vars are missing, this tier returns immediately with a "not set" error and
   the skill falls through to tier 2.
2. **Direct fetch** (always available) — a plain HTTP `fetch` with a desktop User-Agent,
   basic HTML→text conversion, and an automatic HTTPS→HTTP retry for legacy sites. It detects
   WAF block pages and unrendered "Loading…" SPAs and reports them as errors.

So out of the box (no Cloudflare account) every call degrades gracefully to direct fetch.
Use `--tier direct` to skip CF entirely (e.g. a known `llms.txt`/`.md.txt` endpoint), or
`--tier cf` to skip the direct attempt.

If both tiers fail, the result carries `error` (and `blocked: true` for WAF pages) so the
caller can pick the next move — an official docs API, a GitHub-hosted README, a search tool.

### What each tier handles

| Scenario | Direct | Cloudflare Browser Rendering |
|---|---|---|
| Static HTML | works | works |
| JS SPA (React/Vue) | "Loading…" only | works (renders JS) |
| Bot-protected pages | often 403 | usually works |
| `.md.txt` / `llms.txt` endpoints | works | works |
| Sites that block Cloudflare's egress IPs | varies | blocked (WAF blocks CF too) |

## Optional summarization

`--summarize` appends a short, fact-focused summary generated by Google's Gemini Flash. It
needs a `GEMINI_API_KEY` (or `GOOGLE_AI_API_KEY`) in the environment. If neither is set,
summarization is silently skipped and crawling still works. Swap in any LLM you prefer by
editing `summarizeContent()` in `scripts/crawl.ts`.

## Output format

With `--save`, the script writes a YAML frontmatter block followed by the content:

```yaml
---
url: https://example.com
tier: cf-markdown
fetched_at: 2026-06-06T12:00:00.000Z
content_length: 4821
http_status: 200
---
```

`error`, `blocked`, and `summary` fields are added when present. Without `--save`, content
goes to stdout and diagnostics go to stderr, so you can pipe cleanly.

## Anti-patterns

- **Don't hardcode credentials** in scripts or skill files. The Cloudflare token belongs in
  an environment variable.
- **Don't loop-crawl hundreds of URLs** without delays — you'll hit Cloudflare's quota. Use
  `--batch` (capped at concurrency 5) and space out large jobs.
- **Don't assume CF can reach everything.** Some origins block Cloudflare's IPs; keep a
  non-CF fallback ready.
- **Don't use `--tier cf` with no credentials** — it just errors. Let the default `all`
  degrade to direct fetch.

## Error handling

- `error` set + empty `content` → the tier failed; the message says why (`HTTP 403`,
  `Timeout`, `CLOUDFLARE_BR_TOKEN ... not set`, etc.).
- `blocked: true` → a WAF/CAPTCHA block page was detected. Switch tiers or use another source.
- Exit codes: `0` success, `1` all tiers failed, `2` invalid arguments.
