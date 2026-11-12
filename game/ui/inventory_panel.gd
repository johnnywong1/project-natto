extends Control
## The bag and gear screen (I). Three sections:
##   * Gear (left): what you're wearing: helmet, chest, shoes, offhand and three trinkets.
##     Click a worn piece to take it off.
##   * Item wheel (top right): what you can hold in your main hand. It starts with one
##     segment and grows as you add things, up to 8. Right-click an item in the bag to add
##     it; right-click a wheel segment to put it back. Click a segment to hold it, or click
##     two to swap them.
##   * Bag (below): everything else. Right-click gear to wear it. Click two slots to swap.
## Hover anything to read what it does. Every change goes through the host, which owns
## each player's bag, wheel and gear.

const P = preload("res://game/ui/palette.gd")
const Items = preload("res://game/data/items.gd")
const Icons = preload("res://game/ui/icons.gd")
const CELL := 60.0
const GAP := 6.0
const COLS := 8

var _picked := -1          # bag slot clicked first (to swap)
var _picked_wheel := -1    # wheel segment clicked first (to swap)
var _hover := -1
var _hover_wheel := -1
var _hover_equip := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	World.inventory_changed.connect(queue_redraw)
	World.selection_changed.connect(queue_redraw)


func open() -> void:
	_picked = -1
	_picked_wheel = -1
	visible = true
	queue_redraw()


# ---------------------------------------------------------------- layout

func _panel() -> Rect2:
	var w := 200.0 + COLS * (CELL + GAP) + 40.0
	var h := 620.0
	return Rect2(((size - Vector2(w, h)) / 2.0).round(), Vector2(w, h))


func _right_x() -> float:
	return _panel().position.x + 210.0


func wheel_rect(i: int) -> Rect2:
	return Rect2(Vector2(_right_x() + i * (CELL + GAP), _panel().position.y + 92.0), Vector2(CELL, CELL))


func slot_rect(i: int) -> Rect2:
	@warning_ignore("integer_division")
	var row := i / COLS
	var col := i % COLS
	var top := _panel().position.y + 218.0
	return Rect2(Vector2(_right_x() + col * (CELL + GAP), top + row * (CELL + GAP)), Vector2(CELL, CELL))


func equip_rect(k: int) -> Rect2:
	var p := _panel()
	return Rect2(p.position + Vector2(24, 76 + k * 64), Vector2(CELL - 4, CELL - 4))


func _slot_at(pos: Vector2) -> int:
	for i in Items.SLOTS:
		if slot_rect(i).has_point(pos):
			return i
	return -1


func _wheel_at(pos: Vector2) -> int:
	for i in World.wheel.size():
		if wheel_rect(i).has_point(pos):
			return i
	return -1


func _equip_at(pos: Vector2) -> String:
	for k in Items.EQUIP_SLOTS.size():
		if equip_rect(k).has_point(pos):
			return Items.EQUIP_SLOTS[k]
	return ""


# ---------------------------------------------------------------- clicks

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _slot_at(event.position)
		_hover_wheel = _wheel_at(event.position)
		_hover_equip = _equip_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
		var left: bool = event.button_index == MOUSE_BUTTON_LEFT
		var s := _slot_at(event.position)
		var w := _wheel_at(event.position)
		var e := _equip_at(event.position)
		if e != "" and (left or right):
			if str(World.equip.get(e, "")) != "":
				World.to_host(&"c_unequip", [e])
			_picked = -1
		elif w >= 0 and right:
			World.to_host(&"c_wheel_remove", [w])
			_picked_wheel = -1
		elif w >= 0 and left:
			if _picked_wheel >= 0 and _picked_wheel != w:
				World.to_host(&"c_wheel_swap", [_picked_wheel, w])
				_picked_wheel = -1
			else:
				World.select_slot(w)
				_picked_wheel = w
			_picked = -1
		elif s >= 0 and right:
			var id := Items.item_at(World.inventory, s)
			if Items.is_equipment(id):
				World.to_host(&"c_equip", [s])
			elif Items.fits_wheel(id):
				World.to_host(&"c_wheel_add", [s])
			_picked = -1
		elif s >= 0 and left:
			if _picked < 0:
				_picked = s
			else:
				if s != _picked:
					World.to_host(&"c_inv_swap", [_picked, s])
				_picked = -1
			_picked_wheel = -1
		else:
			_picked = -1
			_picked_wheel = -1
		queue_redraw()
		accept_event()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.23, 0.16, 0.35))
	var p := _panel()
	var font := ThemeDB.fallback_font
	P.shape(self, P.rounded_rect_points(p, 22.0), P.CREAM, 4.0)
	var rx := _right_x()
	_label(p.position + Vector2(24, 48), "Gear", 24)
	_label(Vector2(rx, p.position.y + 48), "Item wheel  %d/%d" % [World.wheel.size(), Items.WHEEL_MAX], 24)
	_label(Vector2(rx, p.position.y + 78), "What you can hold. Right-click a bag item to add it here; right-click here to put it back.", 13, 0.25)
	_label(Vector2(rx, p.position.y + 196), "Bag", 24)
	_label(Vector2(rx + 56, p.position.y + 196), "Right-click gear to wear it.  Click two slots to swap.", 13, 0.25)
	_draw_gear(font)
	_draw_wheel()
	_draw_bag()
	_draw_footer(p, rx, font)


func _label(at: Vector2, text: String, size_px: int, lighten: float = 0.0) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, P.OUTLINE.lightened(lighten))


