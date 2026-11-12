extends Control
## The full map (M). Tabs switch between zones and show how many friends are in each.
## Friends appear as coloured dots wherever they are. Click to drop a pin with the label
## in the box (everyone sees it, on the map and in the world); right-click your own pin
## to remove it.

const P = preload("res://game/ui/palette.gd")
const Z = preload("res://game/data/zones.gd")

var view_zone := "middlemost"
var _label: LineEdit
var _map := Rect2()
var _scale := 1.0
var _tabs: Dictionary = {}    # zone -> Rect2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_label = LineEdit.new()
	_label.text = "Meet here!"
	_label.placeholder_text = "Pin label"
	_label.max_length = 28
	_label.custom_minimum_size = Vector2(240, 34)
	add_child(_label)
	World.pins_changed.connect(queue_redraw)
	World.beacons_changed.connect(queue_redraw)
	resized.connect(_layout)


func open(zid: String) -> void:
	view_zone = Z.map_zone(zid)   # inside a house, show the village
	visible = true
	_layout()
	queue_redraw()


func _panel() -> Rect2:
	var w := minf(size.x - 60.0, 1040.0)
	var h := minf(size.y - 40.0, 600.0)
	return Rect2((size - Vector2(w, h)) / 2.0, Vector2(w, h))


func _layout() -> void:
	var p := _panel()
	_tabs.clear()
	var x := p.position.x + 24.0
	for zid in Z.OUTDOOR:
		_tabs[zid] = Rect2(x, p.position.y + 60.0, 210.0, 38.0)
		x += 222.0
	var area := Rect2(p.position + Vector2(24, 112), Vector2(p.size.x - 300.0, p.size.y - 180.0))
	var zs := Z.size_of(view_zone)
	_scale = minf(area.size.x / zs.x, area.size.y / zs.y)
	_map = Rect2(area.position + (area.size - zs * _scale) / 2.0, zs * _scale)
	_label.position = Vector2(p.position.x + 24.0, p.end.y - 54.0)


func to_world(screen: Vector2) -> Vector2:
	return (screen - _map.position) / _scale


func to_map(world: Vector2) -> Vector2:
	return _map.position + world * _scale


func _pin_near(screen: Vector2) -> int:
	for pid: int in World.pins:
		var pin: Dictionary = World.pins[pid]
		if pin["zone"] == view_zone and to_map(pin["pos"]).distance_to(screen) < 14.0:
			return pid
	return -1


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	for zid: String in _tabs:
		if (_tabs[zid] as Rect2).has_point(event.position):
			view_zone = zid
			_layout()
			queue_redraw()
			accept_event()
			return
	if _map.has_point(event.position):
		if event.button_index == MOUSE_BUTTON_LEFT:
			var label := _label.text.strip_edges()
			World.to_host(&"c_pin_add", [view_zone, to_world(event.position), label if label != "" else "Pin"])
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			var pid := _pin_near(event.position)
			if pid >= 0:
				World.to_host(&"c_pin_remove", [pid])
		accept_event()


func _count_in(zid: String) -> int:
	var n := 0
	for id: int in World.beacons:
		if Z.map_zone(str(World.beacons[id][0])) == zid:
			n += 1
	return n


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.23, 0.16, 0.35))
	var p := _panel()
	var font := ThemeDB.fallback_font
	P.shape(self, P.rounded_rect_points(p, 22.0), P.CREAM, 4.0)
	draw_string(font, p.position + Vector2(24, 42), "Map", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, P.OUTLINE)
	draw_string(font, p.position + Vector2(100, 40), "Click to drop a pin for everyone. Right-click your pin to remove it. M to close.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.OUTLINE)
	for zid: String in _tabs:
		var r: Rect2 = _tabs[zid]
		var on := zid == view_zone
		P.shape(self, P.rounded_rect_points(r, 12.0), Color("ffe08a") if on else Color.WHITE, 3.0)
		var n := _count_in(zid)
		var t := "%s  (%d)" % [str(Z.zone(zid)["name"]), n]
		draw_string(font, r.position + Vector2(12, 25), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, P.OUTLINE)
	# The zone
	draw_rect(_map, Z.zone(view_zone)["ground"])
	if view_zone == "middlemost":
		var fr := Z.farm_rect(view_zone)
		draw_rect(Rect2(to_map(fr.position), fr.size * _scale), P.SOIL_DRY)
		draw_string(font, to_map(fr.position) + Vector2(4, -6), "Farm", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.OUTLINE)
		var well: Vector2 = Z.zone("middlemost")["well"]
		P.blob(self, to_map(well), Vector2(6, 6), P.WATER, 2.0)
		P.blob(self, to_map(Vector2(1300, 200)), Vector2(14, 22), Color("7fcf7a"), 2.0)
	if view_zone == "mossmouth":
		draw_rect(_map, Color(0.1, 0.15, 0.2, 0.25))
	for ex: Dictionary in Z.zone(view_zone)["exits"]:
		var er: Rect2 = ex["rect"]
		draw_rect(Rect2(to_map(er.position), er.size * _scale), Color("ffe08a"))
		var lp := to_map(er.get_center())
		draw_string(font, lp + Vector2(-50, -10), str(ex["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.OUTLINE)
	draw_rect(_map, P.OUTLINE, false, 3.0)
	# Pins
	for pid: int in World.pins:
		var pin: Dictionary = World.pins[pid]
		if pin["zone"] != view_zone:
			continue
		var pp := to_map(pin["pos"])
		draw_line(pp, pp + Vector2(0, -16), P.OUTLINE, 3.0, true)
		P.blob(self, pp + Vector2(0, -20), Vector2(8, 8), pin["color"], 2.5)
		draw_string(font, pp + Vector2(12, -16), str(pin["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.OUTLINE)
	# Friends (and you)
	for id: int in World.beacons:
		var b: Array = World.beacons[id]
		if Z.map_zone(str(b[0])) != view_zone:
			continue
		var fp := to_map(Z.map_pos(str(b[0]), b[1]))   # someone indoors shows at the house door
		P.blob(self, fp, Vector2(8, 8), Net.player_color(id), 2.5)
		if id == World.me():
			draw_arc(fp, 12.0, 0.0, TAU, 20, Color.WHITE, 3.0, true)
		draw_string(font, fp + Vector2(11, 5), Net.player_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.OUTLINE)
	# Friends list on the right
	var lx := p.end.x - 250.0
	var ly := p.position.y + 130.0
	draw_string(font, Vector2(lx, ly), "Where everyone is", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, P.OUTLINE)
	ly += 28.0
	var ids: Array = Net.players.keys()
	ids.sort()
	for id: int in ids:
		draw_circle(Vector2(lx + 7, ly - 5), 6.0, Net.player_color(id))
		var where := "?"
		if World.beacons.has(id):
			where = str(Z.zone(str(World.beacons[id][0]))["name"])
		draw_string(font, Vector2(lx + 20, ly), "%s  -  %s" % [Net.player_name(id), where], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, P.OUTLINE)
		ly += 24.0
	ly += 16.0
	draw_string(font, Vector2(lx, ly), "Pins: %d" % World.pins.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, P.OUTLINE)
