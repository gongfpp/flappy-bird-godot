extends SceneTree
## Dependency-free model/save regressions. Run with:
## godot --headless --path . --script tests/run_tests.gd
## Explicit preloads keep this runnable without an editor-generated class cache.

const Flight = preload("res://scripts/flight_model.gd")
const Saves = preload("res://scripts/save_store.gd")
const EPSILON := 0.0001

var checks := 0
var failures := 0
var cases := 0
var fixture_directory := ""
var fixture_files: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	fixture_directory = "user://rule_tests_%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]
	var directory_error := DirAccess.make_dir_recursive_absolute(fixture_directory)
	if directory_error != OK:
		printerr("Cannot create isolated test fixtures: ", error_string(directory_error))
		quit(2)
		return
	print("Sky Hop rule tests | Godot ", Engine.get_version_info().string)
	_run_case("initial state and idle tick", _test_initial_state)
	_run_case("start, flap, gravity and terminal velocity", _test_flight)
	_run_case("pause, resume and invalid actions", _test_pause_resume)
	_run_case("ceiling and ground collision", _test_world_bounds)
	_run_case("crash signal and restart cooldown", _test_restart)
	_run_case("reset clears a completed run", _test_reset)
	_run_case("pipe stems, caps, tangent and safe gap", _test_pipe_collision)
	_run_case("circle/rectangle edge and corner math", _test_circle_rectangle)
	_run_case("pipe scoring occurs once after full clearance", _test_scoring)
	_run_case("collision prevents score on the same pipe", _test_collision_before_scoring)
	_run_case("initial pipes and generation spacing", _test_generation)
	_run_case("seeded generation and safe center limits", _test_generation_limits)
	_run_case("difficulty is monotone and capped", _test_difficulty)
	_run_case("long-running generation keeps pipes bounded", _test_long_running_generation)
	_run_case("missing save uses defaults", _test_missing_save)
	_run_case("best score and mute survive reload", _test_save_roundtrip)
	_run_case("equal/lower scores do not replace best", _test_score_preservation)
	_run_case("record_score API clamps out-of-range input", _test_record_score_limits)
	_run_case("corrupt and incomplete saves recover", _test_corrupt_save)
	_run_case("wrong save value types recover", _test_wrong_save_types)
	_run_case("numeric save limits and finite validation", _test_numeric_save_limits)
	_run_case("write failures are observable", _test_save_failure)
	_cleanup()
	print("RESULT: %s | %d cases | %d checks | %d failures" % ["PASS" if failures == 0 else "FAIL", cases, checks, failures])
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

func _new_model(random_seed: int = 41):
	return Flight.new(random_seed)

func _playing_model():
	var model = _new_model()
	model.flap()
	model.pipes.clear()
	model.bird_y = 350.0
	model.velocity = 0.0
	return model

func _pipe(x: float, center: float = 350.0, gap: float = 204.0, passed: bool = false) -> Dictionary:
	return {"x": x, "center": center, "gap": gap, "passed": passed}

func _test_initial_state() -> void:
	var model = _new_model()
	_check(model.phase == Flight.Phase.READY, "starts ready")
	_near(model.bird_y, 351.0, "initial bird position")
	_near(model.velocity, 0.0, "initial velocity")
	_check(model.score == 0 and model.pipes.is_empty(), "no score or pipes before start")
	model.tick(10.0)
	_check(model.phase == Flight.Phase.READY, "idle tick stays ready")
	_near(model.bird_y, 351.0, "idle tick does not move bird")
	_near(model.elapsed, 0.0, "idle tick does not advance play time")
	_check(not model.restart(), "cannot restart before death")

func _test_flight() -> void:
	var model = _new_model()
	_check(model.flap(), "first flap starts game")
	_check(model.phase == Flight.Phase.PLAYING, "first flap enters playing")
	_near(model.velocity, Flight.FLAP_SPEED, "flap applies upward impulse")
	_check(model.pipes.size() == 2, "start seeds two pipes")
	var start_y: float = model.bird_y
	var delta := 1.0 / 120.0
	model.tick(delta)
	_near(model.velocity, Flight.FLAP_SPEED + Flight.GRAVITY * delta, "gravity changes velocity")
	_near(model.bird_y, start_y + model.velocity * delta, "semi-implicit position integration")
	_check(model.bird_y < start_y, "first frame rises")
	_near(model.elapsed, delta, "play time advances")
	model.velocity = 250.0
	_check(model.flap(), "flap works during play")
	_near(model.velocity, Flight.FLAP_SPEED, "repeated flap resets impulse")
	_check(model.pipes.size() == 2, "repeated flap does not reseed pipes")
	model.pipes.clear()
	model.bird_y = 350.0
	model.velocity = Flight.MAX_FALL_SPEED - 1.0
	model.tick(delta)
	_near(model.velocity, Flight.MAX_FALL_SPEED, "fall speed is capped")

