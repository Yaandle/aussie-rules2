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
  `scripts/dev` are a sandbox. Gameplay uses two model-adjacent things. The
  mark cue is only a cue (`docs/ML_AI_AUDIT.md` §9). `TackleBalance`
  evaluates the tackle model's formula on the real contact: a threshold
  decides hold or break, and the same value sets ragdoll strength. It's
  never rolled.
- **Kits resolve in one place.** `TeamKit` gives HOME the CHARACTER
  screen's kit and AWAY a preset picked to contrast with it. Imported
  models are recoloured by Blender material name (`Shirt`/`Jersey`, `Short`,
  `Shoe`/`Boot`, `Sock`, `Skin`), so keep those words in new exports.
- **Field dressing is a setting, not a scene edit.** `Settings.field_style`
  picks Field 1, the park (`scenes/field/park_environment.tscn`), or Field 2,
  the bush oval (`oval1_environment.tscn`), on Field instances with
  `follow_field_style`. Lines, posts and collision never change with it.
  Menu backdrops still build `field.gd`'s generated field.
- **Field props are generated in Blender and batched in Godot.** The scripts
  in `assets/blender/scripts/` build `park_props.blend` (run it first), then
  the layouts link its meshes. Godot's glTF importer gives every node that
  shares a glTF mesh the same `ArrayMesh`, so `OvalEnvironment` turns a
  layout of ~1,000-1,300 linked copies into ~30 MultiMeshes. Don't commit
  `.blend1` backups. A layout object can still be found by name while it's
  batched: that's how `FieldScoreboard` lands on the prop named
  "Scoreboard". Names carry two more rules: a plant mesh's name holds one of
  `TINTED_MESH_WORDS` (each copy gets its own tint) and nothing else's may,
  and a layout object named `Far*` casts no shadow. Add to a layout in a new
  pass with its own RNG after the seeded one; touching the seeded pass
  reshuffles every tree on the ground.
- **Mark reach is measured from the hands.** `CatchPoint` (in front of the
  chest, 1.4 m) and about an arm's length, not `CarryPoint` by the right
  hip with 2-3 m of reach. Judge a reach change by how close the ball's
  uncaught flight passes the hands, not by where it was when the catch was
  called: the ball is still flying toward the hands then. Mark reach also
  sets the AI's catch rate. A tap judged on its own frame is too tight: a
  kick crosses an arm's reach in about 0.1 s and then hits the chest, so
  the Running tap opens a catch window like the Aggressive leap's. Probe
  marks with presses off the cue, not just on it.
- **The ruckmen can't mark the throw-up.** `_mark_attempt_blocked` blocks
  anyone in a live ruck contest. When Safe reach grew, an AI ruckman
  holding A caught the umpire's toss and the stoppage looped.
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
- **Push a tackled ragdoll along the contact line, mostly as a whole body.**
  Relative velocity sent a side-hit runner backwards. All of a hard push on
  the 17 kg chest backflipped the body, which then lay the wrong way round.
  Start the tackler's ragdoll at their post-collision velocity too. At full
  speed it ploughs into the carrier and sits down backwards.
- **Don't resolve a contact on post-`move_and_slide` velocity alone.** By
  then the part running into the other capsule is gone. A tackle pressed
  against a stopped carrier read 0 m/s closing and whiffed. Count the
  tackler's committed drive (`PlayerController._tackle_velocity`).
- **Freezing a player's physics process freezes their ragdoll too.**
  Kick-to-kick froze the rival the frame a tutorial step cleared, and the
  tackle is what cleared it. The carrier's ragdoll sat mid-build, standing
  frozen, while only the tackler fell. Keep ragdolled players processing.
- **Judge a ragdoll's fall by how it lies at get-up, on a floor that's
  really under it.** A test floor that ended at x = 200 m let half a sweep
  fall into the void and still "connect".
- **Gait clips are slow for the game's speeds.** 6thbuild's run_fwd covers
  ~3.4 m/s of ground and the jog ~2.7, against 8.4 m/s sprints.
  PlayerAnimation measures each clip and scales cadence to match, capped
  at a realistic steps-per-second, so expect some foot skate at a sprint.
- **Move a ragdoll limb with its joint motors, not a pull at its tip.** A
  forearm is jointed to the whole body, so a wrist servo sized for the
  forearm's own 2 kg barely moved it (TackleWrap closed at ~1.5 m/s).
  Solve IK and aim the segments (`PhysicsRagdoll.aim_dirs`); keep the
  point pull for holding on. Stop aiming once down: a target under the
  other body is in the turf, and the arm thrashes at it.
