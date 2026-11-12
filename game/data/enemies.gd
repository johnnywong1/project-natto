extends RefCounted
## Enemy types. The host runs their AI. Every attack except a plain bump is announced first
## with a warning drawn on the ground (a telegraph), so players can step or dash out of it,
## or block it with a Pot Lid.
##
##   charge  a line across the ground, then a bull charge along it (stops and gets dazed
##           if it hits a cliff or ice)
##   burst   a circle that fills up, then a spore burst inside it
##   slam    a wedge in front of a big animal, after a long wind-up

const KINDS := {
	"wilt": {"name": "Mildew Wilt", "hp": 2, "speed": 52.0, "radius": 20.0, "touch": 1, "attack": "",
		"aggro": 420.0, "crops": true, "scale": 1.0},
	"frost_wilt": {"name": "Frost Wilt", "hp": 3, "speed": 38.0, "radius": 22.0, "touch": 1, "attack": "",
		"aggro": 380.0, "frozen": true, "scale": 1.1},
	"boar": {"name": "Thornback Boar", "hp": 6, "speed": 66.0, "radius": 30.0, "touch": 1, "attack": "charge",
		"aggro": 520.0, "range": 380.0, "windup": 1.0, "damage": 3, "attack_speed": 720.0, "length": 460.0, "recover": 1.3, "cooldown": 2.6, "scale": 1.4},
	"puffcap": {"name": "Puffcap", "hp": 3, "speed": 14.0, "radius": 24.0, "touch": 0, "attack": "burst",
		"aggro": 320.0, "range": 200.0, "windup": 1.2, "damage": 2, "area": 140.0, "recover": 0.8,
		"cooldown": 3.0, "scale": 1.0},
	"bear": {"name": "Mossback Bear", "hp": 14, "speed": 40.0, "radius": 44.0, "touch": 2, "attack": "slam",
		"aggro": 360.0, "range": 170.0, "windup": 1.5, "damage": 4, "length": 220.0, "half_angle": 0.9,
		"recover": 1.6, "cooldown": 2.2, "scale": 2.0},
}

const WALL_STUN := 1.6       # a charge that ends in a cliff or ice leaves the boar dazed
const PERFECT_STUN := 1.2    # blocking right before a hit stuns the attacker
const BURN_TIME := 4.0
const BURN_DPS := 1.0

const STATE_CODES := {"move": 0, "windup": 1, "attack": 2, "recover": 3, "stunned": 4}


static func info(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS["wilt"])
