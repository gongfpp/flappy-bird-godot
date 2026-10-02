extends Node2D
## Presentation, input routing, original vector art, particles and sound.
## FlightModel owns gameplay rules; SaveStore owns resilient local settings.

const Model = preload("res://scripts/flight_model.gd")
const Store = preload("res://scripts/save_store.gd")
const Sounds = preload("res://scripts/sound_bank.gd")
const INK := Color("19273d")
const PAPER := Color("fff1cf")
const GOLD := Color("ffcb65")
const MINT := Color("8bcbb0")
const MUTED := Color("a5b5c9")
const PAUSE_RECT := Rect2(350, 23, 44, 44)
const SOUND_RECT := Rect2(403, 23, 44, 44)
const MAIN_BUTTON := Rect2(87, 510, 306, 64)
const RETRY_BUTTON := Rect2(111, 491, 258, 60)
const RESUME_BUTTON := Rect2(111, 434, 258, 60)

var model := Model.new()
var save := Store.new()
var sounds := Sounds.new()
var font: Font = ThemeDB.fallback_font
var time := 0.0
var world_scroll := 0.0
var flap_flash := 0.0
var hit_flash := 0.0
var score_pop := 0.0
var screen_shake := 0.0
var new_best := false
var particles: Array[Dictionary] = []
var trail: Array[Dictionary] = []
var trail_timer := 0.0
var mouse_position := Vector2(-100, -100)
var active_touch := -1
var reduced_motion := false
var debug_tag := "1.0.0"

