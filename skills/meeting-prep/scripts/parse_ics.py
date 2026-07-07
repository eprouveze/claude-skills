#!/usr/bin/env python3
"""parse_ics.py — list upcoming meetings from a .ics calendar export.

Pure Python 3 standard library. No pip installs needed.

Usage:
    python3 parse_ics.py <calendar.ics> [--days N] [--json]

Output (default): human-readable list of events in the next N days (default 7).
With --json: a JSON array of event objects, one per occurrence:
    {
      "summary": str,
      "start": "YYYY-MM-DDTHH:MM:SS" (local wall time) or "YYYY-MM-DD" for all-day,
      "end": same format or null,
      "all_day": bool,
      "location": str or null,
      "organizer": email str or null,
      "attendees": [{"email": str, "name": str or null}, ...],
      "description": str or null,
      "recurring": bool
    }

Known limitations (kept simple on purpose):
  * Recurring events: expands FREQ=DAILY and FREQ=WEEKLY (with INTERVAL,
    BYDAY, UNTIL, COUNT) naively. MONTHLY/YEARLY rules are NOT expanded --
    the event is listed once at its first start if it falls in the window,
    and flagged. EXDATE exceptions ARE honored; modified single occurrences
    (RECURRENCE-ID overrides) replace their generated instance when possible
    but intricate override chains may duplicate.
  * Timezones: uses the TZID on each event via Python's zoneinfo when the
    zone is known to the OS; otherwise falls back to treating the time as
    local wall time. UTC ("Z") times are converted to local time.
  * VTIMEZONE definitions embedded in the file are ignored (zoneinfo is
    used instead).
"""

import json
import re
import sys
from datetime import date, datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:  # < 3.9
    ZoneInfo = None

LOCAL_TZ = datetime.now().astimezone().tzinfo


def unfold(text):
    """RFC 5545 line unfolding: a line starting with space/tab continues the previous one."""
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def parse_prop(line):
    """Split 'NAME;PARAM=x;PARAM=y:value' -> (name, {param: value}, value)."""
    if ":" not in line:
        return None
    head, _, value = line.partition(":")
    parts = head.split(";")
    name = parts[0].upper()
    params = {}
    for p in parts[1:]:
        if "=" in p:
            k, _, v = p.partition("=")
            params[k.upper()] = v.strip('"')
    return name, params, value


def unescape(value):
    return (
        value.replace("\\n", "\n")
        .replace("\\N", "\n")
        .replace("\\,", ",")
        .replace("\\;", ";")
        .replace("\\\\", "\\")
    )


def get_tz(tzid):
    if not tzid or ZoneInfo is None:
        return None
    try:
        return ZoneInfo(tzid)
    except Exception:
        # Common vendor forms like "(UTC+09:00) Osaka, Sapporo, Tokyo" or
        # Outlook names won't resolve; fall back to local wall time.
        return None


def parse_dt(value, params):
    """Return (datetime_or_date, all_day). Datetimes are converted to local time."""
    value = value.strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        return date(int(value[:4]), int(value[4:6]), int(value[6:8])), True
    m = re.fullmatch(r"(\d{8})T(\d{6})(Z?)", value)
    if not m:
        return None, False
    d, t, z = m.groups()
    dt = datetime(
        int(d[:4]), int(d[4:6]), int(d[6:8]), int(t[:2]), int(t[2:4]), int(t[4:6])
    )
    if z == "Z":
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        tz = get_tz(params.get("TZID"))
        dt = dt.replace(tzinfo=tz or LOCAL_TZ)
    return dt.astimezone(LOCAL_TZ), False


def parse_rrule(value):
    rule = {}
    for part in value.split(";"):
        if "=" in part:
            k, _, v = part.partition("=")
            rule[k.upper()] = v
    return rule


WEEKDAYS = {"MO": 0, "TU": 1, "WE": 2, "TH": 3, "FR": 4, "SA": 5, "SU": 6}


