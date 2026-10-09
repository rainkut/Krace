extends Node
## All audio is synthesised at start-up (no audio files shipped): UI/event sounds as short
## AudioStreamWAVs, the engine as a live AudioStreamGenerator driven by speed.

const RATE := 22050
var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _engine_player: AudioStreamPlayer
var _engine_pb: AudioStreamGeneratorPlayback
var engine_on := false
var engine_level := 0.0   # 0..1
var _phase := 0.0
var _phase2 := 0.0
var _lp := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sounds["click"] = _tone([[900.0, 700.0, 0.06]], 0.35)
	_sounds["ding"] = _tone([[880.0, 880.0, 0.10], [1320.0, 1320.0, 0.22]], 0.4)
	_sounds["star"] = _tone([[1100.0, 1500.0, 0.07], [1650.0, 2100.0, 0.16]], 0.35)
	_sounds["beep"] = _tone([[620.0, 620.0, 0.22]], 0.45)
	_sounds["go"] = _tone([[930.0, 930.0, 0.45]], 0.5)
	_sounds["fanfare"] = _tone([[523.0, 523.0, 0.14], [659.0, 659.0, 0.14], [784.0, 784.0, 0.14], [1046.0, 1046.0, 0.5]], 0.45)
	_sounds["horn"] = _tone([[392.0, 392.0, 0.5]], 0.4, 1)
	_sounds["bump"] = _noise(0.22, 0.6)
	_sounds["crunch"] = _noise(0.32, 0.75)
	_sounds["buzz"] = _tone([[200.0, 160.0, 0.25]], 0.4, 1)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_engine_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	_engine_player.stream = gen
	_engine_player.volume_db = -14.0
	add_child(_engine_player)

func play(name: String, volume: float = 1.0) -> void:
	if not _sounds.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _sounds[name]
	p.volume_db = linear_to_db(maxf(volume, 0.001))
	p.play()

func start_engine() -> void:
	engine_on = true
	if not _engine_player.playing:
		_engine_player.play()
	_engine_pb = _engine_player.get_stream_playback()

func stop_engine() -> void:
	engine_on = false
	_engine_player.stop()
	_engine_pb = null

func _process(_dt: float) -> void:
	if not engine_on or _engine_pb == null:
		return
	var n := _engine_pb.get_frames_available()
	var f := 38.0 + engine_level * 120.0
	var vol := 0.22 + engine_level * 0.14
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_phase = fmod(_phase + f / RATE, 1.0)
		_phase2 = fmod(_phase2 + f * 0.5 / RATE, 1.0)
		var s := (_phase * 2.0 - 1.0) * 0.6 + (signf(_phase2 - 0.5)) * 0.3
		_lp += (s - _lp) * 0.18
		buf[i] = Vector2(_lp * vol, _lp * vol)
	_engine_pb.push_buffer(buf)

func _tone(parts: Array, vol: float, wave: int = 0) -> AudioStreamWAV:
	var data := PackedByteArray()
	var phase := 0.0
	for part in parts:
		var n := int(RATE * float(part[2]))
		for i in n:
			var t := float(i) / n
			var f := lerpf(float(part[0]), float(part[1]), t)
			phase += f / RATE
			var s := sin(phase * TAU) if wave == 0 else signf(sin(phase * TAU)) * 0.6
			var env := minf(1.0, t * 30.0) * pow(1.0 - t, 1.3)
			data.append_array(_s16(s * env * vol))
	return _wav(data)

func _noise(dur: float, vol: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	var n := int(RATE * dur)
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		lp += (randf_range(-1.0, 1.0) - lp) * 0.25
		data.append_array(_s16(lp * pow(1.0 - t, 2.0) * vol))
	return _wav(data)

func _s16(v: float) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_s16(0, int(clampf(v, -1.0, 1.0) * 32000.0))
	return b

func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
