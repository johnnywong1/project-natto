extends Node2D
## A player in the world.
##
## The local player's avatar reads input and moves itself (the host just records where it
## is). Movement and facing are separate, like Spiral Knights: you walk with WASD/left stick
## and face/aim with the mouse or right stick.
##
## Stamina is a row of orbs (like Terraria's mana) spent on dashing, sprinting, swinging
## and blocking; it refills after a short pause. Dashes are quick bursts of speed and do
## NOT make you invulnerable: you have to actually leave the danger zone.
##
## Shields: holding the offhand button with a shield raises it. How long it had been up
## when a hit lands decides the block (Perfect, Great or Regular; see Items.SHIELDS), it
## only covers an arc in front (drawn on the ground around you), and heavier shields slow
## you down more while blocking.
##
## Remote avatars smoothly follow the host's snapshots and show the other player's gear and
## lights (a friend's torch lights up the dark for you too).

const DayNight = preload("res://game/world/day_night.gd")
const HB = preload("res://game/combat/hitboxes.gd")
const P = preload("res://game/ui/palette.gd")
const Icons = preload("res://game/ui/icons.gd")
const Items = preload("res://game/data/items.gd")
const Z = preload("res://game/data/zones.gd")

const RADIUS := HB.PLAYER_BODY
## Light sizes (x 256 px). A torch shows you a small circle; a lantern a bit more.
const TORCH_SCALE := 2.1
const LANTERN_SCALE := 2.5
const SPEED := 220.0
const SPRINT_MULT := 1.6
const DASH_SPEED := 780.0
const DASH_TIME := 0.17
const DASH_COST := 1.0
const SPRINT_COST := 1.25     # orbs per second
const SWING_COST := 0.5
const BASE_ORBS := 5
const REGEN := 1.1            # orbs per second
const REGEN_DELAY := 0.6
const SWING_TIME := 0.22
const MERCY_TIME := 0.6       # after being hit (not from dashing)

# Shared
var peer_id := 0
var display_name := ""
var color := Color("9fdcc8")
var is_local := false
var facing := Vector2.DOWN
var item := ""
var gear: Array = ["", "", "", ""]   # helmet, chest, shoes, offhand
var lights := 0
var hp_frac := 1.0
var fainted := false
var blocking := false
var sprinting := false
var dashing := false

# Local only
var zone := "middlemost"
var aim := Vector2.ZERO               # set by the world view each frame; ZERO = face where you walk
var move_dir := Vector2.ZERO
var stamina := 5.0
var max_orbs := BASE_ORBS
var speed_mult := 1.0
var regen_mult := 1.0
var dash_mult := 1.0
var dash_cost := DASH_COST
var input_enabled := true
var want_sprint := false
var want_block := false
var block_started := -10.0
var shield_broken := false          # the local player's shield is broken (from the host)
var bot_input := Vector2.ZERO
var bot_aim := Vector2.ZERO
var riding := false

var swing_t := 0.0
var mercy_t := 0.0
var dash_t := 0.0
var _dash_dir := Vector2.ZERO
var _spent_t := 0.0
var _knock := Vector2.ZERO
var _walk := 0.0
var _moving := false
var _target := Vector2.ZERO
var _ride_from := Vector2.ZERO
var _ride_to := Vector2.ZERO
var _ride_t := 0.0
var _ride_len := 1.0
var _t := 0.0
var _tired_t := 0.0

var _torch: PointLight2D
var _lantern: PointLight2D
var _headlamp: PointLight2D
var _glow: PointLight2D

static var _radial_tex: GradientTexture2D
static var _cone_tex: ImageTexture


static func radial_texture() -> GradientTexture2D:
	if _radial_tex == null:
		_radial_tex = GradientTexture2D.new()
		_radial_tex.width = 256
		_radial_tex.height = 256
		_radial_tex.fill = GradientTexture2D.FILL_RADIAL
		_radial_tex.fill_from = Vector2(0.5, 0.5)
		_radial_tex.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		# A bright pool that falls off quickly, so a light shows a clear patch and the
		# rest of the night stays dark.
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.65))
		g.add_point(0.8, Color(1, 1, 1, 0.12))
		_radial_tex.gradient = g
	return _radial_tex


