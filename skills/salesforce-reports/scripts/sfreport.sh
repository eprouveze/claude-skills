#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Emmanuel Prouveze
#
# sfreport.sh — create / clone / read / list / run / delete Salesforce Reports
# via the Analytics REST API, driven by the Salesforce CLI (`sf`).
#
# Org-agnostic: works against ANY org you pass with --org (alias or username),
# or the org saved by `sfreport.sh setup`, or the CLI's configured target-org.
# Verified end-to-end (create HTTP 200, delete HTTP 204).
#
# Why a wrapper: `sf api request rest` is the only auth path that works with the
# CLI's masked access token (curl gets INVALID_AUTH_HEADER), but its DELETE/body
# handling is finicky — DELETE needs a full -f envelope with `header` as an ARRAY
# and `body: {"mode":"raw","raw":""}`. This script hides that so you never hit it.

set -euo pipefail

PROG="$(basename "$0")"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-skills"
CONFIG_FILE="$CONFIG_DIR/salesforce-reports.env"

# Defaults (overridable by config file, then env, then flags) ------------------
API_VERSION="${SF_API_VERSION:-62.0}"   # Analytics REST is stable on 62.0
ORG=""                                   # empty => config, then CLI default
GC_COLUMN_DEFAULT=""                     # GAM-only: Global Company filter column

# Load saved config if present (sets ORG / API_VERSION / GLOBAL_COMPANY / GC_COLUMN_DEFAULT)
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# ---------- helpers ----------------------------------------------------------
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
info() { printf '\033[2m%s\033[0m\n' "$*" >&2; }
ok()   { printf '\033[32m%s\033[0m\n' "$*" >&2; }

install_sf() {  # best-effort install via whatever package manager is present
  if command -v npm >/dev/null 2>&1; then
    info "Installing @salesforce/cli via npm ..."; npm install -g @salesforce/cli
  elif command -v brew >/dev/null 2>&1; then
    info "Installing salesforce-cli via Homebrew ..."; brew install --cask salesforce-cli
  elif command -v yarn >/dev/null 2>&1; then
    info "Installing @salesforce/cli via yarn ..."; yarn global add @salesforce/cli
  else
    err "No npm/brew/yarn found. Install Node.js (which bundles npm), then: npm i -g @salesforce/cli"
    return 1
  fi
  command -v sf >/dev/null 2>&1
}

need_sf() {  # $1 (optional) = "auto" to attempt install without prompting
  command -v sf >/dev/null 2>&1 && return 0
  err "sf CLI not found."
  if [[ "${1:-}" == "auto" ]]; then
    install_sf || exit 1
  elif [[ -t 0 ]]; then
    read -r -p "Install it now? [Y/n] " a
    [[ "$a" =~ ^[Nn]$ ]] && { err "Install manually: npm i -g @salesforce/cli"; exit 1; }
    install_sf || { err "Install failed. Try manually: npm i -g @salesforce/cli"; exit 1; }
  else
    err "Install: npm i -g @salesforce/cli  (or run: $PROG setup)"; exit 1
  fi
  command -v sf >/dev/null 2>&1 && ok "sf CLI installed: $(sf version 2>/dev/null | head -1)"
}

org_flag() { [[ -n "$ORG" ]] && printf -- '--target-org %s' "$ORG"; }

sf_rest() {  # $1=method  $2=path  [$3=body-file]
  local method="$1" path="$2" bodyfile="${3:-}"
  # shellcheck disable=SC2046
  case "$method" in
    GET)
      sf api request rest "$path" $(org_flag) 2>/dev/null ;;
    POST|PUT|PATCH)
      sf api request rest "$path" -X "$method" -b "@${bodyfile}" $(org_flag) 2>/dev/null ;;
    DELETE)
      # DELETE requires the full -f envelope (CLI body-handling workaround):
      # header MUST be an array; body MUST be {"mode":"raw","raw":""}.
      local env; env="$(mktemp -t sfreport_del.XXXXXX.json)"
      cat > "$env" <<JSON
{ "url": "${path}", "method": "DELETE",
  "header": ["Content-Type:application/json"],
  "body": { "mode": "raw", "raw": "" } }
JSON
      sf api request rest -f "$env" -i $(org_flag) 2>/dev/null | sed -n '1p'   # HTTP status line
      /bin/rm -f "$env" ;;
  esac
}

