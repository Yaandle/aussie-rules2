# Movement animation and ragdoll tackle audit

2026-10-28. Scope: how a player's movement is animated, and how a tackle
or bump hands the body to physics and back. This covers how it works now,
what was wrong (with measurements), what changed, and what's left.
Everything was checked headless on 6thbuild. How it looks and feels still
needs your eyes (see the end).

## How it works now

**Movement.** `PlayerController._update_locomotion` turns stick input into
a velocity. Acceleration is 10.5 m/s², braking 14 m/s², and the turn rate
falls from 900°/s standing to 190°/s at a sprint. The body faces faster
than its velocity turns. `locomotion_blend()` reads that velocity in the
body's frame and hands it to `PlayerAnimation.drive()`, which positions a
2D blend space of eight clips: idle, jog, run, backpedal, two strafes and
two run diagonals. A TimeScale above the blend space matches leg turnover
to ground speed ("Stride matching"). Actions (kick, mark, tackle clips)
are states around it. After the tree mixes each frame, a post-pass tips
the spine for the drive lean and lifts the whole rig if a foot clips the
turf.

**Contact.** A Lunge (X), Slide (B) or bump decides whether it lands on
closing speed and angle. `TackleBalance` turns the contact into a balance
loss b and a push. `PlayerRagdoll` builds a `PhysicsRagdoll` on the
player's first tackle: 14 bodies, 6DOF ball joints, hinges at the elbows,
knees and ankles. It switches the skeleton to physics with motors at
strength 1 − b, a balance assist, and head and arm reflexes. The player's
capsule follows the hips while they fall. Once the body settles (or after
1.3 s) the bodies sleep and the player is lined up on the get-up clip's
lying frame. Physics then fades out over 0.3 s. A held X also puts the
tackler down with their arms round the carrier (`TackleWrap`).

