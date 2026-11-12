extends Control
## Draws the always-on HUD, laid out so nothing overlaps at 1152x648 and up:
##   top left      zone, day and time, weather; Pepper's lesson card under it
##   top right     minimap, and who's playing (when you're not alone)
##   top centre    short messages ("toasts")
##   bottom left   hearts, stamina orbs, and your shield's health or how your light is doing
##   bottom centre the quickbar: your item wheel in a row, with what you're holding
##   bottom right  a reminder of the menu and controls keys
## The full controls are on the controls screen (F1), not crammed onto the HUD.

const P = preload("res://game/ui/palette.gd")
const Z = preload("res://game/data/zones.gd")
const Items = preload("res://game/data/items.gd")
const Icons = preload("res://game/ui/icons.gd")

const MARGIN := 14.0
const CARD_W := 300.0

var hud: Variant


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud = get_parent()


func _draw() -> void:
	if not Net.in_game:
		return
	var vs := size
	var y := _draw_clock(Vector2(MARGIN, MARGIN))
	_draw_lesson(Vector2(MARGIN, y + 10.0))
	var mm := Rect2(vs.x - 234.0 - MARGIN, MARGIN, 234.0, 150.0)
	_draw_minimap(mm)
	_draw_players(Vector2(mm.position.x - 6.0, mm.end.y + 16.0))
	_draw_quickbar(vs)
	_draw_vitals(Vector2(MARGIN, vs.y - 118.0 - MARGIN))
	_hint(Vector2(vs.x - MARGIN, vs.y - MARGIN), "Esc  menu    F1  controls", true)
	_draw_toasts(vs)
	if bool(World.vitals.get("fainted", false)):
		var msg := "You fainted! A friend can revive you, or you'll wake at the entrance in %d..." % ceili(float(World.vitals.get("faint_t", 0.0)))
		var font := ThemeDB.fallback_font
		var w: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var r := Rect2(Vector2((vs.x - w) / 2.0 - 18.0, vs.y * 0.3), Vector2(w + 36.0, 46))
		P.shape(self, P.rounded_rect_points(r, 16.0), Color("ffe0e6"), 4.0)
		draw_string(font, r.position + Vector2(18, 30), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, P.OUTLINE)


# ---------------------------------------------------------------- helpers

func _card(r: Rect2) -> void:
	P.shape(self, P.rounded_rect_points(r, 14.0), Color(P.CREAM, 0.95), 3.0)


## A small key hint on a pale pill so it reads on grass, paths and at night. `at` is the
## pill's bottom-left corner, or its bottom-right corner when right_aligned.
func _hint(at: Vector2, s: String, right_aligned: bool = false) -> void:
	var font := ThemeDB.fallback_font
	var w: float = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var r := Rect2(Vector2(at.x - (w + 16.0 if right_aligned else 0.0), at.y - 24.0), Vector2(w + 16.0, 24.0))
	P.shape(self, P.rounded_rect_points(r, 10.0), Color(P.CREAM, 0.85), 2.0)
	_text(r.position + Vector2(8, 17), s, 13)


func _text(pos: Vector2, s: String, size_px: int, color: Color = P.OUTLINE) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


## Draws text wrapped to `width`; returns how many lines it took.
func _wrapped(pos: Vector2, s: String, width: float, size_px: int, color: Color, max_lines: int = 2) -> int:
	var font := ThemeDB.fallback_font
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, max_lines, color)
	var lines := font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, max_lines).y / font.get_height(size_px)
	return maxi(roundi(lines), 1)


# ---------------------------------------------------------------- top left

