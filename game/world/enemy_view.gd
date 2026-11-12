extends Node2D
## An enemy as seen by this player. The host simulates it; this node follows the host's
## snapshots and draws its wind-up, attack, daze, fire and ice.

const DayNight = preload("res://game/world/day_night.gd")
const P = preload("res://game/ui/palette.gd")
const E = preload("res://game/data/enemies.gd")
const Avatar = preload("res://game/world/avatar.gd")

var enemy_id := 0
var kind := "wilt"
var state := 0          # 0 move, 1 windup, 2 attack, 3 recover, 4 stunned
var dir := Vector2.RIGHT
var hp_frac := 1.0
var burning := false
var frozen := false
var popping := false
var eating := false
var radius := 20.0
var _target := Vector2.ZERO
var _t := 0.0
var _pop_t := 0.0
var _spawn := 0.4
var _flash := 0.0
var _fire: PointLight2D


func _ready() -> void:
	_fire = PointLight2D.new()
	_fire.texture = Avatar.radial_texture()
	_fire.texture_scale = 1.8
	_fire.energy = 1.0
	_fire.color = Color("ff9a4a")
	_fire.enabled = false
	_fire.position = Vector2(0, -30)
	add_child(_fire)


func push(k: String, pos: Vector2, hp: float, st: int, d: Vector2, burn: bool, ice: bool, pop: bool, eat: bool) -> void:
	if _target == Vector2.ZERO:
		position = pos
	kind = k
	radius = float(E.info(k)["radius"])
	_target = pos
	if hp < hp_frac - 0.001:
		_flash = 0.15
	hp_frac = hp
	state = st
	dir = d
	burning = burn
	frozen = ice
	eating = eat
	if pop and not popping:
		popping = true
		_pop_t = 0.35
	if position.distance_to(pos) > 300.0:
		position = pos


