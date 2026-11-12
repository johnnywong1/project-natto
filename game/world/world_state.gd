extends Node
## The shared world (autoload "World"). The host (peer 1) owns it and simulates every zone,
## even ones nobody is standing in. Clients keep a mirror and send requests.
##
## What goes where:
##   * Detailed snapshots (players, enemies) at SNAPSHOT_HZ, only to peers in that zone.
##   * Map beacons (every player's zone + position) at BEACON_HZ, to everyone.
##   * Reliable events for things that must not be lost: crops, pins, weather, bags and
##     gear, vitals, pickups, ice, lifts, telegraphs, effects, zone changes.
## Each player simulates their own movement, and also decides whether an enemy attack
## hit them (they see the telegraph and know if they dodged or blocked). The host checks
## the claim against the attack it announced and applies the damage.
##
## The host also keeps, per player: bag, item wheel and gear (game/data/items.gd), hearts,
## shields (health, broken time), torch and lantern, Pepper's lessons (game/data/lessons.gd),
## and which chests they've opened. House doors and their locks are shared by everyone.
## Saving and loading is in game/save/save_game.gd.
##
## Requests from players start with c_ (c_use, c_interact...); updates to players start
## with _rpc_. Sections below: sending helpers, setup, simulation, saving, requests, updates.

signal zone_entered(zone: String, arrive: Vector2)
signal snapshot(zone: String, avatars: Array, enemies: Array)
signal beacons_changed
signal crop_changed(zone: String, index: int)
signal pins_changed
signal inventory_changed
signal selection_changed
signal vitals_changed
signal weather_changed(zone: String)
signal pickups_changed(zone: String)
signal ice_changed(zone: String)
signal lift_moved(zone: String, lift_id: String, from_end: String, to_end: String, seconds: float, riders: Array)
signal lift_arrived(zone: String, lift_id: String)
signal telegraph(zone: String, tg: Dictionary)
signal teleported(pos: Vector2)
signal fx(zone: String, kind: String, a: Vector2, b: Vector2, peer: int, item: String)
signal toast(text: String)
signal dialogue(speaker: String, lines: Array)

const Z = preload("res://game/data/zones.gd")
const Items = preload("res://game/data/items.gd")
const E = preload("res://game/data/enemies.gd")
const HB = preload("res://game/combat/hitboxes.gd")
const Lessons = preload("res://game/data/lessons.gd")
const SaveGame = preload("res://game/save/save_game.gd")

const SNAPSHOT_HZ := 20.0
const BEACON_HZ := 4.0
const CLOCK_SYNC_S := 2.0
const PING_S := 1.0
const MINUTES_PER_SECOND := 1.5   # one in-game day = 16 real minutes
const GROW_TIME := 4.0
const REACH := 62.0                # how far in front of you farming reaches
const THROW_FLIGHT := 0.45
const THROW_RANGE := 440.0
const PICKUP_RANGE := 64.0
const WELL_RANGE := 120.0
const PUDDLE_RANGE := 120.0
const CHEST_RANGE := 90.0
const PICKUP_RESPAWN := 45.0
const PINS_PER_PLAYER := 12
const BASE_HP := 10                # 5 hearts
const FAINT_TIME := 10.0
const REVIVE_RANGE := 85.0
const RAIN_SNUFF_TIME := 3.0       # seconds of rain before a torch goes out
const FUEL_SECONDS := 240.0        # a full lantern lasts 4 real minutes at normal speed
const LIFT_TIME := 2.2
const TALK_RANGE := 95.0
const DOOR_RANGE := 60.0
## How long an enemy reels after bumping into a raised shield (seconds).
const CONTACT_BLOCK_STUN := 0.6
const KICK_SLACK := 24.0           # the kicker saw the enemy a moment ago; it may have moved

# ---- Mirrored on every peer
var clock := 6.0 * 60.0          # minutes since midnight
var day := 1
var weather: Dictionary = {}     # zone -> weather id
var crops: Dictionary = {}       # zone -> Array of plots [crop_id, stage, grow_left]
var pins: Dictionary = {}        # pin id -> {"zone", "pos", "owner", "name", "label", "color"}
var beacons: Dictionary = {}     # peer -> [zone, pos]
var pickups: Dictionary = {}     # zone -> {pickup id: pos}
var ice: Dictionary = {}         # zone -> {ice id: [pos, melted]}
var lifts: Dictionary = {}       # zone -> {lift id: "bottom" | "top"}
var unlocked: Dictionary = {}    # house zone -> true, once someone has opened its lock
var inventory: Array = []        # this player's bag (sent by the host)
var wheel: Array = []            # this player's item wheel (sent by the host)
var equip: Dictionary = {}       # this player's gear
var vitals: Dictionary = {}      # this player's hp, max_hp, fainted, torch_lit, lantern_on, fuel, chests
var selected := 0                # which wheel segment this player is holding
var my_zone := "middlemost"
var arrive_pos := Vector2.ZERO
var time_scale := 1.0
var play_time := 0.0             # seconds this world has been played, over every session (saved)
var session_time := 0.0          # seconds since this player entered the world

## Host only: which save slot this world lives in (0 = not saved, e.g. test runs).
var save_slot := 0
var world_name := ""
var _saved_players: Dictionary = {}   # name -> saved record, for players not online right now
var _autosave_t := 0.0
## [unix time, zone, weather] for every weather change this peer has seen (for tests).
var weather_log: Array = []

# ---- Host only
var avatars: Dictionary = {}     # peer -> player record (see host_add_player)
var enemies: Dictionary = {}     # zone -> Array of enemy dictionaries
var shots: Array = []
var attacks: Dictionary = {}     # attack id -> {"zone", "enemy", "damage", "strike_ms", "end_ms", "hit"}
var lift_state: Dictionary = {}  # zone -> {lift id: {"at", "moving", "t", "to", "riders"}}
var test_mode := false
var ai_paused := false
var _next_id := 1
var _rng := RandomNumberGenerator.new()
var _snap_t := 0.0
var _beacon_t := 0.0
var _clock_t := 0.0
var _rain_t := 0.0
var _ping_t := 0.0
var _weather_t: Dictionary = {}
var _respawn: Array = []         # [zone, id, pos, seconds left]
var _weather_period := Vector2(90.0, 180.0)
var _forced: Dictionary = {}     # zone -> {"kind", "start", "end", "done"}
var _game_t := 0.0

## Numbers for the multiplayer test report.
var stats := {
	"snapshots_in": 0, "beacons_in": 0, "weather_events": 0, "crop_events": 0, "pin_events": 0,
	"fx_events": 0, "rtt_ms": [], "frames": 0, "frame_ms_total": 0.0, "frame_ms_max": 0.0,
	"zone_changes": 0, "bytes_sent": 0, "bytes_received": 0, "other_zone_snapshots": 0,
	"telegraphs_in": 0, "hits_taken": 0, "hits_blocked": 0, "lift_rides": 0, "enemy_kinds_seen": {},
}


func _ready() -> void:
	var o: Dictionary = Net.opts if Net != null else {}
	if o.has("time-scale"):
		time_scale = float(o["time-scale"])
	if o.has("weather-period"):
		var p := float(o["weather-period"])
		_weather_period = Vector2(p, p * 1.5)
	test_mode = o.has("test")
	if o.has("force-weather"):
		# zone:kind:start:duration, e.g. middlemost:rain:10:8
		var parts := str(o["force-weather"]).split(":")
		if parts.size() == 4:
			_forced[parts[0]] = {"kind": parts[1], "start": float(parts[2]), "end": float(parts[2]) + float(parts[3]), "done": false}


func is_host() -> bool:
	return Net.is_host()


func me() -> int:
	return multiplayer.get_unique_id()


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


func reset() -> void:
	clock = 360.0
	day = 1
	weather.clear()
	crops.clear()
	pins.clear()
	beacons.clear()
	pickups.clear()
	ice.clear()
	lifts.clear()
	unlocked.clear()
	weather_log.clear()
	inventory = []
	wheel = []
	equip = Items.empty_equip()
	vitals = {}
	selected = 0
	my_zone = "middlemost"
	avatars.clear()
	enemies.clear()
	shots.clear()
	attacks.clear()
	lift_state.clear()
	_respawn.clear()
	_game_t = 0.0
	play_time = 0.0
	session_time = 0.0
	_saved_players = {}
	_autosave_t = SaveGame.AUTOSAVE_SECONDS


## The item this player is holding (from their item wheel).
func held_item() -> String:
	return Items.item_at(wheel, selected)


## Picks a wheel segment to hold.
func select_slot(i: int) -> void:
	selected = clampi(i, 0, maxi(wheel.size() - 1, 0))
	selection_changed.emit()


## How many of an item this player has, bag and wheel together.
func count_mine(id: String) -> int:
	return Items.count_of(inventory, id) + Items.count_of(wheel, id)


func clock_text() -> String:
	var m := int(clock)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [m / 60, m % 60]


## Ice blocks in a zone that are still frozen (for collision).
func frozen_ice(zid: String) -> Array:
	var out: Array = []
	var d: Dictionary = ice.get(zid, {})
	for iid: int in d:
		if not bool(d[iid][1]):
			out.append(d[iid][0])
	return out


func puddles(zid: String) -> Array:
	var out: Array = []
	var d: Dictionary = ice.get(zid, {})
	for iid: int in d:
		if bool(d[iid][1]):
			out.append(d[iid][0])
	return out


## Which lights a player gives off: 1 torch, 2 lantern, 4 headlamp, 8 headlamp boost, 16 glow.
static func light_bits(gear: Dictionary, torch_lit: bool, lantern_on: bool, fuel: float) -> int:
	var bits := 0
	var off := str(gear.get("offhand", ""))
	if off == "torch" and torch_lit:
		bits |= 1
	if off == "lantern" and lantern_on and fuel > 0.0:
		bits |= 2
	if str(gear.get("helmet", "")) == "miner_helmet":
		bits |= 4
		if "miner" in Items.full_sets(gear):
			bits |= 8
	if "glow_pebble" in Items.equipped(gear):
		bits |= 16
	return bits


func my_lights() -> int:
	return light_bits(equip, bool(vitals.get("torch_lit", false)), bool(vitals.get("lantern_on", false)), float(vitals.get("fuel", 0.0)))


# ---------------------------------------------------------------- sending helpers

## Calls a request on the host (directly when we are the host).
func to_host(method: StringName, args: Array = []) -> void:
	if not Net.in_game:
		return
	if is_host():
		callv(method, args)
	else:
		var a: Array = [1, method]
		a.append_array(args)
		callv("rpc_id", a)