## Zone, day and time, weather. Returns the card's bottom edge.
func _draw_clock(at: Vector2) -> float:
	var zd := Z.zone(World.my_zone)
	var night := Z.is_night(World.clock)
	var hint := ""
	if Z.is_interior(World.my_zone):
		hint = "Indoors. Walk onto the doormat to go out."
	elif not bool(zd["outdoor"]):
		hint = "Underground: dark all day. Carry a light."
	elif night:
		hint = "Night: carry a light. Lamps are lit."
	var r := Rect2(at, Vector2(CARD_W, 66.0 if hint == "" else 84.0))
	_card(r)
	_text(at + Vector2(14, 27), str(zd["name"]), 20)
	_text(at + Vector2(14, 52), "Day %d   %s" % [World.day, World.clock_text()], 16)
	var w: String = World.weather.get(World.my_zone, "clear")
	var wname := str(Z.WEATHER_NAMES.get(w, w))
	var font := ThemeDB.fallback_font
	var ww: float = font.get_string_size(wname, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	_weather_icon(Vector2(r.end.x - ww - 34.0, at.y + 46.0), "moon" if w == "clear" and night else w)
	_text(Vector2(r.end.x - ww - 14.0, at.y + 52.0), wname, 15)
	if hint != "":
		_text(at + Vector2(14, 74), hint, 12, P.OUTLINE.lightened(0.15))
	return r.end.y


func _weather_icon(c: Vector2, kind: String) -> void:
	match kind:
		"moon":
			P.blob(self, c, Vector2(9, 9), Color("fff1c4"), 2.5)
			draw_circle(c + Vector2(4, -3), 7.5, Color(P.CREAM, 0.95))   # bite out of it: a crescent
		"clear":
			for k in 8:
				var d := Vector2.from_angle(TAU * k / 8.0)
				draw_line(c + d * 11.0, c + d * 15.0, Color("ffb648"), 2.5, true)
			P.blob(self, c, Vector2(8, 8), Color("ffd27a"), 2.5)
		"cloudy", "rain", "drizzle":
			P.blob(self, c + Vector2(-5, 0), Vector2(9, 7), Color("e6eef5"), 2.5)
			P.blob(self, c + Vector2(5, -3), Vector2(9, 8), Color("e6eef5"), 2.5)
			if kind != "cloudy":
				var n := 3 if kind == "rain" else 2
				for k in n:
					draw_line(c + Vector2(-6 + k * 6, 9), c + Vector2(-8 + k * 6, 15), Color("5aa9e6"), 2.5, true)
		"mist":
			for k in 3:
				draw_line(c + Vector2(-12, -6 + k * 6), c + Vector2(12, -6 + k * 6), Color("9fb0bd"), 3.0, true)
		"drip":
			P.blob(self, c + Vector2(0, 2), Vector2(6, 8), P.WATER, 2.5)
		"spores":
			for k in 5:
				draw_circle(c + Vector2.from_angle(k * 1.3) * 7.0, 3.0, Color("9ff0e0"))


## Pepper's lesson card: the lesson's title and a tick box per task.
func _draw_lesson(at: Vector2) -> void:
	var lesson: Dictionary = World.vitals.get("lesson", {})
	var tasks: Array = lesson.get("tasks", [])
	if tasks.is_empty():
		return
	var r := Rect2(at, Vector2(CARD_W, 50.0 + 22.0 * tasks.size()))
	P.shape(self, P.rounded_rect_points(r, 14.0), Color("fff7d6", 0.95), 3.0)
	_text(at + Vector2(14, 20), "Pepper's lesson %d of %d" % [int(lesson["i"]) + 1, int(lesson["n"])], 12, P.OUTLINE.lightened(0.2))
	_text(at + Vector2(14, 40), str(lesson["title"]), 16)
	var y := at.y + 62.0
	for t: Array in tasks:
		var done := int(t[1]) >= int(t[2])
		var box := Rect2(Vector2(at.x + 14, y - 13), Vector2(14, 14))
		P.shape(self, P.rounded_rect_points(box, 3.0), Color("bfeadb") if done else Color.WHITE, 2.0)
		if done:
			draw_polyline(PackedVector2Array([box.position + Vector2(3, 7), box.position + Vector2(6, 11), box.position + Vector2(12, 2)]), P.OUTLINE, 2.5, true)
		var label: String = t[0]
		if int(t[2]) > 1:
			label += "  %d/%d" % [int(t[1]), int(t[2])]
		_text(Vector2(at.x + 36, y), label, 13, P.OUTLINE.lightened(0.3) if done else P.OUTLINE)
		y += 22.0


# ---------------------------------------------------------------- top right

func _draw_minimap(r: Rect2) -> void:
	_card(r.grow(6.0))
	var zsize := Z.size_of(World.my_zone)
	var s := minf(r.size.x / zsize.x, r.size.y / zsize.y)
	var area := Rect2(r.position + (r.size - zsize * s) / 2.0, zsize * s)
	draw_rect(area, Z.zone(World.my_zone)["ground"])
	if World.my_zone == "middlemost":
		var fr := Z.farm_rect(World.my_zone)
		draw_rect(Rect2(area.position + fr.position * s, fr.size * s), P.SOIL_DRY)
		draw_circle(area.position + (Z.zone("middlemost")["well"] as Vector2) * s, 3.0, P.WATER)
	for ex: Dictionary in Z.zone(World.my_zone)["exits"]:
		var er: Rect2 = ex["rect"]
		draw_rect(Rect2(area.position + er.position * s, er.size * s), Color("ffe08a"))
	for npc: Dictionary in Z.zone(World.my_zone).get("npcs", []):
		draw_circle(area.position + (npc["pos"] as Vector2) * s, 3.5, P.PEPPER_RED)
	draw_rect(area, P.OUTLINE, false, 2.0)
	for pid: int in World.pins:
		var pin: Dictionary = World.pins[pid]
		if pin["zone"] == World.my_zone:
			var pp := area.position + (pin["pos"] as Vector2) * s
			draw_line(pp, pp + Vector2(0, -9), P.OUTLINE, 2.0)
			P.blob(self, pp + Vector2(0, -11), Vector2(4, 4), pin["color"], 1.5)
	for id: int in World.beacons:
		if id == World.me():
			continue
		var b: Array = World.beacons[id]
		if str(b[0]) == World.my_zone:
			P.blob(self, area.position + (b[1] as Vector2) * s, Vector2(5, 5), Net.player_color(id), 2.0)
	if hud != null and hud.world != null:
		var lp: Vector2 = area.position + (hud.world.local.position as Vector2) * s
		P.blob(self, lp, Vector2(6, 6), Net.player_color(World.me()), 2.5)
		draw_arc(lp, 9.0, 0.0, TAU, 16, Color.WHITE, 2.0, true)


## Who's playing and where (only shown when there's someone besides you).
func _draw_players(at: Vector2) -> void:
	var ids: Array = Net.players.keys()
	if ids.size() <= 1:
		return
	ids.sort()
	var ping := ""
	var rtt: Array = World.stats["rtt_ms"]
	if not Net.is_host() and not rtt.is_empty():
		ping = "   %d ms" % roundi(float(rtt[rtt.size() - 1]))
	var r := Rect2(at, Vector2(246.0, 30.0 + 20.0 * ids.size()))
	_card(r)
	_text(at + Vector2(12, 20), "Players %d/%d%s" % [ids.size(), Net.MAX_PLAYERS, ping], 13, P.OUTLINE.lightened(0.15))
	var y := at.y + 42.0
	for id: int in ids:
		draw_circle(Vector2(at.x + 18, y - 5), 6.0, Net.player_color(id))
		draw_arc(Vector2(at.x + 18, y - 5), 6.0, 0.0, TAU, 14, P.OUTLINE, 2.0, true)
		var who := Net.player_name(id) + (" (you)" if id == World.me() else "")
		_text(Vector2(at.x + 32, y), who.left(14), 13)
		if World.beacons.has(id):
			var where := str(Z.zone(str(World.beacons[id][0]))["name"]).trim_prefix("The ")
			_text(Vector2(at.x + 150, y), where, 12, P.OUTLINE.lightened(0.3))
		y += 20.0


# ---------------------------------------------------------------- bottom

## The quickbar: the item wheel in a row. It's as long as your wheel.
func _draw_quickbar(vs: Vector2) -> void:
	var n := World.wheel.size()
	var cell := 46.0
	var gap := 6.0
	var total := cell * n + gap * maxf(n - 1, 0)
	var x0 := (vs.x - total) / 2.0
	var y0 := vs.y - cell - 16.0
	var item := World.held_item()
	var label := "Empty hand" if item == "" else Items.display_name(item)
	if item == "can":
		label += "  %d/%d water" % [Items.count_at(World.wheel, World.selected), Items.CAN_MAX]
	elif item != "" and Items.stackable(item):
		label += "  x%d" % Items.count_at(World.wheel, World.selected)
	var font := ThemeDB.fallback_font
	var lw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var lr := Rect2(Vector2((vs.x - lw) / 2.0 - 12.0, y0 - 40.0), Vector2(lw + 24.0, 28))
	_card(lr)
	_text(lr.position + Vector2(12, 20), label, 16)
	for i in n:
		var sel := i == World.selected
		var rr := Rect2(Vector2(x0 + i * (cell + gap), y0 - (5.0 if sel else 0.0)), Vector2(cell, cell))
		P.shape(self, P.rounded_rect_points(rr, 10.0), Color("bfeadb") if sel else Color(P.CREAM, 0.92), 4.0 if sel else 2.5)
		var id := Items.item_at(World.wheel, i)
		Icons.draw(self, id, rr.get_center(), 0.95)
		if Items.stackable(id):
			Icons.count_badge(self, rr.end + Vector2(3, 3), Items.count_at(World.wheel, i), 11)
		_text(rr.position + Vector2(5, 13), str(i + 1), 11, P.OUTLINE.lightened(0.3))
	if n < Items.WHEEL_MAX:
		_hint(Vector2(x0 + total + 12.0, y0 + cell * 0.5 + 12.0), "+ more in your bag (I)")


func _draw_toasts(vs: Vector2) -> void:
	var y := MARGIN
	var font := ThemeDB.fallback_font
	for k in range(hud.toasts.size() - 1, -1, -1):
		var t: Array = hud.toasts[k]
		var text: String = t[0]
		var a := clampf(float(t[1]) / 0.4, 0.0, 1.0)
		var w: float = minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 460.0)
		var r := Rect2(Vector2((vs.x - w) / 2.0 - 14.0, y), Vector2(w + 28.0, 30))
		P.shape(self, P.rounded_rect_points(r, 12.0), Color(1, 1, 1, 0.94 * a), 3.0)
		draw_string(font, r.position + Vector2(14, 21), text, HORIZONTAL_ALIGNMENT_LEFT, 460.0, 15, Color(P.OUTLINE, a))
		y += 36.0


