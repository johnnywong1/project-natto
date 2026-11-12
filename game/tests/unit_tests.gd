extends SceneTree
## Fast checks of the pure game rules, no network or window needed:
##   godot --headless --path . -s res://game/tests/unit_tests.gd
## Covers hitbox geometry, the item wheel's add/remove/use rules, shields, lessons and zone
## collisions. Prints PASS/FAIL per check and exits with code 1 if anything failed.

const HB = preload("res://game/combat/hitboxes.gd")
const Items = preload("res://game/data/items.gd")
const Lessons = preload("res://game/data/lessons.gd")
const Z = preload("res://game/data/zones.gd")

var _failed := 0
var _passed := 0


func _init() -> void:
	_hitboxes()
	_wheel()
	_shields()
	_lessons()
	_zones()
	_stages()
	print("\n%d/%d unit checks passed" % [_passed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print(("PASS  " if ok else "FAIL  ") + name + (("   [" + detail + "]") if detail != "" else ""))


## The stage files (game/data/zones/*.json) load, validate, and round-trip.
func _stages() -> void:
	check("the three outdoor stages loaded from their files", Z.OUTDOOR == ["middlemost", "fernery", "mossmouth"], str(Z.OUTDOOR))
	check("the houses loaded from houses.json", Z.HOUSES.size() == 4 and Z.ORDER.size() == 7)
	for id: String in Z.OUTDOOR:
		var problems := Z.validate(Z.zone(id))
		check("stage %s passes validation" % id, problems.is_empty(), ", ".join(problems))
	var md := Z.zone("middlemost")
	check("positions became Vector2 and rectangles Rect2", md["spawn"] is Vector2 and md["exits"][0]["rect"] is Rect2 and md["walls"][0] is Rect2)
	check("colours became Color", md["ground"] is Color and md["paths"][0]["color"] is Color)
	check("whole numbers became int (so cols/rows/seed work)", md["seed"] is int and md["farm"]["cols"] is int)
	check("the template is ignored as a stage", not Z.exists("my_meadow"))
	var tpl: Variant = Z.read_file(Z.ZONE_DIR + "/_template.json")
	check("the template itself is a valid stage", tpl is Dictionary and Z.validate(tpl).is_empty(), ", ".join(Z.validate(tpl)) if tpl is Dictionary else "unreadable")
	var back: Variant = Z.from_json(JSON.parse_string(JSON.stringify(Z.to_json(md))))
	check("a stage survives a to_json/from_json round trip", back is Dictionary and back["spawn"] == md["spawn"] and back["walls"] == md["walls"] and back["seed"] == md["seed"])
	var broken: Dictionary = md.duplicate(true)
	broken.erase("spawn")
	check("validation reports a missing field", "missing \"spawn\"" in Z.validate(broken))


func _hitboxes() -> void:
	var swing := HB.sickle(Vector2.ZERO, Vector2.RIGHT)
	check("sickle hits a body straight ahead, inside reach", HB.hits(swing, HB.circle(Vector2(50, 0), 10)))
	check("sickle reaches a body whose centre is past reach but whose edge isn't", HB.hits(swing, HB.circle(Vector2(HB.SICKLE_RANGE + 15, 0), 20)))
	check("sickle misses a body just past reach", not HB.hits(swing, HB.circle(Vector2(HB.SICKLE_RANGE + 25, 0), 20)))
	check("sickle misses right behind you", not HB.hits(swing, HB.circle(Vector2(-40, 0), 15)))
	check("sickle catches a body overlapping the edge of the arc",
		HB.hits(swing, HB.circle(Vector2.from_angle(HB.SICKLE_HALF_ANGLE + 0.3) * 50.0, 20)))
	var burst := HB.telegraph({"kind": "burst", "origin": Vector2.ZERO, "dir": Vector2.RIGHT, "radius": 140.0})
	check("burst: standing at its edge counts", HB.hits(burst, HB.player_hurtbox(Vector2(140 + HB.PLAYER_HURT - 1, 0))))
	check("burst: just outside is safe", not HB.hits(burst, HB.player_hurtbox(Vector2(140 + HB.PLAYER_HURT + 1, 0))))
	var slam := HB.telegraph({"kind": "slam", "origin": Vector2.ZERO, "dir": Vector2.DOWN, "length": 220.0, "half": 0.9})
	check("slam wedge hits in front", HB.hits(slam, HB.player_hurtbox(Vector2(0, 150))))
	check("slam wedge misses behind the bear", not HB.hits(slam, HB.player_hurtbox(Vector2(0, -60))))
	var tg := {"kind": "charge", "origin": Vector2.ZERO, "dir": Vector2.RIGHT, "length": 400.0, "radius": 30.0}
	check("charge: the boar's body hits you once it reaches you", HB.hits(HB.telegraph(tg, 200.0), HB.player_hurtbox(Vector2(210, 20))))
	check("charge: not before it gets there", not HB.hits(HB.telegraph(tg, 50.0), HB.player_hurtbox(Vector2(210, 20))))
	var lane := HB.charge_lane({"origin": Vector2.ZERO, "dir": Vector2.RIGHT, "length": 400.0, "width": 60.0})
	check("lane distance at the round end", is_equal_approx(HB.distance(lane, Vector2(430, 0)), 0.0))
	check("outline points close the shape", HB.outline_points(swing)[0] == HB.outline_points(swing)[-1])


func _wheel() -> void:
	var bag := Items.starter_kit()
	var wheel := Items.starter_wheel()
	check("new players hold just the sickle", wheel.size() == 1 and wheel[0][0] == "sickle")
	var can_slot := Items.find(bag, "can")
	check("adding the can grows the wheel", Items.wheel_add(wheel, bag, can_slot) == "" and wheel.size() == 2 and Items.find(bag, "can") < 0)
	var boots := Items.find(bag, "hermes_boots")
	check("gear can't go in the wheel", Items.wheel_add(wheel, bag, boots) != "" and wheel.size() == 2)
	Items.wheel_add(wheel, bag, Items.find(bag, "popberry"))
	var n := Items.count_of(wheel, "popberry")
	check("harvested berries land on the wheel stack", Items.give(bag, wheel, "popberry", 2) and Items.count_of(wheel, "popberry") == n + 2)
	var at := Items.find(wheel, "popberry")
	for k in Items.count_of(wheel, "popberry"):
		Items.wheel_take_one(wheel, at)
	check("using the last one takes it out of the wheel", Items.find(wheel, "popberry") < 0 and wheel.size() == 2)
	check("putting something back shrinks the wheel", Items.wheel_remove(wheel, bag, 1) == "" and wheel.size() == 1 and Items.find(bag, "can") >= 0)
	var full := []
	for k in Items.WHEEL_MAX:
		full.append(["sickle", 1])
	var bag2 := Items.starter_kit()
	check("a full wheel says so", Items.wheel_add(full, bag2, Items.find(bag2, "can")) != "")


func _shields() -> void:
	for id in ["pot_lid", "buckler", "tower_shield", "spike_shield"]:
		var sh := Items.shield(id)
		check("%s: Perfect window is smaller than Great, effectiveness goes down by tier" % id,
			float(sh["perfect"]) < float(sh["great"]) and float(sh["eff"][0]) >= float(sh["eff"][1]) and float(sh["eff"][1]) >= float(sh["eff"][2]))
	check("the Tower Shield covers more than the Buckler", float(Items.shield("tower_shield")["arc"]) > float(Items.shield("buckler")["arc"]))
	check("the Buckler is faster to move with", float(Items.shield("buckler")["move"]) > float(Items.shield("tower_shield")["move"]))
	check("only the Spike Shield has spikes", int(Items.shield("spike_shield")["spikes"]) > 0 and int(Items.shield("pot_lid")["spikes"]) == 0)
	check("a torch isn't a shield", Items.shield("torch").is_empty())


func _lessons() -> void:
	var p := Lessons.new_progress()
	var a := {"wheel": Items.starter_wheel(), "equip": Items.starter_equip(), "chests": []}
	check("lesson 1 waits for a hello", not Lessons.is_done(p, a))
	p["counts"]["talk"] = 1.0
	check("saying hello finishes lesson 1", Lessons.is_done(p, a))
	p["i"] = 1
	p["counts"] = {}
	a["wheel"].append(["can", 10])
	check("the wheel lesson needs the seeds too", not Lessons.is_done(p, a))
	a["wheel"].append(["popberry_seed", 12])
	check("the wheel lesson finishes when both are in", Lessons.is_done(p, a))
	check("every lesson has a title, a speech and tasks", Lessons.LESSONS.all(func(l: Dictionary) -> bool:
		return str(l["title"]) != "" and not (l["talk"] as Array).is_empty() and not (l["tasks"] as Array).is_empty()))


func _zones() -> void:
	check("houses are solid", Z.blocked("middlemost", Vector2(300, 300), 14.0, []))
	check("a house doorstep is open", not Z.blocked("middlemost", Vector2(300, 360), 14.0, []))
	check("every house has a room", Z.HOUSES.keys().all(func(h: String) -> bool: return Z.exists(h) and Z.is_interior(h)))
	check("indoors is never dark", not Z.is_dark("house_pepper", 0.0))
	check("Mossmouth is always dark", Z.is_dark("mossmouth", 12.0 * 60.0))
	check("someone indoors shows on the village map at the door", Z.map_zone("house_clock") == "middlemost"
		and Z.map_pos("house_clock", Vector2(400, 400)) == Z.HOUSES["house_clock"]["door"])
	var p := Vector2(2300, 14)
	for k in 60:
		p = Z.resolve("fernery", p + Vector2(-12, 0), 14.0, [])
	check("walking along the top edge stops at the ledge's cliff", p.x >= 2200.0, str(p))
