# Rome: Total War (2004) — Design-Document Research Report for an Original Mac Strategy Game

## TL;DR
- **Build the campaign (strategy) layer first and make it fully data-driven.** Rome: Total War's settlements, economy, buildings, factions, traits, events, and campaign setup all live in plain-text data files; replicating that pattern (JSON/YAML tables + a small deterministic rules engine) is the single most important architectural decision, and it is exactly what suits an AI-assisted solo developer.
- **Treat battles as a swappable module from day one.** Ship an auto-resolve `BattleResolver` in the foundation and design its interface so a real-time battle scene can be plugged in later without the campaign code changing.
- **Use Godot 4 (recommended) or native Swift, and stay clean-room.** Mechanics/rules are not copyrightable, so a spiritual successor is low-risk as long as you use an original name, original art/text/music, and author your own data tables — copying no assets or files.

## Key Findings
1. **Two-layer game, campaign-first.** RTW's Imperial Campaign runs 270 BC → 14 AD at **two turns per year**; the campaign map is a network of regions each with exactly one governing settlement. Your foundation targets this layer.
2. **Settlements are the heart of the game.** Population-driven settlement levels, the squalor-vs-growth balancing act, public order (Law vs. Happiness), taxes, culture penalties, and the occupy/enslave/exterminate decision are the highest-priority systems.
3. **Culture drives everything asymmetric** — building trees, unit rosters, temples, and settlement caps (barbarians are hard-capped below the top city tiers).
4. **Roman politics (the Senate, offices, civil war, Marian reforms) is iconic** and applies only to Roman factions — a distinctive feature worth reproducing conceptually.
5. **The data-file architecture is a gift for AI-assisted development** — it decouples content from engine and makes the game testable and moddable.
6. **Godot 4 is the best-balanced stack**; native Swift is the alternative for a "true Mac app." A clean-room spiritual successor is legally low-risk.

---

## 1. Game Overview & Turn Structure

