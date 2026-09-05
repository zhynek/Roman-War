# Roman War — how to play

A short guide for the current build. This is the **campaign layer**: you run a
house, its cities, its money, and its armies. Battles are resolved
automatically for now (a real-time battle mode is designed for later, and the
game is built so it can drop in without changing anything else).

## Starting a campaign

You pick a few things and press **BEGIN THE CAMPAIGN**:

- **House** — who you play. The three Roman houses (Julii, Junii, Cornelii) are
  the intended starting choices; the others are listed as unlockable and are
  playable now for testing.
- **Difficulty** — how much help the computer players get (money, and public
  order in their cities). It does not make them cleverer.
- **World seed** — the same number replays exactly the same world. Change it for
  a different run of luck; keep it to compare two attempts fairly.
- **Guided mode** — on by default. A running list of objectives that walks you
  through the game and reacts to what happens to you, paying rewards along the
  way. Veterans can switch it off here, and anyone can switch it on or off
  mid-campaign under **Options ▾** in the top bar. It changes no rule of the
  world — but its rewards are real gold and troops, so a guided run of a seed
  plays out differently from an unguided one.

The year is 270 BC. Each turn is half a year (summer, then winter), and the
campaign runs to AD 14.

## The screen

- **Top bar** — two rows. The first: your treasury, the date, your people's
  three readings, your standing with the Senate and with the people (Roman
  houses only), how many regions you hold toward victory, and **END TURN** at
  the far right. The second: **Dispatch**, **Family**, **Diplomacy**, **Senate**
  (Roman houses only), **Knowledge**, **Annals**, **Save**, **Load**, and
  **Options ▾** — the mode switches and a **Controls** sheet. Both rows wrap on
  a narrow window instead of running off its edge. (Edicts are issued per
  province, so they live on the city panel rather than up here.)
- **The map** — a terrain map of the whole world: coastlines, province
  borders, and the lie of the land (mountain ridges, forests, hills, marsh,
  desert). Every province is tinted by its terrain and washed with its
  owner's colour; unexplored provinces lie under a dark veil. Cities are
  drawn as they are: they grow with their level, their walls show their
  wall tier in their culture's style (Roman circuits, round Mediterranean
  enceintes, tribal stockades), a banner flies the owner's colour, a gold
  laurel marks your capital, quays mark a port, and siege ladders and red
  ramparts mark a city under attack. Every army and fleet you can see flies
  a **banner** beside its city or in its sea: a tall flag in its owner's
  colour, filled from the bottom by how many units it holds, with a strength
  bar beneath; a gold finial when a general leads (ringed for a faction
  leader), a white sail for a fleet, a red border for a besieger, an orange
  one for weary men, and dimmed once its movement for the season is spent.
  More than four in one place fold into a "+N" chip. Zoom far out and the
  banners give way to small owner badges.
  - **Drag with the left or middle mouse button** (or **WASD/arrows**) to
    move the map; **scroll** (or a trackpad pinch, or the **+ / −** keys) to
    zoom; **double-click** to center on a province.
  - Prefer buttons? **+**, **−** and **Home** sit in the map's bottom-right
    corner. **Home** (or the Home key) returns you to your capital at a
    readable zoom whenever you get lost.
  - **Left-click selects, right-click orders.** Left-click a province to
    select it (its city fills the right panel); left-click a **banner** to
    select that army or fleet — its **force card** opens above the city
    panel, and the map rings everything it can do: **gold** for provinces it
    can reach this season, **orange** for those only a forced march reaches,
    **red** for an enemy army or city it can strike from where it stands. A
    click only counts if the mouse does not travel, so dragging never
    mis-clicks; **hover** a province for its details, or a ringed one for
    the route, its cost in movement points and when the army arrives.
  - **Right-click a ringed province** to march there (an orange one forces
    the pace — or hold **Shift**), a red one to attack the army or lay siege
    to the city, a ringed sea to sail a fleet, one of your own ports to dock
    it. A destination beyond this turn's reach becomes a standing order the
    army resumes each turn (halt it from the force card). Terrain is
    strategy: plains and roads are fast, mountains and marsh cost double,
    and the shortest road on the map is not always the quickest.
  - **Right-click with nothing selected** for a province's dossier: the
    garrison and buildings there, and the armies present — your own troops
    with their skills at a glance, while a foreign stack shows only its
    size. Click any row for its full illustrated card — the unit's stats,
    skills explained, and the building that trains it; a building's card
    lists each level's effects and the troops it unlocks. The same
    right-click answers on the right panel's build, recruit, hire and unit
    rows.
  - **Esc** deselects (the force first, then the province); **Tab** or **N**
    jumps to the next force that still has orders to give. **Options ▾ →
    Controls** lists all of this inside the game.
