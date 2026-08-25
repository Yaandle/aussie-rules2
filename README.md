# Aussie Rules 2

A realistic 3D Aussie Rules football game built in **Godot 4.6** with real
physics — marking, tackling, and every other contest play out physically
rather than being decided by dice rolls. Full keyboard, mouse, and gamepad
support.

**Status:** a complete small-sided match — AI on every player you're not
controlling, a real clock and quarters, and physically resolved kicking,
handballing, bouncing, marking, tackling, spoiling, smothering, bumping,
and ruck contests, plus correct goal/behind restarts and a full-time score
screen. There's a menu system, a character screen, a team formation/tactics
editor, a keyboard remapping screen, and a solo `Kick-to-Kick` practice mode
with three training coaches (kicking, marking, tackling). Every model,
animation, and sound effect is generated in code — there's no imported art
or audio yet.

See [docs/FEATURE_AUDIT.md](docs/FEATURE_AUDIT.md) for what's built vs.
still missing, [docs/HANDOVER.md](docs/HANDOVER.md) for the build history,
and [docs/RULES_REFERENCE.md](docs/RULES_REFERENCE.md) for how the real AFL
rules are simplified at this stage.

Milestone 1's original movement/kick-feel sandbox (no AI, scoring, or menus)
still lives at `scenes/main.tscn` — open it directly in the editor.

## Run

Open `project.godot` in Godot 4.6+ and press **F5**, then pick **FULL GAME**
from the main menu to play a match. No build step, no asset import.

## Project layout

```
project.godot            input map, autoloads, physics layers
scripts/
  tuning.gd               every tunable constant + shared enums (Team, Action)
  main.gd                 milestone-1 sandbox harness (scenes/main.tscn)
  autoload/                InputManager, GameState, ControlMode (routes human input to
                            whichever body should receive it — SINGLE_PLAYER/TEAM_COMMAND),
                            MatchState, CharacterProfile, Settings (persisted
                            user://settings.cfg), SceneWipe,
                            AudioManager (synthesized placeholder SFX)
  player/                  PlayerController (weight model, disposal, contests,
                            Slide/Lunge tackle resolution), PlayerAnimation,
                            HumanoidRig/HumanoidAnimations, KickTrajectory,
                            SkeletonWireframe
  mechanics/               PlayerBrain / HumanBrain / AIBrain / CommandBrain
                            (AIBrain + an issued-order override, TEAM_COMMAND's
                            non-selected teammates), CoachNPC, CoachChallenge
                            (shared base) + KickChallenge, MarkChallenge,
                            TackleChallenge
  modes/                   full_game.gd (match state machine), kick_to_kick.gd
  ball/                    Ball (RigidBody3D: spheroid hull, drag, Magnus, carry/launch)
  camera/                  BroadcastCamera (chase rig, Full-Side broadcast rig, dialogue two-shot)
  field/                   Field (oval markings, posts, fence, trees, score triggers)
  ai/                      TeamFormation (18-slot AFL formation data)
  ui/                      main menu, character screen, team list, settings,
                            remap screen, scoreboard, debug hud, pause/match-end screens
  dev/                     animation_viewer.gd — dev-only clip preview + a Tackle
                            Sandbox mode (two real, controllable players for testing
                            tackle/contest physics in isolation)

scenes/                   mirrors scripts/ — see each script's header comment
  modes/full_game.tscn     the match scene FULL GAME launches
  modes/kick_to_kick.tscn  solo practice, reached via the character screen
  dev/animation_viewer.tscn  not reachable from the menu — open directly in the
                              editor (see scripts/dev/ above)
  main.tscn                milestone-1 sandbox

assets/shaders/           turf, boundary glow, backdrop scrims — no imported art yet
docs/
  FEATURE_AUDIT.md         current-state inventory + development roadmap — start here
  HANDOVER.md              full session-by-session build log
  RULES_REFERENCE.md       Prototype 1's rule numbers translated to real metres
```