resolve_global_company() {
  # Order: --gc arg > $GLOBAL_COMPANY (env or saved config). GAM-only convenience.
  if   [[ -n "${1:-}" ]];                then printf '%s' "$1"
  elif [[ -n "${GLOBAL_COMPANY:-}" ]];   then printf '%s' "$GLOBAL_COMPANY"
  else printf ''; fi
}

# ---------- commands ---------------------------------------------------------
cmd_list() {
  need_sf; info "Listing reports (org: ${ORG:-<default>}) ..."
  sf_rest GET "/services/data/v${API_VERSION}/analytics/reports"
}

cmd_types() {
  need_sf; info "Listing report types ..."
  sf_rest GET "/services/data/v${API_VERSION}/analytics/reportTypes"
}

cmd_get() {  # $1=reportId  [--describe]
  need_sf; [[ -n "${1:-}" ]] || { err "usage: $PROG get <reportId> [--describe]"; exit 2; }
  local id="$1"; shift || true
  local suffix=""; [[ "${1:-}" == "--describe" ]] && suffix="/describe"
  sf_rest GET "/services/data/v${API_VERSION}/analytics/reports/${id}${suffix}"
}

cmd_run() {  # $1=reportId  [--async]
  need_sf; [[ -n "${1:-}" ]] || { err "usage: $PROG run <reportId> [--async]"; exit 2; }
  local id="$1"; shift || true
  if [[ "${1:-}" == "--async" ]]; then
    local body; body="$(mktemp -t sfreport_run.XXXXXX.json)"; printf '{}' > "$body"
    info "Running report ${id} asynchronously ..."
    sf_rest POST "/services/data/v${API_VERSION}/analytics/reports/${id}/instances" "$body"
    /bin/rm -f "$body"
  else
    info "Running report ${id} (synchronous) ..."
    sf_rest GET "/services/data/v${API_VERSION}/analytics/reports/${id}?includeDetails=true"
  fi
}

cmd_clone() {  # --from <id> --name <name> [--gc <value>] [--gc-column <apiName>]
  need_sf
  local from="" name="" gc_arg="" gc_col="$GC_COLUMN_DEFAULT"
  while [[ $# -gt 0 ]]; do case "$1" in
    --from) from="$2"; shift 2;;
    --name) name="$2"; shift 2;;
    --gc) gc_arg="$2"; shift 2;;
    --gc-column) gc_col="$2"; shift 2;;
    *) err "clone: unknown arg $1"; exit 2;;
  esac; done
  [[ -n "$from" && -n "$name" ]] || { err "usage: $PROG clone --from <reportId> --name <name> [--gc <value> --gc-column <apiName>]"; exit 2; }

  info "Fetching source report ${from} ..."
  local desc; desc="$(mktemp -t sfreport_src.XXXXXX.json)"
  sf_rest GET "/services/data/v${API_VERSION}/analytics/reports/${from}/describe" > "$desc"

  local gc; gc="$(resolve_global_company "$gc_arg")"
  local body; body="$(mktemp -t sfreport_body.XXXXXX.json)"
  NAME="$name" GC="$gc" GC_COL="$gc_col" python3 - "$desc" > "$body" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1]))
md = d["reportMetadata"]
md["name"] = os.environ["NAME"]
gc, col = os.environ.get("GC",""), os.environ.get("GC_COL","")
if gc and col:
    filters = md.get("reportFilters") or []
    hit = False
    for f in filters:
        if f.get("column") == col:
            f["value"] = gc; f.setdefault("operator", "equals"); hit = True
    if not hit:
        filters.append({"column": col, "operator": "equals", "value": gc})
    md["reportFilters"] = filters
elif gc and not col:
    print("WARN: --gc given without --gc-column; filter not applied "
          "(set GC_COLUMN_DEFAULT via `setup` or pass --gc-column)", file=sys.stderr)
json.dump({"reportMetadata": md}, sys.stdout)
PY

  info "Creating cloned report '${name}'${gc:+ (filter ${gc_col:-?}=${gc})} ..."
  local out; out="$(sf_rest POST "/services/data/v${API_VERSION}/analytics/reports?cloneId=${from}" "$body")"
  printf '%s\n' "$out"
  printf '%s' "$out" | python3 -c 'import sys,json
try:
  d=json.load(sys.stdin)
  if isinstance(d,dict):
    rid=d.get("attributes",{}).get("reportId")
    if rid: print("Created report: "+rid, file=sys.stderr)
except Exception: pass'
  /bin/rm -f "$desc" "$body"
}

