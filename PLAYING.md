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
- **The map** — every region is a circle at its real geographic place, coloured
  by who owns it and sized by how big its city is. Lines are roads between
  neighbouring regions; dashed lines are sea routes. A red ring means the city
  is under siege. Grey circles are land you have not scouted. Small rings on
  the sea are the seas themselves, named when you zoom in.
  - **Banners** beside a city are armies; banners on a sea are fleets. The
    banner's fill is how many units are in it (a full banner is twenty), the
    bar under it is how many of the men are still standing, a gold disc above
    it means a family member leads it, a white sail means a fleet. Your own
    banners stand nearest the city.
  - **Drag with the right mouse button** (or the middle one) to move the map.
  - **Scroll** to zoom in and out. Zoomed far out, banners become small
    squares again.
  - **Left-click** a banner to select that army or fleet, a city to select the
    region, open sea to clear the selection. Hover a banner for a summary.
  - **Right-click** somewhere to order the selected army or fleet there.
- **Right panel** — the force card for the selected army or fleet (its men,
  its orders), then everything about the selected region and every action you
  can take there.
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

**Left-click an army's banner** to select it. Rings appear on the map: yellow
regions are within a season's march, orange ones only by forced march, red ones
hold an enemy you can strike. The force card on the right lists every unit
with its strength, experience chevrons and upkeep, the general's name (click
*sheet* for his page), and how far the army can still go this season.

- **Right-click a ringed region** to march there. The army takes the cheapest
  road, several regions in one order if it has the legs; roads make it cheaper,
  rough terrain costs more. If the column runs into an enemy the fog was hiding,
  it halts and the log says so.
- **Shift + right-click** an orange region to force march — roughly double the
  range, but the men arrive tired and fight worse.
- **March to →** on the card does the same from a list, for trackpads.
- **Right-click a red region** to attack the army there or lay siege to the
  city. If you are not already at war, the game asks first — it will never start
  a war by accident, and marching or sailing never starts one either.
- **Click a coastal region across a sea** with the army selected to sail there
  the old way (it takes the whole turn). Real fleets can carry armies too
  (see *Fleets*).
- Standing at a besieged city, you can **assault the walls** once your siege
  equipment is ready (two turns), or wait and starve them out. When you take a
  city you choose to **occupy** (keeps the people, worst unrest), **enslave**
  (half the people, some loot, and the slaves boost your other cities), or
  **exterminate** (most of the people, most loot, quietest afterwards, but you
  have burned your own future tax base).
- **Hire mercenaries** if the region has a pool — they cost more than your own
  troops but need no barracks and no population.
- **Esc** clears the selection; **Tab** or **N** jumps to the next army or
  fleet that still has orders to give.

### Raising, merging and splitting

Armies are made from garrisons. In one of your cities, tick units in the
**Garrison** list and press **Raise army under →** a captain or any family
member standing there — the new army appears beside the city, selected. With an
army selected in a city you can also:

- **Transfer ticked →** the garrison or another of your armies standing there.
- **Merge into →** another army here. The receiving army keeps its general (a
  captain's army takes the joining general). Two generals cannot share a camp
  in the field; merge them in one of your cities and the displaced man stays
  there as governor.
- **Split ticked under →** a captain, the army's own general, or a family
  member standing here: the ticked units become a new army.
- **Disband ticked units**: the men go home to the city's population (nothing
  comes back for mercenaries, and no money ever does).
- **Give command to …** a family member present, or **Detach** the general in
  one of your own cities. Nobody is ever left standing in the wilderness.
- **Consolidate depleted units** folds battered units of the same kind together.

Troops remember how far they marched this season: dropping a tired unit into a
garrison and raising it again does not give it fresh legs, and an army that
receives tired men marches at their pace. Generals remember too: a man who
steps off a spent army leads a fresh one no further that season. A besieged
city keeps its garrison behind the walls — nobody marches out past the siege
lines.

## Fleets

Ships are built in a port with a shipyard and wait in the city's **Harbour**
(they cost upkeep there, but never fight on the walls). Tick ships and press
**Launch fleet into →** one of the seas the port touches: the fleet appears on
that sea's anchor, selected, and sails next season.

- **Right-click a ringed sea** to sail there (**Sail to →** on the card does the
  same). Fleets pass each other at sea; there are no naval battles yet.
- **Dock at →** one of your ports on the same sea to bring the ships home.
  Making port takes one lane of movement, so a fleet launched this season
  waits until the next to dock again.
- **Transfer ticked →** another of your fleets on the same sea, **Merge into →**
  it, or **Split ticked ships into a new fleet**.
- A fleet gives you eyes on its sea and the seas beside it, and on every coast
  it touches.
- Carrying armies aboard fleets, fighting at sea and blockading ports are the
  next steps of this phase (see `docs/plans/phase-9-army-command.md`).

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
- **The art is placeholder.** Coloured circles, not painted maps.

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