func _ready() -> void:
	add_child(sounds)
	sounds.muted = save.muted
	model.scored.connect(_on_scored)
	model.crashed.connect(_on_crashed)
	get_window().focus_exited.connect(_on_focus_lost)
	RenderingServer.set_default_clear_color(Color("1a233a"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_focus_lost()

func _on_focus_lost() -> void:
	if model != null:
		model.pause()
	active_touch = -1

func _physics_process(delta: float) -> void:
	model.tick(delta)

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	time += dt
	if model.phase == Model.Phase.READY or model.phase == Model.Phase.PLAYING:
		world_scroll += dt * (model.speed() if model.phase == Model.Phase.PLAYING else 22.0)
	flap_flash = maxf(0.0, flap_flash - dt * 6.0)
	hit_flash = maxf(0.0, hit_flash - dt * 3.5)
	score_pop = maxf(0.0, score_pop - dt * 3.5)
	screen_shake = maxf(0.0, screen_shake - dt * 24.0)
	if model.phase != Model.Phase.PAUSED:
		for p in particles:
			p.life -= dt
			p.pos += p.vel * dt
			p.vel.y += 140.0 * dt
		particles = particles.filter(func(p: Dictionary) -> bool: return p.life > 0.0)
		for p in trail:
			p.life -= dt
			p.pos.x -= model.speed() * dt * 0.8
		trail = trail.filter(func(p: Dictionary) -> bool: return p.life > 0.0)
		if model.phase == Model.Phase.PLAYING:
			trail_timer += dt
			if trail_timer > 0.055:
				trail_timer = 0.0
				trail.append({"pos": Vector2(Model.BIRD_X - 19.0, model.bird_y + 4.0), "life": 0.32})
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_position = event.position
		var hovering := SOUND_RECT.has_point(mouse_position) or PAUSE_RECT.has_point(mouse_position) or _current_button().has_point(mouse_position)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hovering else Input.CURSOR_ARROW)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE, KEY_UP, KEY_W, KEY_ENTER, KEY_KP_ENTER:
				_primary_action()
			KEY_P, KEY_ESCAPE:
				_toggle_pause()
			KEY_M:
				_toggle_sound()
			KEY_R:
				if model.phase == Model.Phase.GAME_OVER:
					_restart()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pointer_action(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed and active_touch == -1:
			active_touch = event.index
			_pointer_action(event.position)
		elif not event.pressed and active_touch == event.index:
			active_touch = -1

func _current_button() -> Rect2:
	match model.phase:
		Model.Phase.READY: return MAIN_BUTTON
		Model.Phase.GAME_OVER: return RETRY_BUTTON
		Model.Phase.PAUSED: return RESUME_BUTTON
	return Rect2()

func _pointer_action(pos: Vector2) -> void:
	if SOUND_RECT.has_point(pos):
		_toggle_sound()
		return
	if PAUSE_RECT.has_point(pos) and model.phase != Model.Phase.READY and model.phase != Model.Phase.GAME_OVER:
		_toggle_pause()
		return
	if model.phase == Model.Phase.PAUSED:
		if RESUME_BUTTON.has_point(pos):
			_toggle_pause()
		return
	if model.phase == Model.Phase.GAME_OVER:
		if RETRY_BUTTON.has_point(pos):
			_restart()
		return
	_primary_action()

func _primary_action() -> void:
	if model.phase == Model.Phase.PAUSED:
		_toggle_pause()
	elif model.phase == Model.Phase.GAME_OVER:
		_restart()
	elif model.flap():
		flap_flash = 1.0
		sounds.play("flap")
		for i in range(4):
			particles.append({"pos": Vector2(Model.BIRD_X - 14.0, model.bird_y + 10.0), "vel": Vector2(-randf_range(30.0, 100.0), randf_range(12.0, 60.0)), "life": randf_range(0.2, 0.4), "color": GOLD, "size": randf_range(2.0, 4.0)})

func _restart() -> void:
	if model.restart():
		new_best = false
		particles.clear()
		trail.clear()
		flap_flash = 1.0
		sounds.play("flap")

func _toggle_pause() -> void:
	if model.phase == Model.Phase.PLAYING:
		model.pause()
	elif model.phase == Model.Phase.PAUSED:
		model.resume()
	else:
		return
	sounds.play("click")

func _toggle_sound() -> void:
	save.set_muted(not save.muted)
	sounds.muted = save.muted
	if not save.muted:
		sounds.play("click")

func _on_scored(value: int) -> void:
	score_pop = 1.0
	sounds.play("point")
	if save.record_score(value):
		new_best = true
	for i in range(14):
		particles.append({"pos": Vector2(Model.BIRD_X + 18.0, model.bird_y), "vel": Vector2(randf_range(-80.0, 115.0), randf_range(-130.0, 65.0)), "life": randf_range(0.3, 0.7), "color": GOLD if i % 2 == 0 else MINT, "size": randf_range(2.0, 4.0)})

func _on_crashed() -> void:
	hit_flash = 0.65
	screen_shake = 5.0
	sounds.play("hit")
	save.record_score(model.score)

func _draw() -> void:
	_draw_background()
	var shake := Vector2(sin(time * 80.0), cos(time * 93.0)) * screen_shake if not reduced_motion else Vector2.ZERO
	draw_set_transform(shake)
	for pipe in model.pipes:
		_draw_pipe(pipe)
	for p in trail:
		draw_circle(p.pos, 3.8 * p.life / 0.32, Color(GOLD, p.life * 0.55))
	for p in particles:
		draw_circle(p.pos, p.size, Color(p.color, clampf(p.life * 3.0, 0.0, 1.0)))
	_draw_ground()
	var bird_y := model.bird_y
	if model.phase == Model.Phase.READY:
		bird_y += sin(time * 3.6) * 9.0
	var tilt := clampf(model.velocity / 820.0, -0.35, 1.0) if model.phase != Model.Phase.READY else -0.08
	_draw_bird(Vector2(Model.BIRD_X, bird_y), tilt, 1.0)
	draw_set_transform(Vector2.ZERO)
	_draw_header()
	match model.phase:
		Model.Phase.READY: _draw_start()
		Model.Phase.PLAYING: _draw_score()
		Model.Phase.PAUSED:
			_draw_score()
			_draw_paused()
		Model.Phase.GAME_OVER:
			_draw_score()
			if model.dead_time >= Model.RESTART_DELAY:
				_draw_game_over()
	if hit_flash > 0.0:
		draw_rect(Rect2(0, 0, 480, 800), Color(PAPER, hit_flash * 0.45))

func _draw_background() -> void:
	# Painted dusk gradient, deliberately generated instead of using stock art.
	for y in range(0, 718, 3):
		var t := float(y) / 716.0
		var sky := Color("263650").lerp(Color("66808a"), pow(t, 1.25))
		draw_rect(Rect2(0, y, 480, 3), sky)
	# Sparse, warm starlight.
	for i in range(23):
		var x := fposmod(float(i * 113 + 37) - world_scroll * 0.035, 490.0) - 5.0
		var y := 85.0 + float((i * 79) % 326)
		var alpha := 0.2 + 0.23 * (0.5 + 0.5 * sin(time * 1.1 + i))
		draw_circle(Vector2(x, y), 1.0 if i % 3 != 0 else 1.6, Color(PAPER, alpha))
	draw_circle(Vector2(387, 172), 49, Color("f7d78d", 0.05))
	draw_circle(Vector2(387, 172), 39, Color("f7d78d", 0.07))
	draw_circle(Vector2(387, 172), 30, Color("edce91"))
	draw_circle(Vector2(377, 163), 30, Color("33465e"))
	_draw_cloud(Vector2(fposmod(76.0 - world_scroll * 0.11, 670.0) - 95.0, 143), 1.0, Color("819999", 0.15))
	_draw_cloud(Vector2(fposmod(460.0 - world_scroll * 0.07, 720.0) - 95.0, 352), 1.35, Color("b9bfa6", 0.15))
	_draw_cloud(Vector2(fposmod(190.0 - world_scroll * 0.16, 750.0) - 95.0, 452), 0.8, Color("cbd0ae", 0.13))
	# Three parallax mountain layers.
	_draw_hills(565.0, 62.0, 151.0, 0.08, Color("4e707b"))
	_draw_hills(626.0, 69.0, 191.0, 0.16, Color("3e6570"))
	_draw_hills(680.0, 41.0, 109.0, 0.28, Color("31535f"))
	for i in range(10):
		var x := fposmod(i * 67.0 - world_scroll * 0.35, 620.0) - 50.0
		var y := 665.0 + sin(i * 3.0) * 23.0
		_draw_pine(Vector2(x, y), 0.55 + float(i % 3) * 0.17, Color("284a55"))

func _draw_cloud(pos: Vector2, scale_value: float, color: Color) -> void:
	# One silhouette avoids translucent overlap seams between the cloud lobes.
	var outline := PackedVector2Array([Vector2(-17, 13)])
	for x in range(-17, 81, 2):
		var top := 13.0
		for lobe in [Vector3(0, 0, 17), Vector3(28, -11, 29), Vector3(60, 0, 20)]:
			var dx: float = float(x) - lobe.x
			if absf(dx) <= lobe.z:
				top = minf(top, lobe.y - sqrt(maxf(0.0, lobe.z * lobe.z - dx * dx)))
		outline.append(Vector2(x, top))
	outline.append(Vector2(80, 13))
	for i in range(outline.size()):
		outline[i] = pos + outline[i] * scale_value
	draw_colored_polygon(outline, color)

func _draw_hills(base: float, amplitude: float, wavelength: float, factor: float, color: Color) -> void:
	var points := PackedVector2Array([Vector2(-20, 800)])
	for x in range(-20, 521, 10):
		var height := sin((x + world_scroll * factor) / wavelength * PI) * amplitude
		points.append(Vector2(x, base + height))
	points.append(Vector2(520, 800))
	draw_colored_polygon(points, color)

func _draw_pine(pos: Vector2, scale_value: float, color: Color) -> void:
	var points := PackedVector2Array([Vector2(-16, 0), Vector2(-8, -17), Vector2(-13, -17), Vector2(-5, -33), Vector2(-9, -33), Vector2(0, -53), Vector2(9, -33), Vector2(5, -33), Vector2(13, -17), Vector2(8, -17), Vector2(16, 0)])
	for i in range(points.size()):
		points[i] = points[i] * scale_value + pos
	draw_colored_polygon(points, color)

func _draw_pipe(pipe: Dictionary) -> void:
	var x: float = pipe.x
	var top: float = pipe.center - pipe.gap * 0.5
	var bottom: float = pipe.center + pipe.gap * 0.5
	_draw_pipe_stem(Rect2(x, -8, Model.PIPE_WIDTH, top + 8), true)
	_draw_pipe_stem(Rect2(x, bottom, Model.PIPE_WIDTH, Model.GROUND_Y - bottom + 5), false)
	_draw_pipe_cap(Rect2(x - 6, top - 25, Model.PIPE_WIDTH + 12, 25))
	_draw_pipe_cap(Rect2(x - 6, bottom, Model.PIPE_WIDTH + 12, 25))

func _draw_pipe_stem(rect: Rect2, upper: bool) -> void:
	draw_rect(rect.grow(2), INK)
	draw_rect(rect, Color("568f81"))
	draw_rect(Rect2(rect.position + Vector2(5, 0), Vector2(11, rect.size.y)), Color("84b6a0"))
	draw_rect(Rect2(rect.position + Vector2(rect.size.x - 14, 0), Vector2(14, rect.size.y)), Color("37685f"))
	draw_line(rect.position + Vector2(20, 0), rect.position + Vector2(20, rect.size.y), Color("70a793"), 2)
	var anchor_y := rect.end.y - 56.0 if upper else rect.position.y + 56.0
	draw_line(Vector2(rect.position.x + 7, anchor_y), Vector2(rect.end.x - 8, anchor_y), Color("37685f"), 3)
	draw_line(Vector2(rect.position.x + 7, anchor_y + 3), Vector2(rect.end.x - 8, anchor_y + 3), Color("8ab09a", 0.5), 1)
	for bolt_x in [rect.position.x + 10.0, rect.end.x - 11.0]:
		draw_circle(Vector2(bolt_x, anchor_y - 8), 2.5, INK)
		draw_circle(Vector2(bolt_x - 0.5, anchor_y - 8.5), 1.0, Color("b4c5a3"))

func _draw_pipe_cap(rect: Rect2) -> void:
	_panel(rect, Color("78ab92"), 4, INK, 3)
	draw_rect(Rect2(rect.position + Vector2(4, 4), Vector2(rect.size.x - 8, 4)), Color("c2d5ad"))
	draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 6), Vector2(rect.size.x - 8, 4)), Color("37685f"))
	draw_line(rect.position + Vector2(13, 11), rect.position + Vector2(13, 17), Color("38675f"), 2)
	draw_line(rect.position + Vector2(rect.size.x - 13, 11), rect.position + Vector2(rect.size.x - 13, 17), Color("38675f"), 2)

