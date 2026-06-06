// SPDX-License-Identifier: MIT
/**
 * /crawl — Tiered web page fetcher with JS rendering support
 *
 * Fetch web pages that may be JS-rendered or bot-protected, returning clean markdown or HTML.
 *
 * Tiers (tried in order with --tier all):
 *   1. Cloudflare Browser Rendering /markdown endpoint (renders JS, bypasses most WAFs)
 *      — active only when CLOUDFLARE_* env vars are set; otherwise skipped.
 *   2. Direct fetch (fast, free, zero-setup fallback)
 *   3. Returns error with details (caller decides fallback — docs API, web search, cache, etc.)
 *
 * Usage:
 *   npx tsx crawl.ts <url>                    # Single URL → stdout
 *   npx tsx crawl.ts <url> --format html      # Get HTML instead of markdown
 *   npx tsx crawl.ts <url> --save <path>      # Save to file
 *   npx tsx crawl.ts --batch <file>           # Batch: one URL per line
 *   npx tsx crawl.ts <url> --tier cf           # Cloudflare only
 *   npx tsx crawl.ts <url> --tier direct       # Direct fetch only (no setup needed)
 *
 * Environment (optional — enables the Cloudflare Browser Rendering tier):
 *   CLOUDFLARE_BR_TOKEN    — Cloudflare API token with "Browser Rendering - Edit" scope
 *   CLOUDFLARE_ACCOUNT_ID  — Cloudflare account ID
 *   Both are read from ~/.env if not already in the environment.
 *   GEMINI_API_KEY / GOOGLE_AI_API_KEY — optional, only for --summarize.
 *
 * Exit codes:
 *   0 — success
 *   1 — all tiers failed
 *   2 — invalid arguments
 */

import { readFileSync, writeFileSync, existsSync } from "fs";
import { resolve } from "path";
import dotenv from "dotenv";

// Load env from ~/.env (optional)
const homeEnv = resolve(process.env.HOME || "~", ".env");
if (existsSync(homeEnv)) dotenv.config({ path: homeEnv });

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface CrawlResult {
  url: string;
  content: string;
  tier: "direct" | "cf-markdown" | "cf-html";
  httpStatus?: number;
  error?: string;
  blocked?: boolean; // true if content is a WAF block page
  summary?: string; // LLM-generated exec summary (when --summarize is used)
  contentLength?: number; // character count of content
  fetchedAt?: string; // ISO timestamp
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const CF_TOKEN = process.env.CLOUDFLARE_BR_TOKEN;
const CF_ACCOUNT = process.env.CLOUDFLARE_ACCOUNT_ID;
const DIRECT_TIMEOUT = 10_000;
const CF_TIMEOUT = 30_000;

// Patterns that indicate the response is a WAF/bot block page
const BLOCK_PATTERNS = [
  /you have been blocked/i,
  /enable cookies/i,
  /security service to protect itself/i,
  /captcha|hcaptcha|recaptcha/i,
  /access denied.*cloudflare/i,
  /checking your browser/i,
  /just a moment\.\.\./i,
];

function isBlockedResponse(content: string): boolean {
  // Only check first 2000 chars — block pages are at the top
  const head = content.slice(0, 2000);
  return BLOCK_PATTERNS.some((p) => p.test(head));
}

// ---------------------------------------------------------------------------
// Simple HTML → text (for direct fetch fallback)
// ---------------------------------------------------------------------------

function htmlToText(html: string): string {
  return (
    html
      .replace(/<script[\s\S]*?<\/script>/gi, "")
      .replace(/<style[\s\S]*?<\/style>/gi, "")
      .replace(/<\/(p|div|h[1-6]|tr|li|br\s*\/?)>/gi, "\n")
      .replace(/<(br|hr)\s*\/?>/gi, "\n")
      .replace(/<\/(td|th)>/gi, "\t")
      // Preserve alt text from images and area maps before stripping tags
      .replace(/<img\b[^>]*\balt="([^"]*)"[^>]*>/gi, " $1 ")
      .replace(/<area\b[^>]*\balt="([^"]*)"[^>]*>/gi, " $1 ")
      .replace(/<[^>]+>/g, "")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&#x27;/g, "'")
      .replace(/&nbsp;/g, " ")
      .replace(/\n{3,}/g, "\n\n")
      .trim()
  );
}

