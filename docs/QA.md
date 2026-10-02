# Sky Hop 1.0.0 verification

Date: **2026-10-02 UTC**. This report applies to the runtime source hashes in [runtime-source.sha256](runtime-source.sha256). The repository commit containing that manifest identifies the reviewed source; no earlier screenshot or build is being presented as a deployed version.

## Verdict by layer

| Layer | Result | Evidence / limit |
| --- | --- | --- |
| Clean source import | PASS | Fresh copy without `.godot`; Godot import completed |
| Startup/script checks | PASS | Fresh source ran 180 headless frames without script or runtime errors |
| Rules and persistence | PASS | 22 cases, **2,429 assertions**, zero failures |
| Scene/input integration | PASS | 11 cases, **98 assertions**, zero failures; no shutdown resource leaks |
| Native graphics and interaction | PASS | Actual Linux/Compatibility window; manual start/flap, pause/resume, crash, retry button, mute UI and focus-loss pause |
| Native rendered traversal | PASS | Test driver sends ordinary Space input events and earns 4 points through real gameplay; 11 flaps over 934 physics frames, then pause and crash |
| Web export | PASS | Clean single-threaded release export with matching 4.6.3 templates; generated HTML, JS, WASM, PCK, worklets and images |
| Actual browser runtime | BLOCKED | Chromium refused the local test URL with `net::ERR_BLOCKED_BY_CLIENT`; browser execution, browser storage and browser audio are **not verified** |
| Audible sound output | BLOCKED | Native environment has no usable ALSA output device; four effects synthesize/load, mute routing passes, but listening quality is **not verified** |
| Published deployment | NOT TESTED | No game URL or Pages deployment is configured or claimed |
| Mobile devices / other OSes | NOT TESTED | Touch events are covered in integration tests; real iOS/Android hardware and Windows/macOS are not tested |

## Environment

- Godot: `4.6.3.stable.official.7d41c59c4`
- Export templates: `4.6.3.stable`, `web_nothreads_release.zip`
- Template SHA-256: `1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9`
- Renderer: Godot Compatibility; native OpenGL 4.5, Mesa 25.0.7, llvmpipe LLVM 19.1.7
- Browser attempted: Chromium `151.0.7922.173`, Debian 13
- Web preset: `Web`, `variant/thread_support=false`, WebGL 2 / Compatibility
- Native runtime warned that changing V-Sync is unavailable in its virtual graphics driver; this did not prevent play or screenshot capture
- No external code, art or audio dependencies were downloaded for the game

## Screenshots from the actual native renderer

The optional [capture_native.gd](../tests/capture_native.gd) driver sends real input events. It does not teleport the bird, force scores or substitute fake scenes. The four screenshots were captured after the final runtime changes; only export filtering and documentation changed afterward. Their hashes are listed in [screenshots.sha256](screenshots.sha256).

- [Ready screen](screenshots/native-ready.png)
- [Four-point flight](screenshots/native-playing.png)
- [Paused](screenshots/native-paused.png)
- [Game over and new personal best](screenshots/native-game-over.png)

The native game was also inspected in a wide 1180 × 812 desktop window with correct aspect-preserving side bars and working pointer hit locations. Captured content is 487 × 811 pixels; untouched full captures are retained in the local evidence folder. The crop removes only the viewport's one-pixel aspect-rounding edge, not game content.

## Commands actually run

From a fresh source copy without imported caches:

```sh
godot --headless --editor --path . --import
godot --headless --path . --quit-after 180
bash tests/run_tests.sh
bash tests/run_integration.sh
godot --headless --path . --export-release Web build/web/index.html
```

On a graphics-capable Linux session:

```sh
godot --path . --resolution 480x800
bash tests/capture_native.sh
```

The wrappers isolate save data so QA does not overwrite a player's personal best or settings. The native screenshot wrapper uses the Dummy audio driver intentionally; the separate manual run established the actual audio-device limitation.

## Coverage details

- Gravity and bounded velocity; upward impulses; top/ground collision
- Circular collision against stems and protruding pipe caps, including tangency and clear gaps
- Exactly-once scoring, post-collision scoring prevention and phase transitions
- Pipe spacing, gap bounds and five simulated minutes of generation; this fixture holds altitude and does not establish traversal
- Pause freezes model state; explicit resume; automatic focus-loss pause
- Crash cooldown blocks accidental immediate restart
- Best score/mute persistence; incomplete, corrupt, wrong-type and non-finite save recovery
- Large numerical scores are capped **before** conversion and before writing, preserving reload consistency
- Real scene input dispatch: keyboard repeat filtering, pointer button isolation, tap start, secondary-finger suppression and release handling
- Actual score/crash signal callbacks update UI and persistence
- Scene and synthesized audio resources release without orphan/leak warnings

Malformed-save tests intentionally trigger one labeled Godot `ConfigFile` parse diagnostic; the suite verifies recovery and passes. See [tests/README.md](../tests/README.md) for the distinction between expected fixture diagnostics and genuine failures.

## Artifact identity and limits

[web-artifacts.sha256](web-artifacts.sha256) records the locally exported release bytes. Build artifacts are excluded from git. A source repository or successful export is not proof of a playable hosted game. Browser acceptance must be completed on the actual authorized destination before claiming a web release.

No CI run, hosted URL, mobile-device pass, or audible sound pass is implied by this report.