func _draw_ground() -> void:
	draw_rect(Rect2(0, 714, 480, 86), INK)
	draw_rect(Rect2(0, 716, 480, 8), Color("b9c28e"))
	draw_rect(Rect2(0, 724, 480, 7), Color("6f9b79"))
	draw_rect(Rect2(0, 731, 480, 69), Color("d9ba83"))
	draw_rect(Rect2(0, 731, 480, 4), Color("e6cf9b"))
	for i in range(18):
		var x := fposmod(i * 34.0 - world_scroll, 578.0) - 34.0
		draw_line(Vector2(x, 717), Vector2(x + 10, 722), Color("e9dcb0"), 3)
	for i in range(26):
		var x := fposmod(i * 37.0 - world_scroll * 0.9, 540.0) - 30.0
		var y := 744.0 + float((i * 13) % 48)
		draw_line(Vector2(x, y), Vector2(x + 6 + i % 5, y), Color("ac956c", 0.48), 2)
	_text("GODOT  /  ORIGINAL ART & SOUND", Vector2(240, 778), 10, Color("685d4b"), true)

func _draw_bird(pos: Vector2, tilt: float, scale_value: float) -> void:
	draw_set_transform(pos, tilt, Vector2.ONE * scale_value)
	# Tail and tuft.
	draw_colored_polygon(PackedVector2Array([Vector2(-18, 2), Vector2(-32, -9), Vector2(-31, 6), Vector2(-20, 13)]), INK)
	draw_colored_polygon(PackedVector2Array([Vector2(-20, 3), Vector2(-28, -3), Vector2(-27, 5), Vector2(-20, 9)]), Color("e39f56"))
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -16), Vector2(-6, -30), Vector2(2, -22), Vector2(5, -29), Vector2(10, -15)]), INK)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, -17), Vector2(-4, -25), Vector2(3, -18), Vector2(5, -24), Vector2(7, -15)]), GOLD)
	draw_circle(Vector2.ZERO, 24, INK)
	draw_circle(Vector2.ZERO, 20.5, GOLD)
	draw_circle(Vector2(4, 8), 12.5, Color("ffe3a0"))
	# The wing changes angle for a readable flap, even without external animation.
	var wing_angle := -0.7 + flap_flash * 1.4 + (sin(time * 11.0) * 0.15 if model.phase == Model.Phase.READY else 0.0)
	var wing_center := Vector2(-10, 5)
	var wing_tip := wing_center + Vector2(-12, 3).rotated(wing_angle)
	draw_line(wing_center, wing_tip, INK, 17, true)
	draw_line(wing_center, wing_tip, Color("e6a354"), 11, true)
	draw_circle(Vector2(11, -7), 10, INK)
	draw_circle(Vector2(11, -7), 7.5, Color("fff8df"))
	if model.phase == Model.Phase.GAME_OVER:
		draw_line(Vector2(8, -11), Vector2(14, -5), INK, 2.5, true)
		draw_line(Vector2(14, -11), Vector2(8, -5), INK, 2.5, true)
	else:
		draw_circle(Vector2(14, -7), 3.3, INK)
		draw_circle(Vector2(14.5, -8.5), 1.0, PAPER)
	draw_colored_polygon(PackedVector2Array([Vector2(19, 0), Vector2(37, 6), Vector2(21, 13), Vector2(15, 9)]), INK)
	draw_colored_polygon(PackedVector2Array([Vector2(21, 4), Vector2(30, 6), Vector2(21, 9)]), Color("eb9063"))
	draw_set_transform(Vector2.ZERO)

