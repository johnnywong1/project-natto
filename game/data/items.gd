extends RefCounted
## Items, equipment, sets and crops, shared by every peer. Pure data and small helpers.
##
## Each player has three places to keep things:
##   * the **bag**: SLOTS slots for everything. A slot is [] (empty) or [item_id, count].
##   * the **item wheel**: the things you hold in your main hand (sickle, can, seeds,
##     berries to throw, lamp oil). It's a separate list you fill from the bag: it starts
##     with just the sickle and grows one segment per item you add, up to WHEEL_MAX. Hold Q
##     to pick from it. A stack that runs out (last seed planted) leaves the wheel.
##   * **equipment**: helmet, chest, shoes, offhand and three trinkets. The offhand holds a
##     light (torch or lantern) or a Pot Lid for blocking, so you choose between seeing and
##     guarding.
## The host owns all three for every player; these helpers are what it uses to change them.

const SLOTS := 32
const WHEEL_MAX := 8
const CAN_MAX := 10
const FUEL_MAX := 100.0
const EQUIP_SLOTS: Array[String] = ["helmet", "chest", "shoes", "offhand", "trinket1", "trinket2", "trinket3"]
const SLOT_NAMES := {"helmet": "Helmet", "chest": "Chest", "shoes": "Shoes", "offhand": "Offhand",
	"trinket1": "Trinket", "trinket2": "Trinket", "trinket3": "Trinket"}
## Kinds of item you hold in your main hand, so they can go in the wheel.
const WHEEL_KINDS: Array[String] = ["sickle", "can", "seed", "throw", "oil"]

const ITEMS := {
	# Main hand (item wheel)
	"sickle": {"name": "Sickle", "kind": "sickle", "color": Color("d3dae0")},
	"can": {"name": "Watering Can", "kind": "can", "color": Color("8fd3ff")},
	"popberry_seed": {"name": "Popberry Seeds", "kind": "seed", "crop": "popberry", "color": Color("ff8fb1")},
	"radish_seed": {"name": "Thunder Radish Seeds", "kind": "seed", "crop": "radish", "color": Color("b9a6ff")},
	"popberry": {"name": "Popberry", "kind": "throw", "damage": 2, "color": Color("ff8fb1")},
	"radish": {"name": "Thunder Radish", "kind": "throw", "damage": 3, "color": Color("b9a6ff")},
	"oil": {"name": "Lamp Oil", "kind": "oil", "color": Color("e8c15a"),
		"desc": "Refills a lantern. Used automatically when the lantern runs dry."},
	"fern": {"name": "Fern Frond", "kind": "material", "color": Color("86d47e")},
	"glowcap": {"name": "Glowcap", "kind": "material", "color": Color("9ff0e0")},
	"lumber": {"name": "Lumber", "kind": "material", "color": Color("b07f4a"),
		"desc": "Chopped from a tree with your sickle. A building material."},
	# Offhand
	"torch": {"name": "Torch", "kind": "equip", "slot": "offhand", "light": "torch", "color": Color("ff9f4a"),
		"desc": "A small circle of warm light. Right-click to jab: sets enemies alight and melts ice. Rain puts it out; relight at any fire. Never needs refilling."},
	"lantern": {"name": "Lantern", "kind": "equip", "slot": "offhand", "light": "lantern", "color": Color("ffe08a"),
		"desc": "A wider, steady light that rain can't touch. Burns lamp oil. Right-click to turn it on or off."},
	# Shields (offhand). Hold right-click to block; see SHIELDS below for what each one does.
	"pot_lid": {"name": "Pot Lid", "kind": "equip", "slot": "offhand", "shield": "pot_lid", "color": Color("c3ccd4"),
		"desc": "A dependable all-rounder."},
	"buckler": {"name": "Buckler", "kind": "equip", "slot": "offhand", "shield": "buckler", "color": Color("d9a066"),
		"desc": "Small and light: you can almost run while blocking, and good timing is easier. Covers a narrow arc."},
	"tower_shield": {"name": "Tower Shield", "kind": "equip", "slot": "offhand", "shield": "tower_shield", "color": Color("9fb4c8"),
		"desc": "A wall to hide behind: covers a wide arc and soaks big hits, but you crawl while blocking and timing it is hard."},
	"spike_shield": {"name": "Spike Shield", "kind": "equip", "slot": "offhand", "shield": "spike_shield", "color": Color("b07a8a"),
		"desc": "Hurts whatever hits it. Twice as much on a Perfect Block."},
	# Helmets
	"miner_helmet": {"name": "Miner Helmet", "kind": "equip", "slot": "helmet", "light": "miner", "set": "miner",
		"color": Color("ffd27a"), "desc": "A headlamp: light without a torch, but only where you're looking."},
	"pot_helmet": {"name": "Saucepan Helmet", "kind": "equip", "slot": "helmet", "armor": 1, "color": Color("c3ccd4"),
		"desc": "Every hit does 1 less damage."},
	"leaf_hood": {"name": "Leaf Hood", "kind": "equip", "slot": "helmet", "regen": 1.35, "set": "wayfarer",
		"color": Color("86d47e"), "desc": "Stamina comes back faster."},
	# Chest
	"overalls": {"name": "Padded Overalls", "kind": "equip", "slot": "chest", "max_hp": 4, "set": "miner",
		"color": Color("7fa8d9"), "desc": "+2 hearts."},
	"raincoat": {"name": "Raincoat", "kind": "equip", "slot": "chest", "rainproof": true, "set": "wayfarer",
		"color": Color("ffd84a"), "desc": "Keeps your torch lit in the rain."},
	# Shoes
	"hermes_boots": {"name": "Hermes Boots", "kind": "equip", "slot": "shoes", "speed": 1.45, "color": Color("fff6e5"),
		"desc": "Run much faster."},
	"steel_toes": {"name": "Steel-Toed Boots", "kind": "equip", "slot": "shoes", "kick": 2, "set": "miner",
		"color": Color("9aa5ad"), "desc": "Sprint into an enemy to kick it."},
	"wellies": {"name": "Wellies", "kind": "equip", "slot": "shoes", "speed": 1.1, "set": "wayfarer",
		"color": Color("ff7a6b"), "desc": "A little faster in any weather."},
	# Trinkets
	"stamina_acorn": {"name": "Stamina Acorn", "kind": "equip", "slot": "trinket", "orbs": 1, "color": Color("c98b52"),
		"desc": "+1 stamina orb."},
	"feather_pin": {"name": "Feather Pin", "kind": "equip", "slot": "trinket", "dash": 1.35, "color": Color("bfeadb"),
		"desc": "Dashes go further."},
	"ember_charm": {"name": "Ember Charm", "kind": "equip", "slot": "trinket", "ignite": true, "color": Color("ff7a4a"),
		"desc": "Sickle hits set enemies alight while your torch is lit."},
	# Keys (kept in the bag; they open locked houses for good)
	"brass_key": {"name": "Brass Key", "kind": "key", "color": Color("e3b04b"),
		"desc": "Opens the Clockmaker's house in Middlemost. Press E at its door."},
	"rusty_key": {"name": "Rusty Key", "kind": "key", "color": Color("b5683f"),
		"desc": "Opens the Old Storehouse in Middlemost. Press E at its door."},
	"glow_pebble": {"name": "Glow Pebble", "kind": "equip", "slot": "trinket", "light": "glow", "color": Color("d8fff2"),
		"desc": "A faint glow around you. Not much, but not nothing."},
}

