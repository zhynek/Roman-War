# Roman War development roadmap

Updated 2026-09-26 from the [release audit](reviews/2026-09-26-release-audit.md).
The approved Mac baseline is now [release 0.14.2](releases/0.14.2.md), with
the full campaign and Alpine Route in one app and independent save slots.
This is a prioritized delivery plan; `DESIGN.md` remains the system specification
and `CLAUDE.md` remains the architecture contract. Milestones below are proposed
work, not features already delivered or calendar commitments.

## Product target

Build an original ancient Mediterranean strategy game in which campaign choices
create interesting armies, opponents and wars, and battles reward the player's
command. The current campaign is a useful foundation. The largest missing part
of the Rome-inspired experience is **player-controlled tactical combat**. More
unit records and a larger map will not substitute for that system.

The original [Rome: Total War manual](https://cdn.akamai.steamstatic.com/steam/apps/4760/manuals/manual_en.pdf)
is the reference for the two connected layers: settlement/faction management on
the campaign map and deployment, movement and combat on the battlefield. Its
fleet, siege and army sections inform the feature comparison. Reproduce the
depth of decision-making with original rules, values, prose and procedural art;
do not copy its assets or content. Interactive naval battles are optional future
expansion, not a prerequisite for matching the original's strategic fleet role.

## Starting point

| Area | Current game | Remaining depth |
|---|---|---|
| Campaign | 70 provinces, 21 faction records, construction, recruitment, trade, diplomacy, characters, succession, society, techniques, edicts and Roman politics | Campaign completion UX, faction balance, political choices, credible late-game challenge |
| Army command | Leaders, split/merge/transfer, fatigue, terrain costs, crossings, marches, forts and towers | Shared AI/player legality, improved reinforcement planning, explicit logistics design |
| Reconnaissance | Geographic reports and map agreements; local preview adds forest concealment and paid patrols | AI intelligence policy, playable ambush encounters and readable counterplay |
| Combat | Auto-resolution with class counters, generals, kit, terrain, morale, casualties and pursuit; animated result playback | Player deployment and orders, formations, flanks, missiles, tactical terrain, tactical AI and siege battlefields |
| Sea | Fleets, ship recruitment, harbours and sea movement | Fleet-dependent transport, naval combat, blockades, interception and AI island invasions |
| Presentation | Original procedural 3D campaign, classic comparison, portraits and illustrated cards | More convincing terrain/settlements/troops, clearer panel hierarchy, sound/music, accessibility and broad Mac QA |

These are system capabilities, not a claim that every faction or content record
is equally balanced. The current 92 unit templates and 70 techniques already
provide enough content to validate better mechanics before enlarging the roster.

## Delivery order and acceptance gates

| Milestone | Deliverable | Acceptance gate | Dependency / scale |
|---|---|---|---|
| M0 — Feedback build | Identifiable universal Mac campaign and Alpine-route previews, separate saves, checksums and reproducible source snapshots | Data/import/full tests pass; packaged save/replay probe and actual rendering pass; launch instructions and feedback checklist included | Current delivery; bounded release work |
| M1 — Campaign trust | Save integrity/recovery, legal-action parity, visible victory conditions, real unrest input to AI policy, reliable performance reporting | Corrupt saves cannot replace valid progress; old additive saves resume; identical player/AI movement refusals; every victory condition visible and testable | First follow-up; several focused changes |
| M2 — Strategic opponent | Weighted route planning, matchup-aware attacks/recruitment, meaningful persona choices, provincial policies and reconnaissance policy | Mountain/road, bridge, spear/cavalry and fortified-target scenarios show sensible choices; multi-seed campaigns remain deterministic and avoid persistent stalls | M1; medium system work |
| M3 — Playable field battle | One complete small infantry/missile/cavalry battle with deployment, orders, formations, fatigue, morale/routing, terrain and tactical AI | Different commands produce intelligible different outcomes; same command stream produces the same result across frame rates and save/resume; result commits once to campaign | M1 plus battle lifecycle design; major new subsystem |
| M4 — Mediterranean warfare | Embarkation/capacity, naval auto-resolution, escort/interception, blockades, AI fleet building and hostile-island landings | Embarked saves reload; lost transports cannot duplicate troops; blockade changes trade; AI completes an island invasion with player rules | M1–M2; independent of tactical renderer |
| M5 — Siege and campaign depth | Gates/walls/breaches/street fighting/reinforcements, distinctive faction campaigns, meaningful reforms and civil-war choices | Complete short campaigns for contrasting cultures and one Roman civil-war finish; siege choices change outcome and AI can attack/defend | Tactical sieges depend on M3; campaign content on M1–M2 |
| M6 — Production finish | Consistent procedural art and animation, original audio, onboarding, accessibility, Mac performance tiers and notarized release automation | Novice can finish the first 30 minutes; sustained play/quit/reload passes; measured Apple Silicon and Intel coverage; published artifact matches tested source | Continuous polish, final gate after complete core loop |

M3 is the largest experiential gain and the largest technical risk. Start its
design/prototype after M1, in parallel with bounded AI work. Do not postpone it
until every campaign expansion is complete, or expand it immediately to a full
commercial-scale army simulation.

## First implementation backlog

1. **Finish save UX.** This audit adds structural checks and safer files. Next:
   named slots, rolling autosaves, explicit recovery notices and compatibility
   fixtures from real prior builds. Avoid promising complete content validation
   from a structural validator alone.
2. **Unify attack legality.** Move the shared movement/crossing budget rule into
   a scene-free command boundary; AI must not attack after spending its march
   budget when a player could not. Rebaseline expansion in several seeds before
   changing aggression tuning.
3. **Expose all victory conditions.** Show territory counts, named provinces,
   rival survival and civil-war requirements with map focus and a deadline.
   Test the case where the region target is met but another condition remains.
4. **Repair the AI civic signal.** Compute the minimum order currently read as
   an absent `ai.min_order`; demonstrate that unrest changes policy priorities.
   Wire persona settings deliberately, removing promises from unused knobs.
5. **Replace hop-count planning.** Use terrain/road/crossing costs consistent
   with execution and full read-only battle estimates for target decisions.
6. **Make performance evidence portable.** Keep timing visible, but replace the
   brittle 600 ms correctness-suite gate with a reviewed calibrated benchmark
   or dedicated stable-runner performance job. Do not simply increase the limit.
7. **Reduce map/panel friction.** Preserve roster selection and scroll on refresh,
   keep the arriving army visible above controls, clear stale hover information
   during camera motion, and make the route briefing unobtrusive at 1280×800.

## Tactical battle architecture checkpoint

Keep `BattleResolver` as the campaign boundary and retain auto-resolve as a
supported choice. Its current synchronous call mutates unit arrays. A real-time
battle needs an explicit pending-battle and single-commit lifecycle around this
boundary, not just a replacement animation scene.

Before detailed battle art, prove a scene-free tactical state, fixed simulation
steps, deterministic commands and an isolated random stream. Test deployment,
orders, pause/speed, retreat, casualties, commander survival, save/resume and
exactly-once rewards. Rendered soldiers may interpolate; frames, tweens and
physics presentation must never decide campaign outcomes. Start with a bounded
six-versus-six formation exercise, set measured hardware budgets, and scale only
after the complete command-to-campaign-result path works.

## Expansion after the core loop

- Ground and sea supply with actual stocks, consumption, replenishment and
  attrition, if playtests support it. Today's connectivity report is not that
  simulation.
- Non-Roman court/assembly systems, richer civil-war allegiance, political
  bargaining and faction-specific campaigns.
- More historically grounded unit/building families, climates and theaters
  once their AI, art and balance coverage exists.
- Custom/historical battle scenarios and mod/content tooling after M3.
- Multiplayer and interactive naval combat only as separately scoped projects
  after the single-player campaign/battle loop is stable.

The procedural, no-image-assets policy remains in force. A different asset
pipeline needs an explicit product decision; it is not an incidental dependency
of better gameplay. Original audio can be scoped alongside the visual pass.

## Feedback that should drive the next build

Play the normal campaign for 10–20 turns and the Alpine route once. Record the
preview version, mode, seed, turn, faction and province. For each finding, say
what you expected, what happened, and what decision was confusing or enjoyable.
Attach a save when reporting a specific state; screenshots help for visual
issues. Rank the next investment among command clarity, opponent behavior,
tactical battles and visual detail. Use that feedback to choose the first M1
changes and the exact M3 battle slice.