func _test_pause_resume() -> void:
	var ready = _new_model()
	ready.pause()
	ready.resume()
	_check(ready.phase == Flight.Phase.READY, "pause/resume cannot start ready game")
	var model = _new_model()
	model.flap()
	model.tick(0.01)
	model.pause()
	var y: float = model.bird_y
	var velocity: float = model.velocity
	var elapsed: float = model.elapsed
	var original_pipes: Array = model.pipes.duplicate(true)
	_check(model.phase == Flight.Phase.PAUSED, "pause enters paused state")
	_check(not model.flap(), "paused flap is ignored")
	_check(not model.restart(), "paused restart is ignored")
	model.pause()
	model.tick(20.0)
	_near(model.bird_y, y, "paused bird is frozen")
	_near(model.velocity, velocity, "paused velocity is frozen")
	_near(model.elapsed, elapsed, "paused play clock is frozen")
	_check(model.pipes == original_pipes, "paused pipes are frozen")
	model.resume()
	model.resume()
	_check(model.phase == Flight.Phase.PLAYING, "resume returns to play")
	model.tick(0.01)
	_check(model.bird_y != y and model.elapsed > elapsed, "resumed game progresses")

func _test_world_bounds() -> void:
	for edge in [Flight.RADIUS, Flight.GROUND_Y - Flight.RADIUS]:
		var model = _playing_model()
		model.bird_y = edge
		model.tick(0.0)
		_check(model.phase == Flight.Phase.GAME_OVER, "world-edge tangent is a collision at %s" % edge)
		_near(model.bird_y, edge, "world collision clamps at contact")
	for y in [Flight.RADIUS + 0.01, Flight.GROUND_Y - Flight.RADIUS - 0.01]:
		var model = _playing_model()
		model.bird_y = y
		model.tick(0.0)
		_check(model.phase == Flight.Phase.PLAYING, "bird just inside world bounds survives")
	var falling = _playing_model()
	falling.bird_y = Flight.GROUND_Y - Flight.RADIUS - 1.0
	falling.velocity = Flight.MAX_FALL_SPEED
	falling.tick(0.1)
	_near(falling.bird_y, Flight.GROUND_Y - Flight.RADIUS, "overshooting ground is clamped")
	_check(falling.phase == Flight.Phase.GAME_OVER, "ground overshoot crashes")

func _test_restart() -> void:
	var model = _playing_model()
	var crash_events: Array = []
	model.crashed.connect(func(): crash_events.append(true))
	model.bird_y = Flight.RADIUS
	model.tick(0.0)
	_check(crash_events.size() == 1, "one crash signal is emitted")
	_check(not model.flap(), "flap after death is ignored")
	model.pause()
	model.resume()
	_check(model.phase == Flight.Phase.GAME_OVER, "pause/resume cannot escape death")
	_check(not model.restart(), "instant restart is rejected")
	model.tick(Flight.RESTART_DELAY - 0.001)
	_check(not model.restart(), "restart just before cooldown is rejected")
	_check(crash_events.size() == 1, "dead ticks do not repeat crash signal")
	model.tick(0.002)
	_check(model.restart(), "restart after cooldown succeeds")
	_check(model.phase == Flight.Phase.PLAYING, "restart starts a fresh round")
	_check(model.score == 0 and model.pipes.size() == 2, "restart resets score and pipes")
	_near(model.bird_y, 351.0, "restart restores bird position")
	_near(model.velocity, Flight.FLAP_SPEED, "restart includes initial flap")
	_near(model.dead_time, 0.0, "restart clears death timer")
	_near(model.elapsed, 0.0, "restart clears play clock")
	var boundary = _playing_model()
	boundary.bird_y = Flight.RADIUS
	boundary.tick(0.0)
	boundary.tick(Flight.RESTART_DELAY)
	_check(boundary.restart(), "restart is accepted at exact cooldown boundary")

