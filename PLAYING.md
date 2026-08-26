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

- **Top bar** — your treasury, the date, your standing with the Senate and with
  the people (Roman houses only), and how many regions you hold toward victory.
  Buttons: **Family**, **Diplomacy**, **Save**, **Load**, and **END TURN**.
- **The map** — a terrain map of the whole world: coastlines, province
  borders, and the lie of the land (mountain ridges, forests, hills, marsh,
  desert). Every province is tinted by its terrain and washed with its
  owner's colour; unexplored provinces lie under a dark veil. Cities are
  drawn as they are: they grow with their level, their walls show their
  wall tier in their culture's style (Roman circuits, round Mediterranean
  enceintes, tribal stockades), a banner flies the owner's colour, a gold
  laurel marks your capital, quays mark a port, and siege ladders and red
  ramparts mark a city under attack. Armies are shield roundels showing
  their unit count and a star when a general leads; your fleets ride at
  anchor in their named seas.
  - **Drag with the right mouse button** (or **WASD/arrows**) to move the
    map; **scroll** to zoom; **double-click** to center on a province.
  - **Left-click** a province to select it; **hover** for its details.
  - With an army selected, its **reach this turn glows gold**; hovering a
    destination sketches the route with each leg's cost in movement points
    and when the army will arrive. **Click to march** — a destination
    beyond this turn's reach becomes a standing order the army resumes
    each turn (halt it from the army panel). **Shift-click** forces the
    march: double the ground, weary men. Terrain is strategy now: plains
    and roads are fast, mountains and marsh cost double, and the shortest
    road on the map is not always the quickest.
  - **Click a sea** holding one of your fleets to take the helm, then click
    a highlighted neighbouring sea to sail.
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

## Diplomacy

Open **Diplomacy**. You can see where every house stands with you and set a
stance directly — declare war, offer peace, trade rights, or an alliance. The
proper negotiation system (offers, tribute, bribery, an AI that has opinions
about you) is the next phase of development; today the other side simply
accepts. Your fleets are in this window too, because they live on the sea
rather than in a region.

## Winning

Check the top bar for your progress. A long campaign wants around 50 regions
including Rome; a Roman house must also settle matters with the Senate. A short
campaign wants about 15 regions and specific rivals destroyed. If nobody manages
it by AD 14, the age simply closes.

## What is not in this build yet

Honest list, so you know what you are looking at:

- **The computer players are deliberately passive.** They manage their cities
  and build, but they do not scheme, invade, or negotiate. Real opponents are
  the next phase. Expect a quiet world.
- **Battles resolve on paper.** You see the outcome, not the fight.
- **Agents** (spies, diplomats, assassins) are designed and their data exists,
  but they are not playable yet.
- **The Senate** issues missions and the civil war can trigger, but the full
  political system (offices, elections) is later.
- **The art is original vector work, still early.** The map, towns, and
  tokens are drawn by the engine from the campaign data — expect the style
  to keep sharpening.

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