func _draw_header() -> void:
	_text("SKY HOP", Vector2(30, 49), 20, PAPER)
	draw_circle(Vector2(164, 42), 2, Color(MINT, 0.5))
	_text("BEST  %02d" % save.best, Vector2(181, 47), 13, MINT)
	if model.phase == Model.Phase.PLAYING or model.phase == Model.Phase.PAUSED:
		_icon_button(PAUSE_RECT, PAUSE_RECT.has_point(mouse_position))
		if model.phase == Model.Phase.PAUSED:
			draw_colored_polygon(PackedVector2Array([Vector2(367, 35), Vector2(367, 55), Vector2(383, 45)]), PAPER)
		else:
			draw_rect(Rect2(365, 35, 5, 19), PAPER)
			draw_rect(Rect2(375, 35, 5, 19), PAPER)
	_icon_button(SOUND_RECT, SOUND_RECT.has_point(mouse_position))
	var center := SOUND_RECT.get_center()
	draw_colored_polygon(PackedVector2Array([center + Vector2(-12, -4), center + Vector2(-6, -4), center + Vector2(0, -10), center + Vector2(0, 10), center + Vector2(-6, 4), center + Vector2(-12, 4)]), PAPER)
	if save.muted:
		draw_line(center + Vector2(5, -5), center + Vector2(13, 5), PAPER, 2, true)
		draw_line(center + Vector2(13, -5), center + Vector2(5, 5), PAPER, 2, true)
	else:
		draw_arc(center + Vector2(0, 0), 8, -0.85, 0.85, 12, PAPER, 2, true)
		draw_arc(center + Vector2(0, 0), 14, -0.85, 0.85, 12, PAPER, 2, true)

