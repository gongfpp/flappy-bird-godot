# Rule and save regression tests

This dependency-free suite loads the production `flight_model.gd` and
`save_store.gd` directly. It needs Godot 4.6 and does not require an editor import,
third-party test framework, display server, or generated class-name cache.

From the project root:

```sh
godot --headless --path . --script tests/run_tests.gd
```

The final line reports the number of cases, assertions, and failures. Exit status
is `0` on success, `1` on assertion failure, or `2` if the fixture directory cannot
be created. A GDScript parse/startup error also produces a nonzero engine exit.

## Isolated user data

The suite never opens the game's default `user://sky_hop.cfg` save. Every run
creates a uniquely named fixture directory under `user://`, passes explicit paths
to `SaveStore`, and removes only its own fixture files afterward.

For an additionally isolated user-data directory on Linux/CI, use the launcher:

```sh
./tests/run_tests.sh
# Optionally select an installed engine:
GODOT_BIN=godot ./tests/run_tests.sh
```

The launcher creates temporary `XDG_DATA_HOME` and `XDG_CACHE_HOME` directories and
removes them when the run ends. It does not install an engine or download anything.

One `ConfigFile parse error` diagnostic is **intentional**: the corrupt-syntax
fixture exercises graceful recovery. The runner labels that expected diagnostic
immediately before it occurs. Do not interpret this one error as a broken game or
silence all engine errors; the final result and exit code must still pass.

## Coverage

The suite contains 22 cases:

- Initial state and idle ticking
- Starting, flapping, gravity, integration, and terminal falling speed
- Pause/resume, frozen clocks and pipes, and actions in invalid phases
- Ceiling/ground contact, safe interior positions, and ground overshoot
- Single crash notification, cooldown rejection, exact-boundary restart, and reset
- Upper/lower stems, protruding caps on both sides, tangent contact, and safe gaps
- Circle/rectangle side and corner geometry, including a bounding-box false positive
- Scoring only after full trailing-cap clearance, once per pipe, with cumulative signals
- Collision before scoring the colliding pipe
- Initial runway, spawn threshold, pipe movement, and horizontal spacing
- Seed-reproducible generation, vertical gap limits, and bounded center changes
- Monotonic speed/gap difficulty with both caps
- Five simulated minutes at 120 Hz, hundreds of pipes, ordered and bounded lists,
  cleanup, and stable spacing
- Missing saves, best-score/mute round trips, and preserving best on lower/equal scores
- Invalid ConfigFile syntax, incomplete saves, and reset of stale in-memory state
- Incorrect score/mute types, negative/fractional/oversized numeric scores, and
  nonfinite values
- Out-of-range `record_score()` API input and consistent values across reload
  (a robustness boundary, not a realistically reachable normal gameplay score)
- Observable write failure and successful retry to a valid destination

For spawn-stress coverage, the test deliberately places the model bird in the
nearest safe gap every step. This isolates generation and scoring from player
skill. It is **not** a demonstration that normal flap inputs can navigate the game.

These tests do not exercise `game.gd`, real keyboard/mouse/touch input, graphics,
audio output, actual browser storage, web exports, or deployed builds. Those
require separate GUI and browser acceptance checks. Passing this suite alone is
not evidence that a published game is playable.

## Extending the suite

Add a function and register it with `_run_case()` in `_run()`. Use `_check()` or
`_near()` so failed assertions are accumulated and cause a nonzero exit. Create
save fixtures through `_fixture()` so only the current run's files are cleaned
up. Keep production scripts read-only during QA, and report failures instead of
weakening assertions to match defects.

## Scene and input integration

Run the complementary integration suite with:

```sh
./tests/run_integration.sh
```

`run_integration.gd` instantiates the production `main.tscn`, allows real frames
to complete scene initialization, then sends actual `InputEventKey`,
`InputEventMouseButton`, and `InputEventScreenTouch` objects through
`Viewport.push_input()`. It does not call the private input handlers directly or
replace the game script. This covers the real `_unhandled_input()` →
`_pointer_action()`/action routing described by the
[Godot Viewport API](https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-push-input).

The 11 integration cases cover:

- Scene initialization, generated sound resources, and connected callbacks
- Space start/flap, key-release suppression, and keyboard-echo suppression
- P/Escape pause and resume, Space resume without a new flap
- Window focus signals and application focus/suspend notifications, touch-owner
  reset on focus loss, and explicit-input-only resume
- Keyboard, mouse, and touch mute controls without accidental flapping/resume;
  mute persistence and audio/store agreement
- Pause/resume button routing and ignored background/right-button/release input
- Death through the production physics callback and click-retry cooldown
- First-finger ownership, second-finger suppression, matching release, and fresh
  touch recovery, including touch UI controls
- Actual score/crash signals updating UI state and persisted best score
- Scene, model, save store, audio players, and synthesized stream teardown, with
  node/orphan counts returning to baseline

After initial automatic frames, normal process/physics scheduling is disabled to
make assertions repeatable. Clock-dependent steps call the production
`_physics_process()` with explicit deltas. The focus notifications are injected
at the engine API boundary; no operating-system focus change is performed. Audio
is initialized and exercised using the headless driver, but audible output is
not assessed. The final teardown allows the audio mixing thread to drain before
checking stream weak references and exiting.

Use the launcher on Linux/CI: the real scene's field initializer constructs a
default SaveStore before it can be replaced, so the launcher isolates both that
initial read and all writes with fresh XDG directories. Direct execution requires
`SKY_HOP_ISOLATED_TESTS=1` plus an isolated `XDG_DATA_HOME` (and preferably
`XDG_CACHE_HOME`); otherwise the test exits with code 2 before instantiating the
scene. The launcher also treats any script/engine error or shutdown ObjectDB leak
warning as a failure, including diagnostics printed after the script has quit.

These are headless scene integration tests. They do not replace graphical,
physical-device, real operating-system focus, browser, export, or deployment QA.
The original 22-case rule suite remains separate and unchanged.
