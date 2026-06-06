// SPDX-License-Identifier: MIT
// Reference driver for the /model-scan skill.
//
// Hits a provider's /models endpoint, fetches their docs, and emits a JSON snapshot.
// Extend with more providers, regex extractors, and a richer fallback table for
// production use.
//
// Usage:
//   npx tsx scripts/model-scan.ts [--update-claude-md] [--skip-docs] [--help]

import fs from "node:fs";
import path from "node:path";

const HELP = `model-scan.ts — LLM model and docs scanner

Usage:
  npx tsx scripts/model-scan.ts [flags]

Flags:
  --update-claude-md  Rewrite CLAUDE.md's "Current AI Model IDs" table
  --skip-docs         Reuse the most recent doc snapshots instead of fetching
  --setup             Verify required env vars and print a checklist
  --help, -h          Show this help

Environment:
  OPENAI_API_KEY       Required to scan OpenAI
  ANTHROPIC_API_KEY    Required to scan Anthropic
  GEMINI_API_KEY       Required to scan Google Gemini

Output:
  docs/briefings/model-scan/<date>.json
  docs/briefings/model-scan/docs/<date>/*.txt
`;

const args = new Set(process.argv.slice(2));

if (args.has("--help") || args.has("-h")) {
  console.log(HELP);
  process.exit(0);
}

if (args.has("--setup")) {
  const required = ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY"];
  console.log("model-scan setup check:");
  let allOk = true;
  for (const k of required) {
    const ok = !!process.env[k];
    console.log(`  ${ok ? "OK " : "-- "} ${k}${ok ? "" : "  (provider will be skipped)"}`);
    if (!ok) allOk = false;
  }
  console.log("");
  console.log(allOk
    ? "All keys present. Run `npx tsx scripts/model-scan.ts` to perform a scan."
    : "Set the missing variables in your shell or in a .env file, then re-run --setup.");
  process.exit(0);
}

const UPDATE_CLAUDE_MD = args.has("--update-claude-md");
const SKIP_DOCS = args.has("--skip-docs");
const DATE = new Date().toISOString().slice(0, 10);
const OUT_DIR = path.join("docs", "briefings", "model-scan");
const DOCS_DIR = path.join(OUT_DIR, "docs", DATE);
fs.mkdirSync(DOCS_DIR, { recursive: true });

type Model = {
  id: string;
  provider: string;
  context_window?: number | "TBD";
  max_output?: number | "TBD";
  input_price_per_m?: number | "TBD";
  output_price_per_m?: number | "TBD";
  data_sources: string[];
};

const FALLBACK_PRICING: Record<string, { in: number; out: number }> = {
  // Update these as providers ship new flagships
  "gpt-5.5": { in: 5, out: 30 },
  "claude-opus-4-7": { in: 15, out: 75 },
  "claude-sonnet-4-6": { in: 3, out: 15 },
  "gemini-3-pro": { in: 1.25, out: 5 },
};

// CLI_EXTRAS — non-API CLIs that share the provider namespace. These are not scanned
// via /models endpoints (they don't expose one); the catalogue exists so CLAUDE.md
// regeneration and downstream tooling stay aware of which binary serves which provider.
//
// Antigravity CLI (`agy`) replaced the Gemini CLI on consumer plans on 2026-06-18.
// Enterprise plans (Gemini Code Assist Standard/Enterprise, Google Cloud paid keys)
// may continue to ship the legacy `gemini` binary; both share the same API and
// `GEMINI_API_KEY` env var.
const CLI_EXTRAS: Array<{
  name: string;
  binary: string;
  provider: string;
  install: string;
  notes: string;
}> = [
  {
    name: "Claude Code",
    binary: "claude",
    provider: "anthropic",
    install: "npm install -g @anthropic-ai/claude-code",
    notes: "Anthropic's coding CLI — same models as the API.",
  },
  {
    name: "Codex CLI",
    binary: "codex",
    provider: "openai",
    install: "npm install -g @openai/codex",
    notes: "ChatGPT Business subscription auth via `codex login`.",
  },
  {
    name: "Antigravity CLI",
    binary: "agy",
    provider: "google",
    install: "curl -fsSL https://antigravity.google/cli/install.sh | bash",
    notes:
      "Replaces Gemini CLI on consumer plans (sunset 2026-06-18). " +
      "Enterprise plans may keep `gemini`. Non-interactive form must be " +
      "`agy -p \"<prompt>\" </dev/null` — without the stdin redirect, `agy` " +
      "deadlocks waiting on a TTY even when a prompt arg is supplied.",
  },
];