cmd_create() {  # --type <reportTypeApiName> --name <name> [--format TABULAR|SUMMARY|MATRIX]
  need_sf
  local rtype="" name="" fmt="TABULAR"
  while [[ $# -gt 0 ]]; do case "$1" in
    --type) rtype="$2"; shift 2;;
    --name) name="$2"; shift 2;;
    --format) fmt="$2"; shift 2;;
    *) err "create: unknown arg $1"; exit 2;;
  esac; done
  [[ -n "$rtype" && -n "$name" ]] || { err "usage: $PROG create --type <reportTypeApiName> --name <name> [--format TABULAR|SUMMARY|MATRIX]"; exit 2; }

  local body; body="$(mktemp -t sfreport_new.XXXXXX.json)"
  cat > "$body" <<JSON
{ "reportMetadata": {
    "name": "${name}",
    "reportType": { "type": "${rtype}" },
    "reportFormat": "${fmt}",
    "detailColumns": [],
    "reportFilters": []
} }
JSON
  info "Creating report '${name}' (type ${rtype}, ${fmt}) ..."
  info "Note: a bare report has no columns — clone an existing one for a useful start."
  sf_rest POST "/services/data/v${API_VERSION}/analytics/reports" "$body"
  /bin/rm -f "$body"
}

cmd_delete() {  # $1=reportId  [--yes]
  need_sf; [[ -n "${1:-}" ]] || { err "usage: $PROG delete <reportId> [--yes]"; exit 2; }
  local id="$1"; shift || true
  if [[ "${1:-}" != "--yes" ]]; then
    read -r -p "Delete report ${id} on org ${ORG:-<default>}? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { info "aborted"; exit 0; }
  fi
  info "Deleting report ${id} ..."
  local status; status="$(sf_rest DELETE "/services/data/v${API_VERSION}/analytics/reports/${id}")"
  printf '%s\n' "$status"
  echo "$status" | grep -q '204' && ok "Deleted." || { err "Expected HTTP 204, got: $status"; exit 1; }
}

cmd_setup() {  # interactive config writer; non-interactive via flags
  local in_org="" in_api="" in_gc="" in_gccol="" save=1
  while [[ $# -gt 0 ]]; do case "$1" in
    --org) in_org="$2"; shift 2;;
    --api) in_api="$2"; shift 2;;
    --global-company) in_gc="$2"; shift 2;;
    --gc-column) in_gccol="$2"; shift 2;;
    --check-only) save=0; shift;;
    -h|--help) usage; exit 0;;
    *) err "setup: unknown arg $1"; exit 2;;
  esac; done

  # First job of setup: make sure the sf CLI exists (offer to install it).
  need_sf

  # Prompt for anything not supplied on the command line (skip when --check-only).
  if [[ $save -eq 1 ]]; then
    [[ -z "$in_org" ]] && read -r -p "Target org alias or username [${ORG:-<CLI default>}]: " in_org || true
    [[ -z "$in_api" ]] && read -r -p "API version [${API_VERSION}]: " in_api || true
    echo
    echo "Optional — Global Company filter. Useful for GAM / global-account-manager"
    echo "roles that scope reports to one global parent account. Leave blank for any"
    echo "other role."
    [[ -z "$in_gc" ]]    && read -r -p "  Default Global Company value (e.g. 'NTT, Inc.') [${GLOBAL_COMPANY:-}]: " in_gc || true
    [[ -z "$in_gccol" ]] && read -r -p "  Filter column API name (e.g. Account.Global_Company__c) [${GC_COLUMN_DEFAULT:-}]: " in_gccol || true
  fi

  # Apply (flag/prompt wins; else keep current).
  ORG="${in_org:-$ORG}"
  API_VERSION="${in_api:-$API_VERSION}"
  GLOBAL_COMPANY="${in_gc:-${GLOBAL_COMPANY:-}}"
  GC_COLUMN_DEFAULT="${in_gccol:-${GC_COLUMN_DEFAULT:-}}"

  if [[ $save -eq 1 ]]; then
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
# salesforce-reports skill config — written by \`$PROG setup\`
# Org-agnostic: change ORG to point at any org you've authed with the sf CLI.
ORG="${ORG}"
API_VERSION="${API_VERSION}"
# Global Company filter (GAM / global-account roles only; harmless if blank):
GLOBAL_COMPANY="${GLOBAL_COMPANY}"
GC_COLUMN_DEFAULT="${GC_COLUMN_DEFAULT}"
EOF
    ok "Saved config → $CONFIG_FILE"
  fi

  echo
  echo "$PROG — connectivity check"
  echo "  sf CLI:    $(sf version 2>/dev/null | head -1)"
  echo "  org:       ${ORG:-<CLI default>}    api: v${API_VERSION}"
  if [[ -n "$GLOBAL_COMPANY" || -n "$GC_COLUMN_DEFAULT" ]]; then
    echo "  GAM mode:  Global Company '${GLOBAL_COMPANY}' on column '${GC_COLUMN_DEFAULT}'"
  else
    echo "  GAM mode:  off (no Global Company filter — fine for non-GAM roles)"
  fi
  printf '  auth:      '
  if sf_rest GET "/services/data/v${API_VERSION}/analytics/reports?pageSize=1" >/dev/null 2>&1; then
    ok "OK — Analytics REST reachable"
  else
    err "FAILED — run: sf org login web --alias ${ORG:-myorg}"
  fi
}

