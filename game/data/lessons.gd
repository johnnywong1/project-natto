extends RefCounted
## Pepper's lessons: the tutorial. Pepper stands by the notice board in Middlemost. Talk to
## her (E) and she teaches one thing at a time; each lesson has a few tasks that tick off as
## you do them, shown in the lesson card under the clock. When every task is done, the next
## lesson starts. Talk to her again any time to hear the current lesson again.
##
## Every player has their own progress (saved with the world). The host counts what each
## player does (see World.lesson_event) and checks the tasks with `progress()` below.
##
## A task is one of:
##   {"text": ..., "event": "plant", "need": 2}     do something this many times
##   {"text": ..., "check": "wheel:can"}            have something in your wheel
##   {"text": ..., "check": "equip:pot_helmet"}     be wearing something
##   {"text": ..., "check": "chest:fern_chest"}     have opened a chest

const NPC_ID := "pepper"
const NPC_NAME := "Pepper"

const LESSONS := [
	{"id": "hello", "title": "Say hello to Pepper",
		"talk": ["Oh! A new face. I'm Pepper. I help newcomers find their feet in Middlemost.",
			"Walk with WASD or the left stick. Press E to talk to people and to use things in front of you.",
			"I'll teach you the basics, one lesson at a time. Your current lesson shows under the clock."],
		"tasks": [{"text": "Talk to Pepper (E)", "event": "talk", "need": 1}],
		"reward": []},
	{"id": "wheel", "title": "Fill your item wheel",
		"talk": ["Your item wheel is what you hold in your hand. Right now it's only your sickle.",
			"Press I to open your bag. Right-click the Watering Can, then the Popberry Seeds, to add them to your wheel.",
			"Then hold Q and point at what you want to hold. The number keys work too."],
		"tasks": [{"text": "Put the Watering Can in your wheel", "check": "wheel:can"},
			{"text": "Put the Popberry Seeds in your wheel", "check": "wheel:popberry_seed"}],
		"reward": []},
	{"id": "farm", "title": "Grow a popberry",
		"talk": ["The farm plots are just north-west of here. Hold the seeds, face a plot and click to plant.",
			"Hold the watering can and click the plot. A seed needs water at every stage to grow, so water it twice.",
			"When it's ripe, press E (or swing your sickle) to pick it. Popberries are for throwing at Wilts!"],
		"tasks": [{"text": "Plant a seed", "event": "plant", "need": 1},
			{"text": "Water your crops", "event": "water", "need": 2},
			{"text": "Harvest something ripe", "event": "harvest", "need": 1}],
		"reward": [["radish_seed", 2]]},
	{"id": "move", "title": "Quick feet",
		"talk": ["Press Space to dash. It's quick, but it doesn't make you invincible: dash OUT of danger, not through it.",
			"Hold Shift to sprint. Dashing, sprinting, blocking and swinging all use the green stamina orbs under your hearts.",
			"Orbs fill back up when you stop for a moment."],
		"tasks": [{"text": "Dash (Space)", "event": "dash", "need": 3},
			{"text": "Sprint (hold Shift) for 2 seconds", "event": "sprint", "need": 2}],
		"reward": []},
	{"id": "gear", "title": "Dress for adventure",
		"talk": ["You can wear a helmet, a top, shoes, something in your offhand and three trinkets.",
			"Open your bag (I) and right-click the Saucepan Helmet to put it on. It softens every hit.",
			"Some pieces belong to sets. Wear a whole set for a bonus."],
		"tasks": [{"text": "Wear the Saucepan Helmet", "check": "equip:pot_helmet"}],
		"reward": [["oil", 1]]},
	{"id": "light", "title": "Light in the dark",
		"talk": ["Nights here are really dark, and Mossmouth is dark all day. Your torch lights the way.",
			"Right-click to jab with it: it sets enemies alight and melts ice. Rain puts it out, though.",
			"If it goes out, press E next to a campfire, a brazier or a street lamp to relight it. A lantern doesn't mind rain, but it burns oil."],
		"tasks": [{"text": "Jab with your lit torch (right-click)", "event": "jab", "need": 1}],
		"reward": []},
	{"id": "fight", "title": "Shoo a Wilt",
		"talk": ["Wilts creep in and nibble the crops. Swing your sickle (click) at one. The swing hits everything in the white arc.",
			"Bigger animals warn you first: a red shape on the ground fills up, then they strike. Get out of it before it fills!",
			"Hold right-click with a Pot Lid in your offhand to block hits from the front."],
		"tasks": [{"text": "Defeat an enemy", "event": "defeat", "need": 1}],
		"reward": [["popberry", 4]]},
	{"id": "map", "title": "Never get lost",
		"talk": ["Press M for the map. You can see your friends on it wherever they are.",
			"Press P to drop a pin where you're pointing, so friends know where to meet you."],
		"tasks": [{"text": "Drop a pin (P)", "event": "pin", "need": 1}],
		"reward": []},
	{"id": "explore", "title": "Up the pulley lift",
		"talk": ["Head east to The Fernery. Up on the Canopy Ledge there's an old chest, but there's a cliff in the way.",
			"Stand on the pulley lift's platform and press E. Everyone standing on it rides together.",
			"If the platform is at the other end, press E next to the empty end to call it over."],
		"tasks": [{"text": "Ride a pulley lift", "event": "lift", "need": 1},
			{"text": "Open the chest on the Canopy Ledge", "check": "chest:fern_chest"}],
		"reward": [["oil", 2]]},
]

const DONE_TALK := ["You've learned everything I know! Mossmouth, south of the village, is dark and full of ice. Bring a light.",
	"Come back any time. I'm always by the notice board."]


static func count() -> int:
	return LESSONS.size()


## A fresh player's progress record (kept on the host, saved with the world).
static func new_progress() -> Dictionary:
	return {"i": 0, "counts": {}}


## Where each task of the current lesson stands: [[text, have, need], ...].
## `p` is the player's progress record, `a` the host's record of the player.
static func progress(p: Dictionary, a: Dictionary) -> Array:
	var i: int = p["i"]
	if i >= LESSONS.size():
		return []
	var out: Array = []
	var counts: Dictionary = p["counts"]
	for t: Dictionary in LESSONS[i]["tasks"]:
		if t.has("event"):
			var need := int(t["need"])
			out.append([t["text"], mini(int(floor(float(counts.get(t["event"], 0.0)))), need), need])
		else:
			out.append([t["text"], 1 if _check(str(t["check"]), a) else 0, 1])
	return out


static func is_done(p: Dictionary, a: Dictionary) -> bool:
	if int(p["i"]) >= LESSONS.size():
		return false
	for t: Array in progress(p, a):
		if int(t[1]) < int(t[2]):
			return false
	return true


static func _check(what: String, a: Dictionary) -> bool:
	var parts := what.split(":")
	match parts[0]:
		"wheel":
			for slot: Array in a["wheel"]:
				if slot.size() == 2 and slot[0] == parts[1]:
					return true
			return false
		"equip":
			for s: String in a["equip"]:
				if str(a["equip"][s]) == parts[1]:
					return true
			return false
		"chest":
			return parts[1] in (a["chests"] as Array)
	return false


## What the lesson card shows a player (sent to them with their vitals).
static func summary(p: Dictionary, a: Dictionary) -> Dictionary:
	var i: int = p["i"]
	if i >= LESSONS.size():
		return {"i": i, "n": LESSONS.size(), "title": "", "tasks": []}
	return {"i": i, "n": LESSONS.size(), "title": LESSONS[i]["title"], "tasks": progress(p, a)}
