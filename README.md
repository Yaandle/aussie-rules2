# Aussie Rules 2

Realistic-leaning 3D Aussie Rules football. **Godot 4.6**, Jolt physics,
controller-first with full keyboard parity. Contests resolve physically, not
by dice roll.

Brief: `PROTOTYPE2_DESIGN.md`. Prototype 1 (`E:\aussie-rules_game`) stays the
canonical rules reference — see [docs/RULES_REFERENCE.md](docs/RULES_REFERENCE.md).

**Status:** a small-sided (`Tuning.TEAM_SIZE` a side) Full Game with AI on
every player you're not driving, a real clock/quarters, and physically
resolved kicking, handballing, bouncing, marking (3-tier, with stand-the-
mark and a general 10m retreat), tackling (+ lunge assist), spoiling,
smothering, bumping, ruck contests (centre bounce / field ball-up /
boundary throw-in / out on the full, all one shared mechanic), correct
goal/behind restarts, protected kick-ins, a real pause overlay, and a real
full-time screen with a per-team box score (kicks/handballs/marks/
tackles). A menu system, a character/attributes screen, a Team Edit screen
(formation + tactics presets), a keyboard control-remapping screen, and a
solo `Kick-to-Kick` practice mode with all three training coaches also
exist. Placeholder SFX (kick, mark,
tackle, bump, whistle, goal/behind, full time) are synthesized in code —
see `scripts/autoload/audio_manager.gd` — the same "no imported assets"
approach the rig already uses; `assets/audio/` stays empty on purpose. See
[docs/FEATURE_AUDIT.md](docs/FEATURE_AUDIT.md) for a full current-state
inventory (what works, what's buggy, what's missing) and the development
roadmap; see [docs/HANDOVER.md](docs/HANDOVER.md) for the full session-by-
session build log, and `docs/RULES_REFERENCE.md` for exactly which real AFL
rules are simplified for this milestone and why.

Milestone 1's original single-player sandbox (weighted locomotion,
blend-space animation, no AI/scoring/menus) still lives at `scenes/main.tscn`
for isolating movement/kick feel in isolation — open it directly in the
editor.

## Run

Open `project.godot` in Godot 4.6+ and press **F5** to play a match
(`run/main_scene` is the main menu — pick FULL GAME). No build step, no
asset import — every model, animation and texture is generated in code.

Verified headless: `godot --headless --path . --quit-after 300` exits 0
with no errors. If a freshly-added script with `class_name` fails to
resolve on a plain run, force a rescan of the global class-name cache first:
`godot --headless --editor --quit --path .`

## Controls

| Action | Key | Pad |
|---|---|---|
| Move / walk / sprint | `WASD` / `Ctrl` / `Shift` | Stick / — / L3 (click) |
| Camera / recentre | Arrows, mouse / `C` | Right stick / R3 |
| Kick stance — hold to aim/charge | `K` | LT |
| Kick execute — aimed, while in stance | `F` | RT (while LT held) |
| Kick hip-fire — quick, imprecise | `F` | RT (LT not held) |
| Handball (toward move direction) | `Q` | X |
| Bounce (in possession) · Tackle (hold, not) | `Space` · `E` | B · B |
| Mark: Safe (hold) · Running (tap) · Aggressive (tap, jumps) | `G` · `Q` · `H` | A · X · Y |
| Spoil (not carrying, near a contest) | `P` | LT (tap) |
| Smother (not carrying, opponent mid-kick) | `Q` | X |
| Bump: hold stance, flick right stick to swing | `L` + flick | LB + flick |
| Hit-out — ruck contest only | `J` | RB |
| Switch player · Pause | `Tab` · `Esc` | LB (D-pad L cycles) · Start |
| Reset ball · Debug HUD | `R` · `F3` | Back · D-pad up |