A whiffed bump (2026-10-30) is a stumble on the same ragdoll, for a human
on a 6thbuild rig: strong motors (0.75), the balance assist carrying 80%
of the weight and reading tilt against the feet, a forward pitch at the
chest, and a hand-back to locomotion after 0.5 s while still up
(`PlayerController._bump_miss_stumble`, Tuning's "Bump miss"). The
procedural rig and any AI keep the canned fall.

Since 2026-10-30 a held tackle's outcome also depends on who wins the
collision (`TackleBalance`'s `drive`, the pair's mass-weighted common
velocity along the hit; Tuning's "Who wins the collision"). X: the carrier
out-muscling the tackler keeps their feet on the ragdoll and is held up
("stand"); an even collision knocks them over alone ("fall", tackler up);
a tackler driving through wraps and takes them down ("wrap", as before).
B: neither winning, or the carrier winning, holds them up with both
standing ("stand"); otherwise the hold-up clips or the sling, as before.
The stand reuses the stumble's strong-motor ragdoll. `tackle_sweep.tscn`
prints each case's outcome, drive and b.

## Findings and fixes

### 1. Ragdoll joints were centred on a random frame of animation (bug, fixed)

A `PhysicalBone3D` makes its joint when it enters the tree, from wherever
its body and its parent's body are at that moment. That pose is the
joint's zero, and it never moves. The lab and the bakes reset the skeleton
to rest before building. A match builds a player's ragdoll mid-run at
their first tackle, so every joint limit for the rest of the match was
centred on that one frame.

- Measured: an elbow built while bent 90° snapped to 115° when the body
  later went rigid with a straight arm.
- Across 15 Lunges on the old code, carriers' thighs swung up to 96°
  behind the pelvis and knees folded to ~180°. Tacklers were the same.

**Fix:** `PhysicsRagdoll.build()` builds at rest and hands the pose back.
`joint_report()` now measures from the rest pose too.

### 2. Joint limits weren't anatomical (fixed, within what Jolt holds)

Every clip was sampled at 60 Hz against the joint limits and adult ranges
of motion:

- **Hips:** ±60° let a leg swing 60° behind the body (a real hip stops at
  ~20-30°; the run clips reach 26°). They also capped forward flexion at
  60°.
- **Spine:** it bent as far back as forward.
- **Knees and elbows:** they could never straighten past their rest bend,
  and an elbow could fold to 166°.
- **Ankle:** the run clips reach 33° of dorsiflexion against a 25° limit,
  so a body going rigid mid-stride snapped its foot.

**Fix:** BALL joints take an optional asymmetric `flexion` range:

| Joint | Old | New |
|---|---|---|
| Hips | ±60° | 30° back / 65° forward, sideways ±45° |
| Spine and chest (each) | ±25° | 15° back / 35° forward, sideways ±20° |
| Knee | 0 to 140° from rest | −10 to 135° |
| Elbow | 0 to 140° from rest | −25 to 120° (now straightens) |
| Ankle | −40 to 25° | −45 to 35° |

The hips stop at 65°, not a real hip's ~110°. Pushed steadily forward,
Jolt's 6DOF swing limit held clean at 65°, bounced at 70-75°, and came
apart from 80° (the thigh snapped back through 100°). Building the hip
pre-bent to the middle of a wider range held in that push test. In real
falls it tripled the spin spikes, and one thigh tore round to 172°.

### 3. The wrap yanked the tackler's arms on its first tick (fixed)

On the bind tick the wrist grip servo tried to cancel the wrist's whole
velocity off the carrier's waist in one go, which can be the full closing
speed. Measured: the arms whipped at 45-105 rad/s for a frame before the
reach began. This happened on the old code too, at 43-62 rad/s. With the
wrap off, going rigid is smooth (~5 rad/s).

**Fix:** the grip and the hug ramp in over `TACKLE_WRAP_GRIP_RAMP` (0.12 s).
The worst first-frame spin dropped to 45 rad/s.

### 3b. The wrap's grip was sized ~6× too strong sideways (fixed)

This was the "pinned forearm" left open below, and it wasn't a pin. A probe
logged every frame a tackler's elbow was past its limit. 38 of 42 were
during the reach, still on their feet, not once down. The grip servo
worked out its pull from the forearm and upper arm's mass (3.15 kg against
the waist). Pushed sideways, a wrist is the tip of a 2 kg forearm and
feels about 0.5 kg, so each tick the pull did ~6× the correction it meant
to. Every tackler's forearm whipped at 40-50 rad/s in the reach, and a
folded arm slammed its elbow 20-47° past the stop.

**Fix:** `PhysicsRagdoll.point_mass()` gives how heavy a point on a body
feels along a direction (its mass and inertia, as if free). The grip sizes
each pull on it. A free body is the lightest the jointed arm can feel, so
the servo can under-correct but not overshoot. The reach's IK also stops
asking for more than 100° of elbow bend (`TackleWrap.ELBOW_MAX_BEND`),
which on its own made little difference.

| Tackler, 12 Lunges | Before | After |
|---|---|---|
| Worst spin | 335 rad/s | 52 |
| Spin in first 0.1 s | 45 rad/s | 23 |
| Fastest body | 21 m/s | 12 |
| Frames an elbow is >5° past its stop, reaching | 37 | 5 |
| Worst elbow overshoot | 47° | 8° |
| Went down | all | all |

The cost: the grip is looser. The wrist's mean gap to its grip point went
from 0.34 to 0.40 m while reaching and 0.20 to 0.32 m once down, and 23 of
24 arms got round the carrier (24 before). A higher gain to win it back
brought the whipping back (0.65 and 0.8 both did), and the down-phase
grip settings (`TACKLE_WRAP_DOWN_GRIP`, `DOWN_DEADZONE`) no longer change
anything, because the grip never reaches its force cap now.

### 4. The gait clips drifted out of step (bug, fixed)

The comment on the blend space said `sync = true` locks every clip to a
shared phase. It doesn't. In Godot it only keeps a clip's clock running
while its weight is zero, and each clip loops on its own length. 6thbuild
has two lengths: 0.708 s for the jog family and 0.542 s for the run
family. Between jog and sprint pace the two drift half a stride apart
every ~1.2 s, and the blend averages a planted foot with a swinging one.
The strafes and backpedal weren't even in step at the start.

**Fix:** "Gait phase lock" in `PlayerAnimation`. Once per model, every
stepping clip is resampled to the jog's length and turned round its loop
so the middle of the left foot's stance lands at time 0. Stride matching
measures the rebuilt clips, so cadence is unchanged: 3.3, 4.25 and 5.2
steps/s at 4.6, 6.5 and 8.4 m/s, as before.

How often the supporting foot slips forward relative to the hips (it
should only ever sweep back):

| Blend | Before | After |
|---|---|---|
| Jog-to-sprint mix (6.5 m/s) | 21% of frames | 6% |
| Running turn | 9% | 5% |
| Strafe-jog | 4% | 0% |

The run and jog clips on their own slip in 4-6% of frames, so the mix is
now as clean as its clips. The procedural rig's clips already started in
step and slip ~40% on their own; the lock makes their mix match them,
rather than the damped average the drift produced.

### 5. The drive lean popped upright at top speed (fixed)

Speed climbs at a constant rate and stops dead at the top, so the lean
fell from 12° to 4° in a couple of frames. It now eases off at
`LEAN_RELEASE_SMOOTHING` (3.5/s) while still running, which takes about
0.7 s. Leaving locomotion still clears it fast.

### 6. Nobody leaned into a turn (added)

"Turn bank" rolls the spine toward the inside of a turn by
atan(sideways acceleration / g) × 0.6, capped at 14°. It uses the body's
real velocity, so it reports the physics the same way the strafe axis
does. A sprint cut banks ~13° and settles as the turn completes.

### 7. The get-up fade was linear (eased)

Physics' influence now fades out on a smoothstep, so the body doesn't
jerk into motion at the start or kink onto the clip at the end.

### 8. The kick, the ball carry and the hand-off (playtest, fixed)

Playtest 2026-10-28: the kick's "knee comes up high but the leg isn't doing
the kicking motion", the ball "is just sitting on its hip floating" with
the arms out in a "45 degree sort of t-pose", and control switched before
the kick finished.

- **Kick.** Sampled on 6thbuild, the old clip's contact had the thigh 70°
  up, the shin hanging straight down and the knee bent 79°. The
  follow-through had the thigh at 134° (past horizontal) and the knee bent
  114°. Its boot targets sat 0.5 m ahead of the hip, out of a straight
  leg's reach. The clip is re-authored as a right-foot drop punt from the
  two-hand carry, the kicking leg keyed by joint angles (`solve_leg`):
  - **Step and drop:** step onto the left foot, then let the ball go over
    the right foot at 0.16 s.
  - **Swing:** the heel kicks up behind, then the knee drives through.
  - **Contact:** thigh 61°, knee 37°, foot pointed 69° past square, the
    ankle 0.78 m out and 0.33 m up.
  - **Follow-through:** the leg straight (knee 0-5°) and high, with the
    toes forward.

  `BootPoint` moved onto the instep at contact (0.95 m out, 0.34 m up, was
  0.52/0.32), so kicks now launch from there.
- **Carry.** A `carry` clip (both hands on the ball in front of the
  belly, elbows in) is laid over the arm bones by a filtered Blend2 while
  the player has the ball. The ball rides `BallHold`, which
  `PlayerAnimation` moves to where the hands have it each frame. On the
  kick it falls from the hands onto `BootPoint`, timed on the gameplay
  clock. Handballs and bounces now launch from the hands. From
  `CarryPoint` they jumped 0.33-0.38 m back at release, and the bounce is
  still re-gathered at 0.6×-1.4× pace. Gameplay reach still measures from
  `CarryPoint`.
- **Clip lag.** Every action clip ran ~2 frames behind the gameplay clock
  (an AnimationTree travel lands on its next update). `play_action` now
  advances the tree right after it, so the boot meets the ball on the
  launch frame (instep 0.92 m out against `BootPoint`'s 0.95, was 0.53).
- **Hand-off.** FULL_TEAM control now waits out the rest of the kick clip
  plus `Tuning.FULL_TEAM_KICK_SWITCH_HOLD` (0.2 s): 0.57 s after the ball
  leaves the boot, measured in a quick-play match. It was the same frame.

### Before and after, ragdoll

`scenes/dev/tackle_sweep.tscn` gives each pair of already-running 6thbuild
players their first tackle. These are the 15 Lunge cases (8 bearings
running, 3 standing, 4 mixed):

| | Carrier, old → new | Tackler, old → new |
|---|---|---|
| Thigh swung behind pelvis (worst) | 96° → 50° | 101° → 56° |
| Knee folding | 178° → 11° | one splayed-leg reading either way |
| Spine bent back (worst) | 81° → 58° | 68° → 72° |
| Spin in first 0.1 s (worst) | 41 → 30 rad/s | 62 → 45 rad/s |
| Went down | 15/15 → 15/15 | 14/15 → 15/15 |

A wider 24-case run gave the same picture, with fewer spin spikes past 60
rad/s (new 2, old 7). Three tacklers ended propped on their knees there
(hips above the "down" line); the old code had none in that run. Falls
are chaotic, so watch for it.

## What's left, in priority order

1. ~~Pinned forearms in the wrap.~~ Fixed: it was the grip's sizing
   (3b above), not a pin.
2. **Overshoot at ground impact.** Spine and chest overshoot their limits
   by 10-45° for a frame or two as the torso lands. Options: raise Jolt's
   solver iterations (`physics/jolt_physics_3d/simulation/velocity_steps`
   and `position_steps`) or run physics at 120 Hz, which the lab measured
   halves landing penetration. Both are project-wide costs, so profile
   first.
3. **Limb velocity at the hand-off.** Every body starts at the player's
   velocity, so a swinging leg stops dead the instant physics takes over.
   Sampling the last two rendered poses gives each body its own velocity.
   It needs care where render and physics rates differ (LESSONS.md), so
   it wasn't done here.
4. **A downed player still has a standing capsule.** Others collide with
   an invisible standing-height body over a player lying on the turf.
   Shrinking it while ragdolled is a gameplay call.
5. **The speed curve has a corner.** Constant acceleration to top speed,
   then a hard stop, which is what made the lean pop. Tapering acceleration
   over the last ~1.2 m/s would cost ~0.12 s to top speed. That's a
   gameplay feel change, so it's left for a playtest decision.
6. **Feet.** The foot fix only lifts the whole rig. Per-leg two-bone IK
   with 6thbuild's own pole targets would lock planted feet. The phase
   lock's stance measurement already finds when each foot is down.
7. **Turning on the spot** spins the body at 720°/s over an idle pose with
   sliding feet. It needs a turn-in-place clip or a procedural step.
8. **Re-bake the off-balance mark landing.** `mark_landing_bake` writes
   `assets/animations/mark_offbalance_ragdoll.json` from the passive
   ragdoll, which was baked under the old limits. Re-run it if the landing
   should reflect the new hips and spine.
9. **Root motion for contest outcomes** (MECHANICS_AUDIT §A5), as before.

## Needs your eyes

- **The kick and the carry** (section 8): the drop punt's look, the ball's
  drop, the carry pose while sprinting, and the 0.2 s hold before the
  hand-off. Kicks launch 0.43 m further forward than before.

- **The phase lock:** accelerate from a jog to a sprint and cut. The feet
  should stop scissoring.
- **The bank:** 14° max, `BANK_SHARE` 0.6, both guesses. **The lean
  release:** 3.5/s.
- **Tackles:** legs no longer fold behind the body, and the tackler's arms
  close a beat softer. Check the X wrap still reads as a grab: since 3b
  the hands sit a few centimetres further off the carrier's waist.
- **Tacklers propped on their knees:** watch for any that rise straight
  back up.

## How to re-check

- **Tackles:** `godot --headless --path . res://scenes/dev/tackle_sweep.tscn --fixed-fps 60 --quit-after 700`.
  The script header explains each column.
- **The gait comparison** was a scratch scene and has been deleted (see
  the commit message). It ran two animation stacks, phase-locked and
  original, with the original's own strides measured, at fixed blends,
  sampling the feet after the tree mixed.

## 2026-11-09: Build 7 motion (Phase 2 of the Build 7 polish)

Measured with `scenes/dev/anim_audit.tscn` (new): a real player on a
scripted brain through jog, sprint, start/stop, 90° and 180° cuts, a weave,
a walk and turning on the spot, plus every clip sampled on a bare rig.
Slip is a planted sole's speed over the turf (heel, ball and toe sampled;
planted = within 1.5 cm). Everything here is Build 7 only: its clips live
in `assets/blender/7thbuild.blend`, and Build 6's audit and tackle sweep
are unchanged (sweep byte-identical to the 2026-10-30 baseline).

| Build 7 vs Build 6 | Build 6 | Build 7 |
|---|---|---|
| Walk 1.8 m/s: slip mean | 1.35 m/s | 0.32 |
| Jog 4.8 m/s | 1.49 | 0.75 |
| Sprint 8.4 m/s | 2.88 | 1.22 |
| 90° cut at a sprint | 3.03 | 1.18 |
| Pelvis / chest yaw in a sprint (peak to peak) | 0° / 0° | 17° / 26°, counter-turning (corr -1.0) |
| Arm swing L/R | 73° / 57° | 53° / 53° |
| `smother_dive` peak bone speed | 92 rad/s (snap upright at the end) | 26 |
| `tackled` peak | 50 rad/s (both knees flipped twice) | 38 |

What changed:

- **New gait clips** (`tools/blender/author_7thbuild_gaits.py`): walk,
  jog_fwd, run_fwd and the run diagonals from a parametric model. The ball
  of each foot sweeps back at the design speed while down and the foot
  rolls over the toe tip (the foot is one rigid bone: rolling over the ball
  sank the toe 6 cm into the turf). The swing leaves and lands moving back
  with the turf. Pelvis bob and turn, chest counter-turn, head steady,
  arms opposite the legs. All on the jog's 16-frame cycle, so phase lock
  never stretches them; stride matching sets the cadence. Every pose stays
  inside the ragdoll's joint limits (the first cut went 50° back at the hip
  and a tackle mid-stride snapped it at the hand-off).
