# Village warfare — 0.14.0 local milestone

This continues the preserved 0.13 defense implementation on
`codex/village-defense`; it does not replace it with a historical branch. The
original deterministic village, household and construction engines remain the
source of people, materials and seasonal labor. The independent village does not
call or modify the parent campaign's BattleResolver.

## Explicit adoption and compatibility

**Defend the village → Enable village warfare** adopts the separate
`village_warfare_v1` semantic profile. Loading or inspecting an older village
adds only inactive `warfare: {}`. Adopted saves use wrapper 10. An unresolved
wrapper-9 battle must first finish under its original rules. Original defense,
lifecycle and town hashes remain unchanged. The atomic validated save writer
still checks its temporary file before replacing the destination.

The new profile is defined by `governance.warfare` and `balance.warfare`. Its
top-level UI strings are excluded from the hash; the authored fortification
definitions and tuning are pinned. Tactical state is additive under `battle.tactics`
and `group.tactical`. Fixed 100 ms ticks own positions, contact memory, routes,
spacing decisions, fatigue, morale and simultaneous damage. Integer state and
serialized accepted commands survive JSON roundtrips. No renderer, timer,
camera gesture or animation resolves a rule or consumes randomness.

## Phase 1: movement, orders and readable combat

Groups reserve space, choose separate destinations, queue in narrow passages,
seek clear alternate routes and yield at blocked crossings. A spread formation
files into a column where the sampled collision grid narrows. It reopens where
space permits. Buildings, ordinary boundaries and current paid-project geometry
are sampled from the actual village. Paths and close positions remain subject
to that conservative one-meter grid; this is a small-group abstraction, not
per-person collision or weapon physics.

Existing click, rectangle and Shift selection and the seven orders remain.
Column/spread controls add width. Face keeps a chosen direction; turning is
bounded per tick. Selected groups display destinations, facing, order, fatigue,
morale, local support and position benefits. Overhead, close view, wheel zoom,
middle-drag and trackpad camera gestures do not issue battle orders.

Serviceable equipment and earned watch training affect striking power. Actual
resident watch aptitude is reused explicitly. The appointed watch leader adds
leadership only when personally present in the group. No resident is granted
new expertise by adoption. Movement and striking cause fatigue; a safe hold
recovers it. Frontal holding, restricted approaches and prepared positions lower
incoming damage; rear exposure increases it. Nearby numerical support affects
morale. The interface names these factors instead of displaying guessed odds.

Both sides acquire targets through current unobstructed vision. A targeted
attack searches the last seen position for a bounded interval; it cannot track
an enemy invisibly through buildings. Raiders pursue the objective and abandon
it when losses or time make continuation unproductive. Idle and total-tick
limits remain hard termination gates.

Original procedural figures use jointed limbs, guarded staff attacks, recoil,
falls and retreat poses. Pose clocks read detached snapshots and sequence IDs;
they cannot cause damage. Drawing and picking use the same anchors. Unseen
enemies are not instantiated and generic observed appearances never inspect
private equipment or roster identities.

## Phase 2: paid defenses and saved plans

After adopting warfare, use **Defend the village** or the ordinary **Watch**
project cards to commission either screen. Both require the existing paid watch
shelter. They spend real timber immediately and receive work only from their
allocated seasonal crews; food, care, upkeep and other paid projects retain their
normal claims on finite adults and work places.

| Project | Timber | Work | Purpose |
|---|---:|---:|---|
| Screen the store approach | 12 | 16 | Deflect an eastern approach beside the shared stores |
| Screen the landing approach | 10 | 16 | Shape the approach beside the existing yard path |

Each project adds two original low woven boundary sections around a permanently
open entrance. These are hypothetical village preparations, not an excavated
defensive plan or Roman military technology. The ordinary project queue remains
the only construction ledger. Crew limits, priorities, pause, cancellation,
unused-material refunds and completed fabric use the established commands.
Preparation displays current progress, assigned adults and forecast work. Main
project cards, the planning room and physical sites show the actual paired
geometry and its construction stages; their piles and selection outlines leave
the entrance open.

