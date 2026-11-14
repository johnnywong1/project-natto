extends Node2D
## Draws the zone the local player is in: ground, paths, decor, farm plots and crops,
## pickups, exits, and house fronts with their doors (a padlock while locked). House
## interiors get a floor, a back wall with windows, furniture and a doormat instead.
## Layouts come from the stage files (game/data/zones/*.json, see docs/STAGES.md); the
## scattered decor is placed by each zone's seed, so every player sees the same map.
## Lamps and glowing mushrooms carry 2D lights that show up at night and underground.

const P = preload("res://game/ui/palette.gd")
const Z = preload("res://game/data/zones.gd")
const Items = preload("res://game/data/items.gd")
const Icons = preload("res://game/ui/icons.gd")
const FireProp = preload("res://game/world/fire_prop.gd")
const LiftProp = preload("res://game/world/lift_prop.gd")

var zone := ""
var size := Vector2(2600, 1700)
var decor: Array = []       # [kind, pos, scale]
var paths: Array = []       # [PackedVector2Array, width, color]
var _glows: Array[PointLight2D] = []
var _props: Array[Node] = []
var _lift_nodes: Dictionary = {}
var _t := 0.0
var _redraw_t := 0.0
var _light_tex: GradientTexture2D


func _ready() -> void:
	World.crop_changed.connect(_on_crop_changed)
	World.pickups_changed.connect(_on_pickups_changed)
	World.ice_changed.connect(_on_pickups_changed)
	World.stumps_changed.connect(_on_pickups_changed)
	World.vitals_changed.connect(queue_redraw)
	_light_tex = GradientTexture2D.new()
	_light_tex.width = 256
	_light_tex.height = 256
	_light_tex.fill = GradientTexture2D.FILL_RADIAL
	_light_tex.fill_from = Vector2(0.5, 0.5)
	_light_tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_light_tex.gradient = g


func _on_crop_changed(z: String, _i: int) -> void:
	if z == zone:
		queue_redraw()


func _on_pickups_changed(z: String) -> void:
	if z == zone:
		queue_redraw()


func build(zid: String) -> void:
	zone = zid
	var zd := Z.zone(zid)
	size = zd["size"]
	for l in _glows:
		l.queue_free()
	_glows.clear()
	for n in _props:
		n.queue_free()
	_props.clear()
	_lift_nodes.clear()
	for f: Vector2 in zd["fires"]:
		_add_prop("fireplace" if Z.is_interior(zid) else str(zd.get("fire_kind", "campfire")), f)
	for lp: Vector2 in zd["lamps"]:
		_add_prop("lamp", lp)
	for l: Dictionary in zd["lifts"]:
		var lift := LiftProp.new()
		lift.setup(l, str(World.lifts.get(zid, {}).get(l["id"], "bottom")))
		add_child(lift)
		_props.append(lift)
		_lift_nodes[l["id"]] = lift
	decor.clear()
	paths.clear()
	if not Z.is_interior(zid):
		_layout(zd)
	queue_redraw()


func _add_prop(kind: String, pos: Vector2) -> void:
	var f := FireProp.new()
	f.kind = kind
	f.position = pos
	add_child(f)
	_props.append(f)


func animate_lift(lift_id: String, from_end: String, to_end: String, seconds: float) -> void:
	if _lift_nodes.has(lift_id):
		(_lift_nodes[lift_id] as LiftProp).animate(from_end, to_end, seconds)


