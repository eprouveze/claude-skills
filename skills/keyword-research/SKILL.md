---
name: keyword-research
description: >
  Check Google Trends for keyword interest and SEO prioritization. Use when the user mentions
  "keyword research", "SEO", "search trends", "content strategy", "blog prioritization",
  "compare keywords", "trending topics", or wants to evaluate keyword opportunities.
allowed-tools: Bash, Read, Edit, Glob, Grep
user-invocable: true
version: 0.1.0
last-updated: 2026-06-06
last-consolidated: 2026-06-06
metadata:
  author: Emmanuel Prouveze
---

# Keyword Research

Check Google search trends and relative interest for keywords. Useful for SEO content
strategy, blog-post prioritization, and deciding where to place marketing assets.

This skill uses a driver script at `scripts/keyword-research.ts` that wraps the
`google-trends-api` npm package. A self-contained reference driver is bundled — adapt the
tracked-keyword lists to your own site.

## Requirements

- **Node.js 20+**
- **`tsx`** to run the TypeScript driver: `npm install -g tsx`
- **`google-trends-api`** npm package: `npm install google-trends-api`

Google Trends has no official API and no API key — the package scrapes the public Trends
endpoints, so it is rate-limited. Wait a few seconds between requests to avoid temporary
blocks.

> The bundled driver is TypeScript/Node, but the same data is reachable from Python via the
> `pytrends` library if you prefer that ecosystem (`pip install pytrends`). The CLI surface
> and result interpretation below are framework-agnostic.

## Immediate action

When this skill is invoked, run the keyword research script from the project root:

```bash
npx tsx scripts/keyword-research.ts
```

If the user provides arguments, pass them through:

```bash
npx tsx scripts/keyword-research.ts --keywords "AI writing tools, ChatGPT prompts, prompt engineering"
npx tsx scripts/keyword-research.ts --related "AI writing tools"
npx tsx scripts/keyword-research.ts --geo US --top 5
```

## Commands

### Compare all tracked keywords

```bash
npx tsx scripts/keyword-research.ts
```

Returns a ranked table of all keywords defined in the driver's tracked-keyword lists, sorted
by average Google Trends interest over the last 12 months.

### Compare specific keywords

```bash
npx tsx scripts/keyword-research.ts --keywords "keyword1, keyword2, keyword3"
```

Compare up to 15 custom keywords. Google Trends allows max 5 per batch, so the driver
compares them in batches.

### Related queries for a keyword

```bash
npx tsx scripts/keyword-research.ts --related "AI writing tools"
```

Returns:
- **Top related queries**: most commonly searched alongside this keyword
- **Rising queries**: fastest-growing related searches (breakout = >5000% growth)
- **Top regions**: countries with highest search interest

### Filter by country

```bash
npx tsx scripts/keyword-research.ts --geo US
npx tsx scripts/keyword-research.ts --geo JP
npx tsx scripts/keyword-research.ts --related "AI writing" --geo US
```

Use ISO 3166-1 alpha-2 country codes. Omit `--geo` for worldwide.

### Show top N only

```bash
npx tsx scripts/keyword-research.ts --top 5
```

## Understanding results

- **Average Interest**: relative number (0–100) where 100 = peak search interest for that
  term in the period. NOT absolute search volume.
- **0 interest**: the keyword has too little search volume for Google Trends to register.
  This doesn't mean zero searches — it's below Google Trends' threshold (roughly <1000
  monthly searches).
- **Comparing across batches**: keywords in different batches are normalized to different
  baselines. The most reliable comparisons are within the same batch (up to 5 keywords).

## Limitations

- Google Trends shows **relative** interest, not absolute search volume. A score of 50 means
  half the peak interest, not 50 searches.
- Very niche / long-tail keywords often show 0 because they fall below Google Trends'
  threshold.
- For actual monthly search-volume numbers, you need a paid tool (Ahrefs, SEMrush, DataForSEO).
- Rate limited: wait between requests to avoid being temporarily blocked.

## Tracked keywords

Keywords are defined in `scripts/keyword-research.ts` in the `BLOG_KEYWORDS` and
`LANDING_KEYWORDS` objects. Update these when adding new blog posts or landing pages so the
default (no-args) run reflects your own content inventory.

## Ad-hoc queries

For quick one-off checks, query Google Trends directly:

```typescript
import googleTrends from "google-trends-api";

const result = await googleTrends.interestOverTime({
  keyword: ["ChatGPT custom instructions", "AI writing tools"],
  startTime: new Date(Date.now() - 365 * 24 * 60 * 60 * 1000),
  geo: "US",
});
const data = JSON.parse(result);
console.log(data.default.timelineData);
```

## Known gotchas

- **Rate limiting is silent.** A blocked request often returns an HTML error page rather than
  JSON, which surfaces as a JSON-parse error. Back off and retry after a pause.
- **Batch normalization confuses comparisons.** Two keywords ranked across different batches
  of 5 are scored against different peaks — never read absolute rank across batch boundaries
  as exact.
- **`geo` must be a valid ISO 3166-1 alpha-2 code.** Invalid codes silently return empty
  timelines that look like "0 interest".
