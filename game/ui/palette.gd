extends RefCounted
## Sticker Pop colours and drawing helpers: thick brown outlines over flat pastel fills.
## Everything in the game (and the Sprout Patch demo) is drawn with these in code, so
## there are no image files yet.

const OUTLINE := Color("5b3a29")
const LINE := 4.0
const GRASS := Color("c5e8a5")
const GRASS_DARK := Color("a9d98a")
const MEADOW := Color("d8f0c2")
const PATH := Color("f3dfb6")
const SOIL_DRY := Color("cf9f70")
const SOIL_WET := Color("8f6548")
const SOIL_MOUND := Color("b98a5e")
const LEAF := Color("86d47e")
const BERRY := Color("ff8fb1")
const BERRY_SHINE := Color("ffe0ea")
const WATER := Color("8fd3ff")
const HOODIE := Color("9fdcc8")
const SKIN := Color("ffd9b8")
const MOUTH := Color("e8566b")
const MILDEW := Color("cbb9ec")
const MILDEW_DARK := Color("a68fd6")
const CREAM := Color("fff6e5")
const PEPPER_RED := Color("ff7a6b")
const DRESS := Color("ffe08a")
const STONE := Color("d3dae0")
const WOOD := Color("e3b37f")
const SHADOW := Color(0.36, 0.23, 0.16, 0.22)


static func ellipse_points(center: Vector2, radius: Vector2, segments: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return pts


static func rounded_rect_points(rect: Rect2, r: float) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.45)   # a corner bigger than the box folds over itself
	var pts := PackedVector2Array()
	var centers: Array[Vector2] = [
		rect.position + Vector2(rect.size.x - r, r),
		rect.position + Vector2(rect.size.x - r, rect.size.y - r),
		rect.position + Vector2(r, rect.size.y - r),
		rect.position + Vector2(r, r),
	]
	for c in 4:
		var start: float = -PI / 2.0 + PI / 2.0 * float(c)
		for i in 6:
			var a: float = start + PI / 2.0 * float(i) / 5.0
			pts.append(centers[c] + Vector2(cos(a), sin(a)) * r)
	return pts


static func outline(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float = LINE) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, color, width, true)


static func shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, width: float = LINE) -> void:
	ci.draw_colored_polygon(pts, fill)
	outline(ci, pts, OUTLINE, width)


static func blob(ci: CanvasItem, center: Vector2, radius: Vector2, fill: Color, width: float = LINE) -> void:
	shape(ci, ellipse_points(center, radius), fill, width)


static func shadow(ci: CanvasItem, center: Vector2, radius: Vector2) -> void:
	ci.draw_colored_polygon(ellipse_points(center, radius, 20), SHADOW)


static func face(ci: CanvasItem, center: Vector2, s: float, mouth_open: bool = true) -> void:
	ci.draw_circle(center + Vector2(-6.0, -2.0) * s, 2.8 * s, OUTLINE)
	ci.draw_circle(center + Vector2(6.0, -2.0) * s, 2.8 * s, OUTLINE)
	ci.draw_circle(center + Vector2(-5.0, -3.0) * s, 0.9 * s, Color.WHITE)
	ci.draw_circle(center + Vector2(7.0, -3.0) * s, 0.9 * s, Color.WHITE)
	if mouth_open:
		shape(ci, ellipse_points(center + Vector2(0.0, 6.0) * s, Vector2(4.5, 3.6) * s, 14), MOUTH, 2.0)
	else:
		ci.draw_arc(center + Vector2(0.0, 3.0) * s, 4.0 * s, 0.3, PI - 0.3, 10, OUTLINE, 2.0, true)


static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color = OUTLINE) -> void:
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, pos - Vector2(w / 2.0, 0.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
