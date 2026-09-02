# Roman War — a military strategy guide

How investment in barracks, armouries, drill and doctrine becomes victory in the field,
and what it costs the towns that pay for it. Every number in this guide is read from
the game's own data tables (`data/unit_classes.json`, `data/doctrines.json`,
`data/buildings.json`, `data/balance.json`), so what you read here is what the engine
does. The historical notes are the reasons the numbers are what they are.

## 1. How a battle is decided

A battle is a comparison of two **paper strengths**, then a roll of fortune. Each side's
strength is built unit by unit, in a fixed order that the battle report names factor by factor:

1. **Base** — men × quality × the class's **mass**, where quality is attack + defence + half
   morale + half missile attack + a quarter of the charge value, and mass is what one soldier
   of that class weighs against a foot soldier: a horseman and his horse count as two, a horse
   archer two, a chariot three, an elephant eight, an artillery crew two, a general's escort
   two and a half. Numbers matter, but so does the kind of men — and the kind of beast.
2. **Kit** — each weapon level adds 1 to attack, each armour level 1 to defence (§4).
3. **Doctrines** — the faction's reforms (§6): stat bonuses for a class, then side-wide percentages.
4. **Experience** — +10% per chevron, up to nine.
5. **Matchups** — the counter table (§2), weighted by what the *enemy* actually brought: a pike
   block facing an army that is one-third cavalry gets one-third of its anti-cavalry edge.
   Every unit card counts as one slot, whatever its headcount, so eighteen elephants count for
   as much *in the enemy's composition* as a hundred and sixty pikemen.
6. **Ground** — each class's terrain table (§3), for both sides; the defender also keeps the
   old bonus for having chosen the ground.
7. **Walls** — in an assault, each class's storming or wall-holding multiplier (§3).
8. **Attacking** and **fatigue** — war cries fire only when charging; a forced march costs
   20% unless the men or their doctrine shrug it off.

Then the general (+5% per point of command, +2% per point of troop morale), **combined arms** (+6% when a line, a shock arm and missiles each hold at least 15% of the cards) and a sally bonus for starving defenders.

Both sides then roll fortune, ±15%, and the higher strength wins. The odds the
game shows before an attack — *odds 1.42:1 — 78% to win* — are the paper ratio and the exact
chance that fortune leaves it standing:

| Paper odds | Chance to win |
|---|---|
| 0.8:1 | 3% |
| 0.9:1 | 21% |
| 1.0:1 | 50% |
| 1.1:1 | 77% |
| 1.2:1 | 92% |
| 1.3:1 | 99% |
| 1.5:1 | 100% |
| 2.0:1 | 100% |

So a 1.3:1 edge is nearly safe and a 1.1:1 edge is a gamble: build the edge before you fight.

**Casualties** come in two parts. The *melee* is set by the odds and shared out so that the
units the enemy countered bleed more than their share and the units that countered him bleed
less. The *rout* falls on the loser only, and it is where ancient battles killed: it scales with
the winner's **pursuit** (fast units, especially light horse) and is reduced for each losing unit
by its own **escape** speed. Beaten cavalry rides away; beaten pikemen do not. Winners gain a
chevron, or 2 if they were the paper underdog by 1.3:1 or worse. A destroyed army takes its general with it; a losing general otherwise dies one time in 10.

## 2. The arms and their counters

Twelve classes of unit, each with a job:

- **Sword and Axe Infantry** (`infantry`, line) — Close-order foot who fight with sword, axe or short spear and shield: the line that decides most battles. Steady against other foot and at home on broken ground, but a flank or rear charge by horse breaks them, and they cannot catch skirmishers who will not stand. The Roman legion and the Gallic warband are both of this class.
- **Spear Infantry** (`spear`, line) — Foot who fight with a long thrusting spear and a large shield. Horses will not charge a steady hedge of points, so spearmen anchor a line against cavalry and chariots; against swords in a press they give ground slowly, and they cannot reach archers who keep their distance.
- **Pike Phalanx** (`pike`, line) — Deep blocks of the Macedonian sarissa, the two-handed pike. Frontally on level ground nothing pushes through them, and cavalry that charges them dies on the points; but the block cannot turn, loses its order on hills and in woods, and is helpless against missiles it cannot chase. Cynoscephalae and Pydna were lost on broken ground, not in the pike-to-pike push.
- **Foot Missiles** (`missile`, missile) — Archers, slingers and javelin men who wound at range and run when charged. They break up elephants and chariots, wear down slow pike blocks and outshoot horse archers from a hill; caught in the open by horse they are ridden down. Slingers against Parthian horse archers won Ventidius his triumph in 38 BC.
- **Shock Cavalry** (`cavalry`, shock) — Lancers and heavy horse who win by the charge. On open ground they ride down archers, roll up infantry from the flank and run down anyone who breaks, and most of a beaten army dies in that pursuit. Against a steady spear or pike front they achieve nothing, in woods and mountains they are dismounted men on bad footing, and inside a city wall they are useless.
- **Horse Archers** (`horse_archer`, missile) — Mounted bowmen of the steppe and the Iranian plateau who shoot and never close. On open plains they empty an army of foot at no cost, as Crassus learned at Carrhae; light cavalry that can catch them, slingers who can outrange them, and any wood or mountain take the plains away from them.
- **Chariots** (`chariot`, shock) — The war cart of Britain and the scythed chariots of the Hellenistic east. A terrifying charge on flat ground against loose foot, a wreck against pikes, spears or any obstacle, and easy meat for missiles: at Magnesia the Seleucid scythed chariots were shot to pieces before reaching the line.
- **War Elephants** (`elephant`, shock) — Beasts that horses will not face and that trample close-order foot, but that panic under missile fire and turn on their own side. Pyrrhus won with them at Heraclea; Scipio opened lanes for them at Zama and let his skirmishers finish them.
- **Artillery** (`siege`, artillery) — Bolt throwers, stone throwers and rams. Decisive against walls and dense pike blocks, a liability in a running fight: slow, few, and lost the moment cavalry reaches them.
- **General's Escort** (`general_bodyguard`, guard) — The general's mounted escort: picked heavy horse, few in number, that fight as shock cavalry and carry the commander's life with them.
- **Levied Peasants** (`peasant`, levy) — Farmhands with whatever they brought from the fields. They fill a line, police a town badly, and break under any real pressure.
- **Warships** (`ship`, naval) — Warships fight at sea and are not part of a land battle.

The counter table. Each cell is the **net** edge of the row's class over the column's when
the two meet one-on-one on level ground (the row's multiplier divided by the column's back).
1.00 is even; 1.67 means the row fights two-thirds stronger than its numbers. Mixed armies
dilute every edge in proportion — which is why combined arms are strong.

| my arm \ theirs | inf | spear | pike | missile | cav | h.arch | chariot | eleph | artil. | escort | levy |
|---|---|---|---|---|---|---|---|---|---|---|---|
| infantry | — | 1.08 | 1.05 | 1.11 | 0.80 | 0.67 | 0.84 | 0.78 | **1.22** | 0.84 | 1.11 |
| spear | 0.92 | — | 0.90 | 1.00 | **1.40** | 0.78 | **1.17** | 0.90 | 1.11 | **1.29** | 1.11 |
| pike | 0.95 | 1.11 | — | 0.82 | **1.67** | 0.67 | **1.53** | 1.00 | 0.78 | **1.60** | 1.11 |
| missile | 0.90 | 1.00 | **1.22** | — | 0.67 | **1.22** | **1.35** | **1.60** | 1.11 | 0.74 | **1.22** |
| cavalry | **1.24** | 0.71 | 0.60 | **1.50** | — | **1.40** | 1.11 | 0.74 | **1.67** | 0.90 | **1.35** |
| horse archer | **1.50** | **1.29** | **1.50** | 0.82 | 0.71 | — | 1.11 | **1.22** | **1.35** | 0.74 | **1.35** |
| chariot | **1.20** | 0.86 | 0.65 | 0.74 | 0.90 | 0.90 | — | 0.70 | **1.22** | 0.82 | **1.35** |
| elephant | **1.28** | 1.11 | 1.00 | 0.62 | **1.35** | 0.82 | **1.44** | — | 0.71 | **1.29** | **1.50** |
| siege | 0.82 | 0.90 | **1.28** | 0.90 | 0.60 | 0.74 | 0.82 | **1.41** | — | 0.67 | 1.11 |
| general bodyguard | **1.20** | 0.77 | 0.62 | **1.35** | 1.11 | **1.35** | **1.22** | 0.77 | **1.50** | — | **1.35** |
| peasant | 0.90 | 0.90 | 0.90 | 0.82 | 0.74 | 0.74 | 0.74 | 0.67 | 0.90 | 0.74 | — |

Why the table looks the way it does — one battle for each edge:

- **Pikes over cavalry (1.67)** and **spears over cavalry (1.40)**. Horses will not charge a steady hedge of
  points. Alexander's phalanx was the anvil at Gaugamela (331 BC) and received Porus's elephants
  at the Hydaspes (326 BC); no cavalry charge of the age broke a steady pike front, and at Magnesia
  (190 BC) the Seleucid cataphracts broke a Roman legion, not the phalanx beside it. With the
  *phalanx* attribute the edge is larger still.