A completed screen changes the same walking collision that the tactical adapter
samples. A group holding or defending its inner stand receives the configured
prepared-position benefit while watch condition is at least 50: incoming damage
uses an 80% multiplier within 3.5 metres. It still needs actual residents to hold
that ground. Raiders can use the entrance or go around either end. No defender,
equipment, passive security bonus or completed structure is granted by adoption.

Maintenance reuses the watch asset's existing timber and repair-worker allocation.
Below the condition threshold the prepared-position benefit stops. The paid
screen remains physically present; this phase adds no structural battle damage,
demolition or cosmetic collapse. Restoring ordinary maintenance restores the
benefit. Existing refuge screens remain available as separately paid preparations.

The preparation panel saves five plan slots: **Assembly**, **Defended approach**,
**Important place**, **Reserve** and **Fallback**. Previous/next controls choose
among nine named positions; assembly choices remain inside the deployment area.
Designating ground costs nothing and grants no structures. **Save village &
plans** and **Load village & plans** use the normal independent village slot.

Mobilization resolves the named positions against actual captured navigation.
The assembly is issued through the ordinary serialized deployment-order boundary;
the fallback is also the watch's rout destination. Battle plan buttons issue Move
for assembly, Defend for approach/important/reserve, and Withdraw for fallback.
The five authoritative coordinates persist with the active battle. Plans,
workforce, spending and seasonal work cannot change while that battle awaits
resolution. Save validation rejects unsupported protection or altered plan data.

## Phase 3: threats and command modes

After adopting warfare, **Enable recurring threats** explicitly enables continuing
threats. This replaces the old one-consequential-encounter restriction for the
adopted village. It does not silently activate on load. At least eight quiet
seasons follow acceptance, followed by two full warning seasons. A previously
completed friendly trade or aid relationship can provide one extra warning
season; it does not identify the attackers as that neighbor. Injuries, active
ordinary incidents, insufficient food reserves or no available watch defer the
next actionable threat. A mature, supportable warning must be resolved before
another season; normal preparation remains available until mobilization.

The sequence has three different objectives, with fixed capability rather than
unbounded escalation: uncontested occupation of the stores; taking a landing
supply bundle and escaping with its carrier; and holding the northern approach
long enough to complete a probe. Intercepting the carrier can recover the bundle.
Clearing the northern approach interrupts progress. Deadlines, morale failure,
withdrawal, unreachable routes and the hard battle clock all produce explicit
end states. No attack silently removes resources before acceptance.

**Additional home watch** requests zero, two or four additional named adults
through the existing workforce allocator. Food, care and prior obligations keep
their priority. Extra watch competes with paid construction, timber and reserve
work. A tested 21-adult village changes from two to six mobilizable residents;
its paid screen crew falls from five adults to one. Requesting watch supplies
neither equipment nor people. Mobilization still pays one provision per actual
resident, and unavailable injured residents cannot be assigned twice.

- **Command personally** opens paused deployment and waits for player orders.
- **Delegate command** prepares legal defensive positions and issues ordinary
  serialized orders using current friendly state and observed enemies. Existing
  deliberate defensive placements remain meaningful. Leadership comes from the
  appointed resident when present, not a hidden mode bonus.
- **Resolve quickly** runs that same delegated fight in worker batches, omitting
  expensive battlefield drawing. A progress display and **Stop & pause** retain
  a coherent battle that can be commanded, saved or resumed.

The player may hand off and take command back while the battle remains active.
Issuing an order during delegation takes command back; selection and camera
movement do not. The runtime quick flag is only pacing. Objective state, mode,
commander decision tick, accepted orders, contacts, morale, fatigue and movement
remain serialized battle authority. The thread releases its mutex between
bounded batches. A returned outcome must still be accepted once before seasons
resume. Practice works on a detached village and never commits or writes a save.

## Phase 4: named consequences and ordinary recovery

`warfare.aftermath` is explicitly adopted with version, person records, pooled
kit condition and a treatment-order flag. Adoption imports any existing recovery
exclusion without granting battle experience. The existing `defense.recovery`
ledger remains the single authority for unavailable adults; no second workforce
roster is created. Household, lifecycle and paid-project identities survive.

