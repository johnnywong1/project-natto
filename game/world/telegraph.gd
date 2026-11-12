extends Node2D
## A warning drawn on the ground before an enemy attack lands: a line for a charge, a
## circle for a burst, a wedge for a slam. It fills up as the wind-up runs out, so the
## moment it's full is the moment it hits. Lives on a layer the darkness doesn't touch, so
## you can always read an attack even at night.

var tg: Dictionary = {}
var windup := 1.0
var active := 0.3
var _t := 0.0


func setup(data: Dictionary, lead: float) -> void:
	tg = data
	windup = maxf(float(data["windup"]) - lead, 0.05)
	match str(data["kind"]):
		"charge":
			active = float(data["length"]) / maxf(float(data["speed"]), 1.0) + 0.1
		_:
			active = 0.25


func _process(delta: float) -> void:
	_t += delta
	if _t > windup + active + 0.25:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var origin: Vector2 = tg["origin"]
	var d: Vector2 = tg["dir"]
	var fill := clampf(_t / windup, 0.0, 1.0)
	var fading := clampf(1.0 - (_t - windup) / (active + 0.25), 0.0, 1.0) if _t > windup else 1.0
	var edge := Color(1.0, 0.35, 0.25, 0.95 * fading)
	var inside := Color(1.0, 0.45, 0.25, 0.22 * fading)
	var full := Color(1.0, 0.3, 0.2, 0.45 * fading)
	match str(tg["kind"]):
		"charge":
			var length: float = tg["length"]
			var w: float = float(tg["width"]) / 2.0
			var side := Vector2(-d.y, d.x)
			var box := PackedVector2Array([origin + side * w, origin + d * length + side * w, origin + d * length - side * w, origin - side * w])
			draw_colored_polygon(box, inside)
			var f := length * fill
			draw_colored_polygon(PackedVector2Array([origin + side * w, origin + d * f + side * w, origin + d * f - side * w, origin - side * w]), full)
			box.append(box[0])
			draw_polyline(box, edge, 4.0, true)
			for k in 4:
				var tip := origin + d * (length * (0.25 + k * 0.22))
				draw_polyline(PackedVector2Array([tip - d * 14.0 + side * 16.0, tip, tip - d * 14.0 - side * 16.0]), edge, 4.0, true)
		"burst":
			var r: float = tg["radius"]
			draw_circle(origin, r, inside)
			draw_circle(origin, r * fill, full)
			draw_arc(origin, r, 0.0, TAU, 48, edge, 4.0, true)
		"slam":
			var length: float = tg["length"]
			var half: float = tg["half"]
			var base := d.angle()
			var wedge := PackedVector2Array([origin])
			var inner := PackedVector2Array([origin])
			for k in 17:
				var a := base - half + 2.0 * half * k / 16.0
				wedge.append(origin + Vector2.from_angle(a) * length)
				inner.append(origin + Vector2.from_angle(a) * length * fill)
			draw_colored_polygon(wedge, inside)
			if fill > 0.02:
				draw_colored_polygon(inner, full)
			wedge.append(origin)
			draw_polyline(wedge, edge, 4.0, true)
