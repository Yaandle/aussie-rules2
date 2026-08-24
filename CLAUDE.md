# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A realistic-leaning 3D Aussie Rules football game in Godot 4.6 with Jolt
physics. Controller-first with full keyboard parity. Contests (marking,
tackling, ruck, bump) resolve through real physics simulation, never dice
rolls. Everything — models, animations, textures, SFX — is generated in
code; there is no imported art or audio, and `assets/audio/` stays
intentionally empty (see `scripts/autoload/audio_manager.gd`, which
synthesizes placeholder SFX).

`docs/RULES_REFERENCE.md` documents exactly which real AFL rules are
simplified for this milestone and why — read it before changing any rule
logic (marking distance, holding-the-ball, stand-the-mark, etc.).
`docs/FEATURE_AUDIT.md` is the current-state inventory (what works, what's
buggy, what's missing) and the live development roadmap — check it before
assuming a feature is unbuilt or before reporting one as done.
`docs/HANDOVER.md` is the full session-by-session build log.

There is a Python/Pygame prototype at `E:\aussie-rules_game` (outside this
repo) that stays the canonical rules reference for porting features
(formations, AI, throw-in, holding-the-ball). It proved the design but uses
abstract grid units on a 166x88 field; this project translates everything
to real SI units (metres/kg/seconds) on a real 165x135m oval.

## Running the game

No build step, no asset import. Open `project.godot` in Godot 4.6+ and
press F5 — `run/main_scene` is the main menu; pick FULL GAME to play a
match.

The Godot editor binary is not on PATH. Invoke it by full path:

```bash
"C:\Users\Bozzy\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" --headless --path "F:\dev\aussie-rules2" --quit-after 300
```

This is the standard headless smoke test — exits 0 with no output on
success. It only exercises the main menu unless a scene is also passed
positionally, e.g. `"res://scenes/modes/kick_to_kick.tscn"` before the
flags.

**Stale class-name cache**: if a freshly-added script with `class_name`
fails to resolve (`Could not find type "X" in the current scope`), Godot's
global class cache (`.godot/global_script_class_cache.cfg`) hasn't seen it
yet. Force a rescan with:

```bash
"C:\Users\Bozzy\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" --headless --editor --quit --path "F:\dev\aussie-rules2"
```

**For real physics verification** (not just parse-clean), never use
`--script extends SceneTree` — that mode does not bootstrap
`project.godot`'s `[autoload]` singletons, so any script referencing
`MatchState`/`GameState`/etc. fails to compile, and any scene whose root
script failed to compile silently instantiates as its bare base type
instead. Instead write a scratch `.tscn` + `Node3D`-derived `.gd` under
`res://` using `_ready()`/`_physics_process()`, instantiate real scenes
(`field.tscn`, `player.tscn`, `ball.tscn`) as children, optionally give a
`PlayerController` a scripted `PlayerBrain` subclass to drive it without
real input, and run it via the positional scene argument (goes through
normal project boot, autoloads included):

```bash
"...\Godot_v4.6-stable_win64_console.exe" --headless --path "F:\dev\aussie-rules2" "res://_scratch_test.tscn" --fixed-fps 60 --quit-after 1200
```

Always pass `--quit-after <N>` and call `get_tree().quit()` from the test
script once done. Add `--fixed-fps 60` for any multi-phase/multi-frame
scripted scenario — without it, physics steps only accumulate as real time
passes, and an unthrottled headless loop can burn through hundreds of
iterations with zero physics ticks, producing suspiciously empty output
with a clean exit code rather than an obvious error. A bare boot/parse
smoke test doesn't need `--fixed-fps`. Delete scratch test files when done
— they aren't part of the diff.

There is no other test suite, linter, or CI in this repo. Verification
means: headless boot cleanly, and/or a scripted physics scenario reaching
its expected end state.

## Architecture

**Autoloads** (`project.godot` `[autoload]`, load order matters — later
ones may depend on earlier ones being ready):
`InputManager` → `GameState` → `MatchState` → `CharacterProfile` →
`SceneWipe` → `Settings` → `AudioManager`.

- `InputManager` — keyboard/mouse/gamepad input normalization: per-action
  deadzone/curve, rumble, flick-gesture detection (used by bump), device
  auto-detect, `get_gait()`.
- `GameState` — phase/mode-level state.
- `MatchState` — score, clock, quarters, possession. Deliberately separate
  from `GameState` because not every mode has a scoreboard (Kick-to-Kick
  doesn't); both teams' scores flow through the same `score()` call so
  neither can silently diverge.
- `CharacterProfile` — the single global player profile (Speed/Height/Kick
  Power/Kick Accuracy) — no roster system yet, one profile only.
- `Settings` — persisted to `user://settings.cfg`; Team Edit
  presets/tactics and audio volume live here.
- `SceneWipe` — pixel-wipe scene transitions.
- `AudioManager` — synthesizes placeholder SFX in code (kick, mark,
  tackle, bump, whistle, goal/behind, full time).

**`scripts/tuning.gd`** (`class_name Tuning`, not an autoload — a static
data class) is the one file to open to change how the game feels: every
tunable constant plus the shared `Team` and `Action` enums. It is the
direct descendant of Prototype 1's `settings.py`. Units are strict SI:
1 Godot unit = 1 metre/kg/second. Ground plane is XZ, +X is the home
team's attacking direction, +Y is up. `Action` enum is append-only —
`ACTION_DURATION`/`ACTION_CONTACT` index into it positionally, so existing
slots must never be reordered.

**Brain pattern** (`scripts/mechanics/player_brain.gd`): `PlayerController`
never reads `Input`/`InputManager` directly — it queries a `PlayerBrain`
interface (`wish_direction()`, `wants_kick()`, `wants_tackle()`, etc.).
`HumanBrain` reads live input per-call; `AIBrain` caches one decision per
physics frame in `update()` since deriving it is more expensive. This is
what lets Full Game put a human on one `PlayerController` and AI on all
the others through the identical code path. When adding a new player
action, add the query method to `PlayerBrain` (base returns a neutral
default), then implement it in both `HumanBrain` and `AIBrain`.

**Mode scripts** (`scripts/modes/`) are the state machines: `full_game.gd`
drives the real match (quarters, ruck contests via `_begin_ruck_contest` —
one shared mechanic for centre bounce, field ball-up, and boundary
throw-in — scoring restarts, holding-the-ball rulings, out-of-bounds).
`kick_to_kick.gd` drives the solo practice mode with an AI rival and two
training coaches (`CoachNPC` + `KickChallenge`/`MarkChallenge` minigames).

**`scripts/player/player_controller.gd`** is the largest script and the
core simulation: weight-modeled locomotion (accel/brake asymmetry,
speed-coupled turn rate, plant-and-pivot), the two-stage kick (ADS
stance/charge + hip-fire), handball/bounce, gathering, the 3-tier mark
(Safe/Running/Aggressive), tackle + lunge assist, spoil, smother, bump
(flick-gesture based), and ruck hit-outs. It never reaches into
`HumanoidRig` directly — animation is driven by state/events, not the
other way around, which is what keeps a future real-mesh swap clean (see
"Placeholder art" below).

**`scripts/ball/ball.gd`** — `RigidBody3D` with a prolate-spheroid
collision hull, quadratic drag, Magnus spin (kick swerve), and a "catch
gravity" assist that pulls the ball toward a marking player's reach.

**`scripts/ai/team_formation.gd`** — static 18-slot AFL formation
geometry, no coupling to game state or player roles (mirrors Prototype
1's `formations.py`). AI scope is deliberately limited to ball-carrier
control + generic proximity-based off-ball positioning — there is no
team-level tactics/zone-coverage system, and that's a standing project
decision, not a gap to casually "fix."

**Placeholder art**: `HumanoidRig` is a real `Skeleton3D` built to Godot's
humanoid bone profile, animated by `HumanoidAnimations`' procedurally
generated bone-track clips; every mesh on it is still a primitive
box/capsule/sphere. Importing a real Mixamo `.glb` and pointing the
existing `AnimationPlayer`/`AnimationTree` graph at it is meant to be a
clean swap.

**`scenes/main.tscn`** is a separate, older milestone-1 sandbox (no
AI/scoring/menus) kept for isolating movement/kick feel — open it directly
in the editor, it's not reachable from the main menu.

## Working conventions

- This project verifies changes by actually running them headless with
  scripted physics (see above), not just by reading the code — match that
  discipline for any gameplay/physics change.
- Rule numbers (distances, timers, thresholds) should trace back to either
  a real AFL rule (cite it in a comment, as `tuning.gd` does throughout)
  or an explicit Prototype 1 constant being translated to real units. Don't
  invent a number without a comment explaining where it came from.
  `docs/RULES_REFERENCE.md` has the P1→real-metres translation table.
  A few things are deliberately left unbuilt pending a real design
  decision rather than guessed at (e.g. bump's dangerous-contact free
  kick, the set-shot shot-clock) — check `docs/FEATURE_AUDIT.md` before
  filling one of those in with an invented default.
- Commit messages in this repo's history are terse (`updates`, `brief
  update`); no enforced convention beyond that.
