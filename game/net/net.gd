extends Node
## Networking (autoload "Net"): playing solo, hosting and joining, the waiting room, finding
## games on the local network, and command-line options for tests.
##
## Three ways to play:
##   * Solo: no network at all (an offline peer). You are the host of a world only you are
##     in, and the pause menu really pauses.
##   * Host: a listen server (peer 1) that owns the world (see World). Up to MAX_PLAYERS
##     people can play; anyone past that is turned away with a message. Friends can join a
##     game that has already started; they get the full world state when they arrive.
##   * Join: connect to a host by address, or pick a game found on your network.
## Solo and hosted worlds live in a save slot (see game/save/save_game.gd).
##
## Test options go after "--" on the command line, for example:
##   godot --path . -- --host --name=Host --bot --autostart=5 --report=user://host.json
##   godot --path . -- --join=127.0.0.1 --name=Bot1 --bot --report=user://bot1.json
##   godot --path . -- --solo --slot=3 --name=Ana
## (--wipe-slot deletes that slot first; tests use it. --ui-test, --menu-test and --lobby-test=host|join run the tests in game/tests/.)

signal lobby_changed
signal status_changed(text: String)
signal lan_games_changed

const PROTOCOL := 1
const DEFAULT_PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 5
const COLORS: Array[Color] = [Color("9fdcc8"), Color("ffb3c7"), Color("ffd27a"), Color("b9a6ff"), Color("8fd3ff")]
## How long a join waits for the host before giving up (ENet itself can wait far longer).
const JOIN_TIMEOUT := 8.0
const MENU_SCENE := "res://game/menu/main_menu.tscn"
const WORLD_SCENE := "res://game/world/world.tscn"

## peer id -> {"name": String, "color": Color, "ready": bool}
var players: Dictionary = {}
var in_game := false
var local_name := "Sprout"
var local_color := 0
var status := ""
var rejected_reason := ""
## Why the last game ended, if the host ended it ("The host ended the game.").
var end_reason := ""
## "ip:port" -> {"name", "ip", "port", "count", "in_game", "seen"}
var lan_games: Dictionary = {}
## Command-line options after "--" (see top of file).
var opts: Dictionary = {}
var started_at_msec := 0
## True when this player arrived after the game had already started.
var joined_in_progress := false
## True in a solo world (no network).
var solo := false
## The save slot the next hosted or solo world uses (0 = don't save).
var save_slot := 0

var _beacon: PacketPeerUDP
var _listener: PacketPeerUDP
var _beacon_t := 0.0
var _port := DEFAULT_PORT
var _autostart_t := -1.0
var _join_t := -1.0   # seconds left to connect before giving up (see JOIN_TIMEOUT)


func _ready() -> void:
	opts = parse_args(OS.get_cmdline_user_args())
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if opts.has("name"):
		local_name = str(opts["name"])
	if opts.has("color"):
		local_color = int(opts["color"]) % COLORS.size()
	if opts.has("port"):
		_port = int(opts["port"])
	if opts.has("report"):
		var probe: Node = load("res://game/tests/test_report.gd").new()
		probe.name = "Probe"
		add_child(probe)
	if opts.has("ui-test"):
		add_child(load("res://game/tests/ui_tests.gd").new())
	if opts.has("menu-test"):
		add_child(load("res://game/tests/menu_tests.gd").new())
	if opts.has("lobby-test"):
		add_child(load("res://game/tests/lobby_tests.gd").new())
	if opts.has("slot"):
		save_slot = int(opts["slot"])
		if opts.has("wipe-slot"):
			load("res://game/save/save_game.gd").delete(save_slot)   # tests start from nothing
	if opts.has("solo"):
		play_solo.call_deferred(save_slot)
	elif opts.has("host"):
		host.call_deferred(_port)
	elif opts.has("join"):
		join.call_deferred(str(opts["join"]), _port)


