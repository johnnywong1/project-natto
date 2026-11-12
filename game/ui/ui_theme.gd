extends RefCounted
## The look of every menu (title screen, pause menu, controls): cream panels with thick
## brown outlines and butter-yellow buttons, to match the Sticker Pop art.

const P = preload("res://game/ui/palette.gd")


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var panel := StyleBoxFlat.new()
	panel.bg_color = P.CREAM
	panel.border_color = P.OUTLINE
	panel.set_border_width_all(4)
	panel.set_corner_radius_all(22)
	panel.set_content_margin_all(20)
	t.set_stylebox("panel", "PanelContainer", panel)
	var fills := {"normal": Color("ffe08a"), "hover": Color("ffeaa8"), "pressed": Color("f5cf6a"),
		"disabled": Color("e8e1d4"), "focus": Color("ffe08a")}
	for state: String in fills:
		var b := StyleBoxFlat.new()
		b.bg_color = fills[state]
		b.border_color = P.OUTLINE if state != "focus" else Color("5fb35f")
		b.set_border_width_all(3)
		b.set_corner_radius_all(14)
		b.content_margin_left = 16
		b.content_margin_right = 16
		b.content_margin_top = 8
		b.content_margin_bottom = 8
		if state == "focus":
			b.draw_center = false
		t.set_stylebox(state, "Button", b)
	for state in ["normal", "focus"]:
		var e := StyleBoxFlat.new()
		e.bg_color = Color.WHITE
		e.border_color = P.OUTLINE if state == "normal" else Color("5fb35f")
		e.set_border_width_all(3)
		e.set_corner_radius_all(12)
		e.set_content_margin_all(8)
		t.set_stylebox(state, "LineEdit", e)
	for type_name in ["Label", "Button", "LineEdit", "CheckButton"]:
		t.set_color("font_color", type_name, P.OUTLINE)
	t.set_color("font_hover_color", "Button", P.OUTLINE)
	t.set_color("font_pressed_color", "Button", P.OUTLINE)
	t.set_color("font_focus_color", "Button", P.OUTLINE)
	t.set_color("font_disabled_color", "Button", Color(P.OUTLINE, 0.5))
	t.set_color("font_hover_color", "CheckButton", P.OUTLINE)
	t.set_color("font_pressed_color", "CheckButton", P.OUTLINE)
	t.set_color("caret_color", "LineEdit", P.OUTLINE)
	return t


static func heading(text: String, size_px: int = 24) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	return l


static func note(text: String, size_px: int = 15) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size_px)
	l.modulate = Color(1, 1, 1, 0.8)
	return l


static func button(text: String, on_press: Callable, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 0)
	b.pressed.connect(func() -> void: Sound.play("ui"))
	b.pressed.connect(on_press)
	return b


## "1h 05m" or "12m" or "40s".
static func duration(seconds: float) -> String:
	var s := int(seconds)
	@warning_ignore("integer_division")
	var h := s / 3600
	@warning_ignore("integer_division")
	var m := (s % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	if m > 0:
		return "%dm" % m
	return "%ds" % s
