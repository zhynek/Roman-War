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
- **The map** — a drawn Mediterranean: coastlines, terrain (mountain ridges,
  forests, marshes), roads that follow the land, and province borders tinted
  by their owner. Cities are drawn to their size, with their walls (each
  culture builds its own shape of circuit), a banner in their owner's colors,
  a laurel ring on your capital, a quay if they work a port, and ladders and
  a red ring under siege. Round shield tokens beside a city are armies — the
  number is how many units stand there, a star means a general leads them.
  Your fleets ride at anchor on their sea's name. A dark veil covers land you
  have not scouted; the geography shows, its owners and armies do not.
  - **Drag with the right mouse button**, or use **WASD / arrow keys**, to
    move the map. **Double-click a province** to center it.
  - **Scroll** to zoom — closer in, more detail appears.
  - **Left-click** anywhere in a province to select it.
  - **Hover** any region for its name, terrain, march cost, goods, and a line
    of its story.
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

- Every province the army can reach this season **lights up**, with a dimmer
  fringe for what only a forced march reaches. **Hover** a destination and the
  route draws itself along the roads, with the cost of each leg and how many
  turns the march will take; a red dashed leg means the destination itself is
  barred (a city you would first have to besiege).
- **Click any lit region** to march there. **Click beyond the light** and the
  army sets out on a standing order — it keeps marching every turn until it
  arrives, and halts (without ever starting a fight) if an enemy blocks the
  road. The panel shows the order and a **Halt** button.
- **Shift-click** to force march — roughly double the range, but the men arrive
  tired and fight worse.
- **Click a coastal region across a sea** to sail there (it takes the whole
  turn).
- **Click a sea's name** to select your fleet there; its reachable seas ring
  up, and a second click sails it.
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
accepts. Your fleets are listed in this window too, and can also be ordered
directly on the map by clicking their sea.

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
- **The art is procedural.** The coastlines, terrain, and city icons are all
  drawn by the engine from the map data — there is not one imported image. A
  hand-painted pass is future polish; the geography you see is the real
  playing field.

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
