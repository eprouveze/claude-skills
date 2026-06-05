---
name: namecheap
description: >
  Namecheap domain management via the Namecheap XML API. Check domain availability,
  register/transfer/renew domains, manage DNS records (A, AAAA, CNAME, MX, TXT, etc.),
  list domains, set custom nameservers, manage email forwarding, and check pricing.
  Use when the user says "namecheap", "check domain", "register domain", "DNS records",
  "nameservers", "domain transfer", "renew domain", or "domain pricing".
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, AskUserQuestion
user-invocable: true
version: 0.1.0
last-updated: 2026-06-04
last-consolidated: 2026-06-04
metadata:
  author: Emmanuel Prouveze
  argument-hint: "[subcommand] [args]"
---

# Namecheap Domain Manager

Manage domains via the Namecheap XML API. All commands require credentials configured in environment variables.

## Setup & Authentication

**Required environment variables.** Put them in a `.env` file, your shell rc, or
`~/.config/claude-skills/namecheap.env`. The bundled script will pick them up.

| Variable | Description |
|---|---|
| `NAMECHEAP_API_USER` | Your Namecheap username |
| `NAMECHEAP_API_KEY` | API key from Profile → Tools → API Access |
| `NAMECHEAP_USERNAME` | Usually same as `NAMECHEAP_API_USER` |
| `NAMECHEAP_CLIENT_IP` | Your whitelisted IPv4 address |
| `NAMECHEAP_USE_SANDBOX` | Set to `true` for sandbox mode (default: `false`) |

**First-time setup:** run `scripts/nc_api.sh --setup` to be prompted for each value and
have a `~/.config/claude-skills/namecheap.env` file written for you.

**Get an API key:** sign in at namecheap.com, go to Profile → Tools → API Access, enable
API access, then create a key. The key is shown only once — copy it.

**IP Whitelisting:** Namecheap requires the calling IP to be whitelisted. Only IPv4 is supported. The user must whitelist their IP at Profile > Tools > API Access > Whitelisted IPs.

**Production API requirements** (at least one must be met):
- 20+ domains in the account
- $50+ account balance
- $50+ in purchases within the last 2 years

Sandbox has no requirements — create a free account at `https://www.sandbox.namecheap.com/`.

## API Base URLs

| Environment | URL |
|---|---|
| Production | `https://api.namecheap.com/xml.response` |
| Sandbox | `https://api.sandbox.namecheap.com/xml.response` |

## Rate Limits

- **20 requests/minute**, 700/hour, 8,000/day
- Batch domain checks using comma-separated lists to conserve quota

---

## Subcommands

### `/namecheap check <domain1> [domain2] [...]`

Check domain availability.

**Steps:**
1. Validate credentials are set (run `scripts/nc_api.sh check-env`)
2. Accept one or more domain names as arguments (comma or space separated)
3. Call `scripts/nc_api.sh check "domain1.com,domain2.com"`
4. Parse XML response — display results as a table:

| Domain | Available | Premium | Price | ICANN Fee |
|---|---|---|---|---|
| example.com | No | - | - | - |
| example.net | Yes | No | - | $0.18 |

5. If any are available, ask if the user wants to register one

---

### `/namecheap search <keyword> [tlds]`

Search for available domains across multiple TLDs.

**Steps:**
1. Take a keyword and optional TLD list (default: `com,net,org,io,co,dev,app,ai`)
2. Generate domain combinations: `keyword.com`, `keyword.net`, etc.
3. Call `scripts/nc_api.sh check "<comma-separated-list>"`
4. Display availability table sorted by: available first, then by TLD preference
5. Offer to check pricing for available domains

---

### `/namecheap register <domain> [years]`

Register/purchase a new domain.

**Steps:**
1. Confirm domain is available first (call check if not already confirmed)
2. Check pricing: `scripts/nc_api.sh pricing "com" "REGISTER"` (use appropriate TLD)
3. Display price and ask for confirmation: "Register **example.com** for **N year(s)** at **$X.XX**?"
4. Ask the user for contact information OR check if they have a default address configured
   - If user wants to use an existing address: `scripts/nc_api.sh get-address-list`
   - Let user pick an address or enter new contact details
