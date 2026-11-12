extends Node
## Checks the in-game screens react to real key presses: Esc opens the pause menu from the
## game, the bag, the map and the controls screen, and Resume brings that screen back;
## Esc inside Settings goes back to the menu; Exit returns to the title screen.
##   godot --headless --path . -- --solo --ui-test
## (No --slot, so nothing is saved.) Prints PASS/FAIL per check and quits with code 1 if
## anything failed. Started by game/net/net.gd when --ui-test is given.

var _passed := 0
var _failed := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps running while the solo game is paused
	_run.call_deferred()


func _run() -> void:
	# Wait for the world to load.
	for i in 300:
		await get_tree().process_frame
		var s := get_tree().current_scene
		if s != null and s.get("hud") != null and Net.in_game:
			break
	var game: Node = get_tree().current_scene
	check("the solo world started", game != null and game.get("hud") != null)
	if game == null or game.get("hud") == null:
		_finish()
		return
	var hud: Node = game.hud
	var menu: Control = hud.pause_menu
	for i in 10:
		await get_tree().process_frame

	await _key(KEY_ESCAPE)
	check("Esc in game opens the pause menu", menu.visible)
	check("the solo game pauses", get_tree().paused)
	await _key(KEY_ESCAPE)
	check("Esc again closes it", not menu.visible and not get_tree().paused)

	for screen: Array in [["the bag", KEY_I, hud.inventory_panel], ["the map", KEY_M, hud.map_panel], ["the controls screen", KEY_F1, hud.controls]]:
		var panel: Control = screen[2]
		await _key(screen[1])
		check("%s opens" % screen[0], panel.visible)
		await _key(KEY_ESCAPE)
		check("Esc over %s opens the pause menu" % screen[0], menu.visible and not panel.visible)
		await _key(KEY_ESCAPE)
		check("Resume from over %s lands in the game" % screen[0], not menu.visible and not panel.visible)
		await _key(screen[1])
		check("%s opens again with its own key" % screen[0], panel.visible)
		await _key(screen[1])
		check("%s closes with its own key" % screen[0], not panel.visible)

	await _key(KEY_ESCAPE)
	menu.call("_show_settings")
	await get_tree().process_frame
	var settings: Control = menu.get("_settings")
	check("Settings opens from the pause menu", settings.is_visible_in_tree())
	await _key(KEY_ESCAPE)
	check("Esc in Settings goes back to the menu", menu.visible and not settings.visible)
	await _key(KEY_ESCAPE)
	check("Esc again resumes", not menu.visible)

	await _key(KEY_ESCAPE)
	menu.call("_exit")
	for i in 30:
		await get_tree().process_frame
	var title := get_tree().current_scene
	check("Exit goes back to the title screen", title != null and title.scene_file_path == Net.MENU_SCENE and not Net.in_game)
	_finish()


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


func check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print(("PASS  " if ok else "FAIL  ") + name)


func _finish() -> void:
	print("\n%d/%d UI checks passed" % [_passed, _passed + _failed])
	get_tree().quit(1 if _failed > 0 else 0)