- **Cavalry over infantry (1.24) and over foot missiles (1.50)**. Cannae (216 BC): Hasdrubal's
  horse beat the Roman cavalry, came round behind the legions and closed the ring. Velites
  caught in the open by horsemen simply died.
- **Missiles over elephants (1.60) and chariots (1.35)**. Zama (202 BC): Scipio opened lanes,
  his skirmishers goaded Hannibal's elephants through them and turned some back on the Punic
  line. Beneventum (275 BC) and Magnesia (190 BC) tell the same story; the Seleucid scythed
  chariots at Magnesia were shot to pieces before they reached anyone.
- **Horse archers over infantry and pikes (1.50)**. Carrhae (53 BC): Surena's ten thousand horse
  archers, resupplied from a camel train, emptied their quivers into seven legions that could
  neither close nor withdraw across open plain.
- **Cavalry over horse archers (1.40), slingers over horse archers (1.22)**. Alexander at the
  Jaxartes (329 BC) pinned the Scythians with his lancers; Ventidius at Mount Gindarus (38 BC)
  put slingers on a hill and let the Parthians charge them.
- **Elephants over cavalry (1.35, more with *frightens horses*)**. Horses that have never smelt
  an elephant refuse to close: Heraclea (280 BC), Ipsus (301 BC).
- **Infantry against pikes is even on the flat.** Heraclea and Asculum went to the pikes in the
  frontal push; Cynoscephalae (197 BC) and Pydna (168 BC) went to the legion because the ground
  was broken — that edge lives in the terrain table (§3), not here.

**Attributes** are exceptions carried by particular units (they appear on the unit card):

| Attribute | Effect | Story |
|---|---|---|
| Phalanx (`phalanx`) | matchups: cavalry +15%, general bodyguard +15%, chariot +10%, elephant +10%; terrain: hills -10%, forest -10%, mountains -10%, marsh -10% | Fights as a close-order spear or pike block: a wall against horse and chariots, but one that comes apart on rough ground. |
| Shield Wall (`shield_wall`) | matchups: missile +15%, horse archer +15%, cavalry +5% | Locked shields turn arrows and slingstones and steady the line against a charge. |
| Testudo (`testudo`) | assault +15%; matchups: missile +15%, horse archer +10% | Roofed with shields, the unit approaches walls and archers under cover; it is a drill for storming and for enduring, not for charging horse. |
| War Cry (`war_cry`) | attacking +8% | Works itself into a fury before the charge: harder-hitting when attacking, no help when standing to receive. |
| Frightens Infantry (`terrifies_foot`) | matchups: infantry +10%, spear +10%, missile +10%, peasant +15% | Foot soldiers who have never seen the like of it waver before contact. |
| Frightens Horses (`terrifies_horse`) | matchups: cavalry +15%, horse archer +10%, chariot +15%, general bodyguard +15% | Horses refuse to close with the smell and noise: elephants and camels have broken cavalry that had never met them. |
| Woodsmen (`forest_ambusher`) | terrain: forest +20% | At home under the trees, where a column marching through can be ambushed: the lesson of the Litana forest and the Teutoburg. |
| Hardy (`hardy`) | terrain: desert +10%, mountains +10%, marsh +5% | Bred to thirst, cold and thin air; fights well where others merely endure. |
| Fleet (`fast_moving`) | escape +25%; pursuit +20% | Runs down a broken enemy and gets away from a lost battle: the Numidian horse at Cannae and at Zama. |
| Sappers (`sapper`) | assault +20% | Undermines and breaches walls, so an assault reaches the streets with less blood on the ramparts. |

## 3. Ground, walls and assaults

Each class fights better or worse by terrain (1.00 where blank). This applies to **both** sides;
the defender additionally enjoys the ground he chose (forest ×1.15, hills ×1.2, mountains ×1.35, marsh ×1.1).

| class | plains | steppe | desert | hills | forest | mountains | marsh |
|---|---|---|---|---|---|---|---|
| infantry | — | — | — | 1.05 | — | — | 0.90 |
| spear | — | — | — | 1.05 | 0.95 | — | 0.90 |
| pike | 1.10 | 1.05 | — | 0.80 | 0.75 | 0.75 | 0.75 |
| missile | 0.95 | — | — | 1.15 | 1.05 | 1.15 | — |
| cavalry | 1.05 | 1.10 | — | 0.85 | 0.70 | 0.65 | 0.70 |
| horse archer | 1.05 | 1.15 | 1.10 | 0.85 | 0.65 | 0.65 | 0.70 |
| chariot | 1.10 | 1.05 | 0.90 | 0.65 | 0.50 | 0.50 | 0.50 |
| elephant | 1.05 | — | 0.95 | 0.90 | 0.80 | 0.70 | 0.75 |
| siege | — | — | — | 0.90 | 0.80 | 0.70 | 0.60 |
| general bodyguard | — | 1.05 | — | 0.90 | 0.80 | 0.75 | 0.80 |

