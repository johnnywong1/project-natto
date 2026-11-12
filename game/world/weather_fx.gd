extends Node2D
## Screen-space weather for the zone you're in: rain and drizzle streaks, drifting mist,
## cloud shadows, cave drips and floating spores. Lives on its own CanvasLayer so the
## day/night tint doesn't wash it out.

var zone := "middlemost"
var _drops: Array = []     # [pos, speed]
var _blobs: Array = []     # [pos, radius, speed]
var _t := 0.0
var _kind := ""
var _rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	_t += delta
	var view := get_viewport_rect().size
	var kind: String = World.weather.get(zone, "clear")
	if kind != _kind:
		_kind = kind
		_reset(view)
	match _kind:
		"rain", "drizzle":
			var fall := 900.0 if _kind == "rain" else 520.0
			for d: Array in _drops:
				var p: Vector2 = d[0]
				p += Vector2(-0.25, 1.0) * fall * float(d[1]) * delta
				if p.y > view.y + 20.0:
					p = Vector2(_rng.randf_range(0, view.x + 200.0), -20.0)
				d[0] = p
		"drip":
			for d: Array in _drops:
				var p: Vector2 = d[0]
				p.y += 700.0 * float(d[1]) * delta
				if p.y > float(d[2]):
					p = Vector2(_rng.randf_range(0, view.x), -10.0)
					d[2] = _rng.randf_range(view.y * 0.3, view.y)
				d[0] = p
		"spores":
			for d: Array in _drops:
				var p: Vector2 = d[0]
				p += Vector2(sin(_t + float(d[1]) * 6.0) * 12.0, -18.0 * float(d[1])) * delta
				if p.y < -10.0:
					p = Vector2(_rng.randf_range(0, view.x), view.y + 10.0)
				d[0] = p
	for b: Array in _blobs:
		var p: Vector2 = b[0]
		p.x += float(b[2]) * delta
		if p.x - float(b[1]) > view.x:
			p.x = -float(b[1])
		b[0] = p
	queue_redraw()


func _reset(view: Vector2) -> void:
	_drops.clear()
	_blobs.clear()
	var n := 0
	match _kind:
		"rain":
			n = 160
		"drizzle":
			n = 70
		"drip":
			n = 14
		"spores":
			n = 60
	for i in n:
		_drops.append([Vector2(_rng.randf_range(0, view.x + 200.0), _rng.randf_range(0, view.y)), _rng.randf_range(0.7, 1.3), _rng.randf_range(view.y * 0.3, view.y)])
	if _kind == "mist" or _kind == "cloudy":
		for i in 7:
			_blobs.append([Vector2(_rng.randf_range(0, view.x), _rng.randf_range(0, view.y)), _rng.randf_range(160, 320), _rng.randf_range(10, 28)])


func _draw() -> void:
	var view := get_viewport_rect().size
	match _kind:
		"rain", "drizzle":
			var streak := 22.0 if _kind == "rain" else 12.0
			var col := Color(0.75, 0.88, 1.0, 0.55 if _kind == "rain" else 0.4)
			for d: Array in _drops:
				var p: Vector2 = d[0]
				draw_line(p, p + Vector2(-0.25, 1.0) * streak, col, 2.0, true)
			if _kind == "rain":
				draw_rect(Rect2(Vector2.ZERO, view), Color(0.4, 0.5, 0.7, 0.08))
		"mist":
			draw_rect(Rect2(Vector2.ZERO, view), Color(1, 1, 1, 0.12))
			for b: Array in _blobs:
				var r: float = b[1]
				draw_circle(b[0], r, Color(1, 1, 1, 0.10))
				draw_circle(b[0], r * 0.6, Color(1, 1, 1, 0.08))
		"cloudy":
			for b: Array in _blobs:
				draw_circle(b[0], float(b[1]), Color(0.2, 0.25, 0.35, 0.07))
		"drip":
			for d: Array in _drops:
				var p: Vector2 = d[0]
				draw_line(p, p + Vector2(0, 10), Color(0.8, 0.95, 1.0, 0.7), 3.0, true)
		"spores":
			for d: Array in _drops:
				draw_circle(d[0], 2.0 + float(d[1]) * 1.5, Color(0.7, 1.0, 0.9, 0.55))