func _add_light(pos: Vector2, color: Color, scale_: float, energy: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _light_tex
	l.texture_scale = scale_
	l.color = color
	l.energy = energy
	l.position = pos
	add_child(l)
	return l


## Lays the zone out from its stage file (docs/STAGES.md): the paths, the fixed decor, and
## the scattered decor (trees, ferns, rocks...), which is placed by the zone's seed so every
## player sees the same map. Scatter avoids exits, paths, the farm, the well and the stage's
## "keep_clear" rectangles.
func _layout(zd: Dictionary) -> void:
	for pth: Dictionary in zd.get("paths", []):
		var pts := PackedVector2Array()
		for pt: Vector2 in pth["points"]:
			pts.append(pt)
		paths.append([pts, float(pth.get("width", 80.0)), pth.get("color", P.PATH)])
	# The fixed and scattered decor both come from zones.gd now, so the collision code and
	# the renderer place every tree and bush in exactly the same spot. Trees carry their
	# stump index (a 4th element) so _draw_decor can tell a standing tree from a stump.
	var tree_i := 0
	for e: Array in Z.all_decor(zone):
		if e[0] == "tree":
			decor.append(["tree", e[1], e[2], tree_i])
			tree_i += 1
		else:
			decor.append([e[0], e[1], e[2]])
		if bool(e[3]):
			_glows.append(_add_light((e[1] as Vector2) + Vector2(0, -12), e[4], 1.2, 0.8))
	for lt: Dictionary in zd.get("lights", []):
		_glows.append(_add_light(lt["pos"], lt.get("color", Color.WHITE), float(lt.get("scale", 1.0)), float(lt.get("energy", 1.0))))


func _process(delta: float) -> void:
	_t += delta
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.25    # growth rings and bobbing pickups
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if zone == "":
		return
	var zd := Z.zone(zone)
	draw_rect(Rect2(Vector2(-200, -200), size + Vector2(400, 400)), Color(zd["ground"]).darkened(0.35))   # beyond the edge
	draw_rect(Rect2(Vector2.ZERO, size), zd["ground"])
	if bool(zd.get("interior", false)):
		_draw_room(zd)
		return
	var accent: Color = zd["accent"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(zd["seed"]) + 99
	for i in int(size.x * size.y / 6000.0):
		var t := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
		draw_line(t, t + Vector2(-4, -9), accent, 3.0, true)
		draw_line(t, t + Vector2(3, -10), accent, 3.0, true)
	# All path outlines first, then all fills, so joins and crossings stay seamless.
	for pth: Array in paths:
		var pts: PackedVector2Array = pth[0]
		var w: float = pth[1]
		draw_polyline(pts, P.OUTLINE, w + 8.0, false)
		for i in range(1, pts.size() - 1):
			draw_circle(pts[i], w * 0.5 + 4.0, P.OUTLINE)
	for pth: Array in paths:
		var pts: PackedVector2Array = pth[0]
		var w: float = pth[1]
		draw_polyline(pts, pth[2], w, false)
		for i in range(1, pts.size() - 1):
			draw_circle(pts[i], w * 0.5, pth[2])
	draw_rect(Rect2(Vector2.ZERO, size), P.OUTLINE, false, 8.0)
	_draw_heights(zd)
	for ex: Dictionary in zd["exits"]:
		_draw_exit(ex)
	for lm: Dictionary in zd.get("landmarks", []):
		match str(lm["kind"]):
			"great_sprout":
				_draw_sprout(lm["pos"])
	if zd.has("well"):
		_draw_well(zd["well"])
	if zd.has("farm"):
		_draw_farm()
	var flat: Array = []
	var tall: Array = []
	for d: Array in decor:
		if d[0] in ["flower", "puddle", "roots", "rock", "mossrock", "fern", "bush", "mushroom"]:
			flat.append(d)
		else:
			tall.append(d)
	for d: Array in flat:
		_draw_decor(d)
	tall.sort_custom(func(x: Array, y: Array) -> bool: return (x[1] as Vector2).y < (y[1] as Vector2).y)
	for d: Array in tall:
		_draw_decor(d)
	_draw_ice_and_chests(zd)
	var pk: Dictionary = World.pickups.get(zone, {})
	var item: String = zd["pickup"]
	for pid: int in pk:
		var pos: Vector2 = pk[pid]
		var bob := sin(_t * 3.0 + float(pid)) * 3.0
		P.shadow(self, pos, Vector2(14, 5))
		Icons.draw(self, item, pos + Vector2(0, -14 + bob), 1.25)


## Inside a house: plank floor, back wall with windows, rug, furniture, doormat, chest.
func _draw_room(zd: Dictionary) -> void:
	var wall_col: Color = zd["wall_color"]
	for y in range(0, int(size.y), 40):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(zd["accent"]), 2.0)
		var off := 60.0 if int(y / 40.0) % 2 == 0 else 0.0
		for x in range(int(off), int(size.x), 120):
			draw_line(Vector2(x, y), Vector2(x, y + 40), Color(zd["accent"]), 2.0)
	draw_rect(Rect2(0, 0, size.x, 80), wall_col)                       # back wall
	draw_line(Vector2(0, 80), Vector2(size.x, 80), P.OUTLINE, 4.0)
	for wx: float in [300.0, 520.0]:
		var lit := World.clock >= 18.5 * 60.0 or World.clock < 6.5 * 60.0
		P.shape(self, P.rounded_rect_points(Rect2(wx, 14, 70, 48), 8.0), Color("2c3557") if lit else Color("bfe6ff"), 3.0)
		draw_line(Vector2(wx + 35, 14), Vector2(wx + 35, 62), P.OUTLINE, 3.0)
	P.blob(self, size / 2.0 + Vector2(0, 40), Vector2(170, 90), Color("e8a0a8"), 3.0)   # rug
	P.blob(self, size / 2.0 + Vector2(0, 40), Vector2(120, 60), Color("f3c3c8"), 0.0)
	var walls: Array = zd["walls"]
	# Fireplace (the flame and its light are a FireProp)
	var fp: Rect2 = walls[0]
	P.shape(self, P.rounded_rect_points(fp, 10.0), P.STONE, 4.0)
	P.shape(self, P.rounded_rect_points(Rect2(fp.position + Vector2(24, 60), Vector2(fp.size.x - 48, 70)), 14.0), Color("4a3a32"), 3.0)
	# Bed
	var bed: Rect2 = walls[1]
	P.shape(self, P.rounded_rect_points(bed, 12.0), P.WOOD, 4.0)
	P.shape(self, P.rounded_rect_points(Rect2(bed.position + Vector2(10, 10), bed.size - Vector2(20, 20)), 10.0), Color(zd["wall_color"]).darkened(0.1), 3.0)
	P.shape(self, P.rounded_rect_points(Rect2(bed.end - Vector2(60, bed.size.y - 14), Vector2(46, bed.size.y - 28)), 10.0), Color.WHITE, 3.0)
	# Table with a teapot
	var table: Rect2 = walls[2]
	P.shape(self, P.rounded_rect_points(table, 12.0), Color("c98b52"), 4.0)
	P.blob(self, table.get_center() + Vector2(-30, -8), Vector2(16, 12), Color("8fd3ff"), 3.0)
	P.blob(self, table.get_center() + Vector2(40, -4), Vector2(10, 8), Color.WHITE, 2.5)
	# Shelf
	var shelf: Rect2 = walls[3]
	P.shape(self, P.rounded_rect_points(shelf, 8.0), Color("b07a52"), 4.0)
	for k in 4:
		P.blob(self, shelf.position + Vector2(22 + k * 32, 40), Vector2(9, 14), [P.BERRY, P.LEAF, P.WATER, P.DRESS][k], 2.0)
	# Doormat (the way out)
	var mat: Rect2 = (zd["exits"][0] as Dictionary)["rect"]
	P.shape(self, P.rounded_rect_points(mat.grow(-4.0), 10.0), Color("c9a77a"), 3.0)
	P.text(self, mat.get_center() + Vector2(0, -16), "Outside", 14)
	draw_rect(Rect2(Vector2.ZERO, size), P.OUTLINE, false, 8.0)
	_draw_ice_and_chests(zd)


func _draw_exit(ex: Dictionary) -> void:
	var r: Rect2 = ex["rect"]
	draw_rect(r, Color(1, 1, 0.85, 0.45))
	var c := r.get_center()
	var inward := Vector2.ZERO
	if r.position.x <= 0.0:
		inward = Vector2.RIGHT
	elif r.end.x >= size.x:
		inward = Vector2.LEFT
	elif r.position.y <= 0.0:
		inward = Vector2.DOWN
	else:
		inward = Vector2.UP
	var sign_pos := c + inward * 120.0
	P.shape(self, P.rounded_rect_points(Rect2(sign_pos + Vector2(-5, -50), Vector2(10, 56)), 4.0), P.WOOD, 3.0)
	var label: String = ex["label"]
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var board := Rect2(sign_pos + Vector2(-w / 2.0 - 12.0, -86), Vector2(w + 24.0, 34))
	P.shape(self, P.rounded_rect_points(board, 8.0), P.CREAM, 3.0)
	draw_string(font, board.position + Vector2(12, 24), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, P.OUTLINE)
	for k in 3:
		var tip := c - inward * 10.0 - inward * float(k) * 26.0
		var side := Vector2(-inward.y, inward.x)
		draw_polyline(PackedVector2Array([tip + inward * 12.0 + side * 14.0, tip - inward * 2.0, tip + inward * 12.0 - side * 14.0]), P.OUTLINE, 5.0, true)


func _draw_sprout(base: Vector2) -> void:
	P.shape(self, PackedVector2Array([base + Vector2(-120, 60), base + Vector2(-70, -400), base + Vector2(70, -400), base + Vector2(120, 60)]), Color("7fcf7a"))
	for k in 5:
		var y := -40.0 - k * 70.0
		draw_line(base + Vector2(-90 + k * 6, y), base + Vector2(90 - k * 6, y + 18), Color("5fb35f"), 6.0, true)
	P.blob(self, base + Vector2(-170, -80), Vector2(70, 30), Color("86d47e"))
	P.blob(self, base + Vector2(170, -140), Vector2(70, 30), Color("86d47e"))
	P.text(self, base + Vector2(0, 100), "The Great Sprout", 22)


func _draw_well(c: Vector2) -> void:
	P.shadow(self, c + Vector2(0, 22), Vector2(58, 14))
	P.shape(self, P.rounded_rect_points(Rect2(c.x - 50.0, c.y - 86.0, 12, 90), 5.0), P.WOOD, 3.0)
	P.shape(self, P.rounded_rect_points(Rect2(c.x + 38.0, c.y - 86.0, 12, 90), 5.0), P.WOOD, 3.0)
	P.shape(self, PackedVector2Array([c + Vector2(-66, -78), c + Vector2(0, -116), c + Vector2(66, -78)]), P.PEPPER_RED)
	P.blob(self, c, Vector2(48, 28), P.STONE)
	P.blob(self, c + Vector2(0, -5), Vector2(33, 15), P.WATER, 3.0)
	P.text(self, c + Vector2(0, 52), "WELL", 16)


func _draw_farm() -> void:
	var fr := Z.farm_rect(zone).grow(26.0)
	P.outline(self, P.rounded_rect_points(fr, 18.0), P.WOOD, 8.0)
	var plots: Array = World.crops.get(zone, [])
	for i in plots.size():
		var p: Array = plots[i]
		var c := Z.plot_center(zone, i)
		var rect := Rect2(c - Z.TILE / 2.0, Z.TILE)
		var wet := float(p[2]) > 0.0
		var soil: Color = P.SOIL_WET if wet else P.SOIL_DRY
		P.shape(self, P.rounded_rect_points(rect, 12.0), soil)
		for k in 3:
			var y: float = rect.position.y + 15.0 + k * 14.0
			draw_line(Vector2(rect.position.x + 14.0, y), Vector2(rect.end.x - 14.0, y), soil.darkened(0.15), 3.0, true)
		_draw_crop(p, c, i)


func _draw_crop(p: Array, c: Vector2, i: int) -> void:
	var crop: String = p[0]
	if crop == "":
		return
	var stage: int = p[1]
	var top: int = Items.CROPS[crop]["stages"]
	var col: Color = Items.ITEMS[crop]["color"]
	if stage == 1:
		P.blob(self, c + Vector2(0, 6), Vector2(14, 7), P.SOIL_MOUND, 3.0)
		P.blob(self, c + Vector2(0, 2), Vector2(5, 4), P.CREAM, 2.5)
	elif stage < top:
		var grow := float(stage - 1) / float(top - 1)
		var h := 12.0 + 10.0 * grow
		draw_line(c + Vector2(0, 10), c + Vector2(0, -h), P.OUTLINE, 7.0, true)
		draw_line(c + Vector2(0, 10), c + Vector2(0, -h), P.LEAF, 3.0, true)
		P.blob(self, c + Vector2(-9, -h), Vector2(9.0 + 4.0 * grow, 5.0 + 2.0 * grow), P.LEAF, 3.0)
		P.blob(self, c + Vector2(9, -h - 3.0), Vector2(9.0 + 4.0 * grow, 5.0 + 2.0 * grow), P.LEAF, 3.0)
	else:
		if crop == "popberry":
			P.blob(self, c + Vector2(0, -6), Vector2(27, 20), P.LEAF)
			for o: Vector2 in [Vector2(-12, -12), Vector2(10, -16), Vector2(-2, -3), Vector2(14, -2)]:
				P.blob(self, c + o, Vector2(7, 7), col, 3.0)
				draw_circle(c + o + Vector2(-2, -2), 2.0, P.BERRY_SHINE)
		else:
			P.blob(self, c + Vector2(0, 4), Vector2(15, 13), col)
			for o: Vector2 in [Vector2(-10, -14), Vector2(0, -20), Vector2(10, -14)]:
				P.blob(self, c + o, Vector2(6, 11), P.LEAF, 3.0)
			draw_line(c + Vector2(-5, 2), c + Vector2(4, 8), Color("fff27a"), 3.0, true)
	if stage < top:
		var bubble := c + Vector2(26, -22)
		if float(p[2]) > 0.0:
			var k := 1.0 - float(p[2]) / World.GROW_TIME
			P.blob(self, bubble, Vector2(11, 11), Color.WHITE, 3.0)
			draw_arc(bubble, 6.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(k, 0.02, 1.0), 20, P.WATER, 4.0, true)
		elif fmod(_t + float(i) * 0.1, 1.2) < 0.85:
			P.blob(self, bubble, Vector2(11, 11), Color.WHITE, 3.0)
			P.blob(self, bubble + Vector2(0, 1), Vector2(4.5, 5.5), P.WATER, 2.0)


func _draw_decor(d: Array) -> void:
	var kind: String = d[0]
	var p: Vector2 = d[1]
	var s: float = d[2]
	match kind:
		"tree":
			# A felled tree is a stump until it grows back; a sapling pokes up as it does.
			var regrow: float = float((World.stumps.get(zone, {}) as Dictionary).get(int(d[3]), -1.0)) if d.size() > 3 else -1.0
			if regrow >= 0.0:
				P.shadow(self, p, Vector2(26, 9) * s)
				P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-13, -16) * s, Vector2(26, 18) * s), 6.0), P.WOOD, 3.0)
				draw_circle(p + Vector2(0, -8) * s, 6.0 * s, P.WOOD.lightened(0.25))   # cut rings
				var grown := clampf(1.0 - regrow / 150.0, 0.0, 1.0)
				if grown > 0.35:
					var leaf2 := Color("7fcf7a") if zone != "fernery" else Color("6cc070")
					P.blob(self, p + Vector2(0, -26) * s * grown, Vector2(20, 18) * s * grown, leaf2)
				return
			P.shadow(self, p, Vector2(40, 12) * s)
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-10, -60) * s, Vector2(20, 62) * s), 6.0), P.WOOD, 3.0)
			var leaf := Color("7fcf7a") if zone != "fernery" else Color("6cc070")
			P.blob(self, p + Vector2(0, -92) * s, Vector2(52, 46) * s, leaf)
			P.blob(self, p + Vector2(-20, -104) * s, Vector2(16, 12) * s, leaf.lightened(0.2), 0.0)
		"bush":
			P.blob(self, p, Vector2(30, 20) * s, Color("86d47e"))
			draw_circle(p + Vector2(-8, -6) * s, 4.0 * s, P.BERRY)
		"flower":
			var cols: Array[Color] = [Color("ffb3c7"), Color("fff27a"), Color("ffffff"), Color("b9a6ff")]
			var col: Color = cols[int(s) % 4]
			for k in 4:
				draw_circle(p + Vector2.from_angle(k * PI / 2.0) * 4.0, 3.5, col)
			draw_circle(p, 2.5, Color("ffd27a"))
		"rock":
			P.blob(self, p, Vector2(22, 14) * s, P.STONE)
		"mossrock":
			P.blob(self, p, Vector2(28, 18) * s, P.STONE)
			P.blob(self, p + Vector2(-4, -8) * s, Vector2(18, 8) * s, Color("86d47e"), 0.0)
		"fern":
			for k in 5:
				var a := -PI / 2.0 + (k - 2) * 0.45
				var tip := p + Vector2.from_angle(a) * 34.0 * s
				draw_line(p, tip, P.OUTLINE, 6.0, true)
				draw_line(p, tip, Color("6cc070"), 3.0, true)
		"house":
			P.shadow(self, p + Vector2(0, 10), Vector2(110, 18))
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-90, -110), Vector2(180, 120)), 12.0), P.CREAM)
			P.shape(self, PackedVector2Array([p + Vector2(-112, -100), p + Vector2(0, -180), p + Vector2(112, -100)]), P.PEPPER_RED)
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-20, -60), Vector2(40, 70)), 8.0), P.WOOD)
			var lit := World.clock >= 18.5 * 60.0 or World.clock < 6.5 * 60.0
			var win := Color("ffe59a") if lit else Color("bfe6ff")
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-72, -88), Vector2(36, 30)), 6.0), win, 3.0)
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(36, -88), Vector2(36, 30)), 6.0), win, 3.0)
			_draw_door_sign(p)
		"board":
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-5, -40), Vector2(10, 50)), 4.0), P.WOOD, 3.0)
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-40, -82), Vector2(80, 48)), 8.0), P.CREAM, 3.0)
			P.text(self, p + Vector2(0, -52), "Notices", 14)
		"roots":
			var end := p + Vector2(0, 120) * s
			draw_polyline(PackedVector2Array([p, p + Vector2(14, 50) * s, end]), P.OUTLINE, 10.0, true)
			draw_polyline(PackedVector2Array([p, p + Vector2(14, 50) * s, end]), Color("8a6a52"), 5.0, true)
		"stalagmite":
			P.shadow(self, p, Vector2(22, 7) * s)
			P.shape(self, PackedVector2Array([p + Vector2(-20, 0) * s, p + Vector2(0, -70) * s, p + Vector2(20, 0) * s]), Color("c3d0c8"))
		"puddle":
			P.blob(self, p, Vector2(46, 18) * s, Color("8fd3ff"), 3.0)
			draw_arc(p, (8.0 + fmod(_t * 10.0, 20.0)) * s, 0.0, TAU, 20, Color(1, 1, 1, 0.6), 2.0, true)
		"mushroom":
			draw_line(p, p + Vector2(0, -12) * s, P.OUTLINE, 7.0, true)
			draw_line(p, p + Vector2(0, -12) * s, P.CREAM, 3.5, true)
			P.blob(self, p + Vector2(0, -14) * s, Vector2(14, 8) * s, Color("9ff0e0"))


