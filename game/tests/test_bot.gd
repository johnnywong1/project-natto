extends Node
## Test bot: plays by itself so a multiplayer session can be checked automatically.
## It drives the local avatar with the same calls a player's input makes (filling and
## picking from the item wheel, use, offhand, interact, dash, sprint, block, equip, pins,
## exits, lifts). Roles (--role=N):
##   0 farmer: farms Middlemost, loses the torch to rain, relights it at the campfire
##   1 climber: Fernery, rides the pulley lift up with a friend, loots the Wayfarer set,
##     relights its rained-out torch at the ledge campfire (the raincoat keeps it lit after)
##   2 delver: Mossmouth, relights its torch at the entrance braziers if the rain got it,
##     calls the lift over, rides down, melts the ice wall, loots the
##     Miner set, refills the can at the meltwater, swaps to a lantern (burns oil)
##   3 fighter: Fernery, rides up with the climber and back down, then fights with a Pot Lid
##     (blocks or dashes out of telegraphs, circles enemies while aiming at them), and
##     goes back to a torch at night
##   4 round trip: Fernery and back to Middlemost (this one leaves the game early)
##   5 late joiner: Mossmouth, thaws a Frost Wilt with the torch and finishes it
##   6 ("saver") for the save test: fills the wheel, plants, wears a helmet, drops a pin and
##     says hello to Pepper, so the next run can check all of it came back

const Z = preload("res://game/data/zones.gd")
const Items = preload("res://game/data/items.gd")
const E = preload("res://game/data/enemies.gd")

var world: Variant
var role := 0
var log: Array = []
var _steps: Array = []
var _i := 0
var _wait := 0.0
var _act_t := 0.0
var _stop_at := 1e9
var _entered := false
var _rode := false
var _strafe := 1.0
var _ride_end := ""
var _stuck_t := 0.0
var _last_pos := Vector2.INF
var _torch_cd := 0.0   # self-defence: time until the next torch jab
var _ride_phase := 0


func _ready() -> void:
	if str(Net.opts.get("role", "0")) == "idle":
		role = -1
	elif str(Net.opts.get("role", "0")) == "saver":
		role = 6
	elif str(Net.opts.get("role", "0")) == "auto":
		var ids: Array = Net.players.keys()
		ids.sort()
		role = maxi(ids.find(World.me()), 0) % 5
	else:
		role = int(Net.opts.get("role", "0"))
	if Net.opts.has("report-at"):
		_stop_at = float(Net.opts["report-at"]) - 4.0
	World.zone_entered.connect(func(_z: String, _p: Vector2) -> void: _entered = true)
	World.lift_moved.connect(_on_lift)
	_steps = _plan(role)
	Net.log_line("bot role %d with %d steps" % [role, _steps.size()])


func _on_lift(_z: String, _l: String, _f: String, _t: String, _s: float, riders: Array) -> void:
	if World.me() in riders:
		_rode = true


func _plot_stand(i: int) -> Vector2:
	return Z.plot_center("middlemost", i) + Vector2(0, -46)


