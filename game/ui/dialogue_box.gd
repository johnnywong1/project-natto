extends Control
## A speech box at the bottom of the screen for villagers (Pepper's lessons). Shows one
## line at a time; E shows the next line. You can keep walking while it's open. New lines
## that arrive while it's open are queued up. While Pepper is talking, Backspace skips her
## lessons for players who already know the game.

const P = preload("res://game/ui/palette.gd")
const Lessons = preload("res://game/data/lessons.gd")

const WIDTH := 640.0
const HEIGHT := 118.0

var speaker := ""
var _lines: Array = []
var _shown := 0.0   # how many characters of the current line are showing (typewriter)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func say(who: String, lines: Array) -> void:
	if visible and who == speaker:
		_lines.append_array(lines)
		return
	speaker = who
	_lines = lines.duplicate()
	_shown = 0.0
	visible = not _lines.is_empty()


## Shows the rest of the line, or the next line, or closes.
func next() -> void:
	if _lines.is_empty():
		close()
		return
	var line: String = _lines[0]
	if _shown < line.length():
		_shown = line.length()
		return
	_lines.pop_front()
	_shown = 0.0
	if _lines.is_empty():
		close()


func close() -> void:
	visible = false
	_lines.clear()


func box_rect() -> Rect2:
	return Rect2(Vector2((size.x - WIDTH) / 2.0, size.y - HEIGHT - 132.0), Vector2(WIDTH, HEIGHT))


func _process(delta: float) -> void:
	if visible:
		_shown += delta * 60.0
		queue_redraw()


func _draw() -> void:
	if _lines.is_empty():
		return
	var r := box_rect()
	P.shape(self, P.rounded_rect_points(r, 18.0), Color(P.CREAM, 0.97), 4.0)
	# Portrait: Pepper's face in a circle.
	var face := r.position + Vector2(56, 58)
	P.blob(self, face, Vector2(36, 36), Color("fff0d6"), 3.0)
	P.blob(self, face + Vector2(0, 6), Vector2(22, 21), P.SKIN, 3.0)
	P.face(self, face + Vector2(0, 7), 1.1, false)
	P.blob(self, face + Vector2(0, -15), Vector2(25, 12), P.PEPPER_RED, 3.0)
	var font := ThemeDB.fallback_font
	draw_string(font, r.position + Vector2(108, 30), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.OUTLINE)
	var line: String = _lines[0]
	draw_multiline_string(font, r.position + Vector2(108, 56), line.left(int(_shown)), HORIZONTAL_ALIGNMENT_LEFT,
		WIDTH - 128.0, 16, 3, P.OUTLINE)
	var more := "E: next" if _lines.size() > 1 else "E: done"
	var hint := more
	if speaker == "Pepper" and int(World.vitals.get("lesson", {}).get("i", 0)) < Lessons.count():
		hint += "    Backspace: skip the lessons"
	var font_w: float = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, r.end - Vector2(font_w + 16.0, 12), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.OUTLINE.lightened(0.3))
