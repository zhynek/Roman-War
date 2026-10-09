# Tools — what each script is for

Index of the parent campaign's tools (October 2026 cleanup). Nothing here is
game content. Rendered checks write images and saves to an `out_dir` outside
the repository; QA images are never game assets. The independent settlement in
`Castles and Cities/` has its own tools under each experience's `tools/` folder.

Run Godot scripts with `godot --headless --path . --script res://tools/<name>.gd`
(drop `--headless` for rendered checks) and Python tools with `python3 tools/<name>.py`.

## Gates and generators

| Tool | Purpose |
|---|---|
| `validate_data.py` | Schema and cross-reference validation of every `data/*.json` table. Part of CI and the weekly review. |
| `test_knowledge_glossary.py` | Negative cases for the knowledge-scroll wording in `data/effects_glossary.json`. |
| `generate_map_geometry.py` | Regenerates `data/map_geometry.json` (fixed seed, byte-stable). Rerun after editing region positions or adjacency. |
| `military_guide.py` | Regenerates the data-driven tables in `docs/MILITARY_STRATEGY.md`. |
| `soak.gd` | Manual balance soak: two 100-turn AI campaigns with a world summary. Not part of the test suite. |

## Rendered acceptance checks (manual, one feature each)

Each script drives the real interface with actual input and prints PASS/FAIL
lines. The linked review explains what it proves.

| Tool | Feature | Record |
|---|---|---|
| `map_playtest.gd` | Map planning, marching, arrival and maximum zoom (required for map work) | `docs/reviews/2026-09-map-experience.md` |
| `recon_playtest.gd` | Commanders, scouting and observed movement | `docs/reviews/2026-09-v13-map-overhaul.md` |
| `terrain_playtest.gd` | Terrain and campaign-view review | `docs/reviews/2026-09-terrain-standard.md` |
| `campaign_route_playtest.gd` | Alpine route: forest, bridge, marsh and passes | `docs/reviews/2026-09-campaign-route.md` |
| `route_app_playtest.gd` | Route development entry scene at the 1280×800 minimum window | `docs/reviews/2026-09-campaign-route.md` |
| `city_playtest.gd` | Walkable Roma district | `docs/reviews/2026-09-roma-city.md` |
| `city_evolution_playtest.gd` | Roma development tabs, previews, dawn report and troops | `docs/reviews/2026-09-roma-city.md` |
| `city_controls_playtest.gd` | Roma pointer controls at two window sizes | `docs/reviews/2026-09-roma-city.md` |
| `city_navigation_playtest.gd` | Roma walking physics: roofs, furniture, doorways | `docs/reviews/2026-09-roma-city.md` |
| `city_country_playtest.gd` | City-to-country navigation and settlement memory | `docs/reviews/2026-10-city-country.md` |
| `city_battle_playtest.gd` | Continuous Roma battles and recruitment | `docs/CITY_BATTLES.md` |
| `roma_campaign_playtest.gd` | One continuing Roma campaign across city, map and battle views | `docs/reviews/2026-09-roma-unified-campaign.md` |
| `fortress_playtest.gd` | Fortress inspection and siege fire | `docs/reviews/2026-09-roma-fortress.md` |
| `swordplay_playtest.gd` | Articulated swordplay and specialists | `docs/reviews/2026-09-roma-swordplay.md` |
| `tactics_playtest.gd` | Platoon splitting, frontage and formation commands | `docs/reviews/2026-10-siege-command.md` |
| `app_playtest.gd` | Exported campaign menu and persistent save across two processes | `BUILDING.md` |

## Builds and packaging

| Tool | Purpose |
|---|---|
| `build_macos_playtest.py` | Exports macOS feedback builds or an approved release from a source snapshot (`BUILDING.md`). |
| `build_probe.gd` | Probe packed into exports: loads data, plays five turns and checks save/load lockstep. |
| `thin_macos_arm64.py` | Extracts the arm64 slice of a universal macOS export. |
| `build_realism_preview.py` | Builds the separate route/terrain/realism development apps without touching production settings. |

## Developer helpers

| Tool | Purpose |
|---|---|
| `screenshot.gd` | Map screenshots at chosen zooms and turns. |
| `realism_preview.gd` | Interactive realism-study comparison with isolated saves. |
| `dev_art_gallery.gd` | One sheet of every procedural building and unit illustration. |
| `dev_card_shot.gd` | Captures an info card, map dossier or staged battle playback. |
| `render_qa_storage.gd` | Shared helper that keeps rendered checks' shader caches and saves out of the user's folders. |
