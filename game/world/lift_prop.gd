extends Node2D
## A pulley lift between a low and a high spot (or down onto a lower shelf). Stand on the
## platform and press E: it carries everyone standing on it together. Press E at the empty
## end to call it over. The host decides when it moves; this just shows it.

const P = preload("res://game/ui/palette.gd")
const Z = preload("res://game/data/zones.gd")

var lift_id := ""
var label := "Pulley lift"
var bottom := Vector2.ZERO
var top := Vector2.ZERO
var at := "bottom"
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0
var _len := 0.0
var _moving := false


func setup(def: Dictionary, where: String) -> void:
	lift_id = def["id"]
	label = def.get("label", "Pulley lift")
	bottom = def["bottom"]
	top = def["top"]
	at = where


func platform_pos() -> Vector2:
	if _moving:
		var k := clampf(_t / _len, 0.0, 1.0)
		return _from.lerp(_to, k * k * (3.0 - 2.0 * k))
	return bottom if at == "bottom" else top


func animate(from_end: String, to_end: String, seconds: float) -> void:
	_from = bottom if from_end == "bottom" else top
	_to = bottom if to_end == "bottom" else top
	_t = 0.0
	_len = seconds
	_moving = true
	at = to_end


func _process(delta: float) -> void:
	if _moving:
		_t += delta
		if _t >= _len:
			_moving = false
	queue_redraw()


func _draw() -> void:
	# Frame and pulley at the high end, rope down to the platform.
	var high := top if top.y < bottom.y else bottom
	var post_l := high + Vector2(-80, -40)
	var post_r := high + Vector2(80, -40)
	for post in [post_l, post_r]:
		draw_line(post + Vector2(0, 60), post + Vector2(0, -60), P.OUTLINE, 10.0, true)
		draw_line(post + Vector2(0, 60), post + Vector2(0, -60), P.WOOD, 5.0, true)
	draw_line(post_l + Vector2(0, -60), post_r + Vector2(0, -60), P.OUTLINE, 8.0, true)
	draw_line(post_l + Vector2(0, -60), post_r + Vector2(0, -60), P.WOOD, 4.0, true)
	var wheel := high + Vector2(0, -100)
	P.blob(self, wheel, Vector2(14, 14), P.STONE, 3.0)
	var plat := platform_pos()
	var rect := Z.lift_rect(plat)
	draw_line(wheel, rect.position + Vector2(10, 0), P.OUTLINE, 3.0, true)
	draw_line(wheel, Vector2(rect.end.x - 10, rect.position.y), P.OUTLINE, 3.0, true)
	# Landing marks at both ends.
	for end in [bottom, top]:
		var lr := Z.lift_rect(end)
		draw_rect(lr, Color(1, 1, 0.8, 0.18))
		draw_rect(lr, Color(P.OUTLINE, 0.5), false, 2.0)
	P.shape(self, P.rounded_rect_points(rect, 8.0), Color("d6b48a"), 4.0)
	for k in 4:
		var y := rect.position.y + 18.0 + k * 18.0
		draw_line(Vector2(rect.position.x + 8, y), Vector2(rect.end.x - 8, y), Color("a8865e"), 3.0, true)
	P.text(self, plat + Vector2(0, rect.size.y / 2.0 + 22.0), "%s (E)" % label, 15)
