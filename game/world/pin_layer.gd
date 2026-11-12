extends Node2D
## Map pins that belong to the zone you're in, drawn in the world so friends can find them.

const P = preload("res://game/ui/palette.gd")

var zone := ""
var _t := 0.0


func _ready() -> void:
	World.pins_changed.connect(queue_redraw)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for pid: int in World.pins:
		var pin: Dictionary = World.pins[pid]
		if pin["zone"] != zone:
			continue
		var pos: Vector2 = pin["pos"]
		var col: Color = pin["color"]
		var bob := sin(_t * 2.5 + float(pid)) * 4.0
		P.shadow(self, pos, Vector2(14, 5))
		draw_line(pos, pos + Vector2(0, -40 + bob), P.OUTLINE, 5.0, true)
		P.blob(self, pos + Vector2(0, -48 + bob), Vector2(13, 13), col)
		draw_circle(pos + Vector2(-4, -52 + bob), 3.5, Color(1, 1, 1, 0.8))
		var text := "%s  (%s)" % [str(pin["label"]), str(pin["name"])]
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tag := Rect2(pos + Vector2(-w / 2.0 - 8.0, -92 + bob), Vector2(w + 16.0, 24))
		P.shape(self, P.rounded_rect_points(tag, 9.0), P.CREAM, 3.0)
		draw_string(font, tag.position + Vector2(8, 17), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.OUTLINE)
