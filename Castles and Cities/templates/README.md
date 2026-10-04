# Add an independent city or castle study

1. Choose a place, realm and reference year. Use lowercase `snake_case` IDs,
   such as a city name plus period. `realm_id` is a research category, not a game
   faction. Choose `city`, `settlement` or `castle` for `study_kind`.
2. Create `realms/<realm_id>/cities/<study_id>/`. Copy
   [study.template.json](study.template.json) into it as `study.json`. Fill in
   every placeholder, the reference year and active snapshot. The incomplete
   template itself is deliberately not a registered study.
3. Create the five documents listed below. Cite sources you actually consulted
   and disclose abstracts, inaccessible full texts and secondary summaries.
4. Add a realm brief and its catalog entry if needed. Register the study's ID,
   realm and manifest path in `catalog.json`, and add a readable row to
   `CATALOG.md`.
5. Run `python3 "Castles and Cities/tools/validate_studies.py"` from the
   repository root. Metadata validation does not establish historical accuracy.

## Document outlines

| File | Required working content |
|---|---|
| `README.md` | Place and date; scope; atmosphere as a design target; anachronism exclusions; actual model status |
| `ATLAS.md` | Topographic framework; district or castle-assembly IDs; capabilities expressed physically; evidence and first deliverable |
| `STAGES.md` | Dated historical snapshots; stable objects and changes; separately labeled creative growth scenarios |
| `SOURCES.md` | Source ID, author/institution, title, URL, locator, access date and extent, supported claims and limits |
| `WORKPLAN.md` | One bounded next package; concrete artifacts; evidence and rendered review gates; honest checkpoint |

Use source headings in this exact form so the validator can resolve references:

```markdown
### `source_id` — short description

- Source: author/institution, title, URL and locator.
- Access: date and what was actually read or inspected.
- Supports: specific claim in original prose.
- Limits: what this source does not establish for the target date.
```

Add stable capability IDs and reference them from districts. Add source IDs to
districts and snapshots. Exactly one historical snapshot is `active_reference`,
matching `active_snapshot_id` and `reference_year_ce`. Earlier/later snapshots
can remain `research_outline` until developed. Add a creative variant only when
it has a real local brief and an identified baseline snapshot; see the schema
for its fields.

Do not copy Constantinople's architecture, evidence or institutions wholesale
into another culture. A castle study can break down into approach, outer works,
gate, ward, residence, service buildings and water infrastructure where supported
by its own sources. A town may organize around several institutions rather than
one universal central hall.

Follow [MODELING.md](../MODELING.md) for coordinates, evidence, CAD/source and
render separation. Keep images and generated exports external. The repository's
[CLAUDE.md](../../CLAUDE.md) remains the architecture contract.
