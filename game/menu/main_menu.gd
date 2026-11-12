extends Control
## The title screen (the game's main scene). Pages:
##   * Home: your name and hoodie colour, then Play solo, Host a game, Join a game,
##     Controls and Quit.
##   * Worlds: pick a save slot to play solo or host in: continue a saved world, start a new
##     one, or delete one. Each slot shows its day, time, play time and who has played.
##   * Join: type the host's address, or pick a game found on your network.
##   * Room: who's here before the host presses Start (up to 5). Friends can still join
##     after the game has started.
##   * Controls: every button.
## Esc goes back a page.

const P = preload("res://game/ui/palette.gd")
const UiTheme = preload("res://game/ui/ui_theme.gd")
const SaveGame = preload("res://game/save/save_game.gd")
const ControlsPanel = preload("res://game/ui/controls_panel.gd")
const SettingsPanel = preload("res://game/ui/settings_panel.gd")

var _pages: Dictionary = {}      # page name -> Control
var _page := "home"
var _worlds_mode := "solo"       # "solo" or "host": what picking a world slot does
var _name: LineEdit
var _colors: Array[Button] = []
var _port: LineEdit
var _address: LineEdit
var _slot_list: VBoxContainer
var _worlds_title: Label
var _port_row: HBoxContainer
var _lan_list: VBoxContainer
var _players: VBoxContainer
var _room_hint: Label
var _ready_btn: CheckButton
var _start_btn: Button
var _status: Label
var _confirm_delete := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()
	_build()
	Net.lobby_changed.connect(_refresh_room)
	Net.status_changed.connect(_on_status)
	Net.lan_games_changed.connect(_refresh_lan)
	_status.text = Net.status
	_show("room" if Net.is_online() else "home")
	Sound.start_music()


