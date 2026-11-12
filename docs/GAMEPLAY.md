# Gameplay guide

Everything here works the same for every player in a session: the host decides what
happened, and every player sees the same enemies, telegraphs, gear, lifts, ice, doors and
fires. All controls are on the controls screen (F1, or Esc > Controls).

## Starting, menus and saving

- **Title screen**: set your name and hoodie colour, then choose:
  - **Play solo**: a world just for you, with no network. The menu really pauses it.
  - **Host a game**: up to 4 friends can join, even once you've started.
  - **Join a game**: type the host's address, or pick a game found on your Wi-Fi.
  - **Controls** and **Quit**.
- **Worlds**: solo and hosted worlds live in one of 3 save slots. Each slot shows the
  day, the time, how long it's been played and who has played in it. You can continue a
  slot, start a new world in an empty one, or delete one (press Delete twice).
- **Saving is automatic**. The world saves every 2 minutes, when someone leaves, when the
  host exits, and when the window closes. Everyone's things are kept by player name, so
  rejoining with the same name gets yours back.
  - **The world**: day and time, crops, pins, melted ice, lifts, unlocked doors.
  - **Each player**: bag, item wheel, gear, hearts, shields, lessons, and where they stood.
- **Esc (or Start)** opens the menu from anywhere, even with the bag or map open.
  Resume puts you back where you were (the bag or map comes back).
  - **Settings**: Master, Music and Sound effects volume. These are kept between sessions.
  - **Controls**: every button.
  - **Exit / Logout**: back to the title screen.
    - If you're the **host**, this ends the game for everyone: they all go back to the
      title screen with a message.
    - If you **joined**, only you leave.
    - Solo and hosted worlds save first.
- The menu also shows the day, the time and how long you've played.
- Sounds and music are simple ones made in code for now. They're placeholders until real
  recordings are added.

## Pepper's lessons

Pepper stands by the notice board in the middle of Middlemost, with a **!** over her head
until you've said hello. Talk to her (E) and she teaches one thing at a time. Your
current lesson and its tasks show under the clock, and tick off as you do them. When a
lesson is done the next one starts, sometimes with a small reward.

| # | Lesson | Tasks |
|---|---|---|
| 1 | Say hello to Pepper | Talk to her |
| 2 | Fill your item wheel | Put the Watering Can and the Popberry Seeds in your wheel |
| 3 | Grow a popberry | Plant, water twice, harvest (reward: 2 Thunder Radish Seeds) |
| 4 | Quick feet | Dash 3 times, sprint for 2 seconds |
| 5 | Dress for adventure | Wear the Saucepan Helmet (reward: Lamp Oil) |
| 6 | Light in the dark | Jab with your lit torch |
| 7 | Shoo a Wilt | Defeat an enemy (reward: 4 Popberries) |
| 8 | Never get lost | Drop a pin |
| 9 | Up the pulley lift | Ride a lift, open the chest on the Canopy Ledge (reward: 2 Lamp Oil) |

Talk to her again any time to hear the current lesson. If you already know the game,
press **Backspace** while she's talking to skip the lessons. Each player has their own
progress, and it's saved.

## The item wheel

Your **item wheel** holds what you can have in your hand: the sickle, the watering can,
seeds, berries to throw, lamp oil. It's separate from your bag:

- It starts with **just the sickle** and gets one segment for each thing you add, up to 8.
  You can see the free segment as a dashed **+** in the bag screen.
- Open the bag (I) and **right-click** something to add it to your wheel. Right-click a
  wheel segment to put it back in the bag. Click two segments to swap them.
- **Hold Q** (or Tab, or LB), point and let go to pick. The number keys 1-8 and the mouse
  wheel work too. The quickbar at the bottom of the screen shows the wheel in a row.
- When a stack runs out (your last seed planted, your last berry thrown), that segment
  goes away. Harvested berries land straight in your wheel if berries are already there.

## Darkness and light

- **Night is really dark** outdoors, from dusk (18:30) to dawn (5:30). At midnight the
  screen is about 5% as bright as noon.
- **Mossmouth** is underground, so it's that dark all day.
- **Houses** are lit inside.
- Lights fade in at dusk and are off at noon, so they never wash out the daytime picture.

| Light | Where | Notes |
|---|---|---|
| Torch | Offhand | Small circle of light. Never needs fuel. **Rain or drizzle puts it out after 3 s** (unless you wear a Raincoat). Relight it at any campfire, brazier, street lamp or fireplace (E). Right-click jabs. |
| Lantern | Offhand | Wider, steady light. Rain can't touch it. **Burns Lamp Oil**: a full lantern lasts about 4 real minutes and refills itself from oil you carry. Right-click turns it on or off. |
| Miner Helmet | Helmet | Headlamp beam where you're looking, so your offhand is free. |
| Glow Pebble | Trinket | A faint glow around you. |

