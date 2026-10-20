# Brief: marking animations on 6thbuild, then the MLP marking-cue stage

Hand this whole file to the next coding agent as its prompt. Written
2026-10-20 at the end of the session that built the Physics Ragdoll Lab
(stage 1), so the facts below were true on branch `update` at commit
`1af9a54`. Verify anything you're about to rely on; the code moves.

---

You're working in `F:\dev\aussie-rules2`, a Godot 4.6 (Jolt physics) Aussie
Rules football game, on branch `update`. The task has two halves, done in
order:

1. **Build the full set of marking animations for the current character
   (6thbuild), authored in Godot.** Use Madden-style catch types as the
   design language and the Physics Ragdoll Lab as a physical reference.
2. **Then build the MLP stage of the ML Experiments page for marking-cue
   timing.** Apply it so the cue, and the moment a mark clip starts, line
   the clip's contact frame up with the ball's real arrival.

Commit each half separately on `update` with clear messages. **Don't push.**
The user pushes after reviewing. Stop and report at the checkpoints marked
**CHECKPOINT** below.

## Read first

- `docs/RULES_REFERENCE.md` §3 (contests are decided by collision, timing
  and momentum, **never a probability roll**) and §5 (three-tier marking,
  including the open Standard/Strong/Aggressive naming conflict).
- `docs/MECHANICS_AUDIT.md` §B4 (the 5-stage active-ragdoll plan and its
  stage-1 status).
- `docs/ML_AI_AUDIT.md`, especially §3 (why the tackle model was never
  wired into live resolution), §4 (the AI only attempts the Safe mark tier)
  and §6–§8 (how the LR/GA stages were built and verified).
- `scripts/tuning.gd`, the marking block: `MARK_*_REACH_SCALE`,
  `MARK_*_IDEAL_WINDOW` / `OK_WINDOW`, `MARK_TIMING_*`, `MARK_CONTEST_RANGE`,
  `MARK_AGGRESSIVE_JUMP_SPEED`, `MARK_SAFE_HOP_SPEED`, and
  `ACTION_DURATION` / `ACTION_CONTACT`. The comment history there records
  what was already tried and why.
- `scripts/player/player_controller.gd`: `_update_aerial_contest`,
  `_ball_in_catch_reach`, `mark_timing_offset`, `live_mark_prompts`.
- `scripts/player/player_animation.gd` (`ACTION_STATES`,
  `_build_merged_library`) and `scripts/player/humanoid_animations.gd`
  (`_build_mark_*`).
- `scripts/player/humanoid_rig.gd` header (the import contract) and
  `scripts/dev/physics_ragdoll.gd` header (what the lab proved about this
  rig under Jolt).
- `scripts/mechanics/mark_challenge.gd` (the coach's marking drill: real
  kick deliveries that cycle Safe/Running/Aggressive and report
  `mark_caught` / `mark_missed`).
- Memory file `reference_godot_binary.md` (or the "Verification" section
  below) for how to run Godot headless here.

## Current state you're building on

