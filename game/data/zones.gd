extends RefCounted
## Zones are separate instances, like Stardew Valley's locations: each is a big map of its
## own and players can be in different zones at the same time. Exits link them.
##
## Height works without jumping: a ledge ("plateau") is walled off by a cliff, and a pulley
## lift carries everyone standing on its platform up or down together.
## Fires (campfires, braziers, street lamps, fireplaces) relight torches. Ice blocks paths
## until a torch melts it; the melt leaves a puddle you can fill a watering can from.
##
## Houses: the village houses in Middlemost are solid, and each has a door. Press E on the
## doorstep to go inside: every house is a small zone of its own (an interior). Some doors
## are locked ("lock" = the key you need). Using the key unlocks the door for good, for
## everyone in that world. Inside, walk onto the doormat to go back out.

const TILE := Vector2(76, 58)
const GAP := 10.0
const ICE_RADIUS := 42.0
const LIFT_SIZE := Vector2(130, 90)
const FIRE_RANGE := 95.0

## Stage files. Every outdoor zone is a JSON file in res://game/data/zones/ (one per zone),
## and the house interiors come from houses.json in the same folder. docs/STAGES.md
## explains the format. The files are read once when this script loads.
const ZONE_DIR := "res://game/data/zones"
const ROOM_SIZE := Vector2(900, 620)

## zone id -> zone data (see docs/STAGES.md), outdoor zones only.
static var ZONES: Dictionary = {}
## House interiors: id -> {"name", "door", "lock", "wall", "chest"}.
static var HOUSES: Dictionary = {}
## The big outdoor zones, in map-tab order (the "order" field of each stage file).
static var OUTDOOR: Array[String] = []
## Every zone the host simulates: the outdoor zones and the house interiors.
static var ORDER: Array[String] = []

const WEATHER_NAMES := {
	"clear": "Clear", "cloudy": "Cloudy", "rain": "Rain", "mist": "Mist",
	"drizzle": "Drizzle", "drip": "Dripping", "spores": "Spore drift", "indoors": "Indoors",
}
## Weather that waters crops by itself and puts out torches and fires on enemies.
const WET_WEATHER: Array[String] = ["rain", "drizzle"]


static var _rooms: Dictionary = {}


static func _static_init() -> void:
	reload()


## Reads the stage files. Called once on load; tests call it again after editing a file.
static func reload() -> void:
	ZONES.clear()
	HOUSES.clear()
	OUTDOOR.clear()
	ORDER.clear()
	_rooms.clear()
	var dir := DirAccess.open(ZONE_DIR)
	if dir == null:
		push_error("Zones: can't open %s" % ZONE_DIR)
		return
	var files := Array(dir.get_files())
	files.sort()
	for f: String in files:
		if not f.ends_with(".json") or f.begins_with("_"):
			continue   # "_name.json" files are drafts and templates, not stages
		var data: Variant = read_file(ZONE_DIR + "/" + f)
		if not (data is Dictionary):
			push_error("Zones: %s is not a JSON object" % f)
			continue
		if f == "houses.json":
			HOUSES = data
		else:
			var zd: Dictionary = data
			var id := str(zd.get("id", f.get_basename()))
			var problems := validate(zd)
			if not problems.is_empty():
				push_error("Zones: %s: %s" % [f, "; ".join(problems)])
			ZONES[id] = zd
	var ids: Array = ZONES.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(ZONES[a].get("order", 99)) < int(ZONES[b].get("order", 99)))
	for id: String in ids:
		OUTDOOR.append(id)
		ORDER.append(id)
	for h: String in HOUSES:
		ORDER.append(h)


