# Minimap — design direction

Status: **design note**, not built yet. Captured from a Scrabdackle reference the team liked.

## Where we are today
`game/ui/hud_draw.gd` `_draw_minimap()` draws a small scaled top-down picture of the current
zone: ground, farm, exits, NPCs, pins, other players and you. It works for the open overworld
and reads the zone straight from its stage file. Good enough for the demo.

## Where we want to go
Two different minimaps, chosen by the kind of place you're in:

- **Dungeons → a room-grid map (the Scrabdackle look).** A dungeon is a set of rooms on a
  grid, joined by doorways. The minimap shows one cell per *discovered* room, corridors as short
  links between neighbours, the room you're in highlighted, and icons for things found (chest,
  stairs, boss, locked door). Undiscovered rooms stay blank until you enter them. This reads far
  better than a scaled top-down view when the space is corridors-and-rooms.
- **Overworld → keep a free-form map.** The grid falls apart outdoors (Middlemost isn't on a
  grid), so the overworld keeps today's scaled top-down minimap, refined over time.

## What building the dungeon map needs
Dungeons aren't a zone *type* yet — that's the first dependency. A sketch of the pieces:

1. **A dungeon zone kind.** Either a new stage type whose rooms sit on integer grid cells
   `{col, row}` with links `{to, dir}`, or a generator that lays rooms on a grid. Each room is
   (or compiles to) a zone like today's, plus its grid coordinate and its doorways.
2. **Discovery state.** Per-world, per-dungeon set of visited room cells (host-authoritative,
   synced and saved — mirror how `stumps` / `ice` are done in `world_state.gd`). Mark a room
   discovered on first entry; optionally reveal immediate neighbours as "seen but unvisited".
3. **Room metadata for icons.** Flags per room: has a chest, stairs up/down, a locked door, a
   boss. These can live in the dungeon stage data.
4. **A grid renderer.** A new branch in `_draw_minimap()` (or a sibling `_draw_dungeon_map()`)
   that, when `Z.is_dungeon(zone)`, draws the discovered cells as rounded squares with links and
   icons instead of the scaled view. The full-screen map (M) gets the same treatment.

## Smallest first step when we pick this up
Add the dungeon zone kind with a hand-made 3–4 room test dungeon and the discovery set, then the
grid renderer. Everything else (icons, generation) can follow. Until then the overworld minimap
is unchanged.
