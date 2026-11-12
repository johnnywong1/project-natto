# Project Natto: engineering guide (codebase, testing, PC deploy)

The same content lives in the repo as Claude Code skills under `.claude/skills/` (natto-codebase, natto-testing, natto-pc-deploy). Update both when something changes.

# Project Natto: codebase guide

A cozy co-op farming adventure, Godot 4.7, GDScript, everything drawn in code (no image
assets yet). Repo: github.com/johnnywong1/project-natto. Main scene:
`game/menu/main_menu.tscn`. Autoloads (in load order): `Net`, `World`, `Sound`, `Display`.

## Where things live

| Path | What |
|---|---|
| `game/net/net.gd` | `Net`: solo (OfflineMultiplayerPeer), ENet host/join, room, LAN discovery, command-line options for tests, `leave()`, `_rpc_session_over` |
| `game/world/world_state.gd` | `World`: the host-owned world. Clock, weather, crops, enemies, lifts, ice, chests, doors, lessons, shields, saves. ~2100 lines |
| `game/world/world_view.gd` + `world.tscn` | The game screen on each client: input, local hit judging, snapshots → nodes, zone changes, camera |
| `game/world/avatar.gd` | A player: movement, stamina, dash, block tiers, shield coverage arc, drawing |
| `game/world/zone_view.gd`, `enemy_view.gd`, `npc_view.gd`, `fire_prop.gd`, `lift_prop.gd`, `telegraph.gd`, `fx.gd`, `day_night.gd`, `weather_fx.gd`, `pin_layer.gd`, `hitbox_debug.gd` | What you see |
| `game/combat/hitboxes.gd` (`HB`) | Every hitbox/hurtbox shape (circle, sector, lane) and `HB.hits(a, b)` |
| `game/data/items.gd` | Items, gear slots, sets, `SHIELDS` (per-shield stats), `CHEST_LOOT`, the wheel rules |
| `game/data/enemies.gd` (`E`) | Enemy kinds, telegraphs, stun constants |
| `game/data/zones.gd` (`Z`) + `game/data/zones/*.json` | Stages are data files (see `docs/STAGES.md`); `houses.json` for interiors |
| `game/data/lessons.gd` | Pepper's 9 lessons: talk lines, tasks, rewards |
| `game/save/save_game.gd` | Slots 1-3 in `user://saves/slot_N.json`; write to tmp then rename |
| `game/ui/` | `hud.gd` (owns screens, decides what Esc does), `hud_draw.gd` (the drawn HUD), inventory/map/wheel/dialogue/pause/settings/controls panels, `palette.gd`, `ui_theme.gd`, `icons.gd` |
| `game/audio/sound.gd` | `Sound`: synthesized placeholder SFX and music, volumes in `user://settings.cfg` |
| `game/display/display_settings.gd` | `Display`: window mode/size/vsync, F11 |
| `game/tests/` | unit, ui, menu, lobby tests; `scenarios.gd`; `test_bot.gd`; `test_report.gd`; `local_session_*.tscn` (multi-window launcher on the PC) |
| `tools/` | `run_tests.py`, `mp_test.py`, `lag_proxy.py` |
| `demo/sprout_patch/` | The old one-screen demo; untouched |

## Conventions

- **Host-authoritative.** Clients call `World.to_host(&"c_xxx", [...])` (requests, prefix
  `c_`); the host validates with `_sender()` and pushes state with `_rpc_xxx` via
  `_to_peer`, `_to_clients`, `_to_zone`. 20 Hz per-zone snapshots, 4 Hz map beacons. In
  solo, `Net.solo` is true and `is_host()` is true, so the same code runs locally.
- **Hits are judged on the player's screen** (`world_view._got_hit` → `c_hit_me(enemy_id,
  atk_id, tier)`; `atk_id 0` is contact), then checked by the host (distance, timing,
  shield state). Shield tier: 3 Perfect, 2 Great, 1 Regular, 0 none.
- **Typed GDScript.** The project treats "inferred from Variant" as an error: write
  `var x: Dictionary = d["k"]`, never `var x := d["k"]`. Loop vars typed too (`for k: String in d`).
- **No multi-line lambdas inside call arguments**; use a method.
- Every script starts with a `##` header saying what it does. Keep it true when editing.
- Drawing helpers: `P.blob`, `P.shape`, `P.rounded_rect_points`, `P.text` in `palette.gd`;
  `Icons.draw(canvas, item_id, at, scale)`.