**Torch jab (right-click)**:
- sets an enemy alight: it burns for 4 s, 1 damage a second;
- thaws a Frost Wilt, which ignores the sickle while it's frozen;
- melts the ice it touches into a puddle, where you can refill the watering can (E).

Rain puts out burning enemies too.

## Enemies

Every attack except a plain bump is announced first with a red **telegraph** on the ground
that fills up. Step out, dash out, or block it.

| Enemy | Where | Attack | Telegraph | Damage |
|---|---|---|---|---|
| Mildew Wilt | Middlemost, Fernery | Bumps you, eats crops | none | 1 |
| Frost Wilt | Mossmouth | Bumps you. Frozen: thaw it with the torch first | none | 1 |
| Thornback Boar | Fernery, Middlemost at night | **Bull charge** | A lane across the ground with arrows, 1 s | 3 |
| Puffcap | Fernery, Mossmouth | **Spore burst** | A circle that fills up, 1.2 s | 2 |
| Mossback Bear | Mossmouth | **Slam** | A wide wedge in front of it, 1.5 s wind-up while it shakes | 4 |

- A boar that charges into a cliff or an ice wall is **dazed** for 1.6 s.
- You have **5 hearts** (10 hp). At 0 you faint. A friend can revive you with E within 10 s.
  Otherwise you wake at the zone entrance with half your hearts.

## Hitboxes and hurtboxes

All of this is in `game/combat/hitboxes.gd`, and the same code judges hits on every
player's screen and on the host.

- **Hurtboxes**: every body is a circle around its feet, the size of its shadow. Big
  animals have big ones. A player is a little smaller for enemy attacks (11 px) than for
  bumping into things (14 px), so a hit that only grazes you on screen doesn't count.
- **Your attacks**:
  - **Sickle**: a 150-degree swing, 72 px reach, exactly the white arc you see.
  - **Torch jab**: narrower and longer (92 px).
  - **Steel-toed kick**: a short wedge in front.
  - **Thrown berry**: a 60 px splash where it lands.
- **Enemy attacks**: each telegraph is the hitbox: the circle, the wedge, or the boar's
  own body moving along its lane.
- **A hit counts when the shapes overlap anywhere**, not just when the centre is inside.
  So a bear whose middle is out of reach still gets hit when its body is in the swing.
  Something right behind you doesn't.
- **F3** shows the hitbox view: green rings for players, orange for enemies, and each
  attack for a moment (red if it hit, white if it missed).

## Moving

| | |
|---|---|
| **Dash** (Space) | A quick burst in the direction you're moving. Costs 1 stamina orb. **No invincibility**: dash *out* of a telegraph, not through it. |
| **Sprint** (hold Shift) | 1.6x speed while held. Drains orbs (1.25 a second). |
| **Block** (hold right-click with a shield) | See Shields below. |
| **Stamina orbs** | 5 orbs (6 with a Stamina Acorn) under your hearts. Swinging the sickle costs half an orb. Orbs refill after a short pause. |
| **Aim separately from moving** | The mouse (or right stick) sets where you face, swing and throw, wherever you're walking. Leave the mouse alone for 3 s and you face where you walk again. |
| **Pulley lifts** | Stand on the platform and press E. Everyone standing on it rides together. If the platform is at the other end, press E next to the empty end to call it. Cliffs can't be walked up, so lifts are how you reach the Canopy Ledge (Fernery) and the Deep Shelf (Mossmouth). |

There is no jump. With this camera angle, dashes and lifts read better than hops.

## Shields

Put a shield in your offhand and **hold right-click** to raise it. When a hit lands, how
long the shield had been up decides the block:

| Block | When | Damage stopped | Shield takes | Stamina | Extra |
|---|---|---|---|---|---|
| **Perfect** | Raised just before the hit (the shield's Perfect window) | All of it | Nothing | Half | Stuns the attacker for 1.2 s |
| **Great** | A little earlier (the Great window) | Most | Half of what it stopped | Three quarters | |
| **Regular** | Any earlier | Some | All of what it stopped | Full | |

- A shield only covers an **arc in front of you**. A hit from behind or the side outside
  that arc goes straight through.
- The arc is **drawn on the ground around you**:
  - faint blue while you're not blocking;
  - bright while you block: gold in the Perfect window, white in the Great window, blue
    after that;
  - red dashes all the way round the back, where you're open.
- Shields have their own **health** (shown under your hearts). At 0 the shield **breaks**:
  you can't block until its break time is over, then it slowly regrows. Each shield keeps
  its own health.
- Holding a shield up drains stamina slowly, and every block costs stamina too. With no
  stamina left, you can't block.
- Heavier shields slow you down more while blocking.

| Shield | Health | Covers | Perfect / Great window | Stops (Perfect / Great / Regular) | Block cost | Speed blocking | Breaks for | Regrows | Where |
|---|---|---|---|---|---|---|---|---|---|
| Pot Lid | 6 | 70 degrees | 0.12 s / 0.30 s | 100 / 75 / 50% | 1 orb | 55% | 4 s | 1.0 a second | Starting bag |
| Buckler | 4 | 50 degrees | 0.18 s / 0.40 s | 100 / 70 / 40% | 0.6 orb | 85% | 2.5 s | 1.6 a second | Willow's House |
| Tower Shield | 14 | 150 degrees | 0.08 s / 0.20 s | 100 / 90 / 75% | 1.5 orbs | 30% | 6 s | 0.6 a second | The Clockmaker's (locked) |
| Spike Shield | 8 | 65 degrees | 0.12 s / 0.28 s | 100 / 70 / 50% | 1 orb | 50% | 4 s | 0.9 a second | Old Storehouse (locked) |

The **Spike Shield** hurts whatever you block: 2 damage, or 4 on a Perfect block. All of
these numbers are in `game/data/items.gd` (`SHIELDS`).

## Houses

The four houses along the top road in Middlemost are solid, and each has a front door
with its name over it.

- **Press E on the doorstep** to go in. Each house is a room of its own: a fireplace (it
  relights torches), a bed, a table, a shelf, and sometimes a chest.
- **Walk onto the doormat** to go back out.

| House | Door | Inside |
|---|---|---|
| Pepper's Cottage | Open | A cosy room |
| Willow's House | Open | A chest with a Buckler |
| The Clockmaker's | Locked: **Brass Key** (in the Canopy Ledge chest, Fernery) | A chest with a Tower Shield |
| Old Storehouse | Locked: **Rusty Key** (in the Deep Shelf chest, Mossmouth) | A chest with a Spike Shield and a Stamina Acorn |

- A locked door shows a padlock. Pressing E without the key tells you which key it needs.
- With the key, the door unlocks **for good, for everyone in that world**, and that's saved.
- On the map, a friend who's inside a house shows at its front door.

## Gear

Press **I** for the bag and gear. Right-click an item in the bag to wear it; click a worn
piece to take it off. There are 7 slots: helmet, chest, shoes, offhand and 3 trinkets.

| Item | Slot | Effect |
|---|---|---|
| Saucepan Helmet | Helmet | Every hit does 1 less damage |
| Miner Helmet | Helmet | Headlamp (light without a torch) |
| Leaf Hood | Helmet | Stamina refills 35% faster |
| Padded Overalls | Chest | +2 hearts |
| Raincoat | Chest | Torch stays lit in rain |
| Hermes Boots | Shoes | 1.45x speed |
| Steel-Toed Boots | Shoes | Sprint into an enemy to kick it (2 damage) |
| Wellies | Shoes | 1.1x speed |
| Torch, Lantern, any shield | Offhand | See above |
| Stamina Acorn | Trinket | +1 orb |
| Feather Pin | Trinket | Dashes go 35% further |
| Ember Charm | Trinket | Sickle hits set enemies alight while your torch is lit |
| Glow Pebble | Trinket | Faint glow |

**Sets**: wear all three pieces for a bonus.

- **Wayfarer's Set** (Leaf Hood, Raincoat, Wellies): dashes cost half an orb. It's in the
  chest on the Fernery's Canopy Ledge, with the Brass Key.
- **Miner's Set** (Miner Helmet, Padded Overalls, Steel-Toed Boots): the headlamp reaches
  twice as far and kicks hit harder. It's in the chest on Mossmouth's Deep Shelf, behind
  an ice wall you have to melt with the torch, with an Ember Charm and the Rusty Key.

Chests give their loot once per player, so everyone in the group can get a set.

Everyone starts with:

- **In the wheel**: the sickle.
- **Offhand**: a torch.
- **In the bag**: a watering can, popberry seeds, popberries, radish seeds, two Lamp Oil, a
  lantern, a Pot Lid, Hermes Boots, a Saucepan Helmet, a Stamina Acorn, a Feather Pin and
  a Glow Pebble.

## Tests

| Command | What it checks |
|---|---|
| `godot --headless --path . -s res://game/tests/unit_tests.gd` | 40 quick checks of the rules: hitbox shapes, the item wheel, shields, lessons and walls |
| `python tools/mp_test.py --godot ... --scenarios` | 39 mechanics played over a real connection: attacks and telegraphs, dashes, the three block levels, shields breaking, spikes, shield arcs and speed, fire, rain, lanterns, ice, chests and sets, stamina, aiming, darkness, fainting, sickle hitboxes, the item wheel, Pepper's lessons, open and locked doors |
| `python tools/mp_test.py --godot ... --save-test` | Plays a solo world, saves, starts it again, and checks that everything came back |
| `python tools/mp_test.py --godot ...` | The 5-player session (see `docs/MULTIPLAYER.md`) |

Results are in `docs/MULTIPLAYER_TEST_RESULTS.md`.