- **A walk blend point** at walking pace for a model with a walk clip, and
  a lower stride-rate floor (0.6) for such a model. Without one, BLEND_POINTS
  and STRIDE_MIN_RATE (0.85) are as before; lowering the floor for every
  model changed Build 6's sweep, so it does bind somewhere.
- `mark_running`, `mark_running_miss` and `bounce` re-authored on the new
  run's legs (same specs and frame counts).
- **smother_dive** pushes up off the turf after contact and ends in a low
  crouch instead of snapping upright; the blend back to locomotion is 0.32 s
  for that state (ACTION_BLEND_OUT_BY_STATE). ACTION_DURATION is unchanged.
- **Knee flips** (`tools/blender/fix_7thbuild_knee_flips.py`): `tackled`'s
  knees flipped to the other side at 0.40 s and back at 0.96 s, both legs
  bent ~90°, and the ragdoll get-up plays that stretch. The IK poles are
  re-keyed so each knee keeps bending one way.

Not done, and why:

- **The tackle hand-off on Build 7 starts faster.** tackle_sweep on Build 7
  (temporary copy, MODEL_ID = "7thbuild"): start worst 43 / 48 rad/s
  (carrier / tackler) against 22 / 19, mostly the light foot bodies; spin
  worst 93 against 82; every carrier still down. The ragdoll starts from the
  animated pose, and the new stride puts ankles and knees at different
  angles when the tackle lands. Matching per-limb velocity and easing the
  pose into the joint limits at the hand-off is Phase 3 work ("What's left"
  3); until then, watch the first frames of Build 7 tackles.