func _to_peer(id: int, method: StringName, args: Array) -> void:
	if id == multiplayer.get_unique_id():
		callv(method, args)
	else:
		var a: Array = [id, method]
		a.append_array(args)
		callv("rpc_id", a)


## Sends to every player in the game except the host (who has already applied the change).
## Never broadcasts to peers that haven't been let in yet, such as someone being turned away.
func _to_clients(method: StringName, args: Array) -> void:
	var me_id := multiplayer.get_unique_id()
	for id: int in avatars.keys():
		if id != me_id:
			var a: Array = [id, method]
			a.append_array(args)
			callv("rpc_id", a)


func _to_all(method: StringName, args: Array) -> void:
	for id: int in avatars.keys():
		_to_peer(id, method, args)


func _to_zone(zone: String, method: StringName, args: Array) -> void:
	for id: int in avatars.keys():
		if avatars[id]["zone"] == zone:
			_to_peer(id, method, args)


func _new_id() -> int:
	_next_id += 1
	return _next_id


# ---------------------------------------------------------------- host setup

func host_init(seed_value: int) -> void:
	reset()
	_rng.seed = seed_value
	for zid in Z.ORDER:
		var zd := Z.zone(zid)
		weather[zid] = _roll_weather(zid)
		_weather_t[zid] = _rng.randf_range(_weather_period.x, _weather_period.y)
		enemies[zid] = []
		if zd.has("farm"):
			var plots: Array = []
			for i in Z.plot_count(zid):
				plots.append(["", 0, 0.0])
			crops[zid] = plots
		var pk := {}
		var count: int = zd["pickups"]
		if count > 0:
			var r := RandomNumberGenerator.new()
			r.seed = int(zd["seed"]) * 7919
			var size: Vector2 = zd["size"]
			while pk.size() < count:
				var p := Vector2(r.randf_range(220.0, size.x - 220.0), r.randf_range(220.0, size.y - 220.0))
				if not Z.blocked(zid, p, 20.0, zd["ice"]) and not _on_plateau(zid, p):
					pk[_new_id()] = p
		pickups[zid] = pk
		var ic := {}
		for p: Vector2 in zd["ice"]:
			ic[_new_id()] = [p, false]
		ice[zid] = ic
		var ls := {}
		var lstate := {}
		for l: Dictionary in zd["lifts"]:
			ls[l["id"]] = "bottom"
			lstate[l["id"]] = {"at": "bottom", "moving": false, "t": 0.0, "to": "bottom", "riders": {}}
		lifts[zid] = ls
		lift_state[zid] = lstate


func _on_plateau(zid: String, p: Vector2) -> bool:
	for r: Rect2 in Z.zone(zid)["plateaus"]:
		if r.has_point(p):
			return true
	return false


func host_add_player(id: int) -> void:
	var spawn: Vector2 = Z.zone("middlemost")["spawn"]
	spawn += Vector2(_rng.randf_range(-80.0, 80.0), _rng.randf_range(-50.0, 50.0))
	var gear := Items.starter_equip()
	avatars[id] = {"zone": "middlemost", "pos": spawn, "facing": Vector2.DOWN, "slot": 0, "act": 0,
		"inv": Items.starter_kit(), "wheel": Items.starter_wheel(), "equip": gear, "hp": BASE_HP, "max_hp": BASE_HP, "fainted": false,
		"faint_t": 0.0, "torch_lit": true, "lantern_on": true, "fuel": Items.FUEL_MAX, "rain_t": 0.0,
		"chests": [], "touch_cd": 0.0, "kick_cd": 0.0, "dirty": true, "lesson": Lessons.new_progress(), "shields": {},
		"state_ms": Time.get_ticks_msec()}
	var who := Net.player_name(id)
	if _saved_players.has(who):
		SaveGame.restore_player(avatars[id], _saved_players[who])
		_recompute_max_hp(avatars[id])
		avatars[id]["hp"] = clampi(int(avatars[id]["hp"]), 1, int(avatars[id]["max_hp"]))
		Net.log_line("%s's things were loaded from the save" % who)
	for pid: int in pins:
		if int(pins[pid]["owner"]) == 0 and str(pins[pid]["name"]) == who:
			pins[pid]["owner"] = id   # their saved pins are theirs again
	beacons[id] = [avatars[id]["zone"], avatars[id]["pos"]]


func host_remove_player(id: int) -> void:
	if avatars.has(id):
		_saved_players[Net.player_name(id)] = SaveGame.player_record(self, id)
		if save_slot > 0:
			save_now()
	avatars.erase(id)
	beacons.erase(id)
	_send_beacons()


# ---------------------------------------------------------------- saving (host)

## Loads the world in `slot` (if there is one) on top of a fresh host_init() world, and
## remembers the slot so the game saves there. Returns true if a save was loaded.
func host_load(slot: int, host_name: String) -> bool:
	save_slot = slot
	world_name = "%s's world" % host_name
	if slot <= 0:
		return false
	var data := SaveGame.read(slot)
	if data.is_empty():
		return false
	SaveGame.restore_world(self, data)
	_saved_players = data["players"]
	world_name = str(data.get("name", world_name))
	Net.log_line("loaded save slot %d: day %d, %s" % [slot, day, clock_text()])
	return true


## Saves the world to its slot now. Returns true if it worked.
func save_now() -> bool:
	if not is_host() or save_slot <= 0 or not Net.in_game:
		return false
	var data := SaveGame.capture(self, _saved_players, world_name)
	_saved_players = data["players"]
	var ok := SaveGame.write(save_slot, data)
	Net.log_line("saved to slot %d: %s" % [save_slot, "ok" if ok else "FAILED"])
	return ok


## A fresh id for pins, enemies, attacks and so on (host only).
func new_id() -> int:
	return _new_id()


func _notification(what: int) -> void:
	# Closing the window saves first.
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_host() and Net.in_game and save_slot > 0:
		save_now()


## Something a player did that one of Pepper's lessons might be waiting for (see
## game/data/lessons.gd). Lessons only count once you've said hello to Pepper.
func lesson_event(id: int, what: String, amount: float = 1.0) -> void:
	if not is_host() or not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	var p: Dictionary = a["lesson"]
	if int(p["i"]) >= Lessons.count() or (int(p["i"]) == 0 and what != "talk"):
		return
	var counts: Dictionary = p["counts"]
	var before := floori(float(counts.get(what, 0.0)))
	counts[what] = float(counts.get(what, 0.0)) + amount
	if floori(float(counts[what])) != before or what in ["wheel", "equip", "chest"]:
		a["dirty"] = true   # the lesson card changed: send it
	_check_lesson(id)


## Finishes the player's lesson if every task is done: gives the reward and starts the
## next one (Pepper explains it in a speech bubble). Repeats, because a new lesson's
## tasks may already be done (say, you're already wearing the helmet).
func _check_lesson(id: int) -> void:
	var a: Dictionary = avatars[id]
	var p: Dictionary = a["lesson"]
	var finished := false
	while Lessons.is_done(p, a):
		var lesson: Dictionary = Lessons.LESSONS[int(p["i"])]
		var got: Array[String] = []
		for r: Array in lesson["reward"]:
			if Items.give(a["inv"], a["wheel"], str(r[0]), int(r[1])):
				got.append("%s x%d" % [Items.display_name(str(r[0])), int(r[1])])
		_toast_to(id, "Lesson done: %s!%s" % [str(lesson["title"]), (" Pepper gave you " + ", ".join(got) + ".") if not got.is_empty() else ""])
		p["i"] = int(p["i"]) + 1
		p["counts"] = {}
		finished = true
		Net.log_line("%s finished lesson %s" % [Net.player_name(id), str(lesson["id"])])
	if finished:
		a["dirty"] = true
		_send_inventory(id)
		var i: int = p["i"]
		if i < Lessons.count():
			var next: Dictionary = Lessons.LESSONS[i]
			_to_peer(id, &"_rpc_dialogue", [Lessons.NPC_NAME, ["Next lesson: %s." % str(next["title"])] + (next["talk"] as Array)])
		else:
			_to_peer(id, &"_rpc_dialogue", [Lessons.NPC_NAME, Lessons.DONE_TALK])


## A house door: in you go, unless it's locked and you haven't got the key. Using the key
## unlocks the door for good, for everyone.
func _use_door(id: int, house: String) -> void:
	var a: Dictionary = avatars[id]
	var h: Dictionary = Z.HOUSES[house]
	var key := str(h["lock"])
	if key != "" and not unlocked.has(house):
		if Items.locate(a["inv"], a["wheel"], key).is_empty():
			_toast_to(id, "%s is locked. You need a %s." % [str(h["name"]), Items.display_name(key)])
			_fx_zone(a["zone"], "locked", h["door"], h["door"], id, "")
			return
		unlocked[house] = true
		_to_clients(&"_rpc_unlocked", [house])
		broadcast_toast("%s unlocked %s with the %s." % [Net.player_name(id), str(h["name"]), Items.display_name(key)])
		Net.log_line("%s unlocked %s" % [Net.player_name(id), house])
	_move_to_zone(id, house, Z.zone(house)["spawn"])


## Puts a player in another zone (zone exits and doors).
func _move_to_zone(id: int, to_zone: String, at: Vector2) -> void:
	var a: Dictionary = avatars[id]
	var from: String = a["zone"]
	a["zone"] = to_zone
	a["pos"] = at
	beacons[id] = [to_zone, at]
	Net.log_line("%s travelled %s -> %s" % [Net.player_name(id), from, to_zone])
	_to_peer(id, &"_rpc_enter_zone", [to_zone, at])
	_send_beacons()


## Talking to Pepper: says hello the first time, then repeats the current lesson.
func _talk_to_pepper(id: int) -> void:
	var a: Dictionary = avatars[id]
	var p: Dictionary = a["lesson"]
	var i: int = p["i"]
	if i >= Lessons.count():
		_to_peer(id, &"_rpc_dialogue", [Lessons.NPC_NAME, Lessons.DONE_TALK])
		return
	if i > 0:
		_to_peer(id, &"_rpc_dialogue", [Lessons.NPC_NAME, Lessons.LESSONS[i]["talk"]])
		return
	# First hello: Pepper introduces herself; the next lesson's speech follows on.
	_to_peer(id, &"_rpc_dialogue", [Lessons.NPC_NAME, Lessons.LESSONS[0]["talk"]])
	lesson_event(id, "talk")