func _draw_start() -> void:
	_text("ONE MORE FLIGHT", Vector2(240, 160), 12, MINT, true, 2.0)
	_text("SKY HOP", Vector2(240, 232), 61, INK, true, 1.0, Vector2(0, 5))
	_text("SKY HOP", Vector2(240, 232), 61, PAPER, true, 1.0)
	_text("A tiny bird. A big sky.", Vector2(240, 269), 18, Color("cbd4cd"), true)
	# A dotted arc shows the mechanic without obscuring the bird.
	for i in range(9):
		var t := float(i) / 8.0
		var point := Vector2(209.0 + t * 102.0, 351.0 - sin(t * PI) * 35.0)
		draw_circle(point, 2.0, Color(PAPER, 0.2 + 0.25 * t))
	draw_line(Vector2(303, 346), Vector2(313, 353), Color(PAPER, 0.55), 2, true)
	draw_line(Vector2(313, 353), Vector2(314, 340), Color(PAPER, 0.55), 2, true)
	_text("FIND YOUR RHYTHM", Vector2(240, 442), 12, Color("d4dacb"), true, 1.0)
	_button(MAIN_BUTTON, "LET'S FLY", true)
	_keycap(Rect2(160, 599, 72, 27), "SPACE")
	_text("or tap", Vector2(248, 618), 15, PAPER)
	_text("Slip through the pipes. Keep the sky.", Vector2(240, 662), 13, Color("d1d6c4"), true)