## A headlamp beam pointing along +x, with a small glow at the source.
static func cone_texture() -> ImageTexture:
	if _cone_tex == null:
		var n := 128
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
		var c := Vector2(n / 2.0, n / 2.0)
		for y in n:
			for x in n:
				var v := Vector2(x, y) - c
				var d := v.length() / (n / 2.0)
				var ang := absf(v.angle())
				var beam := 0.0
				if v.x > 0.0:
					beam = clampf(1.0 - (ang - 0.22) / 0.16, 0.0, 1.0) * clampf(1.0 - d, 0.0, 1.0)
				var core := clampf(1.0 - d / 0.16, 0.0, 1.0) * 0.7
				img.set_pixel(x, y, Color(1, 1, 1, maxf(beam, core)))
		_cone_tex = ImageTexture.create_from_image(img)
	return _cone_tex


func _make_light(tex: Texture2D, scale_: float, energy: float, col: Color) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.texture_scale = scale_
	l.energy = energy
	l.color = col
	l.enabled = false
	l.position = Vector2(0, -24)
	add_child(l)
	return l


func _ready() -> void:
	_target = position
	_torch = _make_light(radial_texture(), TORCH_SCALE, 0.95, Color("ffb066"))
	_lantern = _make_light(radial_texture(), LANTERN_SCALE, 0.9, Color("ffe2a0"))
	_headlamp = _make_light(cone_texture(), 6.0, 1.3, Color("fff3cf"))
	_glow = _make_light(radial_texture(), 1.0, 0.7, Color("d8fff2"))


## Recalculate gear bonuses for the local player.
func apply_gear(equip: Dictionary) -> void:
	max_orbs = BASE_ORBS + Items.total(equip, "orbs")
	speed_mult = Items.mult(equip, "speed")
	regen_mult = Items.mult(equip, "regen")
	dash_mult = Items.mult(equip, "dash")
	dash_cost = DASH_COST * (0.5 if "wayfarer" in Items.full_sets(equip) else 1.0)
	stamina = minf(stamina, float(max_orbs))
	gear = [equip.get("helmet", ""), equip.get("chest", ""), equip.get("shoes", ""), equip.get("offhand", "")]


func act_bits() -> int:
	var b := 0
	if dashing:
		b |= 1
	if blocking:
		b |= 2
	if sprinting:
		b |= 4
	return b


func push_state(pos: Vector2, face: Vector2, held: String, flags: int, g: Array, light_bits: int, hp: float) -> void:
	_target = pos
	facing = face
	item = held
	dashing = flags & 1 != 0
	blocking = flags & 2 != 0
	sprinting = flags & 4 != 0
	fainted = flags & 8 != 0
	gear = g
	lights = light_bits
	hp_frac = hp
	if position.distance_to(pos) > 260.0:
		position = pos


## Spends stamina if there's enough. Returns false (and shows a little puff) if not.
func try_spend(cost: float) -> bool:
	if stamina + 0.001 < cost:
		_tired_t = 0.4
		return false
	stamina -= cost
	_spent_t = REGEN_DELAY
	return true


func try_dash() -> bool:
	if fainted or riding or dash_t > 0.0 or not try_spend(dash_cost):
		return false
	var want := bot_input if bot_input.length() > 0.1 else move_dir   # bots set input and dash in the same frame
	_dash_dir = want.normalized() if want.length() > 0.1 else facing
	dash_t = DASH_TIME * dash_mult
	return true


func play_swing() -> void:
	swing_t = SWING_TIME


## The local player got hit: knocked back, short mercy period.
func take_hit(from: Vector2, strength: float) -> void:
	_knock = (position - from).normalized() * strength
	mercy_t = MERCY_TIME


func ride(from_center: Vector2, to_center: Vector2, seconds: float) -> void:
	var offset := position - from_center
	riding = true
	_ride_from = from_center + offset
	_ride_to = to_center + offset
	_ride_t = 0.0
	_ride_len = seconds