- **Right panel** — the force card for the selected army or fleet (its roster,
  its orders and the regrouping toolbox), then everything about the province
  you clicked and every action you can take there; with nothing selected, a
  reminder of the controls and how many of your forces still await orders.
- **Bottom right** — the turn log: every report of the day just closed, in one
  list, coloured by whether it was good news.

## Ending a turn: the day

**END TURN** does not just jump the world forward. It plays out **a day at
court**, and you watch it happen:

- The screen opens on **dawn** with the date, and the light over the map warms
  through midday and reddens into evening as the day runs.
- Then the day's reports, one at a time, with the map panning to wherever each
  one happened — a building your masons finished, men taking the oath in your
  drill yard, a neighbour's army on a road your scouts can see, a city changing
  hands, the Senate's opinion of you.
- **1x / 2x / 4x** speeds it up. **SKIP** ends it immediately. Neither changes
  anything: the turn is already fully resolved before the first frame plays, so
  skipping costs you nothing but the show.
- Your **treasury counts up or down** in the top bar to the day's new figure,
  with the swing shown beside it in green or red.

The day closes on the **Daily Dispatch**: the whole thing written out, under
headings — the wider world, our works, our coffers and people, our cause — with
the two or three things anyone would actually repeat pulled out at the top.
Dismiss it with **BEGIN THE NEXT DAY**.

You only ever see what you could plausibly know. Your own affairs in full; your
neighbours' only where you have eyes on the ground. Wars and alliances are the
exception — those are proclaimed, so you hear about them wherever they happen,
including wars that have nothing to do with you.

The **Dispatch** button in the top bar reopens the last day's recap at any time,
and it survives a save: load a campaign and the dispatch you left is still there.

## Options

**Options ▾** in the top bar holds the two switches people ask for most:

- **Play the day out over the map after End Turn** — on, END TURN plays the
  day as described above; off, the turn resolves at once and the Dispatch and
  the log tell it. The game remembers your choice between sessions.
- **Guided mode** — the trail's objectives, rewards and helping hand, on or
  off at any point of a campaign. Off, no objectives are issued and no rewards
  paid; on again, the trail resumes where it was. The setting travels with
  the save.
- **Controls…** — the whole command grammar on one sheet.

## Running a city

Click one of your cities. You will see several lists that add up to a number,
which is the whole point of the design — you can always see *why* a city is
doing well or badly:

- **Public order** — below 75% the city riots; a sustained collapse means it
  revolts and joins the independents. Garrisons count by *quality*: drilled,
  experienced regular infantry police a town, levies and elephants barely do,
  and a barracks with drill grounds makes every garrison better at it. Raising
  troops from a town leaves **levy strain** behind for a few turns — spread the
  levy across your cities rather than emptying one. Garrisons, a governor, entertainment
  buildings and low taxes push it up; squalor, distance from your capital,
  foreign-culture buildings and high taxes drag it down.
- **Growth** — how fast the population rises. Population is what upgrades a
  city to the next tier, and also what recruits cost you.
- **Income** — taxes, farming, trade, mines, minus corruption.
- **Society** — the slow part, and the part that decides how your reign is
  remembered. **Standing** is how far the province obeys you because it accepts
  you rather than because it must. **Grievance** is what it has been made to
  bear against its will, added up over years. **Belonging** is how far it counts
  itself among your people.

