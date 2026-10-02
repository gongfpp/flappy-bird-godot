class_name SaveStore
extends RefCounted
## A missing or corrupt file never prevents play.
var path: String
var best := 0
var muted := false
var last_save_error: Error = OK

func _init(save_path: String = "user://sky_hop.cfg") -> void:
	path = save_path
	load_data()

func load_data() -> void:
	best = 0
	muted = false
	var data := ConfigFile.new()
	if data.load(path) != OK:
		return
	var stored: Variant = data.get_value("scores", "best", 0)
	if (stored is int or stored is float) and is_finite(float(stored)):
		best = int(clampf(float(stored), 0.0, 1000000.0))
	var sound: Variant = data.get_value("settings", "muted", false)
	if sound is bool:
		muted = sound

func record_score(value: int) -> bool:
	value = clampi(value, 0, 1000000)
	if value <= best:
		return false
	best = value
	save_data()
	return true

func set_muted(value: bool) -> void:
	muted = value
	save_data()

func save_data() -> void:
	var data := ConfigFile.new()
	data.set_value("scores", "best", best)
	data.set_value("settings", "muted", muted)
	last_save_error = data.save(path)
