# Handoff — picking up Roman War in a fresh session

Everything an assistant (or a human) needs to be productive here within five
minutes. This deliberately does **not** repeat what the other docs cover:

| For | Read |
|---|---|
| Architecture rules, conventions, clean-room policy | [`CLAUDE.md`](../CLAUDE.md) (auto-loaded by Claude Code) |
| What every system does and the phase-by-phase status table | [`docs/DESIGN.md`](DESIGN.md) — §12 is authoritative |
| What the game is like to play | [`PLAYING.md`](../PLAYING.md) |
| How to produce a downloadable app | [`BUILDING.md`](../BUILDING.md) |
| Why the design is what it is | [`docs/research/rtw-research-report.md`](research/rtw-research-report.md) |

## 1. Where things stand

An original clean-room turn-based grand-strategy game of the 270 BC
Mediterranean, in Godot 4.4 / GDScript. The campaign engine is data-driven: 21
JSON tables under `data/` validated by `schemas/`, with a thin deterministic
rules engine in `src/core/`. Battles resolve behind a swappable
`BattleResolver` interface.

**Built:** Phases 0–4 (map & turns, settlements & economy, armies & sieges at
foundation depth, the full character/family layer), Phase 6 AI opponents
(modular `FactionAi` — deliberate wars, white peace, sieges, defence, sea
invasions, mustering, threat-based garrisons, priority construction; DESIGN.md
§9), the Phase 7 senate foundation loop, a playable Phase 8 campaign UI, and
the **guided campaign trail + points of interest** (DESIGN.md §10): 20
data-driven stages (16 tutorial-arc + 4 reactive with cooldowns), rewards
including permanent faction boons, 22 explorable sites, a quest panel, map
markers/highlights, and the player's raise-army action. Newest: the **building
yard** (DESIGN.md §10.3) — a drawer over the map that says what a building is,
what it does, what it leads to and why it is locked, with every building and
unit **drawn at runtime** from recipe data rather than image files.

**Green as of this branch:** 148 tests / 0 failures, validator 0 errors /
0 warnings, clean boot. Branch `claude/building-details-upgrades-kiq3tt`
(fast-forwarded from `claude/ai-opponents-5y68t6`). A Mac build from the pre-AI
foundation was delivered to the user, who is playtesting.

## 2. Get productive in five minutes

The container starts with **no Godot installed**. Get it:

```sh
cd /tmp && curl -sSL -o godot.zip \
  https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip
unzip -q godot.zip && chmod +x Godot_v4.4.1-stable_linux.x86_64
```

> **Always run `--import` first — and again after adding any `class_name` file.**
> ```sh
> godot --headless --path . --import
> ```
> This is the single biggest time-waster in this project. A missing or stale
> `.godot/` class cache produces bogus `Identifier "X" not declared in the
> current scope` parse errors on globals that plainly exist, causes test files
> to fail to load *while the runner still prints passes for them*, and can make
> the suite look like it is hanging. It cost time twice in one session. CI does
> this step explicitly for the same reason.

Then the three commands that must stay green:

```sh
python3 tools/validate_data.py                                   # 0 errors, 0 warnings
godot --headless --path . --script res://tests/run_tests.gd      # 100 tests, 0 failures (~35s)
godot --headless --path . --quit-after 5                         # clean boot, no output = good
```

`pip install jsonschema` if the validator complains about the import.

## 3. Building a playable app

`BUILDING.md` has the recipe. The four things that are painful to rediscover:

- **Export templates** are a separate ~1.2 GB download
  (`Godot_v4.4.1-stable_export_templates.tpz` from the same release page),
  unzipped into `~/.local/share/godot/export_templates/4.4.1.stable/`.
- **`textures/vram_compression/import_etc2_astc=true`** must stay in
  `project.godot`, or the macOS export dies with a configuration error.
- **macOS architecture must stay `universal`.** The stock template ships only a
  universal binary; an `arm64` export fails with "template binary not found"
  because thinning needs Apple's `lipo`, which does not exist on Linux.
- **Ad-hoc signing is mandatory for Apple Silicon** (`codesign/codesign=1`).
  arm64 macOS refuses to launch a fully unsigned binary outright rather than
  merely warning.

