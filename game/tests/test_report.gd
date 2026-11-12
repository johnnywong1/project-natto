extends Node
## Test report. Net adds it when the game is started with --report=PATH. It watches the
## session and writes a JSON report at --report-at seconds of game time (or as soon as the
## mechanic scenarios finish), then quits after --linger seconds. If the player is turned
## away (game full) it writes that instead. tools/mp_test.py compares everyone's reports.
## With --save-at-report the host saves the world first (for the save test).

const Z = preload("res://game/data/zones.gd")

var report_path := ""
var report_at := 40.0
var linger := 0.0
var lobby_max := 0
var lobby_names: Dictionary = {}
var count_timeline: Array = []
var sightings: Dictionary = {}
var foreign_sightings := 0
var clock_samples: Array = []
var light_samples: Array = []
var bytes_sent := 0
var bytes_recv := 0
var pos_log: Array = []      # [unix time, x, y] of this player's own avatar
var seen_log: Array = []     # [unix time, "b" (map beacon) or "r" (in-zone player), peer, x, y]
var _pos_t := 0.0
var _seen_t := 0.0
var _sample_t := 0.0
var _written := false
var _quit_t := -1.0
var _boot_msec := 0


func _ready() -> void:
	report_path = str(Net.opts.get("report"))
	report_at = float(Net.opts.get("report-at", "40"))
	linger = float(Net.opts.get("linger", "0"))
	_boot_msec = Time.get_ticks_msec()
	Net.lobby_changed.connect(_on_lobby)
	World.snapshot.connect(_on_snapshot)


func game_time() -> float:
	return (Time.get_ticks_msec() - Net.started_at_msec) / 1000.0


func _on_lobby() -> void:
	lobby_max = maxi(lobby_max, Net.players.size())
	for id: int in Net.players:
		lobby_names[str(id)] = Net.player_name(id)
	count_timeline.append([snappedf((Time.get_ticks_msec() - _boot_msec) / 1000.0, 0.01), Net.players.size()])


func _on_snapshot(zid: String, av: Array, _wl: Array) -> void:
	for e: Array in av:
		var id: int = e[0]
		if id == World.me():
			continue
		sightings[str(id)] = int(sightings.get(str(id), 0)) + 1
		if World.beacons.has(id) and str(World.beacons[id][0]) != zid:
			foreign_sightings += 1


