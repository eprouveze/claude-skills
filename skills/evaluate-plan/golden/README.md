# evaluate-plan golden cases

Five (source-doc, plan, expected-gaps) triples. Run the skill against each pair and check
that the reported coverage and top gaps match.

## Cases

- `01-explicit-feature-drop/` — Source lists 8 features; plan covers 5. Expected: 3 missing items, coverage 62.5%.
- `02-implicit-spotlight/` — Source says "like Spotlight"; plan addresses only the search input. Expected: 4 implicit behaviors flagged (hotkey, float, escape, fuzzy).
- `03-misinterpreted/` — Source says "soft delete"; plan implements hard delete. Expected: 1 misinterpreted.
- `04-perfect/` — Source has 5 features; plan covers all 5 with specifics. Expected: 100%.
- `05-why-dropped/` — Source includes a rationale section the plan omits. Expected: rationale flagged as a gap.

Each case contains `source.md`, `plan.md`, and `expected.json`.
