extends Node2D
## The game screen. Shows the zone this player is in; the host keeps the other zones
## running. Sends this player's movement to the host 20 times a second and turns the
## host's snapshots into remote players and enemies.
##
## Combat is decided where the player can see it: when an enemy telegraph fills up, this
## screen checks whether *you* were inside its hitbox (game/combat/hitboxes.gd), how well
## you blocked it, or whether you'd already got out, and tells the host. Bumping into an
## enemy works the same way.
##
## Input: everything is listed on the controls screen (game/ui/controls_panel.gd, F1).
## Esc opens the menu from anywhere; F3 shows the hitbox debug view.

const Z = preload("res://game/data/zones.gd")
const Items = preload("res://game/data/items.gd")
const E = preload("res://game/data/enemies.gd")
const HB = preload("res://game/combat/hitboxes.gd")
const HitboxDebug = preload("res://game/world/hitbox_debug.gd")
const Avatar = preload("res://game/world/avatar.gd")
const EnemyView = preload("res://game/world/enemy_view.gd")
const Telegraph = preload("res://game/world/telegraph.gd")
const Fx = preload("res://game/world/fx.gd")
const Bot = preload("res://game/tests/test_bot.gd")

## A bump on the shield costs this share of the shield's stamina cost (see _got_hit).
const CONTACT_BLOCK_COST := 0.35
const ZoneView = preload("res://game/world/zone_view.gd")
const PinLayer = preload("res://game/world/pin_layer.gd")
const NpcView = preload("res://game/world/npc_view.gd")
const DayNight = preload("res://game/world/day_night.gd")
const WeatherFx = preload("res://game/world/weather_fx.gd")

const STATE_HZ := 20.0

@onready var zone_view: ZoneView = $Zone
@onready var entities: Node2D = $Entities
@onready var pin_layer: PinLayer = $Pins
@onready var camera: Camera2D = $Camera2D
@onready var day_night: DayNight = $DayNight
@onready var weather_fx: WeatherFx = $WeatherLayer/WeatherFx
@onready var hud: Variant = $HUD

var local: Avatar
var remotes: Dictionary = {}       # peer -> Avatar
var enemy_nodes: Dictionary = {}   # enemy id -> EnemyView
var pending: Array = []            # telegraphed attacks waiting to land: see _on_telegraph
var mouse_idle := 99.0
var aim_override := Vector2.ZERO   # bots aim with this
var telegraph_layer: CanvasLayer
var hitbox_debug: HitboxDebug
var stats := {"hits": 0, "blocked": 0, "perfect": 0, "great": 0, "dodged": 0, "kicks": 0, "dashes": 0, "strafe_s": 0.0, "night_lit_s": 0.0, "night_s": 0.0}
var _state_t := 0.0
var _travel_cooldown := 0.0
var _touch_cd := 0.0
var _kick_cd := 0.0


func _ready() -> void:
	World.snapshot.connect(_on_snapshot)
	World.zone_entered.connect(_on_zone_entered)
	World.fx.connect(_on_fx)
	World.telegraph.connect(_on_telegraph)
	World.selection_changed.connect(_on_gear_changed)
	World.inventory_changed.connect(_on_gear_changed)
	World.vitals_changed.connect(_on_gear_changed)
	World.teleported.connect(_on_teleported)
	World.lift_moved.connect(_on_lift_moved)
	telegraph_layer = CanvasLayer.new()
	telegraph_layer.name = "Telegraphs"
	telegraph_layer.layer = 1
	telegraph_layer.follow_viewport_enabled = true
	add_child(telegraph_layer)
	hitbox_debug = HitboxDebug.new()
	hitbox_debug.world = self
	hitbox_debug.visible = false
	add_child(hitbox_debug)
	local = Avatar.new()
	local.is_local = true
	local.peer_id = World.me()
	local.display_name = Net.player_name(local.peer_id)
	local.color = Net.player_color(local.peer_id)
	entities.add_child(local)
	hud.world = self
	_on_gear_changed()
	local.stamina = float(local.max_orbs)
	_on_zone_entered(World.my_zone, World.arrive_pos)
	if Net.opts.has("bot"):
		var bot := Bot.new()
		bot.name = "Bot"
		bot.world = self
		add_child(bot)
	if Net.opts.has("scenario"):
		var sc: Node = load("res://game/tests/scenarios.gd").new()
		sc.name = "Scenarios"
		sc.set("world", self)
		add_child(sc)


