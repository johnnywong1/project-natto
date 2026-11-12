extends Node2D
## Mildew Wilt: a damp blob from Lord Mildew's cellar. It creeps to the nearest crop and
## nibbles it back to bare soil. Two sickle hits or one popberry splat pops it.

signal defeated(wilt: Node2D, by_popberry: bool)

const P = preload("res://game/ui/palette.gd")
const SoilGrid = preload("res://demo/sprout_patch/soil_grid.gd")
const Player = preload("res://demo/sprout_patch/player.gd")
const SPEED := 46.0
const EAT_TIME := 3.0
const POP_TIME := 0.35
const SPAWN_TIME := 0.4

var grid: SoilGrid
var player: Player
var hp := 2
var target_plot := -1
var eat_t := 0.0
var _flash := 0.0
var _knock := Vector2.ZERO
var _t := 0.0
var _pop := 0.0
var _spawn := SPAWN_TIME
var _loiter := Vector2.ZERO
var _loiter_t := 0.0


func is_alive() -> bool:
	return _pop <= 0.0


func hit(damage: int, from: Vector2, by_popberry: bool) -> void:
	if not is_alive():
		return
	hp -= damage
	_flash = 0.15
	eat_t = 0.0
	_knock = (global_position - from).normalized() * 320.0
	if hp <= 0:
		_pop = POP_TIME
		defeated.emit(self, by_popberry)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _pop > 0.0:
		_pop -= delta
		if _pop <= 0.0:
			queue_free()
		return
	_spawn = maxf(_spawn - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	position += _knock * delta
	_knock = _knock.move_toward(Vector2.ZERO, 700.0 * delta)
	_pick_target()
	var goal: Vector2
	if target_plot >= 0:
		goal = grid.plot_global(target_plot)
	else:
		# Nothing to nibble: loiter around the patch instead of hounding the player.
		_loiter_t -= delta
		if _loiter_t <= 0.0 or global_position.distance_to(_loiter) < 8.0:
			_loiter_t = randf_range(2.0, 4.0)
			_loiter = grid.global_position + Vector2(randf_range(-260.0, 260.0), randf_range(-140.0, 140.0))
		goal = _loiter
	var to_goal := goal - global_position
	if target_plot >= 0 and to_goal.length() < 12.0:
		eat_t += delta
		if eat_t >= EAT_TIME:
			grid.eat(target_plot)
			eat_t = 0.0
			target_plot = -1
	else:
		eat_t = 0.0
		var speed: float = SPEED if target_plot >= 0 else SPEED * 0.6
		global_position += to_goal.normalized() * speed * delta
	if global_position.distance_to(player.global_position) < 30.0:
		player.bonk(global_position)


func _pick_target() -> void:
	if target_plot >= 0 and grid.stages[target_plot] == SoilGrid.Stage.EMPTY:
		target_plot = -1
	if target_plot >= 0:
		return
	var best_d := INF
	for i in grid.planted_plots():
		var d := grid.plot_global(i).distance_to(global_position)
		if d < best_d:
			best_d = d
			target_plot = i


func _draw() -> void:
	var c := Vector2(0, -16)
	if _pop > 0.0:
		var k: float = 1.0 - _pop / POP_TIME
		var col := Color(P.MILDEW, 1.0 - k)
		for n in 6:
			var a: float = TAU * float(n) / 6.0
			draw_circle(c + Vector2.from_angle(a) * (10.0 + 30.0 * k), 7.0 * (1.0 - k) + 1.0, col)
		return
	var s: float = maxf(1.0 - _spawn / SPAWN_TIME, 0.1)
	var wob: float = sin(_t * 6.0) * 1.6
	var chomp: bool = eat_t > 0.0 and fmod(_t, 0.3) < 0.15
	var body: Color = Color.WHITE if _flash > 0.0 else P.MILDEW
	c *= s
	P.shadow(self, Vector2.ZERO, Vector2(20, 7) * s)
	P.blob(self, c, Vector2(21.0 + wob, 17.0 - wob) * s, body)
	draw_circle(c + Vector2(-10, 8) * s, 3.5 * s, P.MILDEW_DARK)
	draw_circle(c + Vector2(12, 5) * s, 2.5 * s, P.MILDEW_DARK)
	draw_circle(c + Vector2(4, -10) * s, 3.0 * s, P.MILDEW_DARK)
	draw_arc(c + Vector2(-7, -2) * s, 4.0 * s, 0.0, PI, 8, P.OUTLINE, 3.0, true)
	draw_arc(c + Vector2(7, -2) * s, 4.0 * s, 0.0, PI, 8, P.OUTLINE, 3.0, true)
	if chomp:
		P.blob(self, c + Vector2(0, 7) * s, Vector2(6, 5) * s, P.MOUTH, 2.0)
	else:
		draw_line(c + Vector2(-4, 7) * s, c + Vector2(4, 7) * s, P.OUTLINE, 3.0, true)
	P.blob(self, c + Vector2(0, -17) * s, Vector2(11, 6) * s, P.MILDEW_DARK, 3.0)
