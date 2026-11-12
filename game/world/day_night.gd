extends CanvasModulate
## Day and night for the zone you're in. Outdoor zones follow the shared clock (dawn, day,
## dusk, night) with their own tint and light level; underground zones like Mossmouth stay
## dark all day. Nights are properly dark: without a torch, lantern, headlamp or a fire
## nearby you can barely see. Clouds, rain and mist darken things a little more.

const Z = preload("res://game/data/zones.gd")

## Hour -> sky colour, interpolated.
const SKY := [
	[0.0, Color(0.045, 0.05, 0.11)],
	[4.5, Color(0.045, 0.05, 0.11)],
	[5.5, Color(0.28, 0.22, 0.34)],
	[6.5, Color(1.00, 0.80, 0.72)],
	[8.0, Color(1.00, 1.00, 1.00)],
	[17.0, Color(1.00, 1.00, 1.00)],
	[18.5, Color(1.00, 0.72, 0.55)],
	[19.5, Color(0.30, 0.24, 0.40)],
	[20.5, Color(0.045, 0.05, 0.11)],
	[24.0, Color(0.045, 0.05, 0.11)],
]
const WEATHER_DIM := {"clear": 1.0, "cloudy": 0.9, "rain": 0.8, "drizzle": 0.86, "mist": 0.92, "drip": 1.0, "spores": 0.95}

var zone := "middlemost"

## How dark the screen is right now: 0 = full daylight, 1 = pitch black. Torches, lanterns
## and fires scale their glow with this, so they light up the night without bleaching the
## picture at noon.
static var darkness := 0.0


static func sky_at(hour: float) -> Color:
	for i in SKY.size() - 1:
		var h0: float = SKY[i][0]
		var h1: float = SKY[i + 1][0]
		if hour >= h0 and hour <= h1:
			var c0: Color = SKY[i][1]
			var c1: Color = SKY[i + 1][1]
			return c0.lerp(c1, (hour - h0) / maxf(h1 - h0, 0.001))
	return SKY[0][1]


func target_color() -> Color:
	var zd := Z.zone(zone)
	var tint: Color = zd["tint"]
	var light: float = zd["light"]
	var dim: float = WEATHER_DIM.get(World.weather.get(zone, "clear"), 1.0)
	var base: Color
	if bool(zd["outdoor"]):
		base = sky_at(World.clock / 60.0)
		base = Color(base.r * light, base.g * light, base.b * light)
	else:
		base = Color(light, light, light)
	return Color(base.r * tint.r * dim, base.g * tint.g * dim, base.b * tint.b * dim, 1.0)


func _ready() -> void:
	color = target_color()
	darkness = clampf(1.0 - (color.r * 0.3 + color.g * 0.59 + color.b * 0.11), 0.0, 1.0)


## How strongly lights should shine right now (0 at noon, 1 once it's properly dark).
static func light_scale() -> float:
	return smoothstep(0.2, 0.75, darkness)


func _process(delta: float) -> void:
	color = color.lerp(target_color(), 1.0 - exp(-delta * 2.0))
	darkness = clampf(1.0 - (color.r * 0.3 + color.g * 0.59 + color.b * 0.11), 0.0, 1.0)