## Raised ledges get a lighter top; lower shelves a darker floor. Cliff faces sit on walls.
func _draw_heights(zd: Dictionary) -> void:
	if (zd["plateaus"] as Array).is_empty():
		return   # walls here are houses or furniture, drawn as themselves
	var ground: Color = zd["ground"]
	for r: Rect2 in zd["plateaus"]:
		var lower := zone == "mossmouth"
		draw_rect(r, ground.darkened(0.18) if lower else ground.lightened(0.12))
	for w: Rect2 in zd["walls"]:
		var face := Color("8a7058") if zone != "mossmouth" else Color("5f6f68")
		draw_rect(w, face)
		var n := int(w.size.x / 26.0) if w.size.x > w.size.y else int(w.size.y / 26.0)
		for k in n:
			if w.size.x > w.size.y:
				var x := w.position.x + 13.0 + k * 26.0
				draw_line(Vector2(x, w.position.y + 6), Vector2(x + 6, w.end.y - 6), face.darkened(0.2), 3.0, true)
			else:
				var y := w.position.y + 13.0 + k * 26.0
				draw_line(Vector2(w.position.x + 6, y), Vector2(w.end.x - 6, y + 6), face.darkened(0.2), 3.0, true)
		draw_rect(w, P.OUTLINE, false, 4.0)
		var lip := Rect2(w.position, Vector2(w.size.x, 8)) if w.size.x > w.size.y else Rect2(w.position, Vector2(8, w.size.y))
		draw_rect(lip, ground.lightened(0.2))


