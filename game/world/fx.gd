extends Node2D
## Short visual effects the host announces to everyone in a zone: throws, splats, swings,
## watering, planting, harvests, pickups and pops. Frees itself when done.

const P = preload("res://game/ui/palette.gd")
const Icons = preload("res://game/ui/icons.gd")
const Items = preload("res://game/data/items.gd")

var kind := ""
var a := Vector2.ZERO
var b := Vector2.ZERO
var item := ""
var _t := 0.0
var _life := 0.5


func setup(k: String, from: Vector2, to: Vector2, held: String) -> void:
	kind = k
	a = from
	b = to
	item = held
	position = a
	match kind:
		"throw":
			_life = 0.45
		"splat", "pop", "nibble":
			_life = 0.4
		"harvest", "pickup", "chest", "revive", "clang", "daze":
			_life = 0.8
		"burst", "slam", "charge":
			_life = 0.5
		_:
			_life = 0.5


func _process(delta: float) -> void:
	_t += delta
	if kind == "throw":
		position = a.lerp(b, clampf(_t / _life, 0.0, 1.0))
	if _t >= _life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var k: float = clampf(_t / _life, 0.0, 1.0)
	match kind:
		"throw":
			var h := sin(k * PI) * 70.0
			P.shadow(self, Vector2.ZERO, Vector2(9, 4))
			Icons.draw(self, item, Vector2(0, -h - 8.0), 0.9)
		"splat":
			var col: Color = Items.ITEMS[item]["color"] if Items.ITEMS.has(item) else P.BERRY
			col.a = 1.0 - k
			var r := lerpf(10.0, 58.0, k)
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 6.0 * (1.0 - k) + 1.0, true)
			for n in 7:
				draw_circle(Vector2.from_angle(TAU * n / 7.0) * r * 0.8, 5.0 * (1.0 - k) + 1.0, col)
		"pop", "nibble":
			var col := Color(P.MILDEW, 1.0 - k)
			for n in 6:
				draw_circle(Vector2(0, -16) + Vector2.from_angle(TAU * n / 6.0) * (10.0 + 30.0 * k), 7.0 * (1.0 - k) + 1.0, col)
		"swing":
			var dir := (b - a).normalized()
			var a0 := dir.angle() - 1.3
			var a1 := a0 + 2.6 * maxf(k * 2.0, 0.05)
			if k < 0.5:
				draw_arc(Vector2(0, -20), 44.0, a0, minf(a1, a0 + 2.6), 18, P.OUTLINE, 13.0, true)
				draw_arc(Vector2(0, -20), 44.0, a0, minf(a1, a0 + 2.6), 18, P.CREAM, 7.0, true)
		"water":
			for n in 6:
				var x := -18.0 + n * 7.0
				var y := -30.0 + fmod(k * 60.0 + n * 9.0, 40.0)
				draw_circle(Vector2(x, y), 3.0, Color(P.WATER, 1.0 - k * 0.6))
		"plant":
			for n in 5:
				draw_circle(Vector2.from_angle(TAU * n / 5.0) * (6.0 + 18.0 * k), 4.0 * (1.0 - k) + 1.0, Color(P.SOIL_MOUND, 1.0 - k))
		"harvest", "pickup":
			Icons.draw(self, item, Vector2(0, -20.0 - 40.0 * k), 1.0 + 0.3 * (1.0 - k))
			for n in 5:
				draw_circle(Vector2.from_angle(TAU * n / 5.0 + k * 3.0) * (16.0 + 20.0 * k) + Vector2(0, -20), 3.0 * (1.0 - k) + 0.5, Color(1, 1, 0.7, 1.0 - k))
		"hurt":
			draw_arc(Vector2(0, -24), 20.0 + 18.0 * k, 0.0, TAU, 24, Color(1, 0.3, 0.3, 1.0 - k), 4.0, true)
		"block":
			for n in 6:
				var dirv := (b - a).normalized() if (b - a).length() > 1.0 else Vector2.RIGHT
				var sp := dirv.rotated((n - 2.5) * 0.25) * (20.0 + 30.0 * k)
				draw_line(Vector2(0, -24) + dirv * 20.0, Vector2(0, -24) + dirv * 20.0 + sp * 0.5, Color(1, 1, 0.7, 1.0 - k), 3.0, true)
		"clang":
			P.text(self, Vector2(0, -70 - 20.0 * k), "CLANG!", 22, Color(1, 0.85, 0.3, 1.0 - k))
			draw_arc(Vector2(0, -24), 30.0 + 40.0 * k, 0.0, TAU, 32, Color(1, 0.9, 0.5, 1.0 - k), 5.0, true)
		"snuff":
			for n in 5:
				draw_circle(Vector2(sin(n * 1.7) * 8.0, -40.0 - 30.0 * k - n * 6.0), 5.0 + 6.0 * k, Color(0.6, 0.6, 0.6, 0.6 * (1.0 - k)))
		"ignite", "jab":
			for n in 7:
				var a2 := TAU * n / 7.0 + k * 2.0
				P.blob(self, Vector2(0, -20) + Vector2.from_angle(a2) * (10.0 + 24.0 * k), Vector2(5, 8) * (1.0 - k) + Vector2(1, 1), Color("ff9a4a"), 0.0)
		"melt":
			for n in 8:
				var a2 := TAU * n / 8.0
				draw_circle(Vector2.from_angle(a2) * (10.0 + 40.0 * k), 5.0 * (1.0 - k) + 1.0, Color(0.6, 0.85, 1.0, 1.0 - k))
		"kick":
			P.text(self, (b - a) * 0.5 + Vector2(0, -50 - 20.0 * k), "KICK!", 20, Color(1, 0.6, 0.2, 1.0 - k))
		"daze":
			P.text(self, Vector2(0, -80 - 10.0 * k), "Dazed!", 18, Color(1, 0.9, 0.4, 1.0 - k))
		"burst":
			draw_circle(Vector2.ZERO, 140.0 * k, Color(0.9, 0.6, 0.9, 0.35 * (1.0 - k)))
			for n in 14:
				draw_circle(Vector2.from_angle(TAU * n / 14.0) * 140.0 * k, 6.0 * (1.0 - k) + 1.0, Color(0.95, 0.75, 0.95, 1.0 - k))
		"slam":
			var dirv := (b - a).normalized() if (b - a).length() > 1.0 else Vector2.RIGHT
			for n in 9:
				var a2 := dirv.angle() - 0.9 + 1.8 * n / 8.0
				draw_circle(Vector2.from_angle(a2) * 220.0 * k, 9.0 * (1.0 - k) + 1.0, Color(0.75, 0.6, 0.45, 1.0 - k))
		"charge":
			draw_line(Vector2.ZERO, (b - a) * k, Color(0.85, 0.75, 0.6, 0.6 * (1.0 - k)), 30.0, true)
		"chest", "revive":
			for n in 8:
				var a2 := TAU * n / 8.0 + k * 3.0
				draw_circle(Vector2(0, -30) + Vector2.from_angle(a2) * (14.0 + 30.0 * k), 3.5 * (1.0 - k) + 0.5, Color(1, 0.95, 0.6, 1.0 - k) if kind == "chest" else Color(1, 0.5, 0.6, 1.0 - k))
