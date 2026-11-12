# Project Natto

A cozy co-op farming adventure for 1 to 5 players, made in Godot 4.7.

Open the project in Godot and press Play. The title screen lets you play solo, host a game
or join one.

- How to play: `docs/GAMEPLAY.md`
- Multiplayer: `docs/MULTIPLAYER.md`
- Making stages: `docs/STAGES.md`
- Tests: `docs/TESTING.md` (`python tools/run_tests.py --godot /path/to/godot`)
- Latest test results: `docs/MULTIPLAYER_TEST_RESULTS.md`

## Where things are

Everything is drawn in code (no image files yet), so each script's header comment says
what it draws or does.

| Folder | What's in it |
|---|---|
| `game/menu/` | The title screen: solo, host, join, save slots, controls (the game's main scene) |
| `game/net/` | `net.gd`, the `Net` autoload: solo, hosting, joining, the waiting room, finding games on your Wi-Fi |
| `game/world/` | The game itself |
| `game/combat/` | `hitboxes.gd`: every hitbox and hurtbox shape, and the overlap tests |
| `game/data/` | Pure data and rules: items, shields and the wheel; enemies; Pepper's lessons; `zones.gd` loads the stages |
| `game/data/zones/` | The stages: one JSON file per zone, plus `houses.json` (see `docs/STAGES.md`) |
| `game/display/` | `display_settings.gd`, the `Display` autoload: window mode, size, vsync, F11 |
| `game/save/` | `save_game.gd`: save slots, what's saved and how it's loaded back |
| `game/ui/` | The HUD and every screen |
| `game/audio/` | `sound.gd`, the `Sound` autoload: sound effects, music, volume settings |
| `game/tests/` | Unit, UI, menu and lobby tests, the network scenarios, the test bot and report, and the local multi-window launcher |
| `demo/sprout_patch/` | The earlier one-screen Sprout Patch demo (single player) |
| `tools/` | `run_tests.py` (every test suite), `mp_test.py` (sessions, scenarios, save and lobby tests) and `lag_proxy.py` (fakes a bad connection) |
| `addons/godot_mcp/` | The Godot MCP editor plugin |

What's in the bigger folders:

- **`game/world/`**:
  - `world_state.gd`: the `World` autoload, the shared world the host runs.
  - `world_view.gd` and `world.tscn`: the game screen.
  - The things you see: `avatar.gd`, `enemy_view.gd`, `npc_view.gd`, `zone_view.gd`, plus lights, weather and effects.
- **`game/ui/`**:
  - The HUD: `hud.gd` and `hud_draw.gd`.
  - The screens: item wheel, bag, map, dialogue box, pause menu, settings and controls.
  - Shared look: `palette.gd`, `ui_theme.gd`, `icons.gd`.