func _process(delta: float) -> void:
	_t += delta
	swing_t = maxf(swing_t - delta, 0.0)
	mercy_t = maxf(mercy_t - delta, 0.0)
	_tired_t = maxf(_tired_t - delta, 0.0)
	if is_local:
		_local_move(delta)
	else:
		var before := position
		position = position.lerp(_target, 1.0 - exp(-delta * 14.0))
		_moving = before.distance_to(position) > 0.4
	if _moving:
		_walk += delta * (16.0 if sprinting else 12.0)
	_update_lights()
	modulate.a = 0.5 if mercy_t > 0.0 and int(mercy_t * 20.0) % 2 == 0 else 1.0
	queue_redraw()


func _local_move(delta: float) -> void:
	var dir := bot_input
	if input_enabled and dir == Vector2.ZERO and not riding:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_dir = dir
	if riding:
		_ride_t += delta
		var k := clampf(_ride_t / _ride_len, 0.0, 1.0)
		position = _ride_from.lerp(_ride_to, k * k * (3.0 - 2.0 * k))
		_moving = false
		if k >= 1.0:
			riding = false
		return
	if fainted:
		_moving = false
		blocking = false
		sprinting = false
		dash_t = 0.0
		return
	# Stamina refills after a short pause.
	_spent_t -= delta
	if _spent_t <= 0.0:
		stamina = minf(stamina + REGEN * regen_mult * delta, float(max_orbs))
	var sh := Items.shield(str(gear[3]))
	var was_blocking := blocking
	blocking = want_block and not sh.is_empty() and not shield_broken and stamina > 0.05 and dash_t <= 0.0
	if blocking:
		if not was_blocking:
			block_started = _t
		stamina = maxf(stamina - float(sh["hold"]) * delta, 0.0)
		_spent_t = REGEN_DELAY
	sprinting = want_sprint and dir.length() > 0.1 and not blocking and stamina > 0.05
	if sprinting:
		stamina = maxf(stamina - SPRINT_COST * delta, 0.0)
		_spent_t = REGEN_DELAY
	var v := Vector2.ZERO
	if dash_t > 0.0:
		dash_t -= delta
		dashing = true
		v = _dash_dir * DASH_SPEED
	else:
		dashing = false
		var mult := speed_mult
		if sprinting:
			mult *= SPRINT_MULT
		if blocking:
			mult *= float(sh["move"])   # heavy shields slow you more
		v = dir * SPEED * mult
	_moving = v.length() > 1.0
	# Face where you aim; if you're not aiming, face where you walk.
	if aim.length() > 0.1:
		facing = aim.normalized()
	elif dir.length() > 0.1:
		facing = dir.normalized()
	position += (v + _knock) * delta
	_knock = _knock.move_toward(Vector2.ZERO, 1100.0 * delta)
	position = Z.resolve(zone, position, RADIUS, World.frozen_ice(zone))


## True if a blow coming from `from` lands on the lid: blocking and facing it.
## True if a blow coming from `from` is inside the shield's arc while blocking.
func blocks(from: Vector2) -> bool:
	if not blocking:
		return false
	var sh := Items.shield(str(gear[3]))
	if sh.is_empty():
		return false
	var to := from - position
	if to.length() < 1.0:
		return true
	return absf(facing.angle_to(to)) <= deg_to_rad(float(sh["arc"]) / 2.0)


## How well-timed the block is right now: 3 Perfect, 2 Great, 1 Regular (0 = not blocking).
func block_tier() -> int:
	if not blocking:
		return 0
	var sh := Items.shield(str(gear[3]))
	var held := _t - block_started
	if held <= float(sh["perfect"]):
		return 3
	if held <= float(sh["great"]):
		return 2
	return 1


## Stamina a block of this tier costs with the current shield.
func block_cost(tier: int) -> float:
	var sh := Items.shield(str(gear[3]))
	if sh.is_empty() or tier <= 0:
		return 0.0
	return float(sh["cost"]) * [0.0, 1.0, 0.75, 0.5][tier]