func _draw_gear(font: Font) -> void:
	for k in Items.EQUIP_SLOTS.size():
		var slot: String = Items.EQUIP_SLOTS[k]
		var r := equip_rect(k)
		P.shape(self, P.rounded_rect_points(r, 12.0), Color("ffe08a") if slot == _hover_equip else Color("fff0d6"), 3.0)
		var id := str(World.equip.get(slot, ""))
		if id != "":
			Icons.draw(self, id, r.get_center(), 1.2)
		draw_string(font, r.position + Vector2(r.size.x + 10, 22), str(Items.SLOT_NAMES[slot]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.OUTLINE)
		if id != "":
			draw_string(font, r.position + Vector2(r.size.x + 10, 40), Items.display_name(id), HORIZONTAL_ALIGNMENT_LEFT, 110, 12, P.OUTLINE.lightened(0.25))


func _draw_wheel() -> void:
	for i in Items.WHEEL_MAX:
		var r := wheel_rect(i)
		if i < World.wheel.size():
			var fill := Color("d8f5ea")
			if i == _picked_wheel:
				fill = Color("ffe08a")
			P.shape(self, P.rounded_rect_points(r, 12.0), fill, 4.0 if i == _hover_wheel else 3.0)
			if i == World.selected:
				P.outline(self, P.rounded_rect_points(r.grow(4.0), 15.0), Color("5fb35f"), 3.0)
			var id := Items.item_at(World.wheel, i)
			Icons.draw(self, id, r.get_center(), 1.15)
			if Items.stackable(id) or id == "can":
				Icons.count_badge(self, r.end + Vector2(2, 2), Items.count_at(World.wheel, i), 12)
			P.text(self, r.position + Vector2(9, 15), str(i + 1), 11, P.OUTLINE.lightened(0.3))
		elif i == World.wheel.size():
			# The next segment: shows the wheel can grow.
			_dashed_box(r, Color(P.OUTLINE, 0.45))
			P.text(self, r.get_center() + Vector2(0, 9), "+", 26, Color(P.OUTLINE, 0.45))


func _draw_bag() -> void:
	for i in Items.SLOTS:
		var r := slot_rect(i)
		var fill := Color.WHITE
		if i == _picked:
			r = Rect2(r.position - Vector2(0, 5), r.size)
			fill = Color("ffe08a")
		P.shape(self, P.rounded_rect_points(r, 12.0), fill, 4.0 if i == _hover else 3.0)
		var id := Items.item_at(World.inventory, i)
		if id != "":
			Icons.draw(self, id, r.get_center(), 1.15)
			if Items.stackable(id) or id == "can":
				Icons.count_badge(self, r.end + Vector2(2, 2), Items.count_at(World.inventory, i), 12)


func _draw_footer(p: Rect2, rx: float, font: Font) -> void:
	var sy := slot_rect(Items.SLOTS - 1).end.y + 30.0
	var worn := Items.equipped(World.equip)
	var full := Items.full_sets(World.equip)
	for set_id: String in Items.SETS:
		var sd: Dictionary = Items.SETS[set_id]
		var have := 0
		for piece: String in sd["pieces"]:
			if piece in worn:
				have += 1
		var col := Color("2e8b57") if set_id in full else P.OUTLINE.lightened(0.3)
		draw_string(font, Vector2(rx, sy), "%s %d/%d: %s" % [str(sd["name"]), have, (sd["pieces"] as Array).size(), str(sd["bonus"])],
			HORIZONTAL_ALIGNMENT_LEFT, p.end.x - rx - 20.0, 14, col)
		sy += 22.0
	var tip_id := ""
	if _hover >= 0:
		tip_id = Items.item_at(World.inventory, _hover)
	elif _hover_wheel >= 0:
		tip_id = Items.item_at(World.wheel, _hover_wheel)
	elif _hover_equip != "":
		tip_id = str(World.equip.get(_hover_equip, ""))
	var tip := "Press I to close. Esc opens the menu."
	if tip_id != "":
		var d: Dictionary = Items.ITEMS[tip_id]
		var desc := Items.shield_text(tip_id) if not Items.shield(tip_id).is_empty() else str(d.get("desc", _kind_hint(tip_id)))
		tip = "%s: %s" % [str(d["name"]), desc]
		if d.has("set"):
			tip += "  (Part of the %s.)" % str(Items.SETS[d["set"]]["name"])
	draw_multiline_string(font, Vector2(p.position.x + 24, p.end.y - 46.0), tip, HORIZONTAL_ALIGNMENT_LEFT,
		p.size.x - 48.0, 13, 3, P.OUTLINE)


## A line of help for items without their own description.
func _kind_hint(id: String) -> String:
	match str(Items.ITEMS[id]["kind"]):
		"sickle":
			return "Swing at Wilts and harvest ripe crops. Put it in your wheel to hold it."
		"can":
			return "Water planted seeds. Refill at the well or a puddle (E)."
		"seed":
			return "Plant in the farm plots in Middlemost. Put them in your wheel first."
		"throw":
			return "Throw at enemies (click where to throw). Put them in your wheel first."
		"material":
			return "For crafting, coming later."
		"key":
			return "Opens a locked door."
	return ""


func _dashed_box(r: Rect2, col: Color) -> void:
	var pts := P.rounded_rect_points(r, 12.0)
	for k in pts.size():
		if k % 2 == 0:
			draw_line(pts[k], pts[(k + 1) % pts.size()], col, 3.0, true)
