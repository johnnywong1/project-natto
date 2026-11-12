# Testing

Everything runs headless (no window), on Linux, macOS or Windows, with the Godot 4.7
executable. One command runs the lot:

```
python tools/run_tests.py --godot /path/to/godot            # quick set, about 4 minutes
python tools/run_tests.py --godot /path/to/godot --all      # plus the two lag profiles
python tools/run_tests.py --godot /path/to/godot --only unit,menu
```

It prints one line per suite and writes `test_results/` (logs, a `summary.json` per suite,
`results.json` overall). Exit code 1 means something failed. Run it before every commit
that touches `game/`.

| Suite | What it covers | On its own |
|---|---|---|
| unit | Game rules with no network: hitboxes, the item wheel, shield stats and tiers, Pepper's lessons, zone collisions, the stage files | `godot --headless --path . -s res://game/tests/unit_tests.gd` |
| ui | The in-game screens, driven by real key presses: Esc opens the pause menu from the game, the bag, the map and the controls screen; Resume; Settings; Exit to the title | `godot --headless --path . -- --solo --ui-test` |
| menu | The title screen: every page, name and colour, the world slots (new, continue, delete), hosting a room and leaving it, Esc going back | `godot --headless --path . -- --menu-test` |
| lobby | Sign-in and sessions as two real processes: join, Ready, start, leave, rejoin mid-game, the host's exit ending the game for everyone | `python tools/mp_test.py --godot G --lobby-test` |
| lobby-ws | The same lobby story over WebSocket instead of ENet | `python tools/mp_test.py --godot G --lobby-test --transport ws` |
| save | A solo world is played by a bot, saved, started again and compared: bag, wheel, gear, crops, pins, lessons, clock, position | `python tools/mp_test.py --godot G --save-test` |
| session | A 5-player session: bots farm, fight, climb and delve; one leaves, one joins late, a 6th is turned away; snapshot rates and state agreement | `python tools/mp_test.py --godot G` |
| scenarios | 42 mechanic scenarios over the network: block tiers, shield break and recovery, spikes, coverage arcs, bumps, fire and ice, lifts, chests, doors, lessons | `python tools/mp_test.py --godot G --scenarios[=name,name]` |
| lag | The session and the scenarios through `tools/lag_proxy.py` at ~80 ms / 2% loss and ~150 ms / 5% loss | `python tools/mp_test.py --godot G --lag 40 --jitter 8 --loss 0.02` |

## Writing a test

* **A rule with no network** (an item, a shield stat, a hitbox): add a `check(...)` to
  `game/tests/unit_tests.gd`. It runs in well under a second.
* **A screen or a key**: add to `game/tests/ui_tests.gd` (in game) or
  `game/tests/menu_tests.gd` (title screen). They press keys with `Input.parse_input_event`
  and click buttons with `button.pressed.emit()`, then look at what's visible.
* **A mechanic that involves the host** (damage, enemies, weather, doors): add a
  `_s_<name>()` function to `game/tests/scenarios.gd` and its name to the list at the top.
  Scenarios run on a test client talking to a real host; `_spawn`, `_goto`, `_equip` and
  `_debug` set the scene through the host's test commands (`c_debug`, only with `--test`),
  and the check itself uses the same calls a player's input makes.
* **Something about joining, leaving or the room**: `game/tests/lobby_tests.gd` has a host
  story and a joiner story; add steps to both sides.
* **Bot behaviour over a whole session**: `game/tests/test_bot.gd` roles and the checks in
  `tools/mp_test.py`.

Keep each check's message specific ("hp 10 -> 9 (expect -1)") so a failure in the log says
what happened without opening the game.

## Interpreting failures

* A single scenario can be re-run on its own: `--scenarios=holding_off_a_slime`.
* `session` checks on snapshot rate can dip on a loaded machine (two cores running seven
  Godot processes); re-run before treating it as a regression.
* Logs for each process are in the suite's folder (`Host.log`, `Bot1.log`, `tester.log`...).
  Script errors show up as `SCRIPT ERROR` lines, and every suite also checks there were none.

The latest full results are in `docs/MULTIPLAYER_TEST_RESULTS.md`.