func _plan(r: int) -> Array:
	match r:
		0:
			var s: Array = [["wait", 1.0], ["equip", "pot_helmet"], ["to_wheel", "can"], ["to_wheel", "popberry_seed"], ["wheel", 2]]
			for i in 3:
				s.append_array([["walk", _plot_stand(i)], ["face", Vector2.DOWN], ["use"]])
			s.append(["wheel", 1])
			for i in 3:
				s.append_array([["walk", _plot_stand(i)], ["face", Vector2.DOWN], ["use"]])
			s.append_array([["pin", "Farm planted!"], ["wait", 4.6]])
			for i in 3:
				s.append_array([["walk", _plot_stand(i)], ["face", Vector2.DOWN], ["use"]])
			s.append(["wait", 4.6])
			for i in 3:
				s.append_array([["walk", _plot_stand(i)], ["face", Vector2.DOWN], ["interact"]])
			s.append_array([["relight"], ["walk", Vector2(1640, 1240)], ["wheel", 0]])
			return s
		1:
			return [["wait", 1.0], ["equip", "hermes_boots"], ["travel", "fernery"], ["pin", "Ferns here"],
				["ride", 2, 10.0], ["walk", Vector2(2790, 300)], ["interact"], ["wait", 0.6],
				["equip", "leaf_hood"], ["equip", "raincoat"], ["equip", "wellies"], ["dash", Vector2(-1, 0)],
				["wait", 0.5], ["dash", Vector2(1, 0)], ["relight"], ["walk", Vector2(2700, 250)], ["wheel", 0]]
		2:
			return [["wait", 1.0], ["travel", "mossmouth"], ["pin", "Dark down here"], ["relight"], ["ride", 1, 0.5],
				["walk", Vector2(1100, 1420)], ["walk", Vector2(830, 1400)], ["jab_at", Vector2(-1, 0)],
				["wait", 0.4], ["walk", Vector2(700, 1400)], ["walk", Vector2(420, 1450)], ["interact"], ["wait", 0.6],
				["equip", "miner_helmet"], ["equip", "overalls"], ["equip", "steel_toes"], ["equip", "ember_charm"],
				["walk", Vector2(700, 1410)], ["interact"], ["equip", "lantern"], ["walk", Vector2(600, 1450)]]
		3:
			return [["wait", 1.0], ["travel", "fernery"], ["equip", "pot_lid"], ["pin", "Boar country"],
				["board", 12.0], ["wait", 0.5], ["ride", 1, 0.5], ["walk", Vector2(2300, 1000)],
				["fight", 14.0], ["equip", "torch"], ["fight", 6.0], ["walk", Vector2(2200, 1050)]]
		4:
			return [["wait", 1.0], ["travel", "fernery"], ["pin", "Round trip"], ["walk", Vector2(400, 950)],
				["travel", "middlemost"], ["walk", Vector2(1760, 1210)], ["wheel", 0]]
		6:
			return [["wait", 1.0], ["to_wheel", "can"], ["to_wheel", "popberry_seed"], ["wheel", 2],
				["walk", _plot_stand(0)], ["face", Vector2.DOWN], ["use"], ["equip", "pot_helmet"],
				["pin", "Saved pin"], ["walk", Vector2(1660, 1110)], ["interact"], ["wait", 1.0],
				["walk", Vector2(1500, 1200)]]
		5:
			return [["wait", 1.0], ["travel", "mossmouth"], ["pin", "Late but here"], ["relight"], ["hunt", "frost_wilt", 9.0],
				["walk", Vector2(1100, 600)]]
	return []


func _game_time() -> float:
	return (Time.get_ticks_msec() - Net.started_at_msec) / 1000.0


func _note(text: String) -> void:
	log.append("%.1f %s" % [_game_time(), text])


func _process(delta: float) -> void:
	var local = world.local
	local.bot_input = Vector2.ZERO
	local.want_sprint = false
	if _game_time() >= _stop_at or _i >= _steps.size():
		local.want_block = false
		world.aim_override = Vector2.ZERO
		return
	var step: Array = _steps[_i]
	_wait += delta
	_self_defence(local, delta)
	match str(step[0]):
		"wait":
			if _wait >= float(step[1]):
				_next()
		"walk":
			if _walk_to(local, step[1]):
				_next()
		"face":
			local.facing = step[1]
			_next()
		"wheel":
			world.hud.open_wheel()
			world.hud.wheel.hover = int(step[1])
			world.hud.close_wheel(true)
			_next()
		"use":
			world.use_item(world.aim_point())
			_next()
		"interact":
			world.interact()
			_next()
		"pin":
			world.drop_pin(local.position + Vector2(0, -70), str(step[1]))
			_next()
		"equip":
			var slot := Items.find(World.inventory, str(step[1]))
			if slot >= 0:
				World.to_host(&"c_equip", [slot])
				_note("equip " + str(step[1]))
				_next()
			elif _wait > 3.0:
				_note("could not find " + str(step[1]))
				_next()
		"to_wheel":
			if Items.find(World.wheel, str(step[1])) >= 0:
				_next()
			elif _act_t <= 0.0:
				var slot := Items.find(World.inventory, str(step[1]))
				if slot >= 0:
					World.to_host(&"c_wheel_add", [slot])
					_note("put %s in the wheel" % str(step[1]))
				_act_t = 1.0
			else:
				_act_t -= delta
				if _wait > 4.0:
					_note("could not put %s in the wheel" % str(step[1]))
					_next()
		"dash":
			local.bot_input = step[1]
			if world.local.try_dash():
				world.stats["dashes"] = int(world.stats["dashes"]) + 1
			_next()
		"travel":
			if _entered and World.my_zone == str(step[1]):
				_entered = false
				_next()
			else:
				for ex: Dictionary in Z.zone(World.my_zone)["exits"]:
					if ex["to"] == step[1]:
						_walk_to(local, (ex["rect"] as Rect2).get_center())
		"pickup":
			var target := _nearest_pickup(local.position)
			if target == Vector2.INF:
				_next()
			elif _walk_to(local, target):
				world.interact()
				_next()
		"relight":
			if str(World.equip.get("offhand", "")) != "torch" or bool(World.vitals.get("torch_lit", true)):
				_next()   # nothing to relight
				return
			var best := Vector2.INF
			for f in Z.fire_sources(World.my_zone):
				if best == Vector2.INF or f.distance_to(local.position) < best.distance_to(local.position):
					best = f
			if _walk_to(local, best + Vector2(0, 60)):
				world.interact()
				_note("relight torch")
				_next()
		"jab_at":
			# Three jabs fanning across the direction (a torch only melts what it touches).
			var base: Vector2 = step[1]
			_act_t += delta
			var k := int(_act_t / 0.3)
			world.aim_override = base.rotated([-0.45, 0.0, 0.45][mini(k, 2)])
			if _act_t - delta < (k + 0.5) * 0.3 and _act_t >= (k + 0.5) * 0.3 and k <= 2:
				world.offhand()
			if k >= 3:
				world.aim_override = Vector2.ZERO
				_next()
		"ride", "board":
			_ride_step(local, step, delta)
		"fight":
			_fight(local, delta)
			if _wait >= float(step[1]):
				local.want_block = false
				world.aim_override = Vector2.ZERO
				_next()
		"hunt":
			_hunt(local, str(step[1]), delta)
			if _wait >= float(step[2]):
				world.aim_override = Vector2.ZERO
				_next()


func _next() -> void:
	_i += 1
	_wait = 0.0
	_act_t = 0.0
	_ride_end = ""
	_ride_phase = 0


func _walk_to(local: Variant, target: Vector2) -> bool:
	var to: Vector2 = target - (local.position as Vector2)
	if to.length() < 10.0:
		_stuck_t = 0.0
		return true
	local.bot_input = to.normalized()
	# Something in the way (ice, a cliff)? Give up on this spot after a while.
	if (local.position as Vector2).distance_to(_last_pos) < 1.0:
		_stuck_t += get_process_delta_time()
		if _stuck_t > 3.0:
			_stuck_t = 0.0
			_note("couldn't reach %s" % target.round())
			return true
	else:
		_stuck_t = 0.0
	_last_pos = local.position
	return false


## Get on the lift at our end (calling it over first if it's waiting at the other end),
## then either wait for company (ride: press E once `min_riders` are aboard or time runs
## out) or wait to be carried (board: someone else presses E; press it yourself if nobody does).
func _ride_step(local: Variant, step: Array, delta: float) -> void:
	var lifts: Array = Z.zone(World.my_zone)["lifts"]
	if lifts.is_empty():
		_next()
		return
	var def: Dictionary = lifts[0]
	var lid: String = def["id"]
	if local.riding:
		_ride_phase = 4
		return
	if _ride_phase == 4:
		_note("rode the %s" % lid)
		_next()
		return
	if _ride_end == "":
		var pos: Vector2 = local.position
		_ride_end = "bottom" if (def["bottom"] as Vector2).distance_to(pos) <= (def["top"] as Vector2).distance_to(pos) else "top"
	var spot: Vector2 = def[_ride_end]
	var at := str(World.lifts.get(World.my_zone, {}).get(lid, "bottom"))
	_act_t += delta
	if at != _ride_end:
		if _walk_to(local, spot) and _ride_phase == 0:
			world.interact()
			_note("called the %s over" % lid)
			_ride_phase = 1
			_act_t = 0.0
		elif _ride_phase == 1 and _act_t > 6.0:
			_ride_phase = 0
		return
	if not _walk_to(local, spot):
		return
	if _ride_phase < 2:
		_ride_phase = 2
		_act_t = 0.0
	if _ride_phase == 2:
		var aboard := 1
		for id: int in world.remotes:
			if Z.lift_rect(spot).grow(12.0).has_point((world.remotes[id] as Node2D).position):
				aboard += 1
		var go := false
		if str(step[0]) == "ride":
			go = aboard >= int(step[1]) or _act_t >= float(step[2])
		else:
			go = _act_t >= float(step[1])
		if go:
			world.interact()
			_note("pressed E on the %s with %d aboard" % [lid, aboard])
			_ride_phase = 3
			_act_t = 0.0
	elif _ride_phase == 3 and _act_t > 6.0:
		_note("the %s didn't move" % lid)
		_next()


## Which ledge (plateau) a point is on, or -1 on the main ground: a bot can only walk to
## enemies on its own level.
func _level(p: Vector2) -> int:
	var plats: Array = Z.zone(World.my_zone)["plateaus"]
	for i in plats.size():
		if (plats[i] as Rect2).has_point(p):
			return i
	return -1


func _nearest_enemy(from: Vector2, kind: String = "", within: float = 700.0) -> Variant:
	var best: Variant = null
	var bd := within
	var lvl := _level(from)
	for eid: int in world.enemy_nodes:
		var n: Variant = world.enemy_nodes[eid]
		if is_instance_valid(n) and not n.popping and (kind == "" or n.kind == kind) and _level(n.position) == lvl:
			var d: float = (n.position as Vector2).distance_to(from)
			if d < bd:
				bd = d
				best = n
	return best


## A bot with a lit torch jabs any enemy that comes close, like a player would, so the delver
## isn't eaten on the Deep Shelf while it looks for the ice. The jab also melts ice, which
## is what the delver is there for anyway.
func _self_defence(local: Variant, delta: float) -> void:
	_torch_cd -= delta
	if _torch_cd > 0.0 or local.fainted or local.riding:
		return
	if str(World.equip.get("offhand", "")) != "torch" or not bool(World.vitals.get("torch_lit", false)):
		return
	var en: Variant = _nearest_enemy(local.position, "", 64.0)
	if en == null or en.burning or en.state == 4:
		return
	world.aim_override = (en.position as Vector2) - (local.position as Vector2)
	local.facing = world.aim_override.normalized()
	world.offhand()
	if en.frozen:
		_note("jabbed a frozen %s" % str(en.kind))
	world.aim_override = Vector2.ZERO
	_torch_cd = 0.8


## Telegraphs about to land on us: block them with a Pot Lid if we have one, else dash out.
func _defend(local: Variant) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var lid: bool = not Items.shield(str(World.equip.get("offhand", ""))).is_empty() and not local.shield_broken
	for p: Dictionary in world.pending:
		if bool(p["done"]) or now < float(p["strike"]) - 0.45 or now > float(p["end"]):
			continue
		var tg: Dictionary = p["tg"]
		var src: Vector2 = tg["origin"]
		if lid:
			world.aim_override = src - (local.position as Vector2)
			local.want_block = true
		else:
			var away: Vector2 = ((local.position as Vector2) - src).normalized()
			if str(tg["kind"]) == "charge":
				var d: Vector2 = tg["dir"]
				away = Vector2(-d.y, d.x)
			local.bot_input = away
			if local.dash_t <= 0.0 and local.try_dash():
				world.stats["dashes"] = int(world.stats["dashes"]) + 1
		return true
	local.want_block = false
	return false


func _fight(local: Variant, delta: float) -> void:
	if _defend(local):
		return
	var en: Variant = _nearest_enemy(local.position)
	if en == null:
		_walk_to(local, Vector2(1200, 1000))
		return
	var to: Vector2 = (en.position as Vector2) - (local.position as Vector2)
	world.aim_override = to   # always face the enemy...
	var want := 70.0 + float(en.radius)
	if to.length() > want + 20.0:
		local.bot_input = to.normalized()
	else:
		# ...while circling it (moving one way, looking another).
		local.bot_input = Vector2(-to.y, to.x).normalized() * _strafe
		_act_t += delta
		if _act_t > 0.6:
			_act_t = 0.0
			_strafe *= -1.0 if randf() < 0.3 else 1.0
			World.select_slot(0)
			world.use_item(en.position)


func _hunt(local: Variant, kind: String, delta: float) -> void:
	var en: Variant = _nearest_enemy(local.position, kind, 3000.0)
	if en == null:
		return
	var to: Vector2 = (en.position as Vector2) - (local.position as Vector2)
	world.aim_override = to
	if to.length() > 60.0 + float(en.radius):
		local.bot_input = to.normalized()
		return
	_act_t += delta
	if _act_t > 0.5:
		_act_t = 0.0
		if en.frozen:
			world.offhand()
			_note("jabbed a frozen %s" % kind)
		else:
			World.select_slot(0)
			world.use_item(en.position)


func _nearest_pickup(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	var pk: Dictionary = World.pickups.get(World.my_zone, {})
	for pid: int in pk:
		var p: Vector2 = pk[pid]
		if p.distance_to(from) < bd:
			bd = p.distance_to(from)
			best = p
	return best
