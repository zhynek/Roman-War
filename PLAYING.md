# Roman War — how to play

A short guide for the current build. This is the **campaign layer**: you run a
house, its cities, its money, and its armies. Battles are resolved
automatically for now (a real-time battle mode is designed for later, and the
game is built so it can drop in without changing anything else).

## Starting a campaign

You pick three things and press **BEGIN THE CAMPAIGN**:

- **House** — who you play. The three Roman houses (Julii, Junii, Cornelii) are
  the intended starting choices; the others are listed as unlockable and are
  playable now for testing.
- **Difficulty** — how much help the computer players get (money, and public
  order in their cities). It does not make them cleverer.
- **World seed** — the same number replays exactly the same world. Change it for
  a different run of luck; keep it to compare two attempts fairly.

The year is 270 BC. Each turn is half a year (summer, then winter), and the
campaign runs to AD 14.

## The screen

- **Top bar** — your treasury (with the projected net for the coming turn), the
  date, your standing with the Senate and with the people (Roman houses only),
  and how many regions you hold toward victory. Buttons: **Help**, **Family**,
  **Diplomacy**, **Senate** (Roman houses), **Save**, **Load**, and **END TURN**.
- **The map** — every region is a token at its real geographic place, coloured
  by who owns it and sized by how big its city is; notches on the rim count the
  city's tier, and the seas carry their names. Lines are roads between
  neighbouring regions; dashed lines are sea routes. Shields beside a city are
  armies (with a count when more than one); pale dots under a token's shoulder
  are your agents. A gold star marks your capital; a red ring means siege.
  Dark tokens are land you have not scouted.
  - **Drag with the right mouse button** to move the map.
  - **Scroll** to zoom in and out.
  - **Left-click** a region to select it.
- **Right panel** — everything about the region you clicked, and every action
  you can take there.
- **Bottom right** — the turn log: what happened while you were away.

## Running a city

Click one of your cities. You will see three lists that add up to a number,
which is the whole point of the design — you can always see *why* a city is
doing well or badly:

- **Public order** — below 75% the city riots; a sustained collapse means it
  revolts and joins the independents. Garrisons, a governor, entertainment
  buildings and low taxes push it up; squalor, distance from your capital,
  foreign-culture buildings and high taxes drag it down.
- **Growth** — how fast the population rises. Population is what upgrades a
  city to the next tier, and also what recruits cost you.
- **Income** — taxes, farming, trade, mines, minus corruption.

From the same panel you can set **taxes**, **build**, **recruit**, **retrain**
a battered garrison, **demolish** a building (the way you work off the unrest a
conquered city's foreign temples cause), and **make this city your capital**
(everything far from your capital suffers unrest and corruption).

A city grows into its next tier when its population passes the threshold **and**
you have upgraded its government building. Tribal cultures cannot build the top
tiers at all — that is deliberate.

## Armies

Click a region holding one of your armies, then click the army in the right
panel to select it. Now:

- **Click another region** to march there. Roads make it cheaper; rough terrain
  costs more.
- **Shift-click** to force march — roughly double the range, but the men arrive
  tired and fight worse.
- **Click a coastal region across a sea** to sail there (it takes the whole
  turn).
- **Click an enemy region** to attack the army there or lay siege to the city.
  If you are not already at war, the game asks first — it will never start a
  war by accident.
- Standing at a besieged city, you can **assault the walls** once your siege
  equipment is ready (two turns), or wait and starve them out. When you take a
  city you choose to **occupy** (keeps the people, worst unrest), **enslave**
  (half the people, some loot, and the slaves boost your other cities), or
  **exterminate** (most of the people, most loot, quietest afterwards, but you
  have burned your own future tax base).
- **Hire mercenaries** if the region has a pool — they cost more than your own
  troops but need no barracks and no population.
- **Field the garrison as an army** turns city troops into a marching army (it
  moves next season); with a governor present you can march out under his
  command. The reverse — garrisoning an army in a friendly city — saves its
  field upkeep and calms the streets.

Armies cost upkeep every single turn. That is the central squeeze of the game:
your army is the thing that wins you regions and the thing that bankrupts you.
Deep enough debt disbands units for you, starting with the expensive ones.

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
- When your leader dies, the heir succeeds. If a captain wins a battle while
  badly outnumbered, he may be adopted into the family on the spot.

## Agents

Cities with the right buildings train three kinds of agent (each with a cap,
an upkeep, and a skill that grows with the work):

- **Envoy** (government building) — diplomacy's legs. Walk him onto a foreign
  power's soil and the **Negotiate** button opens their court.
- **Informer** (market) — reveals whatever region he stands in, and when you
  assault a city he is inside, gates open for you. Watchful governors hunt
  informers; a spymaster in the governor's retinue is what catches them.
- **Hired blade** (market, tier 2) — sent against a general, governor, or king
  in his region. Bodyguards and food-tasters (personal security) are the
  defence; a failed attempt can cost you the blade — and be traced back.

Select an agent like an army and click anywhere on the map; he walks (or
sails) as far as his legs allow, through any territory.

## Diplomacy & negotiation

Open **Diplomacy** for the ledger: every power, your stance, and how they
regard you — a number built from named causes (culture, treaties, wars, border
friction, remembered deeds; open Negotiation to see the full breakdown). War
can be declared from here directly. Everything else needs an **envoy at their
court**, and their consent:

- **Peace** — a losing enemy takes it; a winning one wants silver on the table.
- **Trade rights / Alliance** — goodwill thresholds; payments sweeten the ask.
- **Gifts** — buy remembered goodwill that fades slowly.
- **Demand tribute** — pays if they fear you; insults them if they don't.
- **Buy a border town** — possible at high goodwill and full price, never
  their capital or last holding.

Deeds are remembered: declaring war scars how a power regards you for a long
time. Your fleets are in the Diplomacy window too, because they live on the
sea rather than in a region — and a fleet parked on an enemy port's sea lane
is how blockade missions are done.

## The Senate

Roman houses answer to the Senate (its own scroll in the top bar): standings
of all houses, the offices of the Republic — filled every summer by the houses
in favor, and worth real bonuses to the men who hold them — and the Senate's
current charge to you. Missions range from taking a rebel region to courting
an ally, opening markets, blockading a port, or removing a troublesome king.
Standing rises with service and falls with failure; the people love conquest.
Grow too loved with too little favor and the Republic breaks: houses choose
sides, and the civil war decides everything. At the very bottom of the
Senate's patience is one final demand — and refusing it means outlawry.

## Winning

Check the top bar for your progress. A long campaign wants around 50 regions
including Rome; a Roman house must also settle matters with the Senate. A short
campaign wants about 15 regions and specific rivals destroyed. If nobody manages
it by AD 14, the age simply closes.

## What is not in this build yet

Honest list, so you know what you are looking at:

- **Battles resolve on paper.** You see the outcome, not the fight. The
  campaign is built so a real-time battle mode can drop in later.
- **Naval combat** — fleets scout, blockade and carry the flag, but ships do
  not yet fight ships.
- **The AI does not use agents against you** — its knives stay sheathed; its
  wars, economies, sieges and peace treaties are all real.
- **The art is stylised** — drawn tokens and a charted sea, not painted terrain.

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