Pending outcomes list the actual residents, their household, injury, expected
care seasons, earned experience and equipment consequences. Acceptance is the
only consequence boundary: it stamps the named report, deducts actual losses,
updates recovery and equipment condition, records participation, applies bounded
household stress and schedules the next recovery interval exactly once. An ended
battle can be saved before acceptance. Duplicate acceptance cannot spend twice.
The persistent **Battle aftermath** view keeps these records available afterward,
including older reports, current care needs and useful recovery actions.

Damage is group based. Remaining group health is allocated to members in stable
order: sufficient loss produces a wound needing one staffed, fed care season;
incapacitation needs three. This is an explicit abstraction, not individual
medical simulation. Each allocated treatment worker can treat two residents per
fed season. Treatment competes for finite labor; disabling it does not heal
patients. The ordinary household care system reduces the accompanying stress.
Recovering adults remain visibly at home and cannot also appear as working staff.

Kit loss follows incapacitated equipped participants. Engaged equipment loses
condition, with additional wear on incapacitation. The ordinary **repair
equipment** order can now restore condition even when the kit count is full:
each completed repair still consumes a prepared set, timber and a worker and
restores 25 condition. Preparation and replacement remain ordinary living work.
Three engaged encounters earn one point above that resident's existing watch
aptitude, capped at the authored tactical limit; merely being mobilized grants
no combat experience. The actual appointed watch leader must participate to
contribute leadership. All these values are validated against named reports.

Combat deaths are deliberately outside this milestone. Combat incapacitation is
recoverable; natural lifecycle deaths retain their existing behavior and history.
A person who becomes naturally inactive leaves the recovery workforce exclusion,
but their participation and household records are preserved. No resident or
household history is deleted to reconcile a battle.

## Authoritative boundaries and save review

- `warfare_rules.gd` owns adoption, profile validation, saved plans, muster and
  treatment commands; `fortification_rules.gd` derives paid protection.
- `defense_adapter.gd` captures actual village navigation and actual residents.
  `tactical_sim.gd` owns integer movement, combat, contacts and battle termination.
- `threat_rules.gd` owns seasonal warning/recovery scheduling and the deliberate
  neighbor-contact adapter. It neither invents diplomacy nor spends battle losses.
- `battle_director.gd` chooses valid serialized orders at fixed decision ticks.
  `defense_rules.step` is the shared normal, delegated and quick tick boundary.
- `defense_host.gd` changes pacing only. Batches release the mutex after at most
  16 ticks or 12 milliseconds; cancel/save/close pause through a serialized command.
- `aftermath_rules.gd` decorates pending outcomes, reconciles accepted named
  consequences and hooks paid treatment/repair into ordinary seasonal resolution.
- `campaign_save.gd` validates complete wrappers before atomic replacement.
  An active or pending battle blocks seasonal, workforce, project and spending
  mutations. Preparation, deployment, active/direct/delegated and ended states
  retain their authoritative orders, navigation, contacts, objectives, AI decision
  tick, fatigue, morale, health and pending consequences.

Ordinary command logging has a 2,000-entry budget. A bounded safety reserve
retains start, pause and each still-commandable group's first withdrawal after
that budget. Repeated withdrawals cannot consume the reserve; same-tick pause
pairs compact only when they cancel exactly without crossing start. Validation
checks reserve entries and the total `2,000 + limit_ticks + 12` bound. The retained
stream replays identically and a full ordinary log cannot trap deployment or make
pause/save/withdraw unavailable.

Adopted active saves also reconstruct the original mobilization quote by restoring
only its already-paid rations in a detached copy. Validation checks the exact
roster and formation order, original kit allocation, readiness, paid cost,
starting morale and fixed raider capability/starting health against that quote.
Current combat health, fatigue, morale and positions remain authoritative changing
state. Editing an original capability cannot bypass the living workforce or
manufacture a favorable retreat threshold.

Normal stepping, worker batching and save/resume use identical rules. Equivalence
means identical initial state and command stream; different player orders can
properly change the outcome. Quick resolution intentionally supplies delegated
orders, and the next ordinary run of that same stream has the same result.

## Verification and local delivery