// ---------------------------------------------------------------------------
// Tier: Direct fetch
// ---------------------------------------------------------------------------

async function fetchDirect(
  url: string,
  wantHtml: boolean,
): Promise<CrawlResult> {
  try {
    const resp = await fetch(url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        Accept:
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
      signal: AbortSignal.timeout(DIRECT_TIMEOUT),
      redirect: "follow",
    });

    if (!resp.ok) {
      return {
        url,
        content: "",
        tier: "direct",
        httpStatus: resp.status,
        error: `HTTP ${resp.status}`,
      };
    }

    const html = await resp.text();

    // Check if response is a block page
    if (isBlockedResponse(html)) {
      return {
        url,
        content: "",
        tier: "direct",
        httpStatus: resp.status,
        error: "WAF block page detected",
        blocked: true,
      };
    }

    // Check if content is mostly "Loading..." (JS SPA not rendered)
    const text = htmlToText(html);
    const loadingRatio =
      (text.match(/loading/gi) || []).length /
      Math.max(text.split("\n").length, 1);
    if (loadingRatio > 0.1 && text.length < 2000) {
      return {
        url,
        content: text,
        tier: "direct",
        error: "JS SPA not rendered (mostly Loading... text)",
        blocked: false,
      };
    }

    return {
      url,
      content: wantHtml ? html : text,
      tier: "direct",
      httpStatus: resp.status,
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);

    // If HTTPS failed, try HTTP as fallback (some legacy sites only serve HTTP)
    if (url.startsWith("https://")) {
      const httpUrl = url.replace("https://", "http://");
      try {
        const resp = await fetch(httpUrl, {
          headers: {
            "User-Agent":
              "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
          },
          signal: AbortSignal.timeout(DIRECT_TIMEOUT),
          redirect: "follow",
        });
        if (resp.ok) {
          const html = await resp.text();
          if (!isBlockedResponse(html)) {
            const text = htmlToText(html);
            return {
              url: httpUrl,
              content: wantHtml ? html : text,
              tier: "direct",
              httpStatus: resp.status,
            };
          }
        }
      } catch {
        // HTTP fallback also failed — return original HTTPS error
      }
    }

    return {
      url,
      content: "",
      tier: "direct",
      error: msg.includes("timeout") ? "Timeout" : msg,
    };
  }
}

// ---------------------------------------------------------------------------
// Tier: Cloudflare Browser Rendering
// ---------------------------------------------------------------------------

async function fetchCF(
  url: string,
  format: "markdown" | "html",
): Promise<CrawlResult> {
  if (!CF_TOKEN || !CF_ACCOUNT) {
    return {
      url,
      content: "",
      tier: format === "markdown" ? "cf-markdown" : "cf-html",
      error: "CLOUDFLARE_BR_TOKEN or CLOUDFLARE_ACCOUNT_ID not set",
    };
  }

  const endpoint =
    format === "markdown"
      ? `https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT}/browser-rendering/markdown`
      : `https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT}/browser-rendering/content`;

  try {
    const resp = await fetch(endpoint, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${CF_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ url }),
      signal: AbortSignal.timeout(CF_TIMEOUT),
    });

    const data = (await resp.json()) as {
      success: boolean;
      result?: string;
      errors?: Array<{ code: number; message: string }>;
    };

    if (!data.success || !data.result) {
      const errMsg =
        data.errors?.map((e) => e.message).join("; ") ?? "Unknown CF error";
      return {
        url,
        content: "",
        tier: format === "markdown" ? "cf-markdown" : "cf-html",
        error: errMsg,
      };
    }

    // Check if CF returned a block page (some WAFs block even Cloudflare's renderer)
    if (isBlockedResponse(data.result)) {
      return {
        url,
        content: data.result,
        tier: format === "markdown" ? "cf-markdown" : "cf-html",
        error: "WAF block page (even with CF Browser Rendering)",
        blocked: true,
      };
    }

    return {
      url,
      content: data.result,
      tier: format === "markdown" ? "cf-markdown" : "cf-html",
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return {
      url,
      content: "",
      tier: format === "markdown" ? "cf-markdown" : "cf-html",
      error: msg,
    };
  }
}