## Players who already know the game can skip the lessons (pause menu).
@rpc("any_peer", "call_remote", "reliable")
func c_skip_lessons() -> void:
	if not is_host():
		return
	var id := _sender()
	if avatars.has(id):
		avatars[id]["lesson"]["i"] = Lessons.count()
		avatars[id]["dirty"] = true
		_toast_to(id, "Lessons skipped. Pepper is still around if you want to chat.")


## Moves a player somewhere (waking up, test commands) and tells them.
func _teleport(id: int, pos: Vector2) -> void:
	var a: Dictionary = avatars[id]
	a["pos"] = pos
	a["tp"] = pos
	a["tp_t"] = 1.5
	beacons[id] = [a["zone"], pos]
	_to_peer(id, &"_rpc_teleport", [pos])


func _vitals_of(a: Dictionary) -> Dictionary:
	return {"hp": a["hp"], "max_hp": a["max_hp"], "fainted": a["fainted"], "faint_t": a["faint_t"],
		"torch_lit": a["torch_lit"], "lantern_on": a["lantern_on"], "fuel": snappedf(float(a["fuel"]), 0.1),
		"chests": a["chests"], "lesson": Lessons.summary(a["lesson"], a), "shield": _shield_summary(a)}


## The worn shield's health for the HUD: {"id", "hp", "max", "broken"} or {}.
func _shield_summary(a: Dictionary) -> Dictionary:
	var off := str(a["equip"]["offhand"])
	var st := _shield_state(a, off)
	if st.is_empty():
		return {}
	return {"id": off, "hp": snappedf(float(st["hp"]), 0.1), "max": float(Items.shield(off)["hp"]), "broken": snappedf(float(st["broken"]), 0.1)}


func full_state(for_id: int) -> Dictionary:
	var a: Dictionary = avatars[for_id]
	return {"clock": clock, "day": day, "weather": weather, "crops": crops, "pins": pins,
		"pickups": pickups, "beacons": beacons, "ice": ice, "lifts": lifts, "unlocked": unlocked, "inv": a["inv"], "wheel": a["wheel"], "equip": a["equip"],
		"vitals": _vitals_of(a), "zone": a["zone"], "pos": a["pos"], "time_scale": time_scale,
		"play_time": play_time}


func apply_full_state(s: Dictionary) -> void:
	clock = s["clock"]
	day = s["day"]
	weather = s["weather"]
	crops = s["crops"]
	pins = s["pins"]
	pickups = s["pickups"]
	beacons = s["beacons"]
	ice = s["ice"]
	lifts = s["lifts"]
	unlocked = s.get("unlocked", {})
	inventory = s["inv"]
	wheel = s["wheel"]
	equip = s["equip"]
	vitals = s["vitals"]
	my_zone = s["zone"]
	arrive_pos = s["pos"]
	time_scale = s["time_scale"]
	play_time = float(s.get("play_time", 0.0))
	session_time = 0.0
	selected = 0
	for zid: String in weather:
		weather_log.append([Time.get_unix_time_from_system(), zid, weather[zid]])


# ---------------------------------------------------------------- simulation

func _process(delta: float) -> void:
	if not Net.in_game:
		return
	_game_t += delta
	session_time += delta
	play_time += delta
	clock += delta * time_scale * MINUTES_PER_SECOND
	if clock >= 1440.0:
		clock -= 1440.0
		day += 1
	if not is_host():
		_ping_t -= delta
		if _ping_t <= 0.0:
			_ping_t = PING_S
			c_ping.rpc_id(1, Time.get_ticks_usec())
		return
	stats["frames"] = int(stats["frames"]) + 1
	stats["frame_ms_total"] = float(stats["frame_ms_total"]) + delta * 1000.0
	stats["frame_ms_max"] = maxf(float(stats["frame_ms_max"]), delta * 1000.0)
	_tick_weather(delta)
	_tick_crops(delta)
	_tick_players(delta)
	_tick_enemies(delta)
	_tick_shots(delta)
	_tick_lifts(delta)
	_tick_respawn(delta)
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t += 1.0 / SNAPSHOT_HZ
		_send_snapshots()
	_beacon_t -= delta
	if _beacon_t <= 0.0:
		_beacon_t += 1.0 / BEACON_HZ
		_send_beacons()
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = CLOCK_SYNC_S
		_to_clients(&"_rpc_clock", [clock, day, play_time])
	if save_slot > 0:
		_autosave_t -= delta
		if _autosave_t <= 0.0:
			_autosave_t = SaveGame.AUTOSAVE_SECONDS
			save_now()


func _roll_weather(zid: String) -> String:
	var climate: Dictionary = Z.zone(zid)["climate"]
	var total := 0
	for w: String in climate:
		total += int(climate[w])
	var r := _rng.randi_range(1, total)
	for w: String in climate:
		r -= int(climate[w])
		if r <= 0:
			return w
	return "clear"


func _tick_weather(delta: float) -> void:
	for zid in Z.ORDER:
		if Z.is_interior(zid):
			continue   # no weather indoors
		if _forced.has(zid):
			var f: Dictionary = _forced[zid]
			if _game_t >= float(f["start"]) and _game_t < float(f["end"]):
				if weather[zid] != f["kind"]:
					host_set_weather(zid, f["kind"])
				continue
			if _game_t >= float(f["end"]) and not bool(f["done"]):
				f["done"] = true
				host_set_weather(zid, "clear")
				_weather_t[zid] = _rng.randf_range(_weather_period.x, _weather_period.y)
				continue
		_weather_t[zid] = float(_weather_t[zid]) - delta
		if float(_weather_t[zid]) <= 0.0:
			_weather_t[zid] = _rng.randf_range(_weather_period.x, _weather_period.y)
			var w := _roll_weather(zid)
			var guard := 0
			while w == weather[zid] and guard < 6:
				w = _roll_weather(zid)
				guard += 1
			host_set_weather(zid, w)
	# Rain waters every thirsty plant in its zone.
	_rain_t -= delta
	if _rain_t <= 0.0:
		_rain_t = 1.5
		for zid: String in crops:
			if weather.get(zid, "") in Z.WET_WEATHER:
				var plots: Array = crops[zid]
				for i in plots.size():
					var p: Array = plots[i]
					if str(p[0]) != "" and int(p[1]) < _crop_max(str(p[0])) and float(p[2]) <= 0.0:
						p[2] = GROW_TIME
						_crop_broadcast(zid, i)


func host_set_weather(zid: String, w: String) -> void:
	weather[zid] = w
	weather_log.append([Time.get_unix_time_from_system(), zid, w])
	Net.log_line("weather in %s is now %s" % [zid, w])
	_to_clients(&"_rpc_weather", [zid, w])
	stats["weather_events"] = int(stats["weather_events"]) + 1
	weather_changed.emit(zid)


func _is_wet(zid: String) -> bool:
	return bool(Z.zone(zid)["outdoor"]) and weather.get(zid, "") in Z.WET_WEATHER


func _crop_max(crop: String) -> int:
	return int(Items.CROPS[crop]["stages"])


func _tick_crops(delta: float) -> void:
	for zid: String in crops:
		var plots: Array = crops[zid]
		for i in plots.size():
			var p: Array = plots[i]
			if float(p[2]) > 0.0:
				p[2] = float(p[2]) - delta
				if float(p[2]) <= 0.0:
					p[2] = 0.0
					p[1] = mini(int(p[1]) + 1, _crop_max(str(p[0])))
					_crop_broadcast(zid, i)


func _crop_broadcast(zid: String, i: int) -> void:
	var p: Array = crops[zid][i]
	_to_clients(&"_rpc_crop", [zid, i, p])
	crop_changed.emit(zid, i)


# ---------------------------------------------------------------- players: health, lights

func _tick_players(delta: float) -> void:
	for id: int in avatars:
		var a: Dictionary = avatars[id]
		a["touch_cd"] = maxf(float(a["touch_cd"]) - delta, 0.0)
		a["tp_t"] = maxf(float(a.get("tp_t", 0.0)) - delta, 0.0)
		_tick_shields(a, delta)
		a["kick_cd"] = maxf(float(a["kick_cd"]) - delta, 0.0)
		if bool(a["fainted"]):
			a["faint_t"] = float(a["faint_t"]) - delta
			if float(a["faint_t"]) <= 0.0:
				var zid: String = a["zone"]
				a["fainted"] = false
				a["hp"] = maxi(int(float(a["max_hp"]) * 0.5), 1)
				_teleport(id, Z.zone(zid)["spawn"])
				_toast_to(id, "You woke up at the entrance, a bit dizzy.")
				a["dirty"] = true
		var gear: Dictionary = a["equip"]
		var off := str(gear["offhand"])
		# Rain puts torches out unless you're wearing a raincoat.
		if off == "torch" and bool(a["torch_lit"]) and _is_wet(a["zone"]) and not Items.has_flag(gear, "rainproof"):
			a["rain_t"] = float(a["rain_t"]) + delta
			if float(a["rain_t"]) >= RAIN_SNUFF_TIME:
				a["torch_lit"] = false
				a["rain_t"] = 0.0
				_fx_zone(a["zone"], "snuff", a["pos"], a["pos"], id, "torch")
				_toast_to(id, "The rain put your torch out! Relight it at a fire.")
				Net.log_line("%s's torch went out in the rain" % Net.player_name(id))
				a["dirty"] = true
		else:
			a["rain_t"] = 0.0
		# Lanterns burn oil, and refill themselves from the bag when they run dry.
		if off == "lantern" and bool(a["lantern_on"]) and float(a["fuel"]) > 0.0:
			var before := float(a["fuel"])
			a["fuel"] = before - delta * time_scale * Items.FUEL_MAX / FUEL_SECONDS
			if float(a["fuel"]) <= 0.0:
				a["fuel"] = 0.0
				if _use_one(id, "oil"):
					a["fuel"] = Items.FUEL_MAX
					_send_inventory(id)
					_toast_to(id, "Lantern refilled with lamp oil (%d left)." % (Items.count_of(a["inv"], "oil") + Items.count_of(a["wheel"], "oil")))
				else:
					_toast_to(id, "Your lantern ran out of oil.")
				a["dirty"] = true
			elif int(before / 5.0) != int(float(a["fuel"]) / 5.0):
				a["dirty"] = true   # tell the owner every 5% so the HUD gauge moves
		if bool(a["dirty"]):
			a["dirty"] = false
			_to_peer(id, &"_rpc_vitals", [_vitals_of(a)])


