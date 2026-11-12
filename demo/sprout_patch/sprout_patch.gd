extends Node2D
## Sprout Patch demo. Plant, water and harvest popberries, then throw them at Mildew Wilts.
## One screen that shows the Project Natto hook: your farm is your loadout.
##
## Controls: WASD/arrows move, E use (plant, water, harvest, refill at the well, talk),
## J sickle, K throw a popberry, Space hop.

const SoilGrid = preload("res://demo/sprout_patch/soil_grid.gd")
const Player = preload("res://demo/sprout_patch/player.gd")
const Pepper = preload("res://demo/sprout_patch/pepper.gd")
const Wilt = preload("res://demo/sprout_patch/wilt.gd")
const Shot = preload("res://demo/sprout_patch/popberry_shot.gd")

const WELL_POS := Vector2(170, 360)
const CAN_SIZE := 5
const TALK_RANGE := 80.0
const WELL_RANGE := 100.0
const PLOT_REACH := 58.0
const SPLAT_RADIUS := 56.0
const SWING_RANGE := 70.0
const MAX_WILTS := 3
const GOAL_HARVEST := 3
const GOAL_SPLATS := 3

enum Quest { NOT_STARTED, ACTIVE, READY, DONE }

@onready var grid: SoilGrid = $SoilGrid
@onready var world: Node2D = $World
@onready var player: Player = $World/Player
@onready var pepper: Pepper = $World/Pepper
@onready var stats_label: Label = $HUD/Stats
@onready var quest_label: Label = $HUD/Quest
@onready var toast_label: Label = $HUD/Toast

var water := CAN_SIZE
var popberries := 0
var harvested := 0
var splats := 0
var popped := 0
var quest := Quest.NOT_STARTED
var _spawn_t := 10.0
var _toast_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	player.blockers.append(Vector3(WELL_POS.x, WELL_POS.y, 56.0))
	player.blockers.append(Vector3(pepper.position.x, pepper.position.y, 26.0))
	player.swung.connect(_on_swung)
	pepper.bubble = "!"
	_toast("Walk over to Pepper (top right) and press E to talk.", 5.0)


func _process(delta: float) -> void:
	grid.highlight = grid.plot_at(player.global_position + player.facing * 26.0, PLOT_REACH)
	if Input.is_action_just_pressed("use_tool"):
		_use()
	if Input.is_action_just_pressed("throw"):
		_throw()
	_tick_spawner(delta)
	_tick_quest()
	_toast_t = maxf(_toast_t - delta, 0.0)
	toast_label.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	stats_label.text = "Water %d/%d     Popberries %d     Wilts popped %d" % [water, CAN_SIZE, popberries, popped]
	quest_label.text = _quest_text()


func _use() -> void:
	var p := player.global_position
	if p.distance_to(pepper.global_position) < TALK_RANGE:
		_talk()
		return
	if p.distance_to(WELL_POS) < WELL_RANGE:
		water = CAN_SIZE
		_toast("Watering can refilled.")
		return
	var i := grid.highlight
	if i < 0:
		_toast("Face a soil plot to plant, water or harvest.")
		return
	var stage: int = grid.stages[i]
	if stage == SoilGrid.Stage.EMPTY:
		grid.plant(i)
		_toast("Planted a popberry seed. Now water it.")
	elif stage == SoilGrid.Stage.RIPE:
		grid.harvest(i)
		popberries += 2
		harvested += 1
		_toast("+2 popberries! Press K to throw one.")
	elif grid.is_wet(i):
		_toast("Already watered. It's growing!")
	elif water <= 0:
		_toast("The can is empty. Refill it at the well.")
	else:
		grid.water(i)
		water -= 1