func _exit_tree() -> void:
	Net.stop_listening()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), P.GRASS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 140:
		var t := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
		draw_line(t, t + Vector2(-4, -9), P.GRASS_DARK, 3.0, true)
		draw_line(t, t + Vector2(3, -10), P.GRASS_DARK, 3.0, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		if _page in ["worlds", "join", "controls", "settings"]:
			_show("home")
			get_viewport().set_input_as_handled()


func _on_status(text: String) -> void:
	_status.text = text
	if not Net.is_online() and _page == "room":
		_show("home")


# ---------------------------------------------------------------- pages

func _show(page: String) -> void:
	_page = page
	_confirm_delete = -1
	for k: String in _pages:
		(_pages[k] as Control).visible = k == page
	if page == "join":
		Net.start_listening()
		_refresh_lan()
	else:
		Net.stop_listening()
	if page == "worlds":
		_refresh_worlds()
	if page == "room":
		_refresh_room()
	var first := _first_button(_pages[page])
	if first != null:
		first.grab_focus.call_deferred()


func _first_button(n: Node) -> Button:
	for c in n.get_children():
		var b := c as Button
		if b != null and b.visible and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			return b
		var deeper := _first_button(c)
		if deeper != null:
			return deeper
	return null


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(root)
	var title := UiTheme.heading("Project Natto", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var sub := UiTheme.heading("A cozy co-op farming adventure for 1 to 5 players", 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)
	var holder := CenterContainer.new()
	root.add_child(holder)
	_pages["home"] = _build_home()
	_pages["worlds"] = _build_worlds()
	_pages["join"] = _build_join()
	_pages["room"] = _build_room()
	var controls := ControlsPanel.new()
	controls.closed.connect(func() -> void: _show("home"))
	_pages["controls"] = controls
	var settings := SettingsPanel.new()
	settings.closed.connect(func() -> void: _show("home"))
	_pages["settings"] = settings
	for k: String in _pages:
		holder.add_child(_pages[k])
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


func _panel(min_width: float) -> Array:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	return [panel, v]


func _build_home() -> Control:
	var pv := _panel(460)
	var v: VBoxContainer = pv[1]
	v.add_child(UiTheme.heading("You", 22))
	var name_row := HBoxContainer.new()
	_name = LineEdit.new()
	_name.text = Net.local_name
	_name.max_length = 16
	_name.custom_minimum_size = Vector2(200, 0)
	_name.tooltip_text = "Your name. Saved worlds remember your things by name."
	_name.text_changed.connect(func(t: String) -> void: Net.local_name = t)
	name_row.add_child(_name)
	for i in Net.COLORS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(36, 36)
		b.tooltip_text = "Hoodie colour"
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pick_color.bind(i))
		name_row.add_child(b)
		_colors.append(b)
	v.add_child(name_row)
	_paint_colors()
	v.add_child(HSeparator.new())
	for entry: Array in [["Play solo", func() -> void: _open_worlds("solo")],
			["Host a game", func() -> void: _open_worlds("host")],
			["Join a game", func() -> void: _show("join")],
			["Settings", func() -> void: _show("settings")],
			["Controls", func() -> void: _show("controls")],
			["Quit", func() -> void: get_tree().quit()]]:
		var b := UiTheme.button(entry[0], entry[1], 300)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(b)
	return pv[0]


func _open_worlds(mode: String) -> void:
	_worlds_mode = mode
	_show("worlds")


func _build_worlds() -> Control:
	var pv := _panel(660)
	var v: VBoxContainer = pv[1]
	_worlds_title = UiTheme.heading("Pick a world", 24)
	v.add_child(_worlds_title)
	v.add_child(UiTheme.note("Worlds save by themselves every couple of minutes and when you leave. Everyone's things are kept by name."))
	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override("separation", 8)
	v.add_child(_slot_list)
	_port_row = HBoxContainer.new()
	var pl := Label.new()
	pl.text = "Port (friends need this)"
	_port_row.add_child(pl)
	_port = LineEdit.new()
	_port.text = str(Net.DEFAULT_PORT)
	_port.custom_minimum_size = Vector2(100, 0)
	_port_row.add_child(_port)
	v.add_child(_port_row)
	v.add_child(UiTheme.button("Back", func() -> void: _show("home"), 140))
	return pv[0]


func _refresh_worlds() -> void:
	_worlds_title.text = "Play solo: pick a world" if _worlds_mode == "solo" else "Host a game: pick a world"
	_port_row.visible = _worlds_mode == "host"
	for c in _slot_list.get_children():
		c.queue_free()
	for slot in range(1, SaveGame.SLOT_COUNT + 1):
		var info := SaveGame.describe(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if info.is_empty():
			l.text = "Slot %d: empty" % slot
			row.add_child(l)
			row.add_child(UiTheme.button("New world", _play.bind(slot), 150))
		else:
			var m := int(info["clock"])
			@warning_ignore("integer_division")
			var clock := "%02d:%02d" % [m / 60, m % 60]
			var when := Time.get_datetime_string_from_unix_time(int(info["saved_at"]) + _tz_offset(), true)
			l.text = "Slot %d: %s\nDay %d, %s  ·  played %s  ·  %s\nSaved %s" % [slot, info["name"], int(info["day"]), clock,
				UiTheme.duration(float(info["play_time"])), ", ".join(PackedStringArray(info["players"])), when.left(16)]
			row.add_child(l)
			row.add_child(UiTheme.button("Continue", _play.bind(slot), 130))
			var del := Button.new()
			del.text = "Delete"
			del.custom_minimum_size = Vector2(110, 0)
			del.pressed.connect(_delete.bind(slot, del))
			row.add_child(del)
		_slot_list.add_child(row)


func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _delete(slot: int, b: Button) -> void:
	if _confirm_delete != slot:
		_confirm_delete = slot
		b.text = "Sure?"
		return
	SaveGame.delete(slot)
	_confirm_delete = -1
	_refresh_worlds()


func _play(slot: int) -> void:
	Net.save_slot = slot
	if _worlds_mode == "solo":
		Net.play_solo(slot)
	else:
		if Net.host(int(_port.text)) == OK:
			_show("room")


func _build_join() -> Control:
	var pv := _panel(560)
	var v: VBoxContainer = pv[1]
	v.add_child(UiTheme.heading("Join a friend", 24))
	var row := HBoxContainer.new()
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	_address.placeholder_text = "Host's address"
	_address.custom_minimum_size = Vector2(230, 0)
	row.add_child(_address)
	var port := LineEdit.new()
	port.text = str(Net.DEFAULT_PORT)
	port.custom_minimum_size = Vector2(90, 0)
	row.add_child(port)
	row.add_child(UiTheme.button("Join", _join.bind(port), 110))
	v.add_child(row)
	v.add_child(UiTheme.heading("Games on your network", 18))
	_lan_list = VBoxContainer.new()
	v.add_child(_lan_list)
	v.add_child(UiTheme.button("Back", func() -> void: _show("home"), 140))
	return pv[0]


func _join(port_edit: LineEdit) -> void:
	if Net.join(_address.text.strip_edges(), int(port_edit.text)) == OK:
		_show("room")


func _join_lan(ip: String, port: int) -> void:
	if Net.join(ip, port) == OK:
		_show("room")


func _leave_room() -> void:
	Net.leave(false)
	_show("home")


func _refresh_lan() -> void:
	if _lan_list == null:
		return
	for c in _lan_list.get_children():
		c.queue_free()
	if Net.lan_games.is_empty():
		_lan_list.add_child(UiTheme.note("None found yet. Games hosted on your Wi-Fi show up here."))
		return
	for key: String in Net.lan_games:
		var g: Dictionary = Net.lan_games[key]
		var line := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s's game  %d/%d%s" % [str(g["name"]), int(g["count"]), Net.MAX_PLAYERS, "  (playing)" if bool(g["in_game"]) else ""]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		var b := UiTheme.button("Join", _join_lan.bind(str(g["ip"]), int(g["port"])))
		b.disabled = Net.is_online() or int(g["count"]) >= Net.MAX_PLAYERS
		line.add_child(b)
		_lan_list.add_child(line)


func _build_room() -> Control:
	var pv := _panel(480)
	var v: VBoxContainer = pv[1]
	v.add_child(UiTheme.heading("Room", 24))
	_players = VBoxContainer.new()
	_players.add_theme_constant_override("separation", 6)
	v.add_child(_players)
	_room_hint = UiTheme.note("")
	v.add_child(_room_hint)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	_ready_btn = CheckButton.new()
	_ready_btn.text = "Ready"
	_ready_btn.toggled.connect(func(on: bool) -> void: Net.set_ready(on))
	btns.add_child(_ready_btn)
	_start_btn = UiTheme.button("Start", Net.start_game)
	btns.add_child(_start_btn)
	btns.add_child(UiTheme.button("Leave", _leave_room))
	v.add_child(btns)
	return pv[0]


func _refresh_room() -> void:
	if _players == null:
		return
	if Net.is_online() and _page != "room" and not Net.in_game:
		_show("room")
		return
	for c in _players.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	var waiting := 0
	for id: int in ids:
		var p: Dictionary = Net.players[id]
		var line := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.color = p["color"]
		dot.custom_minimum_size = Vector2(22, 22)
		line.add_child(dot)
		var l := Label.new()
		var tags := "  (host)" if id == 1 else ("  ready" if bool(p["ready"]) else "  not ready")
		if id != 1 and not bool(p["ready"]):
			waiting += 1
		if id == Net.me():
			tags += "  - you"
		l.text = "%s%s" % [str(p["name"]), tags]
		line.add_child(l)
		_players.add_child(line)
	for i in range(ids.size(), Net.MAX_PLAYERS):
		var empty := Label.new()
		empty.text = "( open slot )"
		empty.modulate = Color(1, 1, 1, 0.5)
		_players.add_child(empty)
	_ready_btn.visible = Net.is_online() and not Net.is_host()
	_start_btn.visible = Net.is_host()
	if Net.is_host():
		_room_hint.text = "Friends join with your computer's address and port %s. %s" % [_port.text,
			"Everyone's ready!" if waiting == 0 else "Waiting on %d to ready up (you can start anyway)." % waiting]
		_start_btn.text = "Start (%d/%d)" % [ids.size(), Net.MAX_PLAYERS]
	elif Net.is_online():
		_room_hint.text = "Tick Ready. The host starts the game."
	else:
		_room_hint.text = "Connecting..."


func _pick_color(i: int) -> void:
	Net.local_color = i
	_paint_colors()


func _paint_colors() -> void:
	for i in _colors.size():
		var s := StyleBoxFlat.new()
		s.bg_color = Net.COLORS[i]
		s.border_color = P.OUTLINE
		s.set_border_width_all(5 if i == Net.local_color else 2)
		s.set_corner_radius_all(18)
		for state in ["normal", "hover", "pressed", "focus"]:
			_colors[i].add_theme_stylebox_override(state, s)
