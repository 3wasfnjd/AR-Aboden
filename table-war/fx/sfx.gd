class_name SfxBank
extends Node3D
## Procedural impact sounds (no audio assets): generated once as 16-bit PCM
## AudioStreamWAV and played through a small pool of AudioStreamPlayer3D voices placed
## at the event (positions are diorama-local; the players follow the diorama).
##   boom   land explosion: sharp crack + low rumble
##   thump  shell into the sea: muffled low thump + soft hiss of the water column
##   launch whoosh as the shot leaves the player's hand

const RATE := 22050
const VOICES := 6

static var _streams := {}
var _voices: Array[AudioStreamPlayer3D] = []
var _next := 0
var last_played := ""


func _ready() -> void:
	for k in VOICES:
		var a := AudioStreamPlayer3D.new()
		a.name = "Voice%d" % k
		a.unit_size = 1.5
		a.max_distance = 30.0
		a.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(a)
		_voices.append(a)
	# generate every sound now (load time), not in the frame of the first impact
	for nm in ["boom", "thump", "launch"]:
		stream(nm)


func play(name: String, pos: Vector3, volume := 1.0) -> void:
	last_played = name
	if _voices.is_empty():
		return
	var a := _voices[_next]
	_next = (_next + 1) % _voices.size()
	a.stream = stream(name)
	a.position = pos
	a.volume_db = linear_to_db(clampf(volume, 0.05, 1.5))
	a.play()


static func stream(name: String) -> AudioStreamWAV:
	if not _streams.has(name):
		_streams[name] = _make(name)
	return _streams[name]


static func _make(name: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var dur := {"boom": 1.6, "thump": 0.9, "launch": 0.7}.get(name, 0.5) as float
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match name:
			"boom":
				# crack (bright noise, 30 ms) + rumble (low-passed noise + 45 Hz body)
				lp += (noise - lp) * 0.06
				lp2 += (lp - lp2) * 0.08
				phase += TAU * lerpf(70.0, 38.0, minf(t / 0.6, 1.0)) / RATE
				v = noise * exp(-t / 0.012) * 0.8 + lp2 * 5.0 * exp(-t / 0.45) + sin(phase) * 0.6 * exp(-t / 0.35)
			"thump":
				# muffled: everything low-passed hard, a 55->30 Hz sine body + soft hiss
				lp += (noise - lp) * 0.02
				lp2 += (lp - lp2) * 0.03
				phase += TAU * lerpf(55.0, 30.0, minf(t / 0.4, 1.0)) / RATE
				v = sin(phase) * 0.85 * exp(-t / 0.18) * minf(t / 0.004, 1.0) + lp2 * 6.0 * exp(-t / 0.3) + noise * 0.04 * exp(-pow((t - 0.15) / 0.12, 2.0))
			_:
				# launch whoosh: band-limited noise swelling and fading
				lp += (noise - lp) * 0.15
				v = (noise - lp) * 0.5 * sin(PI * minf(t / dur, 1.0)) * exp(-t / 0.5)
		var s := clampi(int(clampf(v, -1.0, 1.0) * 30000.0), -32768, 32767)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
