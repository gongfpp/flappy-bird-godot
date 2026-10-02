extends SceneTree
## Headless scene/input integration. Use tests/run_integration.sh to isolate the
## default Store created by the real game scene before _ready().

const MainScene = preload("res://main.tscn")
const Flight = preload("res://scripts/flight_model.gd")
const Store = preload("res://scripts/save_store.gd")
const EPSILON := 0.0001
const PLAY_POINT := Vector2(240.0, 350.0)

var game
var checks := 0
var failures := 0
var cases := 0
var fixture_path := ""
var initial_node_count := 0
var initial_orphan_count := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if OS.get_environment("SKY_HOP_ISOLATED_TESTS") != "1" or OS.get_environment("XDG_DATA_HOME").is_empty():
		printerr("Run tests/run_integration.sh, or supply fresh XDG_DATA_HOME/XDG_CACHE_HOME directories and SKY_HOP_ISOLATED_TESTS=1.")
		quit(2)
		return
	print("Sky Hop input integration | Godot ", Engine.get_version_info().string)
	initial_node_count = get_node_count()
	initial_orphan_count = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	fixture_path = "user://integration_%s_%s.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	game = MainScene.instantiate()
	# Replace the default store before _ready; the launcher also isolates its
	# constructor's initial default-save read from the real user's data.
	game.save = Store.new(fixture_path)
	root.add_child(game)
	await process_frame
	await process_frame
	_run_case("real main scene initializes on actual frames", _test_initialization)
	# Real _ready/_process ran above. Make input assertions deterministic; step
	# the production _physics_process explicitly when a clock must advance.
	game.set_physics_process(false)
	game.set_process(false)
	_run_case("space begins and key echo/release cannot flap", _test_keyboard_start_echo)
	_run_case("P, Escape and Space pause/resume routing", _test_pause_keys)
	_run_case("window/application focus loss pauses without auto-resume", _test_focus)
	_run_case("mute keyboard and pointer do not flap or resume", _test_mute)
	_run_case("pointer pause/resume and inactive button regions", _test_pointer_pause)
	_run_case("death and click retry obey cooldown", _test_death_retry)
	_run_case("one touch owns input until matching release", _test_touch_ownership)
	_run_case("touch sound/pause controls do not flap", _test_touch_controls)
	_run_case("actual score/crash callbacks update presentation and save", _test_model_callbacks)
	await _test_cleanup()
	print("INTEGRATION RESULT: %s | %d cases | %d checks | %d failures" % ["PASS" if failures == 0 else "FAIL", cases, checks, failures])
	quit(0 if failures == 0 else 1)

func _run_case(label: String, test: Callable) -> void:
	cases += 1
	var before := failures
	test.call()
	print("%s %s" % ["PASS" if before == failures else "FAIL", label])

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("  ASSERTION FAILED: ", message)

func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= EPSILON, "%s (actual %s, expected %s)" % [message, actual, expected])

func _dispatch(event: InputEvent) -> void:
	# Go through the actual Viewport event pipeline, not private input methods.
	root.push_input(event, true)

func _key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	_dispatch(event)