func _process(delta: float) -> void:
	_t += delta
	_spawn = maxf(_spawn - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	# A charging boar moves fast; follow it tightly so the hit lines up.
	position = position.lerp(_target, 1.0 - exp(-delta * (30.0 if state == 2 else 14.0)))
	var k := DayNight.light_scale()
	_fire.enabled = burning and not popping and k > 0.0
	_fire.energy = (1.0 + sin(_t * 20.0) * 0.12) * k
	if popping:
		_pop_t -= delta
		if _pop_t <= -0.2:
			queue_free()
	queue_redraw()


func _draw() -> void:
	var scale_f: float = E.info(kind)["scale"]
	if popping:
		var k: float = clampf(1.0 - _pop_t / 0.35, 0.0, 1.0)
		var col := Color(P.MILDEW, 1.0 - k) if kind.ends_with("wilt") else Color(0.6, 0.5, 0.4, 1.0 - k)
		for n in 7:
			var a: float = TAU * float(n) / 7.0
			draw_circle(Vector2(0, -16 * scale_f) + Vector2.from_angle(a) * (10.0 + 34.0 * k) * scale_f, (7.0 * (1.0 - k) + 1.0) * scale_f, col)
		return
	var s: float = maxf(1.0 - _spawn / 0.4, 0.1) * scale_f
	var shake := Vector2(sin(_t * 60.0) * 2.0, 0) if state == 1 else Vector2.ZERO
	P.shadow(self, Vector2.ZERO, Vector2(20, 7) * s)
	match kind:
		"wilt", "frost_wilt":
			_draw_wilt(s, shake)
		"boar":
			_draw_boar(s, shake)
		"puffcap":
			_draw_puffcap(s)
		"bear":
			_draw_bear(s, shake)
	if burning:
		for n in 3:
			var fx := Vector2(-10 + n * 10, -34 * s) + Vector2(0, sin(_t * 14.0 + n) * 3.0)
			P.blob(self, fx, Vector2(6, 10 + sin(_t * 17.0 + n * 2.0) * 3.0), Color("ff8a3a"), 2.0)
			P.blob(self, fx + Vector2(0, 3), Vector2(3, 5), Color("fff27a"), 0.0)
	if state == 4:
		for n in 3:
			var a := _t * 4.0 + TAU * n / 3.0
			P.text(self, Vector2(0, -60 * s) + Vector2(cos(a) * 18.0, sin(a) * 6.0), "*", 18, Color("ffd27a"))
	if hp_frac < 0.999:
		var w := 44.0 * maxf(s, 1.0)
		var bar := Rect2(Vector2(-w / 2.0, 10), Vector2(w, 5))
		draw_rect(bar, Color(0, 0, 0, 0.4))
		draw_rect(Rect2(bar.position, Vector2(w * hp_frac, 5)), Color("ff7a8a"))


func _body_col(base: Color) -> Color:
	return Color.WHITE if _flash > 0.0 else base


func _draw_wilt(s: float, shake: Vector2) -> void:
	var c := Vector2(0, -16) * s + shake
	var wob: float = sin(_t * 6.0) * 1.6
	var base := P.MILDEW if kind == "wilt" else Color("bfe3ff")
	P.blob(self, c, Vector2(21.0 + wob, 17.0 - wob) * s, _body_col(base))
	var spot := P.MILDEW_DARK if kind == "wilt" else Color("8fbfe6")
	draw_circle(c + Vector2(-10, 8) * s, 3.5 * s, spot)
	draw_circle(c + Vector2(12, 5) * s, 2.5 * s, spot)
	draw_arc(c + Vector2(-7, -2) * s, 4.0 * s, 0.0, PI, 8, P.OUTLINE, 3.0, true)
	draw_arc(c + Vector2(7, -2) * s, 4.0 * s, 0.0, PI, 8, P.OUTLINE, 3.0, true)
	if eating and fmod(_t, 0.3) < 0.15:
		P.blob(self, c + Vector2(0, 7) * s, Vector2(6, 5) * s, P.MOUTH, 2.0)
	else:
		draw_line(c + Vector2(-4, 7) * s, c + Vector2(4, 7) * s, P.OUTLINE, 3.0, true)
	P.blob(self, c + Vector2(0, -17) * s, Vector2(11, 6) * s, spot, 3.0)
	if frozen:
		var pts := PackedVector2Array()
		for n in 6:
			pts.append(c + Vector2.from_angle(TAU * n / 6.0 + 0.3) * 30.0 * s)
		draw_colored_polygon(pts, Color(0.8, 0.95, 1.0, 0.55))
		pts.append(pts[0])
		draw_polyline(pts, Color("5aa9e6"), 3.0, true)
		draw_line(c + Vector2(-12, -14) * s, c + Vector2(-4, -22) * s, Color.WHITE, 3.0, true)


func _draw_boar(s: float, shake: Vector2) -> void:
	var flip := -1.0 if dir.x < 0.0 else 1.0
	var c := Vector2(0, -18) * s + shake
	var body := _body_col(Color("b07a55"))
	for n in 4:
		var bx := (-14 + n * 9) * flip
		P.shape(self, PackedVector2Array([c + Vector2(bx - 5 * flip, -12) * s, c + Vector2(bx, -26) * s, c + Vector2(bx + 5 * flip, -12) * s]), Color("7a5a3a"), 2.0)
	P.blob(self, c, Vector2(26, 17) * s, body)
	P.blob(self, c + Vector2(22 * flip, 2) * s, Vector2(12, 10) * s, body, 3.0)
	P.blob(self, c + Vector2(31 * flip, 4) * s, Vector2(5, 4) * s, Color("e8a090"), 2.0)
	draw_line(c + Vector2(26 * flip, 9) * s, c + Vector2(33 * flip, 1) * s, P.CREAM, 3.5 * s, true)
	var eye := Color("ff4a3a") if state == 1 or state == 2 else P.OUTLINE
	draw_circle(c + Vector2(22 * flip, -3) * s, 2.6 * s, eye)
	for lx: float in [-14.0, -4.0, 8.0, 16.0]:
		draw_line(c + Vector2(lx * flip, 12) * s, c + Vector2(lx * flip, 20) * s, P.OUTLINE, 5.0 * s, true)
	if state == 1:
		# Pawing the ground: little dust puffs behind.
		for n in 3:
			var k := fmod(_t * 3.0 + n * 0.33, 1.0)
			draw_circle(Vector2(-30 * flip - k * 20.0 * flip, -4) * s, (4.0 + k * 6.0) * s, Color(0.85, 0.75, 0.6, 1.0 - k))


func _draw_puffcap(s: float) -> void:
	var swell := 1.0 + (sin(_t * 18.0) * 0.06 + 0.25 if state == 1 else sin(_t * 2.0) * 0.03)
	var c := Vector2(0, -14) * s
	P.shape(self, P.rounded_rect_points(Rect2(c + Vector2(-9, -4) * s, Vector2(18, 20) * s), 6.0 * s), _body_col(P.CREAM), 3.0)
	draw_circle(c + Vector2(-4, 4) * s, 2.0 * s, P.OUTLINE)
	draw_circle(c + Vector2(4, 4) * s, 2.0 * s, P.OUTLINE)
	P.blob(self, c + Vector2(0, -10) * s, Vector2(26, 16) * s * swell, _body_col(Color("e39ad8")))
	for o: Vector2 in [Vector2(-12, -14), Vector2(6, -18), Vector2(14, -8)]:
		draw_circle(c + o * s * swell, 4.0 * s, Color("fff0fb"))


func _draw_bear(s: float, shake: Vector2) -> void:
	var c := Vector2(0, -20) * s + shake
	var fur := _body_col(Color("8a6a4a"))
	P.blob(self, c, Vector2(24, 20) * s, fur)
	P.blob(self, c + Vector2(-8, -6) * s, Vector2(10, 6) * s, Color("6fae5f"), 0.0)
	var head := c + Vector2(0, -18) * s + dir * 6.0 * s
	P.blob(self, head + Vector2(-11, -10) * s, Vector2(6, 6) * s, fur, 3.0)
	P.blob(self, head + Vector2(11, -10) * s, Vector2(6, 6) * s, fur, 3.0)
	P.blob(self, head, Vector2(15, 13) * s, fur)
	P.blob(self, head + Vector2(0, 5) * s, Vector2(7, 5) * s, P.CREAM, 2.0)
	var eye := Color("ff4a3a") if state == 1 else P.OUTLINE
	draw_circle(head + Vector2(-6, -3) * s, 2.2 * s, eye)
	draw_circle(head + Vector2(6, -3) * s, 2.2 * s, eye)
	if state == 1:
		# Paws raised for the slam.
		var lift := minf(_t * 3.0, 1.0)
		P.blob(self, c + Vector2(-20, -34 - 10 * lift) * s, Vector2(8, 7) * s, fur, 3.0)
		P.blob(self, c + Vector2(20, -34 - 10 * lift) * s, Vector2(8, 7) * s, fur, 3.0)
	else:
		P.blob(self, c + Vector2(-20, 10) * s, Vector2(8, 6) * s, fur, 3.0)
		P.blob(self, c + Vector2(20, 10) * s, Vector2(8, 6) * s, fur, 3.0)