Read it as history: cavalry, chariots and pike blocks want the plain (Gaugamela, Magnesia);
infantry and missiles like a hill (Cynoscephalae, Gindarus); forests belong to those who know
them (the Litana forest in 216 BC, the Teutoburg in AD 9), and *woodsmen* units get more still.

**Walls.** A settlement's wall tier multiplies the defenders by ×1 / ×1.3 / ×1.6 / ×2 / ×2.5 / ×3 across the six tiers, and on top of that
every class storms or holds walls differently:

| class | storming | holding walls |
|---|---|---|
| infantry | ×1.00 | ×1.00 |
| spear | ×0.90 | ×1.10 |
| pike | ×0.70 | ×0.80 |
| missile | ×1.00 | ×1.30 |
| cavalry | ×0.50 | ×0.60 |
| horse archer | ×0.50 | ×0.70 |
| chariot | ×0.30 | ×0.30 |
| elephant | ×0.60 | ×0.40 |
| siege | ×1.60 | ×1.30 |
| general bodyguard | ×0.60 | ×0.70 |
| peasant | ×0.90 | ×0.90 |

So an assault is an infantry and artillery affair: bring the engines (a siege workshop), or wait.
Siege works take 2 turns to build (engineering doctrines shave a turn off; never below 1); defenders starve after 2 / 3 / 4 / 5 / 6 / 8 turns by settlement size and then
sally out with +10% desperation and one wall tier fewer.

## 4. Men and metal

