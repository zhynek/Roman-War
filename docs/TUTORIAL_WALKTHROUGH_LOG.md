# Tutorial walkthrough log — one continuing settlement

Planning and implementation record begun during the October 2026 city-progression
coherence audit ([the audit report](reviews/2026-10-city-progression-coherence-audit.md)).
The independent Yenikapı settlement now implements eleven **How to play** lessons:
the original five, three civic lessons and three defense lessons. They navigate
to existing reviews; they never autoplay a recipe or adopt a chapter. Setup and
adoption are a separate note. The detailed season counts below remain measured
results from the pre-warfare audit at `2885f38`, not promises about combined play.
Combined evidence belongs to [the integration review](reviews/2026-10-city-warfare-integration.md).

## How to read this log

Each lesson records the player's objective and the exact available action, what
the player must already understand, the cost and trade-off, the immediate
feedback and success condition, the later consequence, the common mistake and
its recovery, and the supporting mechanic or test. Open audit findings that
touch a lesson are named by their finding id (`D-n`, `H-n`, `G-n`) from the
audit report.

Setup and adoption instructions (section A) are kept apart from the ordinary
town-leader decisions (sections B–E). Lessons marked **future content** describe
mechanics that do not exist yet and must not be presented as playable.

## Existing guidance to reuse

| Surface | What it already teaches | Where |
|---|---|---|
| Illustrated dock "How to play" (11 lessons) | Reserves, paid work, labor, land, preparedness; civic readiness, retained rank, operating services; defense preparation, command modes, aftermath | `data/visual_commands.json` `lessons`, `visual_commands.gd::help` |
| Growth guide | Compact vs outward chains with real prerequisite arrows; opens the lifecycle section first | `visual_commands.json` `chains`, `visual_commands.gd::growth` |
| City lifecycle review | Named readiness factors with current/required values, the next civic project card, its upkeep, the planned ladder | `visual_commands.gd::lifecycle`, `data/lifecycle.json` `strings` |
| Asset governance guide (8 steps) | Inspecting a shared asset, standing principles, commissioning through an asset, forecast vs result, pressure, learning, supported growth | `data/assets.json` `tutorial`, `assets_panel.gd::guide` |
| Land planning guide (5 steps) | Reading the ground, preparing, commissioning a location, forecast vs work, lasting costs | `data/land.json` `tutorial`, `land_panel.gd::guide` |
| Living village guide (7 steps) | Woodland, competing uses, practical knowledge, cooperation, watch kits, result vs expectation, a way back | `data/living.json` `tutorial`, `living_panel.gd::guide` |
| Preparedness guide (7 steps) | Warning, inspection, commitment, resolution, recovery, pausing, restoration | `data/incidents.json` `tutorial`, `incident_panel.gd` |
| Seasonal tutorial Guide tab | The legacy town-support milestone text and the recommended foundation | `governance_panel.gd::_guide`, `data/governance_ui.json` |

The civic lessons open City lifecycle. Defense lessons open preparation or the
persistent Battle aftermath review. These destinations retain the real quote,
workforce, care and command controls. An unresolved battle disables guide links
that could attach its worker: reading guidance does not restart saved ticks.
The lesson cursor is transient presentation state; no save extension is needed.

## A. Setup and adoption (not ordinary leader decisions)

**A1. Start a new village with living rules.** Action: dock → **New village**.
Creates the 30-resident village with asset governance, land planning and living
village active (`visual_commands.gd::begin`). The player needs no prior
understanding. No cost. Feedback: the dock shows stocks (100 provisions, 30
timber, 30 residents). Mistake: starting a new village when a save exists; the
dock asks for confirmation and the save file is untouched until an explicit Save.