async function scanOpenAI(): Promise<Model[]> {
  if (!process.env.OPENAI_API_KEY) {
    console.log("[skip] OpenAI — no OPENAI_API_KEY");
    return [];
  }
  const r = await fetch("https://api.openai.com/v1/models", {
    headers: { Authorization: `Bearer ${process.env.OPENAI_API_KEY}` },
  });
  if (!r.ok) {
    console.error("OpenAI models endpoint failed:", r.status);
    return [];
  }
  const json = (await r.json()) as { data: { id: string }[] };
  return json.data.map((m) => ({
    id: m.id,
    provider: "openai",
    data_sources: ["api"],
    ...(FALLBACK_PRICING[m.id] && {
      input_price_per_m: FALLBACK_PRICING[m.id].in,
      output_price_per_m: FALLBACK_PRICING[m.id].out,
    }),
  }));
}

async function scanAnthropic(): Promise<Model[]> {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.log("[skip] Anthropic — no ANTHROPIC_API_KEY");
    return [];
  }
  const r = await fetch("https://api.anthropic.com/v1/models", {
    headers: {
      "x-api-key": process.env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
  });
  if (!r.ok) {
    console.error("Anthropic models endpoint failed:", r.status);
    return [];
  }
  const json = (await r.json()) as { data: { id: string }[] };
  return json.data.map((m) => ({
    id: m.id,
    provider: "anthropic",
    data_sources: ["api"],
    ...(FALLBACK_PRICING[m.id] && {
      input_price_per_m: FALLBACK_PRICING[m.id].in,
      output_price_per_m: FALLBACK_PRICING[m.id].out,
    }),
  }));
}

async function scanGemini(): Promise<Model[]> {
  if (!process.env.GEMINI_API_KEY) {
    console.log("[skip] Gemini — no GEMINI_API_KEY");
    return [];
  }
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models?key=${process.env.GEMINI_API_KEY}`,
  );
  if (!r.ok) {
    console.error("Gemini models endpoint failed:", r.status);
    return [];
  }
  const json = (await r.json()) as {
    models: { name: string; inputTokenLimit?: number; outputTokenLimit?: number }[];
  };
  return (json.models ?? []).map((m) => {
    const id = m.name.replace(/^models\//, "");
    return {
      id,
      provider: "google",
      context_window: m.inputTokenLimit ?? "TBD",
      max_output: m.outputTokenLimit ?? "TBD",
      data_sources: ["api"],
      ...(FALLBACK_PRICING[id] && {
        input_price_per_m: FALLBACK_PRICING[id].in,
        output_price_per_m: FALLBACK_PRICING[id].out,
      }),
    } as Model;
  });
}

async function fetchDocsSnapshot(name: string, url: string) {
  if (SKIP_DOCS) return;
  try {
    const r = await fetch(url);
    if (!r.ok) {
      console.warn(`[doc-fetch warn] ${name}: HTTP ${r.status}`);
      return;
    }
    const text = await r.text();
    fs.writeFileSync(path.join(DOCS_DIR, `${name}.txt`), text);
  } catch (e) {
    console.warn(`[doc-fetch warn] ${name}: ${(e as Error).message}`);
  }
}

async function main() {
  const [openai, anthropic, gemini] = await Promise.all([
    scanOpenAI(),
    scanAnthropic(),
    scanGemini(),
  ]);
  const models = [...openai, ...anthropic, ...gemini];

  await Promise.all([
    fetchDocsSnapshot("openai-models", "https://platform.openai.com/docs/models"),
    fetchDocsSnapshot("anthropic-models", "https://docs.anthropic.com/en/docs/about-claude/models"),
    fetchDocsSnapshot("gemini-models", "https://ai.google.dev/gemini-api/docs/models"),
  ]);

  fs.writeFileSync(
    path.join(OUT_DIR, `${DATE}.json`),
    JSON.stringify({ date: DATE, models, cli_extras: CLI_EXTRAS }, null, 2),
  );

  console.log(`Scanned ${models.length} models across ${new Set(models.map(m => m.provider)).size} providers.`);
  console.log(`CLI catalogue: ${CLI_EXTRAS.map((c) => c.binary).join(", ")}`);
  console.log(`JSON: ${path.join(OUT_DIR, `${DATE}.json`)}`);
  console.log(`Docs: ${DOCS_DIR}`);

  if (UPDATE_CLAUDE_MD) {
    console.log("--update-claude-md requested. Implement table rewrite for your project's CLAUDE.md layout.");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