func _draw_score() -> void:
	var size := 57 + int(score_pop * 10.0)
	_text(str(model.score), Vector2(240, 145), size, INK, true, 0.0, Vector2(0, 4))
	_text(str(model.score), Vector2(240, 145), size, PAPER, true)
	if model.score == 0 and model.elapsed < 2.0 and model.phase == Model.Phase.PLAYING:
		_text("TAP TO FLAP", Vector2(240, 192), 12, Color(PAPER, maxf(0.0, 1.0 - model.elapsed / 2.0)), true, 1.0)

func _draw_game_over() -> void:
	draw_rect(Rect2(0, 0, 480, 716), Color(INK, 0.60))
	_panel(Rect2(63, 247, 354, 357), Color("f6e7c6"), 22, INK, 4)
	_text("FLIGHT COMPLETE", Vector2(240, 285), 12, Color("5b746e"), true, 1.6)
	_text("Nice flying!" if model.score > 0 else "Find your rhythm", Vector2(240, 329), 27, INK, true)
	var medal_color := Color("c9ac84")
	var medal_label := "ROOKIE"
	if model.score >= 5:
		medal_color = Color("c6d8d0")
		medal_label = "GLIDER"
	if model.score >= 10:
		medal_color = GOLD
		medal_label = "SKY ACE"
	if model.score >= 25:
		medal_color = MINT
		medal_label = "LEGEND"
	draw_circle(Vector2(135, 411), 37, INK)
	draw_circle(Vector2(135, 411), 33, medal_color)
	draw_arc(Vector2(135, 411), 28, 0, TAU, 60, Color(INK, 0.18), 2, true)
	_draw_star(Vector2(135, 410), 17, INK)
	_text(medal_label, Vector2(135, 466), 10, Color("586c65"), true, 0.5)
	_text("SCORE", Vector2(246, 376), 11, Color("688074"), true, 1.0)
	_text(str(model.score), Vector2(246, 425), 42, INK, true)
	_text("BEST", Vector2(336, 376), 11, Color("688074"), true, 1.0)
	_text(str(save.best), Vector2(336, 425), 42, INK, true)
	if new_best:
		_panel(Rect2(212, 440, 155, 25), Color("e3c573"), 9)
		_text("NEW PERSONAL BEST", Vector2(289, 457), 10, INK, true)
	else:
		_text("Every flap is a fresh start.", Vector2(292, 456), 11, Color("6d8178"), true)
	_button(RETRY_BUTTON, "FLY AGAIN", true)
	_text("SPACE / ENTER / R TO RETRY", Vector2(240, 578), 10, Color("65796f"), true, 0.3)
	if save.last_save_error != OK:
		_text("Best score is temporary: storage unavailable", Vector2(240, 641), 11, PAPER, true)