func _on_gear_changed() -> void:
	local.item = World.held_item()
	local.apply_gear(World.equip)
	local.lights = World.my_lights()
	local.shield_broken = float(World.vitals.get("shield", {}).get("broken", 0.0)) > 0.0
	local.fainted = bool(World.vitals.get("fainted", false))
	local.hp_frac = float(World.vitals.get("hp", 10)) / maxf(float(World.vitals.get("max_hp", 10)), 1.0)


func _on_teleported(pos: Vector2) -> void:
	local.position = pos
	camera.position = pos
	camera.reset_smoothing()


func _on_lift_moved(zid: String, lid: String, from_end: String, to_end: String, seconds: float, riders: Array) -> void:
	if zid != World.my_zone:
		return
	zone_view.animate_lift(lid, from_end, to_end, seconds)
	Sound.play("lift", 0.8)
	if World.me() in riders:
		var def := Z.lift_def(zid, lid)
		local.ride(def[from_end], def[to_end], seconds)


func _on_zone_entered(zid: String, at: Vector2) -> void:
	if Z.is_interior(zid) or Z.is_interior(local.zone):
		Sound.play("door")
	for id: int in remotes:
		(remotes[id] as Node).queue_free()
	remotes.clear()
	for eid: int in enemy_nodes:
		if is_instance_valid(enemy_nodes[eid]):
			(enemy_nodes[eid] as Node).queue_free()
	enemy_nodes.clear()
	pending.clear()
	for c in entities.get_children():
		if c != local:
			c.queue_free()
	for c in telegraph_layer.get_children():
		c.queue_free()
	zone_view.build(zid)
	for npc: Dictionary in Z.zone(zid).get("npcs", []):
		var n := NpcView.new()
		n.npc_name = str(npc["name"])
		n.position = npc["pos"]
		n.world = self
		entities.add_child(n)
	pin_layer.zone = zid
	day_night.zone = zid
	weather_fx.zone = zid
	var size := Z.size_of(zid)
	local.zone = zid
	local.riding = false
	local.position = at
	camera.limit_left = 0
	camera.limit_top = -90   # room for the head and name tag of someone at the top edge
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)
	if Z.is_interior(zid):
		# Rooms are smaller than the screen: keep the camera on you, so the doormat at the
		# bottom isn't hidden under the item bar.
		camera.limit_left = -400
		camera.limit_top = -400
		camera.limit_right = int(size.x) + 400
		camera.limit_bottom = int(size.y) + 400
	camera.position = at
	camera.reset_smoothing()
	_travel_cooldown = 1.0
	_send_state()
	hud.on_zone_entered(zid)


func _process(delta: float) -> void:
	camera.position = local.position
	mouse_idle += delta
	_touch_cd = maxf(_touch_cd - delta, 0.0)
	_kick_cd = maxf(_kick_cd - delta, 0.0)
	_update_aim()
	# For the test report: time spent moving one way while aiming another, and how much
	# of the dark this player spent with a light.
	if local.move_dir.length() > 0.1 and local.aim.length() > 0.1 and local.move_dir.normalized().dot(local.aim.normalized()) < 0.3:
		stats["strafe_s"] = float(stats["strafe_s"]) + delta
	if Z.is_dark(World.my_zone, World.clock):
		stats["night_s"] = float(stats["night_s"]) + delta
		if World.my_lights() != 0:
			stats["night_lit_s"] = float(stats["night_lit_s"]) + delta
	if not Net.opts.has("bot") and not Net.opts.has("scenario"):   # test bots set these themselves
		var free: bool = local.input_enabled and not hud.is_blocking()
		local.want_sprint = free and Input.is_action_pressed("sprint")
		local.want_block = free and Input.is_action_pressed("offhand") and not Items.shield(str(World.equip.get("offhand", ""))).is_empty()
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = 1.0 / STATE_HZ
		_send_state()
	_travel_cooldown -= delta
	if _travel_cooldown <= 0.0 and not local.fainted and not local.riding:
		for ex: Dictionary in Z.zone(World.my_zone)["exits"]:
			if (ex["rect"] as Rect2).has_point(local.position):
				_travel_cooldown = 1.5
				World.to_host(&"c_travel", [str(ex["to"]), local.position])
				break
	_update_mob_solids()
	_check_attacks()
	_check_contact()