- Test hooks: the host accepts `c_debug(cmd, args)` only with `--test` /
  `World.test_mode` (`clear`, `spawn`, `give`, `teleport`, `goto`, `heal`, `weather`,
  `clock`, `attack`, `pause_ai`). Vector2 args from JSON tools must be sent as the string
  `"Vector2(x, y)"`.

## How to add things

- **Item/gear**: `Items.ITEMS` entry (+ `Icons` drawing); a set in `Items.SETS`; loot in
  `CHEST_LOOT`. Shield: `Items.SHIELDS` (hp, cost, hold, recover, break_time, perfect,
  great, eff[3], arc, move, spikes) + `shield_text`.
- **Enemy**: `E.KINDS` (radius, scale, touch, speed, attack shape) + `enemy_view.gd`
  drawing + a telegraph in `telegraph.gd` if it attacks. Add a scenario.
- **Stage**: copy `game/data/zones/_template.json`; `unit_tests` validates it.
- **Lesson**: `Lessons.LESSONS` + the event name fired from `World.lesson_event`.
- **Screen**: a Control created in `hud.gd._ready`; add to `is_blocking()` and
  `escape()`; `_unhandled_input` must test `is_visible_in_tree()`, not `visible`, and
  mark the event handled.
- **Save field**: `save_game.capture` / `restore_*`; the save test compares reports.

Then: run `python tools/run_tests.py --godot <godot>` (see the `natto-testing` skill) and
update `docs/GAMEPLAY.md` if the player can notice the change.

---

# Project Natto: testing

All tests are headless Godot 4.7 runs. Linux Godot in the cloud workspace:
`/home/claude/godot/Godot_v4.7.2-stable_linux.x86_64` (download the Linux x86_64 build
from godotengine.org releases if missing). On the user's PC the editor binary is under
Steam; tests run there with the same commands.

## Run everything

```
python tools/run_tests.py --godot <godot>            # 7 suites, ~4 min on 2 cores
python tools/run_tests.py --godot <godot> --all      # + home/rough lag profiles, ~10 min
python tools/run_tests.py --godot <godot> --only unit,ui
```

Output: one line per suite; `test_results/` holds logs and `summary.json` per suite.
Full details in `docs/TESTING.md`. Record the final numbers in
`docs/MULTIPLAYER_TEST_RESULTS.md` when a feature lands.

## Suites and what breaks them

| Suite | Script | Typical cause of failure |
|---|---|---|
| unit | `game/tests/unit_tests.gd` (`-s`) | a stat/rule change, a bad stage JSON |
| ui | `--solo --ui-test` | a screen swallowing Esc, pause-menu flow |
| menu | `--menu-test` | title-screen pages, world slots |
| lobby | `mp_test.py --lobby-test` | join/ready/start/leave/host-exit |
| save | `mp_test.py --save-test` | a new field not in `save_game.gd` |
| session | `mp_test.py` | bot got stuck (check `*.log` for its position), snapshot rate dip under load (re-run once) |
| scenarios | `mp_test.py --scenarios[=a,b]` | mechanic regressions; run one by name while iterating |

Quick compile check without running: `/tmp/check.sh` in the cloud (loads every script
under `res://game` and `res://demo` and reports parse errors), or
`godot --headless --path . --check-only -s <script>`.

## Writing checks

- Keep the check message specific: `"hp 10 -> 9 (expect -1)"`.
- Scenarios: `_s_<name>() -> Array` returning `[ok, message]`; add the name to the list at
  the top of `scenarios.gd`. Helpers: `_goto`, `_spawn`, `_equip`, `_debug`, `_wait`,
  `_poll`, `_expect_hp`, `_rtt`. Set `world.aim_override` to face a direction, `me.want_block`
  to block. Reset state with `_reset()` between steps if hp/torch matter.
- The host randomises spawn by ±80 px and the "host closed the game" message is
  `"The host closed the game."`; don't assert exact positions or old wording.
- Transient flakiness seen so far: snapshot rate 14-18 Hz when 7 Godot processes share 2
  cores; a bot stuck on a ledge if it chases an enemy on another level (fixed by level
  filters). Re-run before calling it a regression; fix the bot rather than loosening checks.

---

# Project Natto: cloud → PC → Godot editor

## The three places