func _mouse(pos: Vector2, pressed: bool = true, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.global_position = pos
	event.button_index = button
	event.pressed = pressed
	_dispatch(event)

func _touch(index: int, pressed: bool, pos: Vector2 = PLAY_POINT) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = pos
	_dispatch(event)

func _reset_round() -> void:
	game.model.reset()
	game.active_touch = -1
	game.particles.clear()
	game.trail.clear()
	game.flap_flash = 0.0
	game.hit_flash = 0.0
	game.new_best = false

func _begin_round() -> void:
	_reset_round()
	_key(KEY_SPACE)

func _test_initialization() -> void:
	_check(game.is_inside_tree() and game.is_node_ready(), "main scene completed _ready")
	_check(game.model.phase == Flight.Phase.READY, "scene is ready before input")
	_check(game.time > 0.0 and game.world_scroll > 0.0, "automatic presentation frames ran")
	_check(game.sounds.get_parent() == game, "sound bank is owned by scene")
	_check(game.sounds.players.size() == 4 and game.sounds.streams.size() == 4, "real audio resources initialize")
	_check(game.model.scored.is_connected(game._on_scored), "score callback is connected")
	_check(game.model.crashed.is_connected(game._on_crashed), "crash callback is connected")
	_check(root.focus_exited.is_connected(game._on_focus_lost), "window focus callback is connected")

func _test_keyboard_start_echo() -> void:
	_reset_round()
	_key(KEY_SPACE, false)
	_key(KEY_SPACE, true, true)
	_check(game.model.phase == Flight.Phase.READY, "release and echo cannot start")
	_key(KEY_SPACE)
	_check(game.model.phase == Flight.Phase.PLAYING, "space starts through unhandled input")
	_near(game.model.velocity, Flight.FLAP_SPEED, "space applies initial flap")
	_check(game.model.pipes.size() == 2, "space seeds actual gameplay pipes")
	_check(game.particles.size() == 4, "real flap presentation callback runs")
	game.model.velocity = 123.0
	var particles_before: int = game.particles.size()
	_key(KEY_SPACE, true, true)
	_key(KEY_SPACE, false)
	_near(game.model.velocity, 123.0, "held-key echo/release do not repeatedly flap")
	_check(game.particles.size() == particles_before, "echo/release do not duplicate particles")
	_key(KEY_SPACE)
	_near(game.model.velocity, Flight.FLAP_SPEED, "fresh press still flaps")
	_check(game.particles.size() == particles_before + 4, "fresh press produces one flap burst")

func _test_pause_keys() -> void:
	_begin_round()
	game.model.velocity = 111.0
	_key(KEY_P)
	_check(game.model.phase == Flight.Phase.PAUSED, "P pauses play")
	_key(KEY_P, true, true)
	_check(game.model.phase == Flight.Phase.PAUSED, "P echo cannot resume")
	var before_y: float = game.model.bird_y
	game._physics_process(0.5)
	_near(game.model.bird_y, before_y, "actual physics callback respects pause")
	_key(KEY_ESCAPE)
	_check(game.model.phase == Flight.Phase.PLAYING, "Escape resumes")
	_near(game.model.velocity, 111.0, "pause toggle does not flap")
	_key(KEY_ESCAPE)
	_check(game.model.phase == Flight.Phase.PAUSED, "Escape also pauses")
	_key(KEY_SPACE)
	_check(game.model.phase == Flight.Phase.PLAYING, "Space resumes paused flight")
	_near(game.model.velocity, 111.0, "Space resume does not add a flap")
	_reset_round()
	_key(KEY_P)
	_key(KEY_ESCAPE)
	_check(game.model.phase == Flight.Phase.READY, "pause keys cannot begin ready scene")

func _test_focus() -> void:
	_begin_round()
	_touch(4, true)
	_check(game.active_touch == 4, "touch is owned before focus loss")
	root.focus_exited.emit()
	_check(game.model.phase == Flight.Phase.PAUSED, "real window focus signal pauses")
	_check(game.active_touch == -1, "focus loss releases stale touch owner")
	root.focus_entered.emit()
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	game._physics_process(0.2)
	_check(game.model.phase == Flight.Phase.PAUSED, "focus return never auto-resumes")
	_key(KEY_P)
	_check(game.model.phase == Flight.Phase.PLAYING, "explicit user input resumes after focus return")
	game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(game.model.phase == Flight.Phase.PAUSED, "application focus-out notification pauses")
	_key(KEY_P)
	game.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	_check(game.model.phase == Flight.Phase.PAUSED, "application suspension notification pauses")
	game.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	_check(game.model.phase == Flight.Phase.PAUSED, "application resume also needs explicit input")

func _test_mute() -> void:
	_reset_round()
	var before_mute: bool = game.save.muted
	_key(KEY_M)
	_check(game.save.muted != before_mute, "M toggles persisted mute")
	_check(game.sounds.muted == game.save.muted, "audio and stored mute match")
	_check(Store.new(fixture_path).muted == game.save.muted, "mute reaches disk")
	_check(game.model.phase == Flight.Phase.READY, "mute does not start a round")
	_key(KEY_M, true, true)
	_check(game.save.muted != before_mute, "M echo does not toggle mute again")
	_begin_round()
	game.model.velocity = 87.0
	var particles_before: int = game.particles.size()
	before_mute = game.save.muted
	_mouse(game.SOUND_RECT.get_center())
	_check(game.save.muted != before_mute, "sound-button pointer toggles mute")
	_near(game.model.velocity, 87.0, "sound button does not flap")
	_check(game.particles.size() == particles_before, "sound button creates no flap particles")
	_key(KEY_P)
	_mouse(game.SOUND_RECT.get_center())
	_check(game.model.phase == Flight.Phase.PAUSED, "mute during pause does not resume")
	_near(game.model.velocity, 87.0, "paused mute preserves velocity")

func _test_pointer_pause() -> void:
	_begin_round()
	game.model.velocity = 99.0
	_mouse(game.PAUSE_RECT.get_center())
	_check(game.model.phase == Flight.Phase.PAUSED, "pointer pause icon pauses")
	_mouse(PLAY_POINT)
	_check(game.model.phase == Flight.Phase.PAUSED, "background click cannot resume")
	_mouse(game.RESUME_BUTTON.get_center(), false)
	_mouse(game.RESUME_BUTTON.get_center(), true, MOUSE_BUTTON_RIGHT)
	_check(game.model.phase == Flight.Phase.PAUSED, "release and right button do not resume")
	_mouse(game.RESUME_BUTTON.get_center())
	_check(game.model.phase == Flight.Phase.PLAYING, "resume button resumes")
	_near(game.model.velocity, 99.0, "resume button does not flap")
	_mouse(game.PAUSE_RECT.get_center())
	_mouse(game.PAUSE_RECT.get_center())
	_check(game.model.phase == Flight.Phase.PLAYING, "pause icon also resumes")

func _test_death_retry() -> void:
	_begin_round()
	game.model.bird_y = Flight.GROUND_Y - Flight.RADIUS
	game.model.velocity = 0.0
	game._physics_process(0.0)
	_check(game.model.phase == Flight.Phase.GAME_OVER, "actual physics dispatch reaches death")
	_check(game.hit_flash > 0.0 and game.screen_shake > 0.0, "real crash presentation runs")
	_mouse(game.RETRY_BUTTON.get_center())
	_check(game.model.phase == Flight.Phase.GAME_OVER, "immediate retry click is rejected")
	game._physics_process(Flight.RESTART_DELAY - 0.001)
	_mouse(game.RETRY_BUTTON.get_center())
	_check(game.model.phase == Flight.Phase.GAME_OVER, "pre-cooldown retry click is rejected")
	game._physics_process(0.002)
	_mouse(PLAY_POINT)
	_check(game.model.phase == Flight.Phase.GAME_OVER, "background click cannot retry after cooldown")
	game.trail.append({"pos": Vector2.ZERO, "life": 1.0})
	game.new_best = true
	_mouse(game.RETRY_BUTTON.get_center())
	_check(game.model.phase == Flight.Phase.PLAYING, "retry button starts after cooldown")
	_near(game.model.velocity, Flight.FLAP_SPEED, "retry supplies the initial flap")
	_check(game.model.score == 0 and game.model.pipes.size() == 2, "retry resets model run")
	_check(game.particles.is_empty() and game.trail.is_empty() and not game.new_best, "retry clears presentation state")

func _test_touch_ownership() -> void:
	_reset_round()
	_touch(0, true)
	_check(game.active_touch == 0, "first finger acquires ownership")
	_check(game.model.phase == Flight.Phase.PLAYING, "first finger starts flight")
	_near(game.model.velocity, Flight.FLAP_SPEED, "first finger flaps")
	game.model.velocity = 150.0
	var particles_before: int = game.particles.size()
	_touch(1, true)
	_check(game.active_touch == 0, "second finger cannot replace active finger")
	_near(game.model.velocity, 150.0, "second finger cannot flap")
	_check(game.particles.size() == particles_before, "second finger creates no burst")
	_touch(1, false)
	_check(game.active_touch == 0, "second-finger release cannot release first finger")
	_touch(0, true)
	_near(game.model.velocity, 150.0, "duplicate active-finger press is ignored")
	_touch(0, false)
	_check(game.active_touch == -1, "matching release clears ownership")
	_near(game.model.velocity, 150.0, "release itself does not flap")
	_touch(1, true)
	_check(game.active_touch == 1, "next finger press works after release")
	_near(game.model.velocity, Flight.FLAP_SPEED, "new owner produces a fresh flap")
	_touch(1, false)
	_check(game.active_touch == -1, "final release returns neutral ownership")

func _test_touch_controls() -> void:
	_begin_round()
	game.model.velocity = 73.0
	var before_mute: bool = game.save.muted
	_touch(2, true, game.SOUND_RECT.get_center())
	_check(game.save.muted != before_mute, "touch sound control toggles mute")
	_near(game.model.velocity, 73.0, "touch sound control does not flap")
	_touch(3, true, game.PAUSE_RECT.get_center())
	_check(game.model.phase == Flight.Phase.PLAYING, "second finger cannot activate pause control")
	_touch(2, false)
	_touch(3, true, game.PAUSE_RECT.get_center())
	_check(game.model.phase == Flight.Phase.PAUSED, "released owner lets next touch pause")
	_touch(3, false)
	_touch(4, true, game.RESUME_BUTTON.get_center())
	_check(game.model.phase == Flight.Phase.PLAYING, "touch resume button continues")
	_near(game.model.velocity, 73.0, "touch resume does not flap")
	_touch(4, false)

func _test_model_callbacks() -> void:
	_begin_round()
	game.save.best = 0
	game.model.pipes.clear()
	game.model.pipes.append({"x": Flight.BIRD_X - Flight.RADIUS - Flight.PIPE_WIDTH - Flight.CAP_OVERHANG - 1.0, "center": 351.0, "gap": 204.0, "passed": false})
	game.model.bird_y = 351.0
	game.model.velocity = 0.0
	game._physics_process(0.0)
	_check(game.model.score == 1, "real physics step crosses score threshold")
	_check(game.new_best and game.save.best == 1, "score signal sets best and new-best UI")
	_check(game.score_pop == 1.0, "score signal triggers score animation")
	_check(Store.new(fixture_path).best == 1, "score callback persists best")
	game.model.bird_y = Flight.GROUND_Y - Flight.RADIUS
	game._physics_process(0.0)
	_check(game.model.phase == Flight.Phase.GAME_OVER, "post-score ground contact crashes")
	_check(Store.new(fixture_path).best == 1, "crash callback preserves earned best")

func _test_cleanup() -> void:
	cases += 1
	var before := failures
	var scene_ref: WeakRef = weakref(game)
	var sound_ref: WeakRef = weakref(game.sounds)
	var model_ref: WeakRef = weakref(game.model)
	var save_ref: WeakRef = weakref(game.save)
	var audio_refs: Array[WeakRef] = []
	var stream_refs: Array[WeakRef] = []
	for stream in game.sounds.streams.values():
		stream_refs.append(weakref(stream))
	for player in game.sounds.players:
		player.stop()
		audio_refs.append(weakref(player))
	game.queue_free()
	game = null
	await process_frame
	# Audio stop/free is handed to the mixing thread. Let its queued playbacks
	# drain before checking resources or terminating the engine.
	await create_timer(0.35, true, false, true).timeout
	await process_frame
	_check(scene_ref.get_ref() == null and sound_ref.get_ref() == null, "scene and sound bank are released")
	_check(model_ref.get_ref() == null and save_ref.get_ref() == null, "model and store resources are released")
	for reference in audio_refs:
		_check(reference.get_ref() == null, "audio player is released with scene")
	for reference in stream_refs:
		_check(reference.get_ref() == null, "synthesized audio stream is released after mixer drain")
	_check(get_node_count() == initial_node_count, "node count returns to pre-scene baseline")
	_check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == initial_orphan_count, "orphan count returns to baseline")
	_check(not root.focus_exited.has_connections(), "scene focus signal connection is removed")
	if FileAccess.file_exists(fixture_path):
		_check(DirAccess.remove_absolute(fixture_path) == OK, "isolated save fixture is removed")
	print("%s scene/audio teardown leaves no orphan nodes" % ["PASS" if failures == before else "FAIL"])