- **Resolve a ragdoll hit when the bodies meet, not at the trigger
  range.** A bump resolved at `BUMP_RANGE` (2 m) threw the carrier with the
  bumper still 1.9 m off them.
- **A leg IK pole has to ride up with a raised foot.** 6thbuild's
  `ikpole` sits at knee height in front; a kick's follow-through lifted
  the boot past it and flipped the knee for 0.1 s. To find a glitch like
  that, sample the clip's bones at 120 Hz in a scratch scene and look
  for a per-step spin spike.
- **Read a ragdoll's position from its bodies, not the skeleton.** In
  physics frames `get_bone_global_pose` didn't track the simulated bodies
  (1-3 m off after a fall), though the rendered skin did.
- **A `PhysicalBone3D` joint's zero is the pose it was built in.** The
  joint is made when the body enters the tree, from where the bodies are
  then. A match built ragdolls mid-run, so every limit was centred on one
  frame of running until `PhysicsRagdoll.build` started resetting to rest
  first.
- **Jolt's 6DOF swing limits won't go wide.** Asymmetric limits work, but a
  bend limit past ~75° from the joint's zero comes apart. Wide ranges cost
  stability in real falls even when a push test holds, so check limit
  changes with `scenes/dev/tackle_sweep.tscn`.
- **Check what else a Tuning constant feeds before changing it.**
  `RUCK_HIT_OUT_REACH` was defined as the Aggressive mark's reach, so
  cutting mark reach would have cut the ruck tap from 3.1 m to 1.4 m.
- **`git stash` here rewrites the files it restores with CRLF**
  (`core.autocrlf=true`), and several UI scripts are CRLF in the working
  tree anyway. A script edit that expects LF finds nothing; the Edit tool
  copes with either.
- **Ramp in any servo that grabs a ragdoll limb.** At full strength on its
  first tick, TackleWrap's wrist grip cancelled the whole closing speed at
  the wrist and whipped the arms at up to 105 rad/s.
- **Size a point servo on the point's own mass in the pull's direction**
  (`PhysicsRagdoll.point_mass`), not the limb's. Sideways, a wrist feels
  ~0.5 kg, not the arm's 4.6. Sized on the arm, TackleWrap's grip did ~6×
  too much each tick. It whipped forearms at 40-335 rad/s and broke elbows
  past their stops, which looked like a "pinned wrist" until a per-frame
  probe showed it happened mid-reach.
- **An AnimationTree `travel` lands on the tree's next update.** An action
  clip started ~2 frames behind the gameplay clock that fires its contact,
  so the kick's boot arrived after the ball had gone (0.4 m short on the
  launch frame). `PlayerAnimation.play_action` advances the tree one
  physics step right after the travel.
- **Key a kick's leg by joint angles, not boot positions.** A contact point
  0.5 m ahead of a 1.05 m hip is out of a straight leg's reach, so the leg
  IK folded the knee 80° and lifted it ("the knee comes up high"). See
  `solve_leg` in `tools/blender/author_6thbuild_clips.py`.
- **A blend space's `sync` doesn't line up phases.** It only keeps
  zero-weight clips' clocks running. Clips of different lengths drift, so
  `PlayerAnimation` rebuilds the stepping clips to one length and one
  stance phase ("Gait phase lock").
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
- **`RetroWindow.card()` doesn't grow with its content.** The wrapper is a
  plain Control sized only by `minimum`. Inside a ScrollContainer that gives
  a scroll range of ~0; set the wrapper's minimum height from
  `inner.get_combined_minimum_size()` after filling it (team_list_screen.gd).
- **`ConfigFile.get_value(section, key, null)` errors when the key is
  missing.** A null default means "required". Probe optional or
  new-version keys with `has_section_key()` first (career_profile.gd's
  version-1 migration).
