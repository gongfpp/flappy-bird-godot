class_name SoundBank
extends Node
## Original synthesized effects; no external samples or copyrighted game audio.
var muted := false
var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var next_player := 0

func _ready() -> void:
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.volume_db = -12.0
		add_child(player)
		players.append(player)
	streams["flap"] = _tone(0.11, 530.0, 850.0, 0.2)
	streams["point"] = _tone(0.22, 880.0, 1320.0, 0.22)
	streams["hit"] = _tone(0.20, 155.0, 48.0, 0.24)
	streams["click"] = _tone(0.08, 450.0, 570.0, 0.15)

func play(effect: String) -> void:
	if muted or not streams.has(effect):
		return
	var player: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	player.stream = streams[effect]
	player.play()

func _tone(duration: float, start_hz: float, end_hz: float, volume: float) -> AudioStreamWAV:
	const RATE := 22050
	var count := int(duration * RATE)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	var phase := 0.0
	for i in range(count):
		var t := float(i) / count
		phase += TAU * lerpf(start_hz, end_hz, t) / RATE
		var envelope := minf(t * 24.0, 1.0) * pow(1.0 - t, 1.5)
		var signal_value := sin(phase) + sin(phase * 2.0) * 0.15
		var value := int(clampf(signal_value * volume * envelope, -1.0, 1.0) * 32767.0)
		samples.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = samples
	return stream