## Solid mob bodies in this zone, so the local player can't walk through enemies. Rebuilt
## each frame from what's on screen; the host doesn't need it (player movement is local).
func _update_mob_solids() -> void:
	var out: Array = []
	for eid: int in enemy_nodes:
		var obj: Variant = enemy_nodes[eid]
		if not is_instance_valid(obj):
			continue
		var en: EnemyView = obj
		if en.popping or en.hp_frac <= 0.0:
			continue
		var br := E.body_radius(en.kind)
		if br > 0.0:
			out.append([en.position, br])
	World.dyn_solids = out


func _update_aim() -> void:
	if aim_override != Vector2.ZERO:
		local.aim = aim_override
		return
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.35:
		local.aim = stick
	elif mouse_idle < 3.0:
		local.aim = get_global_mouse_position() - local.position
	else:
		local.aim = Vector2.ZERO


func _send_state() -> void:
	World.to_host(&"c_state", [World.my_zone, local.position, local.facing, World.selected, local.act_bits()])


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_idle = 0.0
	if event.is_action_pressed("menu"):
		if hud.pause_menu.visible:
			return   # the pause menu closes itself
		hud.escape()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			hud.toggle_controls()
			return
		if event.keycode == KEY_BACKSPACE and hud.dialogue.visible and hud.dialogue.speaker == "Pepper":
			World.to_host(&"c_skip_lessons")
			hud.dialogue.close()
			return
		if event.keycode == KEY_F3:
			hitbox_debug.visible = not hitbox_debug.visible
			hud.show_toast("Hitbox view %s." % ("on: green = bodies, orange = enemies, red = a hit" if hitbox_debug.visible else "off"))
			return
	if hud.pause_menu.visible or hud.controls.visible:
		return
	if event.is_action_pressed("map"):
		hud.toggle_map()
	elif event.is_action_pressed("inventory"):
		hud.toggle_inventory()
	elif event.is_action_pressed("item_wheel"):
		hud.open_wheel()
	elif event.is_action_released("item_wheel"):
		hud.close_wheel(true)
	elif hud.is_blocking():
		return
	elif event.is_action_pressed("use_item"):
		use_item(aim_point())
	elif event.is_action_pressed("offhand"):
		offhand()
	elif event.is_action_pressed("interact"):
		if hud.dialogue.visible:
			hud.dialogue.next()
		else:
			interact()
	elif event.is_action_pressed("dash"):
		dash()
	elif event.is_action_pressed("drop_pin"):
		var at := get_global_mouse_position() if mouse_idle < 3.0 else local.position + local.facing * 80.0
		drop_pin(at, "Over here!")
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode >= KEY_1 and event.keycode <= KEY_8:
		if event.keycode - KEY_1 < World.wheel.size():
			World.select_slot(event.keycode - KEY_1)
	elif event is InputEventMouseButton and event.pressed:
		var n := maxi(World.wheel.size(), 1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			World.select_slot((World.selected + 1) % n)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			World.select_slot((World.selected + n - 1) % n)


## Where a thrown item should land: where you aim, else the nearest enemy, else ahead.
func aim_point() -> Vector2:
	if local.aim.length() > 0.1 and (mouse_idle < 3.0 or aim_override != Vector2.ZERO):
		return local.position + local.aim
	var best := Vector2.INF
	var bd := 420.0
	for eid: int in enemy_nodes:
		var obj: Variant = enemy_nodes[eid]
		if not is_instance_valid(obj):
			continue
		var en: EnemyView = obj
		if not en.popping:
			var d := en.position.distance_to(local.position)
			if d < bd:
				bd = d
				best = en.position
	if best != Vector2.INF:
		return best
	return local.position + local.facing * 220.0


func dash() -> void:
	if local.try_dash():
		stats["dashes"] = int(stats["dashes"]) + 1
		Sound.play("dash", 0.7)


func use_item(aim: Vector2) -> void:
	if local.fainted or local.riding:
		return
	var item := World.held_item()
	if item == "":
		hud.show_toast("Nothing in hand. Add things to your item wheel in the bag (I).")
		return
	var to := aim - local.position
	if to.length() > 4.0 and Items.ITEMS[item]["kind"] == "throw":
		local.facing = to.normalized()
	match str(Items.ITEMS[item]["kind"]):
		"sickle":
			if not local.try_spend(Avatar.SWING_COST):
				return
			local.play_swing()
			debug_show(HB.sickle(local.position, local.facing), false)
		"material":
			hud.show_toast("%s is for crafting (coming later)." % Items.display_name(item))
			return
	World.to_host(&"c_use", [World.selected, aim, local.position, local.facing])


func offhand() -> void:
	if local.fainted or local.riding:
		return
	if not Items.shield(str(World.equip.get("offhand", ""))).is_empty():
		return   # blocking is held, handled every frame
	if str(World.equip.get("offhand", "")) == "torch":
		debug_show(HB.jab(local.position, local.facing), false)
	World.to_host(&"c_offhand", [local.position, local.facing])


func interact() -> void:
	if local.fainted:
		return
	World.to_host(&"c_interact", [local.position, local.facing])


func drop_pin(at: Vector2, label: String) -> void:
	World.to_host(&"c_pin_add", [World.my_zone, at, label])


# ---------------------------------------------------------------- being hit (decided here)

func _rtt_s() -> float:
	var rtt: Array = World.stats["rtt_ms"]
	if rtt.is_empty() or Net.is_host():
		return 0.0
	return float(rtt[rtt.size() - 1]) / 1000.0


func _on_telegraph(_zid: String, tg: Dictionary) -> void:
	var lead := _rtt_s() / 2.0   # the message took about this long to get here
	var node := Telegraph.new()
	node.setup(tg, lead)
	telegraph_layer.add_child(node)
	var now := Time.get_ticks_msec() / 1000.0
	var strike := now + maxf(float(tg["windup"]) - lead, 0.0)
	var end := strike + node.active
	pending.append({"tg": tg, "strike": strike, "end": end, "done": false})


func _check_attacks() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for p: Dictionary in pending:
		if bool(p["done"]) or now < float(p["strike"]):
			continue
		var tg: Dictionary = p["tg"]
		var me := HB.player_hurtbox(local.position)
		var progress := 0.0
		if str(tg["kind"]) == "charge":
			progress = float(tg["speed"]) * (now - float(p["strike"]))
		var hitbox := HB.telegraph(tg, progress)
		var hit := HB.hits(hitbox, me)
		var source: Vector2 = hitbox["c"] if str(tg["kind"]) == "charge" else tg["origin"]
		debug_show(hitbox, hit)
		if str(tg["kind"]) != "charge" or now > float(p["end"]):
			p["done"] = true
		if hit and not local.fainted and not local.riding:
			p["done"] = true
			_got_hit(int(tg["enemy"]), int(tg["id"]), source)
		elif bool(p["done"]) and not hit:
			stats["dodged"] = int(stats["dodged"]) + 1
	pending = pending.filter(func(p: Dictionary) -> bool: return not bool(p["done"]) or now < float(p["end"]) + 0.3)


func _got_hit(enemy_id: int, atk_id: int, source: Vector2) -> void:
	# Blocking: is the blow inside the shield's arc, how well timed was it, and is there
	# enough stamina to take it on the shield? The host checks the shield isn't broken.
	var tier := 0
	if local.blocks(source):
		var t: int = local.block_tier()
		# An enemy walking into a raised shield (atk 0) is a bump, not a blow: it costs a
		# third of a real block, so you can hold a slime off without emptying your stamina.
		var cost: float = local.block_cost(t) * (CONTACT_BLOCK_COST if atk_id == 0 else 1.0)
		if local.try_spend(cost):
			tier = t
		else:
			hud.show_toast("Too tired to hold the shield up!")
	if tier > 0:
		stats["blocked"] = int(stats["blocked"]) + 1
		if tier == 3:
			stats["perfect"] = int(stats["perfect"]) + 1
		elif tier == 2:
			stats["great"] = int(stats.get("great", 0)) + 1
		# A real blow still shoves you a little; a bump on the shield doesn't move you at
		# all, so a slime can't walk you out of position (it is the one shoved back).
		local.take_hit(source, 0.0 if atk_id == 0 else [0.0, 220.0, 140.0, 60.0][tier])
		hud.show_toast(Items.BLOCK_NAMES[tier])
	else:
		stats["hits"] = int(stats["hits"]) + 1
		local.take_hit(source, 520.0)
	if Net.opts.has("scenario"):
		Net.log_line("hit by enemy %d attack %d from %s while at %s (block tier %d)" % [enemy_id, atk_id, source, local.position, tier])
	World.to_host(&"c_hit_me", [enemy_id, atk_id, tier])


func _check_contact() -> void:
	if local.fainted or local.riding:
		return
	var steel := Items.total(World.equip, "kick") > 0
	var me := HB.circle(local.position, HB.PLAYER_BODY)
	var kick := HB.kick(local.position, local.facing)
	for eid: int in enemy_nodes:
		var obj: Variant = enemy_nodes[eid]
		if not is_instance_valid(obj):
			continue
		var en: EnemyView = obj
		if en.popping:
			continue
		var body := HB.enemy_hurtbox(en.kind, en.position)
		# Steel-toed boots: sprinting into an enemy kicks it instead of getting bumped.
		if steel and local.sprinting and _kick_cd <= 0.0 and HB.hits(kick, body):
			_kick_cd = 0.4
			stats["kicks"] = int(stats["kicks"]) + 1
			debug_show(kick, true)
			World.to_host(&"c_kick", [en.enemy_id, local.position])
			continue
		if _touch_cd <= 0.0 and local.mercy_t <= 0.0 and int(E.info(en.kind)["touch"]) > 0 and en.state != 4 \
				and HB.hits(body, me):
			_touch_cd = 0.5
			_got_hit(en.enemy_id, 0, en.position)


## Shows a hitbox in the F3 debug view (red if it hit, white if it missed).
func debug_show(shape: Dictionary, hit: bool) -> void:
	if hitbox_debug != null and hitbox_debug.visible:
		hitbox_debug.flash(shape, hit)


# ---------------------------------------------------------------- snapshots and effects

func _on_snapshot(_zid: String, av: Array, el: Array) -> void:
	var seen := {}
	for e: Array in av:
		var id: int = e[0]
		if id == World.me():
			continue
		seen[id] = true
		var node: Avatar = remotes.get(id)
		if node == null:
			node = Avatar.new()
			node.peer_id = id
			node.display_name = Net.player_name(id)
			node.color = Net.player_color(id)
			node.position = e[1]
			entities.add_child(node)
			remotes[id] = node
		node.push_state(e[1], e[2], e[3], e[4], e[5], e[6], e[7])
	for id: int in remotes.keys():
		if not seen.has(id):
			(remotes[id] as Node).queue_free()
			remotes.erase(id)
	var eseen := {}
	for e: Array in el:
		var eid: int = e[0]
		eseen[eid] = true
		var existing: Variant = enemy_nodes.get(eid)
		var node: EnemyView
		if is_instance_valid(existing):
			node = existing
		else:
			node = EnemyView.new()
			node.enemy_id = eid
			entities.add_child(node)
			enemy_nodes[eid] = node
		node.push(e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9])
	for eid: int in enemy_nodes.keys():
		if not eseen.has(eid):
			var obj: Variant = enemy_nodes[eid]
			if is_instance_valid(obj) and not (obj as EnemyView).popping:
				(obj as EnemyView).queue_free()
			enemy_nodes.erase(eid)