const SETS := {
	"miner": {"name": "Miner's Set", "pieces": ["miner_helmet", "overalls", "steel_toes"],
		"bonus": "Headlamp reaches twice as far and kicks hit harder."},
	"wayfarer": {"name": "Wayfarer's Set", "pieces": ["leaf_hood", "raincoat", "wellies"],
		"bonus": "Dashes cost half a stamina orb."},
}

## Shields. Blocking is judged by when you raised the shield before the hit landed:
##   Perfect: within `perfect` seconds. Stops the hit completely, costs half the stamina,
##            doesn't hurt the shield, and stuns the attacker.
##   Great:   within `great` seconds. Stops `eff[1]` of the damage; the shield takes half.
##   Regular: any longer. Stops `eff[2]` of the damage; the shield takes all of what it stops.
## A shield only covers `arc` degrees in front of you. Each block costs `cost` stamina orbs
## (and holding it up drains `hold` orbs a second). At 0 health it breaks: no blocking for
## `break_time` seconds, then it regrows at `recover` health a second. `move` is your speed
## while blocking. `spikes` is damage dealt back to whatever you block.
const SHIELDS := {
	"pot_lid": {"hp": 6.0, "cost": 1.0, "hold": 0.3, "recover": 1.0, "break_time": 4.0,
		"perfect": 0.12, "great": 0.30, "eff": [1.0, 0.75, 0.5], "arc": 70.0, "move": 0.55, "spikes": 0},
	"buckler": {"hp": 4.0, "cost": 0.6, "hold": 0.2, "recover": 1.6, "break_time": 2.5,
		"perfect": 0.18, "great": 0.40, "eff": [1.0, 0.7, 0.4], "arc": 50.0, "move": 0.85, "spikes": 0},
	"tower_shield": {"hp": 14.0, "cost": 1.5, "hold": 0.45, "recover": 0.6, "break_time": 6.0,
		"perfect": 0.08, "great": 0.20, "eff": [1.0, 0.9, 0.75], "arc": 150.0, "move": 0.3, "spikes": 0},
	"spike_shield": {"hp": 8.0, "cost": 1.0, "hold": 0.3, "recover": 0.9, "break_time": 4.0,
		"perfect": 0.12, "great": 0.28, "eff": [1.0, 0.7, 0.5], "arc": 65.0, "move": 0.5, "spikes": 2},
}
const BLOCK_NAMES := ["", "Regular block", "Great block", "Perfect block!"]

