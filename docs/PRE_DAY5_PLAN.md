# Pre-Day-5 plan: smooth, controllable gameplay

Written 2026-11-18 from an audit of the W47 Context task board, the open
lists in `docs/MECHANICS_AUDIT.md` and `docs/ANIMATION_RAGDOLL_AUDIT.md`,
`docs/PLAYTEST_CHECKLIST.md`, the code, and one measurement. The user's
brief: smooth "FIFA-style" Full Game, full-side and chase cameras that feel
fluent, the marking cue earlier, every player easy to control, switching on
demand and automatic switching that works. No DQL (ML Stage 4) yet. The
character model, motor control and ragdoll work comes after these.

Each workstream below is written so an agent session can start from it
cold. Read `CLAUDE.md`, then `docs/LESSONS.md`, then the workstream.

## What the audit found

### Measured: the Full Game runs at ~32 fps

Windowed 1920x1080 Full Game on the dev machine (GTX 1660 SUPER), 40 s
after a 5 s settle, 2026-11-18 (`update` at 9ac21af):

| | p50 | p95 | p99 | max |
|---|---|---|---|---|
| frame | 31.4 ms | 50.2 ms | 64.9 ms | 86.7 ms |
| physics process (`TIME_PHYSICS_PROCESS`) | 14.2 ms | 25.7 ms | | 42.3 ms |

`TIME_PROCESS` ~18 ms, 849 draw calls. The frame is CPU-bound (process +
physics ≈ the whole frame). This is the biggest single reason play doesn't
feel smooth: 60 fps needs everything under 16.7 ms. Nothing about it is in
any audit yet; MECHANICS_AUDIT A1 (the group-scan hot path) was fixed in
August and nobody has profiled a full match since Build 7, the W46 contact
physics, the AI ragdoll tackles and the 2026-11-17 idle-life layer.

### The task board is behind the code

The W47 Context lists 6AD (jump attribute), 6AE (mark-contest probability)
and 6AF (timing assist) as "not evidenced". All three are built
(`CharacterProfile` jump, `scripts/mechanics/mark_contest.gd`,
`Tuning` "Mark-timing assist" + HUD STYLE > MARKING). 6AC (side select) too.
They need a playtest, not building.

### Nothing on the checklist has been ticked

`docs/PLAYTEST_CHECKLIST.md` has 114 open items and none ticked. Day 5's
match is the playtest; the agents below must not pile more unplayed feel
changes on top than they have to, and each must add its one-line checks.

### Switching

`FullGame._switch_human_player` jumps to the HOME player nearest the ball
(`ControlMode.next_in_roster`); if you're already him it does nothing, so
there's no way to cycle to the second-nearest. There's no directional
(right-stick) switch and no on-screen sign of who a switch will pick. LB tap
switches on defence (6AB). Automatic switching: onto the carrier whenever
HOME gathers (`_on_home_gained_possession`), and after the human's own kick
to whoever is nearest the drop (`_on_home_kick_disposed`, not on shots).
**Nothing switches when the opposition kicks**, so to contest a mark from
an AI kick you have to switch by hand in time.

### The marking cue

`MarkPrompt` only shows once `PlayerController.live_mark_prompt` returns a
tier, and that needs the ball within reach or `MARK_CONTEST_RANGE` of the
player now. The ring's countdown already maps `RING_LEAD_TIME` 1.8 s, but
the badge appears late, often when there's under a second left. The
landing shadow (`LandingShadow`, `Ball.predicted_landing_position`) already
knows where the kick comes down from the boot.

### Cameras

`scripts/camera/broadcast_camera.gd`: CHASE (third person on a spring arm)
and FULL_SIDE (elevated outside the boundary, panning). Both update in
`_process` from targets that move on the physics tick, and the project
doesn't use physics interpolation, so at ~32 fps with 60 Hz physics a
frame sees 0, 1 or 2 physics steps of movement: judder on top of the low
frame rate.