func _update_lights() -> void:
	var flicker := 1.0 + sin(_t * 23.0) * 0.04 + sin(_t * 7.3) * 0.05
	var k := DayNight.light_scale()   # no glow at noon, full glow at night
	_torch.enabled = lights & 1 != 0 and not fainted and k > 0.0
	_torch.energy = 0.95 * flicker * k
	_lantern.enabled = lights & 2 != 0 and k > 0.0
	_lantern.energy = 0.9 * k
	_glow.energy = 0.7 * k
	_headlamp.energy = 1.3 * k
	_headlamp.enabled = lights & 4 != 0 and not fainted and k > 0.0
	_headlamp.rotation = facing.angle()
	_headlamp.texture_scale = 9.0 if lights & 8 != 0 else 6.0
	_glow.enabled = lights & 16 != 0 and k > 0.0


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if fainted:
		_draw_fainted()
		return
	P.shadow(self, Vector2.ZERO, Vector2(18, 7))
	_draw_shield_cover()
	if dashing:
		var trail: Vector2 = _dash_dir if is_local else facing
		for k in 3:
			var ghost := -trail * (14.0 + k * 14.0)
			P.blob(self, ghost + Vector2(0, -22), Vector2(15 - k * 3, 15 - k * 3), Color(color, 0.35 - k * 0.1), 0.0)
	var bob: float = absf(sin(_walk)) * 2.5 if _moving else 0.0
	var up := Vector2(0, -bob)
	var step: float = sin(_walk) * 3.0 if _moving else 0.0
	var shoe_col := Color(P.CREAM)
	var shoes := str(gear[2])
	if Items.ITEMS.has(shoes):
		shoe_col = Items.ITEMS[shoes]["color"]
	P.blob(self, up + Vector2(-7, -3.0 + step), Vector2(6, 4), shoe_col, 3.0)
	P.blob(self, up + Vector2(7, -3.0 - step), Vector2(6, 4), shoe_col, 3.0)
	if shoes == "hermes_boots":
		for sx: float in [-11.0, 3.0]:
			P.blob(self, up + Vector2(sx, -7.0), Vector2(4, 2.5), Color.WHITE, 1.5)
	var body := color
	var chest := str(gear[1])
	if chest == "raincoat":
		body = Items.ITEMS["raincoat"]["color"]
	P.blob(self, up + Vector2(0, -18), Vector2(16, 15), body)
	if chest == "overalls":
		P.shape(self, P.rounded_rect_points(Rect2(up + Vector2(-10, -24), Vector2(20, 18)), 5.0), Items.ITEMS["overalls"]["color"], 2.5)
	var side := 1.0 if facing.x >= -0.2 else -1.0
	var hand := up + Vector2(16.0 * side, -16)
	var off_hand := up + Vector2(-16.0 * side, -18)
	var back := facing.y < -0.6
	if back:
		_draw_held(hand)
		_draw_offhand(off_hand)
	P.blob(self, up + Vector2(0, -41), Vector2(20, 19), color)
	if back:
		P.blob(self, up + Vector2(0, -42), Vector2(13, 12), color.darkened(0.12), 3.0)
	else:
		var look: float = clampf(facing.x, -1.0, 1.0) * 3.0
		P.blob(self, up + Vector2(look, -40), Vector2(14, 13), P.SKIN, 3.0)
		P.face(self, up + Vector2(look, -40), 0.85, swing_t > 0.0 or dashing)
	_draw_helmet(up)
	if not back:
		_draw_held(hand)
		_draw_offhand(off_hand)
	if blocking:
		var lid_at := up + Vector2(0, -24) + facing * 22.0
		var sid := str(gear[3])
		var big := 1.35 if sid == "tower_shield" else (0.8 if sid == "buckler" else 1.0)
		P.blob(self, lid_at, Vector2(15, 15) * big, Items.ITEMS[sid]["color"] if Items.ITEMS.has(sid) else P.STONE, 3.5)
		P.blob(self, lid_at, Vector2(4, 4), P.OUTLINE, 0.0)
		if sid == "spike_shield":
			for k in 6:
				var d := Vector2.from_angle(TAU * k / 6.0)
				draw_line(lid_at + d * 14.0, lid_at + d * 21.0, P.OUTLINE, 3.0, true)
		if is_local:
			_draw_shield_hp(lid_at + Vector2(0, -20.0 * big - 10.0), sid)
	if swing_t > 0.0:
		# The swing sweeps across exactly the area the sickle's hitbox covers, on the ground.
		var k: float = 1.0 - swing_t / SWING_TIME
		var half := HB.SICKLE_HALF_ANGLE
		var a0: float = facing.angle() - half
		var a1: float = a0 + 2.0 * half * maxf(k, 0.05)
		var reach := HB.SICKLE_RANGE - 8.0
		var fan := PackedVector2Array([Vector2.ZERO])
		for n in 13:
			fan.append(Vector2.from_angle(lerpf(a0, a1, n / 12.0)) * reach)
		if a1 - a0 > 0.2:   # a sliver too thin to fill would fail to triangulate
			draw_colored_polygon(fan, Color(1, 1, 1, 0.22 * (1.0 - k * 0.6)))
		draw_arc(Vector2.ZERO, reach, a0, a1, 18, P.OUTLINE, 9.0, true)
		draw_arc(Vector2.ZERO, reach, a0, a1, 18, P.CREAM, 5.0, true)
	if is_local:
		# Aim marker: a small arrow on the ground in the direction you're facing.
		var tip := facing * 46.0
		var sideways := Vector2(-facing.y, facing.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - facing * 12.0 + sideways * 7.0, tip - facing * 12.0 - sideways * 7.0]), Color(1, 1, 1, 0.75))
		if _tired_t > 0.0:
			P.text(self, up + Vector2(0, -100), "tired!", 14)
	_draw_tag(up)