## What each chest gives (once per player).
const CHEST_LOOT := {
	"fern_chest": ["leaf_hood", "raincoat", "wellies", "brass_key"],
	"moss_chest": ["miner_helmet", "overalls", "steel_toes", "ember_charm", "rusty_key"],
	"willow_chest": ["buckler"],
	"clock_chest": ["tower_shield"],
	"store_chest": ["spike_shield", "stamina_acorn"],
}

## stages: how many growth stages until ripe (1 = seed). Each stage needs one watering.
const CROPS := {
	"popberry": {"stages": 3, "yield": "popberry", "amount": 2},
	"radish": {"stages": 4, "yield": "radish", "amount": 1},
}


## What a new player's bag starts with. The sickle starts in the wheel instead.
static func starter_kit() -> Array:
	var kit: Array = [["can", CAN_MAX], ["popberry_seed", 12], ["popberry", 6], ["radish_seed", 4], ["oil", 2],
		["lantern", 1], ["pot_lid", 1], ["hermes_boots", 1], ["pot_helmet", 1],
		["stamina_acorn", 1], ["feather_pin", 1], ["glow_pebble", 1]]
	var slots: Array = []
	for i in SLOTS:
		slots.append(kit[i] if i < kit.size() else [])
	return slots


## A new player's item wheel: just the sickle. It grows as you add things from the bag.
static func starter_wheel() -> Array:
	return [["sickle", 1]]


static func starter_equip() -> Dictionary:
	var e := empty_equip()
	e["offhand"] = "torch"
	return e


static func empty_equip() -> Dictionary:
	var e := {}
	for s in EQUIP_SLOTS:
		e[s] = ""
	return e


static func stackable(id: String) -> bool:
	var kind: String = ITEMS[id]["kind"]
	return kind == "seed" or kind == "throw" or kind == "material" or kind == "oil"


static func display_name(id: String) -> String:
	return str(ITEMS[id]["name"]) if ITEMS.has(id) else ""


## The shield stats of an item, or {} if it isn't a shield.
static func shield(id: String) -> Dictionary:
	if not ITEMS.has(id) or not ITEMS[id].has("shield"):
		return {}
	return SHIELDS[ITEMS[id]["shield"]]


## A shield's description for the bag screen, built from its numbers.
static func shield_text(id: String) -> String:
	var sh := shield(id)
	var eff: Array = sh["eff"]
	return "%s Health %d. Covers %d degrees in front. Perfect block within %.2fs, Great within %.2fs (stops %d%% / %d%% / %d%%). Costs %.1f orbs a block. Speed while blocking %d%%.%s" % [
		str(ITEMS[id].get("desc", "")), int(sh["hp"]), int(sh["arc"]), float(sh["perfect"]), float(sh["great"]),
		roundi(float(eff[0]) * 100.0), roundi(float(eff[1]) * 100.0), roundi(float(eff[2]) * 100.0),
		float(sh["cost"]), roundi(float(sh["move"]) * 100.0),
		(" Spikes deal %d damage." % int(sh["spikes"])) if int(sh["spikes"]) > 0 else ""]


static func is_equipment(id: String) -> bool:
	return ITEMS.has(id) and str(ITEMS[id]["kind"]) == "equip"


## Which equipment slot an item goes in (trinkets take the first free trinket slot).
static func target_slot(id: String, equip: Dictionary) -> String:
	var s: String = ITEMS[id].get("slot", "")
	if s != "trinket":
		return s
	for t in ["trinket1", "trinket2", "trinket3"]:
		if str(equip.get(t, "")) == "":
			return t
	return "trinket1"