func _test_reset() -> void:
	var model = _new_model()
	model.flap()
	model.score = 8
	model.elapsed = 22.0
	model.dead_time = 0.4
	model.bird_y = 500.0
	model.velocity = 99.0
	model.reset()
	_check(model.phase == Flight.Phase.READY, "reset returns ready")
	_check(model.score == 0 and model.pipes.is_empty(), "reset clears run data")
	_near(model.elapsed + model.dead_time + model.velocity, 0.0, "reset clears timers and velocity")
	_near(model.bird_y, 351.0, "reset restores position")
	model.flap()
	_near(model.pipes[0].center, 355.0, "reset preserves accessible first gap")

func _test_pipe_collision() -> void:
	var model = _new_model()
	var pipe := _pipe(Flight.BIRD_X)
	model.bird_y = pipe.center
	_check(not model.collides_with_pipe(pipe), "middle of gap is safe")
	var top: float = pipe.center - pipe.gap * 0.5
	var bottom: float = pipe.center + pipe.gap * 0.5
	model.bird_y = top + Flight.RADIUS
	_check(model.collides_with_pipe(pipe), "top cap tangent collides")
	model.bird_y += 0.01
	_check(not model.collides_with_pipe(pipe), "just inside top gap is safe")
	model.bird_y = bottom - Flight.RADIUS
	_check(model.collides_with_pipe(pipe), "bottom cap tangent collides")
	model.bird_y -= 0.01
	_check(not model.collides_with_pipe(pipe), "just inside bottom gap is safe")
	model.bird_y = 100.0
	_check(model.collides_with_pipe(pipe), "upper stem collides")
	model.bird_y = 620.0
	_check(model.collides_with_pipe(pipe), "lower stem collides")
	# Center is 22 px from stem: only the protruding 6 px cap can touch.
	pipe.x = Flight.BIRD_X + Flight.RADIUS + Flight.CAP_OVERHANG
	model.bird_y = top - 12.0
	_check(model.collides_with_pipe(pipe), "leading top cap overhang participates in collision")
	model.bird_y = bottom + 12.0
	_check(model.collides_with_pipe(pipe), "leading bottom cap overhang participates in collision")
	pipe.x += 0.01
	_check(not model.collides_with_pipe(pipe), "outside cap edge is safe")
	pipe.x = Flight.BIRD_X - Flight.RADIUS - Flight.PIPE_WIDTH - Flight.CAP_OVERHANG
	model.bird_y = top - 12.0
	_check(model.collides_with_pipe(pipe), "trailing cap overhang participates in collision")
	pipe.x -= 0.01
	_check(not model.collides_with_pipe(pipe), "outside trailing cap edge is safe")
	model.bird_y = top + Flight.RADIUS - 1.0
	pipe.x = Flight.BIRD_X
	model.phase = Flight.Phase.PLAYING
	model.pipes.append(pipe)
	model.tick(0.0)
	_check(model.phase == Flight.Phase.GAME_OVER, "tick integrates pipe collision into death")

func _test_circle_rectangle() -> void:
	var rectangle := Rect2(10.0, 10.0, 20.0, 20.0)
	_check(Flight.circle_hits_rect(Vector2(20.0, 20.0), 1.0, rectangle), "center inside rectangle hits")
	_check(Flight.circle_hits_rect(Vector2(5.0, 20.0), 5.0, rectangle), "side tangent hits")
	_check(not Flight.circle_hits_rect(Vector2(4.99, 20.0), 5.0, rectangle), "separated side misses")
	_check(Flight.circle_hits_rect(Vector2(7.0, 6.0), 5.0, rectangle), "3-4-5 corner tangent hits")
	_check(not Flight.circle_hits_rect(Vector2(6.0, 6.0), 5.0, rectangle), "corner bounding boxes alone do not count as collision")