## The name over a house door, and a padlock while it's locked.
func _draw_door_sign(p: Vector2) -> void:
	for door: Dictionary in Z.zone(zone).get("doors", []):
		if (door["pos"] as Vector2).distance_to(p) > 40.0:
			continue
		var house: String = door["to"]
		var h: Dictionary = Z.HOUSES[house]
		var font := ThemeDB.fallback_font
		var name_text := str(h["name"])
		var w: float = font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var plate := Rect2(p + Vector2(-w / 2.0 - 8.0, -138.0), Vector2(w + 16.0, 22))
		P.shape(self, P.rounded_rect_points(plate, 8.0), P.CREAM, 2.5)
		draw_string(font, plate.position + Vector2(8, 16), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.OUTLINE)
		if str(h["lock"]) != "" and not World.unlocked.has(house):
			var lc := p + Vector2(0, -26)
			draw_arc(lc + Vector2(0, -8), 7.0, PI, TAU, 10, P.OUTLINE, 3.5, true)
			P.shape(self, P.rounded_rect_points(Rect2(lc + Vector2(-10, -8), Vector2(20, 16)), 4.0), Color("e3b04b"), 2.5)
			draw_circle(lc + Vector2(0, -1), 2.5, P.OUTLINE)


func _draw_ice_and_chests(zd: Dictionary) -> void:
	var zi: Dictionary = World.ice.get(zone, {})
	for iid: int in zi:
		var block: Array = zi[iid]
		var c: Vector2 = block[0]
		if bool(block[1]):
			P.blob(self, c, Vector2(52, 22), Color("8fd3ff"), 3.0)
			draw_arc(c, 10.0 + fmod(_t * 12.0, 26.0), 0.0, TAU, 20, Color(1, 1, 1, 0.6), 2.0, true)
		else:
			var pts := PackedVector2Array()
			for k in 6:
				pts.append(c + Vector2.from_angle(TAU * k / 6.0 + 0.4) * Vector2(Z.ICE_RADIUS, Z.ICE_RADIUS * 0.85))
			P.shape(self, pts, Color(0.82, 0.95, 1.0), 4.0)
			draw_line(c + Vector2(-16, -14), c + Vector2(-4, -26), Color.WHITE, 4.0, true)
			draw_line(c + Vector2(6, 10), c + Vector2(16, -2), Color("bfe3ff"), 3.0, true)
	var opened: Array = World.vitals.get("chests", [])
	for ch: Dictionary in zd["chests"]:
		var p: Vector2 = ch["pos"]
		var open: bool = ch["id"] in opened
		P.shadow(self, p + Vector2(0, 6), Vector2(36, 9))
		P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-30, -30), Vector2(60, 36)), 6.0), Color("c98b52"))
		if open:
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-30, -58), Vector2(60, 20)), 6.0), Color("b07a45"))
			draw_rect(Rect2(p + Vector2(-24, -28), Vector2(48, 10)), Color("3a2a1e"))
		else:
			P.shape(self, P.rounded_rect_points(Rect2(p + Vector2(-32, -44), Vector2(64, 18)), 6.0), Color("b07a45"))
			P.blob(self, p + Vector2(0, -24), Vector2(6, 6), Color("ffd27a"), 2.5)
		P.text(self, p + Vector2(0, 30), "Chest (E)" if not open else "Empty", 14)
