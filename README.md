# Aussie Rules 2

Realistic-leaning 3D Aussie Rules football in **Godot 4.6** (Jolt physics).
Controller-first, keyboard at full parity. Contests resolve physically, not
by dice roll.

The brief is `PROTOTYPE2_DESIGN.md`. Prototype 1 — the Python/Pygame AFL
prototype at `E:\aussie-rules_game` — stays intact as the canonical rules
reference; see [docs/RULES_REFERENCE.md](docs/RULES_REFERENCE.md) for the
translation of its rule numbers into this project's real metres.

## Status: milestone 1

Design doc §11's first milestone, and only that:

> one `CharacterBody3D` player with blend-space locomotion and a physically
> simulated ball, feeling "weighty" to move and kick — before AI, a second
> team, or match rules.

**Done:** the oval, the player and its weight model, the blend-space
animation pipeline, the ball as a real rigid body, the broadcast camera,
controller/keyboard parity, a debug HUD.

**Deliberately absent:** AI, a second player, a second team, tackling,
marking, scoring, the match clock, menus, audio. Empty directories from §10
(`scripts/mechanics`, `scripts/ai`, `scenes/modes`, `data/scenarios`) are
placeholders for the milestones that own them.

## Running it

Requires Godot 4.6+. There is no build step and no asset import — every
model, animation and texture in the project is generated in code.

1. Open the Godot editor, **Import**, and select `project.godot`.
2. Press **F5**.

Keyboard alone is enough to test everything; a controller is never required.
That is a hard requirement carried over from Prototype 1, not a nice-to-have.

## Controls

Every action is an Input Map action bound to both a key and a controller
input. No code branches on device type.

| Action | Keyboard | Controller |
|---|---|---|
| Move | `WASD` | Left stick |
| Walk / sprint | `Ctrl` / `Shift` | Left stick click / right trigger |
| Camera | Arrow keys, mouse | Right stick |
| Recentre camera | `C` | Right stick click |
| Kick (hold to charge) | `K` | A |
| Handball | `Q` | X |
| Bounce | `Space` | B |
| Mark / contest | `E` | Y |
| Switch player | `Tab` | LB |
| Release mouse | `Esc` | Start |
| Reset ball to your feet | `R` | Back |
| Toggle debug HUD | `F3` | D-pad up |

Mark/contest and switch-player are bound but have nothing to do yet.

The keyboard's `Ctrl` / nothing / `Shift` tiers hit exactly the same gait
values an analog stick reaches, so the keyboard is a real input path rather
than a degraded one.

## What to look for

The milestone is a feel question, so it needs to be judged by feel:

- **Sprint flat out, then demand a 180.** The player should plant, bleed the
  speed, come round in an arc and rebuild. Turn rate falls as speed rises,
  and running against your own momentum drives target speed to zero — the
  plant-and-pivot is those two rules interacting, not a special case.
- **Watch the strafe axis on the HUD during a hard turn.** The rig's facing
  turns faster than the velocity heading does, so velocity spends a moment
  pointing off to one side of the body and the blend space genuinely
  interpolates lateral animation. The animation is reporting the physics.
- **Hold `K` to full charge and let go.** The ball should climb lazily and
  come down steeply. That asymmetry is quadratic air drag; a scripted flight
  path cannot produce it.
- **Kick on the run vs. standing.** Momentum transfers into the ball.
- **Run onto a stationary ball at pace.** It should be knocked on.
- **Bounce while running** (`Space`) and run onto the rebound.

## Layout

Design doc §10, plus two additions noted below.

```
project.godot            input map, autoloads, physics engine, layers
scenes/
  main.tscn              the milestone-1 harness
  player/player.tscn     CharacterBody3D + rig + AnimationTree
  ball/ball.tscn         RigidBody3D
  field/field.tscn       turf slab; markings and posts are generated
  camera/broadcast_camera.tscn
  ui/debug_hud.tscn
  modes/                 empty — §7's Full Game / Scenario / Goal Kicking
scripts/
  tuning.gd              ADDITION: every tunable, plus the shared enums
  main.gd
  autoload/
    input_manager.gd     device abstraction, deadzones, curves, haptics
    game_state.gd        mode + phase
    match_state.gd       score, clock, possession
  player/
    player_controller.gd the weight model
    player_animation.gd  BlendSpace2D + state machine
    placeholder_rig.gd       PLACEHOLDER — deleted when Mixamo lands
    placeholder_animations.gd PLACEHOLDER — deleted when Mixamo lands
  ball/ball.gd
  camera/broadcast_camera.gd
  field/field.gd         ADDITION: generates markings and goals
  ui/debug_hud.gd
  mechanics/, ai/        empty — later milestones
assets/shaders/turf.gdshader
data/scenarios/          empty — §7 priority 2
docs/RULES_REFERENCE.md
```

Two departures from §10, both deliberate:

- **`scripts/tuning.gd`** is the direct descendant of Prototype 1's
  `settings.py` — one file holding every number that governs feel. §10 did
  not list it, but the pattern is one P1 proved and is worth keeping. It
  also holds the two shared enums (`Team`, `Action`), because it is the one
  module everything depends on, so a shared type can live there without
  creating a dependency cycle.
- **`scripts/field/`** was not in §10. The oval is not decoration here: you
  cannot judge whether movement feels heavy or a kick feels long without a
  50m arc and a mown band every 9m to measure against.

## Placeholder art

Design doc §9 says start on placeholder humanoids and Mixamo animation before
investing in art. There are no assets yet, so the player is a blocked-out
1.85m figure built in code and its animation clips are sampled from a
parametric gait function. They are not good animation and are not trying to
be — they exist so the BlendSpace2D has real, differently-shaped clips to
interpolate, which is the only way to prove the locomotion pipeline before
there is art.

**The swap:** import a Mixamo `.glb`, delete `placeholder_rig.gd` and
`placeholder_animations.gd`, and stop calling `build_library()` in
`player_animation.gd`. The blend point layout, the state names, the
parameter paths and everything in `player_controller.gd` already match what
the real version will use.

## Next

In the brief's order (§7, §11):

1. Contest mechanics — a second player, tackling and marking resolved by
   collision and momentum. This is where `root_motion_track` gets wired, per
   §5: root motion for impacts, code-driven locomotion.
2. Small-sided Full Game (3v3 or 6v6) with AI, then match rules from
   `docs/RULES_REFERENCE.md` §4.
3. Scenarios as data-driven resources.
4. Goal Kicking as a harness around the same ball physics.