Underneath those you will see three numbers that are the heart of the whole
game: what is **asked of it**, what it **grants willingly**, and what therefore
has to be **compelled**. Read them together. Public order can sit at 130% while
most of what you are asking is being compelled — because a garrison holds the
lid down without lowering the pressure, and the grievance underneath goes on
climbing. When it finally boils over, no garrison prevents the province going.

That is the central trap, and it has a mirror. Games and baths raise order the
moment you build them, and within a decade or so the city stops experiencing
them as generosity and starts expecting them. Take them away and it is angrier
than if you had never built them at all. Public generosity is a promise, not a
purchase.

Each province can hold **one standing order** — an edict — set from this
panel. It is the only lever you have that acts in years rather than decades;
the **Edicts** section below says what each one costs you.

A distant province you have built no road to, with no one of yours standing in
it, will not report exact figures — you will get a rounded survey several turns
old, or nothing but "the province is said to be restive". Roads, a bigger
government building and a resident governor buy you the truth. Not knowing is a
real cost, and it is one you can spend money to fix.

**Open the building yard** (or the muster hall) and a drawer slides up over the
map. On the left is everything this city can hold; in the middle a drawing of
the building with what it is and what it will do for your money, your soldiers,
your public order; along the bottom the whole ladder of that building's life,
every rung drawn, marked as built, rising, next, or locked with the reason said
plainly — *Needs a Large Town. This is a Town.* Click a rung to see it. For
barracks, stables and shipyards each rung also names the troops it opens, so you
can see what an upgrade is actually worth before you pay for it. The **Soldiers**
tab does the same for troops, and shows which building tier each one waits on.

From the same panel you can set **taxes**, **build**, **recruit**, **retrain**
a battered garrison, **demolish** a building (the way you work off the unrest a
conquered city's foreign temples cause), and **make this city your capital**
(everything far from your capital suffers unrest and corruption).

A city grows into its next tier when its population passes the threshold **and**
you have upgraded its government building. Tribal cultures cannot build the top
tiers at all — that is deliberate.

## Armies

**Left-click an army's banner** (or click the army in the province panel's
list) to select it. Its **force card** opens on the right — who leads it, how
many men stand and what they cost, how far it can still go this season, and
every unit with its strength bar, experience and kit — and the map rings what
it can do. Now:

- **Right-click a gold-ringed province** to march there. Roads make it
  cheaper; rough terrain costs more. An **orange** ring means only a forced
  march reaches it — right-click it, or hold **Shift**, and the men arrive
  tired and fight worse. A destination beyond this turn's reach becomes a
  standing order the army resumes each turn; the card shows it and can halt
  it. The card's **March to** list gives the same orders for trackpads.
- **Right-click a coastal province across a sea** to sail there (it takes the
  whole turn). Sailing onto the shore of a faction you are **at war** with is
  an amphibious landing: allowed as long as no enemy field army holds the
  beach — the garrison waits behind its walls, and you besiege it next turn.
  This is how islands are taken.
- **Right-click a red-ringed province** to attack the army there or lay siege
  to the city. If you are not already at war, the game asks first — it will
  never start a war by accident. **A battle takes the season**: the men need
  movement enough to step into the enemy's province (a battle in your own
  province costs nothing to start), and none remains afterwards — storming
  walls is a battle too. Laying siege costs the step to the walls like any
  march, and a **field army standing before the walls must be beaten first**,
  whether you are at war with it yet or not. Every battle you order then plays back as
  an animated field: the lines close, grind, and one side breaks and is
  ridden down, with morale bars draining above. It is a replay of the decided
  outcome, and you can skip it at any moment. (A siege you let starve
  resolves during END TURN and reports in the log instead.)
- **Before every attack the game shows the paper odds** — *odds 1.42:1 — 78% to
  win* — under the Attack button and again in the dialog that asks. Afterwards
  the log says who prevailed, what each side lost, and the three factors that
  decided it: matchups, ground, walls, general, warcraft, fortune. Unit rows
  show each unit's class, chevrons and kit (`w1/a1`), and the recruitment list
  shows what a recruit raised here will carry. The counters, terrain effects
  and warcraft are all laid out in
  [`docs/MILITARY_STRATEGY.md`](docs/MILITARY_STRATEGY.md); the short version:
  spears and pikes stop cavalry, cavalry rides down infantry and archers,
  missiles shred elephants and chariots, horse archers rule open plains and
  lose in hills and woods, and cavalry is useless in an assault.