### Open from the audits (not yet built)

From ANIMATION_RAGDOLL_AUDIT "What's left" and "Still open":
impact overshoot at ground contact (solver steps or 120 Hz physics, a cost
question); limb velocity at a full ragdoll's hand-off; a downed player keeps
a standing capsule (gameplay call); the speed curve's corner at top speed
(feel call); per-leg foot IK; turning on the spot slides the feet (6AG-b);
re-bake the off-balance mark landing; root motion for contest outcomes; a
whipping body drags its trunk (follow should carry the yaw rate); stand
ragdoll and bump stumble hand back upright; stamina into TackleBalance
(gameplay call). From MECHANICS_AUDIT: A3 (split `player_controller.gd`,
now far over 2660 lines) still left for its own session. Board items: 6AA LT
defensive stance (new mechanic), 6S on-screen maths (idea, needs a
reference image), 6E stadium venues, 6Q hands on a wall, 6AG-a elbow tear
(3 of 256 falls), 6O smother-dive snap re-check.

## Rules for every workstream

- Branch from `update` in its own worktree; commit there; don't push.
- Tackling and marking outcomes don't change unless the workstream says so:
  `scenes/dev/tackle_sweep.tscn` and `contact_sweep.tscn` must print the same
  table before and after (they're deterministic; LESSONS.md has the
  incantations). Contests stay physics and timing, never a roll
  (RULES_REFERENCE.md §3).
- New numbers go in `scripts/tuning.gd` marked "unplaytested feel guess".
- One line per user-visible change in `docs/PLAYTEST_CHECKLIST.md`.
- Measure before and after; say what still needs the user's eyes.

## Workstreams, in order

### W1. Performance: a full match at 60 fps (do first)

Goal: windowed 1080p Full Game p95 frame under 16.7 ms on the dev machine,
same match outcomes.

1. Profile before touching anything: Godot's profiler (or a scratch scene
   timing each system with `Time.get_ticks_usec`) over a full quarter. Split
   the ~18 ms of process and ~14 ms of physics by system: AI brains,
   PlayerController physics, PlayerAnimation post-mix passes (lean, contact,
   fend, idle life, foot clamp, ball hold), AnimationTree, partial/motor
   ragdolls, HUD, the highlight recorder (it packs every body every frame),
   OvalEnvironment, shadows.
2. Fix the biggest first. Likely suspects: per-frame work that can run at a
   lower rate (AI decisions, nearest-opponent scans), AnimationTrees and
   post-mix passes on far-away players (LOD by distance from the camera),
   the recorder's per-frame packing, shadow casters, draw calls (849).
3. Turn on physics interpolation (`physics/common/physics_interpolation`)
   if it holds up with the ragdolls and the camera; otherwise interpolate
   the camera's target only. Smooth motion between physics ticks matters as
   much as the frame rate.
4. Report a before/after table (p50/p95/p99/max, process, physics) and the
   sweep tables unchanged.

### W2. Cameras: fluent chase and full side

Starts after W1 lands (same frame-timing territory). Goal: no judder, no
snaps, the play always in frame.

- Both modes follow interpolated positions (W1's interpolation, or their
  own smoothing on a fixed timestep).
