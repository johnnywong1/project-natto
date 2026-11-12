extends RefCounted
## Save slots. The host (or a solo player) keeps the world in one of SLOT_COUNT slots, as a
## JSON file under user://saves/ (on Windows: %APPDATA%/Godot/app_userdata/Project Natto/saves).
##
## What's saved:
##   * the world: day and time, weather, crops, pins, melted ice, where each lift is, which
##     house doors have been unlocked, and how long the world has been played;
##   * every player who has ever joined, by name: bag, item wheel, gear, hearts, shields,
##     torch and lantern, opened chests, Pepper's lessons, and where they were standing.
## Enemies and forage respawn fresh, so they aren't saved.
##
## The game saves on its own every AUTOSAVE_SECONDS, when someone leaves, when the host
## leaves or quits, and from the pause menu (Esc > Save).

const Z = preload("res://game/data/zones.gd")
const Items = preload("res://game/data/items.gd")
const Lessons = preload("res://game/data/lessons.gd")

const VERSION := 1
const SLOT_COUNT := 3
const DIR := "user://saves"
const AUTOSAVE_SECONDS := 120.0


static func path(slot: int) -> String:
	return "%s/slot_%d.json" % [DIR, slot]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


## A one-line summary of each slot for the title screen, or {} for an empty slot.
static func describe(slot: int) -> Dictionary:
	var data := read(slot)
	if data.is_empty():
		return {}
	var w: Dictionary = data["world"]
	return {"day": int(w["day"]), "clock": float(w["clock"]), "play_time": float(w.get("play_time", 0.0)),
		"players": (data["players"] as Dictionary).keys(), "saved_at": float(data.get("saved_at", 0.0)),
		"name": str(data.get("name", "Slot %d" % slot))}


static func read(slot: int) -> Dictionary:
	if not exists(slot):
		return {}
	var text := FileAccess.get_file_as_string(path(slot))
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("Save slot %d is damaged and was ignored." % slot)
		return {}
	var data: Variant = JSON.to_native(parsed)
	if not data is Dictionary or int((data as Dictionary).get("version", 0)) != VERSION:
		push_warning("Save slot %d is from a different version and was ignored." % slot)
		return {}
	return data


static func write(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	# Write to a temporary file first, so a crash mid-save can't wreck the old save.
	var tmp := path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Couldn't write save slot %d (error %d)." % [slot, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(JSON.from_native(data), "\t"))
	f.close()
	if exists(slot):
		DirAccess.remove_absolute(path(slot))
	return DirAccess.rename_absolute(tmp, path(slot)) == OK


static func delete(slot: int) -> void:
	if exists(slot):
		DirAccess.remove_absolute(path(slot))


# ---------------------------------------------------------------- world <-> save data

## Everything worth keeping, taken from the host's World. `keep` is the slot's previous
## player list, so people who aren't online right now keep their things.
static func capture(world: Node, keep: Dictionary, world_name: String) -> Dictionary:
	var players: Dictionary = keep.duplicate(true)
	for id: int in world.avatars:
		players[Net.player_name(id)] = player_record(world, id)
	var ice_melted := {}
	for zid: String in world.ice:
		var flags: Array = []
		for iid: int in _sorted_keys(world.ice[zid]):
			flags.append(bool(world.ice[zid][iid][1]))
		ice_melted[zid] = flags
	var pins: Array = []
	for pid: int in _sorted_keys(world.pins):
		var pin: Dictionary = world.pins[pid]
		pins.append({"zone": pin["zone"], "pos": pin["pos"], "name": pin["name"], "label": pin["label"], "color": pin["color"]})
	return {
		"version": VERSION, "name": world_name, "saved_at": Time.get_unix_time_from_system(),
		"world": {"clock": world.clock, "day": world.day, "weather": world.weather, "crops": world.crops,
			"pins": pins, "ice": ice_melted, "lifts": world.lifts, "unlocked": world.unlocked.keys(),
			"play_time": world.play_time},
		"players": players,
	}


static func player_record(world: Node, id: int) -> Dictionary:
	var a: Dictionary = world.avatars[id]
	return {"inv": a["inv"], "wheel": a["wheel"], "equip": a["equip"], "hp": a["hp"],
		"torch_lit": a["torch_lit"], "lantern_on": a["lantern_on"], "fuel": a["fuel"], "chests": a["chests"],
		"lesson": a["lesson"], "shields": a["shields"], "zone": a["zone"], "pos": a["pos"]}


## Puts a saved world back after World.host_init() made a fresh one.
static func restore_world(world: Node, data: Dictionary) -> void:
	var w: Dictionary = data["world"]
	world.clock = float(w["clock"])
	world.day = int(w["day"])
	world.play_time = float(w.get("play_time", 0.0))
	for zid: String in w["weather"]:
		if world.weather.has(zid):
			world.weather[zid] = str(w["weather"][zid])
	for zid: String in w["crops"]:
		if world.crops.has(zid) and (w["crops"][zid] as Array).size() == (world.crops[zid] as Array).size():
			world.crops[zid] = w["crops"][zid]
	for pin: Dictionary in w["pins"]:
		var p := pin.duplicate()
		p["owner"] = 0   # matched back to its owner by name when they join
		world.pins[world.new_id()] = p
	for zid: String in w["ice"]:
		if not world.ice.has(zid):
			continue
		var flags: Array = w["ice"][zid]
		var k := 0
		for iid: int in _sorted_keys(world.ice[zid]):
			if k < flags.size():
				world.ice[zid][iid][1] = bool(flags[k])
			k += 1
	for house: String in w.get("unlocked", []):
		world.unlocked[house] = true
	for zid: String in w["lifts"]:
		for lid: String in w["lifts"][zid]:
			if world.lift_state.has(zid) and world.lift_state[zid].has(lid):
				var at := str(w["lifts"][zid][lid])
				world.lifts[zid][lid] = at
				world.lift_state[zid][lid]["at"] = at
				world.lift_state[zid][lid]["to"] = at


## Gives a returning player their saved things (host_add_player calls this).
static func restore_player(a: Dictionary, rec: Dictionary) -> void:
	for key in ["inv", "wheel", "equip", "chests", "lesson", "shields"]:
		if rec.has(key):
			a[key] = rec[key]
	# A bag saved by an older layout keeps its items but gets the right number of slots.
	var inv: Array = a["inv"]
	while inv.size() < Items.SLOTS:
		inv.append([])
	if (a["wheel"] as Array).is_empty():
		a["wheel"] = Items.starter_wheel()
	for key in ["hp", "torch_lit", "lantern_on", "fuel"]:
		if rec.has(key):
			a[key] = rec[key]
	var zid := str(rec.get("zone", "middlemost"))
	if Z.exists(zid):
		a["zone"] = zid
		a["pos"] = Z.resolve(zid, rec.get("pos", Z.zone(zid)["spawn"]), 14.0, [])
	if not a["lesson"] is Dictionary or not (a["lesson"] as Dictionary).has("i"):
		a["lesson"] = Lessons.new_progress()


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys
