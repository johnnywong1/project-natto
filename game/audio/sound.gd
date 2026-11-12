extends Node
## Sound (autoload "Sound"): sound effects, music and the volume settings.
##
## There are no audio files yet: every sound is made in code when the game starts (short
## synth tones and noise bursts), and the music is a gentle looping tune built the same
## way. They are placeholders with the right *hooks*: swap in real recordings later by
## changing `_make_sounds()` / `_make_music()`; everything else stays.
##
## Three audio buses: Master, Music and SFX. The Settings screen sets their volumes, and
## they're kept in user://settings.cfg between sessions.

const SETTINGS_PATH := "user://settings.cfg"
const RATE := 22050
const BUSES := ["Master", "Music", "SFX"]

## Volumes, 0.0 to 1.0, by bus name.
var volumes := {"Master": 0.8, "Music": 0.5, "SFX": 0.8}

var _sounds: Dictionary = {}       # name -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_load_settings()
	if DisplayServer.get_name() == "headless":
		return   # tests: no sound card, nothing to make
	_make_sounds()
	for k in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.stream = _make_music()
	add_child(_music)


## Plays a sound effect. `gain` (0..1) makes it quieter, e.g. for things far away.
func play(sound: String, gain: float = 1.0) -> void:
	if _players.is_empty() or not _sounds.has(sound) or gain <= 0.01:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[sound]
	p.volume_db = linear_to_db(gain)
	p.pitch_scale = randf_range(0.95, 1.05)
	p.play()


func start_music() -> void:
	if _music != null and not _music.playing:
		_music.play()


func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply(bus)
	_save_settings()


func _apply(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var v: float = volumes[bus]
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for bus: String in BUSES:
			volumes[bus] = clampf(float(cfg.get_value("audio", bus, volumes[bus])), 0.0, 1.0)
	for bus: String in BUSES:
		_apply(bus)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for bus: String in BUSES:
		cfg.set_value("audio", bus, volumes[bus])
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------- the synth

func _make_sounds() -> void:
	_sounds["ui"] = _tone([[1200.0, 1200.0]], 0.04, 0.35)
	_sounds["swing"] = _noise(0.16, 0.5, 2.5)
	_sounds["hit"] = _tone([[160.0, 90.0]], 0.12, 0.9, 0.3)
	_sounds["hurt"] = _tone([[420.0, 200.0]], 0.22, 0.6)
	_sounds["block"] = _tone([[620.0, 600.0], [930.0, 900.0]], 0.18, 0.5)
	_sounds["great"] = _tone([[880.0, 870.0], [1320.0, 1300.0]], 0.22, 0.5)
	_sounds["perfect"] = _tone([[1046.0, 1046.0], [1568.0, 1568.0], [2093.0, 2093.0]], 0.35, 0.45)
	_sounds["shield_break"] = _noise(0.35, 0.7, 6.0)
	_sounds["pickup"] = _tone([[660.0, 990.0]], 0.12, 0.5)
	_sounds["plant"] = _tone([[300.0, 220.0]], 0.1, 0.5, 0.2)
	_sounds["water"] = _tone([[1400.0, 700.0]], 0.14, 0.35)
	_sounds["harvest"] = _tone([[523.0, 523.0], [784.0, 784.0]], 0.2, 0.45)
	_sounds["throw"] = _noise(0.1, 0.35, 4.0)
	_sounds["splat"] = _noise(0.14, 0.6, 3.0)
	_sounds["fire"] = _noise(0.3, 0.45, 1.5)
	_sounds["ice"] = _tone([[1800.0, 1500.0], [2400.0, 2000.0]], 0.25, 0.35)
	_sounds["door"] = _tone([[110.0, 100.0]], 0.18, 0.8, 0.4)
	_sounds["locked"] = _tone([[300.0, 300.0]], 0.05, 0.6, 0.6)
	_sounds["chest"] = _tone([[392.0, 392.0], [523.0, 523.0], [659.0, 659.0]], 0.4, 0.4)
	_sounds["lift"] = _tone([[90.0, 120.0]], 0.5, 0.4, 0.3)
	_sounds["dash"] = _noise(0.12, 0.4, 5.0)
	_sounds["pop"] = _tone([[700.0, 1400.0]], 0.1, 0.5)


## A short tone: each partial glides from its start to its end frequency, with a quick
## attack and an exponential fade. `grit` adds a little noise (thumps, knocks).
func _tone(partials: Array, seconds: float, gain: float, grit: float = 0.0) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phases: Array[float] = []
	phases.resize(partials.size())
	phases.fill(0.0)
	for i in n:
		var t := float(i) / n
		var env := minf(t * 40.0, 1.0) * exp(-4.0 * t)
		var v := 0.0
		for k in partials.size():
			var f: float = lerpf(float(partials[k][0]), float(partials[k][1]), t)
			phases[k] += TAU * f / RATE
			v += sin(phases[k]) / partials.size()
		v = v * (1.0 - grit) + randf_range(-1.0, 1.0) * grit
		data.encode_s16(i * 2, int(clampf(v * env * gain, -1.0, 1.0) * 32000.0))
	return _wav(data)


## A noise burst (whooshes, crackles). Higher `fall` dies away faster.
func _noise(seconds: float, gain: float, fall: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var last := 0.0
	for i in n:
		var t := float(i) / n
		var env := minf(t * 20.0, 1.0) * exp(-fall * t)
		last = lerpf(last, randf_range(-1.0, 1.0), 0.35)   # a soft low-pass
		data.encode_s16(i * 2, int(clampf(last * env * gain, -1.0, 1.0) * 32000.0))
	return _wav(data)


## A slow, calm tune: a pentatonic melody over two chords, 16 seconds, looping.
func _make_music() -> AudioStreamWAV:
	var rate := 16000
	var beat := 0.5
	var melody := [64, 67, 69, 67, 72, 69, 67, 64, 62, 64, 67, 64, 62, 60, 62, 64,
		64, 67, 69, 72, 74, 72, 69, 67, 69, 67, 64, 62, 60, 62, 60, 0]
	var bass := [48, 48, 45, 45, 53, 53, 43, 43]
	var total := int(melody.size() * beat * rate)
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		var t := float(i) / rate
		var b := int(t / beat)
		var bt := fmod(t, beat) / beat
		var v := 0.0
		var note: int = melody[b % melody.size()]
		if note > 0:
			var f := 440.0 * pow(2.0, (note - 69) / 12.0)
			v += sin(TAU * f * t) * exp(-3.0 * bt) * 0.35 + sin(TAU * f * 2.0 * t) * exp(-5.0 * bt) * 0.08
		@warning_ignore("integer_division")
		var bn: int = bass[(b / 4) % bass.size()]
		var bf := 440.0 * pow(2.0, (bn - 69) / 12.0)
		var bar_t := fmod(t, beat * 4.0) / (beat * 4.0)
		v += sin(TAU * bf * t) * 0.22 * (1.0 - bar_t * 0.5)
		data.encode_s16(i * 2, int(clampf(v * 0.6, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = total
	return w


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w