5. **CRITICAL: Always ask for explicit confirmation before purchasing.** Display the total cost.
6. Call `scripts/nc_api.sh register "<domain>" "<years>" "<contact_params>"`
7. Parse response — display: Domain, Order ID, Transaction ID, Charged Amount, WhoisGuard status
8. If `AddFreeWhoisguard=yes` and `WGEnabled=yes` were included, confirm privacy is active

**Contact fields required** (for Registrant, Tech, Admin, AuxBilling — all four):
`FirstName, LastName, Address1, City, StateProvince, PostalCode, Country, Phone (+1.2125551234 format), EmailAddress`

**Optional:** `OrganizationName, Address2`

---

### `/namecheap list [filter]`

List domains in the account.

**Steps:**
1. Call `scripts/nc_api.sh list "[filter]"` where filter can be: `all` (default), `expiring`, `expired`
2. Optional search term can be passed to filter by keyword
3. Parse XML — display as table:

| Domain | Created | Expires | Auto-Renew | Locked | WhoisGuard | DNS |
|---|---|---|---|---|---|---|
| example.com | 2024-01-15 | 2025-01-15 | Yes | Yes | Enabled | Namecheap |

4. Show paging info if more than one page of results

---

### `/namecheap info <domain>`

Get detailed information about a domain.

**Steps:**
1. Call `scripts/nc_api.sh info "<domain>"`
2. Parse and display:
   - Domain status, ID, owner
   - Created/Expires dates, years registered
   - WhoisGuard status and expiration
   - DNS provider, nameservers list
   - Host record count
   - Modification rights

---

### `/namecheap dns <domain>`

Show current DNS records for a domain.

**Steps:**
1. Split domain into SLD and TLD
2. Call `scripts/nc_api.sh dns-get "<sld>" "<tld>"`
3. Display records as table:

| # | Name | Type | Address | MX Pref | TTL | Active |
|---|---|---|---|---|---|---|
| 1 | @ | A | 1.2.3.4 | - | 1800 | Yes |
| 2 | www | CNAME | example.com | - | 1800 | Yes |
| 3 | @ | MX | mail.example.com | 10 | 1800 | Yes |

---

### `/namecheap dns-set <domain> <action> [records...]`

Manage DNS records for a domain.

**Actions:**
- `add` — Add a record (merges with existing)
- `remove` — Remove a record by index or match
- `replace` — Replace all records with the provided set
- `reset` — Reset to Namecheap default DNS

**Steps for `add`:**
1. Export env vars from `~/.claude/settings.local.json` (see Critical DNS Gotchas §4)
2. Get existing records: `scripts/nc_api.sh dns-get "<sld>" "<tld>"`
3. Parse existing records into a list
4. Ask user for new record details if not provided:
   - Type (A, AAAA, CNAME, MX, TXT, URL, URL301, FRAME)
   - Host (@ for root, www, subdomain name, * for wildcard)
   - Value (IP address, target domain, TXT content, etc.)
   - TTL (default: 1800)
   - MX Priority (only for MX records, default: 10)
5. Merge new record into existing list
6. **CRITICAL: `setHosts` is destructive — it replaces ALL records.** Always send the complete desired record set including all existing records.
7. **If any record contains special characters (+, /, =, spaces) in its value — especially TXT records (DKIM, SPF, DMARC) — use `curl --data-urlencode` directly** instead of the `nc_api.sh` script. See safe pattern below.
8. **If any MX records are present, include `EmailType=MX`** in the POST body (see Critical DNS Gotchas §2).
9. Confirm success and display updated record table

