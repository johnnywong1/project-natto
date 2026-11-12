extends Control
## The item wheel (radial picker): hold Q (or Tab, or LB on a gamepad), point at an item
## with the mouse or right stick, and let go to hold it. Number keys 1-8 and the mouse wheel
## also pick.
##
## The wheel only holds what you've put in it from the bag (I): it starts with just the
## sickle and gets one segment per item you add, up to 8. Segment 1 is at the top and the
## rest go clockwise.

const P = preload("res://game/ui/palette.gd")
const Items = preload("res://game/data/items.gd")
const Icons = preload("res://game/ui/icons.gd")
const BUBBLE := 44.0

var hover := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open() -> void:
	hover = World.selected
	visible = true
	queue_redraw()


func close(apply: bool) -> void:
	if apply and hover >= 0 and hover < World.wheel.size():
		World.select_slot(hover)
	visible = false


## The ring gets bigger as the wheel fills up, so bubbles never overlap.
func radius() -> float:
	return clampf(40.0 + 22.0 * World.wheel.size(), 90.0, 160.0)


## Which segment a direction points at (segment 0 at the top, then clockwise).
static func slot_for_direction(v: Vector2, n: int) -> int:
	if n <= 1:
		return 0
	var t := fposmod(v.angle() + PI / 2.0 + PI / n, TAU)
	return int(t / (TAU / n)) % n


func slot_center(i: int) -> Vector2:
	var n := maxi(World.wheel.size(), 1)
	if n == 1:
		return size / 2.0 + Vector2(0, -radius())
	return size / 2.0 + Vector2.from_angle(-PI / 2.0 + TAU * i / n) * radius()


func _process(_delta: float) -> void:
	if not visible:
		return
	var n := World.wheel.size()
	var m := get_local_mouse_position() - size / 2.0
	if m.length() > 36.0:
		hover = slot_for_direction(m, n)
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > 0.5:
		hover = slot_for_direction(stick, n)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var n := World.wheel.size()
	var ring := radius() + BUBBLE + 22.0
	draw_circle(c, ring, Color(0.36, 0.23, 0.16, 0.35))
	draw_arc(c, ring, 0.0, TAU, 64, P.OUTLINE, 4.0, true)
	for i in n:
		var sc := slot_center(i)
		var is_hover := i == hover
		var r := BUBBLE * (1.15 if is_hover else 1.0)
		P.blob(self, sc, Vector2(r, r), Color("ffe08a") if is_hover else P.CREAM, 4.0 if is_hover else 3.0)
		var id := Items.item_at(World.wheel, i)
		Icons.draw(self, id, sc, 1.5 if is_hover else 1.3)
		if Items.stackable(id) or id == "can":
			Icons.count_badge(self, sc + Vector2(r, r) * 0.75, Items.count_at(World.wheel, i), 13)
		P.text(self, sc + Vector2(-r + 10.0, -r + 16.0), str(i + 1), 13)
		if i == World.selected:
			draw_arc(sc, r + 6.0, 0.0, TAU, 32, Color.WHITE, 3.0, true)
	P.blob(self, c, Vector2(64, 64), P.CREAM, 4.0)
	var label_text := Items.display_name(Items.item_at(World.wheel, hover)) if hover >= 0 else ""
	var words := label_text.split(" ") if label_text != "" else PackedStringArray()
	for k in words.size():
		P.text(self, c + Vector2(0, 6.0 + (k - (words.size() - 1) / 2.0) * 18.0), words[k], 16)
	if n < Items.WHEEL_MAX:
		P.text(self, c + Vector2(0, ring + 26.0), "Add more to your wheel in the bag (I)", 15)