Rome: Total War was released for Microsoft Windows on **22 September 2004 by Activision (developed by The Creative Assembly)** (per Wikipedia's "Rome: Total War"). It has two layers: a turn-based grand-strategy **campaign map** and a real-time tactical battle engine. This report covers the campaign layer in depth and treats battles at interface level.

- **Timeline & seasons:** The Imperial Campaign runs 270 BC → 14 AD, with **two turns per year (summer and winter)**. Seasons mainly affect map visuals and attrition flavor; the economic/growth cycle resolves every turn.
- **Campaign geography:** The map is divided into **provinces/regions**, each containing exactly **one settlement** that governs it. Regions have terrain (plains, forest, hills, mountains, desert), rivers crossed at bridges (chokepoints), roads (built as buildings; raise movement and trade), sea regions with ports and sea lanes, and **fog of war** based on line-of-sight from settlements, armies, agents, and watchtowers.
- **Turn resolution order (end-turn):** player actions → end turn → AI factions take their turns → resolution of income, population growth, construction completion, recruitment completion, random/scripted events → notifications delivered via event scrolls at the start of the player's next turn.
- **Movement:** Each army/character has movement points per turn; roads increase distance, rough terrain reduces it. **Forced march** roughly doubles range but leaves troops fatigued/vulnerable. Zones of control let armies block passage (notably bridges). Forests enable ambushes.
- **Campaign modes:** Imperial Campaign (full map; long or short victory), a **Prologue/tutorial** campaign following the Julii, and standalone **historical battles** (out of scope for the strategy layer). Short vs. long changes victory conditions only.

## 2. Factions & Cultures

RTW groups factions into **culture groups** that determine building trees, unit rosters, temples, and settlement caps. Community-documented assignments:

| Culture group | Factions |
|---|---|
| Roman | House of Julii, House of Brutii, House of Scipii, Roman Senate (SPQR) |
| Greek | Greek Cities, Macedon, Seleucid Empire, Thrace |
| Eastern | Parthia, Armenia, Pontus |
| Carthaginian | Carthage |
| Egyptian | Egypt |
| Barbarian | Gaul, Germania, Britannia, Dacia, Spain, Scythia, Numidia |
| Neutral | Rebels/Eleutheroi (independents), Slaves |

**Playability/unlocking (vanilla original game):** Only the three Roman houses (Julii, Brutii, Scipii) are playable at start. Completing a short or long campaign with any starting faction unlocks the **unlockable** set (Egypt, Seleucids, Carthage, Parthia, Gaul, Germania, Britannia, Greek Cities). **Destroying** an unlock-eligible faction in a campaign also unlocks it. A third tier (Macedon, Pontus, Armenia, Dacia, Numidia, Scythia, Spain, Thrace, and the Senate) is marked non-playable and can only be played by editing `descr_strat.txt` (moving faction names into the "playable" block; unlocking the Senate/slaves can crash the game). **Total War: Rome Remastered (released 29 April 2021)** unlocked "16 additional factions that were previously locked, giving a grand total of 38 playable factions" (per Creative Assembly's official list via GameWatcher).

- **Culture determines settlement level caps:** **Barbarian factions are hard-capped** and cannot build the top government tiers / cannot reach the Imperial-Palace "Huge City" in the Imperial Campaign — a hardcoded restriction (lifted in the Barbarian Invasion expansion). This is a major balance asymmetry: barbarian provinces hit squalor problems earlier because they cannot build advanced sanitation/entertainment buildings. (Sources conflict on whether the cap is Minor City or Large City; the confirmed fact is barbarians cannot reach Huge City / build an Imperial Palace in vanilla.)
- **Cultural penalty on conquest:** Capturing another culture's settlement imposes a **culture penalty** to public order, proportional to the ratio of foreign-culture buildings to your own. It drops as you demolish/upgrade foreign buildings (temples especially). Some buildings in captured Huge Cities can't be upgraded/removed, leaving a residual penalty.
- **Community-summarized faction identities (examples):** Julii = anti-Gaul frontier Romans; Brutii = pointed at Greece/Balkans; Scipii = aimed at Sicily/Carthage/Africa; Egypt = rich Nile farming with distinctive (historically inaccurate) chariots/pyramid units; Seleucids = huge but surrounded, elite pikes and elephants; Carthage = naval/mercenary strength + Sacred Band; Parthia = horse archers and cataphracts; Greek Cities = superb hoplite phalanx but weak early cavalry; Gaul/Germania/Britannia = cheap mass infantry, warbands, chariots/druids/berserkers; Numidia = desert skirmishers.

## 3. Settlements / Towns (Highest Priority)

### Settlement levels & population thresholds
Upgrade thresholds are **hard-coded** in vanilla. Per TWC Wiki ("Population"): "2000 to upgrade to a Large Town, 6000 for a city, 12000 for a Large City, and 24000 for a Huge City...in Rome Total War...these values are...hard coded."

| Level | Population to reach | Notes |
|---|---|---|
| Village | 0 (start) | smallest; few building slots |
| Town | ~800 | Governor's House |
| Large Town | 2,000 | |
| Minor City | 6,000 | walls, more military |
| Large City | 12,000 | |
| Huge City | 24,000 | max; non-barbarian cultures only |

### Government (core) building chain per culture
The central building must be upgraded to raise settlement level. Confirmed chains (internal codes `governors_house → governors_villa → governors_palace → proconsuls_palace → imperial_palace`):

| Settlement level | Roman | Greek / Eastern | Barbarian |
|---|---|---|---|
| Village–Town | Governor's House | Governor's House | Warrior's Hold |
| Large Town | Governor's Villa | Governor's Villa | Warlord's Hold |
| Minor City | Governor's Palace | Governor's Palace | High King's Hall (top for barbarians) |
| Large City | Pro-Consul's Palace | Councillor's Chambers | — (capped) |
| Huge City | Imperial Palace | (top tier) | — (capped) |

Carthage and Egypt use the standard "Governor's" civilised set (no confirmed unique names in vanilla). The **Imperial Palace triggers the Marian reforms** (see §8). Government buildings' main public-order relevance is the **culture penalty** avoided by upgrading to your own culture's version; per-tier explicit law bonuses are not well documented in vanilla. Approximate build times (single-source, verify): Governor's Villa ~2, Governor's Palace ~3, Pro-Consul's Palace ~4, Imperial Palace ~6 turns; exact denarii costs are not documented.

### Population growth
Growth is a per-turn percentage summing positive and negative factors (each on-screen icon ≈ 0.5%; per MarekBrutus's GameFAQs "City Management Guide"):
- **Positive:** base farming/fertility of the region (fixed); farm building upgrades (+0.5% each, up to ~+2.5% — farms cannot be demolished); health buildings (each +10% health ≈ +1% growth); markets and certain temples; **low taxes** (+0.5%); **slaves** from enslaving (temporary, ~20 turns, distributed to governed cities); governor traits/ancillaries; wheat/food-import trade routes (~+1.5% per wheat route, ~3% for two, ~4% for three).
- **Negative:** **squalor**; high/very-high taxes (−0.5%/−1%); **plague** (up to ~−10%); recently captured penalty; some governor traits.

### Squalor
Squalor rises with population and is the main growth counterweight. Community approximation: for a city with the top core building, **~3,000 people ≈ 1% squalor** (a 24,000 Huge City ≈ 8% negative growth from squalor alone), capped around −25% growth. There is **no permanent way to reduce squalor** other than building core buildings promptly and capping population (recruit peasants to drain population, enslave/exterminate, or deliberately trigger revolts). Squalor also reduces public order.

### Public order / happiness
Displayed as a percentage; the player adds a base +100% to the sum of factors. **Below ~75% → unrest/riots; sustained very low → revolt** (settlement secedes to the Rebel faction, garrison may be expelled/destroyed). Two distinct axes matter: **Law** (reduces corruption AND unrest) and **Happiness** (unrest only).
- **Positive factors:** garrison size (suppression), **low tax rate**, governor influence (~+5% per influence point), entertainment buildings (arenas, amphitheatres, circus), law buildings, health buildings, temples (happiness and/or law), Senate-thrown games (temporary), population-boom bonus, and certain wonders (e.g., Statue of Zeus +4 loyalty).
- **Negative factors:** **squalor**, **distance to capital**, **culture penalty**, high taxes, no governor, recently conquered unrest, plague, religious/cultural unrest.

### Distance to capital
Per therother's research on totalwar.org ("Distance to Capital Public Order penalties"): "There is no penalty within 15 squares of your capital. The penalty is always 80% over 86 squares away. The penalty increases by ~1% per square." You can **move the capital** (settlement details scroll) to re-center the empire; corruption (a money drain) scales with distance and low law.

### Tax levels
Five rates (very low / low / normal / high / very high). Higher taxes raise income but lower public order and growth; **low tax gives +0.5% growth**, very high gives −1% growth. Per-settlement tax management is the primary lever balancing income vs. order.

### Building categories (per culture, examples)
- **Government/core:** see chain above; gates settlement level and unit tiers.
- **Walls/defense:** wooden palisade → wooden wall → stone wall → large stone wall → epic stone wall (higher walls add arrow/ballista towers, boiling oil, iron gates; longer sieges).
- **Military:** barracks (infantry), stables (cavalry), archery ranges (missiles), siege engineer's workshop (artillery), city/port for naval; blacksmith/armourer for weapon & armour upgrades.
- **Economy:** markets/traders/forums (trade + some growth); farms (Land Clearance → Communal Farming → Crop Rotation → Irrigation → Latifundia; each +0.5% growth and farm income; **cannot be demolished**); roads → paved roads → highways (movement + trade); ports (sea trade + ships); mines (income where an ore resource exists).
- **Health:** sewers → public baths → aqueducts (health, growth, reduced plague chance).
- **Entertainment:** arena → amphitheatre → colosseum; execution square; odeon/theatre; hippodrome/circus (public order; some give order without growth = squalor-safe).
- **Education:** academy → scriptorium → ludus magna (management/education traits for family members; spawn ancillaries).
- **Temples:** one god per building slot; bonuses vary by god and level.

### Temples & god bonuses (representative, from community guides)
Temple levels are Shrine → Temple → Large Temple → Awesome Temple → Pantheon. Effects group into archetypes:

| Temple archetype (example gods) | Primary effect |
|---|---|
| Fertility (Ceres/Isis/Freya) | Happiness + population growth (e.g., Julii Ceres: +5%/+10%/+15% happiness and +0.5%/+1%/+1.5% growth up the tiers) |
| Law/order (Jupiter/Zeus) | Law + happiness (e.g., Jupiter +5% law +5% happiness) |
| Fun (Bacchus/Dionysus) | Larger happiness (~+10%) but risks "drunkard" governor traits |
| Trade (Mercury/Milqart) | Trade income + happiness; top tier can give +experience |
| Battle/violence (Mars/Ares) | Troop morale/experience, weapon upgrades; can train special units (Carthage Sacred Band at top Baal temple; Julii Mars pantheon trains arcani) |
| Naval (Neptune, Scipii) | Weapon/armour upgrades at top tier |
| Healing (Juno/Asclepius) | Health, growth |
| Forge (Vulcan/Hephaestus) | Weapon/armour upgrades; good-engineer/miner traits |

### Occupation options on capture
- **Occupy:** keep the entire population; smallest loot; **highest post-conquest unrest**; preserves recruitment pool and fast upgrades.
- **Enslave:** removes a sizeable portion of the captured population and **distributes slaves among your other governed cities** (boosting their growth ~20 turns); moderate loot; less order damage to the captured city than occupy; good for growing backwater towns. (Reports on exact split vary — commonly ~50% removed, recipients getting a fraction; verify.)
- **Exterminate:** kills a large share of the population; **largest immediate cash** (loot roughly equals the number killed); **best public order** (fear + less squalor) but hurts the long-term tax base. Typically reserved for large hostile-culture cities (e.g., Carthage) or repeat-rebel cities.

### Other settlement mechanics
- **Governed vs. ungoverned:** a settlement with a family member present is "governed" — the governor's traits/ancillaries/influence modify order, growth, and income; ungoverned cities run on auto-management with weaker order.
- **Walls & sieges:** wall tier sets siege difficulty; besiegers build equipment over turns (rams, ladders, towers, sap points) or starve defenders (duration depends on settlement supplies).
- **Forts & watchtowers:** built by generals in the field; watchtowers extend vision; forts provide defensive terrain and block movement.
- **Plague:** probabilistic each turn, driven by population outstripping health/sanitation; up to ~−10% growth and population loss; spreads via infected characters/units (including enemy agents — usable as biological warfare); cannot be cured, only waited out and prevented with health buildings.
- **Rebels/brigands:** low order/unrest spawns rebel/brigand stacks; unhappy settlements can secede to the Rebel faction.

## 4. Economy & Trade

- **Income sources:** taxes (largest steady source), **farming** (base fertility + farm upgrades + harvest variance), **trade** (land and sea), **mining** (resource-dependent), one-time and per-turn **tribute/diplomacy payments**, **Senate mission rewards**, and **loot** from occupy/enslave/exterminate.
- **Expenses:** **army upkeep** (dominates the budget), navy upkeep, agent upkeep, construction, recruitment, diplomatic gifts, and bribes. There is **no "free upkeep" slot** system in RTW (that is a Medieval II feature). Likewise, **Merchants are not in vanilla RTW** (a Medieval II feature; Remastered backported them). Clarify both to avoid confusion.
- **Debt:** the treasury can go negative; sustained debt forces the game to auto-disband units.
- **Trade mechanics:** cross-faction trade requires **trade rights** (via diplomacy); goods flow along **land routes** (need roads and a land connection) and **sea routes** (need a port; the game auto-selects the most profitable route; sea trade occurs only if no land route exists). Trade value depends on trade-good resources on the map (grain/wheat, wine, olive oil, silk, purple dye, silver, gold, iron, timber, slaves, etc.) and market/port building levels. Regions won't trade a good they both already have.
- **Corruption** grows with distance from capital and low law; it silently drains city income.
- **Financial summary scroll** aggregates all income/expenses; the per-settlement **trade summary scroll** shows route-by-route value.

## 5. Characters & Family Tree

- **Family members** are your generals/governors. The **family tree** screen shows the leader, heir, and relations. Each faction starts with a leader, spouse, children (including heir), and grandchildren. Only **males aged 16+** are controllable.
- **Adding members:** birth; **marriage** (marriageable women bring in husbands); **adoption** (a proposed candidate); and **"man of the hour"** (an outnumbered captain who wins a battle can be adopted into the family).
- **Succession:** on the leader's death the heir becomes leader; heir selection is influenced by authority/influence and tree position; the player can manually set the heir (the displaced one gets a "disinherited" influence penalty).
- **Aging/death:** members age and die naturally, in battle, by assassination, or by disaster.
- **Attributes:** **Command** (battle effectiveness/bodyguard), **Management** (settlement income/growth/order when governing), **Influence** (diplomacy weight, public order, Senate standing).
- **Traits system:** traits are gained/lost from triggers — governing well/poorly, winning/losing battles, tax policy, idleness, sitting in a city with certain buildings (academies → education traits; temples → religious/behavioral traits), moving on campaign, etc. Traits have levels and positive/negative "anti-trait" counterparts and modify the three attributes plus special effects (trade income, movement, personal security).
- **Ancillaries (retinue):** up to **8 per character**; gained from buildings/events/battles; **transferable between characters** in the same settlement (player only; AI doesn't transfer). They grant attribute bonuses or special effects (priests, tutors, etc.).
- **Bodyguards:** each general has a bodyguard unit that shrinks with casualties and is replenished by retraining.
- **Loyalty:** RTW family members are generally loyal by default (unlike later Total War intrigue). The notable exception is the **Roman civil war / Senate "outlaw"** dynamic (§8). Leaderless armies are led by non-family "captains" who cannot govern or gain family traits.

## 6. Agents & Diplomacy

- **Diplomats:** conduct **trade rights, alliances, ceasefire/peace, exchange/sale of map information, tribute (one-time and per-turn), protectorate, region/settlement transfer, gifts, demands**, and **bribery** of enemy armies/agents/settlements (turn them for cash). ("Military access" as a formal treaty is a Medieval II feature; in RTW the three Roman houses effectively share access via alliance — verify in play.) The AI evaluates offers via an **attitude/faction-standing** model (relative power, past dealings, shared enemies, gift value).
- **Spies:** infiltrate settlements to reveal garrison/buildings and extend vision; **open gates during a siege**; provide **counter-espionage** when garrisoned (detect/deter enemy agents). Skill shown as levels ("eyes"); keeping a spy with a top general protects him from unseen assassins.
- **Assassins:** assassinate enemy characters/agents and can **sabotage buildings**; success is a probability from the assassin's skill vs. target's security/traits; skill grows with use (start on weak targets like rebel captains and enemy diplomats). Retinue like Pet Monkey/Dancer add skill.
- **Skill/experience:** all agents gain levels through use; higher level = higher success/effect.
- **Diplomacy UI:** a scroll where you assemble offers/demands with a balance indicator of acceptability. RTW's diplomacy AI is famously weak — prone to breaking treaties and suicidal re-declarations.

## 7. Armies on the Campaign Map

- **Recruitment:** unit availability is tied to **buildings + faction + settlement level**; recruiting queues units over turns, costs denarii, adds per-turn upkeep, and **deducts population** from the settlement. **Mercenaries** are hired in the field from regional pools that replenish over time.
- **Retraining/merging:** damaged units retrain in a settlement with the appropriate building (also applies **weapon/armour upgrades** from blacksmiths and refills bodyguards); partial units can be merged.
- **Experience:** units gain **chevrons** (up to 9) improving combat; weapon/armour upgrades add arrow/shield icons.
- **Stacks:** up to **20 units per army**; armies led by a **general** (family member, with bodyguard) or a **captain** (default when no general).
- **Movement/terrain/ZoC/ambush:** as §1; forests hide ambushers.
- **Sieges:** build equipment over turns or starve; assaults, defender sallies; wall tier sets difficulty.
- **Navy:** fleets transport armies, blockade ports (cut trade), and fight naval battles (auto-resolved in the strategy layer).
- **Garrisons** suppress unrest (public-order contribution) and hold walls.
- **Upkeep dominates the economy** — the central economic tension is army size vs. treasury.
- **Auto-resolve:** the game estimates outcomes from unit stats/numbers/experience; it is often **unfavorable to the player** vs. playing manually, especially sieges — a key reason to design the resolver as swappable.
- **Reinforcements:** nearby allied stacks can join a battle.
- **Last settlement:** losing your last settlement with no recovery ends the faction/game.
- **Marian reforms** swap Roman rosters from manipular (hastati/principes/triarii) to cohort legionaries (§8).

## 8. Roman Politics & the Senate

- **The Senate (SPQR)** is a Rome-based faction that issues **missions** to the three Roman houses (capture city X, blockade a port, assassinate a target, reach a trade level, etc.) with **rewards** (money, free units, recruitment unlocks, Senate/People standing) and sometimes **penalties/deadlines**. Late-game missions become punitive (e.g., "your faction leader must commit suicide").
- **Two standings:** **Senate standing** (favor with the Senate) and **Popular standing / standing with the People**. Expanding successfully inevitably **drops Senate standing** and **raises Popular standing**.
- **Senate offices** (held by family members, granting traits/influence and minor powers): **Quaestor, Aedile, Praetor, Censor, Consul, Pontifex Maximus** (with an effective Dictator/consul-for-life role). The **Consul** can conduct Senate diplomacy and, critically, **trigger the Civil War**. Ex-office traits (e.g., "ex-consul") give permanent bonuses; Quaestor/Censor can excuse a failed mission's punishment.
- **Civil war / being outlawed:** when Popular standing is high and Senate standing low, you can **attack Rome/the Senate** and start the **civil war**; alternatively the Senate eventually **outlaws** you. In the civil war the other Roman houses and the Senate become enemies; winning (taking Rome) is required for a Roman world-conquest victory.
- **Roman inter-house relations:** the three houses start **allied and effectively share the map/access**; you generally cannot freely attack them until standings permit civil war.
- **Marian reforms trigger:** Per TWC Wiki ("Marian reforms"): "The Marian Reforms are a hard coded event...they occur when a Huge City with the italy hidden resource (the region 'Latium' excluded) is occupied by a roman cultured faction." It **unlocks cohort legionaries and makes several pre-Marian units obsolete**. These Senate/civil-war rules apply to Roman factions only; non-Romans ignore them.

## 9. Victory Conditions

Defined in `descr_win_conditions.txt` per faction, with separate long and short goals:

| Campaign | Typical condition |
|---|---|
| Imperial (long), Roman factions | Hold **50 regions including Rome** and win the civil war over the Senate |
| Imperial (long), non-Roman | Hold **50 regions including Rome** (`take_rome`) or a set of **specific hold_regions + take_regions N** |
| Short campaign | Hold **~15 regions** and **outlive/destroy specified rival faction(s)** (`outlive_factions`) |

The campaign has a **time limit (ends 14 AD)**; reaching thresholds before then wins, otherwise the game concludes. Victory/defeat trigger end screens. Note: in vanilla RTW, `hold_regions` and `take_regions` must be used together to work.

## 10. Events & Scripted Content

- **Disasters:** plague (§3), earthquakes, floods, volcanic eruptions — cause population/building damage and order hits.
- **Historical/date-triggered announcements** and **random events** deliver flavor and mechanical effects via the advisor and event scrolls.
- **Seven Wonders** (owner gets a factionwide bonus). Per TWC Wiki "Wonders - Modding Info for RTW":
  - **Colossus of Rhodes** (Rhodes) — "increases naval trade by 40%"
  - **Statue of Zeus** (Corinth/Olympia) — "gives a +4 (20%) bonus to population loyalty in all settlements"
  - **Temple of Artemis** (Ephesus) — "reduces the cost of new religious buildings by 30%"
  - **Hanging Gardens of Babylon** (Babylon/Seleucia) — "20% bonus to farming income"
  - **Mausoleum of Halicarnassus** (Halicarnassus) — −20% build time (buildings ≥5 turns)
  - **Great Pyramid & Sphinx** (Memphis) — cancels the **Egyptian culture penalty** for the owner
  - **Pharos of Alexandria** (Alexandria) — nominal naval-movement / reduced-sinking bonus, but per the same source these bonuses are non-functional ("Neither of these bonuses actually works")
- **Advisor ("Victoria"):** tooltips and suggested actions.
- **Man of the hour, spawned rebel armies/invasions, and end-of-year reports** round out scripted content.

## 11. AI & Difficulty

- **Campaign difficulty (Easy/Medium/Hard/Very Hard)** primarily gives the **AI economic bonuses, public-order help, and greater aggression** (it does not make the AI "smarter"); **battle difficulty is a separate setting** that buffs AI unit stats/morale.
- **Known AI behavior/weaknesses:** competent at expansion and besieging, but **poor diplomacy** (breaks treaties, suicidal re-declarations, immediate backstabs), sometimes passive or predictable, exploitable ZoC/bridge behavior, and it does not transfer ancillaries or optimize economy well. Design your AI as separate modular "behaviors" (economy, expansion, diplomacy, war) so weaknesses stay tunable.

## 12. User Interface & Presentation (information architecture only)

- **Campaign map screen:** a 3D terrain map with **settlement models that visually grow** with level, unit/agent figures, a **minimap**, an **end-turn button**, a control/command panel, and the faction symbol (opens the faction overview).
- **Settlement scroll/panel:** name, level, population, income summary, growth and public-order bars, tax slider, construction queue, recruitment queue, governor info, and buttons to the **building browser**, **city advisor**, **settlement details** (full breakdown of growth/order/income factors), and map location.
- **Other scrolls:** finances summary, family tree, diplomacy, faction overview (with victory conditions), unit info cards, trade summary, and event/notification scrolls — all in a **parchment/scroll aesthetic**. Build your own original visual identity; reuse only the *information architecture* (details-on-demand, per-settlement drill-down, queue-based construction/recruitment).

## 13. How the Game Is Data-Driven (Architecture-Critical)

RTW's mechanics live in plain-text files. **Do not copy them — replicate the pattern:**

| File | Governs |
|---|---|
| `export_descr_buildings.txt` (EDB) | Building trees, levels, requirements, capabilities (bonuses), and **which units each building recruits**; hidden resources; faction-wide capabilities |
| `export_descr_unit.txt` (EDU) | Unit stats, soldiers/unit, cost, upkeep, ownership, attributes |
| `descr_strat.txt` | Campaign start: playable/unlockable/nonplayable factions, starting settlements, characters, armies, treasury, dates |
| `descr_win_conditions.txt` | Victory conditions per faction (take_rome / hold_regions / take_regions / outlive_factions) |
| `descr_regions.txt` | Regions, resources, rebel faction, religion, hidden resources (e.g., "Italy") |
| `descr_sm_factions.txt` / `descr_cultures.txt` | Faction and culture definitions |
| `descr_settlement_mechanics.xml` | Public-order and population-growth factor curves (how factors scale) |
| `export_descr_character_traits.txt` (EDCT) & `export_descr_ancillaries.txt` | Traits/ancillaries: triggers (conditions), effects, levels, chances |
| `descr_mercenaries.txt` | Regional mercenary pools and replenishment |
| `descr_rebel_factions.txt` | Rebel/brigand spawns |
| `descr_events.txt` / `campaign_script.txt` | Scripted/historical events and scripting |
| `descr_campaign_db.xml` | Global campaign tunables |
| `descr_names.txt` | Name pools |
| `descr_faction_standing.txt` | Faction standing/relations model |

**Extracted values/formulas the community documents:** population thresholds 2,000/6,000/12,000/24,000 (hard-coded, per TWC Wiki); squalor ≈ 3,000 people per 1% (approx, capped ~−25% growth); farm/health/tax growth contributions (±0.5–1% each; health +10% ≈ +1% growth); distance-to-capital 0% within 15 tiles → +1%/tile → 80% cap at 86+ tiles (per totalwar.org research); wonder bonuses (§10); temple bonus tables (§3). Trait/ancillary triggers use a `WhenToTest` / `Condition` / `Affects` / `Chance` structure — a clean template for a data-driven trait engine.

**Architecture takeaway:** model buildings, units, traits, events, factions, and campaign setup as **declarative data (JSON/YAML/CSV)** loaded by a small deterministic rules engine. This makes the game moddable, testable, and AI-assistant-friendly (the assistant edits data tables, not engine code).

## 14. Community Knowledge Sources & Uncertainties

**Most authoritative sources:**
- **TWC Wiki** (wiki.twcenter.net) and **TWCenter forums** — the deepest modding/mechanics reference (EDB/EDCT guides, population, Marian reforms, win conditions, wonders).
- **Rome: Total War Heaven** (rtw.heavengames.com) — settlement tables, temple guides, strategy.
- **GameFAQs — MarekBrutus "City Management Guide"** — the canonical community write-up of growth/order/income factors and formulas.
- **Total War Fandom wikis** and **totalwar.com wiki** — building/faction overviews.
- **Feral Interactive's official Rome Remastered modding docs (GitHub)** — documents the same files and confirms mechanics.
- **Steam Community guides** (traits/triggers; occupy/enslave/exterminate) and **totalwar.org** research threads (distance-to-capital; economics).

**Well documented:** settlement thresholds; occupy/enslave/exterminate effects; Marian reforms trigger; wonders; temple bonus archetypes; the data-file structure; victory-condition syntax; distance-to-capital curve.

**Uncertain / verify by observation:** exact denarii costs and build times per government tier; exact top-tier government building names for Greek/Eastern/Carthaginian/Egyptian; precise squalor curve (3,000/1% is an approximation, non-linear at low tiers); exact trade-income formula (community understands trade only qualitatively); whether "military access" exists as a formal RTW treaty; exact enslave split percentages; and the exact barbarian settlement cap level (Minor City vs. Large City). Treat all these as tunable parameters and confirm against play/EDB when precision matters.

## 15. Intellectual Property Considerations (not legal advice)

- **Not protected (free to use):** game **mechanics, rules, systems, and ideas** (public-order formulas, turn structure, building-tree concept); **historical facts**; **real place names**; **real historical unit types** (hastati, principes, triarii, hoplites, cataphracts); **real deities**; and **real historical figures**.
- **Protected (do not copy):** the **name "Rome: Total War"/"Total War"** and logos (trademarks); the **specific text** (unit/building descriptions, advisor lines); **art, 3D models, textures, UI art, music**; **faction symbols as drawn**; and the **specific campaign-map artwork**.
- **Clean-room checklist for a spiritual successor:** original title and logo; original art and music; original written descriptions; **no extracted game assets**; **no copied data files** (author your own JSON tables from scratch). Choose licenses deliberately: **code** under MIT/Apache-2.0 (permissive) or GPL-3.0 (copyleft); **original assets** under CC-BY or CC0. Well-known clean spiritual successors/clones: **Unciv** (Civilization-like, libGDX), **FreeCiv**, **OpenTTD**, **The Battle for Wesnoth**, **Widelands** (Settlers-like), **0 A.D.** (original RTS). A private, non-commercial, possibly-open-source project is low-risk if these rules are followed.

## 16. Technology Options for a Mac App

| Stack | Turn-based UI-heavy fit | Campaign map rendering | Save/load | Path to 3D battles | macOS packaging | AI-assistant support | Learning curve | Verdict |
|---|---|---|---|---|---|---|---|---|
| **Godot 4** (GDScript/C#) | Excellent; strong UI (Control nodes), scene system | 2D tilemap/region map easy; capable 3D | Built-in resource serialization + JSON | Good (built-in 3D) | Exports macOS app; sign/notarize | Very good (large corpus; GDScript simple) | Low–moderate | **Recommended balanced choice** |
| **Native Swift** (SwiftUI/AppKit + SpriteKit/SceneKit/Metal) | Excellent for UI screens; more engine work | SpriteKit 2D or SceneKit 3D; free-form region map doable | `Codable` (JSON) is ideal | SceneKit/Metal path exists (more work) | Best-in-class (Xcode, native notarization) | Very good | Moderate | **Best if a "true Mac app" is the goal** |
| **Unity** (C#) | Very good | 2D/3D both strong | JSON/ScriptableObjects | Strong 3D | Good | Excellent | Moderate | Viable; licensing/runtime-fee history a caution |
| **Unreal** (C++/Blueprints) | Overkill for UI-heavy TBS | Excellent 3D | Custom | Excellent | Good | Good | High | Not recommended now |
| **Rust + Bevy** | Good but young UI ecosystem | ECS 2D/3D | serde (excellent) | Improving | Manual | Moderate | High | For Rust enthusiasts only |
| **Web (Tauri/Electron + Pixi/Phaser/Three.js)** | Excellent UI (HTML/CSS) | Pixi/Phaser 2D; Three.js 3D | JSON trivial | Three.js possible | Tauri packages small Mac apps | Excellent | Low–moderate | Strong alt; prefer Tauri over Electron |
| **Love2D/Lua** | OK for prototypes | 2D only | Lua serialize | Weak for 3D | Manual | Good | Low | Prototype only |
| **libGDX** (Java/Kotlin) | Good (proven by Unciv) | 2D strong, 3D ok | JSON | Moderate | Manual | Good | Moderate | Solid reference-driven choice |

**Recommendation:** Start in **Godot 4** for the best balance of UI ergonomics, 2D-first campaign map, easy data-driven design, MIT license, and a smooth later path to 3D battles. Choose **native Swift (SwiftUI + SpriteKit)** instead if a polished, notarized, "real Mac app" is the priority and you accept writing more engine-level code. Performance for ~100 regions, ~20 factions, and hundreds of units is trivial for any of these stacks — the bottleneck will be AI turn computation, not rendering, so keep the simulation deterministic and profile the AI. **Open-source references to study:** Unciv (data-driven civ mechanics, hex map), FreeCiv, OpenTTD, Battle for Wesnoth (hex + campaign scripting), Widelands, 0 A.D., and Godot strategy/hex-map demo repositories.

## 17. Proposed Phased Roadmap for the Foundation

**Core data model / entity list:** Faction, Culture, Region, Settlement, Building, BuildingTree/BuildingLevel, ResourceType, UnitTemplate, Unit, Army, Fleet, Character (family member), Trait, Ancillary, Agent, DiplomaticRelation, TradeRoute, Event, Mission, Wonder, Turn/GameState. Key relationships: Region 1–1 Settlement; Settlement → Buildings; Faction → Settlements/Armies/Characters; Army → Units; Character → Traits/Ancillaries; Faction ↔ Faction via DiplomaticRelation.

| Phase | Systems to build | Data tables | Key formulas | Acceptance criteria |
|---|---|---|---|---|
| **0 — Design & setup** | Game design doc, data schema, repo, tech choice, save format | Schemas for all entities | — | Schemas load; empty game boots; macOS build/CI runs |
| **1 — Campaign map & turns** | Region map, settlements, terrain, fog of war, movement, end-turn loop | Regions, terrain, adjacency, roads | Movement points vs. terrain/roads; line-of-sight | Move an army across regions, reveal fog, end turn advances date (2/yr) |
| **2 — Settlements & economy** | Population growth, buildings, construction queue, taxes, public order, squalor, treasury | Building trees, temple bonuses, tax table | Growth = Σ(farm+health+tax+slaves − squalor − plague); Order = 100 + Σ factors; squalor ≈ pop/3000; distance-to-capital 0%/15 tiles → +1%/tile → 80% cap | Cities grow, upgrade at thresholds, revolt below 75% order, budget balances |
| **3 — Armies & battles (auto-resolve)** | Unit templates, recruitment (pop cost/upkeep), stacks, garrisons, sieges, **Battle resolver interface** | Unit stats, upkeep, recruitment reqs | Auto-resolve estimator (numbers × stats × experience × terrain); upkeep drain | Recruit, besiege, auto-resolve a battle, apply casualties/experience |
| **4 — Characters** | Family tree, traits, ancillaries, attributes, succession, aging, man-of-the-hour | Traits/ancillaries with triggers | Trait triggers (WhenToTest/Condition/Chance); heir selection | Generals age/die, heir succeeds, traits change from governing/battle |
| **5 — Agents & diplomacy** | Diplomats, spies, assassins; diplomacy offers/attitude model | Agent actions, standing weights | Assassination success = f(skill, security); AI offer acceptance | Sign trade rights/alliance, assassinate a target, bribe an army |
| **6 — AI opponents** | Modular economy/expansion/diplomacy/war behaviors + difficulty bonuses | AI personality tunables | Difficulty income/order/aggression multipliers | AI expands, manages cities, wages war, honors/breaks treaties believably |
| **7 — Politics, events, victory** | Senate (Roman), missions, civil war, Marian reforms, disasters, wonders, victory checks | Missions, events, wonders, win conditions | Standing math; Marian trigger; win checks | Senate issues missions, civil war triggers, wonders grant bonuses, victory/defeat fires |
| **8 — Polish** | Save/load robustness, UI polish, balancing, tutorial | Balance constants | — | Full campaign playable end-to-end; saves round-trip |
| **Future — Real-time battles** | Swap auto-resolve for a real-time battle scene | Battle unit stats, formations | Combat/morale model | The same battle runs auto or real-time via the resolver interface |

**Design-for-battles-from-day-one:** define a `BattleResolver` abstraction with one method — `resolve(attacker, defender, terrain, settlement?) → BattleResult { casualties, survivors, experienceGained, capturedSettlement, generalDeaths, traitsAwarded }`. Phase 3 ships an auto-resolve implementation; the Future phase adds a real-time implementation behind the same interface, so the campaign never needs to know which ran.

## Recommendations
1. **Start now with Phase 0–2 in Godot 4.** The campaign map + settlement/economy loop is 70% of what makes RTW feel like RTW, and it validates your data-driven architecture early. Benchmark to change course: if you find yourself fighting Godot's UI for the dense strategy scrolls, or you strongly want native macOS polish, switch to **Swift (SwiftUI + SpriteKit)** before Phase 3 — after that the cost of switching rises sharply.
2. **Author everything as data from day one.** Put buildings, units, traits, temples, wonders, factions, and campaign setup in JSON/YAML with a schema. Have your AI assistant generate and edit these tables; keep the engine thin. This is the highest-leverage practice for solo + AI development.
3. **Implement the `BattleResolver` interface in Phase 3 even though battles are out of scope.** Auto-resolve first; the real-time engine later drops in behind the same interface. This is the one decision that most protects your "battles later" goal.
4. **Model public order and growth exactly as two summed factor lists** (matching RTW's settlement-details scroll). Use the documented anchor values (thresholds 2,000/6,000/12,000/24,000; squalor ≈ pop/3,000; distance 0%/+1%/80%-cap; low-tax +0.5% growth) as starting constants, then tune. Keep them in a single balance file.
5. **Stay clean-room:** original name, art, text, music; no extracted assets; hand-authored data. If you open-source, use MIT/Apache-2.0 for code and CC-BY/CC0 for assets. Study Unciv's repository first — it is the closest proven model of a data-driven, moddable, open-source 4X built by a small team.
6. **Reserve the Roman Senate/civil-war system for Phase 7** but keep hooks for it (faction "standing" fields, mission objects) in your data model from the start, so it isn't a painful retrofit.

## Caveats
- Several precise numbers are community-derived approximations, not official CA figures — notably the **squalor curve (~3,000 people/1%)**, the **enslave population split**, and **per-tier government-building costs**. Treat these as tunable and verify against play or the game's data files where precision matters.
- Some mechanics differ between the **2004 original, the Barbarian Invasion expansion, and the 2021 Remastered** (e.g., barbarian city caps, Merchants, playable-faction counts, minor UI/AI behavior). This report describes the **original 2004 game**; where Remastered clarifies a mechanic it is noted as such. Confirm any borderline detail against the original if you want strict fidelity.
- A few widely repeated "facts" are actually **from later Total War titles** (free-upkeep slots and Merchants = Medieval II; formal "military access" treaties = later games). These are flagged in-text; do not import them into an RTW-faithful design by mistake.
- RTW's **diplomacy and campaign AI are weak** — do not use them as your quality bar. Budget real effort for the AI behaviors in Phase 6; it is the hardest part of a strategy game to get right and the part least documented by the community.
- This is a technical/design summary, **not legal advice**. The IP guidance reflects the generally understood distinction between unprotectable mechanics and protected expression; if you ever move toward commercialization, consult a qualified attorney.