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