- **Kick aim/power coupling (open, unplaytested).** `get_look_vector()`
  shapes the stick's combined magnitude, so on the aim stick the x (aim) and
  y (power) axes aren't independent. A big diagonal push suppresses power.
  Worth checking if kicking off to the side feels inconsistent. (Full-side
  on a pad no longer splits the axes: the stick points, its push is the
  reach. See Tuning's "Full-side kick aim".)
- **A scripted bot's kick goes along its body facing when the stance
  starts** (`_current_look_yaw()` with no camera). Square it up with
  `face_toward()` every frame until `is_kick_aiming()`, not once: after a
  mark it walks back off the mark first and turns as it goes (DrillBrain).
- **A player spawned without `set_brain()` is human-controlled.**
  `_brain` defaults to `HumanBrain`, so a bot needs a brain before its
  first physics frame or it runs off the shared input.

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
  `--write-movie <dir>/x.png --fixed-fps 30` and read the frames. This
  caught a skinning bug the numbers missed. Frames come out at the
  project's 1600x900 window override; `--resolution` doesn't change that.
  `scenes/dev/demo_recorder.tscn` is a worked example (the README's GIFs).
- **A scratch scene that plays a Career match writes the real save**
  (`user://career_profile.cfg`, `settings.cfg`, under
  `%APPDATA%\Godot\app_userdata\Aussie Rules 2`). Back them up first, or
  set state in memory and open the screen directly instead.
- **Committing next to another session's edits in the same file:** with no
  `git add -p`, build the staged copy as `git show HEAD:<file>` plus only
  your hunk, then `git hash-object -w` it and `git update-index --cacheinfo`.
  Their hunks stay unstaged in the working tree (Career Phases 7-8).
- At render rates below the physics rate, `_process` skips physics ticks.
  Sample physics state on `SceneTree.physics_frame` instead.
- **A new player skin on 6thbuild's skeleton can't change gameplay**: the
  ragdoll, anchors and clips read bones only. Prove it by the tackle sweep
  printing identically with `MODEL_ID` swapped (a temporary copy), not by
  a match: two matches on the same model already end differently.
  Compare imported clips key for key; `Quaternion.angle_to` reads ~0.006 rad
  on a clip against itself. Check skin and cloth with
  `tools/blender/check_7thbuild_deform.py` and by eye (`build_compare.tscn`):
  a face crossing a crease can show with every vertex inside (Build 7).
- **Test a poke by the line from the vertex's own bone, not the nearest
  face.** A vertex deep in a folded crease finds a face whose normal points
  at it and reads "outside" (a jog read 38 mm that renders clean).
- **Hidden geometry under cloth at a ball joint has to fit the sphere the
  cloth leaves round the pivot.** Linear-blend creases cave in toward a
  bent joint; 6thbuild's hips leave ~5 cm in front of each hip joint, so
  Build 7's thigh under the shorts is a slim cone.
- **Draws scale with surfaces, times every shadow cascade.** Build 7
  before's ten surfaces cost 48 draws a player; one surface with per-face
  slots and instance shader parameters costs 5, and 36 players share one
  material. glTF flips V: a projection authored in Blender UVs reads
  upside down in Godot.
- **Windowed review renders:** `scenes/dev/build_compare.tscn` (in-game
  look, takes a `res://` .glb for a before/after) and
  `scenes/dev/model_cost.tscn` (render cost, v-sync off).
- **Animated poses must stay inside the ragdoll's joint limits.** A tackle
  can land on any frame and the ragdoll starts from the pose: Build 7's
  first new sprint went 50° back at the hip and started tackle_sweep's
  falls at 100 rad/s. Check a gait's hip, knee and ankle ranges against
  PhysicsRagdoll.BODIES before shipping it. **That includes the hinge's
  axis:** a hinge allows one axis only, and a forearm bent about any other
  (the upper arm rolled wrong by the arm IK) is snapped onto it in one
  tick. `joint_report` can't see it (it measures bend, not twist or
  off-axis). Build 7's gaits had elbows 50-84° off-axis: forearms at 43
  rad/s at the hand-off, while every joint read inside its limits. The
  rest pose's carrying angle means the elbow's plane doesn't hold the
  upper arm, so fit the swivel and roll together
  (`author_6thbuild_clips.solve_arm(..., hinge=True)`).
- **A rigid foot rolls over its toe tip, not the ball.** With no toe bone,
  a heel-off pivoting on the ball sank the toe 6 cm into the turf.
- **Ragdoll tackles:** `scenes/dev/tackle_sweep.tscn` runs real X, B and
  bump connects between running 6thbuild players and prints how every body
  fell. Its header holds the 2026-10-28 baseline.
- Nobody in this project's history has had a live GUI session during an
  agent run. Anything about feel, framing or camera needs the user's eyes:
  say so rather than claiming it.
