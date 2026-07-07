---
name: meeting-prep
description: >
  Prepare briefing documents for upcoming external meetings. Reads the user's
  calendar (gcalcli, a Google Calendar CLI, an exported .ics file, or pasted
  text — whichever is available), then researches each external company and
  its public representatives using ONLY public web sources, and writes one
  briefing document per meeting into a local folder. Use when the user says
  "prep my meetings", "meeting prep", "brief me on next week's meetings",
  "who am I meeting this week", "prepare briefings for my calendar", or asks
  to research the companies/people they are about to meet.
version: "1.0.0"
allowed-tools: Read, Write, Bash, Glob, WebSearch, WebFetch
metadata:
  argument-hint: "[days ahead, default 7] [path to .ics file if using an export]"
---

# Meeting Prep — one researched briefing per upcoming meeting

For each meeting in the next N days (default 7), produce a briefing document
covering the company, recent news, the people you're meeting, the competitive
landscape, suggested talking points, and open questions — researched from
public web sources only.

## What this skill sends over the network (read this first)

This skill is designed to be safe to use with a work calendar:

- **Sent over the network:** ONLY public search queries built from the
  external company/organization name and the public names + job titles of
  people you are meeting (e.g. "Acme Corp recent news", "Jane Doe Acme Corp
  VP Sales"). These go through the normal web search tools.
- **NEVER sent over the network:** attendee email addresses, meeting titles,
  meeting descriptions/agendas, meeting locations or links, internal document
  contents, customer data, or anything else from your calendar. Calendar
  parsing happens entirely on your machine.
- **Internal meetings are skipped, not researched.** A meeting whose
  attendees are all on your own email domain is listed in the summary with a
  "skipped — internal" note and no web search is performed for it.

If a meeting title or description contains something that looks like the only
clue to who the external party is, do NOT search for that text. Ask the user
instead: "Who is the external company in '<meeting title>'?"

## Setup (copy-paste friendly — no technical background needed)

1. **Where to put this folder.** Place the `meeting-prep` folder inside the
   `skills` folder of your Claude configuration:
   - Mac: `~/.claude/skills/meeting-prep/` (in Terminal:
     `mkdir -p ~/.claude/skills && cp -R meeting-prep ~/.claude/skills/`)
   - Windows: `C:\Users\<you>\.claude\skills\meeting-prep\`
   - Or, for one project only: `<project folder>/.claude/skills/meeting-prep/`
2. **How to invoke.** Open Claude Code in any folder and type:
   `/meeting-prep` — or just say "prep my meetings for next week".
   To change the window: "prep my meetings for the next 3 days".
3. **What to expect.** Claude will (a) tell you which calendar source it found,
   (b) show you the list of meetings it plans to research and ask you to
   confirm, (c) research each external meeting (this takes a few minutes),
   and (d) write one file per meeting into a `meeting-briefings/` folder in
   your current directory, then tell you where they are.
4. **Troubleshooting.**
   - *"It says no calendar found."* Export your calendar as a file (see the
     export instructions below) and say: "use the file Downloads/mycalendar.ics".
   - *"It researched the wrong company."* Company names are guessed from
     attendee email domains — correct it in chat ("that meeting is with
     Contoso, not Acme") and ask it to redo that one briefing.
   - *"A meeting is missing."* Recurring-event handling in the file parser is
     basic (see limitations at the top of `scripts/parse_ics.py`). Paste the
     missing meeting in chat and it will be included.
   - *"It's asking permission to run things."* That's normal — approve the
     calendar-reading commands. Nothing is sent anywhere except the public
     web searches described above.

## Phase 1 — Detect the calendar source (in this order)

Work down this ladder and STOP at the first source that works. Always tell the
user which mode you're in, e.g. "Reading your calendar via gcalcli."

1. **gcalcli** (a free Google Calendar command-line tool). Check with
   `command -v gcalcli`. If present, use
   `gcalcli agenda --nocolor --details end --details location --tsv "$(date +%Y-%m-%d)" "$(date -v+7d +%Y-%m-%d 2>/dev/null || date -d '+7 days' +%Y-%m-%d)"`
   (adjust the day count to N). Note: gcalcli's TSV output does not include
   attendee emails; treat every meeting as potentially external and confirm
   the company with the user from the meeting title — without searching the
   title itself (see privacy section).
2. **Any other Google Calendar CLI already installed** (check
   `command -v gcal khal calendar 2>/dev/null`). If one exists, read the next
   N days with its agenda/list command.
3. **An exported .ics file.** If the user gave a path, or a `*.ics` file
   exists in the current folder or `~/Downloads` (newest first — confirm with
   the user before using one you found yourself), parse it locally:
   `python3 scripts/parse_ics.py <file.ics> --days 7 --json`
   (the script is inside this skill folder; use its full path). It needs only
   Python 3 — no installs.

   **How to export (tell the user this when no file exists):**
   - *Google Calendar:* calendar.google.com → gear icon → **Settings** →
     **Import & export** → **Export**. You get a .zip; double-click it and
     use the .ics file inside.
   - *Outlook (new Outlook / web):* outlook.office.com → **Calendar** → gear
     icon → **Calendar** → **Shared calendars** → publish your calendar and
     download the ICS link — or in classic Outlook desktop: **File** →
     **Save Calendar** → set the date range → save as .ics.
4. **Pasted text (always works).** Ask the user: "Paste your meetings for the
   next week — one per line, like: `Tue 10:00 — Acme Corp intro call — with
   Jane Doe (VP Sales)`." Parse what they paste.

## Phase 2 — Build the meeting list and classify

1. Determine the user's own email domain: from the calendar data (organizer/
   attendee marked as self) or by asking ("What's your work email domain,
   e.g. yourcompany.com?"). Public mail domains (gmail.com, outlook.com,
   yahoo.*, icloud.com, hotmail.com) never count as an "internal" domain.
2. For each meeting in the window:
   - **Internal** (every attendee on the user's domain, or no external
     attendee identifiable): mark "skipped — internal", do not research.
   - **External**: derive the organization from the external attendees'
     email domains (`jane@acme.com` → "Acme"; verify the proper company name
     via a public search for the domain, e.g. "acme.com company"). Searching
     a bare domain name is allowed — it identifies a company, not a person.
     Never search a full email address.
   - **Ambiguous** (no attendee data, e.g. gcalcli mode or pasted titles):
     ask the user which meetings are external and with whom.
3. Show the user the table — date/time, meeting, company, external/internal/
   skipped — and get a quick confirmation before spending time on research.

## Phase 3 — Research each external meeting (public web only)

For each external meeting, run these searches with WebSearch and read the
best sources with WebFetch. Query material is restricted to: the company
name, its public website domain, and public person names + titles. Nothing
else from the calendar goes into a query.

1. **Company snapshot:** "<Company> company overview", the company's own
   about page, size/HQ/funding if public.
2. **Recent news:** "<Company> news <current year>" — keep only dated,
   citable items from the last ~6 months; note the date and source URL for
   each.
3. **People:** for each external attendee whose name is public (or that the
   user provided): "<Name> <Company>" — role, background, recent public
   activity (talks, posts, interviews). If nothing public is found, say so;
   never speculate.
4. **Competitive landscape:** "<Company> competitors", "<Company> vs" — 2-4
   named competitors and how the company positions itself.
5. Prefer primary sources (company site, press releases, filings) over
   aggregators. Every factual claim in the briefing gets a source URL and,
   for news, a date. Mark anything uncertain as "unverified".

Research meetings in parallel where the tools allow it; a 5-meeting week
should not be done strictly one at a time.

## Phase 4 — Write the briefings

1. Create `meeting-briefings/` in the current working directory.
2. For each external meeting write
   `meeting-briefings/YYYY-MM-DD-<company-slug>.md` using
   `templates/briefing-template.md` (in this skill folder) — fill every
   section; write "Nothing public found" rather than deleting a section or
   inventing content.
3. Finish with a summary message: meetings found, briefings written (with
   file paths), internal meetings skipped, and anything that needs the
   user's input (ambiguous companies, people with no public footprint).