func _test_scoring() -> void:
	var model = _playing_model()
	var events: Array[int] = []
	model.scored.connect(func(value: int): events.append(value))
	var threshold: float = Flight.BIRD_X - Flight.RADIUS - Flight.PIPE_WIDTH - Flight.CAP_OVERHANG
	model.pipes.append(_pipe(threshold))
	model.tick(0.0)
	_check(model.score == 0 and events.is_empty(), "touching clearance boundary does not score")
	model.pipes[0].x -= 0.01
	model.tick(0.0)
	_check(model.score == 1 and events == [1], "cleared pipe emits score one")
	_check(model.pipes[0].passed, "cleared pipe is marked passed")
	for frame in 10:
		model.tick(0.0)
	_check(model.score == 1 and events.size() == 1, "same pipe never scores twice")
	model.pipes.append(_pipe(threshold - 1.0))
	model.tick(0.0)
	_check(model.score == 2 and events == [1, 2], "next pipe emits cumulative score")

func _test_collision_before_scoring() -> void:
	var model = _playing_model()
	var events: Array[int] = []
	model.scored.connect(func(value: int): events.append(value))
	model.pipes.append(_pipe(Flight.BIRD_X - Flight.PIPE_WIDTH))
	model.bird_y = 200.0
	model.tick(0.0)
	_check(model.phase == Flight.Phase.GAME_OVER, "intersecting pipe crashes")
	_check(model.score == 0 and events.is_empty(), "collision does not award that pipe")

func _test_generation() -> void:
	var model = _new_model()
	model.flap()
	_near(model.pipes[0].x, 580.0, "first pipe gives runway")
	_near(model.pipes[0].center, 355.0, "first pipe has known center")
	_near(model.pipes[1].x - model.pipes[0].x, Flight.PIPE_SPACING, "initial horizontal spacing")
	_near(model.pipes[0].gap, model.gap_size(), "initial gap matches difficulty")
	var before_x: float = model.pipes[0].x
	model.tick(1.0 / 120.0)
	_near(before_x - model.pipes[0].x, 166.0 / 120.0, "pipes move at game speed")
	# Exercise the spawn threshold with a safely centered bird.
	model.pipes.clear()
	model.pipes.append(_pipe(Flight.WIDTH + 40.0))
	model.tick(0.0)
	_check(model.pipes.size() == 1, "no spawn at exact threshold")
	model.pipes[0].x -= 0.01
	model.tick(0.0)
	_check(model.pipes.size() == 2, "spawn when final pipe crosses threshold")
	_near(model.pipes[1].x - model.pipes[0].x, Flight.PIPE_SPACING, "new spawn maintains spacing")

func _test_generation_limits() -> void:
	var first = _new_model(2718)
	var second = _new_model(2718)
	first.flap()
	second.flap()
	_check(first.pipes == second.pipes, "same seed produces same initial pipes")
	var old_center: float = first.pipes[-1].center
	for index in 400:
		first.score = index
		second.score = index
		first._add_pipe(900.0 + index * Flight.PIPE_SPACING)
		second._add_pipe(900.0 + index * Flight.PIPE_SPACING)
		var pipe: Dictionary = first.pipes[-1]
		_check(pipe == second.pipes[-1], "seeded generated pipe %d matches" % index)
		_check(pipe.center - pipe.gap * 0.5 >= 164.0 - EPSILON, "top gap edge has minimum clearance")
		_check(pipe.center + pipe.gap * 0.5 <= Flight.GROUND_Y - 118.0 + EPSILON, "bottom gap edge has minimum clearance")
		_check(absf(pipe.center - old_center) <= 122.0 + EPSILON, "successive vertical gaps stay within jump limit")
		_near(pipe.gap, first.gap_size(), "new pipe snapshots current difficulty")
		old_center = pipe.center

func _test_difficulty() -> void:
	var model = _new_model()
	_near(model.speed(), 166.0, "initial speed")
	_near(model.gap_size(), 204.0, "initial gap")
	var previous_speed := model.speed()
	var previous_gap := model.gap_size()
	for score_value in range(1, 101):
		model.score = score_value
		var current_speed: float = model.speed()
		var current_gap: float = model.gap_size()
		_check(current_speed >= previous_speed and current_speed <= 200.0, "speed increases only to cap")
		_check(current_gap <= previous_gap and current_gap >= 178.0, "gap decreases only to floor")
		previous_speed = current_speed
		previous_gap = current_gap
	model.score = 1000000
	_near(model.speed(), 200.0, "large score retains max speed")
	_near(model.gap_size(), 178.0, "large score retains min gap")