- FULL_SIDE as a broadcast ("FIFA tele") camera: pans and zooms with the
  play (ball plus the nearest players, with lead in the ball's direction),
  a dead zone so it doesn't wobble with every step, no swing when control
  switches, height and FOV options in Settings.
- CHASE: switch pans that don't whip, the ball-pull on long kicks kept.
- Check every mode against goal kicks, the goal set shot, rucks and the
  dialogue framing (all have their own paths in broadcast_camera.gd).

### W3. Control: switching and the marking cue (parallel with W1)

Goal: you can always get onto the player you want, and the game puts you
there when it obviously should.

Switching (`full_game.gd`, `control_mode.gd`, `human_brain.gd`, settings):
- A second switch press within ~0.6 s cycles to the next nearest (then the
  next), instead of doing nothing.
- Right-stick flick switches to the teammate in that direction (FIFA's
  directional switch); keyboard equivalent if a key is free.
- A small marker under the player a switch would pick next.
- Auto-switch on the opposition's kick: when an AI opponent kicks and the
  human isn't the carrier, hand control to the HOME player best placed for
  the predicted drop (the same predicted landing the shadow shows), after a
  short delay, unless the human is already contesting it. A setting:
  AUTO SWITCH off / assisted (default) / full.
- Never switch mid-action (a mark attempt, tackle, kick) or mid-ragdoll.

Marking cue (`mark_prompt.gd`, `player_controller.gd` read-only for the
tier logic):
- An "incoming" cue as soon as a kick's predicted landing is within a
  radius of the controlled player: the badge dimmed and the ring already
  counting down (it has RING_LEAD_TIME 1.8 s of sweep), becoming the live
  badge when `live_mark_prompt` does. Catch resolution doesn't change.
- With the auto-switch above, the player who'll contest is under your
  control before the cue appears.

Check with the existing mark harnesses (`scenes/dev/mark_cue_*`,
`mark_contest_check`) that catches are unchanged; the cue is display only.

### W4. Movement feel (after W1; small, each a feel call)

- Speed curve: taper acceleration over the last ~1.2 m/s (audit item 5).
- Turning on the spot (6AG-b): a procedural step or turn clip so feet don't
  slide at 720°/s.
- Per-leg foot IK for planted feet (audit item 6), if W1 left the budget.
- Each behind a Tuning switch so the user can compare in the playtest.

### Later (after Day 5): the character model and the physics

The user's next block. Not for these sessions:
motor control and ragdoll (limb velocity at hand-off, impact overshoot /
120 Hz physics once W1 has headroom, trunk follow carrying the yaw rate,
upright hand-backs, 6AG-a elbow tear), the tackling and marking formulas
driving the physics and game state more directly (5C marking contests on
the active ragdoll, stamina into TackleBalance), Build 7 / 4D model work,
6AA LT stance, 6S maths display, A3 controller split, root motion.

## Suggested sessions

| Session | Workstream | Can run alongside |
|---|---|---|
| Performance | W1 | Control |
| Control and marking cue | W3 | Performance |
| Cameras | W2 | after Performance merges |
| Movement feel | W4 | after Performance merges |

Merge order into `update`: W1, W3, then W2 and W4. Then the Day 5 match is
the playtest of all of it.

## Status 2026-11-18 (evening)

- **W3 done and merged** (`f9e9dd2`, `1aa678d`): switch cycling, right-stick
  flick switch, the next-player marker, auto-switch on the opposition's kick
  (AUTO SWITCH setting), the incoming mark cue. User played it: "switching
  works", fps felt higher.
- **W1 not done.** The session profiled and stopped; nothing was committed
  and its probe code was discarded. Its findings, for the next W1 session:
  - With vsync off: p50 13.0 ms, p95 27.2 ms, max 64.5 ms (15 s run). The
    31.4 ms median above is probably vsync rounding frames just over 16.7 ms
    up to 33 ms; the p95 and spikes are the real problem.
  - ~9 ms of process time sits outside the game scripts: most likely the 36
    AnimationTrees and skeleton updates. Biggest target (distance LOD on far
    players).
  - Player physics scripts 6.7 ms per tick; Jolt ~3 ms per tick.
  - Idle life 1.3 ms, mostly its nearest-opponent check every frame (cache
    or share one scan per frame).
  - `contact_sweep.tscn` crashes on load: loading the players' animations
    overflows Godot's message queue (it only ran with an `override.cfg`
    raising the limit). The same flood probably slows Full Game loading.
  - Still to try: time the AnimationTrees, distance LOD, small `drive()` and
    idle-life fixes, physics interpolation.