func _heart(c: Vector2, fill: float) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var t := TAU * k / 24.0
		pts.append(c + Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))) * 0.55)
	draw_colored_polygon(pts, Color(1, 1, 1, 0.85))
	if fill >= 0.99:
		draw_colored_polygon(pts, Color("ff6f86"))
	elif fill > 0.0:
		var half := PackedVector2Array()
		for p in pts:
			half.append(Vector2(minf(p.x, c.x), p.y))
		draw_colored_polygon(half, Color("ff6f86"))
	P.outline(self, pts, P.OUTLINE, 2.5)


## Hearts (2 hp each), stamina orbs, and a line about your light.
func _draw_vitals(at: Vector2) -> void:
	var hp := int(World.vitals.get("hp", 10))
	var max_hp := int(World.vitals.get("max_hp", 10))
	_card(Rect2(at, Vector2(CARD_W, 118)))
	@warning_ignore("integer_division")
	for k in (max_hp + 1) / 2:
		var fill := clampf((hp - k * 2) / 2.0, 0.0, 1.0)
		_heart(at + Vector2(24 + k * 26, 24), fill)
	var wv: Variant = hud.world if hud != null else null
	if wv != null:
		var av: Variant = wv.local
		var orbs: int = av.max_orbs
		var st: float = av.stamina
		for k in orbs:
			var c := at + Vector2(22 + k * 24, 52)
			draw_circle(c, 9.0, Color(1, 1, 1, 0.85))
			var f := clampf(st - k, 0.0, 1.0)
			if f > 0.0:
				draw_circle(c, 9.0 * (0.35 + 0.65 * f), Color("6fd3a0") if f >= 1.0 else Color("a9e9c8"))
			draw_arc(c, 9.0, 0.0, TAU, 18, P.OUTLINE, 2.0, true)
	var sh: Dictionary = World.vitals.get("shield", {})
	if not sh.is_empty():
		_draw_shield_bar(at + Vector2(14, 80), sh)
		if Z.is_dark(World.my_zone, World.clock) and World.my_lights() == 0:
			_text(at + Vector2(14, 106), "It's dark! A shield gives no light (I to swap).", 12, Color("c0392b"))
		return
	var line := _light_status()
	_wrapped(at + Vector2(14, 82), line[0], CARD_W - 28.0, 13, line[1], 2)