func _draw_paused() -> void:
	draw_rect(Rect2(0, 0, 480, 716), Color(INK, 0.68))
	_panel(Rect2(72, 292, 336, 239), Color("f6e7c6"), 22, INK, 4)
	_text("TAKE A BREATHER", Vector2(240, 331), 11, Color("5b746e"), true, 1.2)
	_text("Flight paused", Vector2(240, 375), 31, INK, true)
	_text("Your sky will wait.", Vector2(240, 408), 15, Color("66796d"), true)
	_button(RESUME_BUTTON, "KEEP FLYING", true)
	_text("P / ESC / SPACE TO RESUME", Vector2(240, 512), 10, Color("65796f"), true)

func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var a := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2(cos(a), sin(a)) * radius * (1.0 if i % 2 == 0 else 0.47))
	draw_colored_polygon(points, color)

func _button(rect: Rect2, label: String, primary: bool) -> void:
	var hovered := rect.has_point(mouse_position)
	_panel(Rect2(rect.position + Vector2(0, 5), rect.size), Color("16283a"), 15)
	_panel(rect, Color("ffdc8b") if hovered else GOLD, 15, INK, 3)
	draw_line(rect.position + Vector2(17, 6), rect.position + Vector2(rect.size.x - 17, 6), Color("fff0bc"), 2, true)
	_text(label, rect.get_center() + Vector2(-9, 8), 21 if primary else 17, INK, true, 0.8)
	var cx := rect.end.x - 31.0
	var cy := rect.get_center().y
	draw_line(Vector2(cx - 7, cy - 6), Vector2(cx, cy), INK, 2.5, true)
	draw_line(Vector2(cx, cy), Vector2(cx - 7, cy + 6), INK, 2.5, true)

func _icon_button(rect: Rect2, hovered: bool) -> void:
	_panel(rect, Color("516b7a") if hovered else Color("2e4259"), 12, Color("76908e", 0.36), 1)

func _keycap(rect: Rect2, label: String) -> void:
	_panel(Rect2(rect.position + Vector2(0, 3), rect.size), Color("223b49"), 6)
	_panel(rect, Color("93aaa1"), 6, Color("bfceba"), 1)
	_text(label, rect.get_center() + Vector2(0, 5), 11, INK, true, 0.7)

func _panel(rect: Rect2, color: Color, radius: int = 12, border: Color = Color.TRANSPARENT, border_width: int = 0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(border_width)
	draw_style_box(style, rect)

func _text(value: String, baseline: Vector2, size: int, color: Color, centered: bool = false, spacing: float = 0.0, offset: Vector2 = Vector2.ZERO) -> void:
	if spacing <= 0.0:
		var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, baseline + offset - Vector2(width * 0.5 if centered else 0.0, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		return
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing * (value.length() - 1)
	var cursor := baseline + offset - Vector2(width * 0.5 if centered else 0.0, 0)
	for character in value:
		draw_string(font, cursor, character, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		cursor.x += font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + spacing
