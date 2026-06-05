#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Namecheap API wrapper script.
# All requests go through this script for consistent auth and error handling.
#
# Required env vars:
#   NAMECHEAP_API_USER    - API username
#   NAMECHEAP_API_KEY     - API key
#   NAMECHEAP_USERNAME    - Account username (usually same as API_USER)
#   NAMECHEAP_CLIENT_IP   - Whitelisted IPv4 address
#   NAMECHEAP_USE_SANDBOX - "true" for sandbox (default: false)
#
# Config file (auto-loaded if present): ~/.config/claude-skills/namecheap.env
# Run `nc_api.sh --setup` to create it interactively.

set -euo pipefail

# --- Auto-load config if present ---
CONFIG_FILE="${HOME}/.config/claude-skills/namecheap.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$CONFIG_FILE"; set +a
fi

# --- Handle --help and --setup before anything else ---
case "${1:-}" in
  --help|-h)
    cat <<'EOF'
nc_api.sh — Namecheap API wrapper

Usage:
  nc_api.sh --help                       Show this help
  nc_api.sh --setup                      Interactive config (writes ~/.config/claude-skills/namecheap.env)
  nc_api.sh check-env                    Verify credentials are loaded
  nc_api.sh check <domains>              Check availability (comma-separated)
  nc_api.sh list [all|expiring|expired] [search]
  nc_api.sh info <domain>                Domain details
  nc_api.sh dns-get <sld> <tld>          Read DNS records
  nc_api.sh dns-set <sld> <tld> <params> Write DNS records (destructive)
  nc_api.sh ns-set <sld> <tld> <ns1,ns2> Set nameservers
  nc_api.sh register <domain> <years> <params>
  nc_api.sh renew <domain> [years]
  nc_api.sh pricing <tld> [REGISTER|RENEW|TRANSFER]
  nc_api.sh balance                      Account balance
  nc_api.sh help                         Full command list

Env vars: NAMECHEAP_API_USER, NAMECHEAP_API_KEY, NAMECHEAP_USERNAME,
          NAMECHEAP_CLIENT_IP, NAMECHEAP_USE_SANDBOX
EOF
    exit 0
    ;;
  --setup)
    mkdir -p "${HOME}/.config/claude-skills"
    echo "Namecheap API setup"
    echo "==================="
    echo "Get your API key: namecheap.com -> Profile -> Tools -> API Access"
    echo "Whitelist your IPv4 in the same UI."
    echo ""
    read -rp "API user: " API_USER_IN
    read -rp "API key: " API_KEY_IN
    read -rp "Username (usually same as API user) [${API_USER_IN}]: " USERNAME_IN
    USERNAME_IN="${USERNAME_IN:-$API_USER_IN}"
    read -rp "Whitelisted IPv4: " CLIENT_IP_IN
    read -rp "Use sandbox? (true/false) [false]: " SANDBOX_IN
    SANDBOX_IN="${SANDBOX_IN:-false}"

    cat > "$CONFIG_FILE" <<EOF
NAMECHEAP_API_USER="${API_USER_IN}"
NAMECHEAP_API_KEY="${API_KEY_IN}"
NAMECHEAP_USERNAME="${USERNAME_IN}"
NAMECHEAP_CLIENT_IP="${CLIENT_IP_IN}"
NAMECHEAP_USE_SANDBOX="${SANDBOX_IN}"
EOF
    chmod 600 "$CONFIG_FILE"
    echo ""
    echo "Wrote $CONFIG_FILE (mode 600)."
    echo "Run 'nc_api.sh check-env' to verify."
    exit 0
    ;;
esac

# --- Configuration ---
if [[ "${NAMECHEAP_USE_SANDBOX:-false}" == "true" ]]; then
  API_URL="https://api.sandbox.namecheap.com/xml.response"
else
  API_URL="https://api.namecheap.com/xml.response"
fi

API_USER="${NAMECHEAP_API_USER:-}"
API_KEY="${NAMECHEAP_API_KEY:-}"
USERNAME="${NAMECHEAP_USERNAME:-$API_USER}"
CLIENT_IP="${NAMECHEAP_CLIENT_IP:-}"

# --- Helpers ---
check_env() {
  local missing=()
  [[ -z "$API_USER" ]] && missing+=("NAMECHEAP_API_USER")
  [[ -z "$API_KEY" ]] && missing+=("NAMECHEAP_API_KEY")
  [[ -z "$CLIENT_IP" ]] && missing+=("NAMECHEAP_CLIENT_IP")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required environment variables: ${missing[*]}"
    echo ""
    echo "Run 'nc_api.sh --setup' to write them to ~/.config/claude-skills/namecheap.env,"
    echo "or export them in your shell before calling this script."
    exit 1
  fi
  echo "OK: credentials configured. Environment: $([ "${NAMECHEAP_USE_SANDBOX:-false}" = "true" ] && echo "SANDBOX" || echo "PRODUCTION")"
}