Delivering the build: `SendUserFile` caps at **30 MiB** and the universal zip is
56 MB. The fix used was to extract the arm64 slice from the Mach-O fat binary in
Python (fat header at offset 0, `cputype 0x0100000c`), overwrite the executable,
re-zip → 27 MB. **Verify `LC_CODE_SIGNATURE` (cmd `0x1d`) survives in the thinned
slice before shipping**, or the app will not launch.

## 4. Two determinism traps not in CLAUDE.md

1. **Sort keys in any loop that can steer an RNG draw.** A JSON round-trip
   reorders dictionaries, so an unsorted iteration makes a loaded save diverge
   from the live game. This shipped as a real bug once and the save round-trip
   test caught it only after the RNG fix below.
2. **`state.rng_state` is a decimal *string*, not an int.** JSON numbers are
   float64 and silently round a 64-bit RNG state to a multiple of ~1024,
   producing a different random stream after loading.

## 4b. The building yard, and the rules it added

Four things a newcomer will trip over otherwise:

- **`ConstructionRules.blockers_for` is the only answer to "may this be built".**
  It returns `{kind, params}`, and `available_projects` offers a chain iff the
  next tier has no blockers. Add a filter there and nowhere else, or
  `tests/test_building_info.gd`'s cross-check will fail — deliberately.
- **Sentences are content.** `data/effects_glossary.json` holds the wording;
  `src/core/` returns `{kind, params}` and never authors English. Numbers stay
  in `balance.json`. The schema refuses an `inert` effect without a note, which
  is what keeps `weapon_upgrade` / `armor_upgrade` (45 uses, no engine reader)
  from being sold to the player as working bonuses.
- **Effects are standing totals at a tier, not increments**, so an upgrade is
  worth `new - old`; and the five keys read through `effect_max` must be diffed
  against the best *other* chain in the town, or a shipyard claims recruit
  experience a Field of Mars already provides.
- **There are no image files and none may be added.** `BuildingArt` / `UnitArt`
  resolve a level or a unit into a parts list in a normalised 0..1 stage;
  `ArtPainter` draws it with the map's own primitives and palette. Never
  `randf()` — hash from the id, as `MapGeometry` does. Two traps that bite:
  `Array.sort_custom` is **not stable** (parts sort on `layer * 1000 + index`),
  and the plate cache must live on the resolver keyed to `GameData`, because the
  panels holding the plates are rebuilt on every player order.

Look at the art rather than reasoning about it:

```sh
SHOT_MODE=contact SHOT_KIND=walls SHOT_OUT=/tmp/walls.png \
  xvfb-run -a -s "-screen 0 1920x1200x24" godot --path . --script res://tools/screenshot.gd
SHOT_OUT=/tmp/yard.png SHOT_TURNS=8 SHOT_DRAWER=construction SHOT_CHAIN=roman_barracks \
  xvfb-run -a -s "-screen 0 1920x1200x24" godot --path . --script res://tools/screenshot.gd
```

Every visual fix in that work came from opening the PNG, not from reading code.

## 5. Ways forward

The user has not committed to a direction. Each is self-contained; pick one and
paste its prompt.

### Phase 5 — Agents & diplomacy
`DiplomacyRules` currently offers only symmetric stances and war declaration;
the UI sets a stance directly and the other side simply accepts. The
`personal_security` and `agent_skill` ancillary effects are authored in the data
and have **no engine reader** — they exist for this phase.

> Build Phase 5: diplomats, spies and assassins as campaign agents, plus a real
> negotiation model (offers, tribute, region deals, bribery) and an AI attitude
> model, replacing the direct set-a-stance panel.

### Phase 8 — Balance & polish
Driven by whatever the playtest surfaced.

> Here is what felt wrong when I played: <notes>. Tune the balance constants and
> UI accordingly.

If the user reports a problem, **ask for the world seed** — the same seed
reproduces their exact campaign, which makes any bug directly debuggable.

### The one the user actually wants next — societal trade-offs
The user's stated ambition for the core of the game: investment in military,
public benefit, learning and infrastructure should trade off against each other
in ways that are *felt* rather than tabulated, and that teach something true
about history and societies. Guns without bread works for a while, then does
not. They explicitly want **first-principles and physics-like, not a
ten-thousand-parameter cause-and-effect weighing scale** — or a deliberate
hybrid. The building yard is the natural surface for it: it already names what
each choice buys, so it can be made to name what each choice costs.

