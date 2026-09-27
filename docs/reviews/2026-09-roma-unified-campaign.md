# Unified Roma campaign — September 27, 2026

## Delivered behaviour

Roma, its strategic map and its live siege defence now share one continuing
campaign. `CampaignSession` owns one `Game` and save path, retaining both city
and map scenes through view switches. City walking position, camera and visible
garrison return with the visit. Main-menu Roma resumes the common save before
considering the legacy Roma slot; an existing campaign of another faction is
preserved and opens on its strategic map. The Alpine comparison retains its
separate scenario and save.

The city command bar now exposes **Campaign map**, **Next season** and
**Calendar & history**. Its **Roma through the years** ledger offers calendar, historical stock charts, paged
records and campaign construction. A requested year runs the ordinary seasonal
engine twice, stopping for a threat, decision, siege, ownership loss or campaign
ending. A ready defence and any unfinished battle block a season before civic
costs or queue progress.

After an explicit visit activates Roma, the same seasonal facade schedules
three funded civic work days before normal campaign resolution from either
view. Unfunded civic work waits without blocking seasonal income. City recruits
use their civic queue; strategic recruits retain their seasonal queue. This
keeps each completion and payment singular. Civic days remain close-management
operations, independent of the half-year calendar.

Live command now supports rectangle selection at the formations' actual drawn
positions. Shift adds to selection; selection is restricted to active defending
formations and releasing over HUD cancels the gesture. Group orders work while
fighting or paused. Camera controls include perspective zoom, WASD and
middle-drag pan, Alt-drag orbit, Q/E orbit, Up/Down elevation, selected-group
follow, aerial and tilt views, plus inset recentering. Camera and selection are
presentation only.

## Lifecycle and save contracts

`CityBattleHost` remains the sole runtime owner of live ticks. Session switches,
load and exit stop and join it before another screen reads the shared game.
Returning to a fight retains its exact paused state; no unseen worker continues
combat on the campaign map. Loading swaps the state dictionary in the existing
facade and clears obsolete UI selections, journals and treasury animation.

The common slot stores city, campaign and battle together. The legacy city file
is considered only when no common campaign file exists. Returning to the menu
saves the session and a failed save keeps the session available. Finished
defeat reports remain accessible after Roma changes ownership; closing the
report returns directly to the campaign, so it cannot trap the player away
from surviving holdings. Live real losses still commit
once through `SiegeRules.assault` / `BattleResolver`; practice remains isolated.

`CityCampaignRules` adds activation and bounded dated history through an
additive save field. Status/history queries return detached data. Entering again
does not reset elapsed work or history. Existing saves remain inactive until a
visit; malformed history rejects at the normal save boundary. Calendar and
queue tuning lives in data, with schema and cross-reference validation.

## Time and scope

The existing campaign runs from 270 BC to AD 14 with summer/winter turns and
its normal victory conditions. This change connects city play to that engine;
it does not invent a separate long-term simulation or bypass AI turns. History
retains up to 640 snapshots, paged in the UI.

The 200-season fixture directly records dated snapshots and verifies save
retention across a century. It is a storage/calendar test, **not a 100-year AI
soak or proof of century-scale balance or performance**. Only seasons actually
played appear in a real campaign history. This work does not add era-specific
architectural rebuilding, household life simulation or new tactical city maps.
Roma remains an original procedural district with formation-level combat.
Individual-soldier physics, multiple breaches, siege towers and multiplayer
remain outside this scope.

## Verified results

- **643 tests, 0 failures**, Godot exit 0, no `SCRIPT ERROR:` or `ERROR:` diagnostics. The existing 600 ms turn-speed guard passes unchanged. One inherited Control anchor/size warning remains in UI coverage.
- Fresh Godot import passes. Content/schema validation reports **0 errors, 0 warnings**.
- The exact exported Mac app passes `tools/roma_campaign_playtest.gd`: city/map roundtrips, recruitment and calendar/history, cross-view save/load, held marquee and live selection, close views at 1280×800 and 1600×900, camera gestures, group orders, direct battle-to-map suspension, real siege loss, exactly-once capture and return to the surviving campaign.
- The exact exported app passes `tools/city_battle_playtest.gd`: actual barracks recruitment of archers/cavalry, visible town formations, deployment, live pause/save/load, volleys, charge and group commands, gate breach, a completed defence and return to town. This seeded practice reaches victory at 1:36 simulation time, with 26% defender and 88% attacker losses; practice preserves the campaign roster.
- The rendered campaign-map gate passes planning, marching, arrival and maximum zoom. Inspected screenshots remain outside the repository. Its local short sample records 6.898 ms median / 7.217 ms p95 and 85 FPS, not a cross-platform guarantee.
- Universal arm64/x86_64 export, ad-hoc signature, data packing, campaign save/replay and battle package probes pass. All **522** captured runtime/validation files match the workspace exactly.

An earlier gate caught a new test reading `RichTextLabel.text` instead of its displayed `get_parsed_text()`, and a legacy menu test assuming `CampaignScreen` was a direct menu child. Those assertions now exercise the new session contract; the complete suite was rerun successfully.

Final logs are copied into `build/roma-unified-campaign-20260927/verification/`.
Rendered images are in `/private/tmp/roma-unified-package-qa/`, `/private/tmp/roma-unified-package-battle/` and `/private/tmp/roma-unified-map-qa/`.

## Build

**0.18.0-preview.20260927**, full campaign/menu app:
`build/roma-unified-campaign-20260927/Roman War Playtest.app`.
The same directory contains the zipped app, frozen source snapshot, source hashes,
verification logs, provenance and a concise control guide. Preview saves retain
the existing preview identity; no production release was published.

ZIP SHA256: `cf08c0531992251bc04570dda4fdc49faa3999bb9ba278cd84024b3653600835`.