func _damage_player(id: int, dmg: int, from: Vector2) -> void:
	var a: Dictionary = avatars[id]
	if bool(a["fainted"]) or dmg <= 0:
		return
	a["hp"] = maxi(int(a["hp"]) - dmg, 0)
	_fx_zone(a["zone"], "hurt", a["pos"], from, id, "")
	if int(a["hp"]) <= 0:
		a["fainted"] = true
		a["faint_t"] = FAINT_TIME
		_toast_to(id, "You fainted! A friend can revive you (E), or you'll wake at the entrance.")
		Net.log_line("%s fainted" % Net.player_name(id))
		for other: int in avatars:
			if other != id and avatars[other]["zone"] == a["zone"]:
				_toast_to(other, "%s fainted! Stand next to them and press E to revive." % Net.player_name(id))
	a["dirty"] = true


func _near_fire(zid: String, pos: Vector2) -> bool:
	for f: Vector2 in Z.fire_sources(zid):
		if f.distance_to(pos) < Z.FIRE_RANGE:
			return true
	for en: Dictionary in enemies.get(zid, []):
		if float(en["burn"]) > 0.0 and (en["pos"] as Vector2).distance_to(pos) < 90.0:
			return true
	return false


func _recompute_max_hp(a: Dictionary) -> void:
	a["max_hp"] = BASE_HP + Items.total(a["equip"], "max_hp")
	a["hp"] = mini(int(a["hp"]), int(a["max_hp"]))
	a["dirty"] = true


# ---------------------------------------------------------------- enemies

func _tick_enemies(delta: float) -> void:
	var night := Z.is_night(clock)
	for zid in Z.ORDER:
		if not _zone_has_players(zid):
			continue
		var list: Array = enemies[zid]
		var zd := Z.zone(zid)
		if not ai_paused:
			var caps: Dictionary = zd["spawns"].duplicate()
			if night and bool(zd["outdoor"]):
				for k: String in zd["night_spawns"]:
					caps[k] = int(caps.get(k, 0)) + int(zd["night_spawns"][k])
			for kind: String in caps:
				var have := 0
				for en: Dictionary in list:
					if en["kind"] == kind:
						have += 1
				if have < int(caps[kind]) and _rng.randf() < delta * 0.25:
					list.append(_spawn_enemy(zid, kind, Vector2.INF))
		var frozen := frozen_ice(zid)
		for en: Dictionary in list:
			_tick_enemy(zid, en, delta, frozen)
		enemies[zid] = list.filter(func(en: Dictionary) -> bool: return float(en["pop"]) > 0.0 or int(en["hp"]) > 0)
	var now := Time.get_ticks_msec()
	for atk: int in attacks.keys():
		if now > int(attacks[atk]["end_ms"]) + 3000:
			attacks.erase(atk)


func _spawn_enemy(zid: String, kind: String, at: Vector2) -> Dictionary:
	var info := E.info(kind)
	var size := Z.size_of(zid)
	var r: float = info["radius"]
	var pos := at
	if pos == Vector2.INF:
		for attempt in 16:
			if kind == "puffcap":
				pos = Vector2(_rng.randf_range(200, size.x - 200), _rng.randf_range(200, size.y - 200))
			else:
				var edge := _rng.randi_range(0, 3)
				match edge:
					0: pos = Vector2(_rng.randf_range(100, size.x - 100), 100)
					1: pos = Vector2(_rng.randf_range(100, size.x - 100), size.y - 100)
					2: pos = Vector2(100, _rng.randf_range(100, size.y - 100))
					_: pos = Vector2(size.x - 100, _rng.randf_range(100, size.y - 100))
			var ok := not Z.blocked(zid, pos, r, frozen_ice(zid))
			for ex: Dictionary in Z.zone(zid)["exits"]:
				if (ex["rect"] as Rect2).grow(260.0).has_point(pos):
					ok = false
			for id: int in avatars:
				if avatars[id]["zone"] == zid and (avatars[id]["pos"] as Vector2).distance_to(pos) < 360.0:
					ok = false
			if ok:
				break
	return {"id": _new_id(), "kind": kind, "pos": pos, "hp": int(info["hp"]), "max": int(info["hp"]),
		"state": "move", "st": 0.0, "dir": Vector2.RIGHT, "plot": -1, "eat": 0.0, "kb": Vector2.ZERO,
		"pop": 0.0, "burn": 0.0, "burn_tick": 0.0, "frozen": bool(info.get("frozen", false)),
		"wander": pos, "wt": 0.0, "cd": _rng.randf_range(1.0, 2.0), "atk": 0, "travel": 0.0, "moved": 0.0}


func _tick_enemy(zid: String, en: Dictionary, delta: float, frozen: Array) -> void:
	if float(en["pop"]) > 0.0:
		en["pop"] = float(en["pop"]) - delta
		return
	var info := E.info(en["kind"])
	var pos: Vector2 = en["pos"]
	var r: float = info["radius"]
	# Fire: burns for a few seconds, rain puts it out.
	if float(en["burn"]) > 0.0:
		if _is_wet(zid):
			en["burn"] = 0.0
			_fx_zone(zid, "snuff", pos, pos, 0, "")
		else:
			en["burn"] = float(en["burn"]) - delta
			en["burn_tick"] = float(en["burn_tick"]) + delta
			if float(en["burn_tick"]) >= 1.0:
				en["burn_tick"] = float(en["burn_tick"]) - 1.0
				_hurt_enemy(zid, en, int(E.BURN_DPS), pos, 0, false, true)
				if float(en["pop"]) > 0.0:
					return
	var kb: Vector2 = en["kb"]
	pos += kb * delta
	en["kb"] = kb.move_toward(Vector2.ZERO, 700.0 * delta)
	match str(en["state"]):
		"stunned":
			en["st"] = float(en["st"]) - delta
			if float(en["st"]) <= 0.0:
				en["state"] = "move"
		"windup":
			en["st"] = float(en["st"]) - delta
			if float(en["st"]) <= 0.0:
				_strike(zid, en)
		"attack":
			var step := float(info["attack_speed"]) * delta
			var left := float(en["travel"]) - float(en["moved"])
			var d := minf(step, left)
			pos += (en["dir"] as Vector2) * d
			en["moved"] = float(en["moved"]) + d
			if float(en["moved"]) >= float(en["travel"]) - 0.01:
				if float(en["travel"]) < float(info["length"]) - 1.0:
					en["state"] = "stunned"
					en["st"] = E.WALL_STUN
					_fx_zone(zid, "daze", pos, pos, 0, "")
				else:
					en["state"] = "recover"
					en["st"] = float(info["recover"])
		"recover":
			en["st"] = float(en["st"]) - delta
			if float(en["st"]) <= 0.0:
				en["state"] = "move"
				en["cd"] = float(info.get("cooldown", 2.0))
		_:
			if not ai_paused:
				pos = _enemy_move(zid, en, info, pos, delta)
	en["pos"] = Z.resolve(zid, pos, r, frozen)


func _nearest_player(zid: String, pos: Vector2, within: float) -> int:
	var best := -1
	var bd := within
	for id: int in avatars:
		var a: Dictionary = avatars[id]
		if a["zone"] == zid and not bool(a["fainted"]):
			var d := (a["pos"] as Vector2).distance_to(pos)
			if d < bd:
				bd = d
				best = id
	return best


func _enemy_move(zid: String, en: Dictionary, info: Dictionary, pos: Vector2, delta: float) -> Vector2:
	en["cd"] = float(en["cd"]) - delta
	var speed: float = info["speed"]
	var goal := Vector2.INF
	var target := _nearest_player(zid, pos, float(info["aggro"]))
	if float(en["burn"]) > 0.0 and target >= 0:
		# On fire: run away from people.
		var away := pos - (avatars[target]["pos"] as Vector2)
		goal = pos + away.normalized() * 200.0
		speed *= 1.6
	elif bool(info.get("crops", false)) and crops.has(zid):
		var plots: Array = crops[zid]
		var t := int(en["plot"])
		if t >= 0 and str(plots[t][0]) == "":
			t = -1
		if t < 0:
			var best := INF
			for i in plots.size():
				if str(plots[i][0]) != "":
					var d := Z.plot_center(zid, i).distance_to(pos)
					if d < best:
						best = d
						t = i
		en["plot"] = t
		if t >= 0:
			goal = Z.plot_center(zid, t)
			if goal.distance_to(pos) < 12.0:
				en["eat"] = float(en["eat"]) + delta
				if float(en["eat"]) >= 3.0:
					plots[t] = ["", 0, 0.0]
					_crop_broadcast(zid, t)
					_fx_zone(zid, "nibble", pos, pos, 0, "")
					en["eat"] = 0.0
					en["plot"] = -1
				return pos
	en["eat"] = 0.0
	if goal == Vector2.INF and target >= 0:
		var tp: Vector2 = avatars[target]["pos"]
		var attack: String = info["attack"]
		if attack != "" and float(en["cd"]) <= 0.0 and tp.distance_to(pos) <= float(info["range"]):
			_begin_windup(zid, en, info, tp)
			return pos
		goal = tp
		if attack != "" and tp.distance_to(pos) < float(info["range"]) * 0.6:
			return pos   # close enough; wait for the cooldown
	if goal == Vector2.INF:
		en["wt"] = float(en["wt"]) - delta
		if float(en["wt"]) <= 0.0 or pos.distance_to(en["wander"]) < 10.0:
			en["wt"] = _rng.randf_range(2.0, 4.0)
			en["wander"] = pos + Vector2(_rng.randf_range(-260, 260), _rng.randf_range(-200, 200))
		goal = en["wander"]
		speed *= 0.6
	var to := goal - pos
	if to.length() > 1.0:
		en["dir"] = to.normalized()
		pos += to.normalized() * minf(speed * delta, to.length())
	return pos


func _begin_windup(zid: String, en: Dictionary, info: Dictionary, target: Vector2) -> void:
	var pos: Vector2 = en["pos"]
	var dir := (target - pos).normalized() if target.distance_to(pos) > 1.0 else Vector2.RIGHT
	var windup: float = info["windup"]
	var atk := _new_id()
	en["dir"] = dir
	en["state"] = "windup"
	en["st"] = windup
	en["atk"] = atk
	var tg := {"id": atk, "enemy": en["id"], "kind": info["attack"], "origin": pos, "dir": dir, "windup": windup}
	var active := 0.3
	match str(info["attack"]):
		"charge":
			var t := Z.travel(zid, pos, dir, float(info["length"]), float(info["radius"]), frozen_ice(zid))
			en["travel"] = t
			en["moved"] = 0.0
			tg["length"] = t
			tg["width"] = float(info["radius"]) * 2.0   # the lane the boar's body sweeps
			tg["speed"] = info["attack_speed"]
			tg["radius"] = info["radius"]
			active = t / float(info["attack_speed"]) + 0.15
		"burst":
			tg["radius"] = info["area"]
		"slam":
			tg["length"] = info["length"]
			tg["half"] = info["half_angle"]
	var now := Time.get_ticks_msec()
	attacks[atk] = {"zone": zid, "enemy": en["id"], "damage": int(info["damage"]),
		"strike_ms": now + int(windup * 1000.0), "end_ms": now + int((windup + active) * 1000.0), "hit": {}}
	_to_zone(zid, &"_rpc_telegraph", [zid, tg])