func _talk() -> void:
	match quest:
		Quest.NOT_STARTED:
			quest = Quest.ACTIVE
			pepper.bubble = ""
			_toast("Pepper: Lord Mildew's Wilts keep nibbling my patch! Grow popberries, then splat 3 Wilts with them.", 6.0)
		Quest.ACTIVE:
			_toast("Pepper: Harvest %d popberry bushes and splat %d Wilts. Popberries pop!" % [GOAL_HARVEST, GOAL_SPLATS], 4.0)
		Quest.READY:
			quest = Quest.DONE
			pepper.bubble = ""
			pepper.cheer_t = 2.0
			_toast("Pepper: You did it! See? Your farm is your loadout. Quest complete!", 6.0)
		Quest.DONE:
			pepper.cheer_t = 1.0
			_toast("Pepper: Keep that patch growing, sprout!", 3.0)


func _tick_quest() -> void:
	if quest == Quest.ACTIVE and harvested >= GOAL_HARVEST and splats >= GOAL_SPLATS:
		quest = Quest.READY
		pepper.bubble = "?"
		_toast("Quest goals met! Go tell Pepper.", 4.0)


func _quest_text() -> String:
	match quest:
		Quest.NOT_STARTED:
			return "Quest: talk to Pepper"
		Quest.ACTIVE:
			return "Pepper's Patch Problem:  harvest %d/%d   |   splat Wilts with popberries %d/%d" % [
				mini(harvested, GOAL_HARVEST), GOAL_HARVEST, mini(splats, GOAL_SPLATS), GOAL_SPLATS]
		Quest.READY:
			return "Pepper's Patch Problem:  done! Go tell Pepper."
	return "Pepper's Patch Problem:  complete. Keep farming!"


func _throw() -> void:
	if popberries <= 0:
		_toast("No popberries yet. Grow and harvest some first!")
		return
	popberries -= 1
	var from := player.global_position
	var target := from + player.facing * 230.0
	var best: float = 400.0
	for w in _wilts():
		var d: float = from.distance_to(w.global_position)
		if d < best:
			best = d
			target = w.global_position
	var shot: Shot = Shot.new()
	world.add_child(shot)
	shot.setup(from, target)
	shot.splatted.connect(_on_splat)


func _on_splat(at: Vector2) -> void:
	for w in _wilts():
		var d: float = at.distance_to(w.global_position)
		if d < SPLAT_RADIUS:
			w.hit(2, at, true)


func _on_swung(origin: Vector2, facing: Vector2) -> void:
	for w in _wilts():
		var to: Vector2 = w.global_position - origin
		if to.length() < 24.0 or (to.length() < SWING_RANGE and facing.dot(to.normalized()) > 0.1):
			w.hit(1, origin, false)


func _on_wilt_defeated(_wilt: Node2D, by_popberry: bool) -> void:
	popped += 1
	if by_popberry:
		splats += 1
		_toast("Splat! Popberry power.", 1.5)
	else:
		_toast("Swatted!", 1.2)


func _tick_spawner(delta: float) -> void:
	if quest == Quest.NOT_STARTED and grid.planted_plots().is_empty():
		return
	_spawn_t -= delta
	if _spawn_t > 0.0:
		return
	_spawn_t = _rng.randf_range(4.5, 7.5)
	if _wilts().size() < MAX_WILTS:
		_spawn_wilt()


func _spawn_wilt() -> void:
	var w: Wilt = Wilt.new()
	var side := _rng.randi_range(0, 2)
	if side == 0:
		w.position = Vector2(-20.0, _rng.randf_range(170.0, 520.0))
	elif side == 1:
		w.position = Vector2(1172.0, _rng.randf_range(170.0, 520.0))
	else:
		w.position = Vector2(_rng.randf_range(320.0, 860.0), 110.0)
	w.grid = grid
	w.player = player
	w.defeated.connect(_on_wilt_defeated)
	world.add_child(w)


## Live Wilts (untyped so callers can use their methods directly).
func _wilts() -> Array:
	var out: Array = []
	for c in world.get_children():
		var w := c as Wilt
		if w != null and w.is_alive():
			out.append(w)
	return out


## Short message near the bottom of the screen. Quick toasts don't cut off dialogue.
func _toast(msg: String, duration: float = 2.2) -> void:
	if _toast_t > 2.0 and duration < 2.0:
		return
	toast_label.text = msg
	_toast_t = duration