**Safe curl pattern for DNS with special characters:**
```bash
curl -s -X POST "https://api.namecheap.com/xml.response" \
  --data-urlencode "ApiUser=${NAMECHEAP_API_USER}" \
  --data-urlencode "ApiKey=${NAMECHEAP_API_KEY}" \
  --data-urlencode "UserName=${NAMECHEAP_USERNAME}" \
  --data-urlencode "ClientIp=${NAMECHEAP_CLIENT_IP}" \
  --data-urlencode "Command=namecheap.domains.dns.setHosts" \
  --data-urlencode "SLD=example" \
  --data-urlencode "TLD=com" \
  --data-urlencode "EmailType=MX" \
  --data-urlencode "HostName1=@" \
  --data-urlencode "RecordType1=A" \
  --data-urlencode "Address1=1.2.3.4" \
  --data-urlencode "TTL1=1800" \
  --data-urlencode "HostName2=resend._domainkey" \
  --data-urlencode "RecordType2=TXT" \
  --data-urlencode "Address2=p=MIGfMA0GCSqGSIb3DQEB..." \
  --data-urlencode "TTL2=1800"
```

**Steps for `remove`:**
1. Get and display existing records (numbered)
2. Ask which record to remove (by number)
3. Remove from list, send remaining records via `dns-set`

**Steps for `reset`:**
1. Confirm with user
2. Call `scripts/nc_api.sh dns-default "<sld>" "<tld>"`

---

### `/namecheap ns <domain> <action> [nameservers]`

Manage nameservers.

**Actions:**
- `get` — Show current nameservers
- `set` — Set custom nameservers (comma-separated)
- `reset` — Reset to Namecheap default nameservers
- `create` — Create a personal/child nameserver (e.g., ns1.example.com -> IP)

**Steps for `set`:**
1. Call `scripts/nc_api.sh ns-set "<sld>" "<tld>" "ns1.example.com,ns2.example.com"`
2. **Warn:** Custom nameservers disable URL forwarding, email forwarding, and dynamic DNS

**Steps for `create`:**
1. Ask for nameserver hostname and IP
2. Call `scripts/nc_api.sh ns-create "<sld>" "<tld>" "<nameserver>" "<ip>"`

---

### `/namecheap renew <domain> [years]`

Renew a domain registration.

**Steps:**
1. Get domain info to check current expiry
2. Check renewal pricing: `scripts/nc_api.sh pricing "<tld>" "RENEW"`
3. Display: "Renew **example.com** for **N year(s)** at **$X.XX**? Current expiry: YYYY-MM-DD"
4. **Ask for explicit confirmation before charging.**
5. Call `scripts/nc_api.sh renew "<domain>" "<years>"`
6. Display: new expiry, order ID, charged amount

---

### `/namecheap transfer <domain>`

Transfer a domain to Namecheap.

**Steps:**
1. Check transfer pricing: `scripts/nc_api.sh pricing "<tld>" "TRANSFER"`
2. Ask for the EPP/authorization code from the current registrar
3. Display cost and confirm
4. Call `scripts/nc_api.sh transfer "<domain>" "<years>" "<epp_code>"`
5. Display transfer ID and status
6. Note: Transfer typically takes 5-7 days

---

### `/namecheap pricing <tld> [action]`

Check pricing for a TLD.

**Steps:**
1. Action defaults to `REGISTER`. Options: `REGISTER`, `RENEW`, `TRANSFER`, `REACTIVATE`
2. Call `scripts/nc_api.sh pricing "<tld>" "<action>"`
3. Display pricing table:

| Duration | Regular Price | Your Price | Currency |
|---|---|---|---|
| 1 year | $10.98 | $8.88 | USD |
| 2 years | $21.96 | $17.76 | USD |

---

### `/namecheap email <domain> [action]`

Manage email forwarding.

**Actions:**
- `get` — Show current email forwarding rules
- `set` — Set email forwarding (mailbox -> forward-to pairs)

**Steps for `set`:**
1. Ask for mailbox name (e.g., `info`) and forward-to address
2. Can set multiple rules at once
3. Call `scripts/nc_api.sh email-set "<domain>" "<mailbox1>=<forward1>,<mailbox2>=<forward2>"`

---

### `/namecheap balance`

Check account balance.

**Steps:**
1. Call `scripts/nc_api.sh balance`
2. Display: Available Balance, Account Balance, Earned Amount, Withdrawable Amount

---

## Critical DNS Gotchas