## Your shield's health, as a row of pips just above the raised shield (full = blue, lost =
## hollow). Red while it's broken. Comes from the host's vitals (World.vitals["shield"]).
func _draw_shield_hp(at: Vector2, sid: String, only_if_hurt: bool = false) -> void:
	var sh := Items.shield(sid)
	var st: Dictionary = World.vitals.get("shield", {})
	if sh.is_empty() or st.is_empty() or str(st.get("id", "")) != sid:
		return
	var max_hp := int(sh["hp"])
	var hp := float(st.get("hp", max_hp))
	if only_if_hurt and hp >= float(max_hp) - 0.05 and not shield_broken:
		return
	var pips := mini(max_hp, 8)
	var per := float(max_hp) / float(pips)
	var w := pips * 7.0 - 2.0
	var x0 := at.x - w / 2.0
	for i in pips:
		var filled := clampf((hp - i * per) / per, 0.0, 1.0)
		var r := Rect2(Vector2(x0 + i * 7.0, at.y - 2.5), Vector2(5, 5))
		draw_rect(r, Color(0.2, 0.2, 0.25, 0.9), false, 1.5)
		if filled > 0.0:
			var fill := r.grow(-0.5)
			fill.size.y *= filled
			fill.position.y += r.size.y - 1.0 - fill.size.y
			draw_rect(fill, Color(0.95, 0.3, 0.25) if shield_broken else Color(0.45, 0.7, 1.0))


## The shield's coverage on the ground: the arc it protects (blue, gold during the Perfect
## window, white during the Great window) and the rest of the ring, where you're open (red).
## You always see your own (faintly when not blocking); other players' show while they block.
func _draw_shield_cover() -> void:
	var sh := Items.shield(str(gear[3]))
	if sh.is_empty() or (not is_local and not blocking):
		return
	var half := deg_to_rad(float(sh["arc"]) / 2.0)
	var base := facing.angle()
	# A band round your feet rather than a full wedge, so your own body doesn't hide it.
	var r_in := 30.0
	var r_out := 54.0
	if is_local and shield_broken:
		draw_arc(Vector2.ZERO, r_out, base - half, base + half, 24, Color(0.45, 0.45, 0.45, 0.8), 4.0, true)
		return
	if not blocking:
		draw_arc(Vector2.ZERO, r_out, base - half, base + half, 24, Color(0.35, 0.6, 1.0, 0.45), 3.0, true)
		return
	var col := Color(0.35, 0.6, 1.0)
	match block_tier() if is_local else 1:
		3:
			col = Color(1.0, 0.82, 0.25)
		2:
			col = Color(1.0, 1.0, 1.0)
	var band := PackedVector2Array()
	for k in 17:
		band.append(Vector2.from_angle(base - half + 2.0 * half * k / 16.0) * r_out)
	for k in range(16, -1, -1):
		band.append(Vector2.from_angle(base - half + 2.0 * half * k / 16.0) * r_in)
	draw_colored_polygon(band, Color(col, 0.32))
	draw_arc(Vector2.ZERO, r_out, base - half, base + half, 24, col, 4.0, true)
	# The open side: dashes all the way round the back.
	var gap := TAU - 2.0 * half
	for k in 12:
		var a0 := base + half + gap * (k + 0.25) / 12.0
		draw_arc(Vector2.ZERO, r_out - 6.0, a0, a0 + gap * 0.5 / 12.0, 4, Color(0.9, 0.25, 0.2, 0.6), 2.5, true)


