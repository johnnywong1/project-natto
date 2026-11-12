extends Node
## The `Display` autoload: window mode and size, kept in user://settings.cfg (the same
## file the sound volumes use) and applied when the game starts.
##   * Modes: windowed, fullscreen, borderless (a borderless window the size of the screen).
##   * Sizes: a few presets for windowed mode. The game scales to any size (the project
##     uses the "canvas_items" stretch mode with "expand"), so dragging the window edge
##     works too.
##   * F11 toggles fullscreen from anywhere.
## The Settings screen (game/ui/settings_panel.gd) is the UI for this.

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const MODES := ["windowed", "fullscreen", "borderless"]
const MODE_NAMES := {"windowed": "Windowed", "fullscreen": "Fullscreen", "borderless": "Borderless window"}
const SIZES: Array[Vector2i] = [Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var mode := "windowed"
var size := Vector2i(1152, 648)
var vsync := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		set_mode("windowed" if mode != "windowed" else "fullscreen")
		get_viewport().set_input_as_handled()


func set_mode(m: String) -> void:
	if m not in MODES:
		return
	mode = m
	apply()
	_save()
	changed.emit()


func set_size(s: Vector2i) -> void:
	size = s
	if mode != "windowed":
		mode = "windowed"
	apply()
	_save()
	changed.emit()


func set_vsync(on: bool) -> void:
	vsync = on
	apply()
	_save()
	changed.emit()


func size_name(s: Vector2i) -> String:
	return "%d x %d" % [s.x, s.y]


## Puts the window in the chosen mode. Does nothing headless (tests). In a browser only
## fullscreen vs. in-page works (the page itself sets the size), so sizes and vsync are skipped.
func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if mode == "windowed" else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var screen := DisplayServer.screen_get_usable_rect()
			var s := Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
			if DisplayServer.window_get_size() != s:
				DisplayServer.window_set_size(s)
				DisplayServer.window_set_position(screen.position + (screen.size - s) / 2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	var m := str(cfg.get_value("display", "mode", mode))
	if m in MODES:
		mode = m
	var s: Variant = cfg.get_value("display", "size", size)
	if s is Vector2i and (s as Vector2i).x >= 640 and (s as Vector2i).y >= 360:
		size = s
	vsync = bool(cfg.get_value("display", "vsync", vsync))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "mode", mode)
	cfg.set_value("display", "size", size)
	cfg.set_value("display", "vsync", vsync)
	cfg.save(SETTINGS_PATH)
