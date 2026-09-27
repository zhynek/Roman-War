# Roma swordplay and specialist formations — 2026-09-27

This extends the fortress preview in the occupied `codex/roma-city` checkout.
Existing shared campaign work is preserved. Godot remains the renderer; these
changes replace the tactical troop models and their animation, not the engine.

## What is playable

Tactical troops now have original joint-tagged geometry: shoulders, elbows,
knees, shields, weapons, heads, cloaks and horse legs move as coherent parts.
Resolved melee events produce a short windup, thrust or cut, shield reaction and
recovery. Contact-rank representatives fight; rear ranks keep weapons in guard.
Ranks close to their contact line and losses fall after the visual impact.
Mounted escorts have seated riders, bridles, saddle cloths, crests, cloaks and
command insignia. Metal roughness and fine surface variation reduce the former
uniform sheen. Peacetime garrisons use the same distinct specialist models.

These remain procedural representative miniatures (normally one model per four
troops, bounded at sixty per formation), not photorealistic humans or individual
physical combatants. No motion capture, per-blade collision, individual hit
simulation, ragdoll physics or imported image assets are claimed. Opposing units
retain faction-colored original equipment rather than a researched per-template
reconstruction. Animation is entirely presentation; damage comes only from the
fixed-tick formation engine and campaign results still cross BattleResolver once.

## Abilities and recruitment

All existing general-bodyguard templates use cavalry and the commander profile.
Roma can also recruit **Commander’s Mounted Escort** through **Barracks → Troops**:
base cost 1,200, forty population, upkeep 200, three civic days in Roma's city UI.
It requires barracks level three and a living, eligible local general who does
not already lead an army. One paid city escort per faction is allowed; pending
recruitment, owned garrisons and field armies all count. Legacy zero-cost
bodyguards remain unavailable for recruitment. The escort is a gameplay muster
option, not a new historical claim. Existing escorts remain eligible for funded
military training even while the recruitment cap prevents another cohort.

Each specialist has a passive improvement beyond the common template-quality
estimator. The selected unit's ability button and tooltip show availability,
duration, recovery, effects and passive training. Timers advance only in battle
ticks. Orders may be issued while paused, with no time elapsing until resumed.

| Formation | Passive damage / damage taken | Active ability | Duration / ready again |
| --- | --- | --- | --- |
| General's mounted guard | ×1.20 / ×0.88 | Rally: +18 morale and 15% less damage to unobstructed friendly cohorts within 18 m; escort deals 10% more damage | 12 s / 45 s from activation |
| Veteran legion | ×1.12 / ×0.92 | Disciplined assault: 45% more damage, +8 morale | 10 s / 35 s from activation |
| Elite spear guard | ×1.08 / ×0.90 | Brace: 45% less damage, cancels charge bonus, +12 morale; movement falls to 35% | 12 s / 40 s from activation |

Principes, cohort legionaries, eagle cohorts, Oathsworn of Mars and Gallic
Oathsworn use the veteran profile. Triarii, Silver Pikes, Sacred Band and Germanic
Spear Wall use the spear-guard profile. Mappings and all numerical tuning live
in `balance.city_battle.specialists`. No ability restores health or resurrects
routed troops. Rally effects do not stack; a defensive ability and rally use the
strongest active protection. A dead or routed commander cannot maintain rally.
The normal tactical counter cycle still applies, so elites are not invulnerable.
Enemy specialists use the same rules at unobstructed contact and obey the same
cooldown. General abilities are currently a Roma tactical-battle feature;
campaign auto-resolve still uses the existing unit and commander estimator.

## State, privacy and verification

New battles carry an optional `specialists_version: 1` plus specialty ids and
integer remaining/cooldown clocks. Existing in-progress battles retain their
original balance and gain no abilities mid-fight; start a new practice to see
them. Save validation rejects partial or malformed extensions. The renderer
uses detached snapshots and never resolves an unseen enemy template: only an
observed role and specialty can change that enemy's visible model. Picking
continues to use the interpolated formation anchors used by drawing.

The three adversarial review lenses found and prompted fixes for asymmetric
player/AI timer expiration, malformed old formation validation, premature enemy
rally through a closed gate, a missing Senate acquisition route, escort training
being blocked by its recruitment cap, and a legacy optional queue-field read.
Tooltip wording now states cooldown from activation and rally's obstruction
requirement. A suspected ordinary-health-bar indentation defect was disproved
and retracted; a regression assertion verifies all formations' strength bars.

`tools/swordplay_playtest.gd` buys the guard through the actual barracks button,
advances civic training, starts practice, and activates all three specialist
buttons. Controlled positions stage repeatable close combat; real simulation
commands determine damage and abilities. It captures several distinct attack
poses and mounted close views, checks paused state and saves, and uses isolated
QA storage. Images remain under `/tmp/roman-war-swordplay-final` outside the repo.
The final source rendering run passed with no script/shader/error diagnostics.

The updated `0.20.0-preview.20260927` universal Mac app is at
`build/roma-swordplay-20260927/Roman War Playtest.app`, with its matching ZIP,
frozen source and provenance beside it. All 548 frozen input hashes matched the
workspace after packaging. The builder passed schema data, import/export,
ad-hoc signature verification, both architectures and packaged save replay.
The exact exported app passed the swordplay playthrough with clean diagnostics
and screenshots under `/tmp/roman-war-swordplay-packaged`.

The fortress playthrough also passed after the troop changes, including paid
fortifications, archers, ignition, destruction and visible casualties. Campaign
map planning, marching, arrival and maximum-detail screenshots were inspected;
the rendered map gate passed. QA and screenshots used isolated storage outside
the repo. No production app or player save was replaced. Preview saves retain
the existing `Roman War Playtest` identity.

Full-suite release gate: **666 tests, 0 failures**, with no script/error diagnostics.
The existing anchored-control sizing warning remains in the headless UI suite;
rendered swordplay, fortress and map acceptance logs are clean. Data validation
reported **0 errors, 0 warnings**. `git diff --check` passed.
