extends Node2D
## A campfire, brazier, street lamp or house fireplace: a flickering flame with a real light.
## Torches relight next to any of these (press E). Lamps only light up at night.

const P = preload("res://game/ui/palette.gd")
const Avatar = preload("res://game/world/avatar.gd")
const DayNight = preload("res://game/world/day_night.gd")

var kind := "campfire"    # campfire, brazier, lamp, fireplace
var _t := 0.0
var _light: PointLight2D


func _ready() -> void:
	_t = randf() * 10.0
	_light = PointLight2D.new()
	_light.texture = Avatar.radial_texture()
	_light.texture_scale = 1.7 if kind == "lamp" else 2.4
	_light.energy = 1.15
	_light.color = Color("ffc070") if kind == "lamp" else Color("ff9a4a")
	_light.position = Vector2(0, -70) if kind == "lamp" else Vector2(0, -20)
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	var on := kind != "lamp" or World.clock >= 18.5 * 60.0 or World.clock < 6.5 * 60.0
	var k := DayNight.light_scale()
	_light.enabled = on and k > 0.0
	var base := 0.7 if kind == "lamp" else 0.95
	_light.energy = (base + sin(_t * 19.0) * 0.05 + sin(_t * 6.1) * 0.06) * k
	queue_redraw()


func _flame(at: Vector2, s: float) -> void:
	var f := 1.0 + sin(_t * 17.0) * 0.12
	P.blob(self, at, Vector2(10, 16) * s * f, Color("ff8a3a"), 3.0)
	P.blob(self, at + Vector2(0, 4) * s, Vector2(5, 8) * s * f, Color("fff27a"), 0.0)


func _draw() -> void:
	match kind:
		"campfire":
			P.shadow(self, Vector2(0, 6), Vector2(34, 10))
			for k in 6:
				var a := TAU * k / 6.0
				P.blob(self, Vector2(cos(a) * 26.0, sin(a) * 10.0 + 2.0), Vector2(8, 6), P.STONE, 2.5)
			draw_line(Vector2(-18, 4), Vector2(16, -6), P.OUTLINE, 9.0, true)
			draw_line(Vector2(-18, 4), Vector2(16, -6), P.WOOD, 5.0, true)
			draw_line(Vector2(-16, -6), Vector2(18, 4), P.OUTLINE, 9.0, true)
			draw_line(Vector2(-16, -6), Vector2(18, 4), P.WOOD, 5.0, true)
			_flame(Vector2(0, -14), 1.3)
		"fireplace":
			_flame(Vector2(-12, -6), 0.9)
			_flame(Vector2(10, -4), 1.1)
		"brazier":
			P.shadow(self, Vector2(0, 4), Vector2(22, 7))
			draw_line(Vector2(-12, 0), Vector2(-6, -26), P.OUTLINE, 5.0, true)
			draw_line(Vector2(12, 0), Vector2(6, -26), P.OUTLINE, 5.0, true)
			P.blob(self, Vector2(0, -28), Vector2(20, 9), Color("8a7a6a"))
			_flame(Vector2(0, -42), 1.0)
		"lamp":
			draw_line(Vector2.ZERO, Vector2(0, -64), P.OUTLINE, 9.0, true)
			draw_line(Vector2.ZERO, Vector2(0, -64), Color("8a6a52"), 4.0, true)
			var on := World.clock >= 18.5 * 60.0 or World.clock < 6.5 * 60.0
			P.blob(self, Vector2(0, -72), Vector2(11, 11), Color("ffe7a0") if on else Color("fff1b0"), 3.0)
			if on:
				P.blob(self, Vector2(0, -72), Vector2(5, 6), Color("ff9a4a"), 0.0)
