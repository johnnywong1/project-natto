extends Node
## Regression checks for the title screen (game/menu/main_menu.gd), driven like a player
## would: buttons pressed, keys typed, Esc to go back.
##   godot --headless --path . -- --menu-test
## Covers: the pages (home, worlds, join, settings, controls), name and colour, the solo
## world list, hosting a room from the menu (and leaving it), and Esc going back a page.
## Uses save slot 8 as scratch and deletes it afterwards. Prints PASS/FAIL per check and
## quits with code 1 if anything failed. Started by game/net/net.gd when --menu-test is given.

const SaveGame = preload("res://game/save/save_game.gd")
const SCRATCH_SLOT := 8

var _passed := 0
var _failed := 0
var _menu: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for i in 120:
		await get_tree().process_frame
		_menu = get_tree().current_scene
		if _menu != null and _menu.get("_pages") != null:
			break
	check("the title screen is the main scene", _menu != null and _menu.scene_file_path == Net.MENU_SCENE)
	if _menu == null or _menu.get("_pages") == null:
		_finish()
		return
	await _frames(3)
	var pages: Dictionary = _menu.get("_pages")
	check("it opens on the home page", _page() == "home" and (pages["home"] as Control).visible)
	for want: String in ["Play solo", "Host a game", "Join a game", "Settings", "Controls", "Quit"]:
		check("home has a \"%s\" button" % want, _button(want) != null)

	# Name and colour.
	var name_edit: LineEdit = _menu.get("_name")
	name_edit.text = "Tester"
	name_edit.text_changed.emit("Tester")
	check("typing a name sets your name", Net.local_name == "Tester")
	var colors: Array = _menu.get("_colors")
	(colors[2] as Button).pressed.emit()
	check("picking a hoodie colour sets it", Net.local_color == 2)

	# Pages and Esc.
	for pair: Array in [["Controls", "controls"], ["Settings", "settings"], ["Join a game", "join"]]:
		_button(pair[0]).pressed.emit()
		await _frames(2)
		check("\"%s\" opens the %s page" % [pair[0], pair[1]], _page() == pair[1] and (pages[pair[1]] as Control).visible)
		await _key(KEY_ESCAPE)
		check("Esc goes back home from %s" % pair[1], _page() == "home")

	# Solo worlds page.
	SaveGame.delete(SCRATCH_SLOT)
	_button("Play solo").pressed.emit()
	await _frames(2)
	check("\"Play solo\" opens the world list", _page() == "worlds" and str(_menu.get("_worlds_mode")) == "solo")
	var slot_list: VBoxContainer = _menu.get("_slot_list")
	check("the list shows one row per slot", slot_list.get_child_count() == SaveGame.SLOT_COUNT, str(slot_list.get_child_count()))
	check("the port row is hidden for solo play", not (_menu.get("_port_row") as Control).visible)
	await _key(KEY_ESCAPE)

	# Hosting from the menu opens the room with you in it; Leave closes it.
	_button("Host a game").pressed.emit()
	await _frames(2)
	check("\"Host a game\" shows the port for friends", _page() == "worlds" and (_menu.get("_port_row") as Control).visible)
	(_menu.get("_port") as LineEdit).text = "7811"
	_menu.call("_play", SCRATCH_SLOT)
	await _frames(5)
	check("hosting opens the room page", _page() == "room" and Net.is_host() and Net.is_online())
	check("the room lists you as the host", Net.players.size() == 1 and Net.player_name(1) == "Tester")
	var start: Button = _menu.get("_start_btn")
	check("the host sees a Start button", start != null and start.visible and start.text.begins_with("Start"))
	check("a joiner's Ready switch is hidden for the host", not (_menu.get("_ready_btn") as Control).visible)
	_button("Leave").pressed.emit()
	await _frames(3)
	check("Leave closes the room and goes home", _page() == "home" and not Net.is_online() and Net.players.is_empty())

	# Joining nothing fails politely.
	_button("Join a game").pressed.emit()
	await _frames(2)
	(_menu.get("_address") as LineEdit).text = "127.0.0.1"
	var row: HBoxContainer = (_menu.get("_address") as Control).get_parent()
	var port_edit: LineEdit = row.get_child(1)
	port_edit.text = "7899"   # nobody is hosting there
	_menu.call("_join", port_edit)
	await _frames(2)
	check("Join moves to the room while connecting", _page() == "room")
	var back_home := false
	for i in 150:   # up to 15 s for the connection attempt to give up
		await get_tree().create_timer(0.1).timeout
		if _page() == "home":
			back_home = true
			break
	check("a failed connection returns you home with a message", back_home and not Net.is_online(), (_menu.get("_status") as Label).text)
	SaveGame.delete(SCRATCH_SLOT)
	_finish()


func _page() -> String:
	return str(_menu.get("_page"))


## The visible button with this text, anywhere on the title screen.
func _button(text: String, root: Node = null) -> Button:
	if root == null:
		root = _menu
	for c in root.get_children():
		var b := c as Button
		if b != null and b.text == text and b.is_visible_in_tree():
			return b
		var deeper := _button(text, c)
		if deeper != null:
			return deeper
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await get_tree().process_frame


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print(("PASS  " if ok else "FAIL  ") + name + (("   [" + detail + "]") if detail != "" else ""))


func _finish() -> void:
	print("\n%d/%d menu checks passed" % [_passed, _passed + _failed])
	get_tree().quit(1 if _failed > 0 else 0)