- Standing at a besieged city, you can **assault the walls** once your siege
  equipment is ready (two turns; the card counts them down and quotes the
  odds), or wait and starve them out — you always get one full season with
  the engines ready to choose before hunger decides it. Peace lifts a siege.
  When you take a
  city you choose to **occupy** (keeps the people, worst unrest), **enslave**
  (half the people, some loot, and the slaves boost your other cities), or
  **exterminate** (most of the people, most loot, quietest afterwards, but you
  have burned your own future tax base).
- **Hire mercenaries** if the region has a pool — they cost more than your own
  troops but need no barracks and no population.
- **Raise an army** from any of your garrisons: on the city panel, tick the
  units you want and **Raise army under** a captain or one of your family
  standing in the city — or raise the whole garrison in one go. Units fresh
  from a garrison keep the movement they had, so an army raised this season
  can march at once. A besieged city raises nothing: nobody marches out past
  the siege lines. Mind the empty walls you leave behind — garrisons also keep
  order.
- **Regroup** from the force card (tick units first): **transfer** ticked
  units into another army standing here, or into the garrison of your own
  city; **merge** the whole army into another; **split** ticked units off
  under a captain or a family member; **disband** ticked units (the men go
  home to the fields and swell the population — no money comes back); **give
  command** to a family member standing in the city, or **detach** the general
  to stay behind as governor; **consolidate** depleted units of the same kind
  into full ones. Units carry their movement and their weariness with them,
  so shuffling men between armies (or through a garrison) never gains a step
  or shakes off a forced march; nobody walks into a city under siege. An army
  holds twenty units at most, a general always keeps one under him, and two
  generals cannot share a camp in the field.
- **Search points of interest.** Gold diamonds on the map mark places worth a
  look — ruins, caches, deserters' camps. March an army onto one and press
  **Search** in its panel: you might find treasure, veterans' wisdom, or
  soldiers who join your cause. Each place gives up its secret once, only to
  you, and the search takes the rest of the season.