def expand_rrule(event, window_start, window_end):
    """Yield occurrence start datetimes for DAILY/WEEKLY rules inside the window."""
    rule = event["rrule"]
    freq = rule.get("FREQ", "").upper()
    start = event["start"]
    if freq not in ("DAILY", "WEEKLY"):
        # Not expanded -- caller lists the first occurrence only, flagged.
        return None
    interval = int(rule.get("INTERVAL", 1) or 1)
    count = int(rule["COUNT"]) if rule.get("COUNT") else None
    until = None
    if rule.get("UNTIL"):
        u, u_all_day = parse_dt(rule["UNTIL"], {})
        until = u if not u_all_day else datetime.combine(u, datetime.max.time(), LOCAL_TZ)

    if isinstance(start, date) and not isinstance(start, datetime):
        cursor = datetime.combine(start, datetime.min.time(), LOCAL_TZ)
        all_day = True
    else:
        cursor = start
        all_day = False

    if freq == "WEEKLY" and rule.get("BYDAY"):
        bydays = sorted(
            WEEKDAYS[d] for d in rule["BYDAY"].split(",") if d in WEEKDAYS
        )
    else:
        bydays = [cursor.weekday()]

    occurrences = []
    emitted = 0
    # Monday 00:00 of the start week; time-of-day is re-applied per candidate.
    week_anchor = (cursor - timedelta(days=cursor.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    step = timedelta(days=interval) if freq == "DAILY" else timedelta(weeks=interval)
    guard = 0
    while guard < 1000:
        guard += 1
        if freq == "DAILY":
            candidates = [cursor]
        else:
            candidates = [
                (week_anchor + timedelta(days=wd)).replace(
                    hour=cursor.hour, minute=cursor.minute, second=cursor.second
                )
                for wd in bydays
            ]
            candidates = [c for c in candidates if c >= cursor]
        for c in candidates:
            if c < cursor and freq == "WEEKLY":
                continue
            emitted += 1
            if count and emitted > count:
                return occurrences
            if until and c > until:
                return occurrences
            if c > window_end:
                return occurrences
            if c >= window_start or (all_day and c.date() >= window_start.date()):
                occurrences.append(c.date() if all_day else c)
        if freq == "DAILY":
            cursor = cursor + step
            if cursor > window_end:
                return occurrences
        else:
            week_anchor = week_anchor + step
            if week_anchor > window_end + timedelta(days=7):
                return occurrences
    return occurrences


def parse_events(lines):
    events = []
    cur = None
    for line in lines:
        stripped = line.strip()
        if stripped == "BEGIN:VEVENT":
            cur = {"attendees": [], "exdates": set(), "rrule": None}
            continue
        if stripped == "END:VEVENT":
            if cur and cur.get("start") is not None:
                events.append(cur)
            cur = None
            continue
        if cur is None:
            continue
        prop = parse_prop(line)
        if not prop:
            continue
        name, params, value = prop
        if name == "DTSTART":
            cur["start"], cur["all_day"] = parse_dt(value, params)
        elif name == "DTEND":
            cur["end"], _ = parse_dt(value, params)
        elif name == "SUMMARY":
            cur["summary"] = unescape(value)
        elif name == "LOCATION":
            cur["location"] = unescape(value)
        elif name == "DESCRIPTION":
            cur["description"] = unescape(value)
        elif name == "ORGANIZER":
            cur["organizer"] = value.replace("mailto:", "").replace("MAILTO:", "")
        elif name == "ATTENDEE":
            email = value.replace("mailto:", "").replace("MAILTO:", "")
            cur["attendees"].append({"email": email, "name": params.get("CN")})
        elif name == "RRULE":
            cur["rrule"] = parse_rrule(value)
        elif name == "EXDATE":
            for v in value.split(","):
                dt, ad = parse_dt(v, params)
                if dt is not None:
                    cur["exdates"].add(dt if ad else dt.replace(second=0, microsecond=0))
        elif name == "STATUS":
            cur["status"] = value.upper()
        elif name == "RECURRENCE-ID":
            cur["recurrence_id"], _ = parse_dt(value, params)
    return events


def fmt(value):
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%dT%H:%M:%S")
    if isinstance(value, date):
        return value.isoformat()
    return None


def in_window(start, window_start, window_end):
    if isinstance(start, datetime):
        return window_start <= start <= window_end
    return window_start.date() <= start <= window_end.date()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv
    days = 7
    if "--days" in sys.argv:
        try:
            days = int(sys.argv[sys.argv.index("--days") + 1])
        except (IndexError, ValueError):
            print("error: --days needs a number, e.g. --days 7", file=sys.stderr)
            sys.exit(2)
    if not args:
        print(__doc__)
        sys.exit(2)
    try:
        with open(args[0], encoding="utf-8", errors="replace") as f:
            lines = unfold(f.read())
    except OSError as e:
        print(f"error: cannot read {args[0]}: {e}", file=sys.stderr)
        sys.exit(1)

    now = datetime.now(LOCAL_TZ)
    window_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    window_end = window_start + timedelta(days=days)

    results = []
    for ev in parse_events(lines):
        if ev.get("status") == "CANCELLED":
            continue
        base = {
            "summary": ev.get("summary", "(no title)"),
            "location": ev.get("location"),
            "organizer": ev.get("organizer"),
            "attendees": ev["attendees"],
            "description": ev.get("description"),
            "all_day": ev.get("all_day", False),
            "recurring": ev.get("rrule") is not None,
        }
        duration = None
        if ev.get("end") is not None and isinstance(ev["start"], datetime) and isinstance(ev.get("end"), datetime):
            duration = ev["end"] - ev["start"]

        if ev.get("rrule"):
            occ = expand_rrule(ev, window_start, window_end)
            if occ is None:
                # MONTHLY/YEARLY etc: not expanded
                if in_window(ev["start"], window_start, window_end):
                    results.append({**base, "start": fmt(ev["start"]), "end": fmt(ev.get("end")),
                                    "note": "recurring rule not expanded (only DAILY/WEEKLY supported); verify date manually"})
                continue
            for o in occ:
                key = o.replace(second=0, microsecond=0) if isinstance(o, datetime) else o
                if any((isinstance(x, datetime) and isinstance(key, datetime) and x == key) or
                       (isinstance(x, datetime) and not isinstance(key, datetime) and x.date() == key)
                       for x in ev["exdates"]):
                    continue
                end = fmt(o + duration) if duration and isinstance(o, datetime) else fmt(ev.get("end")) if not ev.get("rrule") else None
                results.append({**base, "start": fmt(o), "end": end})
        else:
            if in_window(ev["start"], window_start, window_end):
                results.append({**base, "start": fmt(ev["start"]), "end": fmt(ev.get("end"))})

    results.sort(key=lambda r: r["start"])

    if as_json:
        print(json.dumps(results, indent=2, ensure_ascii=False))
        return

    if not results:
        print(f"No events found in the next {days} days.")
        return
    print(f"Events in the next {days} days ({len(results)}):\n")
    for r in results:
        when = r["start"] + (" (all day)" if r["all_day"] else "")
        print(f"* {when}  {r['summary']}")
        if r.get("location"):
            print(f"    location: {r['location']}")
        if r["attendees"]:
            ppl = ", ".join(a["email"] for a in r["attendees"][:8])
            print(f"    attendees: {ppl}")
        if r.get("note"):
            print(f"    NOTE: {r['note']}")
    print("\nTip: add --json for machine-readable output.")


if __name__ == "__main__":
    main()