static func equipped(equip: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for s in EQUIP_SLOTS:
		var id := str(equip.get(s, ""))
		if id != "":
			out.append(id)
	return out


## Multiplies a stat over everything worn (speed, regen, dash). 1.0 if none.
static func mult(equip: Dictionary, key: String) -> float:
	var m := 1.0
	for id in equipped(equip):
		m *= float(ITEMS[id].get(key, 1.0))
	return m


## Adds up a stat over everything worn (armor, orbs, max_hp, kick).
static func total(equip: Dictionary, key: String) -> int:
	var n := 0
	for id in equipped(equip):
		n += int(ITEMS[id].get(key, 0))
	return n


static func has_flag(equip: Dictionary, key: String) -> bool:
	for id in equipped(equip):
		if bool(ITEMS[id].get(key, false)):
			return true
	return false


static func full_sets(equip: Dictionary) -> Array[String]:
	var worn := equipped(equip)
	var out: Array[String] = []
	for set_id: String in SETS:
		var all := true
		for piece: String in SETS[set_id]["pieces"]:
			if not piece in worn:
				all = false
		if all:
			out.append(set_id)
	return out


## Adds n of an item, stacking where possible. Returns false if the bag is full.
static func add_item(slots: Array, id: String, n: int) -> bool:
	if stackable(id):
		for s in slots:
			var slot: Array = s
			if slot.size() == 2 and slot[0] == id:
				slot[1] = int(slot[1]) + n
				return true
	for i in slots.size():
		var slot: Array = slots[i]
		if slot.is_empty():
			slots[i] = [id, n]
			return true
	return false


## Gives a player something: onto a matching stack in their wheel if there is one (so
## harvested berries land in your hand), otherwise into the bag. False if the bag is full.
static func give(bag: Array, wheel: Array, id: String, n: int) -> bool:
	if stackable(id):
		for slot: Array in wheel:
			if slot.size() == 2 and slot[0] == id:
				slot[1] = int(slot[1]) + n
				return true
	return add_item(bag, id, n)


# ---------------------------------------------------------------- the item wheel

static func fits_wheel(id: String) -> bool:
	return ITEMS.has(id) and str(ITEMS[id]["kind"]) in WHEEL_KINDS


## Moves a bag stack into the wheel (merging with a matching stack). Returns "" if it
## worked, or a reason it didn't.
static func wheel_add(wheel: Array, bag: Array, bag_slot: int) -> String:
	var id := item_at(bag, bag_slot)
	if id == "":
		return "That bag slot is empty."
	if not fits_wheel(id):
		return "%s can't go in the item wheel." % display_name(id)
	for slot: Array in wheel:
		if slot.size() == 2 and slot[0] == id and stackable(id):
			slot[1] = int(slot[1]) + count_at(bag, bag_slot)
			bag[bag_slot] = []
			return ""
	if wheel.size() >= WHEEL_MAX:
		return "Your wheel is full (%d). Take something out first." % WHEEL_MAX
	wheel.append(bag[bag_slot])
	bag[bag_slot] = []
	return ""


## Moves a wheel stack back into the bag; the wheel closes the gap.
static func wheel_remove(wheel: Array, bag: Array, wheel_slot: int) -> String:
	if wheel_slot < 0 or wheel_slot >= wheel.size():
		return "Nothing there."
	var slot: Array = wheel[wheel_slot]
	var id: String = slot[0]
	if stackable(id):
		for b: Array in bag:
			if b.size() == 2 and b[0] == id:
				b[1] = int(b[1]) + int(slot[1])
				wheel.remove_at(wheel_slot)
				return ""
	for i in bag.size():
		if (bag[i] as Array).is_empty():
			bag[i] = slot
			wheel.remove_at(wheel_slot)
			return ""
	return "Your bag is full."


## Uses one of a wheel stack. Returns true if that emptied it (the wheel shrinks).
static func wheel_take_one(wheel: Array, wheel_slot: int) -> bool:
	var slot: Array = wheel[wheel_slot]
	slot[1] = int(slot[1]) - 1
	if int(slot[1]) <= 0:
		wheel.remove_at(wheel_slot)
		return true
	return false


## Where an item is: {"in": "wheel" or "bag", "i": slot} or {} if you don't have it.
static func locate(bag: Array, wheel: Array, id: String) -> Dictionary:
	var w := find(wheel, id)
	if w >= 0:
		return {"in": "wheel", "i": w}
	var b := find(bag, id)
	if b >= 0:
		return {"in": "bag", "i": b}
	return {}


static func take_one(slots: Array, i: int) -> void:
	var slot: Array = slots[i]
	slot[1] = int(slot[1]) - 1
	if int(slot[1]) <= 0:
		slots[i] = []


static func find(slots: Array, id: String) -> int:
	for i in slots.size():
		var slot: Array = slots[i]
		if slot.size() == 2 and slot[0] == id:
			return i
	return -1


static func count_of(slots: Array, id: String) -> int:
	var n := 0
	for s in slots:
		var slot: Array = s
		if slot.size() == 2 and slot[0] == id:
			n += int(slot[1])
	return n


static func item_at(slots: Array, i: int) -> String:
	if i < 0 or i >= slots.size():
		return ""
	var slot: Array = slots[i]
	return str(slot[0]) if slot.size() == 2 else ""


static func count_at(slots: Array, i: int) -> int:
	if i < 0 or i >= slots.size():
		return 0
	var slot: Array = slots[i]
	return int(slot[1]) if slot.size() == 2 else 0