> Design and build the societal trade-off model: a small number of conserved,
> first-principles quantities (something like legitimacy, cohesion, capacity)
> that every investment moves in more than one direction, with lags and
> thresholds rather than per-building bonuses. Keep every constant in
> balance.json, keep it deterministic, surface it in the existing breakdowns and
> the building yard, and prove the emergent claim with long headless campaigns:
> an all-military build order must actually collapse, and for a legible reason.

### Phase 6 follow-ups — deepening the AI
The AI plays the whole game but uniformly; the thresholds live in balance
data and the behaviours in `src/core/rules/ai/` (DESIGN.md §9).

> Deepen the Phase 6 AI: per-faction personalities (an `ai` block in
> `factions.json` plus schema and validator coverage), AI mercenary hiring
> when a muster stalls, and smarter target scoring (economic value, wall
> discounting). Keep every knob in data, keep it deterministic, and verify
> with long headless campaigns across several seeds and difficulties.

Hostile single-region islands (Sardinia, Britannia, Crete, Rhodes, Cyprus)
are untouchable for everyone once at war — that unlock belongs to Phase 3's
amphibious landings, not to AI work.

## 6. Known gaps (verified, not guesses)

- **Starting families are adult men only**: 20 leaders, 19 heirs, 32 family, and
  **no spouses, no children, no `gender` field set** in `campaign.json`. The
  marriage path only opens once in-game births produce daughters, so the family
  tree bootstraps slowly. Seeding real households would fix it.
- **`office_gained` triggers are dead** until Phase 7 offices exist. The
  validator knows: `FORWARD_TRIGGERS` in `tools/validate_data.py` allowlists
  them, and warns about any *other* trigger kind no engine call site fires.
- **Phase 3 remainder**: embark-on-fleet transport (sea movement is an
  abstracted crossing today), naval battles, port blockades, forts and
  watchtowers, ambush. Until landings exist, a hostile single-region island
  cannot be invaded by anyone — the AI knows and does not try (DESIGN.md §9).
- **The map is a procedural painting** — `src/ui/map_geometry.gd` carves the 70
  region points into province polygons (wobbled coast discs cut by half-plane
  bisectors; straits kept open between sea-sharing non-adjacent regions), and
  `map_view.gd` paints them on two cached `Node2D` layers (sea, land) that a
  pan just moves — only ownership/fog changes (`repaint_land()` from
  `refresh()`) or a zoom LOD-band change rebake the land. Tokens, labels and
  badges stay in `MapView._draw` (screen space, every frame). Determinism is
  FNV-1a hashes of region ids — no RNG. Screenshot QA:
  `SHOT_OUT=x.png SHOT_ZOOM=-8 SHOT_TURNS=30 xvfb-run -a -s "-screen 0 1600x1000x24"
  godot --rendering-driver opengl3 --path . --script res://tools/screenshot.gd`
  (SHOT_ZOOM is in 1.15× steps; shoot turn 30 as well as 0 — fog hides most
  of the world at turn 0). No portraits or battle art yet — but buildings and
  units are now drawn (§4b), so the pattern for character portraits exists.
- **`weapon_upgrade` and `armor_upgrade` still have no engine reader.** 45 uses
  across the building data, zero call sites in `src/`. The UI is honest about
  it; wiring them into `AutoResolver` would be a small, self-contained win, and
  flipping `status` to `live` in `effects_glossary.json` is the only other
  change needed.

## 7. Process notes

- **Git identity must be `noreply@anthropic.com` / `Claude`** before committing,
  or a stop hook flags the commits as unverified and they need re-authoring.
  Develop on the branch the session assigns (this phase used
  `claude/ai-opponents-5y68t6`).
- **Run adversarial review agents after building anything substantial.** Three
  reviewers (engine correctness, UI behaviour, data/doc fidelity) found **37 real
  issues** the 60-strong test suite had missed — including armies declaring war
  by accident on the first turn, a save-determinism break, movement traits that
  silently did nothing, and generals still governing cities they had marched away
  from. Give each reviewer the research report plus a specific lens, tell them to
  run the suite themselves, and require findings-only output.
- When adding a rules module, add tests to `tests/` **and** cross-reference
  checks to `tools/validate_data.py` if it introduces a data table. Both gates
  must pass before committing.