api_call() {
  local command="$1"
  shift
  local extra_params="$*"

  local url="${API_URL}?ApiUser=${API_USER}&ApiKey=${API_KEY}&UserName=${USERNAME}&ClientIp=${CLIENT_IP}&Command=namecheap.${command}"
  if [[ -n "$extra_params" ]]; then
    url="${url}&${extra_params}"
  fi

  local response
  response=$(curl -s --max-time 30 "$url" 2>&1)
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "ERROR: API request failed (curl exit code: $exit_code)"
    exit 1
  fi

  echo "$response"
}

api_post() {
  local command="$1"
  shift
  local post_data="ApiUser=${API_USER}&ApiKey=${API_KEY}&UserName=${USERNAME}&ClientIp=${CLIENT_IP}&Command=namecheap.${command}"
  if [[ $# -gt 0 ]]; then
    post_data="${post_data}&$*"
  fi

  local response
  response=$(curl -s --max-time 30 -X POST -d "$post_data" "$API_URL" 2>&1)
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "ERROR: API request failed (curl exit code: $exit_code)"
    exit 1
  fi

  echo "$response"
}

split_domain() {
  local domain="$1"
  # Handle multi-part TLDs like co.uk, com.au
  local sld tld
  if echo "$domain" | grep -qE '\.(co|com|net|org|ac)\.[a-z]{2}$'; then
    sld=$(echo "$domain" | sed 's/\.\([^.]*\.[^.]*\)$//')
    tld=$(echo "$domain" | sed 's/^[^.]*\.//')
  else
    sld=$(echo "$domain" | sed 's/\.[^.]*$//')
    tld=$(echo "$domain" | sed 's/^.*\.//')
  fi
  echo "$sld $tld"
}

# --- Commands ---
cmd_check() {
  local domains="$1"
  api_call "domains.check" "DomainList=${domains}"
}

cmd_list() {
  local list_type="${1:-ALL}"
  local search="${2:-}"
  local params="ListType=${list_type}&PageSize=100"
  [[ -n "$search" ]] && params="${params}&SearchTerm=${search}"
  api_call "domains.getList" "$params"
}

cmd_info() {
  local domain="$1"
  api_call "domains.getInfo" "DomainName=${domain}"
}

cmd_dns_get() {
  local sld="$1"
  local tld="$2"
  api_call "domains.dns.getHosts" "SLD=${sld}&TLD=${tld}"
}

cmd_dns_set() {
  local sld="$1"
  local tld="$2"
  shift 2
  local records_params="$*"
  api_post "domains.dns.setHosts" "SLD=${sld}&TLD=${tld}&${records_params}"
}

cmd_dns_default() {
  local sld="$1"
  local tld="$2"
  api_call "domains.dns.setDefault" "SLD=${sld}&TLD=${tld}"
}

cmd_ns_get() {
  local sld="$1"
  local tld="$2"
  api_call "domains.dns.getList" "SLD=${sld}&TLD=${tld}"
}

cmd_ns_set() {
  local sld="$1"
  local tld="$2"
  local nameservers="$3"
  api_call "domains.dns.setCustom" "SLD=${sld}&TLD=${tld}&Nameservers=${nameservers}"
}

cmd_ns_create() {
  local sld="$1"
  local tld="$2"
  local nameserver="$3"
  local ip="$4"
  api_call "domains.ns.create" "SLD=${sld}&TLD=${tld}&Nameserver=${nameserver}&IP=${ip}"
}

cmd_register() {
  local domain="$1"
  local years="$2"
  shift 2
  local contact_params="$*"
  api_post "domains.create" "DomainName=${domain}&Years=${years}&AddFreeWhoisguard=yes&WGEnabled=yes&${contact_params}"
}

cmd_renew() {
  local domain="$1"
  local years="${2:-1}"
  api_call "domains.renew" "DomainName=${domain}&Years=${years}"
}

cmd_transfer() {
  local domain="$1"
  local years="${2:-1}"
  local epp_code="$3"
  api_call "domains.transfer.create" "DomainName=${domain}&Years=${years}&EPPCode=${epp_code}"
}

cmd_pricing() {
  local tld="$1"
  local action="${2:-REGISTER}"
  api_call "users.getPricing" "ProductType=DOMAIN&ActionName=${action}&ProductName=${tld}"
}

cmd_balance() {
  api_call "users.getBalances"
}

cmd_email_get() {
  local domain="$1"
  api_call "domains.dns.getEmailForwarding" "DomainName=${domain}"
}

cmd_email_set() {
  local domain="$1"
  shift
  local forwarding_params="$*"
  api_call "domains.dns.setEmailForwarding" "DomainName=${domain}&${forwarding_params}"
}

cmd_get_address_list() {
  api_call "users.address.getList"
}

cmd_get_address() {
  local address_id="$1"
  api_call "users.address.getInfo" "AddressId=${address_id}"
}

cmd_contacts() {
  local domain="$1"
  api_call "domains.getContacts" "DomainName=${domain}"
}

cmd_lock_get() {
  local domain="$1"
  api_call "domains.getRegistrarLock" "DomainName=${domain}"
}

cmd_lock_set() {
  local domain="$1"
  local action="$2"  # LOCK or UNLOCK
  api_call "domains.setRegistrarLock" "DomainName=${domain}&LockAction=${action}"
}

cmd_tld_list() {
  api_call "domains.getTldList"
}

cmd_transfer_status() {
  local transfer_id="$1"
  api_call "domains.transfer.getStatus" "TransferID=${transfer_id}"
}

# --- Main dispatcher ---
case "${1:-help}" in
  check-env)
    check_env
    ;;
  check)
    cmd_check "$2"
    ;;
  list)
    cmd_list "${2:-ALL}" "${3:-}"
    ;;
  info)
    cmd_info "$2"
    ;;
  dns-get)
    cmd_dns_get "$2" "$3"
    ;;
  dns-set)
    cmd_dns_set "$2" "$3" "${@:4}"
    ;;
  dns-default)
    cmd_dns_default "$2" "$3"
    ;;
  ns-get)
    cmd_ns_get "$2" "$3"
    ;;
  ns-set)
    cmd_ns_set "$2" "$3" "$4"
    ;;
  ns-create)
    cmd_ns_create "$2" "$3" "$4" "$5"
    ;;
  register)
    cmd_register "$2" "$3" "${@:4}"
    ;;
  renew)
    cmd_renew "$2" "${3:-1}"
    ;;
  transfer)
    cmd_transfer "$2" "${3:-1}" "$4"
    ;;
  pricing)
    cmd_pricing "$2" "${3:-REGISTER}"
    ;;
  balance)
    cmd_balance
    ;;
  email-get)
    cmd_email_get "$2"
    ;;
  email-set)
    cmd_email_set "$2" "${@:3}"
    ;;
  address-list)
    cmd_get_address_list
    ;;
  address)
    cmd_get_address "$2"
    ;;
  contacts)
    cmd_contacts "$2"
    ;;
  lock-get)
    cmd_lock_get "$2"
    ;;
  lock-set)
    cmd_lock_set "$2" "$3"
    ;;
  tld-list)
    cmd_tld_list
    ;;
  transfer-status)
    cmd_transfer_status "$2"
    ;;
  help)
    echo "Namecheap API CLI"
    echo ""
    echo "Usage: nc_api.sh <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  check-env                           Verify credentials are set"
    echo "  check <domains>                     Check availability (comma-separated)"
    echo "  list [all|expiring|expired] [search] List domains"
    echo "  info <domain>                       Get domain details"
    echo "  dns-get <sld> <tld>                 Get DNS records"
    echo "  dns-set <sld> <tld> <params>        Set DNS records (POST)"
    echo "  dns-default <sld> <tld>             Reset to default DNS"
    echo "  ns-get <sld> <tld>                  Get nameservers"
    echo "  ns-set <sld> <tld> <ns1,ns2>        Set custom nameservers"
    echo "  ns-create <sld> <tld> <ns> <ip>     Create child nameserver"
    echo "  register <domain> <years> <params>  Register domain (POST)"
    echo "  renew <domain> [years]              Renew domain"
    echo "  transfer <domain> [years] <epp>     Transfer domain in"
    echo "  pricing <tld> [action]              Check pricing"
    echo "  balance                             Account balance"
    echo "  email-get <domain>                  Get email forwarding"
    echo "  email-set <domain> <params>         Set email forwarding"
    echo "  address-list                        List saved addresses"
    echo "  address <id>                        Get address details"
    echo "  contacts <domain>                   Get domain contacts"
    echo "  lock-get <domain>                   Get registrar lock status"
    echo "  lock-set <domain> LOCK|UNLOCK       Set registrar lock"
    echo "  tld-list                            List available TLDs"
    echo "  transfer-status <id>                Check transfer status"
    ;;
  *)
    echo "Unknown command: $1"
    echo "Run: nc_api.sh help"
    exit 1
    ;;
esac
