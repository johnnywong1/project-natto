extends RefCounted
## Item icons drawn in code (Sticker Pop style), used by the wheel, bag, HUD and hands.

const P = preload("res://game/ui/palette.gd")
const Items = preload("res://game/data/items.gd")


static func draw(ci: CanvasItem, id: String, c: Vector2, s: float) -> void:
	if not Items.ITEMS.has(id):
		return
	var col: Color = Items.ITEMS[id]["color"]
	match id:
		"sickle":
			_sickle(ci, c, s, col)
		"can":
			P.shape(ci, P.rounded_rect_points(Rect2(c + Vector2(-11, -6) * s, Vector2(20, 16) * s), 4.0 * s), col, 3.0 * s)
			ci.draw_line(c + Vector2(8, 0) * s, c + Vector2(16, -8) * s, P.OUTLINE, 6.0 * s, true)
			ci.draw_line(c + Vector2(8, 0) * s, c + Vector2(16, -8) * s, col, 2.5 * s, true)
			ci.draw_arc(c + Vector2(-1, -6) * s, 7.0 * s, PI, TAU, 10, P.OUTLINE, 3.0 * s, true)
		"lantern":
			P.shape(ci, P.rounded_rect_points(Rect2(c + Vector2(-8, -8) * s, Vector2(16, 18) * s), 5.0 * s), col, 3.0 * s)
			ci.draw_circle(c + Vector2(0, 1) * s, 4.0 * s, Color("fff6c9"))
			ci.draw_arc(c + Vector2(0, -9) * s, 5.0 * s, PI, TAU, 8, P.OUTLINE, 3.0 * s, true)
		"popberry_seed", "radish_seed":
			P.shape(ci, P.rounded_rect_points(Rect2(c + Vector2(-10, -11) * s, Vector2(20, 22) * s), 5.0 * s), P.CREAM, 3.0 * s)
			P.blob(ci, c + Vector2(0, 2) * s, Vector2(5, 5) * s, col, 2.5 * s)
			ci.draw_line(c + Vector2(-6, -6) * s, c + Vector2(6, -6) * s, P.OUTLINE, 2.5 * s, true)
		"popberry":
			P.blob(ci, c, Vector2(10, 10) * s, col, 3.0 * s)
			ci.draw_circle(c + Vector2(-3, -3) * s, 2.8 * s, P.BERRY_SHINE)
		"radish":
			P.blob(ci, c + Vector2(0, 3) * s, Vector2(9, 10) * s, col, 3.0 * s)
			ci.draw_line(c + Vector2(0, -6) * s, c + Vector2(-5, -14) * s, P.OUTLINE, 5.0 * s, true)
			ci.draw_line(c + Vector2(0, -6) * s, c + Vector2(5, -14) * s, P.OUTLINE, 5.0 * s, true)
			ci.draw_line(c + Vector2(0, -6) * s, c + Vector2(-5, -14) * s, P.LEAF, 2.5 * s, true)
			ci.draw_line(c + Vector2(0, -6) * s, c + Vector2(5, -14) * s, P.LEAF, 2.5 * s, true)
			ci.draw_line(c + Vector2(-3, 2) * s, c + Vector2(2, 5) * s, Color("fff27a"), 2.0 * s, true)
		"fern":
			ci.draw_line(c + Vector2(-6, 10) * s, c + Vector2(6, -10) * s, P.OUTLINE, 5.0 * s, true)
			for k in 4:
				var t := float(k) / 3.0
				var base := c + Vector2(-6, 10) * s + Vector2(12, -20) * s * t
				P.blob(ci, base + Vector2(-5, 1) * s, Vector2(5, 3) * s, col, 2.0 * s)
				P.blob(ci, base + Vector2(5, 3) * s, Vector2(5, 3) * s, col, 2.0 * s)
		"glowcap":
			ci.draw_line(c + Vector2(0, 2) * s, c + Vector2(0, 11) * s, P.OUTLINE, 6.0 * s, true)
			ci.draw_line(c + Vector2(0, 2) * s, c + Vector2(0, 11) * s, P.CREAM, 3.0 * s, true)
			P.blob(ci, c + Vector2(0, -2) * s, Vector2(11, 7) * s, col, 3.0 * s)
			ci.draw_circle(c + Vector2(-4, -3) * s, 1.8 * s, Color.WHITE)
		"oil":
			P.shape(ci, P.rounded_rect_points(Rect2(c + Vector2(-8, -8) * s, Vector2(16, 20) * s), 5.0 * s), col, 3.0 * s)
			ci.draw_rect(Rect2(c + Vector2(-3, -13) * s, Vector2(6, 6) * s), P.OUTLINE)
			P.blob(ci, c + Vector2(0, 3) * s, Vector2(4, 5) * s, Color("fff6c9"), 0.0)
		"torch":
			ci.draw_line(c + Vector2(-5, 12) * s, c + Vector2(3, -4) * s, P.OUTLINE, 7.0 * s, true)
			ci.draw_line(c + Vector2(-5, 12) * s, c + Vector2(3, -4) * s, P.WOOD, 3.5 * s, true)
			P.blob(ci, c + Vector2(4, -9) * s, Vector2(6, 8) * s, col, 2.5 * s)
			P.blob(ci, c + Vector2(4, -7) * s, Vector2(3, 4) * s, Color("fff27a"), 0.0)
		"pot_lid":
			P.blob(ci, c + Vector2(0, 2) * s, Vector2(12, 8) * s, col, 3.0 * s)
			P.blob(ci, c + Vector2(0, -5) * s, Vector2(4, 3) * s, P.OUTLINE, 0.0)
		"buckler":
			P.blob(ci, c, Vector2(10, 10) * s, col, 3.0 * s)
			P.blob(ci, c, Vector2(4, 4) * s, Color("e3b04b"), 2.0 * s)
		"tower_shield":
			var pts := PackedVector2Array([c + Vector2(-11, -13) * s, c + Vector2(11, -13) * s, c + Vector2(11, 6) * s,
				c + Vector2(0, 14) * s, c + Vector2(-11, 6) * s])
			P.shape(ci, pts, col, 3.0 * s)
			ci.draw_line(c + Vector2(0, -11) * s, c + Vector2(0, 11) * s, P.OUTLINE, 2.0 * s, true)
		"spike_shield":
			for k in 8:
				var d := Vector2.from_angle(TAU * k / 8.0)
				ci.draw_line(c + d * 9.0 * s, c + d * 15.0 * s, P.OUTLINE, 3.0 * s, true)
			P.blob(ci, c, Vector2(10, 10) * s, col, 3.0 * s)
			P.blob(ci, c, Vector2(3, 3) * s, P.OUTLINE, 0.0)
		"brass_key", "rusty_key":
			ci.draw_arc(c + Vector2(-6, 0) * s, 6.0 * s, 0.0, TAU, 14, P.OUTLINE, 6.0 * s, true)
			ci.draw_arc(c + Vector2(-6, 0) * s, 6.0 * s, 0.0, TAU, 14, col, 3.0 * s, true)
			ci.draw_line(c + Vector2(0, 0) * s, c + Vector2(13, 0) * s, P.OUTLINE, 6.0 * s, true)
			ci.draw_line(c + Vector2(0, 0) * s, c + Vector2(13, 0) * s, col, 3.0 * s, true)
			ci.draw_line(c + Vector2(9, 0) * s, c + Vector2(9, 6) * s, P.OUTLINE, 4.0 * s, true)
			ci.draw_line(c + Vector2(13, 0) * s, c + Vector2(13, 5) * s, P.OUTLINE, 4.0 * s, true)
		"miner_helmet":
			P.blob(ci, c + Vector2(0, 2) * s, Vector2(12, 9) * s, col, 3.0 * s)
			ci.draw_line(c + Vector2(-13, 6) * s, c + Vector2(13, 6) * s, P.OUTLINE, 3.0 * s, true)
			P.blob(ci, c + Vector2(0, -3) * s, Vector2(4, 4) * s, Color("fffbe0"), 2.0 * s)
		"pot_helmet":
			P.shape(ci, P.rounded_rect_points(Rect2(c + Vector2(-11, -7) * s, Vector2(22, 13) * s), 4.0 * s), col, 3.0 * s)
			ci.draw_line(c + Vector2(10, -2) * s, c + Vector2(17, -6) * s, P.OUTLINE, 4.0 * s, true)
		"leaf_hood":
			P.shape(ci, PackedVector2Array([c + Vector2(-12, 8) * s, c + Vector2(0, -12) * s, c + Vector2(12, 8) * s]), col, 3.0 * s)
			ci.draw_line(c + Vector2(0, -8) * s, c + Vector2(0, 6) * s, Color("5fb35f"), 2.0 * s, true)
		"overalls":
			P.shape(ci, P.rounded_rect_points(Rect2(c + Vector2(-10, -10) * s, Vector2(20, 22) * s), 5.0 * s), col, 3.0 * s)
			ci.draw_circle(c + Vector2(-5, -5) * s, 2.0 * s, P.OUTLINE)
			ci.draw_circle(c + Vector2(5, -5) * s, 2.0 * s, P.OUTLINE)
		"raincoat":
			P.shape(ci, PackedVector2Array([c + Vector2(-8, -11) * s, c + Vector2(8, -11) * s, c + Vector2(13, 11) * s, c + Vector2(-13, 11) * s]), col, 3.0 * s)
			ci.draw_line(c + Vector2(0, -10) * s, c + Vector2(0, 10) * s, P.OUTLINE, 2.0 * s, true)
		"hermes_boots", "steel_toes", "wellies":
			P.shape(ci, PackedVector2Array([c + Vector2(-8, -11) * s, c + Vector2(0, -11) * s, c + Vector2(1, 4) * s, c + Vector2(11, 6) * s, c + Vector2(11, 11) * s, c + Vector2(-8, 11) * s]), col, 3.0 * s)
			if id == "hermes_boots":
				P.blob(ci, c + Vector2(-12, -6) * s, Vector2(6, 3) * s, Color.WHITE, 2.0 * s)
			elif id == "steel_toes":
				P.blob(ci, c + Vector2(7, 8) * s, Vector2(5, 4) * s, Color("d3dae0"), 2.0 * s)
		"stamina_acorn":
			P.blob(ci, c + Vector2(0, 3) * s, Vector2(8, 9) * s, col, 3.0 * s)
			P.blob(ci, c + Vector2(0, -6) * s, Vector2(10, 5) * s, Color("8a6a4a"), 2.5 * s)
		"feather_pin":
			ci.draw_line(c + Vector2(-9, 10) * s, c + Vector2(8, -10) * s, P.OUTLINE, 3.0 * s, true)
			P.blob(ci, c + Vector2(3, -4) * s, Vector2(5, 10) * s, col, 2.5 * s)
		"ember_charm":
			P.blob(ci, c, Vector2(9, 9) * s, col, 3.0 * s)
			P.blob(ci, c + Vector2(0, 1) * s, Vector2(4, 6) * s, Color("fff27a"), 0.0)
		"glow_pebble":
			P.blob(ci, c, Vector2(9, 7) * s, col, 3.0 * s)
			ci.draw_circle(c + Vector2(-3, -2) * s, 2.0 * s, Color.WHITE)
		_:
			P.blob(ci, c, Vector2(8, 8) * s, col, 3.0 * s)