**A2. Adopt the civic ladder.** Action: **City lifecycle → Begin city lifecycle**
(God only). Prerequisite understanding: adoption changes nothing but adds the
readiness memory; opening the review adopts nothing (`lifecycle_preview.gd`
checks "opening lifecycle does not adopt"). No cost. Feedback: the review now
shows *Civic achievement · Small village* and the readiness list. Later
consequence: the readiness counter only advances through resolved seasons.
Mistake: trying to adopt as steward or watch leader (authority error names the
cause). Supporting test: `lifecycle_checks.gd` ("adoption requires God
authority", "adoption preserves …").

**A3. Enable town development.** Action: **City lifecycle → Enable town
development**. Explains that prices and paid contracts stay pinned and that the
finished civic house replaces one civic adult with two. Can be done before the
first promotion. Supporting test: `town_checks.gd` ("explicit extension retains
old …"). Audit note: the ladder in the review marks Town "Enable town
development to play" until this is done, and Large town onward "Planned stage ·
not yet playable" (H-4 in the audit explains why the data still says planned).

**A4. Older saves.** An old save keeps its rules until each chapter is adopted
from the detailed ledger in order (assets → land → living → lifecycle → town).
A save that already reached the legacy town milestone receives explicit town
recognition and pays the ordinary prices for the missing fabric with no
readiness wait (probe 3: a 0.2-route tutorial save reached the civic house five
seasons after adoption). Keep this out of the ordinary walkthrough; it is a
compatibility route, verified by `town_checks.gd::legacy_town`.

## B. Stabilize food, housing and labor (seasons 1–12)

**B1. Inspect needs before giving orders.** Objective: read the forecast strip
("Next season: N provisions (±d) · W construction work") and the Stores review.
Action: select **Stores**, open **Local knowledge** and the season report after
the first **Next season**. Must understand: one provision feeds one resident for
one season; yields are 5/4/7/2 per food worker by season. No cost. Success: the
player can say whether winter is covered. Later consequence: nothing yet; this
lesson is about reading. Mistake: resolving several seasons without reading
the report; recovery is simply reading it (`report()` in `visual_commands.gd`).
Reuses existing dock lesson 1 and asset guide steps 1 and 5.

**B2. Choose the food-reserve principle deliberately.** Action: **Stores →
Daily work → Food reserves** (one / two / three seasons). Must understand: the
principle sets a stock target *and* the priority of extra gathering. Measured
trade-off (probe 1, compact strategy): the two-season reserve reaches Large
village at season 28 and Town at 39; the one-season reserve reaches them at 20
and 32 with the same final stocks, because the reserve request (priority 3)
otherwise pulls adults ahead of timber crews (priority 5) and projects. Early
food was lower with the one-season reserve (141 vs 151 at season 4, 282 vs
300 at season 10) and never ran out in a quiet game. Feedback: the allocation
review shows a "reserve" request and its priority. Later consequence: the
reserve only pays off under incidents or pressure losses; otherwise it is a
pure delay. Mistake: leaving the default and wondering why timber stays near
zero. Recovery: lower the reserve principle for a few seasons. Open finding
H-2 asks for the principle text to state the priority mechanism.

**B3. Allocate labor by commissioning, not by assigning people.** Action:
commission **Renew cultivation** (12 timber / 20 work) and **Larger stores**
(16 / 24) from the Fields and Stores cards. Must understand: materials are
paid once; crews are allocated automatically each season by priority; the
"Work underway" view changes crew limits and priorities. Trade-off: every
crew adult is not gathering. Feedback: the card shows paid materials, next
season's forecast work and the named cause when short. Success: both complete
(seasons 2 and 5 in every recorded strategy). Later consequence: cultivation
is a lasting +8 provisions per staffed harvest; the store is the prerequisite
of the assembly shelter. Mistake: queueing three projects with full crews and
starving timber; recovery: pause one (paid progress is kept, `partial_contract`
checks). Reuses dock lessons 2–3.

**B4. Welcome newcomers.** Action: **Village yard → Daily work → New arrivals →
Welcome when supported**. Must understand: arrivals come three at a time in
spring only when housing, two seasons of food, wellbeing and cooperation allow
it. Measured consequence (probe 3): with welcoming off, residents grow by births
only — 40 residents at season 61 instead of season 18, and the civic ladder
cannot start (the Town support gate needs 40). Mistake: forgetting the
principle; recovery is immediate but the lost seasons are not refunded.

## C. Choose land use (seasons 6–24)

**C1. Compact or outward homes.** Action: Growth guide → commission **Clay court
home** / **Hearth yard home** (14 timber / 24 work each) **or** **Northern path**
(12 / 20) then **Outer west** / **Outer east** homes (20 / 28 each). Must
understand: compact homes consume shared working ground (three places each,
and the hearth yard costs four cooperation); outer homes keep the ground but
need one adult and one timber every season for access. Measured consequence at
season 100 (probe 1): compact 8 construction places and 225 timber; outward 14
places and 121 timber; mixed layouts work (probe 3: court home plus outer east
home, 11 places, Town at season 45). Later consequence: an outward settlement
is exposed to approach incidents — an unprepared approach incident impaired
loaded access for two seasons with a −8 wellbeing penalty on outer households
(probe 3), which never touches a compact settlement. Mistake: starting outer
homes without the northern path (refused with a named cause). Recovery: cancel
unfinished staging for the unused timber share. Reuses dock lesson 4 and the
land guide.

**C2. Adapt the working room before compact homes.** Action: **Adapt workshop**
(10 timber / 16 work). Trade-off: materials now, +4 construction places and the
planning room host; it is also the prerequisite of the later workroom
improvement. Later consequence: compact settlements without it fall to two
places. Supporting check: `land_checks.gd`.

## D. Practical knowledge (seasons 1–12, in parallel)

**D1. Practice wood shaping on purpose.** Objective: raise "Practiced wood
shaping" from 2 to 4 for the assembly shelter. Action: **Workshop → Daily work →
Prepare materials → Ordinary** (one adult, 2 opening timber, one working place
per season). Must understand: one household gains one point per season when one
of its adults prepares or repairs; the readiness factor reads the best
household, and the adult who prepares rotates. Feedback: the Workshop review
shows the assigned household; the readiness row shows current/required.
Measured: the compact strategy met the gate at season 10 (probe 1). Later
consequence: prepared sets also feed watch equipment, repairs and incident
preparations. **Common mistake (audit defect D-1):** with nothing spending the
sets, the store fills at 12 and the preparation order silently stops working,
freezing the factor (a welcome-off village froze at 3/4 for 25 seasons). After
this audit the readiness row says so; recovery is to commission watch equipment
or repairs (two sets reopened practice and the gate was met two seasons later).

**D2. Recognize and support cooperation (optional).** Action: inspect the west
yard and upper households and the workshop, commission **Shared wood work**
(8 / 12), set **Prepare materials → Shared**, then **Support cooperation**.
Trade-off: two adults, 3 timber and two places per session for an extra
prepared set after two supported seasons. This is the only "adopted practice"
with a production effect in the settlement; it also speeds incident repairs.
Reuses living guide steps 3–4.

## E. Commission a paid civic project and operate it (seasons 20–45)

**E1. Read the readiness list and the quote.** Action: **City lifecycle**.
Must understand: readiness is a live check (residents, housing, provisions,
three social stocks, shaping, meeting ground, store, cultivation capability,
free site) and must hold for two consecutive resolved seasons; the quote shows
timber paid now, work, crew places, the civic obligation and the stocks that
remain after payment. Measured binding constraints in the compact strategy
(probe 1): shaping met at season 10, the meeting ground at 21, cooperation at
22 (the hearth-yard home costs four until the meeting ground adds eight), two
qualifying seasons at 24, then **timber** — insufficient at 24, below the
two-timber reserve at 25 — so the shelter was commissioned at 26 and finished
at 28. Mistake: assuming the knowledge gate is the slow part; it is usually
timber and cooperation. Recovery: pause optional work, keep three timber adults.

**E2. Commission the assembly shelter.** Action: card → **Commission** (14
timber / 24 work). Immediate feedback: timber drops once; the card shows paid
materials and the site shows staged materials. Success: "Assembly shelter
completed; large-village improvements are now eligible" and the dock button
reads **Large village**. Later consequence: from the next season one adult is
requested for civic duty at priority 4; two separately paid improvements open;
the Town readiness counter starts at zero. Nothing is granted free
(`lifecycle_checks.gd`: "civic upgrade grants no free buildings"). Supporting
test: `lifecycle_checks.gd`, rendered `lifecycle_preview.gd`.

**E3. Choose the next investment at Large village.** Action: **Organize the
enlarged store** (12 / 20, +60 storage, store revision 2 → 3) or **Organize the
adapted working room** (12 / 20, workroom 6 → 8 places). Trade-off: the store
raises the cap that later limits provisions at 360; the workroom restores
building capacity for a compact settlement. Both keep every furnishing, door
and condition (rendered captures 21–23).

**E4. Sustain town support, then adapt the shelter into a civic house.**
Action: **Enable town development** (if not done), then commission **Adapt the
assembly shelter into a civic house** (22 timber / 36 work) after four
consecutive supported seasons. Must understand: the Town gate reads the legacy
support factors (40 residents, 8 dwelling equivalents, two seasons of
provisions, 65 wellbeing/cooperation/security, seven foundations or their
spatial equivalents). Measured: compact ready at season 32, blocked by timber
until 35, finished at 39; outward finished at 46. Later consequence: civic duty
becomes two adults at priority 6 (replacing the one at priority 4, never
stacking — `town_checks.gd` "no duplicate civic duty"); two optional
facilities open. **Audit note (D-2):** each civic adult also adds six wellbeing
and three cooperation at the ordinary care rates; the forecast now shows this
under "Civic and service duty".

**E5. Operate the obligations and the optional services.** Action: buy
**Fit a material-preparation store** (16 / 24) and **Fit the shared provision
service** (14 / 24); keep store maintenance on. Must understand: benefits need
staffed civic duty, a staffed service adult and store condition ≥ 50; they stop
without erasing rank. Measured (probe 1): the preparation store adds one set per
season only while preparation is on and sets are below 12; the service saves
up to 6 provisions of spoilage, which at a full 360-provision store simply
becomes overflow (season-100 food was 360 with or without the facilities;
finding H-4). Stress and recovery: a priority-1, three-adult exchange project
unstaffs civic duty and the service stops (rendered capture 21); pausing it
restores both the next season (capture 22). Neglecting store maintenance drove
condition to 0, storage to 252 and stopped both benefits while Town rank stayed
(probe 1). Legacy support can also contract (tight rations dropped cooperation
to 64 and the ledger phase to "Village") while the civic rank, duty and output
continued; restoring rations recovered support in four seasons (probe 2).

**E6. Choose the next investment at Town.** Honest end of the walkthrough.
The review says the stage is complete and lists the two facilities; the ladder
marks Large town onward as planned. At this point the settlement sits at its
caps (48 residents, 360 provisions), gathers roughly 146 surplus provisions a
season that overflow, and accumulates timber (225 by season 100) with no sink.
The original audit exercised preparedness (prepared incidents cost 0 provisions
against 28 unprepared — probe 2), neighbors and maintenance. The combined game
also offers optional village warfare, paid defenses and recurring equipment/care
recovery. These are local decisions, not a new civic rank. Present Large town as
**future content**.

## Future content (do not present as playable)

- **Large town and later stages** — no transition, project, unlock or balance
  entry exists (`data/lifecycle.json` stages 3–6 are metadata; audit G-1).
- **Technology beyond local practice** — the settlement has three knowledge
  mechanics with effects (shaping, cooperation, woodland experience) and no
  research, adoption or technique system; the parent campaign's techniques are
  a separate experience (audit section 5).
- **Recruitment, armies and conquest** — village defense now mobilizes actual
  home-watch residents with their paid equipment and experience. Independent
  live battles, delegation, quick resolution and recovery are playable. Standing
  armies, recruitment, conquest and a bridge to the parent `BattleResolver`
  remain future work (audit G-5); village and campaign saves remain separate.

## Implemented civic and defense guidance

Lessons 6–8 teach practical shaping, paid civic promotion, current Town support
versus retained rank, and staffing/maintenance of optional services. The reserve
principle states its priority change explicitly. Civic/service social contribution
and actual priorities are formatted from the existing rules. Town facilities are
situational: prepared sets serve equipment and repair; reduced spoilage may
overflow at full stores. The provision room is discoverable from Homes and Stores
through a presentation alias, retaining one paid project and its original owner.

Lessons 9–11 teach finite named watch and equipment, paid screens and saved
positions, optional recurring warnings, direct/delegated/quick command, coherent
quick cancellation, report acceptance, care and ordinary repair. They distinguish
recoverable incapacitation from death and explicitly leave recruitment/conquest
outside current play. Household learning-circle participation remains an
illustrative score; its existing staffed sessions retain real labor, food and
cooperation effects, separate from shaping and combat experience.

`integration_guide_checks.gd` checks published hashes, the frozen paid fixture,
pure lesson/destination navigation, both provision-card locations, real policy
contraction at earned Town, learning-score versus session effects, and active
battle save/clock preservation. `integration_guide_preview.gd` repeats the guide
and review controls with actual pointer input at 1280×800 and writes captures
outside the repository. Public-command recipes remain QA evidence, never an
in-game autoplay or source of free progress.

Verification on 2026-10-08: the focused headless and actual-input rendered guide
runs each passed 104 checks with no failures and clean stderr. All 14 final
1280×800 captures were inspected, including the scrolled setup note, both
provision-service entry points, current Town support contraction, and the
unresolved-battle navigation guard. The final capture manifest and inspection
record are outside the repository at
`/tmp/village-integration-guide-render-verified/`. The new data regression file
`test_integration_guide_data.py` passed all three tests; the visual-command
validator passed all eight negative cases. Published defense, lifecycle, town
and warfare semantic hashes and the paid Town fixture checksum stayed exact.
