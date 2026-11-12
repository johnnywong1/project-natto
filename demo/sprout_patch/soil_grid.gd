extends Node2D
## A 5x3 patch of soil, centered on this node. Each plot holds one popberry plant.
## Stages: EMPTY -> plant -> SEED -> water -> SPROUT -> water -> RIPE -> harvest -> EMPTY.
## Watering darkens the soil and starts a short growth timer.

signal plot_changed(index: int)

const P = preload("res://game/ui/palette.gd")
const COLS := 5
const ROWS := 3
const TILE := Vector2(76, 58)
const GAP := 10.0
const GROW_TIME := 2.5
const BERRY_SPOTS: Array[Vector2] = [Vector2(-12, -12), Vector2(10, -16), Vector2(-2, -3), Vector2(14, -2)]

enum Stage { EMPTY, SEED, SPROUT, RIPE }

var stages: Array[int] = []
var grow_left: Array[float] = []
var highlight := -1
var origin := Vector2.ZERO
var _t := 0.0


func _ready() -> void:
	origin = -grid_size() / 2.0
	for i in COLS * ROWS:
		stages.append(Stage.EMPTY)
		grow_left.append(0.0)


func grid_size() -> Vector2:
	return Vector2(COLS * TILE.x + (COLS - 1) * GAP, ROWS * TILE.y + (ROWS - 1) * GAP)


func plot_center(i: int) -> Vector2:
	var col: int = i % COLS
	@warning_ignore("integer_division")
	var row: int = i / COLS
	return origin + Vector2(col * (TILE.x + GAP), row * (TILE.y + GAP)) + TILE / 2.0


func plot_global(i: int) -> Vector2:
	return to_global(plot_center(i))


## Index of the plot nearest to a global point within reach, or -1.
func plot_at(global_point: Vector2, reach: float) -> int:
	var best := -1
	var best_d := reach
	for i in stages.size():
		var d := plot_global(i).distance_to(global_point)
		if d < best_d:
			best_d = d
			best = i
	return best


func is_wet(i: int) -> bool:
	return grow_left[i] > 0.0


func plant(i: int) -> bool:
	if stages[i] != Stage.EMPTY:
		return false
	stages[i] = Stage.SEED
	_changed(i)
	return true


func water(i: int) -> bool:
	if stages[i] == Stage.EMPTY or stages[i] == Stage.RIPE or is_wet(i):
		return false
	grow_left[i] = GROW_TIME
	_changed(i)
	return true


func harvest(i: int) -> bool:
	if stages[i] != Stage.RIPE:
		return false
	stages[i] = Stage.EMPTY
	_changed(i)
	return true


## A Wilt finished nibbling this plot.
func eat(i: int) -> void:
	stages[i] = Stage.EMPTY
	grow_left[i] = 0.0
	_changed(i)


func planted_plots() -> Array[int]:
	var out: Array[int] = []
	for i in stages.size():
		if stages[i] != Stage.EMPTY:
			out.append(i)
	return out


func _process(delta: float) -> void:
	_t += delta
	for i in stages.size():
		if grow_left[i] > 0.0:
			grow_left[i] -= delta
			if grow_left[i] <= 0.0:
				grow_left[i] = 0.0
				stages[i] = mini(stages[i] + 1, Stage.RIPE)
				_changed(i)
	queue_redraw()


func _changed(i: int) -> void:
	plot_changed.emit(i)
	queue_redraw()


func _draw() -> void:
	for i in stages.size():
		var c := plot_center(i)
		var rect := Rect2(c - TILE / 2.0, TILE)
		var soil: Color = P.SOIL_WET if is_wet(i) else P.SOIL_DRY
		P.shape(self, P.rounded_rect_points(rect, 12.0), soil)
		for k in 3:
			var y: float = rect.position.y + 15.0 + k * 14.0
			draw_line(Vector2(rect.position.x + 14.0, y), Vector2(rect.end.x - 14.0, y), soil.darkened(0.15), 3.0, true)
		_draw_plant(i, c)
		if i == highlight:
			P.outline(self, P.rounded_rect_points(rect.grow(6.0), 16.0), Color(1, 1, 1, 0.95), 4.0)


func _draw_plant(i: int, c: Vector2) -> void:
	var stage: int = stages[i]
	var sway: float = sin(_t * 2.5 + float(i)) * 2.0
	if stage == Stage.SEED:
		P.blob(self, c + Vector2(0, 6), Vector2(14, 7), P.SOIL_MOUND, 3.0)
		P.blob(self, c + Vector2(0, 2), Vector2(5, 4), P.CREAM, 2.5)
	elif stage == Stage.SPROUT:
		draw_line(c + Vector2(0, 10), c + Vector2(sway, -12), P.OUTLINE, 7.0, true)
		draw_line(c + Vector2(0, 10), c + Vector2(sway, -12), P.LEAF, 3.0, true)
		P.blob(self, c + Vector2(-9.0 + sway, -14), Vector2(9, 5), P.LEAF, 3.0)
		P.blob(self, c + Vector2(9.0 + sway, -17), Vector2(9, 5), P.LEAF, 3.0)
	elif stage == Stage.RIPE:
		var bob: float = sin(_t * 3.0 + float(i)) * 1.5
		P.blob(self, c + Vector2(0, -6.0 + bob), Vector2(27, 20), P.LEAF)
		for o in BERRY_SPOTS:
			P.blob(self, c + o + Vector2(0, bob), Vector2(7, 7), P.BERRY, 3.0)
			draw_circle(c + o + Vector2(-2, -2.0 + bob), 2.0, P.BERRY_SHINE)
	if stage == Stage.SEED or stage == Stage.SPROUT:
		var bubble := c + Vector2(26, -22)
		if is_wet(i):
			var k: float = 1.0 - grow_left[i] / GROW_TIME
			P.blob(self, bubble, Vector2(11, 11), Color.WHITE, 3.0)
			draw_arc(bubble, 6.0, -PI / 2.0, -PI / 2.0 + TAU * maxf(k, 0.02), 20, P.WATER, 4.0, true)
		elif fmod(_t, 1.2) < 0.85:
			P.blob(self, bubble, Vector2(11, 11), Color.WHITE, 3.0)
			P.blob(self, bubble + Vector2(0, 1), Vector2(4.5, 5.5), P.WATER, 2.0)
