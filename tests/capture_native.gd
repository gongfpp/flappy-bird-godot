extends SceneTree
## Optional real-renderer evidence capture. Run WITHOUT --headless.
## The autopilot sends normal Space key events; it never teleports the bird.
## Each PNG comes from the running game's viewport, not a mockup.
var game: Node
var output := "res://evidence"
var flaps := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native capture requires a graphics display; remove --headless.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await create_timer(0.8).timeout
	await _capture("native-ready")
	_press(KEY_SPACE)
	var frames := 0
	while game.model.phase == game.Model.Phase.PLAYING and game.model.score < 4 and frames < 7200:
		var target := 355.0
		for pipe in game.model.pipes:
			if pipe.x + game.Model.PIPE_WIDTH + game.Model.CAP_OVERHANG >= game.Model.BIRD_X - game.Model.RADIUS:
				target = pipe.center + 25.0
				break
		if game.model.bird_y >= target and game.model.velocity > 0.0:
			_press(KEY_SPACE)
			flaps += 1
		await physics_frame
		frames += 1
	if game.model.score < 4:
		push_error("Native flight failed before 4 points: score=%d, frames=%d" % [game.model.score, frames])
		quit(1)
		return
	await _capture("native-playing")
	_press(KEY_P)
	await create_timer(0.35).timeout
	await _capture("native-paused")
	_press(KEY_P)
	while game.model.phase != game.Model.Phase.GAME_OVER:
		await physics_frame
	await create_timer(0.9).timeout
	await _capture("native-game-over")
	print("NATIVE_CAPTURE_PASS score=%d flaps=%d physics_frames=%d" % [game.model.score, flaps, frames])
	game.queue_free()
	await process_frame
	quit(0)

func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.pressed = false
	root.push_input(event)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var full: Image = root.get_texture().get_image()
	full.save_png(output.path_join(label + "-full.png"))
	var width := full.get_width()
	var height := full.get_height()
	var content_width := int(minf(width, height * 0.6))
	var content_height := int(minf(height, width / 0.6))
	var crop := Rect2i((width - content_width) / 2, (height - content_height) / 2, content_width, content_height)
	full.get_region(crop).save_png(output.path_join(label + ".png"))
	print("Captured ", label, " from ", full.get_size())