The phase-by-phase controls and rendered checks include paid projects and open
entrances; click/drag/additive selection and every order; facing, width, pause,
speed and cameras; congestion, pursuit, morale, withdrawal and bounded stalls;
three objectives and repeated cycles; handoff/takeback, quick cancellation and
active saves; named injury, finite care, paid repair and continued development.
Godot stderr is inspected in addition to process status. QA screenshots remain
outside the repository and are never game assets.

See [the delivery verification record](../VERIFICATION-WARFARE.md) for the original
local milestone's source, parent, rendered and exact-export gates, measured quick
times and limits. Its dated integration addendum separates the later source-only
verification from that unchanged exported app. The [controls guide](WARFARE-CONTROLS.md) gives the playable
preparation and recovery sequence. The reproducible local packager is
`Castles and Cities/tools/build_village_warfare_local.py` at the repository root;
it refuses existing outputs, freezes editable source and emits SHA-256 provenance.
The original local milestone changed no published release. The October source
integration authorizes a push to main after verification, without a new build,
release, tag or published binary.

Reproduce from this independent project with Godot 4.4.1 and Python jsonschema:

```sh
python3 tools/validate_warfare.py
python3 tools/test_warfare_data.py
python3 tools/validate_fortifications.py
python3 tools/test_fortification_data.py
python3 tools/validate_threats.py
python3 tools/test_threats.py
python3 tools/validate_aftermath.py
python3 tools/test_aftermath_data.py
godot --headless --path . --import
godot --headless --path . --script res://tools/tactical_checks.gd
godot --headless --path . --script res://tools/warfare_checks.gd
godot --headless --path . --script res://tools/fortification_checks.gd
godot --headless --path . --script res://tools/encounter_checks.gd
godot --headless --path . --script res://tools/modes_checks.gd
godot --headless --path . --script res://tools/modes_host_checks.gd
godot --headless --path . --script res://tools/aftermath_checks.gd
godot --headless --path . --script res://tools/command_budget_checks.gd
godot --path . --max-fps 30 --script res://tools/tactical_preview.gd -- out_dir=/tmp/village-tactical-render
godot --path . --max-fps 30 --script res://tools/tactical_camera_checks.gd -- out_dir=/tmp/village-camera-render
godot --path . --max-fps 30 --script res://tools/tactical_scenarios_preview.gd -- render out_dir=/tmp/village-tactical-scenarios
godot --path . --max-fps 30 --script res://tools/fortification_preview.gd -- out_dir=/tmp/village-fortification-controls
godot --path . --max-fps 30 --script res://tools/modes_preview.gd -- out_dir=/tmp/village-mode-controls
godot --path . --max-fps 30 --script res://tools/aftermath_preview.gd -- out_dir=/tmp/village-aftermath-controls
```

These supplement every retained village and parent gate. Run the retained
validators and suites as well; focused commands alone are not the release gate.

## Civic audit integration

Warfare is available without City lifecycle. It requires explicit Living village
adoption and watch authority; Town is not a prerequisite and adoption grants no
civic achievement. The Town preparation facility feeds the existing prepared-set
path for manufacture/replacement and paid kit-condition repair. The provision
service protects actual spoilage during reserve recovery, with no benefit beyond
capacity when stores are already full.

The combined allocator remains authoritative: every adult has one assignment.
Ordinary watch, watch-practice duty and additional home watch are displayed as
separate security factors while retaining their previous sum. Town civic duty
(priority 6), provision service (7), watch practice/additional watch (4), essential
food (1) and care/treatment (2) compete in the existing priority-then-ID order.
Civic adults retain their explicit social contribution and cannot also mobilize.

Household learning-circle participation is an illustrative history score, not
combat aptitude. Its staffed order still has its existing labor, food and
cooperation effects. Actual resident watch aptitude, paid kit condition, earned
watch readiness, the participating appointed leader and engaged combat experience
are the documented tactical inputs. No hidden bonus was attached to household
practice and no published semantic profile was changed for explanatory copy.

The civic ladder ends at Town; recurring local defenses and recoverable battle
consequences continue afterward. Large town, recruitment, conquest and the future
versioned settlement-development report remain outside this integration. The
report's future design should include current local equipment/recovery and
provenance, without sharing saves or invoking the parent campaign.
