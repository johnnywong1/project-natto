extends PanelContainer
## The controls screen: every action with its keyboard/mouse and gamepad buttons. Opened
## from the title screen, the pause menu (Esc) or with F1 in game. Emits `closed` when the
## player presses Back (or Esc, unless esc_closes is off).

signal closed

## The F1 overlay in game turns this off, so Esc opens the pause menu there like it does
## over every other screen (the overlay comes back on Resume).
var esc_closes := true

const UiTheme = preload("res://game/ui/ui_theme.gd")

const ROWS := [
	["Move", "WASD or arrow keys", "Left stick"],
	["Aim (face, swing, throw)", "Mouse", "Right stick"],
	["Use what you're holding", "Left click or J", "X / Square"],
	["Offhand: torch jab, lantern on/off, block (hold) with a shield", "Right click or K", "B / Circle"],
	["Dash (no invincibility: dash out of danger)", "Space", "A / Cross"],
	["Sprint", "Hold Shift", "Left stick click"],
	["Talk, harvest, pick up, relight torch, ride or call a lift, open chests and doors, revive", "E or F", "Y / Triangle"],
	["Item wheel: hold, point, let go", "Hold Q or Tab (also 1-8, mouse wheel)", "Hold LB"],
	["Bag and gear", "I", "Back / Select"],
	["Map (friends shown live)", "M", "D-pad up"],
	["Drop a pin where you point", "P or middle click", "RB"],
	["Menu: pause, save, controls, leave", "Esc", "Start"],
	["This screen", "F1", ""],
	["Fullscreen on/off", "F11", ""],
	["Hitbox view (for testing fights)", "F3", ""],
]


func _ready() -> void:
	theme = UiTheme.make()
	custom_minimum_size = Vector2(860, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	v.add_child(UiTheme.heading("Controls", 28))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for head in ["", "Keyboard and mouse", "Gamepad"]:
		var h := UiTheme.heading(head, 16)
		h.modulate = Color(1, 1, 1, 0.7)
		grid.add_child(h)
	for row: Array in ROWS:
		var what := Label.new()
		what.text = row[0]
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.custom_minimum_size = Vector2(380, 0)
		what.add_theme_font_size_override("font_size", 15)
		grid.add_child(what)
		for k in [1, 2]:
			var l := Label.new()
			l.text = row[k]
			l.custom_minimum_size = Vector2(190 if k == 1 else 140, 0)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 15)
			grid.add_child(l)
	var back := UiTheme.button("Back", func() -> void: closed.emit(), 160)
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(back)
	back.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	# is_visible_in_tree, not visible: this panel sits inside other screens (the F1 overlay,
	# the Esc menu, the title screen), and when only its parent is hidden it must not
	# swallow Esc.
	if esc_closes and is_visible_in_tree() and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu")):
		get_viewport().set_input_as_handled()
		closed.emit()
