extends Node
## Music, a synthesized "found it" chime, and the device's text-to-speech voice. All offline.

var music := AudioStreamPlayer.new()
var chime_player := AudioStreamPlayer.new()
var music_on := true:
	set(v):
		music_on = v
		music.stream_paused = not v
		if v and not music.playing:
			music.play()

var _voice := ""


func _ready() -> void:
	var s: AudioStreamMP3 = load("res://assets/audio/music.mp3") if ResourceLoader.exists("res://assets/audio/music.mp3") else null
	if s:
		s.loop = true
		music.stream = s
	music.volume_db = linear_to_db(0.3)
	add_child(music)
	chime_player.stream = _make_chime()
	chime_player.volume_db = linear_to_db(0.9)
	add_child(chime_player)
	_pick_voice()


func start_music() -> void:
	if music_on and not music.playing:
		music.play()


func chime() -> void:
	chime_player.play()


func say(text: String) -> void:
	if _voice == "":
		_pick_voice()
	if _voice == "":
		return
	DisplayServer.tts_speak(text, _voice, 90, 1.15, 0.9, 0, true)


func _pick_voice() -> void:
	var best := ""
	for v in DisplayServer.tts_get_voices():
		var lang := str(v.get("language", "")).to_lower().replace("-", "_")
		if lang.begins_with("en_us") and best == "":
			best = v["id"]
		elif lang.begins_with("en") and best == "" :
			best = v["id"]
	if best == "":
		var any := DisplayServer.tts_get_voices_for_language("en")
		if any.size() > 0:
			best = any[0]
	_voice = best


## C-E-G-C arpeggio with soft decay.
func _make_chime() -> AudioStreamWAV:
	var sr := 44100
	var frames := int(sr * 1.4)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var notes := [1046.5, 1318.5, 1568.0, 2093.0]
	for i in frames:
		var t := float(i) / sr
		var s := 0.0
		for k in notes.size():
			var start := k * 0.11
			if t >= start:
				var lt := t - start
				s += sin(TAU * notes[k] * lt) * exp(-lt * 4.0) * 0.22
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = data
	return w
