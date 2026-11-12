extends RefCounted
## Hitboxes and hurtboxes: the one place that decides what touches what in a fight.
##
## Everything is measured on the ground plane, because the camera looks down at a 3/4
## angle and characters stand on their feet: a body's *hurtbox* is a circle around its
## feet, the same size as its shadow. An attack's *hitbox* is a shape on the ground:
##
##   circle  a round area                          (spore burst, thrown berry splash, bump)
##   sector  a slice of a ring in front of someone  (sickle swing, torch jab, kick, bear slam)
##   lane    a straight strip with round ends       (boar charge path)
##
## A hit lands when the hitbox *overlaps* the hurtbox anywhere, not just when the target's
## centre is inside it, so big animals are easier to hit than small ones, the way they look.
## The host uses these functions to judge players' attacks, and each player's game uses
## them to judge enemy attacks on themselves (the host then checks the claim). The same
## numbers drive the debug view (F3), so what you see is what is tested.

const Z = preload("res://game/data/zones.gd")
const E = preload("res://game/data/enemies.gd")

# ---------------------------------------------------------------- hurtboxes

## A player's body for collisions with the world and other bodies.
const PLAYER_BODY := 14.0
## A player's body for enemy attacks. A little smaller than the body, so an attack that
## only grazes your shoulder on screen doesn't count: dodges feel fair.
const PLAYER_HURT := 11.0


## The hurtbox of an enemy of this kind standing at `pos`.
static func enemy_hurtbox(kind: String, pos: Vector2) -> Dictionary:
	return circle(pos, float(E.info(kind)["radius"]))


static func player_hurtbox(pos: Vector2) -> Dictionary:
	return circle(pos, PLAYER_HURT)


# ---------------------------------------------------------------- player attacks

## Sickle: a wide swing in front of you, matching the white arc drawn when you swing.
const SICKLE_RANGE := 72.0
const SICKLE_HALF_ANGLE := 1.3      # radians each side of where you face (about 75 degrees)
## Torch jab: a narrower, longer poke.
const JAB_RANGE := 92.0
const JAB_HALF_ANGLE := 0.75
## Steel-toed kick: a short wedge in front while sprinting.
const KICK_RANGE := 34.0
const KICK_HALF_ANGLE := 1.0
## A thrown berry or radish bursts in a circle where it lands.
const SPLASH_RADIUS := 60.0


static func sickle(pos: Vector2, facing: Vector2) -> Dictionary:
	return sector(pos, facing, SICKLE_RANGE, SICKLE_HALF_ANGLE)


static func jab(pos: Vector2, facing: Vector2) -> Dictionary:
	return sector(pos, facing, JAB_RANGE, JAB_HALF_ANGLE)


## The kick reaches out from the edge of your body, not its centre.
static func kick(pos: Vector2, facing: Vector2) -> Dictionary:
	return sector(pos, facing, PLAYER_BODY + KICK_RANGE, KICK_HALF_ANGLE)


static func splash(at: Vector2) -> Dictionary:
	return circle(at, SPLASH_RADIUS)


# ---------------------------------------------------------------- enemy attacks

## The hitbox of a telegraphed attack at the moment it lands. `tg` is the telegraph the
## host announced; `progress` is for charges: how far along the lane the boar has got.
static func telegraph(tg: Dictionary, progress: float = 0.0) -> Dictionary:
	var origin: Vector2 = tg["origin"]
	var dir: Vector2 = tg["dir"]
	match str(tg["kind"]):
		"burst":
			return circle(origin, float(tg["radius"]))
		"slam":
			return sector(origin, dir, float(tg["length"]), float(tg["half"]))
		"charge":
			# The boar's own body, wherever it has got to along its lane.
			var travelled := clampf(progress, 0.0, float(tg["length"]))
			return circle(origin + dir * travelled, float(tg["radius"]))
	return circle(origin, 0.0)


## The whole lane a charge will sweep (drawn as the telegraph).
static func charge_lane(tg: Dictionary) -> Dictionary:
	return lane(tg["origin"], tg["dir"], float(tg["length"]), float(tg["width"]) / 2.0)