- **Experience.** Nine chevrons, +10% strength each. Winners gain one per battle (2 for an underdog's win). Drill halls and war temples give recruits a head start (`recruit_xp`, the best tier in the town), veteran cadres add another.
- **Kit.** Weapon and armour levels, up to 3 each (an armourers' guild allows one more), each worth a point of attack or defence — an armoury is worth roughly a chevron to a legionary or hoplite, nearly two to a levy spearman. They come from
  the town's forges, summed across chains:

| building | tier | weapon | armour |
|---|---|---|---|
| Roman Infantry Training — Legionary Camp | minor city | 1 | 0 |
| Roman Infantry Training — Field of Mars | large city | 1 | 1 |
| City Infantry Training — Royal Barracks | minor city | 1 | 0 |
| City Infantry Training — Palace Guard Barracks | large city | 1 | 1 |
| Siege Engineering — Great Engine Works | large city | 1 | 0 |
| Roman Arms Workshops — Smithy | large town | 1 | 0 |
| Roman Arms Workshops — Armoury | minor city | 1 | 1 |
| Roman Arms Workshops — State Arms Works | large city | 2 | 1 |
| City Arsenal — Bronzesmiths' Row | large town | 1 | 0 |
| City Arsenal — City Arsenal | minor city | 1 | 1 |
| City Arsenal — Royal Arsenal | large city | 2 | 1 |
| Tribal Forges — Smith's Forge | large town | 1 | 0 |
| Tribal Forges — Master Smith's Hall | minor city | 1 | 1 |

  Forge temples (Vulcan, Atar, Ptah, Gobannos, and Poseidon's armourers) and the war-god temples
  (Mars, Ares, Verethragna, Reshef, Horus, Teutates) add to the same pool. Units are issued kit
  when recruited; **Retrain garrison** refits every unit the town could itself recruit to its
  current standard (never taking better kit away) and refills the depleted ones for half price.
- **Mercenaries** hire in the field at a premium and arrive with one chevron; Punic mercenary
  contracts cut the price. They need no barracks and no townsmen — and leave no levy strain.

## 5. Building for war — and what it costs the town

The military chains and what each does beyond unlocking units:

| chain | tiers | recruits here | drill | law | kit |
|---|---|---|---|---|---|
| Roman Infantry Training (roman) | 5 | infantry, missile, spear | 0/1/1/2/2 | 0/0/2/3/4 | 0w0a/0w0a/0w0a/1w0a/1w1a |
| City Infantry Training (greek, eastern, carthaginian, egyptian) | 5 | infantry, pike, spear | 0/1/1/2/2 | 0/0/2/3/4 | 0w0a/0w0a/0w0a/1w0a/1w1a |
| Warband Training (barbarian, neutral) | 3 | infantry, spear | 0/1/1 | 0/0/2 | 0w0a/0w0a/0w0a |
| Roman Cavalry Training (roman) | 3 | cavalry | 0/0/1 | 0/0/0 | 0w0a/0w0a/0w0a |
| Eastern Horse Breeding (eastern) | 4 | cavalry, chariot, horse archer | 0/0/0/1 | 0/0/0/0 | 0w0a/0w0a/0w0a/0w0a |
| City Cavalry Training (greek, carthaginian, egyptian) | 3 | cavalry, chariot, elephant | 0/0/1 | 0/0/0 | 0w0a/0w0a/0w0a |
| Tribal Horse Pens (barbarian) | 2 | cavalry, chariot, horse archer | 0/1 | 0/0 | 0w0a/0w0a |
| Eastern Archery Tradition (eastern, egyptian) | 3 | missile | 0/0/1 | 0/0/0 | 0w0a/0w0a/0w0a |
| Skirmisher Training (roman, greek, carthaginian) | 2 | missile | 0/1 | 0/0 | 0w0a/0w0a |
| Hunter Training (barbarian) | 2 | missile | 0/1 | 0/0 | 0w0a/0w0a |
| Siege Engineering (roman, greek, eastern, carthaginian, egyptian) | 3 | siege | 0/0/0 | 0/0/0 | 0w0a/0w0a/1w0a |
| Roman Arms Workshops (roman) | 3 | —needs barracks 2 | 0/0/0 | 0/0/0 | 1w0a/1w1a/2w1a |
| City Arsenal (greek, eastern, carthaginian, egyptian) | 3 | —needs barracks 2 | 0/0/0 | 0/0/0 | 1w0a/1w1a/2w1a |
| Tribal Forges (barbarian) | 2 | —needs barracks 2 | 0/0 | 0/0 | 1w0a/1w1a |

Three things flow back into the town:

- **Policing.** A garrison's order bonus is its *policing*, not its headcount: each soldier counts his
  class's weight (infantry and spears 1.0, cavalry 0.9, pikes and missiles 0.8, levies 0.5, elephants
  0.3, a general's escort 1.5) times +5% per chevron, times +10% per drill level in the town, over the population (×400, capped at +80). A cohort of veterans keeps a city quieter than a mob of levies twice its size.
- **Law.** Barracks from the third tier add law (the garrison headquarters polices the streets),
  which also suppresses corruption on the frontier.
- **Levy strain.** Raising or refilling a unit adds (men ÷ population) × 100 strain points to
  the town, softened 15% per drill level, capped at 30, fading 2 a turn; each point is −1 order and −0.05% growth.
  Raise a legion from one village and it will riot; spread the levy across drilled cities and it
  will hardly notice. Camp discipline and drill yards soften it; the Egyptian machimoi levy makes it worse.

Upkeep remains the central squeeze: every unit costs denarii every turn, garrisons included,
and remount herds, steppe horsemanship, native levies and elephant establishments are the only relief.

## 6. Doctrines — learning from whom you fight

Open **Reforms** in the top bar. A house adopts one doctrine at a time, paying up front and waiting
the turns; the computer houses do the same whenever their treasuries allow. Prerequisites are
all required at once: earlier doctrines, a building of a given tier in *some* town, a resource
in *some* region (horses, iron, elephants), the era, battles won or lost — and **arms faced**: Rome
must have met foot soldiers in two battles before it adopts their sword, and the tribes must
have met legions before they learn to ambush them. Rome copied the Iberian sword and the Celtic
mail shirt from the people who used them on her; that is the mechanic.

### Roman

| doctrine | cost / turns | requires | effects | history |
|---|---|---|---|---|
| **Manipular Drill** — practised from the start by senate, julii, junii, cornelii | 1200 / 2 | — | infantry morale +1; infantry on hills +5% | Rome abandoned the hoplite phalanx during the Samnite Wars (343-290 BC), whose hill country punished a rigid line. The three-line manipular array of hastati, principes and triarii could open, close and relieve itself in mid-battle. |
| **Iberian Sword Pattern** | 1800 / 3 | faced infantry in 2 battles | infantry attack +1 | The gladius hispaniensis, a cut-and-thrust sword copied from Iberian mercenaries and enemies during the Second Punic War, became the legion's standard blade for two centuries. |
| **Pilum Volley** | 2500 / 3 | after manipular drill, barracks tier 3 | infantry vs cavalry +10%; infantry vs infantry +5% | A volley of heavy javelins thrown at twenty paces, bending in the shield it pierced, broke the momentum of a charge before the swords came out; at Telamon (225 BC) and Zama (202 BC) it was the legion's opening argument. |
| **Engineering Corps** | 3000 / 4 | siege workshop tier 1 | assault +10%; siege works -1 turn | Roman armies dug as much as they fought: the double ring of works around Alesia (52 BC), the circumvallation of Numantia (133 BC), the ramp at Masada. Siege equipment came out of the legion's own ranks. |
| **Camp Discipline** | 2200 / 3 | 3 battles won | escape +10%; levy strain -20%; immune to forced-march fatigue | Polybius (Book VI) marvelled that a Roman army built the same fortified camp every night of a march. A beaten army had somewhere to rally, a tired one still fought, and citizens under such discipline resented the levy less. |
| **Cohort Reform** | 4000 / 5 | post-marian era, after manipular drill | infantry attack +1, defense +1; infantry recruits +1 xp | The reforms attributed to Gaius Marius (107 BC): the property qualification dropped, the cohort replacing the maniple, state-issued equipment, and long-service professionals who carried their own kit and called themselves his mules. |

### Hellenistic (Greek)

| doctrine | cost / turns | requires | effects | history |
|---|---|---|---|---|
| **Sarissa Drill** (macedon, seleucia, thracia only) — practised from the start by macedon, thracia, seleucia | 1500 / 2 | — | pike defense +1; pike vs cavalry +5% | Philip II gave Macedon the sarissa, a two-handed pike of five to six metres, and drilled poor farmers until sixteen ranks could move as one. His son took it to the Indus. |
| **Hoplite Tradition** — practised from the start by greek_cities | 1200 / 2 | — | spear vs cavalry +10%; spear vs infantry +5% | The citizen hoplite with his round aspis and thrusting spear won Marathon (490 BC) and Plataea (479 BC) and defined Greek war for three centuries: a wall of shields that horsemen would not charge. |
| **Companion Wedge** | 2600 / 3 | stables tier 2, horses region | cavalry charge +2; cavalry vs infantry +10% | Philip's and Alexander's Companion cavalry charged in a wedge, the point aimed at a seam in the enemy line. Gaugamela (331 BC) was decided by it; at Chaeronea (338 BC) the young Alexander led the stroke that broke the Theban line, with the phalanx as the anvil. |
| **Torsion Artillery** | 3000 / 4 | siege workshop tier 2 | siege missile attack +3; assault +10%; wall defense +10% | Catapults appear under Dionysius I of Syracuse (399 BC); the torsion engine, powered by twisted sinew, under Philip II two generations later. By the siege of Rhodes (305 BC) Hellenistic engineers were building them by the hundred, and every city wall answered with its own. |
| **Thureophoroi Reform** (macedon, seleucia, thracia only) | 2000 / 3 | 1 battle lost | infantry on hills +10%; infantry on forest +10%; pike on hills +10% | The thureophoroi, looser-order foot behind the Celtic oval shield, came into Greek armies in the 270s BC after the Galatian invasion; after Magnesia (190 BC) and Pydna (168 BC) had shown what broken ground did to a pike block, the kingdoms went further and paraded whole regiments armed in the Roman fashion (Daphne, 166 BC). Learned from a defeat. |
| **Elephant Corps** (seleucia only) | 3500 / 4 | stables tier 3, elephants region | elephant morale +2; elephant vs infantry +10%; elephant upkeep -15% | The Seleucids kept a permanent elephant corps from Indian stock; four hundred beasts screened the flanks at Ipsus (301 BC), and Raphia (217 BC) saw the only recorded battle between African and Indian elephants. |

### Eastern

| doctrine | cost / turns | requires | effects | history |
|---|---|---|---|---|
| **Composite Bow Mastery** (parthia, armenia only) — practised from the start by parthia, armenia | 1500 / 2 | — | horse archer missile attack +1 | The recurved composite bow of horn, wood and sinew, drawn from the saddle, was the weapon of the Iranian plateau and the steppe. At Carrhae (53 BC) Surena's archers emptied their quivers into seven legions and were resupplied by camel. |
| **Cataphract Armour** | 3200 / 4 | stables tier 3, iron region | cavalry defense +2; cavalry vs infantry +10% | Rider and horse both sheathed in scale, the Parthian and Armenian cataphract charged with a lance held in both hands. It took iron by the ton and broke Roman infantry at Carrhae; at Magnesia (190 BC) the Seleucid version routed a legion before being cut off. |
| **Parthian Shot** | 2400 / 3 | 2 battles won | horse archer vs infantry +10%; escape +30% | The feigned flight, turning in the saddle to shoot at the pursuer, meant a Parthian army was almost never caught: Crassus lost his at Carrhae (53 BC), Antony lost a third of his in retreat (36 BC), and neither ever brought the enemy to a decisive battle. |
| **Remount Herds** | 2000 / 3 | horses region | cavalry upkeep -15%; horse archer upkeep -15%; march +0.25 | The Nisaean plain of Media bred the great horses of the East; a Parthian noble rode to war with a string of remounts, and an army so mounted moved and fought at a pace no infantry could match. |

### Carthaginian

| doctrine | cost / turns | requires | effects | history |
|---|---|---|---|---|
| **Mercenary Contracts** — practised from the start by carthage | 1500 / 2 | — | mercenary cost -20% | Carthage fought with hired Libyans, Iberians, Gauls, Balearic slingers and Numidian horse under a small Punic officer corps. The Spartan Xanthippus, hired in 255 BC, beat Regulus outside the city with them. |
| **War Elephants** | 3500 / 4 | elephants region | elephant morale +2; elephant vs infantry +10%; elephant upkeep -15% | The forest elephants of the Atlas were Carthage's answer to the Hellenistic corps: thirty-seven crossed the Alps with Hannibal in 218 BC, and they scattered the Roman horse at the Trebia that winter. |
| **Sacred Band Drill** | 3000 / 4 | barracks tier 3 | spear morale +2, defense +1 | The Sacred Band was Carthage's one standing citizen regiment: sons of the great houses, armoured and drilled as hoplites, who died almost to a man at the Crimissus (341 BC) rather than break. |

### Egyptian

| doctrine | cost / turns | requires | effects | history |
|---|---|---|---|---|
| **Ptolemaic Phalanx** — practised from the start by egypt | 1500 / 2 | — | spear defense +1; spear vs cavalry +10% | The Ptolemies settled Macedonian and Greek soldiers on Nile land in return for service, and drilled them in the sarissa; at Raphia (217 BC) that phalanx, stiffened with twenty thousand Egyptians, broke the Seleucid centre. |
| **Machimoi Levy** | 1500 / 2 | barracks tier 2 | spear upkeep -20%; infantry upkeep -20%; levy strain +40% | Ptolemy IV armed twenty thousand native Egyptians for Raphia and won; within a decade the machimoi who had learned to fight were in revolt, and Upper Egypt was lost to the crown for twenty years. |
| **Nile Logistics** | 2200 / 3 | port tier 2 | garrison order +10%; march +0.25 | Grain, men and news moved on the river faster than on any road; an Egyptian army marched supplied and its garrisons were never far from relief. |

### Tribal (barbarian)

| doctrine | cost / turns | requires | effects | history |
|---|---|---|---|---|
| **Warband Fury** — practised from the start by gaul, germania, britannia, dacia, hispania | 1200 / 2 | — | attacking +8% | The Gallic charge, screaming and half naked, broke the Roman army at the Allia (390 BC) and nearly did so again at Telamon (225 BC): everything staked on the first rush. |
| **Woodland Ambush** | 1800 / 3 | faced infantry in 2 battles | infantry on forest +15%; spear on forest +15%; missile on forest +15% | The Boii annihilated two legions in the Litana forest (216 BC) by felling half-cut trees onto the column; Arminius did the same to three in the Teutoburg (AD 9). Arminius had served with Rome first and knew how it marched. |
| **Hill-Fort Engineering** | 2000 / 3 | walls tier 2 | wall defense +15% | The murus gallicus, timber-laced stone that neither ram nor fire could break, ringed the oppida of Gaul; Caesar at Alesia (52 BC) chose to starve Vercingetorix rather than storm it. |
| **Chariot Tradition** (britannia only) | 1600 / 2 | stables tier 2 | chariot charge +1; chariot vs missile +10% | Caesar found the war chariot still alive in Britain in 55 BC: drivers who could run along the pole at the gallop, warriors who dismounted to fight and remounted to flee, and Roman skirmishers who could not catch them. |
| **Steppe Horsemanship** (scythia only) — practised from the start by scythia | 1500 / 2 | horses region | horse archer on steppe +10%; horse archer upkeep -15% | The Scythians and their Sarmatian successors lived in the saddle; Darius could not catch them in 513 BC and neither could anyone else. Every family bred its own remounts. |

### Shared between cultures

| doctrine | cost / turns | requires | effects | history |
|---|---|---|---|---|
| **Mail Armour** | 2400 / 4 | iron region | infantry defense +1; spear defense +1 | The riveted mail shirt was a Celtic invention of the third century BC; Rome copied it as the lorica hamata and wore it for the rest of its history. It needs iron, and a great deal of a smith's time. |
| **Falx Reapers** (thracia, dacia only) | 1600 / 2 | barracks tier 2 | infantry vs spear +10%; infantry vs infantry +5% | The Thracian rhomphaia and the Dacian falx, long curved blades swung two-handed, cut through shields and helmets; Trajan's legions added iron reinforcing bars to their helmets because of them. |
| **Numidian Horsemanship** (carthage, numidia only) — practised from the start by numidia | 1800 / 2 | horses region | pursuit +20%; escape +20% | Numidian light horse rode without saddle or bridle, harried a marching enemy for days and turned every victory into a massacre: Hannibal's at Cannae (216 BC), and when Masinissa changed sides, Scipio's at Zama (202 BC). |
| **Veteran Cadres** | 2800 / 4 | 5 battles won | all recruits +1 xp | Rome's evocati, veterans recalled to stiffen new legions, and the Hellenistic habit of brigading old soldiers with new levies show the same idea: seed every new unit with men who have seen a battle. |
| **Drill Yards** | 2000 / 3 | barracks tier 3 | garrison order +10%; levy strain -15% | A regular dilectus with drill fields in every town turned the levy from an outrage into a habit; a drilled garrison policed the streets it had grown up in. |
| **Armourers' Guild** | 3000 / 4 | armoury tier 2, iron region | kit cap +1 | State arms works — the Hellenistic royal arsenals and, later, the Roman fabricae — standardised patterns and let a city issue better kit than any private smith could. |
| **Siege Train** | 2400 / 3 | siege workshop tier 1 | siege works -1 turn | Demetrius the Besieger brought a nine-storey siege tower to Rhodes in 305 BC; a kingdom that kept its engines and engineers together opened a siege in days rather than months. |

## 7. War and the home front

- **Triumph and shock.** A *decisive* battle — at least 1,500 men engaged, and the loser destroyed or
  left with 50% losses against the victor's 20% or less — is heard of at home: every town of the
  victor gains +5 order for 4 turns (a triumph), every town of the loser −8 for 4 turns. Rome after Cannae armed slaves and limited public mourning to thirty days; the mechanic is that shock.
- **Generals.** Command adds strength; battles won against the odds make a man braver, lost
  battles the reverse, and a captain who wins badly outnumbered may be adopted into the house.
- **The Senate** (Roman houses) rewards taken regions and resents them; its missions hand out
  units and standing. Victory in the field is also politics.
- **The war record** — battles won and lost, arms faced — is what your doctrines read (§6); you
  can see it at the top of the Reforms scroll.

## 8. Five armies, and what beats each

- **The manipular legion** (hastati, principes, triarii, velites, equites). Combined arms out of the
  box: a line, a spear reserve, skirmishers and a little horse. Its weaknesses are the ones history
  found: horse archers on the open steppe (Carrhae), an enemy who wins the cavalry battle and
  comes round (Cannae), and its own thin cavalry. Bring allied horse and slingers east; fight
  Hellenistic pikes on hills, never on the plain.
- **The Macedonian combined-arms army** (pike phalanx, companion lancers, peltasts). Unbeatable
  frontally on level ground; its pikes lose their order on hills and in woods (Cynoscephalae,
  Pydna) and cannot chase the skirmishers who harass them. Fight it where the ground is rough,
  screen your line with missiles, and hold spears where its lancers will come.
- **The Parthian horse army** (horse archers, cataphracts, nothing on foot). It rules the plain and
  the steppe and it escapes every defeat. It hates hills and forests, cannot storm a wall, and is
  beaten by slingers on high ground with light horse to catch what runs (Gindarus). Refuse
  battle on the flat; make it come to you.
- **The Punic hired host** (Libyan spears, Iberian swords, Numidian light horse, Balearic slingers,
  elephants). Everything, cheaply, and the best light cavalry in the world — but the elephants
  break to missiles and the whole edifice turns on the cavalry fight. Zama: open the lanes,
  win the horse battle, and the rest follows.
- **The tribal warband host** (warband infantry with the war cry, noble cavalry, chariots in
  Britain). Everything is staked on the charge: attacking, in forest, with the first rush, it
  is terrifying; received by a steady line on open ground after a volley of pila it is a mob.
  Make it attack you across a plain; never march a column through its woods.

*Tuning:* every value above is data. The counter matrix is authored so that the two multipliers of
any pair multiply to between 0.85 and 1.15 (the validator warns otherwise) — the net edge is
their ratio, which is what this guide shows.