func _strike(zid: String, en: Dictionary) -> void:
	var info := E.info(en["kind"])
	var pos: Vector2 = en["pos"]
	match str(info["attack"]):
		"charge":
			en["state"] = "attack"
			en["moved"] = 0.0
			_fx_zone(zid, "charge", pos, pos + (en["dir"] as Vector2) * float(en["travel"]), 0, "")
		"burst":
			en["state"] = "recover"
			en["st"] = float(info["recover"])
			_fx_zone(zid, "burst", pos, pos, 0, "")
		"slam":
			en["state"] = "recover"
			en["st"] = float(info["recover"])
			_fx_zone(zid, "slam", pos, pos + (en["dir"] as Vector2) * float(info["length"]), 0, "")


func _find_enemy(zid: String, enemy_id: int) -> Dictionary:
	for en: Dictionary in enemies.get(zid, []):
		if int(en["id"]) == enemy_id:
			return en
	return {}


## Damages an enemy. by = the player who did it (0 = fire).
func _hurt_enemy(zid: String, en: Dictionary, dmg: int, from: Vector2, by: int, ignite: bool, fire: bool = false) -> void:
	if float(en["pop"]) > 0.0:
		return
	var info := E.info(en["kind"])
	if bool(en["frozen"]) and not fire:
		_fx_zone(zid, "clink", en["pos"], en["pos"], by, "")
		_toast_to(by, "The %s is frozen solid. Melt it with a torch!" % str(info["name"]))
		return
	var mult := 2 if en["state"] == "stunned" else 1
	en["hp"] = int(en["hp"]) - dmg * mult
	var pos: Vector2 = en["pos"]
	if not fire:
		en["kb"] = (pos - from).normalized() * 320.0 / float(info["scale"])
	if ignite:
		en["burn"] = E.BURN_TIME
	if int(en["hp"]) <= 0:
		en["pop"] = 0.35
		_fx_zone(zid, "pop", pos, pos, by, en["kind"])
		_toast_to(by, "Defeated a %s!" % str(info["name"]))
		lesson_event(by, "defeat")


func _tick_shots(delta: float) -> void:
	for s: Dictionary in shots:
		s["t"] = float(s["t"]) + delta
		if float(s["t"]) >= THROW_FLIGHT and not bool(s["done"]):
			s["done"] = true
			var at: Vector2 = s["to"]
			var zid: String = s["zone"]
			_fx_zone(zid, "splat", at, at, int(s["owner"]), str(s["item"]))
			var burst := HB.splash(at)
			for en: Dictionary in enemies[zid]:
				if int(en["hp"]) > 0 and HB.hits(burst, HB.enemy_hurtbox(en["kind"], en["pos"])):
					_hurt_enemy(zid, en, int(s["dmg"]), at, int(s["owner"]), false)
	shots = shots.filter(func(s: Dictionary) -> bool: return not bool(s["done"]))


func _tick_respawn(delta: float) -> void:
	for r: Array in _respawn:
		r[3] = float(r[3]) - delta
		if float(r[3]) <= 0.0:
			var zid: String = r[0]
			var pid: int = r[1]
			pickups[zid][pid] = r[2]
			_to_clients(&"_rpc_pickup", [zid, pid, r[2], true])
			pickups_changed.emit(zid)
	_respawn = _respawn.filter(func(r: Array) -> bool: return float(r[3]) > 0.0)


# ---------------------------------------------------------------- lifts

func _tick_lifts(delta: float) -> void:
	for zid: String in lift_state:
		for lid: String in lift_state[zid]:
			var ls: Dictionary = lift_state[zid][lid]
			if not bool(ls["moving"]):
				continue
			ls["t"] = float(ls["t"]) - delta
			if float(ls["t"]) <= 0.0:
				ls["moving"] = false
				ls["at"] = ls["to"]
				lifts[zid][lid] = ls["at"]
				var def := Z.lift_def(zid, lid)
				var dest: Vector2 = def[ls["at"]]
				var riders: Dictionary = ls["riders"]
				for id: int in riders:
					if avatars.has(id) and avatars[id]["zone"] == zid:
						avatars[id]["pos"] = Z.resolve(zid, dest + (riders[id] as Vector2), 14.0, frozen_ice(zid))
				ls["riders"] = {}
				_to_clients(&"_rpc_lift_state", [zid, lid, ls["at"]])
				lift_arrived.emit(zid, lid)


func _start_lift(zid: String, lid: String, by: int) -> void:
	var ls: Dictionary = lift_state[zid][lid]
	var def := Z.lift_def(zid, lid)
	var from_end: String = ls["at"]
	var to_end := "top" if from_end == "bottom" else "bottom"
	var center: Vector2 = def[from_end]
	var riders := {}
	for id: int in avatars:
		var a: Dictionary = avatars[id]
		if a["zone"] == zid and not bool(a["fainted"]) and Z.lift_rect(center).grow(12.0).has_point(a["pos"]):
			riders[id] = (a["pos"] as Vector2) - center
	ls["moving"] = true
	ls["t"] = LIFT_TIME
	ls["to"] = to_end
	ls["riders"] = riders
	Net.log_line("%s works the %s: %s -> %s with %d aboard" % [Net.player_name(by), lid, from_end, to_end, riders.size()])
	for rider: int in riders:
		lesson_event(rider, "lift")
	_to_zone(zid, &"_rpc_lift", [zid, lid, from_end, to_end, LIFT_TIME, riders.keys()])


# ---------------------------------------------------------------- snapshots

func _zone_has_players(zid: String) -> bool:
	for id: int in avatars:
		if avatars[id]["zone"] == zid:
			return true
	return false


func _send_snapshots() -> void:
	for zid in Z.ORDER:
		if not _zone_has_players(zid):
			continue
		var av: Array = []
		for id: int in avatars:
			var a: Dictionary = avatars[id]
			if a["zone"] == zid:
				var gear: Dictionary = a["equip"]
				var flags := int(a["act"]) & 7
				if bool(a["fainted"]):
					flags |= 8
				av.append([id, a["pos"], a["facing"], Items.item_at(a["wheel"], int(a["slot"])), flags,
					[gear["helmet"], gear["chest"], gear["shoes"], gear["offhand"]],
					light_bits(gear, bool(a["torch_lit"]), bool(a["lantern_on"]), float(a["fuel"])),
					float(a["hp"]) / maxf(float(a["max_hp"]), 1.0)])
		var el: Array = []
		for en: Dictionary in enemies[zid]:
			el.append([en["id"], en["kind"], en["pos"], float(en["hp"]) / maxf(float(en["max"]), 1.0),
				int(E.STATE_CODES.get(en["state"], 0)), en["dir"], float(en["burn"]) > 0.0, bool(en["frozen"]),
				float(en["pop"]) > 0.0, float(en["eat"]) > 0.0])
		_to_zone(zid, &"_rpc_snapshot", [zid, av, el])


func _send_beacons() -> void:
	for id: int in avatars:
		beacons[id] = [avatars[id]["zone"], avatars[id]["pos"]]
	_to_clients(&"_rpc_beacons", [beacons])
	beacons_changed.emit()


func _fx_zone(zid: String, kind: String, a: Vector2, b: Vector2, peer: int, item: String) -> void:
	_to_zone(zid, &"_rpc_fx", [zid, kind, a, b, peer, item])


func _toast_to(id: int, text: String) -> void:
	if avatars.has(id):
		_to_peer(id, &"_rpc_toast", [text])


func broadcast_toast(text: String) -> void:
	_to_all(&"_rpc_toast", [text])


func _send_inventory(id: int) -> void:
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	a["slot"] = clampi(int(a["slot"]), 0, maxi((a["wheel"] as Array).size() - 1, 0))
	_to_peer(id, &"_rpc_inventory", [a["inv"], a["wheel"], a["equip"]])


# ---------------------------------------------------------------- client -> host requests

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_state(zone: String, pos: Vector2, facing: Vector2, slot: int, act: int) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	if zone != a["zone"]:
		return  # sent before a zone change landed; a fresh one is on its way
	# A fainted player can't walk, but still finishes the knockback from the blow that
	# floored them, so small moves are taken.
	if not bool(a["fainted"]) or pos.distance_to(a["pos"]) < 80.0:
		_accept_pos(a, pos, facing)
	a["slot"] = clampi(slot, 0, maxi((a["wheel"] as Array).size() - 1, 0))
	var now := Time.get_ticks_msec()
	if act & 1 != 0 and int(a["act"]) & 1 == 0:
		lesson_event(id, "dash")
	if act & 4 != 0:
		lesson_event(id, "sprint", minf((now - int(a["state_ms"])) / 1000.0, 0.2))
	a["state_ms"] = now
	a["act"] = act


## Players simulate their own movement; the host keeps their reported position inside
## the zone they are actually in.
func _accept_pos(a: Dictionary, pos: Vector2, facing: Vector2) -> void:
	if float(a.get("tp_t", 0.0)) > 0.0:
		# Just moved by the host: updates sent before the player heard about it are stale.
		if pos.distance_to(a["tp"]) > 60.0:
			return
		a["tp_t"] = 0.0
	a["pos"] = pos.clamp(Vector2.ZERO, Z.size_of(a["zone"]))
	a["facing"] = facing.normalized() if facing.length() > 0.01 else Vector2.DOWN


@rpc("any_peer", "call_remote", "reliable")
func c_travel(to_zone: String, pos: Vector2) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	if bool(a["fainted"]):
		return
	_accept_pos(a, pos, a["facing"])
	var from: String = a["zone"]
	for ex: Dictionary in Z.zone(from)["exits"]:
		var rect: Rect2 = ex["rect"]
		if ex["to"] == to_zone and rect.grow(140.0).has_point(a["pos"]):
			_move_to_zone(id, to_zone, ex["arrive"])
			return


