extends CanvasLayer
## The in-game HUD layer. Owns the screens that open over the game and decides what Esc does:
##   * Overlay (hud_draw.gd): the always-on HUD: clock, lesson card, hearts, quickbar...
##   * Wheel: the item wheel (hold Q)
##   * Map (M) and Inventory (I)
##   * Dialogue: villagers' speech (Pepper)
##   * Pause menu (Esc) and the controls screen (F1)
## Esc always opens the pause menu, whatever is open; Resume puts you back in the game.
## It also keeps the short messages ("toasts") that the overlay draws.

const Z = preload("res://game/data/zones.gd")
const Wheel = preload("res://game/ui/wheel.gd")
const MapPanel = preload("res://game/ui/map_panel.gd")
const InventoryPanel = preload("res://game/ui/inventory_panel.gd")
const DialogueBox = preload("res://game/ui/dialogue_box.gd")
const PauseMenu = preload("res://game/ui/pause_menu.gd")
const ControlsPanel = preload("res://game/ui/controls_panel.gd")

@onready var overlay: Control = $Overlay
@onready var wheel: Wheel = $Wheel
@onready var map_panel: MapPanel = $Map
@onready var inventory_panel: InventoryPanel = $Inventory

var world: Variant
var dialogue: DialogueBox
var pause_menu: PauseMenu
var controls: Control
var toasts: Array = []   # [text, seconds left]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the pause menu must work while a solo game is paused
	World.toast.connect(show_toast)
	World.dialogue.connect(func(who: String, lines: Array) -> void: dialogue.say(who, lines))
	wheel.visible = false
	map_panel.visible = false
	inventory_panel.visible = false
	dialogue = DialogueBox.new()
	add_child(dialogue)
	move_child(dialogue, overlay.get_index() + 1)
	pause_menu = PauseMenu.new()
	pause_menu.closed.connect(_on_menu_closed)
	add_child(pause_menu)
	# F1: the controls screen on its own, centred.
	controls = CenterContainer.new()
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls.visible = false
	var panel := ControlsPanel.new()
	panel.esc_closes = false   # Esc opens the pause menu here too (see escape())
	panel.closed.connect(func() -> void: controls.visible = false)
	controls.add_child(panel)
	add_child(controls)


## True while a screen is open that should stop your clicks reaching the game.
func is_blocking() -> bool:
	return map_panel.visible or inventory_panel.visible or pause_menu.visible or controls.visible


func toggle_map() -> void:
	if map_panel.visible:
		map_panel.visible = false
	else:
		inventory_panel.visible = false
		wheel.visible = false
		map_panel.open(World.my_zone)


func toggle_inventory() -> void:
	if inventory_panel.visible:
		inventory_panel.visible = false
	else:
		map_panel.visible = false
		wheel.visible = false
		inventory_panel.open()


func toggle_controls() -> void:
	controls.visible = not controls.visible


func open_wheel() -> void:
	if not is_blocking():
		wheel.open()


func close_wheel(apply: bool) -> void:
	if wheel.visible:
		wheel.close(apply)


## Esc: opens the pause menu from anywhere. Whatever screen was open (bag, map, controls)
## is put away first, so Resume lands you back in the game.
func escape() -> void:
	if pause_menu.visible:
		return   # the menu handles its own Esc
	close_wheel(false)
	inventory_panel.visible = false
	map_panel.visible = false
	controls.visible = false
	pause_menu.open()


func _on_menu_closed() -> void:
	pass   # nothing to restore: Resume goes straight back to the game


func on_zone_entered(zid: String) -> void:
	show_toast("Entered %s" % str(Z.zone(zid)["name"]))


func show_toast(text: String) -> void:
	toasts.append([text, 3.5])
	if toasts.size() > 3:
		toasts.pop_front()


func _process(delta: float) -> void:
	for t: Array in toasts:
		t[1] = float(t[1]) - delta
	toasts = toasts.filter(func(t: Array) -> bool: return float(t[1]) > 0.0)
	overlay.queue_redraw()