func _process(delta: float) -> void:
	if _quit_t >= 0.0:
		_quit_t -= delta
		# Test players stay until the host closes the session (or the linger time runs out).
		if _quit_t <= 0.0 or (not Net.is_host() and not Net.is_online()):
			get_tree().quit()
		return
	if _written:
		return
	if Net.rejected_reason != "" and not Net.is_online():
		_write({"name": Net.local_name, "rejected": Net.rejected_reason, "lobby_max_players": lobby_max,
			"wall_time": Time.get_unix_time_from_system()})
		return
	if not Net.in_game:
		if (Time.get_ticks_msec() - _boot_msec) / 1000.0 > report_at + 60.0:
			_write({"name": Net.local_name, "error": "never entered a game", "status": Net.status})
		return
	_pos_t -= delta
	if _pos_t <= 0.0:
		_pos_t = 0.05
		var cs := get_tree().current_scene
		if cs != null and "local" in cs and cs.local != null:
			var lp: Vector2 = (cs.local as Node2D).position
			pos_log.append([Time.get_unix_time_from_system(), snappedf(lp.x, 0.01), snappedf(lp.y, 0.01)])
			if pos_log.size() > 700:
				pos_log.pop_front()
	_seen_t -= delta
	if _seen_t <= 0.0:
		_seen_t = 0.25
		var now := Time.get_unix_time_from_system()
		for id: int in World.beacons:
			if id != World.me():
				var bp: Vector2 = World.beacons[id][1]
				seen_log.append([now, "b", str(id), snappedf(bp.x, 0.01), snappedf(bp.y, 0.01)])
		var cs2 := get_tree().current_scene
		if cs2 != null and "remotes" in cs2:
			for id: int in cs2.remotes:
				var rp: Vector2 = (cs2.remotes[id] as Node2D).position
				seen_log.append([now, "r", str(id), snappedf(rp.x, 0.01), snappedf(rp.y, 0.01)])
		while seen_log.size() > 1200:
			seen_log.pop_front()
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = 1.0
		clock_samples.append([snappedf(game_time(), 0.01), snappedf(World.clock, 0.01)])
		var w := get_tree().current_scene
		if w != null and w.has_node("DayNight"):
			var c: Color = (w.get_node("DayNight") as CanvasModulate).color
			light_samples.append([snappedf(game_time(), 0.01), World.my_zone, snappedf(c.r, 0.001), snappedf(c.g, 0.001),
				snappedf(c.b, 0.001), snappedf(World.clock, 0.1), World.my_lights()])
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null and enet.host != null:
			bytes_sent += int(enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
			bytes_recv += int(enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	var sc: Variant = _scenarios()
	if (sc != null and sc.done) or game_time() >= report_at:
		_write(_full_report())


func _scenarios() -> Variant:
	var cs := get_tree().current_scene
	if cs != null and cs.has_node("Scenarios"):
		return cs.get_node("Scenarios")
	return null


func _v(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


func _full_report() -> Dictionary:
	var gt := game_time()
	var w := get_tree().current_scene
	var rtt: Array = World.stats["rtt_ms"].duplicate()
	rtt.sort()
	var rtt_info := {"n": rtt.size()}
	if not rtt.is_empty():
		var total := 0.0
		for x: float in rtt:
			total += x
		rtt_info = {"n": rtt.size(), "avg": total / rtt.size(), "max": rtt[rtt.size() - 1],
			"p95": rtt[int(rtt.size() * 0.95) if rtt.size() > 1 else 0]}
	var crops := {}
	for zid: String in World.crops:
		var parts: PackedStringArray = []
		for p: Array in World.crops[zid]:
			parts.append("%s%d" % [str(p[0]).left(1), int(p[1])])
		crops[zid] = ",".join(parts)
	var pins := []
	for pid: int in World.pins:
		var pin: Dictionary = World.pins[pid]
		pins.append({"id": pid, "zone": pin["zone"], "label": pin["label"], "owner": pin["name"]})
	var beacons := {}
	for id: int in World.beacons:
		beacons[str(id)] = [World.beacons[id][0], snappedf((World.beacons[id][1] as Vector2).x, 0.01), snappedf((World.beacons[id][1] as Vector2).y, 0.01)]
	var visible := {}
	var pos := Vector2.ZERO
	if w != null and "remotes" in w:
		for id: int in w.remotes:
			visible[str(id)] = _v((w.remotes[id] as Node2D).position)
		pos = (w.local as Node2D).position
	var players := {}
	for id: int in Net.players:
		players[str(id)] = Net.player_name(id)
	var stats: Dictionary = World.stats
	var secs := maxf(gt, 0.001)
	var rep := {
		"name": Net.local_name, "peer_id": World.me(), "is_host": Net.is_host(),
		"role": int(Net.opts.get("role", "-1")), "wall_time": Time.get_unix_time_from_system(),
		"game_time": gt, "lobby_max_players": lobby_max, "lobby_names": lobby_names,
		"count_timeline": count_timeline, "players": players, "joined_in_progress": Net.joined_in_progress,
		"zone": World.my_zone, "pos": _v(pos), "selected": World.selected, "held": World.held_item(),
		"inventory": World.inventory, "wheel": World.wheel, "clock": World.clock, "day": World.day, "time_scale": World.time_scale,
		"weather": World.weather, "crops": crops, "pins": pins, "beacons": beacons,
		"visible_remotes": visible, "sightings": sightings, "foreign_sightings": foreign_sightings,
		"snapshots_in": stats["snapshots_in"], "snapshot_hz": float(stats["snapshots_in"]) / secs,
		"beacons_in": stats["beacons_in"], "weather_events": stats["weather_events"],
		"crop_events": stats["crop_events"], "pin_events": stats["pin_events"], "fx_events": stats["fx_events"],
		"zone_changes": stats["zone_changes"], "other_zone_snapshots": stats["other_zone_snapshots"], "rtt_ms": rtt_info,
		"bytes_sent": bytes_sent, "bytes_recv": bytes_recv,
		"kbps_up": bytes_sent * 8.0 / 1000.0 / secs, "kbps_down": bytes_recv * 8.0 / 1000.0 / secs,
		"clock_samples": clock_samples, "light_samples": light_samples, "weather_log": World.weather_log, "pos_log": pos_log, "seen_log": seen_log,
		"equip": World.equip, "vitals": World.vitals, "lights": World.my_lights(),
		"telegraphs_in": stats["telegraphs_in"], "hits_taken_host": stats["hits_taken"], "lift_rides": stats["lift_rides"],
		"enemy_kinds_seen": stats["enemy_kinds_seen"], "ice": _ice_state(), "lifts": World.lifts,
		"unlocked": World.unlocked.keys(), "play_time": World.play_time, "save_slot": World.save_slot, "solo": Net.solo,
	}
	if w != null and "local" in w and w.local != null:
		var me = w.local
		rep["avatar"] = {"stamina": snappedf(float(me.stamina), 0.01), "max_orbs": me.max_orbs, "speed_mult": me.speed_mult,
			"dash_mult": me.dash_mult, "regen_mult": me.regen_mult, "gear": me.gear, "lights": me.lights}
		rep["combat"] = w.stats
		var remote_gear := {}
		for id: int in w.remotes:
			var r = w.remotes[id]
			remote_gear[str(id)] = {"gear": r.gear, "lights": r.lights, "item": r.item, "hp": snappedf(float(r.hp_frac), 0.01)}
		rep["remote_gear"] = remote_gear
		var ens := {}
		for eid: int in w.enemy_nodes:
			var n = w.enemy_nodes[eid]
			if is_instance_valid(n):
				ens[str(n.kind)] = int(ens.get(str(n.kind), 0)) + 1
		rep["enemies_visible"] = ens
		if w.has_node("Bot"):
			rep["bot_log"] = w.get_node("Bot").log
	var sc: Variant = _scenarios()
	if sc != null:
		rep["scenarios"] = sc.results
		rep["scenarios_done"] = sc.done
	if Net.is_host():
		var avatars := {}
		for id: int in World.avatars:
			var a: Dictionary = World.avatars[id]
			avatars[str(id)] = {"zone": a["zone"], "pos": _v(a["pos"]), "slot": a["slot"], "inv": a["inv"], "wheel": a["wheel"],
				"equip": a["equip"], "hp": a["hp"], "max_hp": a["max_hp"], "fainted": a["fainted"],
				"torch_lit": a["torch_lit"], "lantern_on": a["lantern_on"], "fuel": snappedf(float(a["fuel"]), 0.1),
				"chests": a["chests"]}
		var enemies := {}
		for zid: String in World.enemies:
			var kinds := {}
			for en: Dictionary in World.enemies[zid]:
				kinds[str(en["kind"])] = int(kinds.get(str(en["kind"]), 0)) + 1
			enemies[zid] = kinds
		var frames := maxi(int(stats["frames"]), 1)
		rep["host"] = {"avatars": avatars, "enemies": enemies, "lift_state": World.lift_state,
			"frame_ms_avg": float(stats["frame_ms_total"]) / frames,
			"frame_ms_max": stats["frame_ms_max"], "frames": frames}
	return rep


func _ice_state() -> Dictionary:
	var out := {}
	for zid: String in World.ice:
		var melted := 0
		var d: Dictionary = World.ice[zid]
		for iid: int in d:
			if bool(d[iid][1]):
				melted += 1
		out[zid] = {"total": d.size(), "melted": melted}
	return out


func _write(rep: Dictionary) -> void:
	if Net.opts.has("save-at-report") and Net.is_host():
		rep["saved"] = World.save_now()
	_written = true
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(rep, "  "))
		f.close()
	Net.log_line("report written to %s" % report_path)
	_quit_t = maxf(linger, 0.05)