Armies cost upkeep every single turn. That is the central squeeze of the game:
your army is the thing that wins you regions and the thing that bankrupts you.
Deep enough debt disbands units for you, starting with the expensive ones
(never a general's last unit).

## Fleets

Ships are built in a port city's shipyard and wait in its **harbour** — a
second list on the city panel, beside the garrison. Tick ships and **Launch
fleet into** one of the seas the port touches; the new fleet flies its banner
at that sea's anchor and sails from next season. Select a fleet by its banner
(or by clicking the sea's anchor when the map is zoomed out): its card lists
the ships and the seas it can reach, ringed on the map. **Right-click a ringed
sea** to sail there, or **one of your own ports on this sea** to dock — the
ships go back into the harbour, where **Retrain** re-arms them and from which
they can be launched again. Fleets regroup like armies: transfer ticked ships
between two of your fleets in the same sea (or into a harbour, which costs
them the lane a docking fleet pays), merge, split, or disband ticked ships in
a sea touching one of your ports. Ships in harbour cost upkeep like
any unit. Fleets do not fight yet (see the end of this guide), but they watch
the seas: their own sea and its neighbours are visible to you, foreign sails
included.

## Your family

Open **Family** in the top bar. These are your generals and governors, and they
are people, not stats: they age, earn traits from what you actually do with
them, gather a retinue, and die. A man who governs a peaceful city well becomes
a better administrator; one who wins battles against the odds becomes braver;
one who exterminates cities becomes cruel, and everyone knows it.

- A family member standing in one of your cities **governs it** automatically.
  March him out and the city loses him — there is no governing by post.
- You can **name any adult male heir**. The man you pass over will not forget it.
- You can **move retinue members** between two family members in the same city.
- A man holding a **Senate office** shows it beside his name. The office makes
  him better at his work for the year; the **Senate** scroll says what he may
  stand for next summer.
- When your leader dies, the heir succeeds. If a captain wins a battle while
  badly outnumbered, he may be adopted into the family on the spot.

## Diplomacy

Open **Diplomacy**. Every living power is listed with its stance toward you and
its *attitude* — a word and a number summing how it actually regards you
(grudges and favors are remembered, and fade; borders chafe; the weak tempt the
strong; the strong are feared; aggressive rulers covet). Two instruments:

- **Negotiate** opens the offer scroll. Compose terms — a new stance (peace,
  trade rights, an alliance), payments and seasonal tribute in either
  direction, even a region changing hands — and watch their live appraisal
  price every part of it before you commit. The losing side of a war pays for
  peace; the winning side must be paid to stop. A diplomat of yours standing
  in their lands sweetens any terms you lay before them.
- **Declare war** does what it says, after a confirmation. Wars declared are
  long remembered — and a war declared on an *ally* is remembered twice over.

Envoys from other powers appear at the top of the scroll with their offers;
accept or decline at your leisure, but they lapse after a few seasons. The
other powers negotiate among themselves too — the turn log carries the world's
wars, peaces and pacts.

## Agents

Cities can train three kinds of agent alongside troops (each behind a building
requirement — an envoy needs a proper government hall, informers and blades
come out of the markets). Agents are diamonds on the map, walk like armies but
cross **any** border, and cost upkeep like troops.

- **Envoy (diplomat)** — parked in a foreign power's lands, he sweetens every
  offer you make them. Standing next to a leaderless warband, he can simply
  **buy it off the map** — priced per head; troops under a general refuse.
- **Informer (spy)** — reads any city he stands in: garrison, works, mood. In
  a city you are assaulting, his opened gate counts against their walls. In a
  foreign city whose masters practice a craft your court has never heard of,
  he can **steal it** — odds shown up front; success brings the drawings home
  with a head start on taking it up, failure can cost you the man.
- **Hired Blade (assassin)** — pick a target in his region and see the odds
  before you commit. Success sharpens him; failure can cost you the man. Wary
  targets with careful retinues (bodyguards, food tasters) are far harder — and
  a governor with spy-catchers hardens his whole city against all of it.

## Knowledge

The crafts of the age — warship designs, siege engines, field husbandry,
drains and aqueducts, coinage, the census — live in the **Knowledge** scroll.
Your court starts with its culture's endowment and hears of the rest by
contact: trade partners and allies talk, neighbors are watched, enemies teach
hard lessons, conquest opens a fallen city's archives, and your informers
steal. **Hearing of a craft is free; practicing it is the investment** — paid
up front, seasons of work, one program at a time, and dearer where it cuts
against your people's grain. Schools and practiced scholarship make your own
craftsmen likelier to devise something first.

Each craft states plainly what it grants — faster columns, richer farms,
tougher walls, cheaper building — and tells the true story it is drawn from.
Recruits are **armed at muster** to the city's current standard (forges plus
practiced crafts); retraining a garrison re-arms it free, so marching
veterans home to a better-equipped city is a real decision.

Lose battles and the pressure for reform mounts: military crafts come
cheaper and your people invent under duress — the log colors those
adoptions differently. Watch the world news: when a rival court takes up a
new practice, everyone hears of it.

**Warcraft** is the military half of the scroll: the manipular drill Rome
starts with, the pilum volley, camp discipline, mail copied from the Gauls,
the Companion wedge, the Parthian shot, and so on for every people. Each one
states what it does in the field — a class fights harder, counters another
arm, keeps its order on rough ground, costs less to keep — and what still bars
it: buildings of a tier somewhere in your realm, a region that yields horses
or iron or elephants, earlier crafts, battles won or lost, and **arms you have
faced**: Rome adopts the Iberian sword only after meeting foot soldiers in
battle, the tribes learn to ambush legions only after facing them. Some are
traditions closed to one people. The scroll opens on your **war record** —
battles won and lost, the arms you have met — and the realm's mood after a
decisive victory or defeat, which every town feels for a few seasons.

## Edicts

Every province can hold **one standing order**, chosen on that city's panel —
the statecraft lever beside the building queue, and the only thing you can do
that acts in years rather than decades.

The **Corn Dole** quiets a city at once and sends a bill every turn that grows
with the population; after a decade the city has stopped experiencing it as
generosity, so stopping it then is taking something away. **Martial Law**
improves the order number tonight and ruins everything else about the province —
you can watch both happen in the same panel, which is the point. **The Amnesty**
is the only thing that empties a province's ledger of grievances quickly, and
you will meet some of the men you pardoned again. There are also a **census**, a
**labour levy**, **tax farmers**, **public works**, a **grant of citizenship**,
and a **levy for the legions**. Each names its price and its requirements up
front — some want a settlement of a certain size, some a particular building.

An order takes a few turns to take hold and stops the moment you revoke it, but
whatever it moved stays moved. After revoking, that province cannot take another
order for a while, so switching is a decision too. Every effect appears by name
in the city's own breakdowns.

## The Annals

The **Annals** scroll is your campaign written as history: wars declared and
summarized battle by battle, cities taken and sacked, crafts devised and
taken up, laws proclaimed and lapsed, reigns summed when a leader dies, and
the names men earn — win enough sieges and your general is *called Breaker
of Walls* for life, one name per man, ever. Filter by Wars, Court, or
Wisdom & World. Everything there really happened in your campaign; the
scribes only wrote it down.

## The Senate

A Roman house lives under the Senate of Rome, and the **Senate** button opens
the scroll that says where you stand: the three houses' standing with the
conscript fathers and with the people, the magistracies and who holds them,
which of your own men may stand next summer, the charge laid on your house,
and how close you are to the break.

- **Charges.** The Senate sets you one task at a time with a deadline: take a
  rebel region, court a foreign power into an **alliance** or a **trade
  agreement**, or — when you are at war — arrange for a foreign king to **stop
  being alive**. Success pays silver and standing, sometimes troops; failure
  costs standing. The negotiation scroll and your agents are how the harder
  ones get done.
- **Offices.** Every summer the Senate fills fifteen seats — four quaestors,
  four aediles, two praetors, two consuls and two censors, and the pontifex
  maximus, who keeps his priesthood for life — from the grown men of the houses
  in good standing. Your house's standing
  and the man's own influence decide the ballot; the higher rungs want a lower
  office first, waived when nobody qualifies, and no man steps back down the
  ladder. An office makes a man better at
  governing and commanding for the year, the consulship names the year after
  him and every court hears of it, and — quietly the most important thing —
  every seat your house holds gives its ambitious sons something to do. A
  house shut out of the curia breeds claimants instead, and enough of them
  drag it into civil war on their own.
- **The demand.** Grow too great while the Senate hates you — the people's
  regard risen to 5 while the Senate's has sunk to −5 — and the conscript
  fathers set aside whatever they were asking and demand your patriarch's
  life. The scroll names the man and the deadline. **Comply** and he dies by
  his own hand, your heir succeeds, and the Senate's regard recovers enough
  that it does not name the heir next. Refuse until
  the deadline falls and the house is **outlawed**: at war with Rome.
- **Civil war.** Once a house is in arms against the Republic the other houses
  choose — those the Senate has already alienated join the rebel, the rest
  stand with the Senate. Your own house is never dragged into another's
  rebellion: it stands with the Senate unless it is the rebel. Nobody in the
  Republic can make war on Rome or on
  another house before that, and nobody can make peace after it: no envoy, no
  silver. It ends when Rome falls or the rebels do. The house that holds Rome
  when the Senate is gone holds it by the sword — which is what the long
  campaign asks of a Roman house.

## The guided trail

With the trail on, the **Objectives** box on the right shows what the game
suggests doing next — from setting your first tax level through raising
armies, exploring, and taking your first city. Objectives are flexible:
some offer alternative paths (hire mercenaries *or* raise levies), timed
ones simply lapse without punishing you, and targets light up on the map
with a yellow ring. Completing steps pays denarii, troops, experience — and
occasionally a permanent edge for your whole realm, like sharper recruits or
a small income bonus.

The trail also answers the world: war comes — declared by you or on you —
someone besieges your city, or crosses your border, and a rewarded objective
appears to see it through. These return throughout the whole campaign (after
a cooldown), so fighting well always pays.

## Winning

Check the top bar for your progress. A long campaign wants around 50 regions
including Rome; a Roman house must also settle matters with the Senate — a
civil war the Senate must lose (see **The Senate**). A short
campaign wants about 15 regions and specific rivals destroyed. If nobody manages
it by AD 14, the age simply closes.

## The world fights back

The computer players now actually play: they garrison and build by need, raise
armies, clear the independents from their borders, declare wars they think
they can win (and the hungrier an empire, the lower its bar), defend and
relieve their own cities, sue for peace with silver or tribute when they are
losing, and trade with neighbors they like. Houses keep wives and children
now, so successions and marriages start mattering from the first decade.
Difficulty still works the honest way — money and contentment for the AI, and
a colder attitude toward you, never extra cleverness.

## What is not in this build yet

Honest list, so you know what you are looking at:

- **Battles play back, but are not fought.** The auto-resolver decides every
  battle on paper — and the paper now says *why*: composition, ground, kit,
  warcraft and fortune, each named in the log; the animated field you watch is
  a faithful replay of that verdict, not an interactive fight. Commanding troops in real time is a later
  phase — the game is built so it can drop in without changing anything else.
- **The computer players do not use agents against you.** Spies, blades and
  envoys are a player's edge this build; the AI's counter-intelligence still
  works, so your own agents can still fail.
- **Naval combat.** Fleets move, dock, regroup and watch the coasts, but they
  do not fight, carry no armies, and there are no port blockades yet. (Armies
  still cross the sea on their own, and an amphibious landing on an enemy
  shore already works.) The computer players build no ships at all.
- **Buying elections, and the aftermath of a civil war.** You cannot canvass
  for a seat with silver, cannot declare on the Senate yourself or join another
  house's rebellion before the Senate demands your life or your ambitious sons
  force the matter, and a civil war proscribes nobody: armies and cities stay with their houses. The computer
  houses always comply with the Senate's demand. Of the Senate's authored
  charges, blockading a port waits on naval combat.
- **All art is drawn by code.** The map, the towns, the buildings and the
  troops are procedural vector work rebuilt from the campaign data every
  launch. There are no character portraits and no battle-scene art yet, and
  the style will keep sharpening.

## macOS blocks the app on first launch

Expected, and not a sign of a broken build. macOS shows:

> **"Roman War" Not Opened** — Apple could not verify "Roman War" is free of
> malware that may harm your Mac or compromise your privacy.

That is the message for any app that has not been through Apple's paid
notarization service. The app *is* code-signed (macOS would say "is damaged"
otherwise) — it simply is not notarized.

1. Click **Done**. **Never "Move to Trash."**
2. Open **System Settings → Privacy & Security**, scroll down to **Security**.
3. Next to *""Roman War" was blocked to protect your Mac"*, click **Open Anyway**.
4. Authenticate with Touch ID or your password.
5. Launch the app again. One more dialog appears — click **Open Anyway**.

macOS only asks once; afterwards it opens like any other app.

If the **Open Anyway** button is not in Privacy & Security, the quarantine flag
can be cleared directly. Open **Terminal** (Spotlight → "Terminal"), paste this
exact line, press Return, then launch the app:

```sh
xattr -cr "/Applications/Roman War.app"
```

(If the app is not in Applications, replace the path — or drag the app onto the
Terminal window after typing `xattr -cr ` to fill the path in automatically.)

Failing both, `BUILDING.md` documents a no-build route: install Godot from
godotengine.org (notarized, so it opens normally), open this project folder in
it, and press Play.

## If something goes wrong

The game writes its save to your user folder and never touches the project. If
a campaign gets into a strange state, start a new one — and please note the
**world seed** and what you did, because with the seed the exact same situation
can be reproduced and fixed.
