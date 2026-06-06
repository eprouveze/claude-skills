#!/usr/bin/env npx tsx
// SPDX-License-Identifier: MIT
/**
 * keyword-research.ts — Google Trends interest checker for SEO prioritization.
 *
 * Wraps the `google-trends-api` npm package. No API key required (Trends has no
 * official API); requests are rate-limited, so the driver paces batches.
 *
 * Install: npm install google-trends-api && npm install -g tsx
 *
 * Usage:
 *   npx tsx scripts/keyword-research.ts
 *   npx tsx scripts/keyword-research.ts --keywords "kw1, kw2, kw3"
 *   npx tsx scripts/keyword-research.ts --related "some keyword"
 *   npx tsx scripts/keyword-research.ts --geo US --top 5
 */

// @ts-ignore — package ships no types
import googleTrends from "google-trends-api";

// ---------------------------------------------------------------------------
// Tracked keywords — replace these with your own blog / landing-page keywords.
// ---------------------------------------------------------------------------
const BLOG_KEYWORDS: Record<string, string> = {
  "ai-writing-tools": "AI writing tools",
  "prompt-engineering": "prompt engineering",
  "content-strategy": "content strategy",
};

const LANDING_KEYWORDS: Record<string, string> = {
  "chatgpt-prompts": "ChatGPT prompts",
  "seo-checklist": "SEO checklist",
};

// ---------------------------------------------------------------------------
// Arg parsing
// ---------------------------------------------------------------------------
interface Args {
  keywords?: string[];
  related?: string;
  geo: string;
  top?: number;
}

function parseArgs(argv: string[]): Args {
  const args: Args = { geo: "" };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--keywords") {
      args.keywords = (argv[++i] || "")
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
    } else if (a === "--related") {
      args.related = argv[++i];
    } else if (a === "--geo") {
      args.geo = (argv[++i] || "").toUpperCase();
    } else if (a === "--top") {
      args.top = parseInt(argv[++i], 10);
    } else if (a === "--help" || a === "-h") {
      printHelp();
      process.exit(0);
    }
  }
  return args;
}

function printHelp(): void {
  console.log(`keyword-research.ts — Google Trends interest checker

Options:
  --keywords "a, b, c"   Compare up to 15 custom keywords (batched by 5)
  --related "keyword"    Show top + rising related queries and top regions
  --geo XX               ISO 3166-1 alpha-2 country code (default: worldwide)
  --top N                Show only the top N results
  -h, --help             Show this help`);
}

const ONE_YEAR_MS = 365 * 24 * 60 * 60 * 1000;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------
// Core: average interest over the last 12 months for a batch (<=5 keywords)
// ---------------------------------------------------------------------------
async function interestForBatch(
  keywords: string[],
  geo: string,
): Promise<Record<string, number>> {
  const raw = await googleTrends.interestOverTime({
    keyword: keywords,
    startTime: new Date(Date.now() - ONE_YEAR_MS),
    ...(geo ? { geo } : {}),
  });

  let parsed: any;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(
      "Google Trends returned a non-JSON response (likely rate-limited). " +
        "Wait a few seconds and retry.",
    );
  }

  const timeline: any[] = parsed?.default?.timelineData ?? [];
  const sums = new Array(keywords.length).fill(0);
  for (const point of timeline) {
    const vals: number[] = point.value ?? [];
    vals.forEach((v, idx) => (sums[idx] += v));
  }
  const n = timeline.length || 1;

  const out: Record<string, number> = {};
  keywords.forEach((kw, idx) => {
    out[kw] = Math.round((sums[idx] / n) * 10) / 10;
  });
  return out;
}

async function compareKeywords(
  keywords: string[],
  geo: string,
  top?: number,
): Promise<void> {
  const results: Record<string, number> = {};

  // Google Trends allows max 5 keywords per request.
  for (let i = 0; i < keywords.length; i += 5) {
    const batch = keywords.slice(i, i + 5);
    if (i > 0) await sleep(2000); // pace to avoid rate-limiting
    try {
      Object.assign(results, await interestForBatch(batch, geo));
    } catch (e) {
      console.error(
        `Batch [${batch.join(", ")}] failed: ${(e as Error).message}`,
      );
    }
  }

  let ranked = Object.entries(results).sort((a, b) => b[1] - a[1]);
  if (top) ranked = ranked.slice(0, top);

  const scope = geo || "Worldwide";
  console.log(`\nAverage Google Trends interest (last 12 months) — ${scope}\n`);
  const pad = Math.max(...ranked.map(([k]) => k.length), 7);
  console.log(`${"Keyword".padEnd(pad)}  Interest`);
  console.log(`${"-".repeat(pad)}  --------`);
  for (const [kw, score] of ranked) {
    console.log(`${kw.padEnd(pad)}  ${score}`);
  }
  console.log(
    "\nInterest is relative (0-100), where 100 = peak for the top term in the set.",
  );
  console.log(
    "Keywords in different batches of 5 are normalized to different baselines.\n",
  );
}

async function relatedQueries(keyword: string, geo: string): Promise<void> {
  const scope = geo || "Worldwide";

  const rawRelated = await googleTrends.relatedQueries({
    keyword,
    startTime: new Date(Date.now() - ONE_YEAR_MS),
    ...(geo ? { geo } : {}),
  });
  let related: any;
  try {
    related = JSON.parse(rawRelated);
  } catch {
    console.error(
      "Related queries returned non-JSON (rate-limited?). Retry later.",
    );
    return;
  }

  const ranked = related?.default?.rankedList ?? [];
  const top = ranked[0]?.rankedKeyword ?? [];
  const rising = ranked[1]?.rankedKeyword ?? [];

  console.log(`\nRelated queries for "${keyword}" — ${scope}\n`);

  console.log("Top related queries:");
  top
    .slice(0, 10)
    .forEach((q: any) => console.log(`  ${q.query}  (${q.value})`));

  console.log("\nRising queries (breakout = >5000% growth):");
  rising.slice(0, 10).forEach((q: any) => {
    const label = q.value >= 5000 ? "Breakout" : `+${q.value}%`;
    console.log(`  ${q.query}  (${label})`);
  });

  // Top regions
  const rawRegion = await googleTrends.interestByRegion({
    keyword,
    startTime: new Date(Date.now() - ONE_YEAR_MS),
    ...(geo ? { geo } : {}),
  });
  try {
    const region = JSON.parse(rawRegion);
    const geos: any[] = region?.default?.geoMapData ?? [];
    const topRegions = geos
      .filter((g) => g.value?.[0] > 0)
      .sort((a, b) => b.value[0] - a.value[0])
      .slice(0, 10);
    console.log("\nTop regions:");
    topRegions.forEach((g) => console.log(`  ${g.geoName}  (${g.value[0]})`));
  } catch {
    /* region data optional */
  }
  console.log();
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  if (args.related) {
    await relatedQueries(args.related, args.geo);
    return;
  }

  let keywords: string[];
  if (args.keywords && args.keywords.length) {
    keywords = args.keywords.slice(0, 15);
  } else {
    keywords = [
      ...Object.values(BLOG_KEYWORDS),
      ...Object.values(LANDING_KEYWORDS),
    ];
  }

  await compareKeywords(keywords, args.geo, args.top);
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