func _draw_held(at: Vector2) -> void:
	if item != "":
		Icons.draw(self, item, at, 0.8)


func _draw_offhand(at: Vector2) -> void:
	var off := str(gear[3])
	match off:
		"torch":
			draw_line(at + Vector2(0, 8), at + Vector2(2, -10), P.OUTLINE, 6.0, true)
			draw_line(at + Vector2(0, 8), at + Vector2(2, -10), P.WOOD, 3.0, true)
			if lights & 1 != 0:
				var f := 1.0 + sin(_t * 18.0) * 0.15
				P.blob(self, at + Vector2(2, -16), Vector2(6, 9) * f, Color("ff9f4a"), 2.0)
				P.blob(self, at + Vector2(2, -14), Vector2(3, 5) * f, Color("fff27a"), 0.0)
			else:
				draw_circle(at + Vector2(2, -12), 3.5, Color("5b5b5b"))
		"lantern":
			Icons.draw(self, "lantern", at, 0.75)
			if lights & 2 != 0:
				draw_circle(at + Vector2(0, 1), 3.5, Color("fff6c9"))
		"pot_lid", "buckler", "tower_shield", "spike_shield":
			if not blocking:
				Icons.draw(self, off, at, 0.7)
				if is_local:
					_draw_shield_hp(at + Vector2(0, 16), off)   # the shield's health sits under it


func _draw_helmet(up: Vector2) -> void:
	var h := str(gear[0])
	match h:
		"miner_helmet":
			P.blob(self, up + Vector2(0, -52), Vector2(19, 11), Items.ITEMS["miner_helmet"]["color"], 3.0)
			draw_line(up + Vector2(-20, -47), up + Vector2(20, -47), P.OUTLINE, 3.0, true)
			P.blob(self, up + Vector2(0, -55) + facing * 6.0, Vector2(5, 5), Color("fffbe0"), 2.0)
		"pot_helmet":
			P.shape(self, P.rounded_rect_points(Rect2(up + Vector2(-17, -64), Vector2(34, 18)), 6.0), Items.ITEMS["pot_helmet"]["color"], 3.0)
			draw_line(up + Vector2(16, -56), up + Vector2(30, -60), P.OUTLINE, 5.0, true)
		"leaf_hood":
			P.shape(self, PackedVector2Array([up + Vector2(-20, -48), up + Vector2(0, -70), up + Vector2(20, -48)]), Items.ITEMS["leaf_hood"]["color"], 3.0)


func _draw_tag(up: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var tag := Rect2(up + Vector2(-w / 2.0 - 7.0, -92), Vector2(w + 14.0, 21))
	P.shape(self, P.rounded_rect_points(tag, 9.0), Color(1, 1, 1, 0.92), 2.5)
	draw_circle(tag.position + Vector2(-1, 10.5), 5.0, color)
	draw_string(font, tag.position + Vector2(7, 16), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.OUTLINE)
	if not is_local and hp_frac < 0.999:
		var bar := Rect2(tag.position + Vector2(0, 24), Vector2(tag.size.x, 5))
		draw_rect(bar, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp_frac, bar.size.y)), Color("ff7a8a"))


func _draw_fainted() -> void:
	P.shadow(self, Vector2.ZERO, Vector2(24, 8))
	P.blob(self, Vector2(-8, -8), Vector2(18, 12), color)
	P.blob(self, Vector2(16, -10), Vector2(13, 12), P.SKIN, 3.0)
	draw_line(Vector2(11, -12), Vector2(15, -12), P.OUTLINE, 2.0)
	draw_line(Vector2(18, -12), Vector2(22, -12), P.OUTLINE, 2.0)
	var z := sin(_t * 3.0) * 4.0
	P.text(self, Vector2(26, -30 + z), "z", 16)
	P.text(self, Vector2(36, -44 + z), "Z", 20)
	_draw_tag(Vector2(0, 30))
	if not is_local:
		P.text(self, Vector2(0, -70), "E: revive", 15)
