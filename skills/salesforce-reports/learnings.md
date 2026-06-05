# salesforce-reports — learnings log

Append-only. Dated entries. Each entry gets one of three fates on consolidation: **apply**
(promote into SKILL.md body), **capture** (keep here), **dismiss**.

Consolidate weekly OR when this file exceeds ~100 bullets.

## Format

```
## YYYY-MM-DD — <one-line context>
- <observation>
- <natural-language critique: "When X, naive approach produces Y because Z — do W instead">
```

## 2026-06-06 — seeded from first build + live verification on org62
- The Analytics REST `POST /analytics/reports?cloneId=<id>` requires a full
  `reportMetadata` body even when `cloneId` is supplied — a bare `{}` returns
  `BAD_REQUEST: "there is no metadata"`. Always fetch the source `/describe`,
  rename, and POST the whole `reportMetadata`. (applied → Known gotchas)
- `sf api request rest` DELETE is broken for a plain `-X DELETE`: it errors
  `No 'mode' found in 'body' entry`. Passing `-b ''` or `--body '{...}'` does NOT
  fix it. The working path is `-f <envelope.json>` where `header` is an ARRAY of
  `"k:v"` strings and `body` is `{"mode":"raw","raw":""}`. A bare object header
  errors `keyValPair.map is not a function`. (applied → Known gotchas)
- curl with the token from `sf org display [--verbose]` returns
  `INVALID_AUTH_HEADER` — the CLI masks the access token (54 chars). Never shell
  out to curl for org calls; always go through `sf api request rest`, which auths
  internally. (applied → Known gotchas)
- `sf data delete record --sobject Report` fails with
  `INSUFFICIENT_ACCESS_OR_READONLY` even when the Analytics REST DELETE succeeds —
  the SObject delete path enforces different rights than the Analytics API. Use
  the Analytics endpoint to delete reports. (applied → Anti-patterns)
- There is no native `sf report create` / `sf analytics` command. The hits for
  "report" in `sf commands` are all package/deploy *status* commands. Report CRUD
  is Analytics REST (this skill) or Metadata API (`Report` component deploy).
  (captured)
- `sf org list` shows org62 connected as `eprouveze@salesforce.com`; default API
  is 67.0 but Analytics REST is verified stable on 62.0 (the skill pins 62.0).
  (captured)
