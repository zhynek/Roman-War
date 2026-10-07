# A Village at Your Fingertips — 0.9.0

0.10.0 extends these controls with [construction sites and shared planning-room oversight](CONSTRUCTION.md). All three surfaces use the same project review and ordinary commands.

Choose **New village** in the illustrated bottom dock, or **Load saved village**.
A new village starts with the existing 30 residents, 100 provisions and 30 timber,
with asset, land and living rules active. Warning and recovery remain an explicit
choice. No starter equipment, free buildings or extra supplies are introduced.

## Give orders through places

Click an actual building or one of the seven place illustrations along the bottom.
Stores govern reserves and protected handling; homes govern care and housing;
fields govern cultivation; the landing governs waterside work; the workshop
governs materials, repair and cooperation; the yard governs connections and
welcoming; the watch governs posts, staffing, practice and equipment.

**Improvements** shows illustrated projects with Available, Unavailable, Completed,
or actual work progress. Click a card to review the timber and prepared sets paid
now, seasonal work still required, prerequisites and consequences. **Commission**
is the payment action. Locked cards remain inspectable and explain their refusal.
They do not hide future possibilities. **View this building site** locates the
actual authored place. Building projects offer **Current / Planned** model views;
drag a model to rotate it. Planned geometry uses the production building generator.
Other improvements show their current place, labelled as such. Model viewing never
changes live geometry, pays materials or advances work.

**Daily work** holds the selected place's standing choices. Choose a card, then an
option. These orders are revisable and use the existing finite adult allocator.
Paid preparations quote their up-front cost; each description retains its seasonal
labor/material requirements. Condition and assigned adult counts appear above the
cards. **Work underway** gathers commissioned projects across places: review work
progress, change crew limits and priorities, pause, resume or cancel. Cancellation
returns only the unused fraction of original materials. Every button quotes the
same public command used by the detailed ledger; role restrictions remain real.

The top strip shows current stocks and the expected next-season food/work result.
**Next season** explicitly resolves it. **Season report** shows actual results and
named causes. Busy feedback and the existing seasonal input lock guard expensive
work. **Local knowledge** opens findings and targeted household, woodland and post
questions, using the same commands as world inspection. Inspection has no reward.
The complete persistent records and administrative detail remain in **Village menu
→ Detailed ledger**. Its **Use visual commands** button returns to the dock.

## See how growth connects

The **Growth guide** groups compact housing, outward housing, productive places,
and preparedness. Arrows mean actual prerequisites, validated against project
content; plus signs mean complementary choices rather than prerequisite locks.
Compact homes use central shared ground. Outward homes require a paid northern
connection and its ongoing upkeep. Both routes preserve existing occupied homes.
The guide links to the original town-readiness review, with no new threshold.

The connected five-step **How to play** guide links each explanation to its place:
reserves, a paid improvement, labor opportunity costs, a growth route, then warning
and recovery. It grants nothing and does not require one layout. Warning banners
remain visible above the world. The preparedness view connects restrictions,
material commitments, named outcome factors and paid repair to existing projects.

## Preserved boundaries and controls

This is a presentation phase. `settlement_rules` and every scene-free extension are
unchanged. The dated village, medieval project, parent campaign, 36 model exports,
existing chapters and previous downloads retain their boundaries. The old Roma
bottom command bar and development viewer (`src/ui/city/city_screen.gd`, documented
in `docs/reviews/2026-09-roma-city.md`) supplied the interaction pattern. No Roman
buildings, troops or campaign simulation have been imported into the village.

The original procedural illustrations use vector drawing, with short labels and
hover text so shape and color are not the only cues. There are no image files or
borrowed art. Ordinary views leave the world visible; reviews collapse the action
row to give their scrollable content room. Small windows keep native-size text.
WASD moves; right-drag or Tab looks; F changes walking/flight; 0 gives an aerial
view; Escape closes a review; H hides the interface. There are no citizen orders.

## Save contract

No save wrapper or resource semantics change in 0.9.0. Wrappers 1–7 keep their
meanings. Opening a legacy save in the visual interface never adopts a new chapter;
its detailed ledger offers the existing explicit adoption path. All layout,
projects, crew limits, progress, principles, contacts, households, knowledge,
equipment and incidents remain in their original authoritative records. The
selected card, open review, model rotation and tutorial page are presentation
state and are not saved. JSON-authored numeric choices are canonicalized before
command dispatch, so save/load preserves exact canonical state.

Starting over requires confirmation when a game or save exists and leaves the
saved file untouched until an explicit Save. The app keeps the existing independent
save directory. It never reads the parent campaign or medieval creative saves.

## Authoring and verification

`data/visual_commands.json` owns labels, short explanations, place/card grouping,
connected lessons and growth links. Its closed schema and
`tools/validate_visual_commands.py` reject missing/unknown places, projects, icons,
invalid choices and misleading prerequisite arrows. `visual_commands.gd` adapts
public quotes and commands. `place_icon.gd` draws original icons;
`place_preview.gd` displays isolated production meshes. Cached future meshes are
keyed by immutable project identity, while current meshes come from the live world.
Hidden ledger tabs are not rebuilt while the dock is active. Menu redraws do not
rebuild routes or scene geometry.

Run `visual_checks.gd`, `visual_preview.gd` and `visual_profile.gd` alongside all
retained gates. The rendered harness uses actual pointer controls and normal
resources for construction, standing orders, pausing, recovery, both housing
layouts, model comparison, save/load and new-game confirmation. Interaction
profiling reports callback time separately from readiness after rendered frames.
The release builder repeats these checks inside the exact universal Mac app.
No Intel performance or Developer ID notarization is claimed.