- **Turning on the spot** still spins over the idle pose (slip 1.5 m/s on
  both builds). A stepping layer or a turn clip is next.
- **Head look** (into turns, at the ball) isn't built.
- `mark_aggressive`'s arms fling up at ~57 rad/s in the first 0.08 s: as
  authored, unchanged.

### Design call: the (Y) ring against (A) in AUTO (applied 2026-11-09)

`PlayerController.live_mark_prompt()` lights a tier from distance: (Y)
Aggressive as soon as the ball is within `MARK_CONTEST_RANGE` of the carry
point, (A) Safe only once it's within Safe reach of the hands, which is
later on every delivery. The ring counts down to the live tier's ideal
press, so it completes for (Y) before (A) is ever live, and a player who
presses what the prompt shows leaps every time. GATED only holds (Y)'s ring
until a press could register; it doesn't change which tier is shown.

Recommendation: choose the prompted tier from the predicted take, not the
current distance. Run the ball's flight forward (PlayerAnimation's
`_flight_crossing` already does this, gravity-only, ~1 s), and prompt (A)
with its own countdown when the flight will pass within Safe reach of the
hands and nobody's contesting; prompt (Y) only when an opponent is within
`MARK_CONTEST_RANGE` or the ball will pass above Safe reach. The ring then
teaches the right call instead of always the leap. It's a cue change only
(RULES_REFERENCE.md §3: resolution never reads it).