@rpc("any_peer", "call_remote", "reliable")
func c_use(slot: int, aim: Vector2, pos_now: Vector2, facing_now: Vector2) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	if bool(a["fainted"]):
		return
	_accept_pos(a, pos_now, facing_now)
	var wh: Array = a["wheel"]
	var item := Items.item_at(wh, slot)
	if item == "":
		return
	a["slot"] = slot
	var zid: String = a["zone"]
	var pos: Vector2 = a["pos"]
	var facing: Vector2 = a["facing"]
	var front := pos + facing * 30.0
	match str(Items.ITEMS[item]["kind"]):
		"sickle":
			_fx_zone(zid, "swing", pos, pos + facing * 40.0, id, item)
			var ignite: bool = Items.has_flag(a["equip"], "ignite") and a["equip"]["offhand"] == "torch" and bool(a["torch_lit"])
			var swing := HB.sickle(pos, facing)
			for en: Dictionary in enemies[zid]:
				if int(en["hp"]) > 0 and HB.hits(swing, HB.enemy_hurtbox(en["kind"], en["pos"])):
					_hurt_enemy(zid, en, 1, pos, id, ignite)
			_try_harvest(id, zid, front)
		"can":
			if _near_water(zid, pos):
				_refill(id)
				return
			if Items.count_at(wh, slot) <= 0:
				_toast_to(id, "The can is empty. Refill it at the well or a puddle.")
				return
			var i := Z.plot_at(zid, front, REACH) if crops.has(zid) else -1
			if i < 0:
				_toast_to(id, "Face a planted plot to water it.")
				return
			var p: Array = crops[zid][i]
			if str(p[0]) == "" or int(p[1]) >= _crop_max(str(p[0])) or float(p[2]) > 0.0:
				_toast_to(id, "That plot doesn't need water right now.")
				return
			p[2] = GROW_TIME
			wh[slot][1] = int(wh[slot][1]) - 1
			lesson_event(id, "water")
			_crop_broadcast(zid, i)
			_send_inventory(id)
			_fx_zone(zid, "water", Z.plot_center(zid, i), Z.plot_center(zid, i), id, item)
		"seed":
			var i := Z.plot_at(zid, front, REACH) if crops.has(zid) else -1
			if i < 0:
				_toast_to(id, "Seeds go in the farm plots in Middlemost.")
				return
			var p: Array = crops[zid][i]
			if str(p[0]) != "":
				_toast_to(id, "Something is already growing there.")
				return
			crops[zid][i] = [str(Items.ITEMS[item]["crop"]), 1, 0.0]
			Items.wheel_take_one(wh, slot)
			lesson_event(id, "plant")
			_crop_broadcast(zid, i)
			_send_inventory(id)
			_fx_zone(zid, "plant", Z.plot_center(zid, i), Z.plot_center(zid, i), id, item)
		"throw":
			var target := aim
			if pos.distance_to(target) > THROW_RANGE:
				target = pos + (target - pos).normalized() * THROW_RANGE
			Items.wheel_take_one(wh, slot)
			shots.append({"zone": zid, "from": pos, "to": target, "t": 0.0, "dmg": int(Items.ITEMS[item]["damage"]),
				"owner": id, "item": item, "done": false})
			_send_inventory(id)
			_fx_zone(zid, "throw", pos, target, id, item)
		"oil":
			if a["equip"]["offhand"] != "lantern":
				_toast_to(id, "Lamp oil is for a lantern. Equip one in your offhand (I).")
			elif float(a["fuel"]) >= Items.FUEL_MAX - 1.0:
				_toast_to(id, "Your lantern is already full.")
			else:
				Items.wheel_take_one(wh, slot)
				a["fuel"] = Items.FUEL_MAX
				a["lantern_on"] = true
				a["dirty"] = true
				_send_inventory(id)
				_toast_to(id, "Lantern filled.")
		_:
			pass


## The offhand action (right-click): jab with a torch, switch a lantern on or off.
## Blocking with a Pot Lid happens on the player's own machine; nothing to send.
@rpc("any_peer", "call_remote", "reliable")
func c_offhand(pos_now: Vector2, facing_now: Vector2) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	if bool(a["fainted"]):
		return
	_accept_pos(a, pos_now, facing_now)
	var zid: String = a["zone"]
	var pos: Vector2 = a["pos"]
	var facing: Vector2 = a["facing"]
	match str(a["equip"]["offhand"]):
		"torch":
			if not bool(a["torch_lit"]):
				if _near_fire(zid, pos):
					_relight(id)
				else:
					_toast_to(id, "Your torch is out. Relight it at a campfire, brazier or lamp.")
				return
			_fx_zone(zid, "jab", pos, pos + facing * 40.0, id, "torch")
			lesson_event(id, "jab")
			var poke := HB.jab(pos, facing)
			for en: Dictionary in enemies[zid]:
				if int(en["hp"]) > 0 and float(en["pop"]) <= 0.0 and HB.hits(poke, HB.enemy_hurtbox(en["kind"], en["pos"])):
					if bool(en["frozen"]):
						en["frozen"] = false
						_fx_zone(zid, "melt", en["pos"], en["pos"], id, "")
						_toast_to(id, "Melted the ice off the %s!" % str(E.info(en["kind"])["name"]))
					else:
						en["burn"] = E.BURN_TIME
						_fx_zone(zid, "ignite", en["pos"], en["pos"], id, "")
			var zi: Dictionary = ice.get(zid, {})
			for iid: int in zi:
				var block: Array = zi[iid]
				if not bool(block[1]) and HB.hits(poke, HB.circle(block[0], Z.ICE_RADIUS)):
					block[1] = true
					_to_clients(&"_rpc_ice", [zid, iid, true])
					ice_changed.emit(zid)
					_fx_zone(zid, "melt", block[0], block[0], id, "")
					_toast_to(id, "The ice melted into a puddle. You can fill your can from it.")
		"lantern":
			if float(a["fuel"]) <= 0.0:
				if not _use_one(id, "oil"):
					_toast_to(id, "Your lantern is out of oil.")
					return
				a["fuel"] = Items.FUEL_MAX
				_send_inventory(id)
				a["lantern_on"] = true
			else:
				a["lantern_on"] = not bool(a["lantern_on"])
			a["dirty"] = true
			_toast_to(id, "Lantern on." if bool(a["lantern_on"]) else "Lantern off (saving oil).")
		"pot_lid":
			pass
		_:
			_toast_to(id, "Nothing in your offhand. Equip a torch, lantern or Pot Lid in your bag (I).")


func _relight(id: int) -> void:
	var a: Dictionary = avatars[id]
	a["torch_lit"] = true
	a["dirty"] = true
	_fx_zone(a["zone"], "ignite", a["pos"], a["pos"], id, "torch")
	_toast_to(id, "Torch relit.")
	Net.log_line("%s relit their torch" % Net.player_name(id))


## A player says an enemy attack (or a bump, atk_id 0) hit them. They saw the telegraph
## and know whether they were in it, dodged, or blocked; the host checks it was real.
@rpc("any_peer", "call_remote", "reliable")
func c_hit_me(enemy_id: int, atk_id: int, tier: int) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	if bool(a["fainted"]):
		return
	var zid: String = a["zone"]
	var en := _find_enemy(zid, enemy_id)
	var dmg := 0
	var from: Vector2 = en["pos"] if not en.is_empty() else a["pos"]
	if atk_id == 0:
		if en.is_empty() or float(en["pop"]) > 0.0 or float(a["touch_cd"]) > 0.0:
			return
		var info := E.info(en["kind"])
		if int(info["touch"]) <= 0 or (en["pos"] as Vector2).distance_to(a["pos"]) > float(info["radius"]) + 140.0:
			return
		dmg = int(info["touch"])
		a["touch_cd"] = 0.5
	else:
		if not attacks.has(atk_id):
			return
		var rec: Dictionary = attacks[atk_id]
		var now := Time.get_ticks_msec()
		if rec["zone"] != zid or (rec["hit"] as Dictionary).has(id) \
				or now < int(rec["strike_ms"]) - 400 or now > int(rec["end_ms"]) + 1500:
			return
		rec["hit"][id] = true
		dmg = int(rec["damage"])
	var taken := dmg
	tier = clampi(tier, 0, 3)
	var off := str(a["equip"]["offhand"])
	var sh := Items.shield(off)
	var st := _shield_state(a, off)
	if tier > 0 and (sh.is_empty() or float(st.get("broken", 0.0)) > 0.0):
		tier = 0   # no shield, or it's broken: the block didn't happen
	if tier > 0:
		var eff: float = (sh["eff"] as Array)[3 - tier]
		var stopped := float(dmg) * eff
		# What gets through rounds down: a Regular block that soaks half of a slime's one
		# heart stops it, rather than rounding the half back up to a full heart.
		taken = floori(float(dmg) - stopped + 0.001)
		st["hp"] = float(st["hp"]) - stopped * [0.0, 1.0, 0.5, 0.0][tier]
		stats["hits_blocked"] = int(stats["hits_blocked"]) + 1
		_fx_zone(zid, "clang" if tier == 3 else "block", a["pos"], from, id, off)
		if float(st["hp"]) <= 0.0:
			st["hp"] = 0.0
			st["broken"] = float(sh["break_time"])
			_fx_zone(zid, "shield_break", a["pos"], a["pos"], id, off)
			_toast_to(id, "Your %s broke! No blocking for %d seconds." % [Items.display_name(off), int(sh["break_time"])])
		a["dirty"] = true
		if not en.is_empty():
			if tier == 3:
				en["state"] = "stunned"
				en["st"] = E.PERFECT_STUN
			if atk_id == 0:
				# A bump taken on the shield shoves the enemy back off you and leaves it
				# reeling for a moment, so it can't just walk straight back into you.
				var info := E.info(en["kind"])
				en["kb"] = (from - (a["pos"] as Vector2)).normalized() * [0.0, 380.0, 460.0, 540.0][tier] / float(info["scale"])
				if str(en["state"]) != "stunned":
					en["state"] = "stunned"
					en["st"] = CONTACT_BLOCK_STUN
				elif tier == 3:
					en["st"] = E.PERFECT_STUN
			if int(sh["spikes"]) > 0:
				_hurt_enemy(zid, en, int(sh["spikes"]) * (2 if tier == 3 else 1), a["pos"], id, false)
		if taken <= 0:
			return
	stats["hits_taken"] = int(stats["hits_taken"]) + 1
	_damage_player(id, maxi(taken - Items.total(a["equip"], "armor"), 1), from)


## A player's state for one of their shields: {"hp", "broken"} (each shield keeps its own).
func _shield_state(a: Dictionary, shield_id: String) -> Dictionary:
	var sh := Items.shield(shield_id)
	if sh.is_empty():
		return {}
	var all: Dictionary = a["shields"]
	if not all.has(shield_id):
		all[shield_id] = {"hp": float(sh["hp"]), "broken": 0.0}
	return all[shield_id]


