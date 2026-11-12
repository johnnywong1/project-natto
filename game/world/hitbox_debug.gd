extends Node2D
## The hitbox debug view (press F3 in game). Draws, on the ground:
##   * every body's hurtbox: green for players (inner ring = what enemy attacks must touch,
##     outer ring = the body that bumps into things), orange for enemies;
##   * every attack this player's game judged, for a moment: your sickle swings, torch jabs
##     and kicks, and enemy attacks as they land (red = it hit, white = it missed).
## The shapes come straight from game/combat/hitboxes.gd, the same code the host uses.

const HB = preload("res://game/combat/hitboxes.gd")
const P = preload("res://game/ui/palette.gd")

const SHOW_FOR := 0.4

var world: Variant
var _flashes: Array = []   # [shape, hit, seconds left]


func _ready() -> void:
	z_index = 100


func flash(shape: Dictionary, hit: bool) -> void:
	_flashes.append([shape, hit, SHOW_FOR])
	if _flashes.size() > 40:
		_flashes.pop_front()


func _process(delta: float) -> void:
	for f: Array in _flashes:
		f[2] = float(f[2]) - delta
	_flashes = _flashes.filter(func(f: Array) -> bool: return float(f[2]) > 0.0)
	if visible:
		queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var players: Array = [world.local]
	players.append_array(world.remotes.values())
	for av: Node2D in players:
		_outline(HB.circle(av.position, HB.PLAYER_BODY), Color(0.3, 0.9, 0.4, 0.5), 2.0)
		_outline(HB.player_hurtbox(av.position), Color(0.2, 1.0, 0.35, 0.95), 3.0)
	for eid: int in world.enemy_nodes:
		var en: Variant = world.enemy_nodes[eid]
		if is_instance_valid(en):
			_outline(HB.enemy_hurtbox(en.kind, en.position), Color(1.0, 0.6, 0.15, 0.95), 3.0)
	for f: Array in _flashes:
		var a := clampf(float(f[2]) / SHOW_FOR, 0.0, 1.0)
		var col := Color(1.0, 0.2, 0.2, a) if bool(f[1]) else Color(1, 1, 1, a)
		var pts := HB.outline_points(f[0])
		if pts.size() >= 4:
			draw_colored_polygon(pts.slice(0, pts.size() - 1), Color(col, 0.18 * a))   # last point repeats the first
		draw_polyline(pts, col, 3.0, true)
	var font := ThemeDB.fallback_font
	var at: Vector2 = world.local.position + Vector2(-90, 60)
	draw_string(font, at, "Hitbox view (F3 to hide)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _outline(shape: Dictionary, col: Color, width: float) -> void:
	draw_polyline(HB.outline_points(shape), col, width, true)
