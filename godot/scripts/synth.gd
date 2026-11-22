class_name Synth
## Small synthesized sounds (all offline): horn, engine loop, scoop, rumble, beep.
## If assets/audio/<name>.ogg|wav exists it is used instead.

static var _cache := {}


static func _file(nm: String) -> AudioStream:
	for ext in ["ogg", "wav", "mp3"]:
		var p := "res://assets/audio/%s.%s" % [nm, ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null


static func _wav(sr: int, samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1, 1) * 30000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


static func horn() -> AudioStream:
	var f := _file("horn")
	if f:
		return f
	var sr := 22050
	var s := PackedFloat32Array()
	s.resize(int(sr * 0.9))
	for i in s.size():
		var t := float(i) / sr
		var env := minf(t * 30, 1.0) * minf((0.9 - t) * 12, 1.0)
		var v := 0.0
		for fr in [311.0, 392.0]:
			var ph := fmod(t * fr, 1.0)
			v += (ph * 2.0 - 1.0) * 0.3
		s[i] = v * env * 0.8
	return _wav(sr, s)


static func engine() -> AudioStream:
	var f := _file("engine")
	if f:
		return f
	var sr := 22050
	var n := sr  # 1 s loop; 30 Hz and harmonics fit a whole number of cycles
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in n:
		var t := float(i) / sr
		var thump := pow(maxf(sin(TAU * 30.0 * t), 0.0), 6.0)
		lp += (rng.randf() * 2 - 1 - lp) * 0.05
		s[i] = thump * 0.5 + lp * 0.6 + sin(TAU * 60.0 * t) * 0.15
	return _wav(sr, s, true)


static func _oneshot(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var f := _file(key)
	if f:
		_cache[key] = f
		return f
	var sr := 22050
	var s := PackedFloat32Array()
	var lp := 0.0
	match key:
		"rumble", "scoop":
			var dur := 1.2 if key == "rumble" else 0.6
			s.resize(int(sr * dur))
			for i in s.size():
				var t := float(i) / sr
				lp += (randf() * 2 - 1 - lp) * (0.05 if key == "rumble" else 0.15)
				var env := minf(t * 20, 1.0) * exp(-t * (2.5 if key == "rumble" else 5.0))
				var clack := 0.0
				if randf() < 0.004:
					clack = randf() * 0.8
				s[i] = (lp * 3.0 + clack) * env
		_:
			s.resize(int(sr * 0.15))
			for i in s.size():
				var t := float(i) / sr
				s[i] = (0.4 if fmod(t * 1000.0, 1.0) < 0.5 else -0.4) * minf((0.15 - t) * 40, 1.0)
	_cache[key] = _wav(sr, s)
	return _cache[key]


static func _play(node: Node, key: String, vol := 0.8) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _oneshot(key)
	p.volume_db = linear_to_db(vol)
	p.pitch_scale = randf_range(0.9, 1.1)
	node.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


static func play_rumble(node: Node) -> void:
	_play(node, "rumble")


static func play_scoop(node: Node) -> void:
	_play(node, "scoop", 0.7)


static func beep(node: Node) -> void:
	_play(node, "beep", 0.5)
