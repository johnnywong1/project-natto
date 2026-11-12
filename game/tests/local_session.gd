extends Node
## Starts a local multiplayer session with no typing, so several windows can be launched
## on one PC: run local_session_host.tscn once, then local_session_client.tscn up to four
## times (in the editor, or through the Godot MCP). Each window gets a test bot so you can
## watch everyone play across the zones. Not used by the real game.

@export var players_to_start := 5

const NAMES: Array[String] = ["Ana", "Ben", "Cal", "Dee", "Eli", "Fay"]


func _ready() -> void:
	var as_host := name == "LocalSessionHost"   # the host scene's root node is called this
	Net.opts["bot"] = true
	Net.opts["role"] = "auto"
	Net.opts["time-scale"] = "12"
	Net.opts["weather-period"] = "12"
	World.time_scale = 12.0
	World._weather_period = Vector2(12.0, 18.0)
	if as_host:
		Net.local_name = "Host"
		Net.local_color = 0
		Net.opts["autostart"] = str(players_to_start)
		Net.opts["autostart-timeout"] = "90"
		Net.host(Net.DEFAULT_PORT)
	else:
		var pid := OS.get_process_id()
		Net.local_name = NAMES[pid % NAMES.size()]
		Net.local_color = 1 + pid % 4
		await get_tree().create_timer(0.5 + float(pid % 7) * 0.2).timeout
		Net.join("127.0.0.1", Net.DEFAULT_PORT)
