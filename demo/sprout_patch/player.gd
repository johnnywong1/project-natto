extends Node2D
## Hoodie kid. Walks, hops (the blob shadow marks the landing spot) and swings a sickle.
## The game controller listens to `swung` to work out what the sickle hits.

signal swung(origin: Vector2, facing: Vector2)

const P = preload("res://game/ui/palette.gd")
const SPEED := 230.0
const HOP_TIME := 0.42
const HOP_HEIGHT := 30.0
const SWING_TIME := 0.22
const BOUNDS := Rect2(30, 120, 1092, 500)

var facing := Vector2.DOWN
## Round things the kid can't walk through: x, y = center, z = radius.
var blockers: Array[Vector3] = []
var hop_t := 0.0
var swing_t := 0.0
var bonk_t := 0.0
var _knock := Vector2.ZERO
var _walk := 0.0
var _moving := false


func is_airborne() -> bool:
	return hop_t > 0.0


func height() -> float:
	if hop_t <= 0.0:
		return 0.0
	return sin((1.0 - hop_t / HOP_TIME) * PI) * HOP_HEIGHT


## Bumped by a Wilt. Hopping makes you immune, like a hop-dodge.
func bonk(from: Vector2) -> void:
	if is_airborne() or bonk_t > 0.0:
		return
	_knock = (global_position - from).normalized() * 420.0
	bonk_t = 0.6


func _process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_moving = dir.length() > 0.1
	if _moving:
		facing = dir.normalized()
		_walk += delta * 12.0
	position += (dir * SPEED + _knock) * delta
	_knock = _knock.move_toward(Vector2.ZERO, 900.0 * delta)
	for b in blockers:
		var center := Vector2(b.x, b.y)
		var away := position - center
		if away.length() < b.z and away.length() > 0.01:
			position = center + away.normalized() * b.z
	position = position.clamp(BOUNDS.position, BOUNDS.end)
	hop_t = maxf(hop_t - delta, 0.0)
	swing_t = maxf(swing_t - delta, 0.0)
	bonk_t = maxf(bonk_t - delta, 0.0)
	if Input.is_action_just_pressed("hop") and hop_t <= 0.0:
		hop_t = HOP_TIME
	if Input.is_action_just_pressed("swing") and swing_t <= 0.0:
		swing_t = SWING_TIME
		swung.emit(global_position, facing)
	modulate.a = 0.45 if bonk_t > 0.0 and int(bonk_t * 20.0) % 2 == 0 else 1.0
	queue_redraw()


func _draw() -> void:
	var h := height()
	var shrink: float = 1.0 - h / HOP_HEIGHT * 0.35
	P.shadow(self, Vector2.ZERO, Vector2(18, 7) * shrink)
	var bob: float = absf(sin(_walk)) * 2.5 if _moving and h == 0.0 else 0.0
	var up := Vector2(0, -h - bob)
	var step: float = sin(_walk) * 3.0 if _moving else 0.0
	P.blob(self, up + Vector2(-7, -3.0 + step), Vector2(6, 4), P.CREAM, 3.0)
	P.blob(self, up + Vector2(7, -3.0 - step), Vector2(6, 4), P.CREAM, 3.0)
	P.blob(self, up + Vector2(0, -18), Vector2(16, 15), P.HOODIE)
	P.blob(self, up + Vector2(0, -41), Vector2(20, 19), P.HOODIE)
	if facing.y < -0.6:
		P.blob(self, up + Vector2(0, -42), Vector2(13, 12), P.HOODIE.darkened(0.12), 3.0)
	else:
		var look: float = clampf(facing.x, -1.0, 1.0) * 3.0
		P.blob(self, up + Vector2(look, -40), Vector2(14, 13), P.SKIN, 3.0)
		P.face(self, up + Vector2(look, -40), 0.85, swing_t > 0.0 or h > 0.0)
	if swing_t > 0.0:
		_draw_sickle(up + Vector2(0, -20))


func _draw_sickle(center: Vector2) -> void:
	var k: float = 1.0 - swing_t / SWING_TIME
	var a0: float = facing.angle() - 1.3
	var a1: float = a0 + 2.6 * maxf(k, 0.05)
	draw_arc(center, 44.0, a0, a1, 18, P.OUTLINE, 13.0, true)
	draw_arc(center, 44.0, a0, a1, 18, P.CREAM, 7.0, true)
	P.blob(self, center + Vector2.from_angle(a1) * 44.0, Vector2(7, 7), P.STONE, 3.0)
