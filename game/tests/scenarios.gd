extends Node
## Mechanic tests that run over a real network connection: a test player joins a host
## started with --test, then drives each scenario with the same calls real input makes
## (dash, block, use, offhand, interact, equip, the item wheel) plus a few host test commands
## to set the scene (spawn an enemy, order an attack, set the weather or clock, teleport,
## wear a shield down). Covers attacks and telegraphs, dashes, the three block levels and
## shields breaking, fire, rain, lanterns, ice, chests and sets, stamina, aiming, darkness,
## fainting, sickle hitboxes, the item wheel, Pepper's lessons and house doors.
## Results go into the test report; tools/mp_test.py --scenarios prints them.

const Z = preload("res://game/data/zones.gd")
const Items = preload("res://game/data/items.gd")
const E = preload("res://game/data/enemies.gd")
const Avatar = preload("res://game/world/avatar.gd")
const HB = preload("res://game/combat/hitboxes.gd")
const Lessons = preload("res://game/data/lessons.gd")

var world: Variant
var results: Dictionary = {}
var done := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _wait(1.5)
	await _reset()
	var list := [
		"touch_bump", "burst_standing_gets_hit", "dash_has_no_iframes", "dash_out_dodges",
		"block_from_front", "block_from_behind_fails", "block_stops_a_bump_and_shoves", "holding_off_a_slime", "perfect_block_stuns", "charge_hits_in_line",
		"charge_into_cliff_dazes", "slam_cone_hits", "frost_wilt_needs_torch", "torch_sets_enemy_alight",
		"rain_puts_out_burning_enemy", "rain_snuffs_torch_then_relight", "raincoat_keeps_torch_lit",
		"lantern_burns_oil", "ice_melts_to_puddle_refills_can", "chest_gives_set_once", "wayfarer_set_bonus",
		"hermes_boots_faster", "sprint_and_dash_cost_stamina", "steel_toes_kick", "aim_independent_of_movement",
		"darkness_at_night_and_underground", "faint_then_wake",
		"sickle_hits_in_front_arc", "sickle_misses_behind", "sickle_reaches_big_body", "sickle_misses_out_of_reach",
		"wheel_grows_and_shrinks", "last_berry_leaves_the_wheel", "pepper_lessons",
		"block_tiers_on_a_bear", "shield_breaks_then_recovers", "spike_shield_hurts_attacker",
		"tower_shield_covers_the_side", "blocking_speed_depends_on_shield",
		"open_house_door", "locked_house_needs_key",
		"chop_tree_gives_lumber", "bush_slows_you_down", "cant_walk_through_a_mob",
	]
	var only := str(Net.opts.get("scenario", "all"))
	if only != "all" and only != "true":
		list = Array(only.split(","))
	for name: String in list:
		var r: Array = await call("_s_" + name)
		results[name] = {"ok": bool(r[0]), "detail": str(r[1])}
		Net.log_line("scenario %-36s %s  %s" % [name, "PASS" if r[0] else "FAIL", r[1]])
		await _reset()
	done = true


# ---------------------------------------------------------------- helpers

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _debug(cmd: String, args: Array = []) -> void:
	World.to_host(&"c_debug", [cmd, args])


func _me() -> Avatar:
	return world.local


func _hp() -> int:
	return int(World.vitals.get("hp", 0))


func _reset() -> void:
	var a := _me()
	a.want_block = false
	a.want_sprint = false
	a.bot_input = Vector2.ZERO
	world.aim_override = Vector2.ZERO
	_debug("clear")
	_debug("pause_ai", [true])
	_debug("weather", [World.my_zone, "clear"])
	_debug("heal")
	_debug("torch", [true])
	await _wait(0.4)
	# On a bad link the host's answer can take a while: start each scenario at full hearts.
	await _poll(func() -> bool: return _hp() == int(World.vitals.get("max_hp", 10)) and bool(World.vitals.get("torch_lit", false)), 3.0)
	a.stamina = float(a.max_orbs)


func _goto(zone: String, pos: Vector2) -> void:
	if World.my_zone != zone:
		_debug("goto", [zone, pos])
		await World.zone_entered
		await _wait(0.4)
	else:
		_debug("teleport", [pos])
		await _wait(0.3)
	_me().position = pos


func _spawn(kind: String, at: Vector2) -> Variant:
	_debug("spawn", [kind, at, true])
	for k in 20:
		await _wait(0.1)
		var best: Variant = null
		var bd := 60.0
		for eid: int in world.enemy_nodes:
			var n: Variant = world.enemy_nodes[eid]
			if is_instance_valid(n) and n.kind == kind and (n.position as Vector2).distance_to(at) < bd:
				bd = (n.position as Vector2).distance_to(at)
				best = n
		if best != null:
			return best
	return null


func _equip(item: String) -> void:
	if Items.find(World.inventory, item) < 0:
		_debug("give", [item, 1])
		await World.inventory_changed
	var slot := Items.find(World.inventory, item)
	World.to_host(&"c_equip", [slot])
	await World.inventory_changed
	await _wait(0.1)


## Orders an attack at the player and returns the time (msec) it will land on this screen.
func _attack(enemy: Variant) -> float:
	var before: int = world.pending.size()
	_debug("attack", [enemy.enemy_id, _me().position])
	for k in 30:
		await _wait(0.05)
		if world.pending.size() > before:
			return float(world.pending[world.pending.size() - 1]["strike"])
	return -1.0


func _until(t: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if t > now:
		await _wait(t - now)


## Waits until `cond` is true (or `timeout` seconds pass) and returns it.
func _poll(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout and not cond.call():
		await _wait(0.05)
		t += 0.05
	return cond.call()


## After a blow lands on this screen the host still has to agree and send the new hearts
## back: wait a round trip (longer on a bad link), then up to 1.5 s more for `expect`.
func _expect_hp(expect: int) -> void:
	var rtt: Array = World.stats["rtt_ms"]
	var last: float = float(rtt[rtt.size() - 1]) / 1000.0 if not rtt.is_empty() else 0.05
	await _wait(0.2 + last * 2.0)
	await _poll(func() -> bool: return _hp() == expect, 1.5)


func _gear_has(item: String) -> bool:
	return item in Items.equipped(World.equip)


# ---------------------------------------------------------------- scenarios

func _s_touch_bump() -> Array:
	await _goto("middlemost", Vector2(1700, 1100))
	var hp0 := _hp()
	await _spawn("wilt", _me().position + Vector2(10, 0))
	await _wait(0.8)
	await _expect_hp(hp0 - 1)
	return [_hp() == hp0 - 1, "bumping a Wilt: hp %d -> %d (expect -1)" % [hp0, _hp()]]


func _s_block_stops_a_bump_and_shoves() -> Array:
	# A slime walking into a raised shield does no damage, and gets shoved back off you.
	await _equip("pot_lid")
	await _goto("middlemost", Vector2(1700, 1100))
	var me := _me()
	world.aim_override = Vector2(1, 0)
	me.want_block = true
	await _wait(0.5)   # well past the Perfect/Great windows: a plain Regular block
	var hp0 := _hp()
	var b0: int = world.stats["blocked"]
	var w: Variant = await _spawn("wilt", me.position + Vector2(12, 0))
	await _wait(0.9)
	var dist: float = (w.position as Vector2).distance_to(me.position) if is_instance_valid(w) else 0.0
	me.want_block = false
	world.aim_override = Vector2.ZERO
	await _wait(0.3)
	var blocks: int = int(world.stats["blocked"]) - b0
	var ok: bool = _hp() == hp0 and dist > 50.0 and blocks >= 1
	return [ok, "bumped by a Wilt while blocking: hp %d -> %d, %d bump(s) taken on the lid, Wilt shoved to %.0f px away" % [hp0, _hp(), blocks, dist]]


func _s_holding_off_a_slime() -> Array:
	# Holding the shield up against a slime for several seconds: it keeps bumping and
	# getting shoved, but bumps are cheap, so you still have stamina and all your hearts.
	await _equip("pot_lid")
	await _goto("middlemost", Vector2(1700, 1100))
	var me := _me()
	world.aim_override = Vector2(1, 0)
	me.want_block = true
	await _wait(0.5)
	var hp0 := _hp()
	var b0: int = world.stats["blocked"]
	await _spawn("wilt", me.position + Vector2(12, 0))
	await _wait(4.0)
	var stamina: float = me.stamina
	var blocks: int = int(world.stats["blocked"]) - b0
	me.want_block = false
	world.aim_override = Vector2.ZERO
	await _wait(0.3)
	var ok: bool = _hp() == hp0 and stamina > 0.5 and blocks >= 1
	return [ok, "held a Wilt off for 4 s: hp %d -> %d, %d bumps blocked, %.1f stamina left" % [hp0, _hp(), blocks, stamina]]


func _s_burst_standing_gets_hit() -> Array:
	var me := _me()
	var p: Variant = await _spawn("puffcap", me.position + Vector2(60, 0))
	var hp0 := _hp()
	var strike := await _attack(p)
	await _until(strike + 0.4)
	await _expect_hp(hp0 - 2)
	return [_hp() == hp0 - 2, "stood in the spore circle: hp %d -> %d (expect -2)" % [hp0, _hp()]]


func _s_dash_has_no_iframes() -> Array:
	var me := _me()
	var p: Variant = await _spawn("puffcap", me.position + Vector2(60, 0))
	var hp0 := _hp()
	var strike := await _attack(p)
	# Dash across the circle so the dash is happening right as the burst lands.
	await _until(strike - 0.08)
	me.bot_input = Vector2(1, 0)
	var dashed := me.try_dash()
	await _wait(0.05)
	var dash_pos := me.position
	me.bot_input = Vector2.ZERO
	await _wait(0.5)
	var inside := dash_pos.distance_to(p.position) < 140.0
	await _expect_hp(hp0 - 2)
	return [dashed and inside and _hp() == hp0 - 2, "dashed through the burst (dash=%s, still inside=%s): hp %d -> %d" % [dashed, inside, hp0, _hp()]]


func _s_dash_out_dodges() -> Array:
	var me := _me()
	var p: Variant = await _spawn("puffcap", me.position + Vector2(60, 0))
	var hp0 := _hp()
	var strike := await _attack(p)
	await _until(strike - 0.5)
	me.bot_input = Vector2(-1, 0)
	me.try_dash()
	await _wait(0.25)
	me.bot_input = Vector2.ZERO
	await _until(strike + 0.4)
	var dist: float = me.position.distance_to(p.position)
	await _expect_hp(hp0)
	return [_hp() == hp0 and dist > 140.0, "dashed clear (%.0f px from the centre, circle 140): hp %d -> %d" % [dist, hp0, _hp()]]


func _s_block_from_front() -> Array:
	await _equip("pot_lid")
	var me := _me()
	var p: Variant = await _spawn("puffcap", me.position + Vector2(70, 0))
	world.aim_override = Vector2(1, 0)
	var hp0 := _hp()
	var strike := await _attack(p)
	await _until(strike - 0.7)
	me.want_block = true
	await _until(strike - 0.05)
	var st0: float = me.stamina
	await _wait(0.35)
	me.want_block = false
	var spent: float = st0 - me.stamina
	await _expect_hp(hp0 - 1)
	return [_hp() == hp0 - 1 and spent >= 0.9, "a Regular block with the lid stops half: hp %d -> %d (2 damage, 1 taken), stamina spent %.2f orbs" % [hp0, _hp(), spent]]


func _s_block_from_behind_fails() -> Array:
	var me := _me()
	var p: Variant = await _spawn("puffcap", me.position + Vector2(70, 0))
	world.aim_override = Vector2(-1, 0)
	var hp0 := _hp()
	var strike := await _attack(p)
	await _until(strike - 0.7)
	me.want_block = true
	await _until(strike + 0.35)
	me.want_block = false
	await _expect_hp(hp0 - 2)
	return [_hp() == hp0 - 2, "blocked facing away: hp %d -> %d (the lid only covers your front)" % [hp0, _hp()]]


func _s_perfect_block_stuns() -> Array:
	var me := _me()
	var p: Variant = await _spawn("puffcap", me.position + Vector2(70, 0))
	world.aim_override = Vector2(1, 0)
	var hp0 := _hp()
	var strike := await _attack(p)
	await _until(strike - 0.06)
	me.want_block = true
	await _until(strike + 0.3)
	me.want_block = false
	await _wait(0.2)
	var stunned: bool = is_instance_valid(p) and p.state == 4
	await _expect_hp(hp0)
	await _equip("torch")
	return [_hp() == hp0 and stunned, "lid up 0.06 s before the hit (Perfect): hp %d -> %d, enemy stunned=%s" % [hp0, _hp(), stunned]]


func _s_charge_hits_in_line() -> Array:
	var me := _me()
	var b: Variant = await _spawn("boar", me.position + Vector2(-250, 0))
	var hp0 := _hp()
	var strike := await _attack(b)
	await _until(strike + 0.8)
	await _expect_hp(hp0 - 3)
	return [_hp() == hp0 - 3, "stood in the charge line: hp %d -> %d (expect -3)" % [hp0, _hp()]]


func _s_charge_into_cliff_dazes() -> Array:
	# The Fernery's Canopy Ledge: a cliff face runs along y = 580..640 from x = 2150.
	await _goto("fernery", Vector2(2500, 690))
	var me := _me()
	var b: Variant = await _spawn("boar", Vector2(2500, 980))
	var strike := await _attack(b)    # aims at the player, who stands right under the cliff
	me.bot_input = Vector2(1, 0)       # step aside so the boar hits the cliff, not us
	await _wait(0.5)
	me.bot_input = Vector2.ZERO
	var dazed := false
	for k in 30:
		await _wait(0.1)
		if is_instance_valid(b) and b.state == 4:
			dazed = true
			break
	return [dazed, "charged at the cliff and stopped dazed=%s at y=%.0f" % [dazed, b.position.y if is_instance_valid(b) else -1.0]]


func _s_slam_cone_hits() -> Array:
	await _goto("middlemost", Vector2(1700, 1100))
	var me := _me()
	var bear: Variant = await _spawn("bear", me.position + Vector2(0, -120))
	var hp0 := _hp()
	var strike := await _attack(bear)
	await _until(strike + 0.4)
	await _expect_hp(hp0 - 4)
	return [_hp() == hp0 - 4, "inside the bear's slam wedge: hp %d -> %d (expect -4)" % [hp0, _hp()]]


func _s_frost_wilt_needs_torch() -> Array:
	var me := _me()
	var fw: Variant = await _spawn("frost_wilt", me.position + Vector2(50, 0))
	world.aim_override = Vector2(1, 0)
	World.select_slot(0)
	world.use_item(fw.position)
	await _wait(0.4)
	var after_sickle: float = fw.hp_frac
	world.offhand()
	await _wait(0.4)
	var thawed: bool = not fw.frozen
	me.stamina = float(me.max_orbs)
	world.use_item(fw.position)
	await _wait(0.4)
	var after: float = fw.hp_frac if is_instance_valid(fw) else 0.0
	return [after_sickle >= 0.999 and thawed and after < 0.999, "sickle on ice: hp %.2f; torch jab thawed=%s; sickle again: hp %.2f" % [after_sickle, thawed, after]]


func _s_torch_sets_enemy_alight() -> Array:
	var me := _me()
	var w: Variant = await _spawn("boar", me.position + Vector2(55, 0))
	world.aim_override = Vector2(1, 0)
	world.offhand()
	await _wait(0.4)
	var burning: bool = w.burning
	var hp_a: float = w.hp_frac
	await _wait(2.2)
	var hp_b: float = w.hp_frac if is_instance_valid(w) else 0.0
	return [burning and hp_b < hp_a, "torch jab: burning=%s, hp %.2f -> %.2f over 2 s" % [burning, hp_a, hp_b]]


func _s_rain_puts_out_burning_enemy() -> Array:
	var me := _me()
	var w: Variant = await _spawn("boar", me.position + Vector2(55, 0))
	world.aim_override = Vector2(1, 0)
	world.offhand()
	await _wait(0.4)
	var lit: bool = w.burning
	_debug("weather", [World.my_zone, "rain"])
	await _wait(0.6)
	return [lit and not w.burning, "set alight=%s, then rain: still burning=%s" % [lit, w.burning]]


func _s_rain_snuffs_torch_then_relight() -> Array:
	await _goto("middlemost", Vector2(1720, 1235))   # next to the campfire
	_debug("weather", ["middlemost", "rain"])
	await _wait(3.2)
	var out: bool = await _poll(func() -> bool: return not bool(World.vitals.get("torch_lit", true)), 2.0)
	_debug("weather", ["middlemost", "clear"])
	await _wait(0.2)
	world.interact()
	var relit: bool = await _poll(func() -> bool: return bool(World.vitals.get("torch_lit", false)), 2.0)
	return [out and relit, "3.5 s of rain: torch out=%s; E at the campfire: relit=%s" % [out, relit]]


func _s_raincoat_keeps_torch_lit() -> Array:
	await _equip("raincoat")
	_debug("weather", ["middlemost", "rain"])
	await _wait(3.8)
	var lit: bool = bool(World.vitals.get("torch_lit", false))
	_debug("weather", ["middlemost", "clear"])
	World.to_host(&"c_unequip", ["chest"])
	await World.inventory_changed
	return [lit, "3.8 s of rain in a raincoat: torch still lit=%s" % lit]


func _s_lantern_burns_oil() -> Array:
	await _equip("lantern")
	var oil0 := Items.count_of(World.inventory, "oil")
	_debug("fuel", [3.0])
	await _wait(0.4)
	var f0 := float(World.vitals.get("fuel", 0.0))
	await _wait(1.5)   # time runs 20x in tests, so a few percent burns per second
	var oil1 := Items.count_of(World.inventory, "oil")
	var f1 := float(World.vitals.get("fuel", 0.0))
	var lit := World.my_lights() & 2 != 0
	await _equip("torch")
	return [oil1 == oil0 - 1 and f1 > 50.0 and lit, "lantern ran dry from %.0f%% and refilled itself: oil %d -> %d, fuel now %.0f%%, lit=%s" % [f0, oil0, oil1, f1, lit]]


func _s_ice_melts_to_puddle_refills_can() -> Array:
	await _goto("mossmouth", Vector2(860, 1400))
	var me := _me()
	var frozen0: int = World.frozen_ice("mossmouth").size()
	world.aim_override = Vector2(-1, 0)
	await _wait(0.2)
	world.offhand()
	await _wait(0.5)
	var frozen1: int = World.frozen_ice("mossmouth").size()
	_debug("set_can", [0])
	await World.inventory_changed
	world.interact()
	await World.inventory_changed
	var at := Items.locate(World.inventory, World.wheel, "can")
	var can := Items.count_at(World.wheel if at["in"] == "wheel" else World.inventory, int(at["i"]))
	me.bot_input = Vector2(-1, 0)
	await _wait(0.8)
	me.bot_input = Vector2.ZERO
	var passed: bool = me.position.x < 740.0
	return [frozen1 < frozen0 and can == Items.CAN_MAX and passed, "ice blocks %d -> %d; can refilled from the puddle to %d; walked through the gap=%s" % [frozen0, frozen1, can, passed]]


func _s_chest_gives_set_once() -> Array:
	await _goto("mossmouth", Vector2(420, 1450))
	world.interact()
	await World.inventory_changed
	var got := Items.count_of(World.inventory, "miner_helmet") + Items.count_of(World.inventory, "overalls") + Items.count_of(World.inventory, "steel_toes")
	world.interact()
	await _wait(0.5)
	var again := Items.count_of(World.inventory, "miner_helmet")
	return [got == 3 and again == 1, "first open gave %d Miner's Set pieces; second open left %d helmet (no duplicates)" % [got, again]]


func _s_wayfarer_set_bonus() -> Array:
	var me := _me()
	for item in ["leaf_hood", "raincoat", "wellies"]:
		await _equip(item)
	var bonus: bool = "wayfarer" in Items.full_sets(World.equip)
	var cost: float = me.dash_cost
	for slot in ["helmet", "chest", "shoes"]:
		World.to_host(&"c_unequip", [slot])
		await World.inventory_changed
	return [bonus and absf(cost - 0.5) < 0.01, "all three Wayfarer pieces worn: bonus=%s, dash costs %.1f orb" % [bonus, cost]]


func _measure_speed() -> float:
	var me := _me()
	await _wait(0.1)
	var x0: float = me.position.x
	me.bot_input = Vector2(1, 0)
	await _wait(0.5)
	me.bot_input = Vector2.ZERO
	var dx: float = me.position.x - x0
	await _wait(0.1)
	me.position.x = x0
	return dx / 0.5


func _s_hermes_boots_faster() -> Array:
	await _goto("middlemost", Vector2(1600, 1180))
	var base := await _measure_speed()
	await _equip("hermes_boots")
	var fast := await _measure_speed()
	World.to_host(&"c_unequip", ["shoes"])
	await World.inventory_changed
	return [fast / base > 1.35, "walking %.0f px/s; in Hermes Boots %.0f px/s (x%.2f)" % [base, fast, fast / base]]


func _s_sprint_and_dash_cost_stamina() -> Array:
	var me := _me()
	me.stamina = float(me.max_orbs)
	var s0: float = me.stamina
	me.want_sprint = true
	me.bot_input = Vector2(1, 0)
	await _wait(0.8)
	me.want_sprint = false
	me.bot_input = Vector2.ZERO
	var after_sprint: float = me.stamina
	me.try_dash()
	var after_dash: float = me.stamina
	me.stamina = 0.2
	var refused: bool = not me.try_dash()
	await _wait(2.0)
	var regen: float = me.stamina
	return [s0 - after_sprint > 0.6 and absf(after_sprint - after_dash - 1.0) < 0.05 and refused and regen > 1.0,
		"sprint 0.8 s: %.2f -> %.2f orbs; dash: -%.2f; dash with 0.2 left refused=%s; 2 s later %.2f" % [s0, after_sprint, after_sprint - after_dash, refused, regen]]


func _s_steel_toes_kick() -> Array:
	await _equip("steel_toes")
	var me := _me()
	var p: Variant = await _spawn("puffcap", me.position + Vector2(160, 0))
	var hp0: float = p.hp_frac
	me.want_sprint = true
	me.bot_input = Vector2(1, 0)
	await _wait(0.6)
	me.want_sprint = false
	me.bot_input = Vector2.ZERO
	await _wait(0.3)
	var hp1: float = p.hp_frac if is_instance_valid(p) else 0.0
	World.to_host(&"c_unequip", ["shoes"])
	await World.inventory_changed
	return [hp1 < hp0, "sprinted into a Puffcap in Steel-Toed Boots: its hp %.2f -> %.2f" % [hp0, hp1]]


func _s_aim_independent_of_movement() -> Array:
	var me := _me()
	var w: Variant = await _spawn("wilt", me.position + Vector2(-50, 0))
	world.aim_override = Vector2(-1, 0)   # aim left...
	me.bot_input = Vector2(1, 0)          # ...while walking right
	await _wait(0.15)
	var facing: Vector2 = me.facing
	World.select_slot(0)
	me.stamina = float(me.max_orbs)
	world.use_item(me.position + Vector2(-60, 0))
	await _wait(0.4)
	me.bot_input = Vector2.ZERO
	var hit: bool = not is_instance_valid(w) or w.hp_frac < 0.999
	return [facing.x < -0.9 and hit, "walking right while aiming left: facing (%.2f, %.2f); sickle hit the Wilt behind=%s" % [facing.x, facing.y, hit]]


func _brightness() -> float:
	var c: Color = world.day_night.color
	return (c.r + c.g + c.b) / 3.0


func _s_darkness_at_night_and_underground() -> Array:
	await _goto("middlemost", Vector2(1600, 1180))
	_debug("clock", [12.0 * 60.0])
	await _wait(3.0)
	var noon := _brightness()
	_debug("clock", [0.0])
	await _wait(3.0)
	var midnight := _brightness()
	await _goto("mossmouth", Vector2(1100, 400))
	_debug("clock", [12.0 * 60.0])
	await _wait(3.0)
	var cave_noon := _brightness()
	var torch := World.my_lights() & 1 != 0
	return [noon > 0.9 and midnight < 0.1 and cave_noon < 0.1 and torch,
		"brightness: Middlemost noon %.2f, midnight %.2f; Mossmouth at noon %.2f; torch light on=%s" % [noon, midnight, cave_noon, torch]]


func _s_faint_then_wake() -> Array:
	await _goto("middlemost", Vector2(1700, 1100))
	_debug("set_hp", [1])
	await _wait(0.3)
	var me := _me()
	await _spawn("wilt", me.position + Vector2(10, 0))
	await _wait(0.8)
	var fainted := bool(World.vitals.get("fainted", false))
	_debug("clear")
	await _wait(10.5)
	var woke := not bool(World.vitals.get("fainted", true)) and _hp() > 0
	return [fainted and woke, "hit at 1 hp: fainted=%s; 10 s later woke up=%s with hp %d" % [fainted, woke, _hp()]]


# ---------------------------------------------------------------- hitboxes

## Swings the sickle facing right at an enemy placed at `offset`; returns [hit, hp before, after].
func _swing_at(kind: String, offset: Vector2) -> Array:
	await _goto("middlemost", Vector2(1950, 1180))
	var me := _me()
	World.select_slot(0)
	world.aim_override = Vector2(1, 0)
	var en: Variant = await _spawn(kind, me.position + offset)
	await _wait(0.3)
	var hp0: float = en.hp_frac
	me.stamina = float(me.max_orbs)
	world.use_item(me.position + Vector2(100, 0))
	var hit: bool = await _poll(func() -> bool: return not is_instance_valid(en) or en.hp_frac < hp0, 1.2)
	var hp1: float = en.hp_frac if is_instance_valid(en) else 0.0
	world.aim_override = Vector2.ZERO
	return [hit, hp0, hp1]


func _s_sickle_hits_in_front_arc() -> Array:
	# The Wilt's centre is beyond the sickle's reach, but its body overlaps the swing.
	var r := await _swing_at("wilt", Vector2(HB.SICKLE_RANGE + 10.0, 30.0))
	return [r[0], "Wilt %d px away, 20 degrees off centre (body inside the arc): hit=%s, hp %.2f -> %.2f" % [
		int(Vector2(HB.SICKLE_RANGE + 10.0, 30.0).length()), r[0], r[1], r[2]]]


func _s_sickle_misses_behind() -> Array:
	var r := await _swing_at("wilt", Vector2(-45, 0))
	return [not r[0], "Wilt right behind you (45 px), swinging forwards: hit=%s (should miss)" % r[0]]


func _s_sickle_reaches_big_body() -> Array:
	# A bear is big: its centre is 110 px away but the edge of its body is inside the swing.
	var r := await _swing_at("bear", Vector2(110, 0))
	return [r[0], "Mossback Bear 110 px away (body edge at %d px, reach %d): hit=%s" % [110 - 44, int(HB.SICKLE_RANGE), r[0]]]


func _s_sickle_misses_out_of_reach() -> Array:
	var r := await _swing_at("wilt", Vector2(104, 0))
	return [not r[0], "Wilt 104 px away (body edge at 84 px, reach %d): hit=%s (should miss)" % [int(HB.SICKLE_RANGE), r[0]]]


# ---------------------------------------------------------------- item wheel

func _s_wheel_grows_and_shrinks() -> Array:
	var n0 := World.wheel.size()
	World.to_host(&"c_wheel_add", [Items.find(World.inventory, "can")])
	await World.inventory_changed
	var n1 := World.wheel.size()
	# Gear can't go in the wheel: nothing changes.
	var gear := ""
	for id in ["hermes_boots", "pot_helmet", "lantern", "stamina_acorn"]:
		if Items.find(World.inventory, id) >= 0:
			gear = id
			break
	World.to_host(&"c_wheel_add", [Items.find(World.inventory, gear)])
	await _wait(0.6)
	var n2 := World.wheel.size()
	World.to_host(&"c_wheel_remove", [Items.find(World.wheel, "can")])
	await World.inventory_changed
	var n3 := World.wheel.size()
	var back := Items.find(World.inventory, "can") >= 0
	return [n1 == n0 + 1 and n2 == n1 and n3 == n0 and back,
		"wheel %d -> %d segments with the can; %s refused (%d); can back in the bag -> %d segments" % [n0, n1, gear, n2, n3]]


func _s_last_berry_leaves_the_wheel() -> Array:
	World.to_host(&"c_wheel_add", [Items.find(World.inventory, "popberry")])
	await World.inventory_changed
	var at := Items.find(World.wheel, "popberry")
	var n0 := World.wheel.size()
	var berries := Items.count_at(World.wheel, at)
	World.select_slot(at)
	for k in berries:
		world.use_item(_me().position + Vector2(200, 0))
		await World.inventory_changed
	var gone := Items.find(World.wheel, "popberry") < 0
	return [gone and World.wheel.size() == n0 - 1 and World.selected < World.wheel.size(),
		"threw all %d popberries: wheel %d -> %d segments, now holding %s" % [berries, n0, World.wheel.size(), World.held_item()]]


# ---------------------------------------------------------------- Pepper

func _s_pepper_lessons() -> Array:
	await _goto("middlemost", Vector2(1660, 1110))   # Pepper stands at (1660, 1050)
	var said: Array = []
	var on_say := func(_who: String, lines: Array) -> void: said.append_array(lines)
	World.dialogue.connect(on_say)
	var i0 := int(World.vitals.get("lesson", {}).get("i", 0))
	world.interact()
	await _poll(func() -> bool: return int(World.vitals.get("lesson", {}).get("i", 0)) >= 1, 2.0)
	var i1 := int(World.vitals.get("lesson", {}).get("i", 0))
	for id in ["can", "popberry_seed"]:
		if Items.find(World.wheel, id) < 0:
			World.to_host(&"c_wheel_add", [Items.find(World.inventory, id)])
			await World.inventory_changed
	await _poll(func() -> bool: return int(World.vitals.get("lesson", {}).get("i", 0)) >= 2, 2.0)
	var lesson: Dictionary = World.vitals.get("lesson", {})
	World.dialogue.disconnect(on_say)
	return [i0 == 0 and i1 >= 1 and int(lesson.get("i", 0)) == 2 and said.size() >= 3,
		"before %d; said hello -> lesson %d; filled the wheel -> lesson %d (%s); Pepper said %d lines" % [
			i0, i1, int(lesson.get("i", 0)), str(lesson.get("title", "")), said.size()]]


# ---------------------------------------------------------------- shields

func _rtt() -> float:
	var rtt: Array = World.stats["rtt_ms"]
	return float(rtt[rtt.size() - 1]) / 1000.0 if not rtt.is_empty() else 0.05


func _s_block_tiers_on_a_bear() -> Array:
	await _equip("pot_lid")
	await _goto("middlemost", Vector2(1950, 1180))
	var me := _me()
	world.aim_override = Vector2(0, -1)
	var bear: Variant = await _spawn("bear", me.position + Vector2(0, -120))
	var out: Array = []
	for early: float in [0.7, 0.2, 0.05]:
		var hit := await _slam_tier(bear, early)
		out.append([early, hit[0], hit[1]])
	world.aim_override = Vector2.ZERO
	# The bear hits for 4. Regular stops 50% (2 taken), Great 75% (1), Perfect 100% (0).
	var ok: bool = out[0][2] == 1 and out[0][1] == 2 and out[1][2] == 2 and out[1][1] == 1 and out[2][2] == 3 and out[2][1] == 0
	var sh: Dictionary = World.vitals.get("shield", {})
	return [ok, "raised 0.7s early: %s, took %d; 0.2s: %s, took %d; 0.05s: %s, took %d (bear hits for 4). Pot Lid now %.1f/%d" % [
		Items.BLOCK_NAMES[out[0][2]], out[0][1], Items.BLOCK_NAMES[out[1][2]], out[1][1], Items.BLOCK_NAMES[out[2][2]], out[2][1],
		float(sh.get("hp", 0)), int(sh.get("max", 0))]]


## Like _slam_blocked but returns [damage taken, tier] measured around the heal.
func _slam_tier(bear: Variant, early: float) -> Array:
	var me := _me()
	me.stamina = float(me.max_orbs)
	var hp0 := _hp()
	var b0: int = world.stats["blocked"]
	var p0: int = world.stats["perfect"]
	var g0: int = world.stats["great"]
	var strike := await _attack(bear)
	await _until(strike - early)
	me.want_block = true
	await _until(strike + 0.3)
	me.want_block = false
	await _wait(0.3 + _rtt() * 2.0)
	await _poll(func() -> bool: return _hp() != hp0, 0.8)
	var taken := hp0 - _hp()
	var tier := 0
	if int(world.stats["perfect"]) > p0:
		tier = 3
	elif int(world.stats["great"]) > g0:
		tier = 2
	elif int(world.stats["blocked"]) > b0:
		tier = 1
	_debug("heal")
	await _poll(func() -> bool: return _hp() == int(World.vitals.get("max_hp", 10)), 2.0)
	await _wait(1.8)   # the bear recovers before it can slam again
	return [taken, tier]


func _s_shield_breaks_then_recovers() -> Array:
	await _equip("pot_lid")
	var me := _me()
	world.aim_override = Vector2(1, 0)
	var p: Variant = await _spawn("puffcap", me.position + Vector2(70, 0))
	var strike := await _attack(p)
	await _until(strike - 0.7)
	_debug("shield_hp", [0.1, 3.0])   # nearly worn out, and held there so lag can't let it regrow
	me.want_block = true
	await _until(strike + 0.3)
	var broke: bool = await _poll(func() -> bool: return float(World.vitals.get("shield", {}).get("broken", 0.0)) > 0.0, 1.5)
	var can_block_while_broken: bool = me.blocking
	me.want_block = false
	var hp0 := _hp()
	var strike2 := await _attack(p)
	await _until(strike2 - 0.7)
	me.want_block = true
	await _until(strike2 + 0.3)
	me.want_block = false
	await _expect_hp(hp0 - 2)
	var full_hit := _hp() == hp0 - 2
	var sh := Items.shield("pot_lid")
	await _wait(float(sh["break_time"]) + 1.5)
	var back: Dictionary = World.vitals.get("shield", {})
	world.aim_override = Vector2.ZERO
	return [broke and not can_block_while_broken and full_hit and float(back.get("broken", 1.0)) <= 0.0 and float(back.get("hp", 0.0)) > 0.0,
		"shield nearly worn out broke on a block=%s; could block while broken=%s; next burst hit in full=%s; %ds later: broken=%.1fs, health %.1f/%d and growing" % [
			broke, can_block_while_broken, full_hit, int(float(sh["break_time"]) + 1.5), float(back.get("broken", 0.0)), float(back.get("hp", 0.0)), int(sh["hp"])]]


func _s_spike_shield_hurts_attacker() -> Array:
	await _equip("spike_shield")
	var me := _me()
	world.aim_override = Vector2(1, 0)
	var p: Variant = await _spawn("puffcap", me.position + Vector2(70, 0))
	await _wait(0.3)
	var ehp0: float = p.hp_frac
	var strike := await _attack(p)
	await _until(strike - 0.7)
	me.want_block = true
	await _until(strike + 0.3)
	me.want_block = false
	var hurt: bool = await _poll(func() -> bool: return not is_instance_valid(p) or p.hp_frac < ehp0, 1.5)
	var ehp1: float = p.hp_frac if is_instance_valid(p) else 0.0
	world.aim_override = Vector2.ZERO
	return [hurt, "blocked a Puffcap's burst with the Spike Shield: the Puffcap's hp %.2f -> %.2f" % [ehp0, ehp1]]


## A Puffcap 60 degrees off to the side. Returns damage taken while blocking forwards.
func _side_burst(shield: String) -> int:
	await _equip(shield)
	await _wait(0.5)
	var me := _me()
	world.aim_override = Vector2(1, 0)
	var off := Vector2.from_angle(deg_to_rad(60.0)) * 70.0
	var p: Variant = await _spawn("puffcap", me.position + off)
	var hp0 := _hp()
	var strike := await _attack(p)
	await _until(strike - 0.7)
	me.want_block = true
	await _until(strike + 0.3)
	me.want_block = false
	await _wait(0.4 + _rtt() * 2.0)
	await _poll(func() -> bool: return _hp() != hp0, 0.8)
	var taken := hp0 - _hp()
	_debug("clear")
	_debug("heal")
	await _poll(func() -> bool: return _hp() == int(World.vitals.get("max_hp", 10)), 2.0)
	world.aim_override = Vector2.ZERO
	return taken


func _s_tower_shield_covers_the_side() -> Array:
	var lid := await _side_burst("pot_lid")
	_debug("give", ["tower_shield", 1])
	await World.inventory_changed
	var tower := await _side_burst("tower_shield")
	return [lid == 2 and tower < 2, "burst from 60 degrees to the side: Pot Lid (covers 70 degrees) took %d; Tower Shield (covers 150) took %d" % [lid, tower]]


func _blocking_speed(shield: String) -> float:
	await _equip(shield)
	await _wait(0.3)
	var me := _me()
	world.aim_override = Vector2(0, 1)
	me.stamina = float(me.max_orbs)
	me.want_block = true
	await _wait(0.1)
	var x0: float = me.position.x
	me.bot_input = Vector2(1, 0)
	await _wait(0.5)
	me.bot_input = Vector2.ZERO
	me.want_block = false
	var v: float = (me.position.x - x0) / 0.5
	me.position.x = x0
	world.aim_override = Vector2.ZERO
	return v


func _s_blocking_speed_depends_on_shield() -> Array:
	await _goto("middlemost", Vector2(1600, 1180))
	_debug("give", ["buckler", 1])
	await World.inventory_changed
	var light := await _blocking_speed("buckler")
	if Items.find(World.inventory, "tower_shield") < 0 and str(World.equip.get("offhand", "")) != "tower_shield":
		_debug("give", ["tower_shield", 1])
		await World.inventory_changed
	var heavy := await _blocking_speed("tower_shield")
	await _equip("torch")
	return [light > heavy * 2.0, "walking while blocking: Buckler %.0f px/s, Tower Shield %.0f px/s" % [light, heavy]]


# ---------------------------------------------------------------- houses

func _s_open_house_door() -> Array:
	await _goto("middlemost", Vector2(300, 370))   # Pepper's Cottage doorstep
	world.interact()
	await World.zone_entered
	var inside := World.my_zone
	await _wait(0.5)
	_me().bot_input = Vector2(0, 1)   # walk onto the doormat
	await World.zone_entered
	_me().bot_input = Vector2.ZERO
	var out := World.my_zone
	await _wait(0.5)
	return [inside == "house_pepper" and out == "middlemost",
		"E at Pepper's Cottage door -> %s; walked onto the doormat -> %s at %s" % [inside, out, _me().position.round()]]


func _s_locked_house_needs_key() -> Array:
	await _goto("middlemost", Vector2(1900, 372))   # the Clockmaker's doorstep
	world.interact()
	await _wait(1.0)
	var stayed := World.my_zone == "middlemost" and not World.unlocked.has("house_clock")
	_debug("give", ["brass_key", 1])
	await World.inventory_changed
	world.interact()
	await World.zone_entered
	var inside := World.my_zone
	var unlocked := World.unlocked.has("house_clock")
	# Inside, the chest has the Tower Shield.
	await _goto("house_clock", Vector2(750, 230))
	world.interact()
	await World.inventory_changed
	var got := Items.find(World.inventory, "tower_shield") >= 0 or str(World.equip.get("offhand", "")) == "tower_shield"
	return [stayed and inside == "house_clock" and unlocked and got,
		"without the key: stayed outside=%s; with the Brass Key: inside %s, door unlocked for everyone=%s; chest gave a Tower Shield=%s" % [stayed, inside, unlocked, got]]


func _s_chop_tree_gives_lumber() -> Array:
	var zid := "middlemost"
	var trees := Z.tree_sites(zid)
	if trees.is_empty():
		return [false, "no trees in middlemost"]
	var t: Dictionary = trees[0]
	var tpos: Vector2 = t["pos"]
	var stand := tpos + Vector2(0, 40)             # just below the trunk, within sickle reach
	await _goto(zid, stand)
	World.select_slot(0)                           # the sickle
	world.aim_override = (tpos - stand).normalized()
	await _wait(0.2)
	var me := _me()
	var before := World.count_mine("lumber")
	for k in 5:                                     # TREE_CHOPS swings fells it
		me.stamina = float(me.max_orbs)
		world.use_item(tpos)
		await _wait(0.35)
	world.aim_override = Vector2.ZERO
	var idx := int(t["i"])
	var felled: bool = (World.stumps.get(zid, {}) as Dictionary).has(idx)
	var gained := World.count_mine("lumber") - before
	var stump_blocks: bool = World.tree_solids(zid).any(func(s: Array) -> bool: return (s[0] as Vector2).distance_to(tpos) < 1.0)
	_debug("regrow")
	var regrew := await _poll(func() -> bool: return not (World.stumps.get(zid, {}) as Dictionary).has(idx), 2.0)
	var blocks_again: bool = World.tree_solids(zid).any(func(s: Array) -> bool: return (s[0] as Vector2).distance_to(tpos) < 1.0)
	var ok := felled and gained >= 1 and not stump_blocks and regrew and blocks_again
	return [ok, "felled=%s, +%d lumber, stump blocks=%s (want false), regrew=%s, blocks again=%s" % [felled, gained, stump_blocks, regrew, blocks_again]]


func _s_cant_walk_through_a_mob() -> Array:
	await _goto("middlemost", Vector2(1950, 1180))
	var me := _me()
	var en: Variant = await _spawn("wilt", me.position + Vector2(120, 0))
	if en == null:
		return [false, "no wilt spawned"]
	await _wait(0.2)
	var body := E.body_radius("wilt")
	# Walk straight at the wilt for a while; the body should stop us short of its centre.
	me.bot_input = Vector2(1, 0)
	var min_gap := 9999.0
	for k in 25:
		await _wait(0.06)
		if not is_instance_valid(en):
			break
		min_gap = minf(min_gap, me.position.distance_to(en.position))
	me.bot_input = Vector2.ZERO
	var kept_out := is_instance_valid(en) and min_gap >= body - 2.0
	return [kept_out, "closest we got to the wilt centre: %.0f px (body %.0f); blocked=%s" % [min_gap, body, kept_out]]


func _s_bush_slows_you_down() -> Array:
	var zid := "middlemost"
	var bushes := Z.bush_sites(zid)
	if bushes.is_empty():
		return [false, "no bushes in middlemost"]
	# A bush never blocks, but standing in one cuts your speed.
	var at_bush := Z.bush_slow(zid, bushes[0])
	var in_open := Z.bush_slow(zid, bushes[0] + Vector2(700, 700))
	var blocks: bool = Z.blocked(zid, bushes[0], 14.0, [], [])
	var ok := at_bush < 1.0 and is_equal_approx(in_open, 1.0) and not blocks
	return [ok, "in a bush speed x%.2f, open ground x%.2f, bush blocks movement=%s (want false)" % [at_bush, in_open, blocks]]