func _test_long_running_generation() -> void:
	var model = _new_model(314159)
	model.flap()
	var max_pipe_count := 0
	var safe := true
	var ordered := true
	var well_spaced := true
	var no_stale_pipe := true
	var bounded := true
	var gap_valid := true
	# Isolate spawning/scoring from player skill: reset altitude/velocity each
	# step to the nearest gap. This does not establish real input playability.
	var delta := 1.0 / 120.0
	for frame in 120 * 300:
		var target: float = 350.0
		for pipe in model.pipes:
			if pipe.x + Flight.PIPE_WIDTH + Flight.CAP_OVERHANG >= Flight.BIRD_X - Flight.RADIUS:
				target = pipe.center
				break
		model.bird_y = target
		model.velocity = 0.0
		model.tick(delta)
		if model.phase != Flight.Phase.PLAYING:
			safe = false
			break
		max_pipe_count = maxi(max_pipe_count, model.pipes.size())
		bounded = bounded and not model.pipes.is_empty() and model.pipes.size() <= 5
		for index in model.pipes.size():
			var pipe: Dictionary = model.pipes[index]
			gap_valid = gap_valid and pipe.gap >= 178.0 and pipe.gap <= 204.0
			no_stale_pipe = no_stale_pipe and pipe.x + Flight.PIPE_WIDTH + Flight.CAP_OVERHANG >= -24.0
			if index > 0:
				ordered = ordered and pipe.x > model.pipes[index - 1].x
				well_spaced = well_spaced and absf(pipe.x - model.pipes[index - 1].x - Flight.PIPE_SPACING) < 0.001
	_check(safe, "spawn simulation survives full five minutes")
	_check(model.elapsed >= 300.0 - 0.001, "long simulation advances five minutes")
	_check(model.score > 200, "long simulation scores hundreds of generated pipes")
	_check(bounded, "pipe list stays nonempty and bounded (max %d)" % max_pipe_count)
	_check(ordered and well_spaced, "long-run pipes remain ordered at fixed spacing")
	_check(no_stale_pipe, "fully offscreen pipes are removed")
	_check(gap_valid, "long-run pipe gaps respect difficulty bounds")

func _fixture(name: String) -> String:
	var path := fixture_directory.path_join(name + ".cfg")
	if not fixture_files.has(path):
		fixture_files.append(path)
	return path

func _write_config(path: String, score_value: Variant, muted_value: Variant) -> void:
	var config := ConfigFile.new()
	config.set_value("scores", "best", score_value)
	config.set_value("settings", "muted", muted_value)
	_check(config.save(path) == OK, "fixture can be written")

func _test_missing_save() -> void:
	var store = Saves.new(_fixture("missing"))
	_check(store.best == 0 and not store.muted, "missing file uses safe defaults")
	_check(store.last_save_error == OK, "fresh store has no write error")

func _test_save_roundtrip() -> void:
	var path := _fixture("roundtrip")
	var store = Saves.new(path)
	_check(store.record_score(12), "new record is accepted")
	_check(store.last_save_error == OK, "record saves successfully")
	store.set_muted(true)
	_check(store.last_save_error == OK, "mute saves successfully")
	var reloaded = Saves.new(path)
	_check(reloaded.best == 12 and reloaded.muted, "best and mute reload together")
	reloaded.set_muted(false)
	var unmuted = Saves.new(path)
	_check(unmuted.best == 12 and not unmuted.muted, "unmute persists without losing best")

func _test_score_preservation() -> void:
	var path := _fixture("preserve")
	var store = Saves.new(path)
	store.record_score(24)
	store.set_muted(true)
	_check(not store.record_score(24), "equal score is not a record")
	_check(not store.record_score(3), "lower score is not a record")
	_check(not store.record_score(-4), "negative score is not a record")
	_check(store.best == 24, "non-record scores preserve best")
	var reloaded = Saves.new(path)
	_check(reloaded.best == 24 and reloaded.muted, "non-record attempts preserve disk data")
	var saved_text := FileAccess.get_file_as_string(path)
	_check(not reloaded.record_score(2), "lower score after loading a valid save is rejected")
	_check(FileAccess.get_file_as_string(path) == saved_text, "rejected score leaves valid save byte-for-byte unchanged")
	_check(Saves.new(path).best == 24, "best remains intact after loaded-store lower score")
	_check(store.record_score(25), "higher score becomes record")
	_check(Saves.new(path).best == 25, "new higher record reaches disk")