# ---------------------------------------------------------------- shapes

static func circle(center: Vector2, radius: float) -> Dictionary:
	return {"type": "circle", "c": center, "r": radius}


## A slice of a ring: everything within `reach` of `center` and within `half_angle` of
## `dir`. Points closer than `inner` don't count (0 = solid slice).
static func sector(center: Vector2, dir: Vector2, reach: float, half_angle: float, inner: float = 0.0) -> Dictionary:
	var d := dir.normalized() if dir.length() > 0.001 else Vector2.DOWN
	return {"type": "sector", "c": center, "dir": d, "r": reach, "half": half_angle, "inner": inner}


## A strip from `start` along `dir` for `length`, `half_width` either side, round ends.
static func lane(start: Vector2, dir: Vector2, length: float, half_width: float) -> Dictionary:
	var d := dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	return {"type": "lane", "a": start, "b": start + d * length, "r": half_width}


# ---------------------------------------------------------------- tests

## True if a hitbox overlaps a hurtbox (a circle).
static func hits(hitbox: Dictionary, hurtbox: Dictionary) -> bool:
	return distance(hitbox, hurtbox["c"]) <= float(hurtbox["r"])


## How far a point is from a shape (0 if inside).
static func distance(shape: Dictionary, p: Vector2) -> float:
	match str(shape["type"]):
		"circle":
			return maxf((p - (shape["c"] as Vector2)).length() - float(shape["r"]), 0.0)
		"lane":
			return maxf(_segment_distance(p, shape["a"], shape["b"]) - float(shape["r"]), 0.0)
		"sector":
			return _sector_distance(shape, p)
	return INF


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.0001 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Distance from a point to a ring slice: if the point is within the slice's angle, it's
## the distance to the ring band; otherwise it's the distance to the nearer straight edge.
static func _sector_distance(s: Dictionary, p: Vector2) -> float:
	var c: Vector2 = s["c"]
	var reach: float = s["r"]
	var inner: float = s["inner"]
	var half: float = s["half"]
	var to := p - c
	var d := to.length()
	if d < 0.0001:
		return 0.0 if inner <= 0.0 else inner
	var dir: Vector2 = s["dir"]
	if absf(dir.angle_to(to)) <= half:
		if d > reach:
			return d - reach
		if d < inner:
			return inner - d
		return 0.0
	var best := INF
	for side: float in [-1.0, 1.0]:
		var edge := dir.rotated(half * side)
		best = minf(best, _segment_distance(p, c + edge * inner, c + edge * reach))
	return best


# ---------------------------------------------------------------- drawing (debug view)

## Outline of a shape, for the F3 debug view.
static func outline_points(shape: Dictionary, steps: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match str(shape["type"]):
		"circle":
			for k in steps + 1:
				pts.append((shape["c"] as Vector2) + Vector2.from_angle(TAU * k / steps) * float(shape["r"]))
		"sector":
			var c: Vector2 = shape["c"]
			var base: float = (shape["dir"] as Vector2).angle()
			var half: float = shape["half"]
			var inner: float = shape["inner"]
			for k in steps + 1:
				pts.append(c + Vector2.from_angle(base - half + 2.0 * half * k / steps) * float(shape["r"]))
			if inner <= 0.0:
				pts.append(c)
			else:
				for k in range(steps, -1, -1):
					pts.append(c + Vector2.from_angle(base - half + 2.0 * half * k / steps) * inner)
			pts.append(pts[0])
		"lane":
			var a: Vector2 = shape["a"]
			var b: Vector2 = shape["b"]
			var r: float = shape["r"]
			var d := (b - a).normalized() if (b - a).length() > 0.001 else Vector2.RIGHT
			var ang := d.angle()
			var hs := int(steps * 0.5)
			for k in hs + 1:
				pts.append(b + Vector2.from_angle(ang - PI / 2.0 + PI * k / hs) * r)
			for k in hs + 1:
				pts.append(a + Vector2.from_angle(ang + PI / 2.0 + PI * k / hs) * r)
			pts.append(pts[0])
	return pts
