class_name FlightModel
extends RefCounted
## Deterministic game rules. All distances are logical viewport pixels.
## Circle/rectangle collision is intentional: the bird's round body is the hitbox.

signal scored(value: int)
signal crashed

enum Phase { READY, PLAYING, PAUSED, GAME_OVER }
const WIDTH := 480.0
const HEIGHT := 800.0
const GROUND_Y := 716.0
const BIRD_X := 150.0
const RADIUS := 16.0
const PIPE_WIDTH := 76.0
const CAP_OVERHANG := 6.0
const PIPE_SPACING := 258.0
const GRAVITY := 990.0
const FLAP_SPEED := -345.0
const MAX_FALL_SPEED := 640.0
const RESTART_DELAY := 0.65

var phase: Phase = Phase.READY
var bird_y := 351.0
var velocity := 0.0
var score := 0
var elapsed := 0.0
var dead_time := 0.0
var pipes: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var seed_value: int = 0
var _last_gap := 355.0

func _init(random_seed: int = 0) -> void:
	seed_value = random_seed
	if random_seed == 0:
		rng.randomize()
	else:
		rng.seed = random_seed

func reset() -> void:
	phase = Phase.READY
	bird_y = 351.0
	velocity = 0.0
	score = 0
	elapsed = 0.0
	dead_time = 0.0
	pipes.clear()
	_last_gap = 355.0

func flap() -> bool:
	if phase == Phase.READY:
		phase = Phase.PLAYING
		_add_pipe(580.0, 355.0)
		_add_pipe(580.0 + PIPE_SPACING)
	elif phase != Phase.PLAYING:
		return false
	velocity = FLAP_SPEED
	return true

func pause() -> void:
	if phase == Phase.PLAYING:
		phase = Phase.PAUSED

func resume() -> void:
	if phase == Phase.PAUSED:
		phase = Phase.PLAYING

func restart() -> bool:
	if phase != Phase.GAME_OVER or dead_time < RESTART_DELAY:
		return false
	reset()
	return flap()

func speed() -> float:
	return minf(166.0 + score * 1.35, 200.0)

func gap_size() -> float:
	return maxf(204.0 - score * 1.7, 178.0)

func _add_pipe(x: float, forced_center: float = -1.0) -> void:
	var gap := gap_size()
	var center := forced_center
	if center < 0.0:
		center = clampf(_last_gap + rng.randf_range(-122.0, 122.0), 164.0 + gap * 0.5, GROUND_Y - 118.0 - gap * 0.5)
	_last_gap = center
	pipes.append({"x": x, "center": center, "gap": gap, "passed": false})

func tick(delta: float) -> void:
	if phase == Phase.GAME_OVER:
		dead_time += delta
		velocity = minf(velocity + GRAVITY * delta, MAX_FALL_SPEED)
		bird_y = minf(bird_y + velocity * delta, GROUND_Y - RADIUS)
		return
	if phase != Phase.PLAYING:
		return
	elapsed += delta
	velocity = minf(velocity + GRAVITY * delta, MAX_FALL_SPEED)
	bird_y += velocity * delta
	for pipe in pipes:
		pipe.x -= speed() * delta
	if bird_y - RADIUS <= 0.0 or bird_y + RADIUS >= GROUND_Y:
		bird_y = clampf(bird_y, RADIUS, GROUND_Y - RADIUS)
		_crash()
		return
	for pipe in pipes:
		if collides_with_pipe(pipe):
			_crash()
			return
		if not pipe.passed and pipe.x + PIPE_WIDTH + CAP_OVERHANG < BIRD_X - RADIUS:
			pipe.passed = true
			score += 1
			scored.emit(score)
	while not pipes.is_empty() and pipes[0].x + PIPE_WIDTH + CAP_OVERHANG < -24.0:
		pipes.pop_front()
	if not pipes.is_empty() and pipes[-1].x < WIDTH + 40.0:
		_add_pipe(float(pipes[-1].x) + PIPE_SPACING)

func collides_with_pipe(pipe: Dictionary) -> bool:
	var top: float = pipe.center - pipe.gap * 0.5
	var bottom: float = pipe.center + pipe.gap * 0.5
	var circle := Vector2(BIRD_X, bird_y)
	# Caps protrude six pixels beyond the pipe stems; use matching rectangles.
	return circle_hits_rect(circle, RADIUS, Rect2(pipe.x, 0.0, PIPE_WIDTH, top - 25.0)) \
		or circle_hits_rect(circle, RADIUS, Rect2(pipe.x - CAP_OVERHANG, top - 25.0, PIPE_WIDTH + 2.0 * CAP_OVERHANG, 25.0)) \
		or circle_hits_rect(circle, RADIUS, Rect2(pipe.x - CAP_OVERHANG, bottom, PIPE_WIDTH + 2.0 * CAP_OVERHANG, 25.0)) \
		or circle_hits_rect(circle, RADIUS, Rect2(pipe.x, bottom + 25.0, PIPE_WIDTH, GROUND_Y - bottom - 25.0))

static func circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_squared_to(closest) <= radius * radius

func _crash() -> void:
	if phase != Phase.PLAYING:
		return
	phase = Phase.GAME_OVER
	dead_time = 0.0
	crashed.emit()
