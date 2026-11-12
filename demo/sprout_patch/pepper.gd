extends Node2D
## Pepper, a Middlemost villager who hands out the demo's quest.
## The controller sets `bubble` ("!" new quest, "?" ready to hand in) and `cheer_t`.

const P = preload("res://game/ui/palette.gd")

var bubble := ""
var cheer_t := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	cheer_t = maxf(cheer_t - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	var hop: float = absf(sin(_t * 12.0)) * 10.0 if cheer_t > 0.0 else 0.0
	var breathe: float = sin(_t * 2.0) * 1.2
	var up := Vector2(0, -hop)
	P.shadow(self, Vector2.ZERO, Vector2(18, 7))
	P.blob(self, up + Vector2(-7, -3), Vector2(6, 4), P.WOOD, 3.0)
	P.blob(self, up + Vector2(7, -3), Vector2(6, 4), P.WOOD, 3.0)
	P.blob(self, up + Vector2(0, -19), Vector2(17, 16.0 + breathe), P.DRESS)
	P.blob(self, up + Vector2(0, -42), Vector2(15, 14), P.SKIN)
	P.face(self, up + Vector2(0, -41), 0.85, cheer_t > 0.0)
	P.blob(self, up + Vector2(0, -56), Vector2(17, 9), P.PEPPER_RED)
	draw_line(up + Vector2(0, -63), up + Vector2(5, -73), P.OUTLINE, 7.0, true)
	draw_line(up + Vector2(0, -63), up + Vector2(5, -73), P.LEAF, 3.5, true)
	if bubble != "":
		var b := up + Vector2(0, -98.0 + sin(_t * 4.0) * 3.0)
		P.blob(self, b, Vector2(15, 15), Color.WHITE, 3.0)
		P.text(self, b + Vector2(0, 8), bubble, 22)