## A sickle: a wooden handle with a brass collar, and a crescent blade that grows out of
## the collar, curves up over the top and round, and ends in a point. The blade is one
## closed shape (broad near the handle, tapering to the tip), so it reads cleanly at any size.
static func _sickle(ci: CanvasItem, c: Vector2, s: float, blade_col: Color) -> void:
	var grip := c + Vector2(-13, 10) * s
	var collar := c + Vector2(-8.5, -2) * s
	var r_out := 11.0 * s
	var a0 := deg_to_rad(190.0)
	var a1 := deg_to_rad(410.0)
	var centre := collar - Vector2.from_angle(a0) * r_out   # so the blade starts at the collar
	ci.draw_line(grip, collar, P.OUTLINE, 7.0 * s, true)
	ci.draw_line(grip, collar, P.WOOD, 3.5 * s, true)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var n := 18
	for k in n + 1:
		var t := float(k) / n
		var a := lerpf(a0, a1, t)
		var thick := (0.6 + 5.2 * pow(1.0 - t, 0.7) * minf(1.0, t * 6.0 + 0.35)) * s
		outer.append(centre + Vector2.from_angle(a) * r_out)
		inner.append(centre + Vector2.from_angle(a) * (r_out - thick))
	inner.reverse()
	var blade := outer + inner
	ci.draw_colored_polygon(blade, blade_col)
	var edge := blade.duplicate()
	edge.append(blade[0])
	ci.draw_polyline(edge, P.OUTLINE, 2.2 * s, true)
	P.blob(ci, collar + Vector2(0, -0.5) * s, Vector2(3.2, 3.2) * s, Color("e3b04b"), 2.0 * s)


static func count_badge(ci: CanvasItem, pos: Vector2, n: int, size: int = 13) -> void:
	var txt := str(n)
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8.0
	var r := Rect2(pos - Vector2(w, size + 4.0), Vector2(w, size + 4.0))
	P.shape(ci, P.rounded_rect_points(r, 6.0), Color.WHITE, 2.0)
	ci.draw_string(font, r.position + Vector2(4, size), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, P.OUTLINE)