// ---------------------------------------------------------------------------
// Optional summarization (Gemini Flash)
// ---------------------------------------------------------------------------

async function summarizeContent(content: string, url: string): Promise<string> {
  const apiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_AI_API_KEY;
  if (!apiKey) return "(summarize skipped — no GEMINI_API_KEY)";

  const truncated = content.slice(0, 8000); // ~2K tokens, enough for a summary
  try {
    const resp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                {
                  text: `Summarize this web page in 2-3 sentences. Be specific — include key facts, numbers, and what the page is about. URL: ${url}\n\nContent:\n${truncated}`,
                },
              ],
            },
          ],
          generationConfig: { maxOutputTokens: 500 },
        }),
        signal: AbortSignal.timeout(15_000),
      },
    );
    if (!resp.ok) return `(summarize failed — ${resp.status})`;
    const data = (await resp.json()) as any;
    return (
      data.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ??
      "(no summary generated)"
    );
  } catch (err) {
    return `(summarize failed — ${err instanceof Error ? err.message : String(err)})`;
  }
}

// ---------------------------------------------------------------------------
// Main: tiered fetch
// ---------------------------------------------------------------------------

export async function crawl(
  url: string,
  options: {
    format?: "markdown" | "html";
    tier?: "direct" | "cf" | "all";
    summarize?: boolean;
  } = {},
): Promise<CrawlResult> {
  const format = options.format ?? "markdown";
  const tier = options.tier ?? "all";

  let result: CrawlResult;

  if (tier === "direct") {
    result = await fetchDirect(url, format === "html");
  } else if (tier === "cf") {
    result = await fetchCF(url, format);
  } else {
    // Default ("all"): CF first (when configured), direct fetch as fallback
    result = await fetchCF(url, format);
    if (!result.content || result.error) {
      const direct = await fetchDirect(url, format === "html");
      if (direct.content && !direct.error) {
        result = direct;
      }
    }
  }

  // Enrich with metadata
  result.fetchedAt = new Date().toISOString();
  result.contentLength = result.content.length;

  // Optional LLM summary
  if (options.summarize && result.content && !result.error) {
    result.summary = await summarizeContent(result.content, url);
  }

  return result;
}

