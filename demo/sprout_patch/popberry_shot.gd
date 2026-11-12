extends Node2D
## A thrown popberry. Flies in an arc to its target, then splats. The controller
## listens to `splatted` and hurts any Wilt inside the splash.

signal splatted(at: Vector2)

const P = preload("res://game/ui/palette.gd")
const FLIGHT := 0.45
const ARC := 70.0
const SPLAT_TIME := 0.4

var start := Vector2.ZERO
var target := Vector2.ZERO
var t := 0.0
var splat_t := 0.0


func setup(from: Vector2, to: Vector2) -> void:
	start = from
	target = to
	global_position = from


func _process(delta: float) -> void:
	queue_redraw()
	if splat_t > 0.0:
		splat_t -= delta
		if splat_t <= 0.0:
			queue_free()
		return
	t += delta
	var k: float = minf(t / FLIGHT, 1.0)
	global_position = start.lerp(target, k)
	if k >= 1.0:
		splat_t = SPLAT_TIME
		splatted.emit(global_position)


func _draw() -> void:
	if splat_t > 0.0:
		var k: float = 1.0 - splat_t / SPLAT_TIME
		var r: float = lerpf(10.0, 52.0, k)
		var col := Color(P.BERRY, 1.0 - k)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 6.0 * (1.0 - k) + 1.0, true)
		for n in 7:
			var a: float = TAU * float(n) / 7.0
			draw_circle(Vector2.from_angle(a) * r * 0.8, 5.0 * (1.0 - k) + 1.0, col)
		return
	var h: float = sin(minf(t / FLIGHT, 1.0) * PI) * ARC
	P.shadow(self, Vector2.ZERO, Vector2(9, 4))
	P.blob(self, Vector2(0, -h - 8.0), Vector2(9, 9), P.BERRY, 3.0)
	draw_circle(Vector2(-3, -h - 11.0), 2.5, P.BERRY_SHINE)