usage() {
  cat <<EOF
$PROG — Salesforce report tool (Analytics REST via the sf CLI). Org-agnostic.

USAGE
  $PROG <command> [options] [--org <alias>] [--api <version>]

COMMANDS
  setup                         Configure default org/API + optional Global Company,
                                then check auth & API reachability. Writes
                                ${CONFIG_FILE/#$HOME/\~}
                                Non-interactive: $PROG setup --org <alias> --check-only
  list                          List all reports the user can see
  types                         List available report types (use the 'type' for create)
  get <id> [--describe]         Fetch a report (--describe = metadata only)
  run <id> [--async]            Run a report and return rows (sync default)
  create --type <apiName> --name <name> [--format TABULAR|SUMMARY|MATRIX]
                                Create a new empty report of a report type
  clone --from <id> --name <name> [--gc <value> --gc-column <apiName>]
                                Clone an existing report (most reliable create path);
                                optionally re-point its Global Company filter
  delete <id> [--yes]           Delete a report (HTTP 204 on success)

GLOBAL OPTIONS
  --org <alias|username>        Target org (default: saved config, else CLI default)
  --api <version>               API version (default: ${API_VERSION})
  -h, --help                    This help

GLOBAL COMPANY FILTER (GAM roles only)
  Global Account Managers scope reports to one global parent account. Configure a
  default once (\`$PROG setup\`) and every clone can re-point that filter:
     $PROG clone --from <id> --name "NTT Pipeline" \\
           --gc "NTT, Inc." --gc-column Account.Global_Company__c
  Non-GAM roles can ignore this entirely — leave it blank at setup.
  Find the right column on a report:
     $PROG get <id> --describe | python3 -c \\
       'import sys,json;[print(f["column"]) for f in json.load(sys.stdin)["reportMetadata"]["reportFilters"]]'

EXAMPLES
  $PROG setup --org org62
  $PROG list
  $PROG clone --from 00O0M0000097OoCUAU --name "My Pipeline Copy"
  $PROG run 00Oed000009R56TEAS
  $PROG delete 00Oed000009gImXEAU --yes

NOTES
  * Clone is the most reliable create path — Salesforce requires full metadata in
    the POST body even when cloneId is supplied (a bare {} returns BAD_REQUEST).
  * DELETE uses an -f envelope internally (CLI body-handling workaround).
  * curl with the CLI token fails (INVALID_AUTH_HEADER, token is masked) — always
    go through sf, which this script does.
EOF
}

# ---------- arg parse --------------------------------------------------------
[[ $# -eq 0 ]] && { usage; exit 0; }
CMD="$1"; shift || true

# Pull global --org / --api / --help out of the remaining args (setup parses its own).
ARGS=()
if [[ "$CMD" != "setup" ]]; then
  while [[ $# -gt 0 ]]; do case "$1" in
    --org) ORG="$2"; shift 2;;
    --api) API_VERSION="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) ARGS+=("$1"); shift;;
  esac; done
  set -- "${ARGS[@]:-}"
fi

case "$CMD" in
  setup)  cmd_setup "$@" ;;
  list)   cmd_list ;;
  types)  cmd_types ;;
  get)    cmd_get "$@" ;;
  run)    cmd_run "$@" ;;
  create) cmd_create "$@" ;;
  clone)  cmd_clone "$@" ;;
  delete) cmd_delete "$@" ;;
  -h|--help|help) usage ;;
  *) err "Unknown command: $CMD"; echo; usage; exit 2 ;;
esac