- **Cloud working copy** (source of truth while building): `/home/claude/natto_pc`. Edit and
  test here first (`natto-testing`).
- **PC project**: `C:\Users\wong5\OneDrive\Documents\project-natto`, mounted in
  `device_bash` as `$HOME/mnt/project-natto`; `device_commit_files` takes
  `devicePath: "~/mnt/project-natto/<rel>"`. OneDrive syncs it; nothing is committed to git
  unless the user asks.
- **Godot editor on the PC** via `mcp__remote-devices__Godot_MCP__*`. The MCP server has
  two backends: `editor` (live, undoable) when the editor is open with the plugin, and
  `headless` (edits files on disk) when it is not. `godot_status` first, always.

## Installing a change on the PC

1. `godot_status`: if `is_playing`, the user may be playing: take a screenshot and look
   before stopping (a character fainting with no input = an idle test window, safe to
   stop with `godot_run_stop`).
2. Close open scenes you are about to move or delete (`godot_scene_close`).
3. Renames/moves: `godot_files_move` carries `.uid` sidecars but does **not** rewrite
   `res://` paths inside `.tscn`/`.gd`. Commit the updated `.tscn` afterwards. Deletes:
   `godot_files_delete` (recursive for folders); plain `rm` in `device_bash` needs the
   delete permission (`device_request_delete_permission`, once per session).
4. Copy files: stage under `/mnt/user-data/outputs/natto_deploy/<rel>` and
   `device_commit_files` (≤50 per call, `force: true` to overwrite). Never `.uid` files
   for scripts that exist on the PC (keep theirs); new scripts get a uid when the editor
   scans. Verify with `md5sum` on both sides (exclude `.uid`, `project.godot`, `icon.svg*`).
5. Settings: `godot_project_set` (main scene), `godot_input_edit` (actions; remove_event
   by index, add_event with `{type: joy_button, button: "start"}`), `godot_autoload_edit`.
   Don't hand-edit `project.godot` on the PC while the editor is open.
6. `godot_project_validate` with `deep: true`: 0 errors expected once the editor has
   rescanned. If the editor disconnected after big moves, `godot_editor_launch` reopens it
   (it comes back on the project's welcome state with stale scenes closed). Tell the user
   that an already-open editor needs Project > Reload Current Project after autoload or
   many-file changes.

## Running and looking

- `godot_run_start` with `mode: process`, `headless: false` gives a window you can drive
  and screenshot without touching the editor's play state. Stop it when done.
- `godot_game_input`: clicks by viewport px (1152×648), keys (`"Escape"`, `"E"`), phases
  `press`/`release` for holds (right-click hold = block). `godot_game_time` `speed 0.02`
  freezes action for a screenshot of a timing window; set it back to 1.
- `godot_game_edit` `call` on `/root/World` with `c_debug` works only after setting
  `test_mode: true` (set `save_slot: 0` too, so the run doesn't overwrite a real slot).
  Vector2 arguments must be the string `"Vector2(x, y)"`; a bare `[x, y]` is an Array and
  fails type checks.
- `godot_game_eval` is disabled on this install; use `godot_game_get` with `"prop:sub"`
  or `"getter()"` and `godot_game_edit` instead.
- Screenshots: `godot_game_screenshot` with `region` for close-ups; `save_to:
  user://shots/x.png` keeps full size. `max_size` 960 fits chat well.
- Solo play from the title screen in the test window: click Play solo (576,313) → New
  world in slot 1 (810,434). Check the slot is empty first (menu shows "Slot 1: empty");
  otherwise use `--solo` via the local_session scenes or set a scratch slot.

## Lessons learned

- The editor's old Sprout Patch and welcome scenes are gone; `scenes/` and `scripts/`
  were folded into `demo/sprout_patch/` and `game/ui/palette.gd`.
- `Control._unhandled_input` on a panel nested in another screen must check
  `is_visible_in_tree()`; a hidden parent with a visible child swallowed Esc for a night.
- Interiors are smaller than the viewport: camera limits are widened for interiors so the
  doormat isn't hidden under the HUD.
- Typed GDScript everywhere; the Windows editor's warnings-as-errors config is the same as
  the cloud's, so anything the cloud `/tmp/check.sh` passes loads on the PC.
- Deploy only after the cloud test matrix is green; the user plays between sessions and a
  broken script in OneDrive shows up as red errors in their editor.
