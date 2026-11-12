extends PanelContainer
## The Settings screen (from the Esc menu or the title screen):
##   * Sound: Master, Music and Sound effects volume (game/audio/sound.gd).
##   * Display: window mode, window size and vsync (game/display/display_settings.gd).
## Changes apply at once and are kept between sessions. Emits `closed` on Back (or Esc).

signal closed

const UiTheme = preload("res://game/ui/ui_theme.gd")

const ROWS := [["Master volume", "Master"], ["Music volume", "Music"], ["Sound effects volume", "SFX"]]

var _values: Dictionary = {}   # bus -> Label showing the percentage
var _mode: OptionButton
var _size: OptionButton
var _vsync: CheckButton


func _ready() -> void:
	theme = UiTheme.make()
	custom_minimum_size = Vector2(520, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	add_child(v)
	v.add_child(UiTheme.heading("Settings", 28))
	v.add_child(UiTheme.heading("Sound", 18))
	for row: Array in ROWS:
		var bus: String = row[1]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var l := Label.new()
		l.text = row[0]
		l.custom_minimum_size = Vector2(200, 0)
		h.add_child(l)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = 100
		s.step = 5
		s.value = roundf(float(Sound.volumes[bus]) * 100.0)
		s.custom_minimum_size = Vector2(200, 28)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(_on_changed.bind(bus))
		h.add_child(s)
		var pct := Label.new()
		pct.custom_minimum_size = Vector2(54, 0)
		pct.text = "%d%%" % int(s.value)
		h.add_child(pct)
		_values[bus] = pct
		v.add_child(h)
	v.add_child(UiTheme.heading("Display", 18))
	_mode = OptionButton.new()
	for m: String in Display.MODES:
		_mode.add_item(Display.MODE_NAMES[m])
	_mode.item_selected.connect(func(i: int) -> void: Display.set_mode(Display.MODES[i]))
	v.add_child(_row("Window mode", _mode))
	_size = OptionButton.new()
	for sz: Vector2i in Display.SIZES:
		_size.add_item(Display.size_name(sz))
	_size.item_selected.connect(func(i: int) -> void: Display.set_size(Display.SIZES[i]))
	var size_row := _row("Window size", _size)
	size_row.visible = not OS.has_feature("web")   # the browser page sets the size
	v.add_child(size_row)
	_vsync = CheckButton.new()
	_vsync.text = "On"
	_vsync.toggled.connect(func(on: bool) -> void: Display.set_vsync(on))
	var vsync_row := _row("Vsync", _vsync)
	vsync_row.visible = not OS.has_feature("web")
	v.add_child(vsync_row)
	v.add_child(UiTheme.note("F11 toggles fullscreen. You can also drag the window to any size."))
	Display.changed.connect(_refresh_display)
	_refresh_display()
	var back := UiTheme.button("Back", func() -> void: closed.emit(), 160)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(back)


func _row(title: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(200, 0)
	h.add_child(l)
	control.custom_minimum_size = Vector2(200, 0)
	h.add_child(control)
	return h


func _refresh_display() -> void:
	_mode.selected = Display.MODES.find(Display.mode)
	var si := Display.SIZES.find(Display.size)
	_size.selected = si
	_size.disabled = Display.mode != "windowed"
	_vsync.set_pressed_no_signal(Display.vsync)


func _on_changed(value: float, bus: String) -> void:
	Sound.set_volume(bus, value / 100.0)
	(_values[bus] as Label).text = "%d%%" % int(value)
	if bus != "Music":
		Sound.play("ui")


func _unhandled_input(event: InputEvent) -> void:
	# is_visible_in_tree, not visible: this panel sits inside the Esc menu, and when only
	# its parent is hidden it must not swallow Esc.
	if is_visible_in_tree() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		get_viewport().set_input_as_handled()
		closed.emit()