## Reads one stage file into game values: [x, y] -> Vector2, [x, y, w, h] -> Rect2,
## "#rrggbb" -> Color, whole numbers -> int. Returns null if the file can't be parsed.
static func read_file(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Zones: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return from_json(json.data)


static func from_json(v: Variant) -> Variant:
	if v is float:
		return int(v) if v == floorf(v) and absf(v) < 1e9 else v
	if v is String:
		var str_v: String = v
		return Color.html(str_v) if str_v.begins_with("#") and Color.html_is_valid(str_v) else str_v
	if v is Array:
		var arr: Array = v
		if arr.size() == 2 and arr.all(func(x: Variant) -> bool: return x is float):
			return Vector2(arr[0], arr[1])
		if arr.size() == 4 and arr.all(func(x: Variant) -> bool: return x is float):
			return Rect2(arr[0], arr[1], arr[2], arr[3])
		var out: Array = []
		for item: Variant in arr:
			out.append(from_json(item))
		return out
	if v is Dictionary:
		var d: Dictionary = v
		var out_d: Dictionary = {}
		for k: Variant in d:
			out_d[k] = from_json(d[k])
		return out_d
	return v


## Turns game values back into the stage file form (the inverse of from_json), for tools.
static func to_json(v: Variant) -> Variant:
	if v is Vector2:
		return [v.x, v.y]
	if v is Rect2:
		return [v.position.x, v.position.y, v.size.x, v.size.y]
	if v is Color:
		return "#" + (v as Color).to_html(false)
	if v is Array:
		var out: Array = []
		for item: Variant in v:
			out.append(to_json(item))
		return out
	if v is Dictionary:
		var out_d: Dictionary = {}
		for k: Variant in v:
			out_d[k] = to_json(v[k])
		return out_d
	return v


## Checks a stage for the fields the game needs. Returns a list of problems (empty = fine).
static func validate(zd: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key: String in ["name", "size", "ground", "accent", "outdoor", "light", "tint", "climate", "spawn",
			"exits", "fires", "lamps", "walls", "plateaus", "lifts", "ice", "chests", "spawns", "night_spawns",
			"pickup", "pickups", "seed"]:
		if not zd.has(key):
			out.append("missing \"%s\"" % key)
	if out.is_empty():
		var size: Vector2 = zd["size"]
		if not (zd["spawn"] is Vector2) or not Rect2(Vector2.ZERO, size).has_point(zd["spawn"]):
			out.append("spawn is outside the zone")
		for ex: Dictionary in zd["exits"]:
			if not ex.has("rect") or not ex.has("to") or not ex.has("arrive"):
				out.append("an exit needs rect, to and arrive")
		for w: Variant in zd["walls"]:
			if not (w is Rect2):
				out.append("walls must be [x, y, w, h]")
		for pth: Dictionary in zd.get("paths", []):
			if (pth.get("points", []) as Array).size() < 2:
				out.append("a path needs at least 2 points")
		for sc: Dictionary in zd.get("scatter", []):
			if not sc.has("kind") or not sc.has("count"):
				out.append("a scatter rule needs kind and count")
	return out


static func zone(id: String) -> Dictionary:
	if ZONES.has(id):
		return ZONES[id]
	if HOUSES.has(id):
		if not _rooms.has(id):
			_rooms[id] = _interior(id)
		return _rooms[id]
	return ZONES["middlemost"]


static func exists(id: String) -> bool:
	return ZONES.has(id) or HOUSES.has(id)


static func is_interior(id: String) -> bool:
	return HOUSES.has(id)


## True where you'd need a light right now: outdoors at night, underground always,
## never inside a house (houses have their own lamps).
static func is_dark(id: String, clock: float) -> bool:
	if is_interior(id):
		return false
	if bool(zone(id)["outdoor"]):
		return is_night(clock)
	return true


## The outdoor zone a place is in, for the map: a house counts as the village it's in.
static func map_zone(id: String) -> String:
	return "middlemost" if is_interior(id) else id


## Where a player inside a house shows up on the map: at the house's front door.
static func map_pos(id: String, pos: Vector2) -> Vector2:
	return HOUSES[id]["door"] if is_interior(id) else pos


## Builds a house interior's zone data from its HOUSES entry.
static func _interior(id: String) -> Dictionary:
	var h: Dictionary = HOUSES[id]
	var size := ROOM_SIZE
	var mat := Rect2(size.x / 2.0 - 60.0, size.y - 40.0, 120.0, 40.0)
	var chests: Array = []
	if str(h["chest"]) != "":
		chests.append({"id": h["chest"], "pos": Vector2(size.x - 150.0, 170.0)})
	return {
		"name": h["name"], "size": size, "interior": true,
		"ground": Color("e9cfa6"), "accent": Color("d9b98a"), "wall_color": h["wall"],
		"outdoor": false, "light": 0.95, "tint": Color(1.0, 0.96, 0.9),
		"climate": {"indoors": 1},
		"spawn": Vector2(size.x / 2.0, size.y - 90.0),
		"exits": [{"rect": mat, "to": "middlemost", "arrive": (h["door"] as Vector2) + Vector2(0, 30), "label": "Outside"}],
		"fires": [Vector2(150, 120)], "lamps": [],
		# Furniture you can't walk through: fireplace, bed, table, shelf.
		# (Fireplace, bed, table and shelf first: the room drawing uses this order.)
		"walls": [Rect2(90, 0, 120, 140), Rect2(size.x - 260, 300, 200, 110), Rect2(330, 250, 220, 90),
			Rect2(size.x - 330, 0, 140, 90), Rect2(0, 0, size.x, 66)],
		"plateaus": [], "lifts": [], "ice": [], "chests": chests,
		"spawns": {}, "night_spawns": {}, "pickup": "", "pickups": 0, "seed": 101 + id.length(),
	}


static func size_of(id: String) -> Vector2:
	return zone(id)["size"]


static func is_night(clock: float) -> bool:
	return clock >= 19.0 * 60.0 or clock < 6.0 * 60.0


## Torches can be relit within FIRE_RANGE of these.
static func fire_sources(id: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var z := zone(id)
	for p: Vector2 in z["fires"]:
		out.append(p)
	for p: Vector2 in z["lamps"]:
		out.append(p + Vector2(0, -40))
	return out


static func lift_def(id: String, lift_id: String) -> Dictionary:
	for l: Dictionary in zone(id)["lifts"]:
		if l["id"] == lift_id:
			return l
	return {}


static func lift_rect(center: Vector2) -> Rect2:
	return Rect2(center - LIFT_SIZE / 2.0, LIFT_SIZE)


# ---------------------------------------------------------------- farm

static func plot_count(id: String) -> int:
	var z := zone(id)
	if not z.has("farm"):
		return 0
	var f: Dictionary = z["farm"]
	return int(f["cols"]) * int(f["rows"])


static func plot_center(id: String, i: int) -> Vector2:
	var f: Dictionary = zone(id)["farm"]
	var cols: int = f["cols"]
	var origin: Vector2 = f["origin"]
	@warning_ignore("integer_division")
	var row: int = i / cols
	var col: int = i % cols
	return origin + Vector2(col * (TILE.x + GAP), row * (TILE.y + GAP)) + TILE / 2.0


static func farm_rect(id: String) -> Rect2:
	var z := zone(id)
	if not z.has("farm"):
		return Rect2()
	var f: Dictionary = z["farm"]
	var cols: int = f["cols"]
	var rows: int = f["rows"]
	var origin: Vector2 = f["origin"]
	return Rect2(origin, Vector2(cols * TILE.x + (cols - 1) * GAP, rows * TILE.y + (rows - 1) * GAP))


## Nearest plot to a point within reach, or -1.
static func plot_at(id: String, point: Vector2, reach: float) -> int:
	var best := -1
	var best_d := reach
	for i in plot_count(id):
		var d := plot_center(id, i).distance_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best


# ---------------------------------------------------------------- collision

## Moves a circle out of cliffs, unmelted ice and the zone edge. `ice` is a list of
## Vector2 centres of ice blocks that are still frozen.
static func resolve(id: String, pos: Vector2, r: float, ice: Array) -> Vector2:
	var z := zone(id)
	var p := pos
	var size: Vector2 = z["size"]
	for w: Rect2 in z["walls"]:
		p = _out_of_rect(p, r, _past_edges(w, size))
	for c: Vector2 in ice:
		var d := p - c
		var min_d := r + ICE_RADIUS
		if d.length() < min_d:
			p = c + (d.normalized() if d.length() > 0.01 else Vector2.UP) * min_d
	return p.clamp(Vector2(r, r), size - Vector2(r, r))


static func blocked(id: String, pos: Vector2, r: float, ice: Array) -> bool:
	return resolve(id, pos, r, ice).distance_to(pos) > 0.5


## A cliff that runs into the edge of the zone is treated as running on past it, so
## someone shoved into its end can't be pushed out along the edge and round the cliff.
static func _past_edges(w: Rect2, size: Vector2) -> Rect2:
	var left := 400.0 if w.position.x <= 0.5 else 0.0
	var top := 400.0 if w.position.y <= 0.5 else 0.0
	var right := 400.0 if w.end.x >= size.x - 0.5 else 0.0
	var bottom := 400.0 if w.end.y >= size.y - 0.5 else 0.0
	return w.grow_individual(left, top, right, bottom)


static func _out_of_rect(p: Vector2, r: float, rect: Rect2) -> Vector2:
	var closest := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
	var d := p - closest
	if d.length() >= r:
		return p
	if d.length() > 0.001:
		return closest + d.normalized() * r
	var left := p.x - rect.position.x
	var right := rect.end.x - p.x
	var top := p.y - rect.position.y
	var bottom := rect.end.y - p.y
	var m := minf(minf(left, right), minf(top, bottom))
	if m == left:
		return Vector2(rect.position.x - r, p.y)
	if m == right:
		return Vector2(rect.end.x + r, p.y)
	if m == top:
		return Vector2(p.x, rect.position.y - r)
	return Vector2(p.x, rect.end.y + r)


## How far something of radius r can travel from `from` along `dir` before it hits a cliff,
## ice or the edge (used to plan a boar's charge).
static func travel(id: String, from: Vector2, dir: Vector2, max_len: float, r: float, ice: Array) -> float:
	var step := 8.0
	var d := 0.0
	while d + step <= max_len:
		if blocked(id, from + dir * (d + step), r, ice):
			return d
		d += step
	return max_len
