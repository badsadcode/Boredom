extends Node
## Tiny procedural sound bank, so the slice has audio without any audio assets.
## Everything is synthesised once at startup (16-bit mono, 22.05 kHz) and played through a pool.

const RATE: int = 22050
var _bank: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_bank["shot_pistol"] = _noise(0.16, 7.0, 0.0, 0.9)
	_bank["shot_shotgun"] = _noise(0.34, 5.0, 60.0, 1.0)
	_bank["shot_smg"] = _noise(0.11, 9.0, 0.0, 0.8)
	_bank["click"] = _noise(0.04, 30.0, 900.0, 0.5)
	_bank["reload"] = _noise(0.09, 14.0, 300.0, 0.55)
	_bank["hit"] = _noise(0.08, 12.0, 160.0, 0.7)
	_bank["groan"] = _tone(0.9, 70.0, 0.55, 3.0)
	_bank["hurt"] = _tone(0.3, 120.0, 0.7, 6.0)
	_bank["pickup"] = _tone(0.18, 660.0, 0.35, 6.0)
	_bank["door"] = _noise(0.5, 3.0, 40.0, 0.8)
	_bank["locked"] = _tone(0.2, 90.0, 0.5, 10.0)


func play(name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _bank.has(name):
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _bank[name]
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.volume_db = volume_db
	p.play()


## Positional one-shot (zombie groans, distant doors). Frees itself when done.
func play3d(name: String, pos: Vector3, pitch: float = 1.0) -> void:
	if not _bank.has(name):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _bank[name]
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.unit_size = 6.0
	p.max_distance = 45.0
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


## Decaying noise burst. `lowpass_hz` > 0 darkens it (a crude boom); 0 leaves it white.
func _noise(dur: float, decay: float, lowpass_hz: float, gain: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp: float = 0.0
	var a: float = 1.0 if lowpass_hz <= 0.0 else clampf(lowpass_hz * 6.28318 / RATE, 0.01, 1.0)
	for i in n:
		var t: float = float(i) / float(n)
		var white: float = randf_range(-1.0, 1.0)
		lp += a * (white - lp)
		out[i] = (white if lowpass_hz <= 0.0 else lp * 2.5) * exp(-decay * t) * gain
	return _make(out)


func _tone(dur: float, hz: float, gain: float, decay: float) -> AudioStreamWAV:
	var n: int = int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t: float = float(i) / float(RATE)
		var env: float = exp(-decay * t / dur)
		var wob: float = 1.0 + 0.04 * sin(t * 9.0)
		var saw: float = fmod(t * hz * wob, 1.0) * 2.0 - 1.0
		out[i] = saw * env * gain
	return _make(out)