## Controls

| Action | Keyboard / Mouse | Pad |
|---|---|---|
| Move / walk / sprint | `WASD` / `Ctrl` / `Shift` | Stick / — / L3 (click) or RT |
| Camera / recentre | Mouse, arrows / `C` | Right stick / R3 |
| Kick stance — hold to aim/charge | Right Mouse (or `K`) | LT |
| Kick execute — aimed, while in stance | Left Mouse (or `F`) | RT (while LT held) |
| Kick hip-fire — quick, imprecise | Left Mouse (or `F`) | RT (LT not held) |
| Handball (toward move direction) | `Q` | X |
| Bounce (in possession) | `Space` | B |
| Slide tackle — hold, not carrying (higher takedown chance, real cost on a miss) | `E` | B |
| Lunge tackle — tap, not carrying (lower commitment, weaker against a fast carrier) | `Q` | X |
| Mark: Safe (hold) · Running (tap) · Aggressive (tap, jumps) | `G` · `Q` · `H` | A · X · Y |
| Spoil (not carrying, near a contest) | `P` | LT (tap) |
| Smother (not carrying, opponent mid-kick) | `Q` | X |
| Bump: hold stance, flick right stick to swing | `L` + flick | LB + flick |
| Hit-out — ruck contest only | `J` | RB |
| Switch controlled player (Single Player mode) | `Tab` | D-pad Left |
| Toggle Single Player / Team Command mode | `M` | D-pad Right |
| Issue a move-here order (Team Command mode) | `B` | Misc1 (Xbox Share / PS Create) |
| Pause | `Esc` | Start |
| Reset ball · Debug HUD | `R` · `F3` | Back · D-pad up |

Slide and Lunge are two different tackle commitments, not two ways to do the
same thing — both resolve from real closing speed, approach angle, and
carrier speed at contact (never a dice roll), but Slide favours takedown
odds over risk and Lunge favours staying on your feet over reliability.
Team Command is a minimal whole-team-control mode: you keep direct control
of one player and can send the nearest teammate to a lead point ahead of
you; it's a debug-grade entry point today (`M` to toggle), not a designed
menu flow yet.

Kick is one action with two triggers, aim and fire. Hold the kick-stance
button to enter a slowed aiming pose — the mouse or right stick then swings
the aim from wherever the camera's already pointing, with a live trajectory
preview. Releasing without ever firing cancels. Tapping the kick-execute
button *without* holding stance first fires an instant, less accurate
hip-fire kick from wherever the body's facing. Settings → MOUSE KICK BUTTONS
swaps which mouse button aims and which fires.

Many action buttons are context-sensitive: on gamepad, Bounce (B) while
carrying becomes Slide tackle once you're not; Handball (X) while carrying
becomes Running Mark, Smother, or Lunge tackle depending on the situation
once you're not (a nearby opponent mid-kick gets smothered, one just
running with the ball gets lunge-tackled); Safe Mark becomes a ground
pickup once the ball isn't airborne.

**Training coaches** (`kick_to_kick.tscn` only): walk up to a coach, `Q`/X
to talk, `Y`/A to accept. The kicking coach runs a target-practice
challenge, the marking coach lobs deliveries to mark, and the tackling
coach hands the rival the ball and expects you to run it down.

**Keyboard remapping**: Settings → REMAP CONTROLS rebinds the keyboard key
on any action button (not the WASD/arrow axes, mouse, or gamepad).

**Not yet verified on real hardware** — gamepad bindings and rumble have
shipped without testing on a physical controller.

## Placeholder art

`HumanoidRig` is a real `Skeleton3D` built to Godot's humanoid bone profile,
driven by procedurally-generated animation clips — every mesh on it is
still a primitive box/capsule/sphere. The plan is to prove the game feels
right first, then swap in a real Mixamo model later without touching the
gameplay code.
