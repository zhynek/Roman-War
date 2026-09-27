# Roma fortress and siege presentation — 2026-09-27

This work retains the occupied `codex/roma-city` checkout and its existing
continuous-battle/shared-campaign changes. `origin/main` was fetched and verified
as `95cc24b`; the local branch is one commit ahead with no missing trunk commits.
No prior work was reset, replaced, or published.

## Player-visible changes

- **Inspect defenses** opens a peacetime inspection ledger. Visit the south gate,
  curtain wall and barracks through the existing collision-checked relocation
  flow; ordinary walking remains available. Fund works from the inspection and
  review actual costs, days, maintenance and civic consequences.
- **Reinforce the south gate** costs 950 denarii, takes four ordinary civic work
  days and costs six denarii per day in completed maintenance. It adds 80 gate
  integrity to a newly begun siege, with visible bracing and iron straps.
- **Prepare incendiary arrows** costs 600 denarii, takes three civic work days,
  and costs four denarii per day in completed maintenance. Preparation unlocks
  the fire-arrow command. Both projects add the named civic burden/legitimacy
  effects authored in balance data; neither can be funded or progressed during
  a siege. In-progress work provides no battle benefit.
- New sieges contain a wheeled, covered **battering ram**. Nearby surviving
  attackers crew it; it advances, strikes the actual gate and can be destroyed.
  With archers deployed near the gate, **Target siege ram** and **Use fire
  arrows** send actual volleys against it. Three full-strength incendiary volleys
  ignite its timber. Fire then consumes its health. Remnant cohorts generate
  proportionally less damage and heat. A destroyed or abandoned ram cannot
  strike. Infantry can still batter the gate slowly, so burning the ram delays
  the assault rather than making the city invulnerable.
- Arrow shafts, heads and fletching follow parabolic trajectories. Fire, smoke,
  charring, wheel/beam motion, hit reactions and fallen troop representatives
  make the combat legible. Cosmetic troop losses wait for visible arrow impact;
  pause freezes pending effects. Final effects may finish after combat ends.
- Buildings have staggered mortar courses, mineral variation, chipped lime
  exposing masonry, and timber fibres. Gate arches, tower apertures, bracing
  and curtain buttresses add depth. All geometry/materials remain original and
  procedural; no image assets were introduced.

The desktop default now uses Godot **Forward+**, with city ambient occlusion,
indirect screen-space lighting, glow and 4x MSAA. Compatibility remains selectable
with `--rendering-method gl_compatibility`; its materials and siege effects use
the same code, with advanced lighting conditionally disabled. Mobile retains its
existing Compatibility setting.

## Engine decision and limits

The prior appearance was not evidence that Godot needed replacement. The game
used its Compatibility renderer and simple procedural models. Godot already
provides [physically based materials](https://docs.godotengine.org/en/4.4/tutorials/3d/standard_material_3d.html)
and [multiple rendering methods](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html).
Keeping the deterministic simulation and upgrading the rendering path makes
this improvement concrete without an engine migration.

This remains a procedural visual preview. It is **not finished photorealism**.
More detailed anatomy, skinned character/archer animation, authored architectural
variety and richer material work remain necessary for that goal. This change
implements ram fire; it does not implement city-wide fire propagation, masonry
destruction, traversable elevated ramparts or individual projectile physics.
Combat still resolves at formation level. A displayed fallen model represents
multiple casualties, and remains cosmetic.

## State and rendering boundaries

`CitySiegeRules` owns integer equipment HP, heat, cooldowns and positions. All
movement, ignition, gate damage and casualties occur in explicit deterministic
battle ticks. No timer, animation, shader or UI frame advances gameplay or RNG.
The existing `BattleResolver` seam still commits real campaign consequences once.
Practice uses copied formations and preserves the campaign garrison and RNG.

The new equipment/preparation fields are optional save extensions. Existing
continuous fights resume their existing siege rather than gaining a ram halfway
through play. Civic project migration follows the existing additive project-key
migration; older cities gain unfunded projects. Inspection queries are read-only.
Save validation checks equipment even before legacy battle migration.

A bounded, numbered event history lets a renderer receive volleys despite polling
between ticks. Presentation only receives detached snapshots and retains the
existing hidden-roster rules. The ram begins at its saved position when a view
opens; visual troop counts and hit reactions wait for the projectile animation.
The scene-free line test samples the high ram volley against authored wall and
building/roof heights. The arrows are a presentation of resolved formation damage,
not a claim of independent collision simulation for every arrow.

## Verification

- Data/schema/cross-reference validation: **0 errors, 0 warnings**.
- Full regression suite: **651 tests, 0 failures**, no error diagnostics.
- After final visual fixes, focused siege/save/UI/presentation verification:
  **18 tests, 0 failures**, including two new presentation regressions beyond the
  full-suite run. Final gate geometry executes without runtime errors.
- Rendered fortress playthrough: actual funding clicks, all three reachable
  inspection points, campaign-preserving inspection, actual archer recruitment,
  strengthened gate, fire-arrow orders, ignition, ram destruction and fallen
  representatives. Final run has no script or renderer error diagnostics.
- Campaign-map playtest: planning, marching, arrival and maximum zoom passed under
  Forward+. All four required images were inspected. Local maximum-zoom sample:
  6.90 ms median, 7.23 ms p95 at 1600x1000 on Apple M3 Max; this is one short
  sample, not a hardware guarantee.
- Three adversarial reviewers checked determinism/save integrity,
  data/schema/presentation, and gameplay/balance. Verified fixes cover malformed
  legacy equipment, remnant archer fire strength, loaded ram placement and
  projectile/impact timing.

QA screenshots stay outside the repository. `tools/fortress_playtest.gd` writes
its default output to `/tmp/roman-war-fortress-qa`. The QA storage helper preserves
only the shader-cache directory skeleton when isolating `user://`: Godot 4.4
starts some Forward+ shader compilation before the test script changes storage.
It copies no cache contents or player saves. Earlier diagnostic runs exposed a
cache-directory error and an arch array-type error; both are absent in the final
acceptance run.

## Local preview

`build/roma-fortress-20260927/Roman War Playtest.app` and the matching
`0.19.0-preview.20260927` universal ZIP contain a frozen copy of the current
checkout, including the existing shared Roma campaign work. The builder verified
schema data, clean import/export, ad-hoc signing, Intel/Apple Silicon slices,
version, campaign save replay and tactical save replay. The exact exported app
also passed the rendered fortress playthrough with no error diagnostics; all
packaged source hashes still match the workspace. Production was not
published or replaced. Preview storage remains the existing Roman War Playtest
save directory; QA exercises use separate per-process directories.

To play: **Enter Roma → Inspect defenses**. Fund gate reinforcement and fire-arrow
stores, recruit Allied Bowmen in the barracks, and advance the required civic
days. Start **Defend Roma → Practice siege**, deploy the bowmen on the street just
inside the south gate, then choose **Target siege ram**, **Use fire arrows**, and
**Begin battle**. Existing in-progress battles retain their old equipment state;
start a new practice to exercise the new ram.
