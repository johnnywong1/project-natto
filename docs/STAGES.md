# Stages (zones) are data files

Every outdoor zone is one JSON file in `game/data/zones/`, and the house interiors come from
`game/data/zones/houses.json`. The game reads them when it starts, so you make or change a
stage by editing a file: no code changes needed. `game/data/zones.gd` loads them and
`game/world/zone_view.gd` draws them.

To add a stage: copy `_template.json` to `<id>.json`, change the fields, and give it an exit
from an existing zone (and an exit back). Files whose names start with `_` are ignored, so
drafts can live in the folder. Run `godot --headless --path . -s res://game/tests/unit_tests.gd`
to validate every stage file.

## Value types

| In the file | In the game |
|---|---|
| `[x, y]` | `Vector2` (a position) |
| `[x, y, w, h]` | `Rect2` (a rectangle) |
| `"#rrggbb"` | `Color` |
| `3` / `3.5` | `int` / `float` |

Coordinates are pixels, with (0, 0) at the top-left of the zone.

## Fields

Required:

| Field | Meaning |
|---|---|
| `id` | The zone's id (matches the file name). |
| `name` | Shown on the HUD, the map and exit signs. |
| `order` | Map-tab order of the outdoor zones. |
| `size` | Zone size in pixels. |
| `ground`, `accent` | Ground colour and the colour of the grass tufts. |
| `outdoor` | `true` gets day and night; `false` is dark all day (a cave). |
| `light`, `tint` | Ambient light level (0-1) and colour. |
| `climate` | Weather name → weight, for example `{"clear": 5, "rain": 2}`. Names: clear, cloudy, rain, mist, drizzle, drip, spores. Rain and drizzle water crops and put torches out. |
| `spawn` | Where new players appear. |
| `exits` | `{"rect", "to", "arrive", "label"}`: walking into `rect` moves you to zone `to` at `arrive`. |
| `fires` | Positions that relight torches. `fire_kind` picks the look: `campfire` or `brazier`. |
| `lamps` | Street lamps (also relight torches, and light the night). |
| `walls` | Solid rectangles (cliffs, houses). |
| `plateaus` | Raised areas (drawn as a ledge; reached by a lift). |
| `lifts` | `{"id", "bottom", "top", "label"}`: a pulley lift between two points. |
| `ice` | Ice block centres (melted with a torch, leaves a puddle). |
| `chests` | `{"id", "pos"}`; the loot per chest id is in `game/data/items.gd` (`CHEST_LOOT`). |
| `spawns`, `night_spawns` | Enemy kind → how many at once (night adds to the day count). Kinds are in `game/data/enemies.gd`. |
| `pickup`, `pickups` | Which item grows wild here and how many are out at once. |
| `seed` | Seed for the scattered decor and the farm's starting soil. |

Optional:

| Field | Meaning |
|---|---|
| `farm` | `{"origin", "cols", "rows"}`: a farm grid of plots. |
| `well` | A well to fill watering cans at. |
| `doors` | `{"pos", "to"}`: house doors; `to` is an id in `houses.json`. |
| `npcs` | `{"id", "name", "pos"}`: villagers (`pepper` runs the lessons). |
| `paths` | `{"points", "width", "color"}`: drawn paths and streams; decor keeps off them. |
| `landmarks` | Special drawings: `{"kind": "great_sprout", "pos"}`. |
| `decor` | Fixed decor: `{"kind", "pos", "scale"}`. Kinds: house, board, tree, bush, flower, rock, fern, mossrock, roots, stalagmite, puddle, mushroom. |
| `keep_clear` | Rectangles the scattered decor stays out of (the village square, the Great Sprout...). Exits, paths, the farm and the well are kept clear automatically. |
| `scatter` | Random decor placed by the seed: `{"kind", "count", "margin", "scale": [min, max]}`. `variants: 4` picks a whole-number look instead of a scale (flowers). `region: [x, y, w, h]` limits a rule to one area (roots along a cave roof). `glow_every: 3` with `glow_color` adds a light to every third one (glowing mushrooms). |
| `lights` | Fixed lights: `{"pos", "color", "scale", "energy"}`. |

## Trees and bushes

Trees (fixed `decor` or `scatter`) are **solid** — they block movement — and can be **chopped**:
swing the sickle at one and after a few hits it falls, drops Lumber, and leaves a stump that
grows back into a tree after a while. **Bushes don't block**, but they slow you to about half
speed while you push through them.

Both are placed the same way as any decor, but their positions now come from `zones.gd`
(`Z.all_decor` / `Z.tree_sites` / `Z.bush_sites`) so the collision code and the renderer agree
on every tree and bush. A tree's stump is tracked by its index among the zone's trees, so if you
reorder or change a zone's `scatter`/`decor`, existing saves may show a stump on a different
tree — fine for development, worth knowing. Tuning lives at the top of `world_state.gd`
(`TREE_CHOPS`, `TREE_REGROW`, `TREE_LUMBER`) and `zones.gd` (`TREE_SOLID_BASE`, `BUSH_RADIUS`,
`BUSH_SLOW`).

## houses.json

```json
"house_clock": {"name": "The Clockmaker's", "door": [1900, 354], "lock": "brass_key",
                "wall": "#d6d0ef", "chest": "clock_chest"}
```

`door` must match a door in the village stage; `lock` is the key item needed (empty = open);
`chest` is a chest id or empty. The room layout itself is built by `Zones._interior()`.

## Exporting

JSON files are not resources, so an export preset must include them: add `*.json` to the
preset's "Filters to export non-resource files" (Project > Export). The editor and
`godot --path .` read them directly.
