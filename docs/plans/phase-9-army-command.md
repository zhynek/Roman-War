# Phase 9 — Army Command: design and delivery plan

**Status:** increments 0–5 built and green on this branch (see §7); increments 6–8
specified below and pending. This document is the spec for the phase and the
record of what was decided, so the next session can finish it without
re-deriving anything.

**The ask (owner's playtest):** *"The biggest thing missing was the ability to
actually click on and move armies around on the map. In the Total War games
you can see, depending on how high the banner is filled, the strength of that
army; the same for ships and fleets. I want to move those characters around,
move armies by clicking, see what troops are in that army, and combine and
merge army forces."*

**How it was designed:** three independent designs (engine-first,
player-first, risk-first) were written against the code at commit `9026730`,
scored by three judges on different lenses, and synthesised. The risk-first
delivery skeleton won (foundations first, banners before any state change, the
save bump only when harbours land); the player-first presentation and input
model and the engine-first legality oracle were grafted in.

---

## 1. Decisions at a glance

| Question | Decision | Why |
|---|---|---|
| Select vs order | **Left-click selects** (a banner selects its force, a token its region, open sea clears). **Right-click orders** the selected force; a right-press that moves more than 4 px is a pan, not an order. **Shift + right-click = forced march.** | The genre convention. It also removes the trap where left-clicking a neighbouring city *to look at it* marched the army there. Trackpad users get **March to →** / **Sail to →** dropdowns on the force card. |
| Banner fill | `units / forces.max_units_per_force` (20), from the bottom, in the owner's colour. A **separate 2 px strength bar** beneath shows `soldiers / max_soldiers`. | Fill = stack size is what the banner means in the genre; depletion needs its own cue or a full-but-shattered army reads as full. |
| General vs captain | Gold finial disc above a general-led army (ringed white for the faction leader); none for a captain; fleets carry a white sail. | One shape difference, legible at 12 px. |
| Where finished ships go | A per-settlement **harbour** list (the ship analogue of the garrison). The player **launches** ticked ships into a chosen sea the port touches; fleets **dock** back. | Symmetric with garrison → raise; explicit zone choice on multi-zone coasts; harbour ships never fight on the walls nor count for public order; upkeep still applies. |
| Abstract sea crossing (`sea_move_army`) | **Kept** through this phase; fleet transport (inc. 6) is strictly more capable. Disabling it is a balance-pass decision (open question 1). | Julii start with no fleet or shipyard; the playtest contract survives. |
| Naval combat (inc. 7) | The same `BattleResolver.resolve` seam with additive context keys `naval: true`, `terrain: "sea"`. No second interface. | One seam is the architecture rule; ships are ordinary unit dicts. |
| Cargo (inc. 6) | Derived: `army.aboard = fleet_id` is the only link; cargo is found by scanning armies in sorted order. | No dual bookkeeping to desync. |
| Two generals in one stack | `merge_armies(from, into)`: `into` keeps its general; a captain's `into` takes `from`'s general; two led armies merge only inside a city the owner holds (the displaced general stays and governs by presence) and are refused in the field (`two_generals`). `detach_general` is own-city only. | No general is ever left standing in the wilderness; no companion or bodyguard subsystem. |
| Movement under regrouping | Army → army (and fleet → fleet): receiver keeps the lesser movement. Army → garrison: the settlement remembers, for the rest of the season, the least movement of any army that dropped units into it (`settlement.muster_march_left`, erased at the turn reset); raising or drawing units out of that garrison is capped by it. Fleet → harbour (docking or transferring) records `settlement.muster_sail_left` the same way and caps ships drawn from the harbour into a fleet. Making port costs a sea lane, so a port on two seas is a crossing, not a free jump. Splits copy movement. Launching a fleet spends the season. A general who leaves an army this season (steps down, garrisons, is displaced by a merge) remembers its remaining march (`character.march_left`, transient) and any army he takes over is capped by it. Nobody is raised or drawn out of a besieged city. | Closes raise → march → garrison → raise, dock → launch → sail → dock, ship relays through fleets and harbours, and general relays across fresh armies, with no per-unit bookkeeping. |
| Legality oracle | Every mutating rule has a pure `check_X(...) -> String` sibling returning `""` or a code from a closed vocabulary; `Game.check(action, args)` dispatches. | Buttons grey with a reason, the log explains refusals in the player's words, Phase 6 AI plans with the same predicate. |
| 20-unit cap | One reader, `ForceRules.max_units(data)` → `balance.forces.max_units_per_force`; the validator ties it to the campaign schema's `maxItems` for armies, fleets and harbours. | `CLAUDE.md`: tunables live in `balance.json`. |
| Disband | Men go home: population return in an own city (`forces.disband_population_return_pct`), never for mercenaries, never denarii. | Cannot be farmed for cash. |
| Save format | `SAVE_VERSION` 1 → 2 once, when harbours landed (inc. 5); version 1 still loads and ships are moved out of garrisons on load. | The owner's playtest save keeps loading. |

Non-goals for the phase: amphibious assault onto a hostile shore, admirals,
zones of control, ambush, forts and watchtowers, reinforcements in battle,
drag-and-drop, companions or bodyguard automation, AI use of the new API
(Phase 6), real-time battles.

---

## 2. Map presentation (`src/ui/map_view.gd`) — built

- **Banner** 12 × 20 px at zoom 1 (everything scales with zoom): dark frame,
  owner-colour fill from the bottom (`fill = units / cap`), dimmed once the
  force has spent its movement; a 2 px strength bar beneath, red → green by
  `strength_pct`; state outline red while besieging, orange while fatigued;
  gold finial for a general (white ring for the leader); white sail for a
  fleet; white outline when selected.
- **Placement:** army banners stand in a row to the upper right of the region
  token (own forces first, then allies and protectorates, then everyone else
  by owner, numeric id order within); fleet banners centre on the sea zone's
  authored `position` anchor. At most four slots; a `+N` chip stands in for a
  crowd (clicking it selects the region, whose panel lists everyone). Below
  zoom 0.6 banners give way to the old owner badges with a tick per force.
- **Sea anchors** are drawn for every zone (geography is not intelligence),
  with the zone name at zoom ≥ 0.8. Fleets on them are drawn only in seas the
  player has eyes on (`VisibilityRules.visible_sea_zones`: own-fleet seas and
  their neighbours, plus every sea touching an owned or occupied region).
- **One layout function feeds drawing and picking** (`_layout_banners`), so
  they cannot disagree and picking survives zoom and pan by construction.
  `_pick` tests banners and chips first (they sit inside the token's pick
  radius), then tokens, then sea anchors. Tooltips come from `_get_tooltip`.
- **Highlights** for the selected force: yellow = reachable this season,
  orange = by forced march only, red = a visible enemy army or at-war city in
  striking range; cyan rings on seas a selected fleet can sail to.
- The road/sea-lane graph is built once per map instead of on every redraw.

## 3. Interaction (`src/ui/campaign_screen.gd`, panels) — built

- `select_force(kind, id)` is the single entry point (banner click, panel
  button, Tab/N cycling). The selection follows a surviving force after an
  order or a battle, moves to the survivor of a merge, to the new army of a
  split or raise, to the new fleet of a launch, and persists across the end
  of turn; it is dropped when the force is gone. Esc clears the force, then
  the region; Tab / N cycles through own forces that still have movement.
- Orders: right-click a region → march (multi-step, cheapest path, halts on
  contact with something the fog hid, never attacks or besieges by itself);
  a visible at-war army adjacent → attack; an at-war city adjacent → siege.
  Acts of war are confirmed when not already at war, as before. A fleet
  right-clicks a sea to sail (multi-lane).
- **Force card** (`src/ui/panels/force_panel.gd`): header (general or
  *Captain's army* / *Fleet*, place, sheet link), stats line (units/cap, men
  standing/full, upkeep, movement left/max), fatigue and siege state, one row
  per unit (checkbox, name, strength bar, chevrons, upkeep). Actions:
  Garrison · Attack here · Lay siege / Assault (occupation choice) · **Regroup**
  (Transfer ticked → garrison or another army here; Merge into →; Split ticked
  under → captain / the general / a candidate; Disband ticked; Give command to
  … / Detach …; Consolidate depleted units) · Mercenaries · **March to →**.
  Fleets: Transfer ticked → another fleet; Merge into →; Split; Dock at →;
  Disband; **Sail to →**.
- **Region scroll** (`src/ui/panels/region_panel.gd`): garrison rows with
  checkboxes and **Raise army under →** (captain or any eligible man in the
  city), **Transfer ticked →** an army here, Disband; a **Harbour** section
  with **Launch fleet into →** (a touching sea) and Disband; *Retrain garrison
  and harbour*.
- Refused orders are logged in the player's words (`ForcePanel._explain`).

## 4. Engine (`src/core`) — built

State additions (all JSON-native; every reader coerces):

```
settlements.<r>.harbour: [unit]            ships only; upkeep counted; lost with the city
settlements.<r>.muster_march_left: float   transient; least movement of any army that dropped
                                           units here this season; erased by reset_movement
```

`ForceRules` (`src/core/rules/forces.gd`): `resolve/units_of/owner_of/summary`
for `army_N`, `fleet_N`, `garrison:<r>`, `harbour:<r>`; `armies_in`,
`fleets_in`, numeric `id_less`; `candidate_generals`; and the actions
`raise_army`, `transfer_units`, `merge_armies`, `split_army`, `disband_unit`,
`attach_general`, `detach_general`, `consolidate`, each with its `check_`
sibling. Error vocabulary: `not_found, wrong_owner, not_colocated, over_cap,
empty_selection, bad_index, last_unit, not_eligible_general, has_general,
no_general, two_generals, no_settlement, foreign_settlement, same_force,
is_ship, not_ship, not_docked, nothing_to_do, no_zone, besieged,
no_movement`; `Game.check` adds `wrong_owner`, `bad_args`, `unknown_action`.

`NavalRules` (`src/core/rules/naval.gd`): `zones_touching`, `harbour_of`,
`own_ports_on_zone`, `launch_fleet` (movement 0 on launch), `dock_fleet`
(costs a sea lane, records `muster_sail_left`), `merge_fleets`,
`split_fleet`, `normalise` (ships out of garrisons on load).

`MovementRules`: `movement_points_for` (the per-turn budget, shared),
`reachable(army, viewer_visible)` (fog-aware Dijkstra returning `reach` and
`blocked` with reasons), `march` (multi-step, halts on contact, forced as a
whole only when needed), `targets_for`, `fleet_reachable`, `sail`;
`reset_movement` grants fleets the Pharos `naval_movement_pct` bonus and
erases musters.

`Game` facade: `force_summary`, `reachable_regions`, `targets_for`,
`reachable_zones`, `forces_awaiting_orders`, `candidate_generals`,
`own_ports_on_zone`, `visible_sea_zones`, `check(action, args)`, `march_army`,
`sail_fleet`, `raise_army`, `transfer_units`, `merge_armies`, `split_army`,
`disband_unit`, `attach_general`, `detach_general`, `consolidate_units`,
`launch_fleet`, `dock_fleet`, `merge_fleets`, `split_fleet`. Every relocating
action refreshes governorship at once (`_after_relocation`), so a general who
marches out of his city stops governing it this turn.

Rules fixed on the way (found by the review): attacks require movement and
end the attacker's turn (no more unlimited attacks per turn); a siege from an
adjacent region pays the step and is refused while a hostile field army stands
at the walls (no more free hop); debt disbandment walks armies in sorted id
order (a loaded save disbands the same unit) and dissolves an emptied army
instead of leaving a ghost; general bodyguards (cost 0, government level 1)
are no longer recruitable; `SiegeRules.release` lifts a siege the moment its
besieger marches, garrisons, dissolves or dies; the campaign screen fills the
window instead of laying out at minimum size in a corner.

Data, schema, validator: `balance.forces {max_units_per_force,
disband_population_return_pct}`; `campaign.schema.json` settlement `harbour`;
`regions.schema.json` sea-zone `position` required; the validator ties the cap
to every `maxItems`, forbids ships in garrisons or armies and non-ships in
harbours or fleets, harbours on landlocked regions, and starting fleets in a
sea touching no coast.

Save: `SAVE_VERSION = 2`; `from_json` accepts 1 and 2, upgrading 1 (empty
harbours); `Game.load_from` runs `NavalRules.normalise`. Newer or version-0
saves are refused.

---

## 5. Increment 6 — Embark and disembark (pending, ≈ 1 day)

State: `armies.army_N.aboard: fleet_id | null`, with the invariant
`aboard != null ⇔ region == ""` (an embarked army is in no region; its general's
location is `""`, which `refresh_governors` already skips).

`balance.naval { transport_capacity_per_ship: 4, embark_cost: 1.0,
disembark_cost: 1.0 }` (schema + validator: keys present, capacity ≥ 1, warn if
embark + disembark exceed the base movement — no same-season strait hop).

`NavalRules`: `capacity(data, fleet) = ships × transport_capacity_per_ship`;
`cargo_of(state, fleet_id)` (sorted army ids with `aboard == fleet_id`);
`cargo_units`; `boardable_fleets(army)` (own fleets in touching seas with spare
capacity); `landing_regions(army, viewer_visible)` (coasts of the fleet's sea
with no *visible* hostile army and no at-war holder — hidden hostiles are
listed and refused on contact, like `march`); `embark(army, fleet)` — ashore,
`movement_left ≥ embark_cost`, same owner, fleet in a touching sea, not the
besieger of a live siege (refuse rather than lapse), capacity; sets
`region = ""`, `aboard`, deducts the cost, syncs the general's location;
`disembark(army, region)` — fleet's sea touches the coast, `movement_left ≥
disembark_cost`, no hostile army present, holder not at war (**landing on a
war shore is never a move**); sets region, `aboard = null`, deducts the cost.
`merge_fleets` re-points cargo to the survivor and requires the merged
capacity to cover it; `split_fleet` keeps cargo with the source; `dock_fleet`
refuses with cargo aboard; `disband_unit` refuses a fleet's last ship with
cargo aboard.

Aboard guards (every reader of `army["region"]`): `visible_regions` skips
aboard armies; `can_enter`/`move_army`/`sea_move_army`/`begin_siege`/
`attack_army`/`hire`/every `ForceRules` action refuse them (`aboard` error);
`MapView` lays out no banner for them — the fleet's banner gains a cargo mark
(a small filled square in its top band) instead. Faction death: aboard armies
defect with everything else.

UI: with an army selected, a right-click on one of our fleet banners in a
touching sea embarks; the force card lists **Embark on →** fleets. With a fleet
selected, right-clicking a ringed coast lands its first cargo army (the card
offers **Land … at →** per army). Highlights: `embark` (cyan outline on
boardable fleet banners), `land` (cyan rings on landing coasts).

Tests: embark/disembark round trip with costs; capacity refusals; a war shore
refused; a hidden hostile discovered on landing; merge/split/dock with cargo;
fog never reveals a hidden army through `landing_regions`; `round_trip_equal`
on embark + sail + disembark; `test_sea_move_army_disabled_by_data` (setting
`movement.sea_move_cost` above the base budget switches the abstract crossing
off).

## 6. Increment 7 — Naval combat and blockade (pending, ≈ 1.5 days)

`balance.naval.blockade_sea_trade_loss_pct: 100`; `balance.battle.
terrain_defense_multiplier.sea: 1.0`; state `fleets.fleet_N.blockading:
region_id | null`.

`NavalRules.attack_fleet(data, state, resolver, rng, attacker, defender)`:
different owners, same or adjacent sea, `attacker.movement_left > 0`; declares
war (as `attack_army` does); `resolver.resolve(data, rng, attacker.ships,
defender.ships, {terrain: "sea", wall_level: 0, attacker_general: null,
defender_general: null, attacker_fatigued: false, sally: false, naval: true})`.
A winner in an adjacent sea moves in; the attacker's movement ends; both
blockades clear. A fleet left with no ships is erased and every army aboard is
lost (general killed, as `_cleanup_destroyed_army` does). **Foundering**: a
surviving fleet whose capacity now falls below its cargo drops units from the
tail of the highest-id cargo army until it fits — deterministic, no RNG.
`Game.attack_fleet` threads the RNG like `attack_army`.

Blockade is an **explicit, port-gated order**: `blockade_port(fleet, region)`
requires the fleet's sea to touch the region, a settlement that is not the
owner's, `port_level > 0`; declares war (the UI confirms first);
`fleet.blockading = region`, movement 0. `lift_blockade`; `is_blockaded(region)`
(a fleet with `blockading == region`, in a touching sea, whose owner is
*currently* at war with the holder); `refresh_blockades` clears stale ones and
runs in `TurnEngine.end_turn` after sieges and before treasuries. Effects:
`EconomyRules.trade_income_parts -> {land, sea, blockaded}` — a sea route
requires neither end blockaded; the income breakdown appends a named
`blockade` factor; `GrowthRules._grain_routes` requires the port not
blockaded. Map: a blockading fleet's banner outlines red and the port gets a
dotted red ring; the panel prints *BLOCKADED by X*.

The resolver contract comment (`battle_resolver.gd`, `DESIGN.md §5.5`)
documents `naval: bool` as an optional key `AutoResolver` ignores.

Tests: naval battle through the seam (determinism, sinking, cargo lost,
foundering), blockade declares war and cuts trade and grain, stale blockades
cleared by peace or movement, `round_trip_equal` on attack + blockade, and a
`test_same_seed_same_world_with_navies` integration run.

## 7. Increment 8 — Docs and closure (pending, ≈ 0.5 day)

`DESIGN.md` §2.2, §2.4, §5.3–5.5, §9.3, §10; `PLAYING.md` *Armies* and
*Fleets* (the walkthrough below); `HANDOFF.md` §1, §6; `schemas/README.md`;
`new_game.gd` header; an adversarial three-reviewer pass over increments 4–7;
the open questions put to the owner.

---

## 8. Delivery record

| # | Increment | Commit | Tests |
|---|---|---|---|
| 0 | Foundations: `ForceRules.summary`, cap in balance, `movement_points_for`, sorted debt disband, `SiegeRules.release`, attack/siege movement guards, bodyguard recruit filter | `88590d6` | 77 |
| 1 | Banners you can click; left selects / right orders; fleets on the map; sea visibility | `c14f3ce` | 80 |
| 2 | Fog-aware reachability, multi-step march, fleet sailing, in-turn governor refresh | `a0618cc` | 86 |
| 3 | The force card | `230fb98` | 87 |
| — | Fix: the screen laid out at minimum size in a corner of the window | `42e34c2` | 87 |
| 4 | Regrouping engine and UI (raise, transfer, merge, split, disband, generals, consolidate) | `06a4484`, `d2dc047` | 95 |
| 5 | Harbours, launch/dock/merge/split fleets, save v2 | `bdd37be` | 100 |
| 6 | Embark / disembark | pending | |
| 7 | Naval combat and blockade | pending | |
| 8 | Docs and closure | pending | |

Every increment ended with the validator at 0 errors / 0 warnings, the suite
green, a clean boot, and a screenshot check of the UI under a virtual display.

## 9. The player's first turn (acceptance walkthrough)

Seed 42, Julii. Beside Umbria's token stands one banner: Julii-coloured, a
quarter full (5 of 20 units), a gold disc above it (Lucius Julius leads), a
green strength bar beneath. Beside Apulia a Junii banner with its own gold disc.
Out in the Tyrrhenian Sea, at the sea's anchor, the Cornelii fleet's banner
with a white sail, one-tenth full. Hover the Umbria banner: *Lucius Julius
(House of the Julii) — 5 units · 460 men (100%) · 2.25 mp*. Left-click it: a
white outline, and the force card — five unit rows, *Units 5/20 · Men 460/460
(100%) · Upkeep 640/turn · Movement 2.25/2.25*, *General: Lucius Julius —
command 7*. Yellow rings on Arretium, Roma and (two steps away) Tarentum;
Mediolanum, a rebel city, rings red. Right-click Arretium: the banner
reappears there, the card reads *0.75/2.25*, the rings shrink, the log says
*The army marches to Etruria.*, and Umbria now shows *No governor* — Lucius
left this turn. Left-click the Arretium token: the settlement scroll; tick a
garrison unit, *Raise army under → a captain*: a second banner stands beside
the first and is selected. *Merge into → Lucius Julius's army*: one banner, six
units, the card follows. End turn: the selection survives; *Movement 2.25/2.25*.
Press N: *Every force has its orders.*

## 10. Open questions for the owner (with the defaults taken)

1. **Abstract sea crossing.** Kept alongside fleet transport for now; decide
   in the balance pass (a data switch, `movement.sea_move_cost` above the base
   budget, disables it) — or remove it so only fleets cross water, which means
   the Julii need a port and shipyard before any sea move.
2. **Two led armies merging in the field.** Refused with *transfer units
   instead, or merge in one of your cities* (taken) — or keep a one-unit
   residual army for the displaced general.
3. **Disband refund.** Men return to an own city's population and no denarii
   ever (taken) — or add a `forces.disband_refund_pct`.
4. **Enemy banner detail.** Full detail in visible regions — fill, strength
   bar, general finial (taken; it makes scouting worth doing) — or unit count
   only.
5. **Transport capacity** (inc. 6). 4 units per ship, so a full stack needs
   five ships (proposed) — or 5.
6. **Blockade reach** (inc. 7). A blockaded port also drops out of its
   partners' sea routes (proposed) — or only the blockaded port loses income.
7. **Launched fleets start with 0 movement** (taken) — or 1 point so a fresh
   fleet can leave port the same season.