## The worn shield's health, or how long until a broken one can block again.
func _draw_shield_bar(at: Vector2, sh: Dictionary) -> void:
	var name_text := Items.display_name(str(sh["id"]))
	_text(at + Vector2(0, 4), name_text, 13)
	var bar := Rect2(at + Vector2(96, -8), Vector2(CARD_W - 28.0 - 96.0, 14))
	P.shape(self, P.rounded_rect_points(bar, 6.0), Color(1, 1, 1, 0.85), 2.0)
	var broken := float(sh.get("broken", 0.0))
	var frac := clampf(float(sh["hp"]) / maxf(float(sh["max"]), 0.1), 0.0, 1.0)
	if frac > 0.01:
		var fill := Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4.0) * frac, bar.size.y - 4.0))
		draw_rect(fill, Color("8fb7e0") if frac > 0.3 else Color("e0a08f"))
	if broken > 0.0:
		_text(bar.position + Vector2(8, 12), "Broken! %ds" % ceili(broken), 12, Color("c0392b"))
	else:
		_text(bar.position + Vector2(8, 12), "%d / %d" % [floori(float(sh["hp"])), int(sh["max"])], 11, P.OUTLINE)


## What your light situation is, in words, and how worried to be about it.
func _light_status() -> Array:
	var off := str(World.equip.get("offhand", ""))
	var bits := World.my_lights()
	var zd := Z.zone(World.my_zone)
	var dark := Z.is_dark(World.my_zone, World.clock)
	var wet: bool = bool(zd["outdoor"]) and World.weather.get(World.my_zone, "") in Z.WET_WEATHER
	var warn := Color("c0392b")
	match off:
		"torch":
			if bits & 1 == 0:
				return ["Torch out. Relight it at a campfire, brazier or lamp (E).", warn]
			if wet and not "raincoat" in Items.equipped(World.equip):
				return ["Rain! Your torch is sputtering. Find cover or wear a raincoat.", warn]
			return ["Torch lit. Right-click to jab (burns enemies, melts ice).", P.OUTLINE]
		"lantern":
			var fuel := float(World.vitals.get("fuel", 0.0))
			var oil := World.count_mine("oil")
			if bits & 2 == 0:
				return ["Lantern off (right-click)%s. Oil: %d." % [" and empty" if fuel <= 0.0 else "", oil], warn if dark else P.OUTLINE]
			return ["Lantern %d%%  ·  spare oil %d" % [int(fuel), oil], warn if fuel < 20.0 else P.OUTLINE]
		"pot_lid":
			if dark and bits == 0:
				return ["It's dark and you're holding a lid! Equip a light (I).", warn]
			return ["Pot Lid: hold right-click to block.", P.OUTLINE]
	if bits & 4 != 0:
		return ["Headlamp on.", P.OUTLINE]
	if dark and bits == 0:
		return ["It's dark! Put a torch or lantern in your offhand (I).", warn]
	return ["No light equipped.", P.OUTLINE]
