# Multiplayer

Up to **5 players**. One player hosts (a listen server) and the others join. Built on Godot's
high-level multiplayer with ENet over UDP.

## Playing

1. Run the game. The main scene is the title screen (`game/menu/main_menu.tscn`).
2. Pick a name and hoodie colour.
3. **Host a game**: pick a save slot (continue a world or start a new one). The default
   port is 7777. Friends join, tick **Ready**, and you press **Start**. Friends can still
   join after the game has started; they arrive with the current world.
4. **Join a game**: type the host's address and press **Join**, or pick the game from
   **Games on your network** (found automatically on the same Wi-Fi).
5. A sixth person is told the game is full.
6. **Play solo** works the same way, with no network at all.
7. **Leaving**: Esc > Exit / Logout.
   - When the **host** exits, the world saves and the game ends for everyone: each player
     is sent back to the title screen with "*host* ended the game."
   - When anyone else exits, only they leave. The others see "*name* went home", and the
     host saves that player's things under their name for next time.

Playing over the internet (not the same Wi-Fi) needs the host to forward UDP port 7777 on
their router, or everyone to join the same virtual LAN (Tailscale, ZeroTier). A Steam lobby
can replace this later by swapping in a Steam multiplayer peer; nothing else changes.

To try several players on one PC, run `game/tests/local_session_host.tscn` once, then
`game/tests/local_session_client.tscn` up to four times. Each window plays itself with a
test bot. You can also use **Debug > Customize Run Instances** in the editor with arguments
such as `--host --name=Ana` and `--join=127.0.0.1 --name=Ben`.

## Controls

Everything is on the controls screen: **F1** in game, or **Esc > Controls**, or **Controls**
on the title screen (`game/ui/controls_panel.gd`). The main ones:

| | Keyboard and mouse | Gamepad |
|---|---|---|
| Move / aim | WASD / mouse | Left stick / right stick |
| Use what you're holding | Left click or J | X / Square |
| Offhand: torch jab, lantern on/off, hold to block with a shield | Right click or K | B / Circle |
| Dash / sprint | Space / hold Shift | A / left stick click |
| Talk, harvest, open doors and chests, ride lifts, relight, revive | E or F | Y / Triangle |
| Item wheel | Hold Q or Tab (also 1-8, mouse wheel) | Hold LB |
| Bag and gear / map / drop a pin | I / M / P | Back / D-pad up / RB |
| Menu (pause, settings, controls, exit) | Esc | Start |

See `docs/GAMEPLAY.md` for the item wheel, Pepper's lessons, houses, shields, darkness and
light, enemies, hitboxes, stamina, lifts and gear.

## How it works

- **Host owns the world** (`World` autoload, `game/world/world_state.gd`): clock, weather,
  crops, enemies and their AI, pickups, pins, ice, lifts, house doors, and every player's
  bag, item wheel, gear, hearts, shields, torch and lantern, chests and lessons. Every zone
  keeps running even when nobody is in it, including the house interiors.
- **The host saves** (`game/save/save_game.gd`) to the save slot the world was started in.
- **Players own their movement**: each player moves locally and sends position 20 times a
  second; the host keeps it inside the right zone.
- **Zones are instances**, like Stardew Valley's locations: Middlemost, The Fernery and
  Mossmouth are separate big maps linked by exits, and each house is a small zone of its
  own. Detailed updates (other players, Wilts)
  go only to people in the same zone. Map beacons (zone + position of everyone) go to all
  players 4 times a second, which is how friends show up on the map anywhere.
- **Reliable events** for things that must not be lost: crops, pins, weather, bags, gear,
  hearts, pickups, ice, lifts, telegraphs, zone changes, effects. The clock is resynced every
  2 seconds, corrected for ping.
- **Combat is judged where the player can see it.** The host announces each enemy attack
  (a telegraph with its shape and timing). Each player's own game decides, at the moment it
  lands on their screen, whether they were inside it, had dashed out, or were blocking it
  facing the right way, and tells the host. The host checks the attack was real and the
  timing fits, then applies the damage. On a laggy connection, what you dodge on screen is
  what you dodged.
- **Day/night and weather**: one shared clock (a day is 16 real minutes). Each zone has its
  own climate (Middlemost: clear/cloudy/rain; Fernery: mist/drizzle/clear; Mossmouth:
  drips/spores) and lighting: nights are properly dark and Mossmouth is dark all the time.
  Rain and drizzle water crops and put out torches.

## Automated tests

The whole suite: `python tools/run_tests.py --godot /path/to/godot` (see `docs/TESTING.md`).
The pieces:

`tools/mp_test.py` starts a host and four players as headless Godot processes. Test bots play
different roles across all three zones:

- the farmer loses its torch to rain and relights it at the campfire;
- the climber rides the Fernery's pulley lift up with the fighter, loots the Wayfarer set
  and relights its torch at the ledge campfire;
- the delver calls Mossmouth's lift over, rides down, melts the ice wall, loots the Miner's
  set, refills the can at the meltwater and swaps to a lantern;
- the fighter blocks or dashes out of telegraphs and circles enemies while aiming at them;
- the late joiner thaws a Frost Wilt with the torch.

Partway through, one player leaves and another joins the game in progress; then a sixth
player tries to join a full game. Each process writes a JSON report and the script makes
52 checks. They cover:

- the lobby, joining and leaving;
- map beacons, zone isolation and positions over time;
- pins, crops, weather, the clock, day/night and darkness;
- the bag, the item wheel and gear (yours, and what friends see);
- lights in the dark, torches in the rain and lantern oil;
- enemy types, telegraphs, blocks and dodges, strafing, thawing and hearts;
- ice, chests and sets, and lifts (two riders, calling, levels), dashes and stamina;
- snapshot rate, ping, host frame time and bandwidth.

`--scenarios` instead runs the 39 mechanic scenarios in `game/tests/scenarios.gd` one by one
over a real connection, and `--save-test` plays a solo world, saves it, loads it again and
checks everything came back (see `docs/GAMEPLAY.md`). `game/tests/unit_tests.gd` checks the
rules on their own in a second.

```
python tools/mp_test.py --godot "C:/path/to/godot.exe" --project .
python tools/mp_test.py --godot ... --lag 40 --jitter 10 --loss 0.02    # ~80 ms ping, 2% loss
python tools/mp_test.py --godot ... --lag 75 --jitter 25 --loss 0.05    # ~150 ms ping, 5% loss
python tools/mp_test.py --godot ... --scenarios [--lag ... --jitter ... --loss ...]
python tools/mp_test.py --godot ... --save-test
godot --headless --path . -s res://game/tests/unit_tests.gd
```

The lag options route players through `tools/lag_proxy.py`, a small UDP relay that adds
delay, jitter and packet loss.

Command-line options the game understands (after `--`): `--host`, `--join=ADDRESS`,
`--port=N`, `--name=X`, `--color=0-4`, `--autostart=N`, `--bot`, `--role=0-5`,
`--report=PATH`, `--report-at=SECONDS`, `--linger=SECONDS`, `--time-scale=X`,
`--weather-period=SECONDS`, `--force-weather=ZONE:KIND:START:SECONDS`, `--solo`, `--slot=N`,
`--wipe-slot`, `--save-at-report`, and for the scenario test `--test` (host: allows test
commands) and `--scenario=all|NAME,NAME`.
