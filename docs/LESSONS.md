# Lessons

These are the durable engineering notes distilled from the session-by-session
handover log. That log was archived on 2026-10-24: it ran to 6,210 lines of
mostly superseded history. The full text lives outside the repo, in
`F:\dev\aussie-rules2-archive\2026-10-24_docs\HANDOVER.md`, and in git history
(`git log -- docs/HANDOVER.md`). Read this file instead of digging through it.

## Design decisions to keep

- **Weight is emergent, not scripted.** Turn rate falls as speed rises, and
  running against your own momentum drives target speed toward zero.
  Plant-and-pivot falls out of that. Don't special-case it.
- **The strafe axis is fed by physics, not input.** The body faces faster
  than the velocity heading turns, so mid-turn `locomotion_blend()` reports
  real lateral motion. That's why the 2D blend space exists.
- **The AnimationTree graph is built in GDScript**, not authored in a `.tscn`
  (`player_animation.gd`). Imported clips override the procedural fallback
  through `_build_merged_library()`. The umpire still uses the procedural rig.
- **Everything tunable lives in `scripts/tuning.gd`**, including the shared
  `Team` / `Action` enums. Autoload enums can't be type annotations. Don't
  rename or renumber `Tuning.Action`: it's positionally indexed by
  `ACTION_DURATION` / `ACTION_CONTACT`.
- **Contests are decided by collision, timing and momentum, never a
  probability roll** (`RULES_REFERENCE.md` §3). The ML models in
  `scripts/dev` are a sandbox. The one model-adjacent thing in gameplay is
  the mark cue, and it's only a cue (`docs/ML_AI_AUDIT.md` §9).
- **Kits resolve in one place.** `TeamKit` gives HOME the CHARACTER
  screen's kit and AWAY a preset picked to contrast with it. Imported
  models are recoloured by Blender material name (`Shirt`/`Jersey`, `Short`,
  `Shoe`/`Boot`, `Sock`, `Skin`), so keep those words in new exports.
- **Field dressing is a setting, not a scene edit.** `Settings.field_style`
  picks classic or Oval 1 (`scenes/field/oval1_environment.tscn`, trees as
  MultiMesh) on Field instances with `follow_field_style`. Lines, posts and
  collision never change with it.
- **One context-sensitive tap.** Keyboard Q / gamepad X is Handball when
  carrying, Running Mark when the ball is airborne and reachable, Lunge
  tackle against a carrier, and Smother against a kicker already in stance.
  Slide tackle is a hold (E / B). Bump is a hold of LB plus a right-stick
  flick.

## Physics and engine gotchas

- **Same-frame construction race (Jolt).** The first two or three
  `PlayerController`s a fresh scene builds can read garbled transforms if
  they're repositioned in the frame they're created. One can be launched
  across the map. There are two workarounds:
  - spawn and free a few throwaway players first
    (`AnimationViewer._ensure_player_construction_warmed`)
  - wait a few physics frames before touching them
  
  Normal match flow never hits it. Synthetic tests do.
- **Use 6DOF joints for PhysicalBone3D under Jolt, not CONE** (CONE
  explodes). A jointed chain needs a settle and sleep assist, and the feet
  must be capsules. See `scripts/player/physics_ragdoll.gd`.
- **Ragdoll bodies can't carry scale.** Match rigs are scaled by height, so
  `PhysicsRagdoll.build` bakes the scale into shapes, joint anchors and an
  inverse-scaled `body_offset`. They live on their own physics layer 5
  ("ragdoll"), because player capsules shove light limbs about.
- **Joint motors alone can't hold a ragdoll up.** Servos sized by each
  link's inertia are about 10× too weak for a stance knee. Standing needs
  the balance assist's weight support, and its tilt correction must be
  weak at low strength, or it soaks up the hit and the body crumples in
  place instead of falling away.
- **Read a ragdoll's position from its bodies, not the skeleton.** In
  physics frames `get_bone_global_pose` didn't track the simulated bodies
  (1-3 m off after a fall), though the rendered skin did.
- **Python edits on Windows corrupt files.** `open()` defaults to cp1252
  and CRLF: an em dash came out as a raw 0x97 byte, which stopped
  `tuning.gd` loading at all. Use the Edit tool, or
  `encoding="utf-8", newline=""`.
- **Bit-identical physics replays need the ball pinned in the air**
  (`Ball.lock_at`) before launch. Launching from a ground contact drifts by
  about 1e-4 m through Jolt's contact warm-start.
- **The ball collides with player bodies.** A leap or dive at the wrong
  instant deflects it, which is why catchable windows have holes.
- **Godot imports any `.csv` under `res://` as a translation table.** Give
  data folders a `.gdignore`; FileAccess still reads them in the editor and
  headless runs. A `.gdignore`d folder isn't exported, so runtime data goes
  elsewhere.
- **A plain `Panel` inside a container collapses to zero height.** It
  doesn't size to its children, so its backing never draws and dark text
  vanishes on a dark page. Use `PanelContainer` for any card built in a
  `CenterContainer`/`VBoxContainer`. This hid the Career full-time screen.
- **Kick aim/power coupling (open, unplaytested).** `get_look_vector()`
  shapes the stick's combined magnitude, so on the aim stick the x (aim) and
  y (power) axes aren't independent. A big diagonal push suppresses power.
  Worth checking if kicking off to the side feels inconsistent.

## Verification that works here

- The Godot binary is
  `D:\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`
  (not on PATH).
- After adding a `class_name`, rebuild the class cache with
  `--headless --editor --quit --path .`.
- Boot check: `--headless --path . res://scenes/<scene>.tscn --quit-after 300`.
- For scripted checks, use a scratch scene run as a positional scene (not
  `--script`, which skips autoloads), with `--fixed-fps 60`, `--quit-after N`
  and an explicit `get_tree().quit()`. Delete it afterwards.
- For visual checks, run windowed with
  `--write-movie <dir>/x.png --fixed-fps 30 --resolution 1280x720` and read
  the frames. This caught a skinning bug the numbers missed.
- **A scratch scene that plays a Career match writes the real save**
  (`user://career_profile.cfg`, `settings.cfg`, under
  `%APPDATA%\Godot\app_userdata\Aussie Rules 2`). Back them up first, or
  set state in memory and open the screen directly instead.
- At render rates below the physics rate, `_process` skips physics ticks.
  Sample physics state on `SceneTree.physics_frame` instead.
- Nobody in this project's history has had a live GUI session during an
  agent run. Anything about feel, framing or camera needs the user's eyes:
  say so rather than claiming it.
