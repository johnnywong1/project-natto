extends Node
## Regression checks for joining, the room, starting, leaving and the host ending a game,
## run as two real processes talking over the network (tools/mp_test.py --lobby-test):
##   godot --headless --path . -- --host --port=7812 --lobby-test=host
##   godot --headless --path . -- --join=127.0.0.1 --port=7812 --lobby-test=join
## The story: the joiner arrives in the room and ticks Ready; the host sees it and starts;
## both are in the world; the joiner leaves (the host's game goes on); the joiner comes back
## mid-game; the host exits, which ends the game for the joiner too, with a message.
## Each side prints PASS/FAIL lines and quits with code 1 if anything failed.

var _passed := 0
var _failed := 0
var _role := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_role = str(Net.opts.get("lobby-test", ""))
	_run.call_deferred()


func _run() -> void:
	await _wait(0.5)
	if _role == "host":
		await _host_story()
	else:
		await _join_story()
	_finish()


func _host_story() -> void:
	check("host: the room opened", Net.is_host() and Net.is_online() and Net.players.size() == 1)
	check("host: a player joined the room", await _until(func() -> bool: return Net.players.size() == 2, 20.0), str(Net.players))
	var joiner := _other_id()
	check("host: the joiner isn't ready yet", joiner > 0 and not bool(Net.players[joiner]["ready"]))
	check("host: the joiner ticked Ready", await _until(func() -> bool: return joiner > 0 and bool(Net.players.get(joiner, {}).get("ready", false)), 10.0))
	Net.start_game()
	check("host: the game started with 2 players", await _until(func() -> bool: return Net.in_game and World.avatars.size() == 2, 10.0))
	check("host: the joiner's avatar stands near the spawn", World.avatars.has(joiner) and (World.avatars[joiner]["pos"] as Vector2).distance_to(World.Z.zone("middlemost")["spawn"]) < 120.0)
	# The joiner leaves: the host's game carries on without them.
	check("host: the joiner left the game", await _until(func() -> bool: return Net.players.size() == 1 and not World.avatars.has(joiner), 15.0))
	check("host: the game carries on after a player leaves", Net.in_game and get_tree().current_scene.scene_file_path == Net.WORLD_SCENE)
	# The joiner comes back mid-game.
	check("host: the joiner came back into the running game", await _until(func() -> bool: return Net.players.size() == 2 and World.avatars.size() == 2, 20.0))
	await _wait(1.0)
	# The host exits: everyone is sent home.
	Net.leave()
	await _wait(0.5)
	check("host: exit took the host to the title screen", await _until(func() -> bool: return not Net.in_game and get_tree().current_scene.scene_file_path == Net.MENU_SCENE, 5.0))
	await _wait(1.0)   # give the goodbye time to reach the joiner before quitting


func _join_story() -> void:
	check("joiner: connected and in the room", await _until(func() -> bool: return Net.is_online() and Net.players.has(Net.me()), 20.0), Net.status)
	check("joiner: the host is listed first", Net.players.has(1) and str(Net.players[1]["name"]) != "")
	await _wait(0.5)
	Net.set_ready(true)
	check("joiner: Ready reached the host and came back", await _until(func() -> bool: return bool(Net.players[Net.me()]["ready"]), 5.0))
	check("joiner: the host started the game", await _until(func() -> bool: return Net.in_game, 15.0))
	check("joiner: in the world scene", await _until(func() -> bool: return get_tree().current_scene.scene_file_path == Net.WORLD_SCENE, 5.0))
	check("joiner: this was a fresh start, not a join in progress", not Net.joined_in_progress)
	await _wait(1.0)
	# Leave on purpose: back to the title screen, the session goes on without us.
	Net.leave()
	check("joiner: leaving returns to the title screen", await _until(func() -> bool: return not Net.in_game and not Net.is_online() and get_tree().current_scene.scene_file_path == Net.MENU_SCENE, 5.0))
	await _wait(1.5)
	# Rejoin the running game.
	Net.join("127.0.0.1", int(Net.opts.get("port", str(Net.DEFAULT_PORT))))
	check("joiner: rejoined the running game", await _until(func() -> bool: return Net.in_game, 15.0))
	check("joiner: flagged as joined in progress", Net.joined_in_progress)
	# Now the host exits: we should be sent home with a message.
	check("joiner: the host's exit ended the game for me", await _until(func() -> bool: return not Net.in_game and not Net.is_online(), 15.0))
	check("joiner: back on the title screen", await _until(func() -> bool: return get_tree().current_scene.scene_file_path == Net.MENU_SCENE, 5.0))
	check("joiner: told why", "closed the game" in Net.status or "ended the game" in Net.status, Net.status)


func _other_id() -> int:
	for id: int in Net.players:
		if id != 1:
			return id
	return 0


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await _wait(0.05)
		t += 0.05
	return cond.call()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print(("PASS  " if ok else "FAIL  ") + name + (("   [" + detail + "]") if detail != "" else ""))


func _finish() -> void:
	print("\n%d/%d lobby checks passed (%s)" % [_passed, _passed + _failed, _role])
	get_tree().quit(1 if _failed > 0 else 0)