static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			out[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			out[s] = true
	return out


func log_line(text: String) -> void:
	print("[net %s] %s" % [local_name, text])


func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not (p is OfflineMultiplayerPeer) \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## True for whoever owns the world: the host of an online game, or a solo player.
func is_host() -> bool:
	return solo or (is_online() and multiplayer.is_server())


func me() -> int:
	return multiplayer.get_unique_id()


func player_name(id: int) -> String:
	return str(players[id]["name"]) if players.has(id) else "Player %d" % id


func player_color(id: int) -> Color:
	return players[id]["color"] if players.has(id) else Color.WHITE


# ---------------------------------------------------------------- host / join / leave

func host(port: int = DEFAULT_PORT) -> Error:
	leave(false)
	var peer := ENetMultiplayerPeer.new()
	# One extra slot so a sixth person can connect long enough to be told the game is full.
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		_set_status("Couldn't host on port %d (error %d). Is another game using it?" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	_port = port
	players.clear()
	players[1] = {"name": local_name, "color": COLORS[local_color], "ready": true}
	_start_beacon()
	_set_status("Hosting on port %d. Friends on your network will see this game." % port)
	log_line("hosting on port %d" % port)
	lobby_changed.emit()
	if opts.has("autostart"):
		_autostart_t = float(opts.get("autostart-timeout", "25"))
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave(false)
	rejected_reason = ""
	end_reason = ""
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		_set_status("Couldn't start connecting (error %d)." % err)
		return err
	multiplayer.multiplayer_peer = peer
	_join_t = JOIN_TIMEOUT
	_set_status("Connecting to %s:%d..." % [address, port])
	log_line("joining %s:%d" % [address, port])
	return OK


## Starts a world just for you, with no network. Uses (and saves to) `slot`.
func play_solo(slot: int) -> void:
	leave(false)
	solo = true
	save_slot = slot
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	players[1] = {"name": _unique_name(local_name), "color": COLORS[local_color], "ready": true}
	log_line("playing solo in slot %d" % slot)
	start_game()


## Leaves the current game or room. The host (or solo player) saves the world first. When
## back_to_menu is true and a game was running, returns to the title screen.
func leave(back_to_menu: bool = true) -> void:
	if in_game and is_host():
		World.save_now()
		# Ending a hosted game ends it for everyone: tell them why before closing.
		if is_online():
			for id: int in players:
				if id != 1:
					_rpc_session_over.rpc_id(id, "%s ended the game." % player_name(1))
			var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if enet != null and enet.host != null:
				enet.host.flush()
	_stop_beacon()
	var p := multiplayer.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var was_in_game := in_game
	players.clear()
	in_game = false
	solo = false
	if get_tree() != null:
		get_tree().paused = false
	_autostart_t = -1.0
	_join_t = -1.0
	World.reset()
	lobby_changed.emit()
	if back_to_menu and was_in_game and is_inside_tree():
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func set_ready(value: bool) -> void:
	if is_host():
		_rpc_set_ready(value)
	elif is_online():
		_rpc_set_ready.rpc_id(1, value)


func start_game() -> void:
	if not is_host() or in_game:
		return
	World.host_init(randi())
	World.host_load(save_slot, local_name)
	in_game = true
	started_at_msec = Time.get_ticks_msec()
	for id: int in players.keys():
		World.host_add_player(id)
	_broadcast_lobby()
	for id: int in players.keys():
		if id != 1:
			_rpc_begin.rpc_id(id, World.full_state(id))
	World.apply_full_state(World.full_state(1))
	log_line("game started with %d players" % players.size())
	_go_to_world()


# ---------------------------------------------------------------- multiplayer callbacks

func _on_connected() -> void:
	_join_t = -1.0
	_set_status("Connected. Saying hello...")
	_rpc_register.rpc_id(1, local_name, local_color, PROTOCOL)


func _on_connection_failed() -> void:
	_set_status("Couldn't reach that game. Check the address and that the host is running.")
	log_line("connection failed")
	leave(false)


func _on_server_disconnected() -> void:
	var reason := "The host closed the game."
	if rejected_reason != "":
		reason = rejected_reason
	elif end_reason != "":
		reason = end_reason
	log_line("disconnected: " + reason)
	leave(true)
	_set_status(reason)


func _on_peer_connected(id: int) -> void:
	if is_host():
		log_line("peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	if players.has(id):
		log_line("%s left (%d/%d)" % [player_name(id), players.size() - 1, MAX_PLAYERS])
		var who := player_name(id)
		players.erase(id)
		if in_game:
			World.host_remove_player(id)
			World.broadcast_toast("%s went home." % who)
		_broadcast_lobby()


# ---------------------------------------------------------------- RPCs

@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(pname: String, color_index: int, protocol: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_reject(id, "That game is running a different version.")
		return
	if players.size() >= MAX_PLAYERS:
		_reject(id, "The game is full (%d/%d players)." % [players.size(), MAX_PLAYERS])
		return
	players[id] = {"name": _unique_name(pname), "color": _free_color(color_index), "ready": false}
	log_line("%s joined (%d/%d)" % [player_name(id), players.size(), MAX_PLAYERS])
	_broadcast_lobby()
	if in_game:
		World.host_add_player(id)
		_rpc_begin.rpc_id(id, World.full_state(id))
		World.broadcast_toast("%s arrived in Middlemost." % player_name(id))


@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	rejected_reason = reason
	log_line("rejected: " + reason)
	leave.call_deferred(false)
	_set_status.call_deferred("Couldn't join: " + reason)


## The host ended the game: everyone goes back to the title screen.
@rpc("authority", "call_remote", "reliable")
func _rpc_session_over(reason: String) -> void:
	end_reason = reason
	log_line("session over: " + reason)
	leave.call_deferred(true)
	_set_status.call_deferred(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(p: Dictionary, started: bool) -> void:
	players = p
	in_game = in_game or started
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(value: bool) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if players.has(id):
		players[id]["ready"] = value
		_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_begin(state: Dictionary) -> void:
	joined_in_progress = absf(float(state["clock"]) - 360.0) > 1.0
	World.apply_full_state(state)
	in_game = true
	started_at_msec = Time.get_ticks_msec()
	log_line("entered the world (%d players)" % players.size())
	_go_to_world()


# ---------------------------------------------------------------- helpers

func _reject(id: int, reason: String) -> void:
	log_line("turning away peer %d: %s" % [id, reason])
	_rpc_rejected.rpc_id(id, reason)
	# Give the message time to arrive even on a lossy connection; the player leaves by
	# themselves when it does. This is only a fallback.
	await get_tree().create_timer(3.0).timeout
	var p := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if p != null and id in multiplayer.get_peers():
		p.disconnect_peer(id)


func _broadcast_lobby() -> void:
	for id: int in players:
		if id != 1:
			_rpc_lobby.rpc_id(id, players, in_game)
	lobby_changed.emit()


func _go_to_world() -> void:
	get_tree().change_scene_to_file.call_deferred(WORLD_SCENE)


func _unique_name(wanted: String) -> String:
	var base := wanted.strip_edges().left(16)
	if base == "":
		base = "Sprout"
	var taken: Array[String] = []
	for id: int in players:
		taken.append(str(players[id]["name"]))
	var n := base
	var k := 2
	while n in taken:
		n = "%s %d" % [base, k]
		k += 1
	return n


func _free_color(wanted: int) -> Color:
	var used: Array[Color] = []
	for id: int in players:
		used.append(players[id]["color"])
	for i in COLORS.size():
		var c: Color = COLORS[(wanted + i) % COLORS.size()]
		if not c in used:
			return c
	return COLORS[wanted % COLORS.size()]


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


# ---------------------------------------------------------------- LAN discovery

func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_beacon_t = 0.0


func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
	_beacon = null


## The lobby calls this so the player sees games hosted on the same network.
func start_listening() -> void:
	if _listener != null:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null  # another copy of the game on this PC is already listening


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
	_listener = null
	lan_games.clear()


func _process(delta: float) -> void:
	if _join_t >= 0.0:
		_join_t -= delta
		if _join_t < 0.0:
			# Nothing answered: a wrong address, a closed port, or the host isn't running.
			_on_connection_failed()
	if _beacon != null and is_host():
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var msg := "NATTO|%d|%s|%d|%d|%d" % [PROTOCOL, player_name(1), _port, players.size(), int(in_game)]
			_beacon.put_packet(msg.to_utf8_buffer())
	if _listener != null:
		var changed := false
		while _listener.get_available_packet_count() > 0:
			var data := _listener.get_packet().get_string_from_utf8()
			var ip := _listener.get_packet_ip()
			var parts := data.split("|")
			if parts.size() == 6 and parts[0] == "NATTO" and int(parts[1]) == PROTOCOL:
				var key := "%s:%s" % [ip, parts[3]]
				lan_games[key] = {"name": parts[2], "ip": ip, "port": int(parts[3]), "count": int(parts[4]),
					"in_game": parts[5] == "1", "seen": Time.get_ticks_msec()}
				changed = true
		for key: String in lan_games.keys():
			if Time.get_ticks_msec() - int(lan_games[key]["seen"]) > 3500:
				lan_games.erase(key)
				changed = true
		if changed:
			lan_games_changed.emit()
	if _autostart_t >= 0.0 and is_host() and not in_game:
		_autostart_t -= delta
		if players.size() >= int(opts.get("autostart", "5")) or _autostart_t <= 0.0:
			_autostart_t = -1.0
			start_game()
