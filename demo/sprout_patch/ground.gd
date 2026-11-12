extends Node2D
## Static backdrop for the Sprout Patch: meadow, fence, path, the well and Pepper's notice post.

const P = preload("res://game/ui/palette.gd")
const VIEW := Vector2(1152, 648)
const WELL_POS := Vector2(170, 360)
const POST_POS := Vector2(1010, 215)

var _tufts: Array[Vector2] = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 80:
		_tufts.append(Vector2(rng.randf_range(20.0, VIEW.x - 20.0), rng.randf_range(130.0, 530.0)))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), P.GRASS)
	draw_rect(Rect2(0, 0, VIEW.x, 96), P.MEADOW)
	for t in _tufts:
		draw_line(t, t + Vector2(-4, -9), P.GRASS_DARK, 3.0, true)
		draw_line(t, t + Vector2(3, -10), P.GRASS_DARK, 3.0, true)
	_draw_fence()
	_draw_path()
	_draw_well()
	_draw_post()


func _draw_fence() -> void:
	for y: float in [62.0, 84.0]:
		draw_rect(Rect2(0, y, VIEW.x, 8), P.WOOD)
		draw_line(Vector2(0, y), Vector2(VIEW.x, y), P.OUTLINE, 3.0)
		draw_line(Vector2(0, y + 8.0), Vector2(VIEW.x, y + 8.0), P.OUTLINE, 3.0)
	var x := 24.0
	while x < VIEW.x:
		P.shape(self, P.rounded_rect_points(Rect2(x - 8.0, 46, 16, 56), 6.0), P.WOOD, 3.0)
		x += 80.0


func _draw_path() -> void:
	var edge := PackedVector2Array([Vector2(0, 575), Vector2(380, 560), Vector2(780, 568), Vector2(VIEW.x, 552)])
	var pts := edge.duplicate()
	pts.append(Vector2(VIEW.x, VIEW.y))
	pts.append(Vector2(0, VIEW.y))
	draw_colored_polygon(pts, P.PATH)
	draw_polyline(edge, P.OUTLINE, 4.0, true)
	for i in 9:
		var s := Vector2(60.0 + i * 125.0, 600.0 + (i % 2) * 12.0)
		P.blob(self, s, Vector2(14, 7), P.STONE, 3.0)


func _draw_well() -> void:
	var c := WELL_POS
	P.shadow(self, c + Vector2(0, 22), Vector2(58, 14))
	P.shape(self, P.rounded_rect_points(Rect2(c.x - 50.0, c.y - 86.0, 12, 90), 5.0), P.WOOD, 3.0)
	P.shape(self, P.rounded_rect_points(Rect2(c.x + 38.0, c.y - 86.0, 12, 90), 5.0), P.WOOD, 3.0)
	P.shape(self, PackedVector2Array([c + Vector2(-66, -78), c + Vector2(0, -116), c + Vector2(66, -78)]), P.PEPPER_RED)
	P.blob(self, c, Vector2(48, 28), P.STONE)
	P.blob(self, c + Vector2(0, -5), Vector2(33, 15), P.WATER, 3.0)
	P.text(self, c + Vector2(0, 52), "WELL", 16)


func _draw_post() -> void:
	var c := POST_POS
	P.shape(self, P.rounded_rect_points(Rect2(c.x - 5.0, c.y - 40.0, 10, 50), 4.0), P.WOOD, 3.0)
	P.shape(self, P.rounded_rect_points(Rect2(c.x - 36.0, c.y - 78.0, 72, 46), 8.0), P.CREAM, 3.0)
	for k in 3:
		var y: float = c.y - 66.0 + k * 11.0
		draw_line(Vector2(c.x - 24.0, y), Vector2(c.x + 24.0 - k * 8.0, y), P.OUTLINE.lightened(0.4), 3.0)