function formatFrontmatter(result: CrawlResult): string {
  const lines = [
    "---",
    `url: ${result.url}`,
    `tier: ${result.tier}`,
    `fetched_at: ${result.fetchedAt}`,
    `content_length: ${result.contentLength}`,
  ];
  if (result.httpStatus) lines.push(`http_status: ${result.httpStatus}`);
  if (result.error) lines.push(`error: "${result.error}"`);
  if (result.blocked) lines.push(`blocked: true`);
  if (result.summary)
    lines.push(`summary: "${result.summary.replace(/"/g, '\\"')}"`);
  lines.push("---", "");
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Batch mode
// ---------------------------------------------------------------------------

async function crawlBatch(
  urls: string[],
  options: {
    format?: "markdown" | "html";
    tier?: "direct" | "cf" | "all";
    summarize?: boolean;
  },
): Promise<CrawlResult[]> {
  // Parallel with concurrency limit of 5
  const results: CrawlResult[] = [];
  const concurrency = 5;

  for (let i = 0; i < urls.length; i += concurrency) {
    const batch = urls.slice(i, i + concurrency);
    const batchResults = await Promise.all(
      batch.map((url) => crawl(url, options)),
    );
    results.push(...batchResults);
  }

  return results;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    console.log(`Usage: npx tsx crawl.ts <url> [options]
       npx tsx crawl.ts --batch <file> [options]

Options:
  --format markdown|html   Output format (default: markdown)
  --save <path>            Save output to file
  --tier direct|cf|all     Which tiers to try (default: all)
  --batch <file>           Read URLs from file (one per line)
  --json                   Output as JSON (useful for scripting)
  --summarize              Add LLM-generated exec summary (uses Gemini Flash)
  -h, --help               Show this help`);
    process.exit(args.length === 0 ? 2 : 0);
  }

  const format = (
    args.includes("--format") ? args[args.indexOf("--format") + 1] : "markdown"
  ) as "markdown" | "html";
  const tier = (
    args.includes("--tier") ? args[args.indexOf("--tier") + 1] : "all"
  ) as "direct" | "cf" | "all";
  const savePath = args.includes("--save")
    ? args[args.indexOf("--save") + 1]
    : null;
  const jsonOutput = args.includes("--json");
  const summarize = args.includes("--summarize");
  const batchFile = args.includes("--batch")
    ? args[args.indexOf("--batch") + 1]
    : null;

  if (batchFile) {
    const urls = readFileSync(batchFile, "utf-8")
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith("#"));

    console.error(`Crawling ${urls.length} URLs...`);
    const results = await crawlBatch(urls, { format, tier, summarize });

    for (const r of results) {
      const status = r.error
        ? `FAIL (${r.tier}: ${r.error})`
        : `OK (${r.tier}${r.summary ? " +summary" : ""})`;
      console.error(`  ${status}: ${r.url}`);
    }

    if (jsonOutput) {
      const output = JSON.stringify(results, null, 2);
      if (savePath) writeFileSync(savePath, output, "utf-8");
      else console.log(output);
    } else if (savePath) {
      for (const r of results) {
        if (!r.content) continue;
        const slug = new URL(r.url).pathname.replace(/\//g, "_").slice(0, 50);
        const ext = format === "html" ? ".html" : ".md";
        const filePath = `${savePath}/${slug}${ext}`;
        writeFileSync(filePath, formatFrontmatter(r) + r.content, "utf-8");
      }
    }

    const failed = results.filter((r) => r.error);
    process.exit(failed.length === results.length ? 1 : 0);
  } else {
    // Single URL mode
    const url =
      args.find((a) => !a.startsWith("--") && args.indexOf(a) === 0) || args[0];
    if (!url || url.startsWith("--")) {
      console.error("Error: No URL provided");
      process.exit(2);
    }

    const result = await crawl(url, { format, tier, summarize });

    if (jsonOutput) {
      const output = JSON.stringify(result, null, 2);
      if (savePath) writeFileSync(savePath, output, "utf-8");
      else console.log(output);
    } else {
      if (result.error) {
        console.error(
          `${result.blocked ? "BLOCKED" : "FAIL"} (${result.tier}): ${result.error}`,
        );
      }
      if (result.summary) {
        console.error(`Summary: ${result.summary}`);
      }
      if (result.content) {
        if (savePath) {
          writeFileSync(
            savePath,
            formatFrontmatter(result) + result.content,
            "utf-8",
          );
          console.error(`Saved to ${savePath}`);
        } else {
          console.log(result.content);
        }
      }
    }

    process.exit(result.content ? 0 : 1);
  }
}

// Only run CLI when this file is the entry point (not when imported)
const isMainModule =
  process.argv[1]?.endsWith("crawl.ts") ||
  process.argv[1]?.endsWith("crawl.js");
if (isMainModule) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