Applied on the user's go-ahead as `PlayerController.prompt_mark_tier()`,
which MarkPrompt and the animation viewer's AUTO read; `live_mark_prompt()`
(which the AI also reads) is unchanged. Headless, one standing player,
28 m deliveries: uncontested chest-high showed Y then A, now A throughout;
contested stays Y then A; over the head stays Y.

## 2026-11-09: contact and collisions (Phase 3 of the Build 7 polish)

### The Build 7 hand-off regression (fixed)

Phase 2 left Build 7's tackle_sweep starting falls at 43 / 48 rad/s
(carrier / tackler) against Build 6's 22 / 19. Diagnosed with prints at
`PhysicsRagdoll.start()` (temporary, removed):

- `physical_bones_start_simulation()` doesn't move the bodies: 0.000 m and
  0.0° from `snap_to_pose()` on every hand-off, both builds.
- No joint was over a bend limit except one elbow by 11°, so easing the
  pose into the limits (tried and reverted last session) had nothing to
  ease. That's why it changed nothing.
- The spike was the **forearms** on the first tick (43 rad/s right, 29
  left), not the feet. The elbow is a hinge, and Build 7's gait arms bent
  their elbows 50-84° off its axis (Build 6: under 6°). Jolt snaps that
  straight onto the hinge in one tick. `joint_report` measures bend only,
  so every joint read "inside its limits".
- Cause: the arm IK (`author_6thbuild_clips.solve_arm`) takes the upper
  arm's shortest turn and keeps whatever roll that leaves. Rolling the
  upper arm onto the hinge alone needed up to ~100° of shoulder twist,
  past the joint's 60° stop, because the rest pose's carrying angle puts
  the elbow's plane off the upper arm. `solve_arm(..., hinge=True)` now
  searches the elbow's swivel about the shoulder-to-wrist line and the
  upper arm's roll together (twist up to 58°, swivel at most 20° off the
  authored pole). Build 7's gaits use it; Build 6's clips don't (they
  re-author byte for byte as before). The wrists land where they did.
  Swivel is the visible cost: allowed 75°, the fit was near perfect but the
  run's back swing lifted the elbow almost level behind the body
  (`docs/review/7thbuild/phase3_arms_close_side.png` is the 20° version
  against before).

Result on the 21 standard cases:

| tackle_sweep | Build 6 | Build 7 before | Build 7 now |
|---|---|---|---|
| start worst, carrier / tackler (rad/s) | 21.9 / 18.8 | 42.6 / 47.9 | 17.5 / 18.0 |
| elbows off-axis at hand-off | < 6° | 50-84° | 15-27° |
| joints over a limit at hand-off | none | one elbow +11° | none |
| carriers / tacklers down | 17/20, 11/12 | 17/20, 10/12 | 17/20, 10/12 |
| spin worst, carrier / tackler | 82.3 / 47.2 | 92.8 / 47.9 | 82.4 / 117.9 |