**Marking mechanics (gameplay, done; don't change resolution):**
- Three tiers map to Madden's catch buttons. `MARK_SAFE` (A) is the
  possession catch, `MARK_RUNNING` (X) the catch taken in stride,
  `MARK_AGGRESSIVE` (Y) the high-point / contested jump catch.
- `MarkPrompt` shows live tiers over the receiver's head as (A)/(X)/(Y)
  badges.
- Each tier is graded by press timing against the ball's live arrival
  (`mark_timing_offset`) with IDEAL/OK windows. Reach then decides
  physically.
- Only Safe and Running have miss clips. Aggressive's miss is a real
  physical whiff. There is no spoil clip.
- `ai_brain.gd` only ever attempts `MARK_SAFE` (`_mark_safe_wanted`), never
  Running or Aggressive.
- A legal mark triggers a 5 m walk-back (`MARK_RETREAT_*`), previewable in
  the animation viewer's SEQUENCES tab.
- Tier naming: the rulebook says Standard/Strong/Aggressive and the code
  says SAFE/RUNNING/AGGRESSIVE. That's unresolved. **Don't rename the
  `Tuning.Action` enum.** It's positionally indexed by `ACTION_DURATION` /
  `ACTION_CONTACT`.

**6thbuild rig (`assets/characters/6thbuild.glb`):**
- 18 bones as of commit `02cf90d`: Hips (root), Spine, Chest, `head`
  (lowercase), Left/RightShoulder, UpperArm, LowerArm, Hand, Left/Right
  UpperLeg, LowerLeg, Foot.
- **No Root, Neck or Toes bone.** The control bones (`ikpole.*`,
  `iktarget.*`, `pelvis.001`) were removed in `02cf90d`. Exported via
  `tools/blender/export_6thbuild.py`.
- Bone rests are **not identity**. Each bone's +Y points at its child
  (Blender convention). That breaks the humanoid_rig.gd contract item 2
  ("identity rest") that `HumanoidAnimations` was written against.
- HumanoidRig turns the Skeleton3D node 180° (glTF faces +Z, the game faces
  -Z). Bone data is untouched, so skeleton space still faces +Z.
- Imported clips: idle, jog_fwd, run_back, run_fwd, run_fwd_l, run_fwd_r,
  strafe_l, strafe_r, tackle_grab, tackle_held, tackle_takedown, tackled.
  **No mark clips.**

**This is your actual starting problem.**
- `PlayerAnimation._build_merged_library()` falls back to the procedural
  `HumanoidAnimations` mark clips for any name the import doesn't provide.
- 13 of each mark clip's 14 tracks resolve on 6thbuild (`Neck` doesn't
  exist).
- But those tracks write absolute local rotations that assume identity
  rests. On 6thbuild they almost certainly produce twisted or collapsed
  poses.
- **Confirm this visually first.** Open the animation viewer's ACTIONS tab
  and press each MARK button. Capture frames with the movie writer (see
  "Verification"). Report what you see.

