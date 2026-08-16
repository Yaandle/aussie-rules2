# Aussie Rules 2

Realistic-leaning 3D Aussie Rules football. **Godot 4.6**, Jolt physics,
controller-first with full keyboard parity. Contests resolve physically, not
by dice roll.

Brief: `PROTOTYPE2_DESIGN.md`. Prototype 1 (`E:\aussie-rules_game`) stays the
canonical rules reference — see [docs/RULES_REFERENCE.md](docs/RULES_REFERENCE.md).

**Status:** design doc §7 priority 1 — Full Game. A small-sided match
(`Tuning.TEAM_SIZE` a side) with AI on every player you're not driving,
tackling and marking resolved physically, goal/behind scoring, and a real
clock with quarters (2 minutes by default — `Tuning.QUARTER_LENGTH`, easy
to change). No menus or audio yet, and several real AFL rules are
deliberately simplified for this milestone — see docs/RULES_REFERENCE.md
and `scripts/modes/full_game.gd`'s header for exactly which.

Milestone 1's single-player sandbox (weighted locomotion, blend-space
animation) still lives at `scenes/main.tscn` for isolating movement/kick
feel — open it directly in the editor.

## Run

Open `project.godot` in Godot 4.6+ and press **F5** to play a match. No
build step, no asset import — every model, animation and texture is
generated in code.

Verified: `godot --headless --path . --quit-after 300` exits 0 with no errors.

## Controls

| Action | Key | Pad |
|---|---|---|
| Move / walk / sprint | `WASD` / `Ctrl` / `Shift` | Stick / — / L3 (click) |
| Camera / recentre | Arrows, mouse / `C` | Right stick / R3 |
| Kick stance — ADS (hold, aim, charge) | `K` | LT |
| Kick execute — aimed, while in stance | `F` | RT (while LT held) |
| Kick hip-fire — quick, imprecise | `F` | RT (LT not held) |
| Handball (toward move direction) | `Q` | X |
| Bounce (in possession) · Tackle (not) | `Space` · `E` | B · B |
| Switch player · Pause | `Tab` · `Esc` | LB · Start |
| Reset ball · Debug HUD | `R` · `F3` | Back · D-pad up |

Kick is two ways to fire, both off the same trigger. Hold K/LT to enter a
slowed ADS stance — the right stick or mouse swings the kick's aim
independently of which way the body is facing, same as the on-screen
trajectory preview, at a deliberately unhurried turn rate for precision —
then tap F/RT to strike at whatever power/aim you've built up. Releasing
K/LT without ever tapping F/RT cancels outright rather than firing. Tap
F/RT **without** ever holding K/LT and you hip-fire instead: an instant
kick wherever the body's currently facing, fixed middling power, no charge,
and noticeably less accurate — the "didn't aim down sights" option, for
when there's no time to line one up. On a pad, aiming also gets a soft
pull toward the nearest teammate roughly in the aim direction (not a
lock-on) — ported from Prototype 1's own aim-assist, confirmed to be a
real, deliberate system there and not something invented for this port.
Handball aims wherever the left stick/WASD is held at the moment of the
press, also independent of facing. B is context-sensitive like a lot of
sports games' off-ball buttons: Bounce while you're carrying, Tackle
(hold, not tap — it fires the instant you're in range of an opposing
carrier) once you're not. Marking, smothering, spoiling and the hit-out
aren't built yet — A/X off the ball and Y/RB/LB are still unbound or
reserved for them. The keyboard's three gait tiers hit the same values an
analog stick reaches, so it is a real input path, not a degraded one —
sprint/walk are keyboard-only modifiers for that reason; a pad's stick is
already analog, so only the L3-click sprint boost (FIFA-style) exists there.

**Kicking coach** (`kick_to_kick.tscn` only, first of three planned):
walk up to the coach on the field, `Q`/X to talk, `Y`/A to accept a
5-kick target-practice challenge, `N`/B to decline. First of three coaches
planned (marking and tackling next); the dialogue text is a placeholder
`Label`, not the real chat-bubble UI yet.

## Files

```
project.godot                       162  input map, autoloads, physics, layers

scripts/
  tuning.gd                         294  every tunable + shared enums (P1's settings.py)
  main.gd                            83  milestone-1 sandbox harness (scenes/main.tscn)
  autoload/
    input_manager.gd                145  device abstraction, radial deadzones, curves, haptics
    game_state.gd                    60  mode + phase singleton
    match_state.gd                  105  score, clock, quarters, possession
  player/
    player_controller.gd            446  weight model, brain-driven input, tackling
    player_animation.gd             173  builds the BlendSpace2D + action state machine
    placeholder_rig.gd              143  PLACEHOLDER blocked-out 1.85m humanoid (has home/away kit)
    placeholder_animations.gd       293  PLACEHOLDER parametric gait + action clips
  mechanics/
    player_brain.gd                  49  the human-vs-AI control interface
    human_brain.gd                   47  reads InputManager/Input — the default brain
    ai_brain.gd                     171  chase/support/press/dispose — the Full Game AI
  modes/
    full_game.gd                    230  match state machine: kickoff, scoring, quarters, AI wiring
  ball/ball.gd                      205  RigidBody3D: spheroid hull, drag, Magnus, carry/launch
  camera/broadcast_camera.gd        134  spring-arm rig, look-ahead, ball focus, dynamic FOV
  field/field.gd                    321  oval markings, posts, and goal/behind scoring triggers
  ui/
    debug_hud.gd                     77  speed, blend position, anim state, carry distance
    scoreboard.gd                    50  always-on score/clock/quarter readout

scenes/
  main.tscn                          55  milestone-1 sandbox: one player, one ball, one oval
  modes/full_game.tscn               54  the scene F5 actually launches
  player/player.tscn                 47  CharacterBody3D + rig + AnimationPlayer/Tree + markers
  ball/ball.tscn                     30  RigidBody3D + mesh (hull built at runtime)
  field/field.tscn                   28  turf slab + collision (markings built at runtime)
  camera/broadcast_camera.tscn       22  Yaw > Pitch > SpringArm3D > Camera3D
  ui/
    debug_hud.tscn                   16  one outlined Label, toggled with F3
    scoreboard.tscn                  20  one centred Label, always on

assets/shaders/turf.gdshader         51  mowing bands, oval boundary and surrounds, analytic

docs/
  RULES_REFERENCE.md                104  P1's rule numbers translated to metres, by category
```

Empty by design, waiting on later milestones: `scripts/ai/` (higher-level
tactics, if `ai_brain.gd`'s baseline needs replacing), `data/scenarios/`,
`assets/models|animations|textures|audio/`.

## Placeholder art

Design doc §9: prove the system before buying art. `placeholder_rig.gd` and
`placeholder_animations.gd` are marked for deletion — import a Mixamo `.glb`,
delete both, and stop calling `build_library()` in `player_animation.gd`. The
blend point layout, state names, parameter paths and all of
`player_controller.gd` already match what the real version uses.