## Broken shields wait out their break time, then every shield regrows.
func _tick_shields(a: Dictionary, delta: float) -> void:
	var worn := str(a["equip"]["offhand"])
	for sid: String in a["shields"]:
		var st: Dictionary = a["shields"][sid]
		var sh := Items.shield(sid)
		var before := floori(float(st["hp"]))
		var was_broken := float(st["broken"]) > 0.0
		if float(st.get("hold", 0.0)) > 0.0:
			st["hold"] = float(st["hold"]) - delta   # test hook: no recovery for a moment
		elif was_broken:
			st["broken"] = maxf(float(st["broken"]) - delta, 0.0)
		elif float(st["hp"]) < float(sh["hp"]):
			st["hp"] = minf(float(st["hp"]) + float(sh["recover"]) * delta, float(sh["hp"]))
		if sid == worn and (floori(float(st["hp"])) != before or was_broken != (float(st["broken"]) > 0.0) \
				or (was_broken and ceili(float(st["broken"])) != ceili(float(st["broken"]) + delta))):
			a["dirty"] = true   # update the shield bar


## Steel-toed boots: sprinting into an enemy kicks it.
@rpc("any_peer", "call_remote", "reliable")
func c_kick(enemy_id: int, pos_now: Vector2) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	var gear: Dictionary = a["equip"]
	var power := Items.total(gear, "kick")
	if power <= 0 or bool(a["fainted"]) or float(a["kick_cd"]) > 0.0:
		return
	_accept_pos(a, pos_now, a["facing"])
	var zid: String = a["zone"]
	var en := _find_enemy(zid, enemy_id)
	if en.is_empty():
		return
	var body := HB.enemy_hurtbox(en["kind"], en["pos"])
	body["r"] = float(body["r"]) + KICK_SLACK
	if not HB.hits(HB.kick(a["pos"], a["facing"]), body):
		return
	if "miner" in Items.full_sets(gear):
		power += 1
	a["kick_cd"] = 0.4
	_fx_zone(zid, "kick", a["pos"], en["pos"], id, "")
	_hurt_enemy(zid, en, power, a["pos"], id, false)


@rpc("any_peer", "call_remote", "reliable")
func c_interact(pos_now: Vector2, facing_now: Vector2) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	if bool(a["fainted"]):
		return
	_accept_pos(a, pos_now, facing_now)
	var zid: String = a["zone"]
	var pos: Vector2 = a["pos"]
	var facing: Vector2 = a["facing"]
	# Revive a fainted friend.
	for other: int in avatars:
		var o: Dictionary = avatars[other]
		if other != id and o["zone"] == zid and bool(o["fainted"]) and (o["pos"] as Vector2).distance_to(pos) < REVIVE_RANGE:
			o["fainted"] = false
			o["hp"] = maxi(int(float(o["max_hp"]) * 0.5), 4)
			o["dirty"] = true
			_fx_zone(zid, "revive", o["pos"], o["pos"], other, "")
			_toast_to(other, "%s helped you up!" % Net.player_name(id))
			_toast_to(id, "You revived %s." % Net.player_name(other))
			return
	for npc: Dictionary in Z.zone(zid).get("npcs", []):
		if (npc["pos"] as Vector2).distance_to(pos) < TALK_RANGE:
			_talk_to_pepper(id)
			return
	for door: Dictionary in Z.zone(zid).get("doors", []):
		if (door["pos"] as Vector2).distance_to(pos) < DOOR_RANGE:
			_use_door(id, str(door["to"]))
			return
	if _try_harvest(id, zid, pos + facing * 30.0):
		return
	# Ride or call a lift.
	for l: Dictionary in Z.zone(zid)["lifts"]:
		var lid: String = l["id"]
		var ls: Dictionary = lift_state[zid][lid]
		if bool(ls["moving"]):
			continue
		var here: Vector2 = l[ls["at"]]
		var other_end: Vector2 = l["top" if ls["at"] == "bottom" else "bottom"]
		if Z.lift_rect(here).grow(12.0).has_point(pos):
			_start_lift(zid, lid, id)
			return
		if Z.lift_rect(other_end).grow(60.0).has_point(pos):
			_start_lift(zid, lid, id)   # calls the empty platform over
			_toast_to(id, "Calling the lift...")
			return
	if a["equip"]["offhand"] == "torch" and not bool(a["torch_lit"]) and _near_fire(zid, pos):
		_relight(id)
		return
	var pk: Dictionary = pickups.get(zid, {})
	for pid: int in pk.keys():
		var ppos: Vector2 = pk[pid]
		if ppos.distance_to(pos) < PICKUP_RANGE:
			var item: String = Z.zone(zid)["pickup"]
			if Items.give(a["inv"], a["wheel"], item, 1):
				pk.erase(pid)
				_respawn.append([zid, pid, ppos, PICKUP_RESPAWN])
				_to_clients(&"_rpc_pickup", [zid, pid, ppos, false])
				pickups_changed.emit(zid)
				_send_inventory(id)
				_fx_zone(zid, "pickup", ppos, ppos, id, item)
				_toast_to(id, "Picked up a %s." % Items.display_name(item))
			else:
				_toast_to(id, "Your bag is full.")
			return
	for c: Dictionary in Z.zone(zid)["chests"]:
		if (c["pos"] as Vector2).distance_to(pos) < CHEST_RANGE:
			var cid: String = c["id"]
			if cid in (a["chests"] as Array):
				_toast_to(id, "Empty. You already took what was in here.")
				return
			var got: Array[String] = []
			for item: String in Items.CHEST_LOOT[cid]:
				if Items.give(a["inv"], a["wheel"], item, 1):
					got.append(Items.display_name(item))
			(a["chests"] as Array).append(cid)
			a["dirty"] = true
			_send_inventory(id)
			_fx_zone(zid, "chest", c["pos"], c["pos"], id, "")
			_toast_to(id, "Found: %s! Equip them in your bag (I)." % ", ".join(got))
			lesson_event(id, "chest")
			Net.log_line("%s opened %s" % [Net.player_name(id), cid])
			return
	if _near_water(zid, pos) and not Items.locate(a["inv"], a["wheel"], "can").is_empty():
		_refill(id)
		return
	_toast_to(id, "Nothing to do here.")


func _near_water(zid: String, pos: Vector2) -> bool:
	if Z.zone(zid).has("well") and pos.distance_to(Z.zone(zid)["well"]) < WELL_RANGE:
		return true
	for p: Vector2 in puddles(zid):
		if p.distance_to(pos) < PUDDLE_RANGE:
			return true
	return false


func _try_harvest(id: int, zid: String, point: Vector2) -> bool:
	if not crops.has(zid):
		return false
	var i := Z.plot_at(zid, point, REACH)
	if i < 0:
		return false
	var p: Array = crops[zid][i]
	if str(p[0]) == "" or int(p[1]) < _crop_max(str(p[0])):
		return false
	var crop: Dictionary = Items.CROPS[str(p[0])]
	if not Items.give(avatars[id]["inv"], avatars[id]["wheel"], str(crop["yield"]), int(crop["amount"])):
		_toast_to(id, "Your bag is full.")
		return true
	crops[zid][i] = ["", 0, 0.0]
	_crop_broadcast(zid, i)
	_send_inventory(id)
	_fx_zone(zid, "harvest", Z.plot_center(zid, i), Z.plot_center(zid, i), id, str(crop["yield"]))
	_toast_to(id, "+%d %s" % [int(crop["amount"]), Items.display_name(str(crop["yield"]))])
	lesson_event(id, "harvest")
	return true


## Fills the player's watering can, wherever they keep it.
func _refill(id: int) -> void:
	var a: Dictionary = avatars[id]
	var at := Items.locate(a["inv"], a["wheel"], "can")
	if at.is_empty():
		return
	var where: Array = a["wheel"] if at["in"] == "wheel" else a["inv"]
	where[int(at["i"])][1] = Items.CAN_MAX
	_send_inventory(id)
	_toast_to(id, "Watering can refilled.")


## Uses up one of an item from the wheel or the bag. False if the player has none.
func _use_one(id: int, item: String) -> bool:
	var a: Dictionary = avatars[id]
	var at := Items.locate(a["inv"], a["wheel"], item)
	if at.is_empty():
		return false
	if at["in"] == "wheel":
		Items.wheel_take_one(a["wheel"], int(at["i"]))
	else:
		Items.take_one(a["inv"], int(at["i"]))
	return true


## Puts a bag item on (swapping out whatever was in that slot).
@rpc("any_peer", "call_remote", "reliable")
func c_equip(bag_slot: int) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	var inv: Array = a["inv"]
	var item := Items.item_at(inv, bag_slot)
	if item == "" or not Items.is_equipment(item):
		return
	var gear: Dictionary = a["equip"]
	var slot := Items.target_slot(item, gear)
	var old := str(gear[slot])
	gear[slot] = item
	inv[bag_slot] = [old, 1] if old != "" else []
	_recompute_max_hp(a)
	_send_inventory(id)
	Net.log_line("%s equipped %s (%s)" % [Net.player_name(id), item, slot])
	lesson_event(id, "equip")


@rpc("any_peer", "call_remote", "reliable")
func c_unequip(slot: String) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	var gear: Dictionary = a["equip"]
	if not gear.has(slot) or str(gear[slot]) == "":
		return
	if not Items.add_item(a["inv"], str(gear[slot]), 1):
		_toast_to(id, "Your bag is full.")
		return
	gear[slot] = ""
	_recompute_max_hp(a)
	_send_inventory(id)


@rpc("any_peer", "call_remote", "reliable")
func c_pin_add(zid: String, pos: Vector2, label: String) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id) or not Z.exists(zid):
		return
	var mine: Array[int] = []
	for pid: int in pins:
		if int(pins[pid]["owner"]) == id:
			mine.append(pid)
	if mine.size() >= PINS_PER_PLAYER:
		mine.sort()
		pins.erase(mine[0])
		_to_clients(&"_rpc_pin", [mine[0], {}])
	var pin_id := _new_id()
	var pin := {"zone": zid, "pos": pos.clamp(Vector2.ZERO, Z.size_of(zid)), "owner": id,
		"name": Net.player_name(id), "label": label.strip_edges().left(28), "color": Net.player_color(id)}
	pins[pin_id] = pin
	_to_clients(&"_rpc_pin", [pin_id, pin])
	stats["pin_events"] = int(stats["pin_events"]) + 1
	pins_changed.emit()
	lesson_event(id, "pin")