**Animation viewer (`scripts/dev/animation_viewer.gd`):**
- ACTIONS has MARK — SAFE / RUNNING / AGGRESSIVE / SAFE MISS / RUNNING MISS.
- CONTESTS now has **APPROACH FROM** (bearing: 0 = from in front, 90 = from
  B's right, 180 = behind) and **APPROACH SPEED** (walk..sprint). There's an
  orange aim arrow on the ground. A RAGDOLL button opens the Physics Ragdoll
  Lab.
- There's no "deliver a kick to a marking player from bearing X at speed Y"
  preview yet. You'll want one (see Part 1, step 4).

**Physics Ragdoll Lab (`scenes/dev/physics_ragdoll_lab.tscn`, builder
`scripts/dev/physics_ragdoll.gd`): stage 1, passive only.**
- 14 PhysicalBone3D bodies on 6thbuild, using 6DOF ball joints and hinges.
- Impacts are GO LIMP / PUSH / THROW with a bearing, strength and target
  part.
- Proven facts:
  - PhysicalBone3D's CONE joint explodes under Jolt; use 6DOF.
  - A jointed chain needs the settle/sleep assist to come to rest.
  - Capsule feet beat box feet.
  - Hard landings briefly sink a light link 4–15 cm.
  - Resting penetration is ~1 cm.
- Stages 2–5 (animation→ragdoll hand-off, motors, impact-aware responses,
  recovery) are **not built**.

**ML Experiments page (`scripts/dev/ml_experiment_viewer.gd`):**
- Stage tabs are LR / GA / MLP / DQL. LR and GA are real; MLP and DQL are
  "QUEUED" placeholders.
- The MLP placeholder already states the plan:
  - Target: marking-cue timing.
  - Inputs: ball height, ball distance, player speed, time to arrival,
    plus 1 TBD.
  - Net: 5 → 8 → 8 → 1 (jump timing).
  - Data: 200–500 recorded marking attempts, labelled success/miss.
  - Goal: let `ai_brain.gd` judge the Running/Aggressive tiers too.

## Part 1: Marking animations for 6thbuild, authored in Godot

**Goal:** every mark state `PlayerAnimation` can enter has a clip that
reads correctly on 6thbuild, plus the situational variants below. They're
authored in Godot (generated and keyed against the real 6thbuild skeleton),
not in Blender.

1. **Diagnose (CHECKPOINT after this).** Confirm how the current procedural
   mark clips look on 6thbuild and why (rest-pose mismatch, missing Neck).
   Report it with captured frames before building anything.

2. **Choose an authoring path and state why.** The likely-right shape is a
   rest-aware generator:
   - Clips are built in GDScript by composing rotations relative to each
     6thbuild bone's own rest (`rest * delta`), not by overwriting it.
   - Saved as `.res`/`.tres` Animation resources (or generated at load).
   - They override the procedural fallback through the same merge
     `_build_merged_library()` already does for imported clips.
   - Keep the procedural rig's own clips working; the umpire still uses the
     procedural rig.

   If you find a better route, explain the trade-off.

3. **Design the set with Madden's catch types as the language, mapped to
   AFL.** Minimum:
   - **Safe / possession** (`mark_safe`): the chest mark. Body square to
     the flight, arms gather into the chest, slight brace. A contested
     variant braces for contact when an opponent is inside
     `MARK_CONTEST_RANGE`.
   - **Running / catch in stride** (`mark_running`): the hands mark on the
     lead. Arms extend in front, the ball is taken without breaking stride,
     then it flows back into locomotion.
   - **Aggressive / high-point** (`mark_aggressive`): the leap and overhead
     grab, including a pack-mark/"speccy" read. Its contact timing has to
     match `ACTION_CONTACT[MARK_AGGRESSIVE]` (0.4 s rise) and
     `MARK_AGGRESSIVE_JUMP_SPEED`.
   - **Misses** (`mark_safe_miss`, `mark_running_miss`): the ball spills
     through the hands. Each miss starts from its catch's setup pose, as
     the procedural ones do. Decide whether Aggressive needs a dedicated
     miss/landing clip, and say so.
   - **Situational variants, chosen by context** (ball height at contact,
     flight direction relative to the player's facing, gait, contested or
     not):
     - Low/knee-height take.
     - Overhead take.
     - Over-the-shoulder take (running with the flight, Madden's
       over-the-shoulder catch). Use the APPROACH FROM bearing convention.
     - Contested braced chest mark.
     - Landing variants after an aggressive leap, clean and off-balance.

   Keep the selection logic in the animation layer
   (`player_animation.gd` / `HumanoidAnimations`-style selection by
   context). **The tier, reach and timing resolution in `player_controller.gd`
   must not change.**

4. **Physical plausibility, informed by the ragdoll system.**
   - The ragdoll is stage-1 passive. Use it as a reference and offline
     tool, **not** a gameplay system. One good use: pose the 6thbuild rig
     at an aggressive mark's peak or contact pose in the lab, let the
     passive ragdoll fall (optionally with a PUSH from the contest bearing),
     and use or bake what it does to inform the off-balance and
     knocked-in-the-air landing variants.
   - Author every clip so the future stage-2 hand-off (animation →
     ragdoll on a hard contested landing) has a clean pose to take over
     from. Note in the code which clips and frames are hand-off candidates.
   - **Don't** build stage 2+ (motors, hand-off logic) or wire the ragdoll
     into gameplay. That's its own decision.

5. **Preview and contact sync.**
   - Each clip's contact frame (hands meet ball) has to land on
     `ACTION_CONTACT[action]` after the press. Check the
     `ACTION_DURATION` / `ACTION_CONTACT` entries when clip lengths change.
     They're gameplay timings, so flag any change you think they need
     rather than silently editing them.
   - Add a marking preview to the animation viewer, either a mark contest
     or a SEQUENCES entry. A real kick delivered to a marking player from
     an APPROACH FROM-style bearing at a chosen speed and height, through
     the real marking code, like the existing contests do, so the user can
     watch each variant from any angle.

**CHECKPOINT:** report each clip and variant, how it's selected, captured
frames for each, and any timing mismatches you found. Then commit.

## Part 2: MLP stage, marking-cue timing

**Goal:** replace the MLP placeholder tab with a working stage, the same
quality bar as LR/GA: real controls, a self-test, and a verification run
against ground truth. Then apply it to the marking cue.

1. **Data from real physics, not synthetic formulas.**
   - Write a headless harness, in the style of `mark_challenge.gd` and the
     viewer's contest staging, that records 200–500 marking attempts.
   - Vary delivery geometry, player speed, approach bearing and press
     timing.
   - Record the planned features at press time and the outcome, from the
     real `mark_caught` / `mark_missed` signals and the real
     `mark_timing_offset`.
   - Fifth input: pick one and justify it. A good candidate is the approach
     bearing to the ball's flight (same convention as APPROACH FROM).
   - Save the dataset under `res://` with a short README of its columns.
   - Seed everything so it's reproducible.

2. **Model.**
   - A 5 → 8 → 8 → 1 MLP in GDScript, mirroring `tackle_model.gd` /
     `tackle_ga.gd`'s style: plain arrays, forward pass, backprop with a
     fixed seed.
   - Decide and state what the output means. The placeholder says "jump
     timing". The most useful definition is probably the predicted best
     press/clip-start offset relative to arrival, or a predicted
     ball-arrival correction to `mark_timing_offset()`.
   - Train/validation split. Show loss curves on the page; reuse
     `ga_fitness_chart.gd`'s chart approach.

3. **Verify like §7 of the ML audit learned to.**
   - Compare against the existing analytic `mark_timing_offset()` estimate
     on held-out attempts.
   - The audit notes that estimate is off by "several tenths of a second";
     check whether the MLP actually beats it.
   - Make sure the evaluation probes the whole input space, not one path
     through it. The GA fitness bug in §7 is the cautionary tale.

4. **Apply it to the marking cue.** Concretely:
   - Use the model's timing to fire the cue (the `MarkPrompt` /
     `RUMBLE_MARK_TIMING_CUE` moment), and to start the chosen mark clip,
     so the clip's contact frame meets the ball.
   - **Optional, behind a flag, off by default:** let `ai_brain.gd` use
     it to time presses and to choose Running/Aggressive when the
     prediction says they're catchable.
   - **Hard rule:** the model may only decide *when to press or animate
     and which tier to try*, a policy. It must **never** decide whether a
     mark succeeds. Success stays the physical reach-plus-timing
     resolution (RULES_REFERENCE §3). If any part of this seems to need a
     probability roll on the outcome, stop and ask; don't build it.

