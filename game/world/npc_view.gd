extends Node2D
## A villager standing in the world. For now that's Pepper, who teaches the lessons
## (game/data/lessons.gd). Shows a "!" over her head until you've said hello, and a
## "Talk (E)" hint when you're close enough to talk.

const P = preload("res://game/ui/palette.gd")
const Lessons = preload("res://game/data/lessons.gd")

var npc_name := "Pepper"
var talk_range := 95.0
var world: Variant
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var breathe: float = sin(_t * 2.0) * 1.2
	P.shadow(self, Vector2.ZERO, Vector2(18, 7))
	P.blob(self, Vector2(-7, -3), Vector2(6, 4), P.WOOD, 3.0)
	P.blob(self, Vector2(7, -3), Vector2(6, 4), P.WOOD, 3.0)
	P.blob(self, Vector2(0, -19), Vector2(17, 16.0 + breathe), P.DRESS)
	P.blob(self, Vector2(0, -42), Vector2(15, 14), P.SKIN)
	P.face(self, Vector2(0, -41), 0.85, false)
	P.blob(self, Vector2(0, -56), Vector2(17, 9), P.PEPPER_RED)
	draw_line(Vector2(0, -63), Vector2(5, -73), P.OUTLINE, 7.0, true)
	draw_line(Vector2(0, -63), Vector2(5, -73), P.LEAF, 3.5, true)
	# Name tag
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(npc_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var tag := Rect2(Vector2(-w / 2.0 - 8.0, -100), Vector2(w + 16.0, 22))
	P.shape(self, P.rounded_rect_points(tag, 9.0), Color("fff0d6"), 2.5)
	draw_string(font, tag.position + Vector2(8, 16), npc_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.OUTLINE)
	# The talk hint sits above the name tag, where your own character can't cover it, and
	# hides while she's talking.
	var talking: bool = world != null and world.hud.dialogue.visible
	var near: bool = world != null and (world.local.position as Vector2).distance_to(position) < talk_range
	var top := -100.0
	if near and not talking:
		var hw: float = font.get_string_size("Talk (E)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var hr := Rect2(Vector2(-hw / 2.0 - 8.0, -128), Vector2(hw + 16.0, 22))
		P.shape(self, P.rounded_rect_points(hr, 9.0), Color("ffe08a"), 2.5)
		draw_string(font, hr.position + Vector2(8, 16), "Talk (E)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.OUTLINE)
		top = -128.0
	var lesson: Dictionary = World.vitals.get("lesson", {})
	if int(lesson.get("i", 0)) == 0 and not talking:
		var b := Vector2(0, top - 24.0 + sin(_t * 4.0) * 3.0)
		P.blob(self, b, Vector2(14, 14), Color("ffe08a"), 3.0)
		P.text(self, b + Vector2(0, 8), "!", 22)