Kick is two ways to fire, off the same trigger. A faint dot always sits at
screen centre marking where the camera's currently pointed — hold K/LT to
enter a slowed aiming stance and the kick's aim starts exactly there, not
wherever the body's facing. From that starting point the right stick or
mouse swings the aim further, same as the on-screen trajectory preview.
Power is live and reversible either way, never a one-way ramp: on a pad, the
stick's forward/back position sets it directly; on keyboard/mouse, arrow
up/down and mouse movement both nudge it live. Releasing K/LT without ever
tapping F/RT cancels outright. Tap F/RT **without** ever holding K/LT and
you hip-fire instead — an instant kick wherever the body's currently facing,
fixed middling power, noticeably less accurate. On a pad, aiming also gets a
soft pull toward the nearest teammate roughly in the aim direction (not a
lock-on).

Many action buttons are context-sensitive, sports-game style: `B`/Space-E is
Bounce while carrying, Tackle (a hold, not a tap) once you're not; `Q`/X is
Handball while carrying, Running Mark or Smother depending on the ball's
state once you're not; `G`/A is a held Safe Mark while the ball's airborne,
a ground pickup once it's not.

**Training coaches** (`kick_to_kick.tscn` only, all three planned coaches
now exist): walk up to a coach on the field, `Q`/X to talk, `Y`/A to
accept, `N`/B to decline. The kicking coach runs a 5-kick target-practice
challenge; the marking coach lobs deliveries for you to mark; the tackling
coach hands the kick-to-kick rival the ball and expects you to run it down
before it gets away. The dialogue text is a placeholder `Label`, not a
real chat-bubble UI yet.

**Keyboard remapping**: Settings → REMAP CONTROLS lets you rebind the
keyboard key on any of the action buttons (not the WASD/arrow axes, and
not gamepad/mouse bindings — see `scripts/ui/remap_screen.gd`'s header for
the exact scope). Picking a key already used by another remappable action
takes it away from that action.

**Not yet verified on real hardware.** Every gamepad binding and rumble
profile has shipped without ever being tested on a physical controller —
see `docs/FEATURE_AUDIT.md`'s "unclear / needs further investigation"
section.

## Project layout

```
project.godot            input map, autoloads, physics layers
scripts/
  tuning.gd               every tunable constant + shared enums (Team, Action)
  main.gd                 milestone-1 sandbox harness (scenes/main.tscn)
  autoload/                InputManager, GameState, MatchState, CharacterProfile,
                            Settings (persisted user://settings.cfg), SceneWipe,
                            AudioManager (synthesized placeholder SFX)
  player/                  PlayerController (weight model, disposal, contests),
                            PlayerAnimation, HumanoidRig/HumanoidAnimations,
                            KickTrajectory, SkeletonWireframe
  mechanics/               PlayerBrain / HumanBrain / AIBrain, CoachNPC,
                            KickChallenge, MarkChallenge, TackleChallenge
  modes/                   full_game.gd (match state machine), kick_to_kick.gd
  ball/                    Ball (RigidBody3D: spheroid hull, drag, Magnus, carry/launch)
  camera/                  BroadcastCamera (chase rig, Full-Side broadcast rig, dialogue two-shot)
  field/                   Field (oval markings, posts, fence, trees, score triggers)
  ai/                      TeamFormation (18-slot AFL formation data)
  ui/                      main menu, character screen, team list, settings,
                            remap screen, scoreboard, debug hud, pause/match-end screens

scenes/                   mirrors scripts/ — see each script's header comment
  modes/full_game.tscn     the match scene FULL GAME launches
  modes/kick_to_kick.tscn  solo practice, reached via the character screen
  main.tscn                milestone-1 sandbox

assets/shaders/           turf, boundary glow, backdrop scrims — no imported art yet
docs/
  FEATURE_AUDIT.md         current-state inventory + development roadmap — start here
  HANDOVER.md              full session-by-session build log
  RULES_REFERENCE.md       Prototype 1's rule numbers translated to real metres
```

## Placeholder art

Design doc §9: prove the system before buying art. `HumanoidRig` is a real
`Skeleton3D` built to Godot's humanoid bone profile, driven by
`HumanoidAnimations`' procedurally-generated bone-track clips — every mesh
on it is still a primitive box/capsule/sphere. Importing a real Mixamo
`.glb` and pointing the existing `AnimationPlayer`/`AnimationTree` graph at
it is meant to be a clean swap; nothing in `player_controller.gd` reaches
into the rig directly.