5. **Ask before** turning anything on in real matches (AI or human cue
   changes outside the dev pages). Build it, verify it, leave it
   switchable, and report.

**CHECKPOINT:** report the dataset, model and training results versus the
analytic estimate, what the cue integration changes, and what's still
behind a flag. Then commit.

## Hard constraints

- No outcome dice rolls anywhere in contest resolution (RULES_REFERENCE §3).
- Don't touch tackle resolution (`_resolve_tackle_contact`, `_try_tackle`,
  knockdowns).
- Don't rename the `Tuning.Action` enum. Don't renumber it.
- Don't build ragdoll stages 2–5. Don't put ragdoll physics into gameplay.
- Don't use PhysicalBone3D CONE joints (they're unstable under Jolt).
- Keep the procedural rig (umpire) working.
- Match the surrounding code style: long explanatory `##` comments that
  say *why*, `Tuning` constants with "unplaytested feel guess" caveats
  where true, and dev tooling under `scenes/dev` + `scripts/dev`.
- Commit on `update` only your own files (other sessions may share this
  checkout). Don't push.

## Verification (how to actually check things here)

- **Godot binary:**
  `D:\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`
  (not on PATH).
- **New `class_name` scripts:** rebuild the class cache first with
  `--headless --editor --quit --path .`.
- **Boot check:**
  `--headless --path . "res://scenes/dev/<scene>.tscn" --quit-after 300`
  should exit 0 with no errors.
- **Scripted physics checks:**
  - Write a scratch scene (`_scratch_*.gd` / `.tscn` at the repo root)
    that instantiates the real scenes.
  - Run it as a positional scene, not `--script`, which skips autoloads.
  - Always add `--fixed-fps 60`, `--quit-after N` and an explicit
    `get_tree().quit()`.
  - Delete the scratch files when done.
- **Visual checks:**
  - Run windowed with
    `--write-movie <scratchpad>/frames/x.png --fixed-fps 30 --quit-after 150 --resolution 1280x720`.
  - Read individual PNG frames.
  - This is how the last session caught a skinning bug the numbers missed.
- Report honestly what you verified headless, what you saw in frames, and
  what still needs the user's eyes in the editor.