Build 6's sweep is byte-identical to its 2026-10-30 baseline. Knees and
ankles still sit 5-14° off their hinge axes on both builds (the legs come
from Blender's own IK); that's small, and the same on Build 6.

One run of 21 cases is a thin sample (a one-line change elsewhere gave
Build 6 a 227 rad/s outlier), so the same sweep was run at eight run-in
lengths (61-90 frames), 256 falls per build:

| 256 falls | start median / p95 / max | spin max | blowups (spin > 150 or joint > 90°) |
|---|---|---|---|
| Build 6 | 10 / 19 / 60 | 164 | 2 (both upper arms) |
| Build 7, swivel up to 75° | 9 / 18 / 60 | 141 | 2 |
| Build 7, swivel up to 20° (shipped) | 16 / 18 / 60 | 288 | 5 (3 elbows torn backwards) |

The shipped fit trades some start spin (the 15-27° the hinge still snaps
out) for an arm swing that looks like the authored one. **Open:** 3 of
Build 7's 256 falls tore an elbow through its -25° stop as the body
landed (Build 6: none). That's ground impact, not the hand-off ("What's
left" 2: more solver iterations or 120 Hz physics); the elbow servo or
a softer arm at impact are the cheaper things to try first.

### How contact resolves now (audit)

| Contact | Decided by | What the bodies do |
|---|---|---|
| Lunge (X) | `TackleBalance` (closing speed, angle, mass; threshold, never a roll) | ragdoll at 1 - b; wrap (`TackleWrap`), fall or stand by who wins the collision |
| Slide (B) | same, knockdown b floor | hold-up clips, or the sling on the ragdoll; stand when neither wins |
| Bump (hit stick) | approach dot at the moment the bodies meet | clean: carrier thrown on the ragdoll, bumper dives; mistimed: `receive_bump` knockback |
| Bump miss | nobody in reach when the dash ends | a human on a 6thbuild-skeleton rig: the stumble ragdoll (strong motors, 80% support); AI: the canned fall |
| Contest hip-and-shoulder | closing speed and approach dot | clean: ragdoll; glancing: `receive_bump`; slow: `_contest_nudge` |
| Ruck jostle | ruckmen within `RUCK_COLLIDE_DISTANCE` | a human in it: short ragdoll stagger; else `_knockback` |
| Running into each other | nothing | capsules slide off each other; until now, no reaction at all |

Two gaps stood out. Every non-ragdoll contact (a glancing bump, a nudge, a
ruck shove on the AI, two players colliding) changed only velocity: the
animation never knew. And a ragdoll is all or nothing: there's no partial
ragdoll for a glancing hit.

### Design

1. **Contact reaction (built, visual only).** A spring on the torso in
   PlayerAnimation's post-mix pass, kicked by the contact's change in
   velocity: it rocks away from the push and back (3 Hz, 0.45 of critical
   damping, capped at 18°). With the other body in front the arms come up
   to it (55° of shoulder flexion, held 0.3 s): hands on the other body.
   Fired by capsules meeting at 1.5 m/s or more closing (both players,
   0.4 s cooldown), `receive_bump` (glancing bumps, contest nudges), the
   nudging player's own recoil and a non-ragdoll ruck jostle. Nothing in
   gameplay reads it, and any ragdoll clears it, so the ragdoll still
   starts from the plain animated pose. Constants: PlayerAnimation's
   "Contact reaction" and Tuning's "Body contact reaction".
2. **Shoulder-to-shoulder lean and push (next, gameplay).** Two players
   running side by side and pressing should lean into each other, and the
   heavier or faster one should move the other off their line. That's a
   force between capsules, sized by mass and closing speed like
   `TackleBalance`'s drive, so it changes contests: it needs named Tuning
   constants and a playtest, not a quiet change. The contact reaction's
   sideways sway is the visual half already.
3. **Exact hands on the body (next).** The brace swings the arms forward;
   it doesn't put the palms on the other player. Real two-bone arm IK at
   runtime (the same fit as `solve_arm`'s hinge search, but per frame)
   aimed at the other player's chest. The 6Q idea of hands on a wall is the
   same solver with a raycast target.
4. **Partial ragdoll for glancing hits (next).** Simulate the upper body
   only (Spine, Chest, head, arms) with the legs kinematic on the clip,
   for 0.3-0.5 s at strong motors, then hand back. Godot's
   `PhysicalBoneSimulator3D` can simulate a subset of bones
   (`physical_bones_start_simulation(bones)`); the motors already drive
   per joint. Today's stumble and stand ragdolls go whole-body because the
   balance assist is whole-body; a partial one wouldn't need it.
5. **Cleaner transitions in and out.** In: Phase 3's hinge fix is the
   biggest part; per-limb velocity at the hand-off ("What's left" 3) is
   still worth doing, sampled on `SceneTree.physics_frame` (LESSONS.md).
   Out: the get-up already fades physics into the clip over 0.3 s; a stand
   or stumble should fade into locomotion at the body's own lean, not
   upright.

Balance: nothing above touches `TackleBalance`, the GA weights in
`data/ml/tackle_weights.json` or the MLP mark cue. Item 1 changes no
contest. Items 2 and 4 would, and need the user's go-ahead.

## 2026-11-10: Contact on the motor ragdoll

The user's brief: players that bump or touch without a tackle should still
be moved by it, a tackle that leaves both standing (a ball-up) should show,
and nothing should snap to a stiff clip. Phase 3's contact reaction was a
procedural sway; this puts the knock on the active ragdoll.

### What changed

| | Before | Now |
|---|---|---|
| Two players colliding, a glancing bump, a contest nudge, an AI ruck shove | procedural torso sway | **upper body on physics** over animated legs (PlayerRagdoll REACTING, PhysicsRagdoll "Upper-body reactions"); the sway stays as the procedural rig's fallback |
| A tackle that lands but breaks | carrier's speed x 0.75, nothing visible | both bodies knocked: the carrier lurches forward over the grab, the tackler is yanked after them |
| A held-up tackle (AI Slides; the tackler in a human's "stand") | TACKLE_GRAB / TACKLE_HELD clips, both stopped dead in one frame | the clips with both trunks on physics; the pair moves on at their common velocity and brakes out (TACKLE_HOLD_BRAKE, ~2 m from a sprint) |
| Stand, bump-miss stumble, ruck stagger (whole-body ragdolls that stay up) | muscles pull toward the pose at contact, frozen mid-stride | muscles pull toward the live animation (`track_pose`) |
| Stamina | didn't exist | per player, drains above a jog; sets body tone only (knocks looser, ragdoll muscles weaker), never an outcome |

How hard a knock is comes from the tackle formula: tone = 1 - 0.85 b, with
b = `TackleBalance.balance_loss` on the contact (closing speed, how square,
mass ratio), times stamina's tone. The numbers are in Tuning's "Physical
contact reactions" and "Stamina".

### How the partial ragdoll works, and what it took

The trunk, head and arms simulate; the hips and legs stay posed on the
animation, so the spine's joint to the hips keeps the trunk on the legs.
The trunk follows the animated pose at a rate set by tone (14/s at full)
and stiffens toward full between 15 and 35 degrees off it. The arms have
joint motors only (a carrier's also follow their carry pose relative to
the physical chest). Each problem `scenes/dev/contact_sweep.tscn` found, in
order:

1. **Motors alone sag** a trunk 0.6 m behind a sprinter: hence the follow.
2. **A tick of lag, twice.** The posed hips body only moves when the
   skeleton updates, after the physics step; and Godot copies body state to
   nodes at the start of the *next* tick, so what renders is a tick old.
   Together the trunk drew 14 cm behind the legs at a sprint. The reaction
   now steps after `move_and_slide` with the hips put on the animated pose,
   and `sync_partial_nodes()` copies server state to the nodes before the
   skeleton draws. The rendered trunk is within ~3 cm.
3. **Unsimulated bodies collide.** With any bone simulating, Godot makes
   the rest kinematic with collision on: a held-up tackler's animated legs
   shoved the carrier's standing ragdoll 1.7 m. Partial bodies touch only
   the ground; the posed ones touch nothing.
4. **Arms fought their limits.** A world-space follow on the arms, where a
   clip reaches past the joints (TACKLE_GRAB), buzzed the chest +/-20-60
   degrees at 40-90 rad/s. The arms got motors only.
5. **Kinematic arms jointed to a simulated chest** (a carrier's, left on the
   animation to keep the ball) wrenched it to 55 degrees. Every reaction
   simulates the arms.
6. **The inertial lurch** (the trunk starting at the pre-contact velocity)
   is right for a grab that stops the legs and wrong for a shove: a bump
   whipped the trunk round the hips at 40 rad/s. Only the broken tackle's
   drag uses it, at half.
7. **A pre-existing bug:** a ~40 m/s kick arriving under a catcher's
   capsule counted as a moving platform, and the catcher left the catch at
   41 m/s (reproduced with every contact feature off).
   `platform_floor_layers` is now the world only.

### Measured (contact_sweep: 18 knock cases and 7 contested marks)

| | Build 6 | Build 7 |
|---|---|---|
| Chest jolt beyond the clip, worst | 15 rad/s (one repeated knock 22) | 14 (repeat 23) |
| Trunk-to-hips gap, worst | 3.6 cm | 3.4 cm |
| Ball from a knocked carrier's wrists | <= 0.39 m (animated hands 0.1-0.35) | <= 0.39 m |
| Contested marks (Build 6) | the winner plays `mark_safe_contested` over the knock; jolt 12-25 rad/s, waist <= 3.7 cm | |

`tackle_sweep` (falls): Build 6's summary is identical to the 2026-10-30
baseline; rows shift by centimetres where a reacting tackler's ragdoll now
exists (Jolt's solver order). Build 7's one 94-degree elbow tear is
pre-existing: it's the same with every new feature off (Phase 3's open
ground-impact item).

### Still open

- **How big a knock should look.** Tone and push are first guesses; a
  head-on sprint collision moves the chest ~30 cm. Playtest.
- **Stamina into outcomes.** It's body tone only. Feeding it into
  `TackleBalance` (the ML model's original third input) would change who
  wins contacts: a gameplay call.
- **Shoulder-to-shoulder push** (Phase 3 design item 2) and **hands on the
  other body** (item 3) aren't built.
- **Turning on the spot**, **per-leg foot IK** and **limb velocity at a
  full ragdoll's hand-off** are as before.

## 2026-11-10: the held-up wrestle and direction from the angle of contact

Phase 2, steps 1-2 of `docs/prompts/fable_pass_1.md`. Whether a tackle
holds is still `TackleBalance`'s threshold; this moves the bodies by it.

### The wrestle (`PlayerController._step_wrestle`, Tuning's "The held-up wrestle")

A held-up pair used to meet at its common velocity and brake out. Now, for
the length of the hold, it is one body driven by both players' legs: the
tackler along the line into the carrier at effort b, the carrier the way
they were running at effort 1 - b, each times mass and stamina tone, with
the feet bleeding speed on a 0.3 s time constant. The tackler's sideways
speed at contact swings them round the carrier. Both trunks stay on physics
for the whole hold (`PlayerRagdoll.sustain`), lean into their own drive as
the motors' target (`PlayerAnimation.set_press`) and take the force between
the bodies on the chest (`press`). The legs step on the locomotion blend
under the hold-up clips. At the end the trunk's remaining tilt becomes the
animation's own sway (`adopt_lean`), so physics fades into a pose that is
already where the body is.

Measured, `contact_sweep`, metres moved in the hold's second (along the hit
line / to its left), tackler then carrier:

| Hold | Before | Now |
|---|---|---|
| Head-on, both sprinting, even | braked at ~0 | 0.62 / 0.56: carrier walked back |
| Head-on, tackler 95 kg v 70 | same | 1.06 / 1.00 |
| Head-on, tackler 70 kg v 95 | same | 0.17 / 0.11: the carrier stands |
| Side-on (90° or 270°) | along the carrier's run | 1.9 along, 1.1 across: diagonal |
| From behind (b 0.13) | carried on, braked | 2.46 / 2.41: carrier drags the tackler |
| Head-on, tired carrier / tired tackler | no difference | 1.24 / 1.02 |

Trunk twist off the clip in a hold is 5-23°; the worst snap in a hold row
is 38 rad/s (the 95 kg tackler; the old worst row was 48).

### Direction from the angle of contact (`PlayerController.contact_change`)

A knock's change of velocity is the closing speed along the contact normal
plus the rubbing speed across it, capped at `CONTACT_FRICTION` times the
first, landing on the chest's surface toward the other body. Glancing bumps
and contest hits knock their target along that, not along the bumper's run.
New sweep rows cover 270°, 225°, the rear, glances from four sides and
holds off the line. `contact_sweep` also prints which way each chest went
(`away`), its twist and how far each capsule moved.

### What it found, not fixed

- **A runner hit side-on still isn't moved sideways.** Their chest goes 90°
  off "away from the hitter": the capsules only slide, so the trunk's lag
  is the runner's own deflection. Step 3's shoulder push is what moves them.
- **A body whose facing whips drags its trunk.** One contested-mark row's
  loser turns 52° and back in a quarter second; the trunk, capped at
  14 rad/s, lags 73° and snaps at 65 rad/s (16 before this pass; friction,
  the chest lever and the lean hand-back were each ruled out). The follow
  should carry the body's own yaw rate.
- The stand ragdoll and the bump-miss stumble (whole-body) still hand back
  upright; only upper-body knocks adopt the lean.
- `contact_sweep` in one line ran past x = 500 m with the new rows, where
  `_contain_to_field` squeezes pairs into a heap. New rows go on a second line.

## 2026-11-11: shoulder push, hands on the body, and why the AI never ragdolls you

- **Shoulder push** (`PlayerController._shoulder_push`, Tuning "Shoulder-to-shoulder push"):
  see commit 5341a61 for the sweep numbers (rows 40-44 of `contact_sweep`).
- **Hands on the other body** (`ArmIK`, `PlayerAnimation._hands_on_other`): a knock
  with `hands` now solves two-bone IK each frame onto the other player's chest,
  elbow swivel + upper-arm roll searched onto the ragdoll's elbow hinge (the
  same fit as `solve_arm(hinge=True)`). The partial ragdoll's arm motors follow
  that animated pose. `take_knock(..., by)` carries the other body. A raycast
  hit point would work as the target too (6Q, "hands on a wall"). Not checked by eye.
- **Why the AI never lands a ragdoll tackle on the human (6T).** The AI's only
  tackle is Slide. Every ragdoll start on a Slide is gated on the *tackler*
  being human: the sling (`_slide_connect`, `_brain is HumanBrain and won and
  b >= TACKLE_SLIDE_KNOCKDOWN_B`) and the stand ragdoll (`_hold_up`'s
  `stand_impact` only `if _brain is HumanBrain`). Lunge and the contest bump
  are human-input only. The one exception is the ruck collision, which ragdolls
  if either player is human. Options, none built: (a) gate on *either*
  player being human, as the ruck already does: the AI slings or stands you up
  with the same b threshold, and AI-v-AI stays on clips (cost unchanged);
  (b) give the AI a Lunge in `AIBrain` (balance and tuning work); (c) keep it.
  (a) is a two-line change plus a playtest of how often it fires.
