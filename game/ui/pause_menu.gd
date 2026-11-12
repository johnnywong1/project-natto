extends Control
## The menu you get with Esc (or Start), from the game or from any open screen:
##   * Resume: back to what you were doing (the bag or map reopens if it was open).
##   * Settings: sound volumes (Master, Music, Sound effects).
##   * Controls: every button.
##   * Exit / Logout: leave this game and go to the title screen. Solo or hosting, the world
##     saves first. If you're the host, this ends the game for everyone: they're all sent
##     back to the title screen. If you joined someone, only you leave.
## It also shows the day, the time and how long you've played. In a solo world it really
## pauses; online, the world keeps going for everyone else.

signal closed

const UiTheme = preload("res://game/ui/ui_theme.gd")
const ControlsPanel = preload("res://game/ui/controls_panel.gd")
const SettingsPanel = preload("res://game/ui/settings_panel.gd")

var _box: PanelContainer
var _title: Label
var _info: Label
var _resume_btn: Button
var _exit_btn: Button
var _controls: ControlsPanel
var _settings: SettingsPanel
var _confirm_exit := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS   # still works while a solo game is paused
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.make()
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = PanelContainer.new()
	_box.custom_minimum_size = Vector2(400, 0)
	center.add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_box.add_child(v)
	_title = UiTheme.heading("Menu", 28)
	v.add_child(_title)
	_info = UiTheme.note("")
	v.add_child(_info)
	_resume_btn = UiTheme.button("Resume", close, 320)
	v.add_child(_resume_btn)
	v.add_child(UiTheme.button("Settings", _show_settings, 320))
	v.add_child(UiTheme.button("Controls", _show_controls, 320))
	_exit_btn = UiTheme.button("Exit / Logout", _exit, 320)
	v.add_child(_exit_btn)
	_controls = ControlsPanel.new()
	_controls.visible = false
	_controls.closed.connect(_back_to_menu)
	center.add_child(_controls)
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(_back_to_menu)
	center.add_child(_settings)


func open() -> void:
	visible = true
	_back_to_menu()
	_confirm_exit = false
	_title.text = "Paused" if Net.solo else "Menu"
	_exit_btn.text = _exit_label()
	_refresh_info()
	if Net.solo:
		get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _exit_label() -> String:
	if Net.solo:
		return "Exit (saves your world)" if World.save_slot > 0 else "Exit"
	if Net.is_host():
		return "Exit / Logout (ends the game for everyone)"
	return "Exit / Logout"


func _process(_delta: float) -> void:
	if visible:
		_refresh_info()


func _refresh_info() -> void:
	var where := "Solo world"
	if not Net.solo:
		where = ("You're hosting  ·  %d players" if Net.is_host() else "%d players") % Net.players.size()
	var saving := ""
	if Net.is_host():
		saving = ("\nSaves to slot %d by itself, and when you exit." % World.save_slot) if World.save_slot > 0 else "\nThis world isn't saved."
	_info.text = "%s  ·  Day %d, %s\nPlayed %s in this world (%s this time)%s" % [where, World.day, World.clock_text(),
		UiTheme.duration(World.play_time), UiTheme.duration(World.session_time), saving]


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _controls.visible or _settings.visible:
			_back_to_menu()
		else:
			close()


func _show_controls() -> void:
	_box.visible = false
	_controls.visible = true


func _show_settings() -> void:
	_box.visible = false
	_settings.visible = true


func _back_to_menu() -> void:
	_controls.visible = false
	_settings.visible = false
	_box.visible = true
	_resume_btn.grab_focus.call_deferred()


func _exit() -> void:
	# The host ending a game with friends in it gets asked twice.
	if Net.is_host() and not Net.solo and Net.players.size() > 1 and not _confirm_exit:
		_confirm_exit = true
		_exit_btn.text = "Sure? This sends all %d players home" % Net.players.size()
		return
	get_tree().paused = false
	Net.leave(true)