These are hard-won lessons. Read before touching DNS records.

### 1. `setHosts` is DESTRUCTIVE
The `setHosts` API **replaces ALL records** on the domain. If you send 2 records, every other record is deleted. **Always** read existing records first (`dns-get`), then include them in the `dns-set` call alongside new records.

### 2. MX records silently dropped in EmailType=FWD mode
By default, Namecheap domains use `EmailType=FWD` (email forwarding). In this mode, **MX records are silently dropped** — the API returns `IsSuccess="true"` but the MX record is simply not created. To fix: include `EmailType=MX` in the setHosts POST body when any MX record is present. This disables Namecheap's email forwarding feature.

### 3. Special characters in TXT values break `curl -d`
DKIM keys, SPF records, and other TXT values often contain `+`, `/`, `=`, spaces, and `~`. These are special in URL-encoded form data (`+` becomes space, `=` delimits params). The `nc_api.sh` script uses plain `curl -d` which does NOT encode values.

**For DNS operations with TXT/DKIM/SPF values, use `curl --data-urlencode` directly** instead of going through the script. See the dns-set section for the safe pattern.

### 4. Env vars must be exported to the script's process
Some users put credentials in a Claude settings file or a vault. Those files don't
automatically export to a shell. Either source them into the shell before invoking
`nc_api.sh`, or rely on the `~/.config/claude-skills/namecheap.env` file the `--setup`
flow creates.

## Anti-patterns

- Registering or renewing a domain without explicit user confirmation and a price display.
- Calling `dns-set` without first reading existing records. It is destructive — all
  records not included in the call get deleted.
- Storing API keys in skill files or scripts. They belong in environment variables.
- Hammering the API. Batch domain checks. Add delays for bulk operations.
- Testing against production. Always sandbox-first.
- Guessing contact information. Ask the user or use a saved address.

## Error handling

- If API returns `Status="ERROR"`, extract `Error@Number` and `Error` text
- Common errors:
  - `2011150` — Missing required parameter
  - `2030280` — Domain not available
  - `2011170` — Invalid domain name
  - `2016166` — Domain locked / cannot modify
  - `4022288` — API access disabled
  - `5050900` — Too many requests (rate limited)
- On rate limit: wait 60 seconds, then retry once
- On auth error: prompt user to verify credentials and IP whitelist

## Known gotchas

- **`setHosts` is destructive** — replaces ALL DNS records on the domain. Read existing
  records first, then send the complete desired set.
- **MX records silently dropped in `EmailType=FWD` mode.** API returns success but the
  record is never created. Include `EmailType=MX` in the call when any MX is present.
- **Special characters in TXT values break `curl -d`.** DKIM, SPF, and DMARC values
  contain `+`, `/`, `=`, spaces. Use `curl --data-urlencode` for DNS writes.
- **Production API requirements:** 20+ domains, $50+ balance, or $50+ in 2-year
  purchases. Sandbox is unrestricted.

## Validated patterns

- Always check availability and price *before* registering. Display the total cost and
  ask for explicit confirmation. The 30-second pause between check and register has
  saved registrations more than once.
- Use the sandbox endpoint for the first run of any new DNS script. The XML API errors
  in production are not always clear; the sandbox surfaces them faster.

## Self-improvement

This skill ships with a lightweight feedback loop. Adopt or ignore — the skill works
without it.

Trigger a review when:

- The user explicitly disagrees with a DNS change (strongest signal — log immediately;
  2–3 corrections on the same theme → promote to body).
- A new Namecheap API behavior surfaces (silent dropped records, new auth error code).
- `learnings.md` crosses ~100 bullets (consolidation time).
- The skill mis-triggers or fails to trigger.
- Namecheap publishes a breaking API change.

Consolidation pass (5–10 min, weekly or threshold-driven):

- Each entry gets one fate: apply, capture, or dismiss.
- Apply = merge into Known gotchas / Anti-patterns / Validated patterns.
- Capture = leave in `learnings.md` for now.
- Dismiss = delete.
- Bump `last-consolidated:` in frontmatter.
