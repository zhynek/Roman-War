# Buildings That Show Their Work — 0.10.0

Choose **Village projects** above the village to compare every available,
unfinished and completed improvement. Select a card, or click the materials or
partial structure at an actual site. Both open the same project review used by
the existing building dock. No new chapter or population milestone is required.

## Read a site

Four unfinished stages represent quarters of the saved work: preparation,
supports, framing/enclosure, and roofing/fittings. Completion displays the actual
finished improvement. Repairs, interior adaptations, paths, grounds and equipment
use their own treatments and stage names. An adaptation leaves the occupied
building, furnishings and entrance in place, with a small work surface alongside.
Pausing retains the exact partial structure and paid commitment. It does not clear
the plot or return timber. Resuming uses the same project identity and progress.

Nearby work has a small shape and label: a work mark, **II** for pause, a person
for limited labor, **0** for a zero crew limit, or **!** for a blocking condition.
Repair and relevant incident signs identify affected places. Selection adds the
stage and work count; the selected footprint and applicable connection are marked.
The detailed cause distinguishes competing adult labor, work-space capacity,
disabled access, missing upkeep timber and incident-impaired access. A damaged
workroom can reduce output even when a crew is assigned.

The review reads **Materials → Workers → Result**. Materials separates village
stock from timber and prepared sets already paid. Workers shows allocated adults,
the requested crew limit, total adult/work-place capacity, saved work still needed
and the authoritative next-season forecast. Result states the existing benefit.
The progress bar counts completed work; it is not an animation timer. **Details**
lists affected objects and the actual assigned residents and households. Required
earlier projects have prerequisite links; a helpful workroom investment is
explicitly described as optional. Current/planned views use the partial site or
existing building and the production model for its eventual result.

Material piles are bounded illustrations of these records, not a second resource
inventory. Citizens follow the existing assignment ledger and collision-checked
routes. A paused or unstaffed project has no assigned construction activity. Merely
watching a worker, viewing a model or entering a room does not perform work.

## Use the shared planning room

**Village projects → Enter shared planning room** visits the existing working
room (`yk_house_06`). Its occupants and working use remain intact. A wall board
holds eight small plans per page; use **Previous / Next plans** for the rest.

1. Click a physical plan on the board. The camera turns to its easel display.
2. Click the easel to enlarge that project's ordinary review.
3. Commission, adjust priority or crew limit, pause/resume, or cancel with the
   same permitted commands as the dock or site. Lower priority numbers go first.
4. Close the review to return to the room. **Project board** turns back to the
   plans; **All village projects** compares cards; **Return to village** restores
   the previous view.

Active, paused and completed plans have matching marks and progress bars. The
selected plan updates after every command and season. Cancellation returns the
existing integer-rounded unused fraction of original timber and prepared sets;
the review quotes that refund. Completed work cannot be canceled. Steward/watch
authority restrictions and all existing project costs remain in force. Ordinary
governance never requires walking here.

This room is an **interpretive gameplay interface**, not evidence of a palace,
architectural office or Neolithic blueprint practice at Yenikapı. The board,
portable easel, diagram objects and their arrangement are original procedural art.
They introduce no facility benefit or free economic upgrade. No new historical
claim is made; see the site's evidence ledger.

## Incidents and saves

Unfinished sites survive both existing incident outcomes. Resolution may change
available labor or loaded access for future seasons, but never removes a site,
resets its accumulated work, erases payment, or repairs/completes it for free.
An active project can gain only its ordinary forecast work during the incident's
season; a paused project gains none. Existing bounded losses and recovery remain
unchanged. Saving before or after an incident preserves these facts.

There are **no new save fields, wrappers or economic rules**. Queue entries,
completed project IDs, asset initiative crew/priority/pause records, land layout,
households, standing orders, knowledge and incidents remain authoritative in
wrappers 1–7. Old manual-workforce saves retain manual work until explicit adoption;
looking at plans never adopts a chapter. Stage meshes, icons, selected plan,
camera position in the room and open review are derived transient presentation.
The independent campaign save directory and explicit Save/Load commands remain.

## Authoring and implementation

`data/construction.json` owns treatments, stage labels, concise benefits, specific
cause labels and the board/easel placement. Its closed schema and validator check
every project and the existing working-room host. `project_presentation.gd` is a
pure read model over public forecasts, assignments, quotes and saved records.
`construction_view.gd` and `planning_room.gd` create original geometry, matching
picking targets and collision. `visual_commands.gd` remains the shared command
surface; it does not introduce a second project manager.

Changing crew, priority or pause reuses unchanged site meshes. Forecasts are cached
by state, future building meshes by project ID, and static room furniture by world
revision. Physical completion compares numeric footprint values, preserves the
world and unchanged buildings, and patches affected terrain triangles. Valid
cached routes are rechecked and retained; newly obstructed routes are rebuilt.
Season input locks and synchronous command guards prevent duplicate submissions.
No timer, draw callback, route animation or scene object can mutate the simulation.

Run the construction validator, `construction_checks.gd`, the real-input
`construction_preview.gd`, and `construction_profile.gd` alongside every retained
independent-project and parent gate. The checks include cold-build geometry
equivalence, actual route walking, legacy save purity, quarter stages, shared
controls, finite competing crews, refund math, and saved active/paused incident
replay. Inspect every exact-app capture, including 1024×768 controls and retained
compact/outward completion views. The profile distinguishes callback time from
readiness after rendered frames. See `../VERIFICATION-0.10.md` for measured results
and remaining latency; do not infer Intel performance from Apple Silicon runs.