func _test_record_score_limits() -> void:
	# These inputs exercise the public API contract. Normal gameplay would need
	# an impractically long run to reach these scores; this is save robustness.
	var values: Array[int] = [1500000, 9223372036854775807]
	for index in values.size():
		var path := _fixture("record_limit_%d" % index)
		var store = Saves.new(path)
		_check(not store.record_score(-1), "negative API score is rejected")
		_check(not store.record_score(0), "zero is not a new record")
		_check(store.record_score(values[index]), "positive oversized API score establishes a record")
		_check(store.best == 1000000, "API best is clamped consistently with loaded best")
		_check(store.last_save_error == OK, "oversized API score saves safely")
		_check(Saves.new(path).best == store.best, "oversized API score is stable across reload")

func _test_corrupt_save() -> void:
	var path := _fixture("corrupt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "corrupt fixture can be opened")
	if file != null:
		file.store_string("[scores\nbest = ? this is deliberately invalid")
		file.close()
	# ConfigFile emits one expected parse diagnostic for this fixture.
	print("  EXPECTED DIAGNOSTIC: invalid ConfigFile syntax in the next load")
	var store = Saves.new(path)
	_check(store.best == 0 and not store.muted, "corrupt syntax recovers to defaults")
	_check(store.record_score(7), "play can establish a record after corruption")
	_check(Saves.new(path).best == 7, "saving replaces corrupt content with valid data")
	var empty_path := _fixture("empty")
	var empty := ConfigFile.new()
	_check(empty.save(empty_path) == OK, "empty fixture can be saved")
	store = Saves.new(empty_path)
	_check(store.best == 0 and not store.muted, "missing sections use defaults")
	store.best = 80
	store.muted = true
	store.load_data()
	_check(store.best == 0 and not store.muted, "reload resets stale in-memory values before reading")

func _test_wrong_save_types() -> void:
	var bad_scores: Array = ["999", true, false, [], {"best": 9}, Vector2(3, 4)]
	for index in bad_scores.size():
		var path := _fixture("wrong_score_%d" % index)
		_write_config(path, bad_scores[index], true)
		var store = Saves.new(path)
		_check(store.best == 0, "wrong best type defaults to zero: %s" % type_string(typeof(bad_scores[index])))
		_check(store.muted, "bad best does not discard a valid mute setting")
	var bad_mutes: Array = ["true", 1, 0, 1.0, [], {"muted": true}]
	for index in bad_mutes.size():
		var path := _fixture("wrong_mute_%d" % index)
		_write_config(path, 42, bad_mutes[index])
		var store = Saves.new(path)
		_check(not store.muted, "non-bool mute defaults to false: %s" % type_string(typeof(bad_mutes[index])))
		_check(store.best == 42, "bad mute does not discard a valid best score")

func _test_numeric_save_limits() -> void:
	var values: Array = [-5, -2.5, 0, 19.9, 1000000, 1500000, 1.0e30, INF, -INF, NAN]
	var expected: Array[int] = [0, 0, 0, 19, 1000000, 1000000, 1000000, 0, 0, 0]
	for index in values.size():
		var path := _fixture("numeric_%d" % index)
		_write_config(path, values[index], false)
		var store = Saves.new(path)
		_check(store.best == expected[index], "numeric best %s sanitizes to %d (got %d)" % [values[index], expected[index], store.best])

func _test_save_failure() -> void:
	# A missing parent is deterministic and does not rely on OS permission bits.
	var store = Saves.new(fixture_directory.path_join("missing_parent/save.cfg"))
	_check(store.record_score(8), "record is still recognized in memory when disk is unavailable")
	_check(store.best == 8, "disk failure does not stop the current session")
	_check(store.last_save_error != OK, "write failure is exposed to the caller")
	store.path = _fixture("recovered_write")
	store.save_data()
	_check(store.last_save_error == OK, "subsequent successful save clears write error")
	_check(Saves.new(store.path).best == 8, "recovered save retains in-memory record")

func _cleanup() -> void:
	# Only remove files created by this invocation; never open the real save.
	for path in fixture_files:
		if FileAccess.file_exists(path):
			var error := DirAccess.remove_absolute(path)
			_check(error == OK, "temporary fixture cleanup succeeds")
	var error := DirAccess.remove_absolute(fixture_directory)
	_check(error == OK, "temporary fixture directory cleanup succeeds")