@rpc("any_peer", "call_remote", "reliable")
func c_pin_remove(pin_id: int) -> void:
	if not is_host() or not pins.has(pin_id):
		return
	var id := _sender()
	if int(pins[pin_id]["owner"]) != id and id != 1:
		return
	pins.erase(pin_id)
	_to_clients(&"_rpc_pin", [pin_id, {}])
	pins_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func c_inv_swap(a_slot: int, b_slot: int) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var inv: Array = avatars[id]["inv"]
	if a_slot < 0 or b_slot < 0 or a_slot >= inv.size() or b_slot >= inv.size():
		return
	var t: Array = inv[a_slot]
	inv[a_slot] = inv[b_slot]
	inv[b_slot] = t
	_send_inventory(id)


## Puts a bag stack into the item wheel (the wheel grows by one segment).
@rpc("any_peer", "call_remote", "reliable")
func c_wheel_add(bag_slot: int) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	var why := Items.wheel_add(a["wheel"], a["inv"], bag_slot)
	if why != "":
		_toast_to(id, why)
		return
	_send_inventory(id)
	lesson_event(id, "wheel")


## Takes a stack out of the item wheel and back into the bag (the wheel shrinks).
@rpc("any_peer", "call_remote", "reliable")
func c_wheel_remove(wheel_slot: int) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	if (a["wheel"] as Array).size() <= 1:
		_toast_to(id, "Keep at least one thing in your wheel.")
		return
	var why := Items.wheel_remove(a["wheel"], a["inv"], wheel_slot)
	if why != "":
		_toast_to(id, why)
		return
	_send_inventory(id)


## Swaps two segments of the item wheel (to put favourites where you want them).
@rpc("any_peer", "call_remote", "reliable")
func c_wheel_swap(a_slot: int, b_slot: int) -> void:
	if not is_host():
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var wh: Array = avatars[id]["wheel"]
	if a_slot < 0 or b_slot < 0 or a_slot >= wh.size() or b_slot >= wh.size():
		return
	var t: Array = wh[a_slot]
	wh[a_slot] = wh[b_slot]
	wh[b_slot] = t
	_send_inventory(id)


@rpc("any_peer", "call_remote", "unreliable")
func c_ping(t_usec: int) -> void:
	if is_host():
		_rpc_pong.rpc_id(multiplayer.get_remote_sender_id(), t_usec)


## Test-only controls (the host must be started with --test).
@rpc("any_peer", "call_remote", "reliable")
func c_debug(cmd: String, args: Array) -> void:
	if not is_host() or not test_mode:
		return
	var id := _sender()
	if not avatars.has(id):
		return
	var a: Dictionary = avatars[id]
	var zid: String = a["zone"]
	match cmd:
		"clear":
			enemies[zid] = []
		"pause_ai":
			ai_paused = bool(args[0])
		"spawn":
			var en := _spawn_enemy(zid, str(args[0]), args[1])
			if args.size() > 2:
				en["cd"] = 999.0
			enemies[zid].append(en)
		"attack":
			for en: Dictionary in enemies[zid]:
				if int(en["id"]) == int(args[0]):
					_begin_windup(zid, en, E.info(en["kind"]), args[1])
		"weather":
			host_set_weather(str(args[0]), str(args[1]))
		"clock":
			clock = float(args[0])
			_to_clients(&"_rpc_clock_jump", [clock, day, play_time])
		"heal":
			a["hp"] = int(a["max_hp"])
			a["dirty"] = true
		"give":
			Items.give(a["inv"], a["wheel"], str(args[0]), int(args[1]))
			_send_inventory(id)
		"teleport":
			_teleport(id, args[0])
		"goto":
			a["zone"] = str(args[0])
			a["pos"] = args[1]
			beacons[id] = [a["zone"], a["pos"]]
			_to_peer(id, &"_rpc_enter_zone", [a["zone"], a["pos"]])
		"set_can":
			var at := Items.locate(a["inv"], a["wheel"], "can")
			if not at.is_empty():
				(a["wheel"] if at["in"] == "wheel" else a["inv"])[int(at["i"])][1] = int(args[0])
				_send_inventory(id)
		"set_hp":
			a["hp"] = int(args[0])
			a["dirty"] = true
		"torch":
			a["torch_lit"] = bool(args[0])
			a["dirty"] = true
		"fuel":
			a["fuel"] = float(args[0])
			a["dirty"] = true
		"shield_hp":
			# Sets the worn shield's health; an optional second argument holds it there for
			# that many seconds (no recovery), so a test's timing doesn't depend on lag.
			var st := _shield_state(a, str(a["equip"]["offhand"]))
			if not st.is_empty():
				st["hp"] = float(args[0])
				st["broken"] = 0.0
				st["hold"] = float(args[1]) if args.size() > 1 else 0.0
				a["dirty"] = true


# ---------------------------------------------------------------- host -> client updates

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(zid: String, av: Array, el: Array) -> void:
	if zid != my_zone:
		stats["other_zone_snapshots"] = int(stats["other_zone_snapshots"]) + 1
		return
	stats["snapshots_in"] = int(stats["snapshots_in"]) + 1
	var seen: Dictionary = stats["enemy_kinds_seen"]
	for e: Array in el:
		seen[str(e[1])] = true
	snapshot.emit(zid, av, el)


@rpc("authority", "call_remote", "unreliable")
func _rpc_beacons(b: Dictionary) -> void:
	beacons = b
	stats["beacons_in"] = int(stats["beacons_in"]) + 1
	beacons_changed.emit()


## Unreliable on purpose: a lost sync is replaced 2 s later, while a late resend would
## drag the clock backwards. The client adds half its ping, the time the message took.
## The clock was set to a new time (not just drifting): must arrive, so it's reliable.
@rpc("authority", "call_remote", "reliable")
func _rpc_clock_jump(c: float, d: int, pt: float) -> void:
	_rpc_clock(c, d, pt)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_clock(c: float, d: int, pt: float) -> void:
	play_time = pt
	var rtt: Array = stats["rtt_ms"]
	var recent := rtt.slice(maxi(rtt.size() - 10, 0))
	var avg := 0.0
	for x: float in recent:
		avg += x
	if not recent.is_empty():
		avg /= recent.size()
	var t := c + (avg / 2000.0) * MINUTES_PER_SECOND * time_scale
	day = d
	if t >= 1440.0:
		t -= 1440.0
		day += 1
	clock = t


@rpc("authority", "call_remote", "reliable")
func _rpc_weather(zid: String, w: String) -> void:
	weather[zid] = w
	weather_log.append([Time.get_unix_time_from_system(), zid, w])
	stats["weather_events"] = int(stats["weather_events"]) + 1
	weather_changed.emit(zid)


@rpc("authority", "call_remote", "reliable")
func _rpc_crop(zid: String, i: int, p: Array) -> void:
	if crops.has(zid):
		crops[zid][i] = p
		stats["crop_events"] = int(stats["crop_events"]) + 1
		crop_changed.emit(zid, i)


@rpc("authority", "call_remote", "reliable")
func _rpc_pin(pin_id: int, pin: Dictionary) -> void:
	if pin.is_empty():
		pins.erase(pin_id)
	else:
		pins[pin_id] = pin
	stats["pin_events"] = int(stats["pin_events"]) + 1
	pins_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_pickup(zid: String, pid: int, pos: Vector2, present: bool) -> void:
	var pk: Dictionary = pickups.get(zid, {})
	if present:
		pk[pid] = pos
	else:
		pk.erase(pid)
	pickups[zid] = pk
	pickups_changed.emit(zid)


@rpc("authority", "call_remote", "reliable")
func _rpc_ice(zid: String, iid: int, melted: bool) -> void:
	var zi: Dictionary = ice.get(zid, {})
	if zi.has(iid):
		zi[iid][1] = melted
	ice_changed.emit(zid)


@rpc("authority", "call_remote", "reliable")
func _rpc_lift(zid: String, lid: String, from_end: String, to_end: String, seconds: float, riders: Array) -> void:
	if me() in riders:
		stats["lift_rides"] = int(stats["lift_rides"]) + 1
	lift_moved.emit(zid, lid, from_end, to_end, seconds, riders)


@rpc("authority", "call_remote", "reliable")
func _rpc_lift_state(zid: String, lid: String, at: String) -> void:
	if lifts.has(zid):
		lifts[zid][lid] = at
	lift_arrived.emit(zid, lid)


@rpc("authority", "call_remote", "reliable")
func _rpc_telegraph(zid: String, tg: Dictionary) -> void:
	if zid != my_zone:
		return
	stats["telegraphs_in"] = int(stats["telegraphs_in"]) + 1
	telegraph.emit(zid, tg)


@rpc("authority", "call_remote", "reliable")
func _rpc_inventory(inv: Array, wh: Array, gear: Dictionary) -> void:
	inventory = inv
	wheel = wh
	selected = clampi(selected, 0, maxi(wheel.size() - 1, 0))
	equip = gear
	inventory_changed.emit()
	vitals_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_vitals(v: Dictionary) -> void:
	vitals = v
	vitals_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_teleport(pos: Vector2) -> void:
	teleported.emit(pos)


@rpc("authority", "call_remote", "reliable")
func _rpc_enter_zone(zid: String, at: Vector2) -> void:
	my_zone = zid
	arrive_pos = at
	stats["zone_changes"] = int(stats["zone_changes"]) + 1
	zone_entered.emit(zid, at)


@rpc("authority", "call_remote", "reliable")
func _rpc_fx(zid: String, kind: String, a: Vector2, b: Vector2, peer: int, item: String) -> void:
	if zid != my_zone:
		return
	stats["fx_events"] = int(stats["fx_events"]) + 1
	fx.emit(zid, kind, a, b, peer, item)


@rpc("authority", "call_remote", "reliable")
func _rpc_unlocked(house: String) -> void:
	unlocked[house] = true
	ice_changed.emit("middlemost")   # redraws the village (the padlock goes)


@rpc("authority", "call_remote", "reliable")
func _rpc_dialogue(speaker: String, lines: Array) -> void:
	dialogue.emit(speaker, lines)


@rpc("authority", "call_remote", "reliable")
func _rpc_toast(text: String) -> void:
	toast.emit(text)


@rpc("authority", "call_remote", "unreliable")
func _rpc_pong(t_usec: int) -> void:
	var rtt: Array = stats["rtt_ms"]
	rtt.append((Time.get_ticks_usec() - t_usec) / 1000.0)
	if rtt.size() > 600:
		rtt.pop_front()