## Which sound each effect makes (see game/audio/sound.gd).
const FX_SOUNDS := {"swing": "swing", "jab": "fire", "plant": "plant", "water": "water", "harvest": "harvest",
	"throw": "throw", "splat": "splat", "pop": "pop", "hurt": "hurt", "block": "block", "clang": "perfect",
	"shield_break": "shield_break", "kick": "hit", "ignite": "fire", "melt": "ice", "chest": "chest",
	"revive": "harvest", "pickup": "pickup", "snuff": "splat", "locked": "locked", "charge": "dash",
	"burst": "splat", "slam": "hit", "clink": "block"}


func _on_fx(_zid: String, kind: String, a: Vector2, b: Vector2, peer: int, item: String) -> void:
	if FX_SOUNDS.has(kind):
		# Quieter the further away it happened.
		Sound.play(FX_SOUNDS[kind], clampf(1.0 - a.distance_to(local.position) / 900.0, 0.0, 1.0))
	if kind == "swing":
		if remotes.has(peer):
			(remotes[peer] as Avatar).play_swing()
		return
	if kind == "throw" and peer == World.me():
		local.facing = (b - a).normalized() if (b - a).length() > 1.0 else local.facing
	var f := Fx.new()
	f.setup(kind, a, b, item)
	entities.add_child(f)