## Playtest 2026-11-18: next changes (user's notes, in their order)

Not started. The user wrote these after playing the W3 build; each wants
its own check line in PLAYTEST_CHECKLIST.md when built.

1. **Switching edge cases.** Can't switch while the opposition has a free
   kick. Sometimes a teammate takes an intercept mark while the human wasn't
   on him and control doesn't move to him (most of the time it does; a
   manual switch works). Find which paths skip `_assign_human_to`.
2. **Ball drop (landing) icon in Settings**, like the other HUD options, with
   simple customisation (on/off, size, colour/style).
3. **Mark cue earlier and bigger in Full Game.** Still appears too late to
   react; make it larger on the Full Game screen so the timing reads, and
   bring the incoming state in earlier (W3's radius / lead).
4. **Contest Slide tackler** (the one in the animation viewer, "A: slings";
   the in-game slide tackle looks fine): the tackler's feet stay flat and he
   slides forward. Make it a quick grab-and-throw, with the tackler on
   partial ragdoll physics that keeps his feet and takes a small step when
   his body is moved (adaptive stepping). The tackled player's fall is good:
   leave it.
5. **Smother vs steal on X.** Close to the kicker as he kicks: the smother
   dive. Otherwise X currently plays an odd arm-jelly animation; make it a
   steal/intercept: arms out (T-pose-ish) to block a handball, and against a
   carrier a steal attempt decided by the attributes / contest formula
   (physics and timing per RULES_REFERENCE §3, the same style as the tackle
   formula, not a dice roll unless the user decides otherwise).
6. **Animation viewer, MARK DELIVERY badges**: every example shows (A). RUN
   should show (X), LEAP (Y); rename LEAP to AGGRESSIVE.
7. **Animation viewer, CONTESTS > MARK DELIVERY > CONTESTED**: a control to
   raise or lower the number of opponents; opponents face the same way as
   the player and stand side by side, for simulating packs of bodies jumping
   with the marking formula on the motor control and ragdoll.
8. **Tackles almost always succeed.** When the tackle formula says the
   carrier wins, he should break away; and the losing side's motor control
   should show it (a broken tackle is a push and a stumble, like a
   successful fend sends the defender back stumbling).
9. **Safe (A) marks not paid**: some look caught but no mark is paid and
   the player is tackled. Reproduce and find why (`_complete_mark` /
   `is_mark_eligible` / the 15 m rule).
10. **LT defensive stance (6AA, shepherding)**: holding LT, in general play
    or with the ball, drops into a low crouch, arms out wide, and keeps
    facing the way he faces while moving in any direction (no body flip:
    the Agility turn-out locks, he side-steps / backs off).

### Where the 2026-11-18 list stands (2026-11-18, later)

Done (624f370, bc4f0b0, 88e2fbd): 1 switching at stoppages + intercept-mark
control; 2 ball drop icon, colour, size; 3 mark cue bigger and earlier; 6
viewer badges A / X / Y and AGGRESSIVE; 7 viewer opponents 1-5 in a line;
8 broken tackles more often + bigger recoil (thresholds only); 9 PLAY ON
call with the reason; 5 (part) X smothers next to a kicker. Also: the goal
prompt is the minimal "[Y] Goals" chip again (the 2026-11-14 stash recovery
had brought in a brown box).

Left:
- 4 Contest Slide tackler: quick grab-and-throw, partial ragdoll that keeps
  his feet and steps when moved (the viewer's CONTESTS > Slide case).
- 5 (rest) X against a handball in flight: an intercept/block pose (arms
  out) instead of the running-mark clip; X against a carrier as a steal.
  **Needs the user's call:** X is the Lunge tackle today; a steal would
  replace it (or sit on another button, or be what a Lunge that breaks
  does).
- 10 LT shepherd stance: hold LT (not carrying, not in kick stance) to
  crouch, arms out, and keep facing while moving any way (no turn-out).
