class_name Tuning
extends RefCounted

## Every tunable number in one place.
##
## This is the direct descendant of Prototype 1's `settings.py` — the one
## file you open to change how the game feels. Prototype 1 proved that
## pattern works; the only difference here is units.
##
## UNITS: everything is SI. 1 Godot unit = 1 metre, 1 kg, 1 second.
## Prototype 1 ran on abstract "logical units" on a 166x88 grid; where a
## number here descends from one of its constants, the P1 name is cited.
## See docs/RULES_REFERENCE.md for the full translation table.
##
## AXES: the ground plane is XZ. +X is the direction the home team attacks
## (goal at +X), Z is wing-to-wing, +Y is up. Godot's -Z-is-forward
## convention applies to node local space as usual.


# ── Shared vocabulary ────────────────────────────────────────────────
# These live here, alongside the tunables, for the same reason Prototype
# 1's settings.py held colours and geometry and rule constants together:
# it is the one module everything else is allowed to depend on, so it is
# the only place a shared type can sit without creating a cycle.

enum Team { HOME, AWAY, NONE }

## Append new actions on the end (keeps int values stable for save data /
## AnimationTree state names). ACTION_DURATION/ACTION_CONTACT below are
## Dictionaries keyed by this enum, so reordering no longer silently
## shifts every timing — but the enum ints are still worth keeping stable.
##
## MARK_SAFE_MISS/MARK_RUNNING_MISS: the cosmetic reaction played when a
## timing-graded attempt on that tier fails outside the window (see
## PlayerController._attempt_running_mark and _update_marking's grounded
## branch) — a distinct clip from the catch one, not a new gameplay
## resolution path. MARK_AGGRESSIVE has no _MISS twin: its catch already
## resolves mid-clip (see ACTION_CONTACT's own comment below), and there is
## no cheap way to fork an already-playing AnimationNodeStateMachine state
## without a visible pop, so its miss stays feedback-only (rumble/SFX/ring),
## same clip either way. Later, animation-layer only: on a rig with
## MarkVariants (6thbuild), PlayerAnimation cross-fades a missed leap into
## mark_aggressive_miss at the contact instant — a state that plays from the
## leap's own contact pose on (custom timeline start offset), so there's no
## pop. Still no Action, no duration and no gameplay of its own.
##
## TACKLED: the cosmetic fall/recover reaction for anyone knocked flat by a
## contest (PlayerController._knockdown) — a Lunge tackle connecting
## (_get_tackled with is_slide=false), or a whiffed bump dash landing on
## the bumper themselves (_resolve_bump_miss). Falls forward, in the
## direction of travel — see _fall_toward(). A Slide connecting no longer
## uses this (see TACKLE_HELD below) and a clean bump connect no longer
## uses this either (see KNOCKED_BACK below) — both used to, until real
## playtesting asked for a different read on each. Like the mark misses
## above, the outcome (ball spilled, or not) is already resolved before
## this ever starts; the clip is purely the visual consequence.
##
## TACKLE_GRAB: the TACKLER's own beat on a Slide connect, synced with the
## target's TACKLE_HELD — playtest feedback wanted Slide to read as a wrap-
## up hold (both stay standing) rather than a knockdown, so this clip
## itself was softened to match (see HumanoidAnimations._build_tackle_
## grab's own doc comment).
##
## TACKLE_HELD: the target's own reaction to a Slide connect — standing,
## wrapped up, ball stripped, not knocked down. Distinct from TACKLED
## (which Lunge's target still uses): playtest feedback specifically wanted
## the two tackle types to read differently — Slide holds them up, Lunge
## can take both players to the ground.
##
## TACKLE_TAKEDOWN: the TACKLER's own beat on a Lunge connect, synced with
## the target's TACKLED fall — driving them down and ending low/kneeling
## rather than standing untouched, since playtest feedback wanted "the
## lunge tackle can take both players to the ground." The tackler
## themselves doesn't get a hard stun or go fully prone (see
## PlayerController._try_lunge_tackle's own doc comment) — this is a
## cosmetic crouch, not a second knockdown.
##
## SMOTHERED: the reaction clip for a blocked kick (PlayerController.
## _get_smothered) — a stumble/recoil, not a knockdown, so it does not
## route through _knockdown() and gets its own (shorter, unstunned) slot.
##
## SMOTHER_DIVE: the beat on the SMOTHERER, not the smothered player — a
## committed dive at the kicker's feet/boot (PlayerController._update_
## smother), reworked after playtest feedback that the first version never
## actually went to ground ("doesn't make the player dive at the ground
## towards oppositions player feet"). Plays whether or not the dive
## actually connects (see Tuning's own Smother section) — the dive itself
## is the animation, the block is the separate game effect.
##
## KNOCKED_BACK: a clean Bump connect's own fall — playtest feedback: the
## target was spinning 180° to face away before falling (TACKLED's own
## "face the direction of the fall" convention, wrong for this case) when
## a clean hit from the front should send them straight down onto their
## back, still facing roughly where they were already facing. Mirrors
## TACKLED's own pose data (see HumanoidAnimations._build_knocked_back's
## doc comment) but skips _fall_toward()'s facing snap entirely — see
## PlayerController._knockdown()'s own `snap_facing` parameter.
enum Action { NONE, KICK, HANDBALL, BOUNCE, MARK_SAFE, MARK_RUNNING, MARK_AGGRESSIVE, HIT_OUT,
	MARK_SAFE_MISS, MARK_RUNNING_MISS, TACKLED, TACKLE_GRAB, SMOTHERED, SMOTHER_DIVE,
	TACKLE_HELD, TACKLE_TAKEDOWN, KNOCKED_BACK }


# ── Ground geometry (metres) ─────────────────────────────────────────
# A real AFL oval varies ground to ground; 165 x 135 is a mid-size
# ground (the MCG is ~160 x 141). Prototype 1's 166 x 88 grid was a
# 16:9-framing compromise for its fixed diorama camera, not a real
# aspect ratio — a 3D camera has no such constraint, so the oval is
# correctly proportioned here.
const FIELD_LENGTH := 165.0            # goal to goal, along X
const FIELD_WIDTH := 135.0             # wing to wing, along Z
const FIELD_HALF_LENGTH := FIELD_LENGTH * 0.5
const FIELD_HALF_WIDTH := FIELD_WIDTH * 0.5

const GOAL_POST_SEPARATION := 6.4      # AFL: 6.4m between the goal posts
const BEHIND_POST_OFFSET := 6.4        # and 6.4m again out to each behind post
const GOAL_POST_HEIGHT := 10.0         # AFL minimum is 6m; AFL-level grounds use ~10m
const BEHIND_POST_HEIGHT := 6.0        # AFL minimum is 3m
const GOAL_SQUARE_DEPTH := 9.0
const CENTRE_SQUARE_SIZE := 50.0
const CENTRE_CIRCLE_OUTER := 5.0       # 10m diameter
const CENTRE_CIRCLE_INNER := 1.5       # 3m diameter
# The 50m arc. P1's SCORING_ARC_RADIUS was 40 in its compressed units and
# its own comment calls it "the 50m arc" — 50 is the real rule.
const SCORING_ARC_RADIUS := 50.0
const LINE_WIDTH := 0.1


# ── Player locomotion ────────────────────────────────────────────────
# Real AFL running speeds. An elite midfielder tops out around 8.5-9 m/s
# over a short burst and cruises at 4-5. Prototype 1's PLAYER_SPEED (28
# logical units/s on a 166-unit field) was an arcade abstraction; a 3D
# game in real metres has to use real numbers or nothing else reads right.
const WALK_SPEED := 1.8
const JOG_SPEED := 4.8
const SPRINT_SPEED := 8.4

# Gait thresholds the three named speeds sit at, so a controller's analog
# stick magnitude (and the keyboard's three-tier equivalent) maps onto
# them. See Tuning.speed_for_gait and InputManager.get_gait.
const GAIT_WALK := 0.35
const GAIT_JOG := 0.70

# Acceleration is what makes a body read as having mass. A human sustains
# roughly 3-4 m/s^2 to top speed; braking is always quicker than getting
# going. These are deliberately a shade brisker than reality so a
# controller still feels responsive.
#
# Fundamentals-pass retune: ACCELERATION nudged up from 9.0 — the model
# itself (real momentum, not instant-start/instant-stop) is staying, per
# design doc §5 and every contest in this file leaning on it, but the brief
# was "more responsive, forgiving" within that model, not a redesign. A
# slightly punchier get-going without touching BRAKING (already the
# quicker of the two, correctly) is the smallest lever toward that.
const ACCELERATION := 10.5             # m/s^2 speeding up
const BRAKING := 14.0                  # m/s^2 slowing down
const AIR_ACCELERATION := 2.0          # m/s^2 while airborne (very little authority)

# Turn rate falls off with speed — this is the single biggest contributor
# to "weight". At a standstill you pivot on the spot; at a full sprint you
# describe an arc. Turn radius = speed / turn_rate, so SPRINT here gives
# 8.4 / 3.32 rad/s ~= 2.5m (was ~3.0m at the old 160 deg/s) — a touch
# tighter/quicker to recover from without losing the commitment a sprint
# is supposed to carry.
const TURN_RATE_STANDING := 900.0      # deg/s at zero speed
const TURN_RATE_SPRINT := 190.0        # deg/s at SPRINT_SPEED

# How much a change of direction costs you in speed. Running back against
# your own momentum drives target speed toward REVERSE_SPEED_SCALE, so you
# brake, and braking raises your turn rate, so you plant and swing round.
# Two coupled rules, one emergent plant-and-pivot — no special case.
#
# Fundamentals-pass retune: was 0.0 — a dead-stop on any reversal, which is
# the single biggest thing that read as "unresponsive" rather than "has
# weight". Raised off zero so a hard reversal still costs real speed (this
# is still meant to hurt enough that backpedal/plant-and-pivot stay the
# genuinely better techniques for reading the play, not a free direction
# change) without fully arresting momentum first.
const REVERSE_SPEED_SCALE := 0.18      # target speed multiplier at 180 deg off heading

# Below this speed there is no momentum worth fighting, so the heading
# snaps straight to intent and you simply turn on the spot.
const PIVOT_SPEED_THRESHOLD := 0.4     # m/s

# Below this speed, horizontal velocity is treated as exactly zero rather
# than real motion — see the comment at the top of _update_locomotion().
# Sub-cm/s residue is collision-response noise, not intent; letting it
# through made a standing-still player's animation blend visibly twitch.
const LOCOMOTION_VELOCITY_DEADZONE := 0.03   # m/s

# Backpedal (design brief: "backpedal-to-turn transitions for defenders
# reading the play"). Distinct from the plant-and-pivot above, which is
# what a full-speed sprint reversal already gets from the
# REVERSE_SPEED_SCALE/turn-rate coupling — this is the other technique:
# reading the play from a standstill or a jog, eyes (facing) locked on
# whatever they were already on while the feet answer the stick directly
# at a capped shuffle speed. See PlayerController._update_locomotion/
# _update_facing.
#
# Gated on wish-direction-vs-*facing* (not heading) so it only engages
# when the input is genuinely behind where the body is looking, and only
# from a modest starting speed — a player already sprinting who reverses
# gets the existing plant-and-pivot instead, a faster, more committed
# move for a different moment (chasing/leading) than this one (holding a
# defensive cushion).
const BACKPEDAL_ENTER_DOT := -0.25     # facing . wish_dir at/below this enters backpedal
const BACKPEDAL_EXIT_DOT := 0.15       # facing . wish_dir at/above this exits + arms a turn burst
const BACKPEDAL_ENTRY_SPEED_MARGIN := 0.5   # m/s above JOG_SPEED still allowed to enter
const BACKPEDAL_SPEED := 3.0           # m/s, capped backward shuffle
const BACKPEDAL_ACCELERATION := 7.0    # m/s^2 — deliberate, a shade under ACCELERATION
# How long a single backpedal can run before the body gives up on holding
# its facing, turns, and just runs that way. Not a rule number — this is
# the fix for two playtest reports. First ("sometimes I look the other way
# and it gets stuck in the backpedal and I have to do a small turn forwards
# and around"): facing is frozen while backpedalling, so holding the stick
# behind you can never turn the body, and BACKPEDAL_EXIT_DOT could only be
# reached by swinging the stick back around to where the body already
# looked. Second ("still get stuck backpedalling 2-3 too many steps before
# it turns the player around"): the original 1s was too long a grace — cut
# to 0.55s (~1.6m at BACKPEDAL_SPEED). This is the "-to-turn" half of the
# design brief's own "backpedal-to-turn transitions" — a shuffle is a
# transition, not a mode you can be parked in. This constant is the
# baseline (agility 1.0); Tuning.backpedal_turnout_duration() scales it per
# player from PlayerController.agility_scale — a nimbler player turns out
# sooner, down to BACKPEDAL_TURNOUT_MIN_DURATION.
const BACKPEDAL_MAX_DURATION := 0.55   # s of continuous shuffle before turning out of it (agility 1.0)
const BACKPEDAL_TURNOUT_MIN_DURATION := 0.28   # s floor so max agility still shuffles, not snaps
# Modest turn-rate swing from agility, applied to both the plant-and-pivot
# sweep and the rig's facing rotation. Bracketed so DEFAULT agility (1.0)
# lands exactly on the tuned turn rates — only off-default stats move it.
const AGILITY_TURN_RATE_MIN_MULT := 0.85
const AGILITY_TURN_RATE_MAX_MULT := 1.25

# The moment a backpedal resolves into a real direction (design brief:
# "acceleration bursts when starting a lead or chase") — heading is
# already aligned (backpedal tracks wish_dir directly, no turn-rate sweep
# to catch up on), so the burst is purely an accel spike driving off the
# plant, not a turn-rate change.
const TURN_BURST_DURATION := 0.22      # s
const TURN_BURST_ACCEL_MULT := 1.8

# The rig's facing turns faster than the velocity heading does, so the
# body leads the change of direction and the velocity lags behind it.
# That lag is what feeds the blend space's strafe axis (see
# player_animation.gd) — a hard turn genuinely blends lateral animation
# instead of the model just snapping round.
const FACING_TURN_RATE := 720.0        # deg/s

const GRAVITY := 9.80665               # m/s^2

## How far below the ground the ball has to fall before a mode's own
## out-of-bounds safety net gives up on it and resets it, rather than
## leaving it to fall forever. Was three independent copies of the same
## number (scripts/main.gd, kick_to_kick.gd, full_game.gd) — single-sourced
## here since none of them mean anything different by it.
const BALL_LOST_BELOW := -5.0          # m

# Force the player imparts to loose rigid bodies it walks into, as a
# multiple of the ball's mass. Running through a ball should shift it.
const PLAYER_PUSH_FORCE := 4.5


# ── Ball (RigidBody3D) ───────────────────────────────────────────────
# A match Sherrin: 450-500 g, 720-730mm longitudinal circumference,
# 545-555mm transverse. That works out to a prolate spheroid with a
# 0.14m semi-major and 0.0875m semi-minor axis.
const BALL_MASS := 0.475               # kg
const BALL_SEMI_MAJOR := 0.14          # m, along the ball's local Z
const BALL_SEMI_MINOR := 0.0875        # m
const BALL_FRICTION := 0.65            # on grass
# Restitution off turf. P1 faked this with a cosmetic two-hop height
# offset that never touched the ball's real position; here it is real.
# Rulebook §8: a ball landing from a kick should sit up livelier than it
# did — raised from 0.45. Not a rule number, a feel target, and it is the
# one value both halves of §8 run through: the manual bounce below rebounds
# off this same restitution, so the two were raised together.
const BALL_BOUNCE := 0.55
const BALL_ANGULAR_DAMP := 0.35        # spin bleeds off
const BALL_LINEAR_DAMP := 0.0          # air resistance is modelled properly below

# Quadratic air drag: F = -0.5 * rho * Cd * A * |v| * v, collapsed into
# one coefficient. rho=1.225, Cd~=0.2 for a spheroid, A = pi * 0.0875^2.
# At 25 m/s that is ~1.8 N on a 0.475 kg ball — about 3.9 m/s^2, which is
# exactly the order of magnitude that gives a kick its real arc shape
# (steeper on the way down than on the way up).
const BALL_DRAG_COEFF := 0.00294

# Magnus force from spin, F = MAGNUS * (omega x v). Small, but it is what
# makes a torpedo hold a line and a badly struck ball fade off it.
const BALL_MAGNUS_COEFF := 0.00022

const BALL_SLEEP_SPEED := 0.12         # m/s below which a resting ball is allowed to sleep


# ── Disposal ─────────────────────────────────────────────────────────
# Launch speeds, not distances — the ball's flight is simulated, so range
# is an outcome rather than an input. Numerically simulated against the
# actual drag+gravity model (matching KickTrajectory's own stepping),
# not hand-estimated: 24 m/s at 40 degrees carries ~46m in the air
# standing, ~55m kicking on the run, which lands the *total* travelled
# distance (including bounce/roll-out) around 60-70m once it's down —
# a real long AFL punt, not a 100m bomb. The first tuned value (30 m/s)
# measured out to ~65m flight / ~100m+ total once roll-out was included,
# confirmed too far by playtesting.
# (P1: KICK_MAX_RANGE = 88 logical units, BALL_FLIGHT_SPEED = 95 — both
# scripted-flight parameters with no physical meaning here.)
const KICK_CHARGE_TIME := 0.85         # seconds held to reach full power
const KICK_MIN_SPEED := 13.0           # m/s, a tapped stab pass
const KICK_MAX_SPEED := 24.0           # m/s, a full-blooded drop punt
const KICK_MIN_ANGLE := 22.0           # deg elevation at zero charge (flat, fast)
const KICK_MAX_ANGLE := 40.0           # deg elevation at full charge (long, high)
const KICK_BACKSPIN := 26.0            # rad/s end-over-end, the drop punt signature

const HANDBALL_SPEED := 15.0           # m/s (P1: HANDBALL_RANGE = 34 units)
const HANDBALL_ANGLE := 9.0            # deg elevation — flat and fast
const HANDBALL_SPIN := 4.0             # rad/s

# Rulebook §8: the manual bounce should come back up higher than it did.
# Cranking this 8 -> 17 across playtests never fixed the ball coming up
# into the body, because the spheroid hull striking the turf nose-first
# scrubbed the rebound to near-dead at random (headless _scratch_bounce:
# apex ~0.5-0.9 m, sometimes basically zero, regardless of speed). The
# rebound is now scripted for a bounce flight only (BOUNCE_REBOUND_* below,
# Ball._physics_process), so this just carries the ball down and forward;
# the height comes from that.
const BOUNCE_SPEED := 11.0             # m/s driving the ball into the turf
# Down, but far enough ahead that a running player runs onto the rebound.
# Eased -52 -> -40: a glancing strike keeps more speed through the contact
# so the ball skips forward rather than stalling; the scripted rebound
# supplies the height regardless of what the hull does.
const BOUNCE_ANGLE := -40.0            # deg

# The manual bounce's rebound off the turf is scripted (Ball._physics_
# process), not left to the erratic hull: the first time a bounce flight
# comes back down through BOUNCE_REBOUND_HEIGHT still falling, its vertical
# speed is set to BOUNCE_REBOUND_UP_SPEED and its horizontal is scaled by
# BOUNCE_REBOUND_KEEP (the turf takes a cut of the forward speed, the way
# a real bounce does -- without it the ball sailed ~10 m downfield and
# outran the bouncer). ~1.2 m apex before drag: hands height on the run,
# not the shins, and slow enough forward that a sprinting carrier runs
# onto it. The trigger sits just above the ~0.22 m airborne threshold
# (BALL_SEMI_MINOR * 2.5) so a ball that has effectively landed can't set
# off a phantom hop. Only a BOUNCE disposal arms it (Ball.launch's
# is_bounce arg); a kick / handball / hit-out bounces off the hull as
# before.
const BOUNCE_REBOUND_HEIGHT := 0.30    # m, on the way down
const BOUNCE_REBOUND_UP_SPEED := 4.2   # m/s clean vertical rebound
const BOUNCE_REBOUND_KEEP := 0.55      # fraction of horizontal speed kept
# Hard ceiling on the rebound's forward speed after KEEP, applied on top:
# without it a sprint's momentum transfer put the ball far enough ahead to
# overrun the bouncer. Trimmed 4.5 -> 3.8 across two rounds of playtest
# feedback ("a little too far in front when sprinting", then "decrease it a
# little more") — lands the ball a short, consistent step in front at any
# run speed.
const BOUNCE_REBOUND_MAX_AHEAD := 3.8  # m/s

# A kick on the run goes further than the same kick standing still.
# Fraction of the player's horizontal velocity added to the ball.
const DISPOSAL_MOMENTUM_TRANSFER := 0.55

# You plant to kick. Fraction of target speed available mid-action.
const ACTION_SPEED_SCALE := 0.4

# LT kick stance (design brief's CONTROLS section): an ADS analogue, not a
# full plant — you can still move and reposition while aiming, just not at
# full pace. Deliberately less restrictive than ACTION_SPEED_SCALE, which
# is the actual kicking-motion lock that follows it.
const KICK_STANCE_SPEED_SCALE := 0.55

# deg/s the right stick/mouse swings the kick aim while in stance — a
# separate dial from CAM_YAW_SPEED, deliberately slower than camera-look
# (180) for precision control once actually aiming. Dropped from the
# first pass's 180 after playtesting read it as too twitchy to line up a
# kick with — P1's equivalent (a velocity-driven aim cursor, not a raw
# yaw rate) had the same "controlled, not snappy" quality; this is the
# simplest lever toward that without porting its cursor/projection system
# wholesale.
const KICK_AIM_YAW_SPEED := 100.0

# RT tapped without ever holding LT first — a hip-fired kick: whatever
# the body's facing, fixed middling power (there was no stance to charge
# through), extra random spread on top of KICK_ACCURACY_MAX_SPREAD_DEG's
# skill-based scatter. P1 itself has no hip-fire (every kick there goes
# through its aim-cursor pipeline) — this pairing is this project's own
# addition, modelled on ADS-vs-hip-fire in a shooter per the design
# brief's own CONTROLS section framing.
const KICK_HIP_FIRE_CHARGE := 0.55
const KICK_HIP_FIRE_SPREAD_DEG := 20.0

# Soft pull toward a nearby teammate while aiming — not a lock-on, a
# per-frame blend, same shape as P1's apply_aim_assist/AIM_ASSIST_STRENGTH
# (ported directly: the formula is a dimensionless k=min(1,STRENGTH*dt)
# blend fraction, so the same constant works whether what's being blended
# is P1's 2D screen cursor or this project's 1D aim yaw). CONE/RANGE have
# no P1 equivalent to port — P1's version worked in screen-space pixels
# around a 2D cursor, which doesn't translate to a world-space yaw system,
# so these are this project's own first pass at the same idea.
const KICK_AIM_ASSIST_STRENGTH := 6.0
const KICK_AIM_ASSIST_CONE_DEG := 18.0
const KICK_AIM_ASSIST_RANGE := 60.0

# Keyboard/mouse has no stick position for kick_charge_override() to read
# (that's gamepad-only), so power comes from PlayerController._update_kick_
# aim() instead: arrow up/down reads as a held rate over KICK_CHARGE_TIME,
# same pacing the old ramp and AI's ramp both already use (deliberately not
# a second, independent knob); mouse motion is a raw per-frame delta, this
# many power-fraction-per-pixel, same idea as CAM_MOUSE_SENSITIVITY but in
# 0..1 units instead of degrees since there's no angle involved here.
const KICK_MOUSE_REACH_SENSITIVITY := 0.0035

# Action timing, keyed by Action. CONTACT is when the ball actually
# leaves — partway through the swing, not at either end of it. Read them
# through action_duration() / action_contact_time(), never by raw key.
#
# These are constants only because the placeholder animations are
# generated from them (see humanoid_animations.gd). When real mocap/Mixamo
# clips arrive, contact becomes a call track on the animation and the
# CONTACT row is deleted; nothing else changes.
## HIT_OUT's timing is a straight copy of MARK_AGGRESSIVE's, not a new
## number — it is the identical jump (see PlayerController._begin_hit_out),
## just resolved as a palm instead of a catch, so it should peak and land
## on exactly the same clock.
##
## MARK_SAFE_MISS/MARK_RUNNING_MISS (indices 8/9): short on purpose — a
## whiffed reach reads as a quick stumble-and-reset, not a settle-into-
## carry, so both are noticeably shorter than the catch clips they sit
## beside (MARK_SAFE/MARK_RUNNING at indices 4/5).
##
## TACKLED (index 10): matches TACKLE_STUN_DURATION exactly, on purpose —
## see that constant's own comment. Contact (0.30) is where the body
## actually hits the ground mid-clip, not a resolution instant (nothing
## fires there — see _update_action's cosmetic-only branch); the clip
## still needs *a* contact time for Tuning.action_contact_time's shared
## bookkeeping the same way MARK_SAFE_MISS/MARK_RUNNING_MISS do.
##
## TACKLE_GRAB (index 11): a wrap-and-hold beat, synced with TACKLE_HELD
## (index 14) — both share this same 1.0s length so tackler and target
## settle together, not one finishing well before the other. No stun of
## its own; the tackler is free to move again the moment it ends, but they
## are physically pinned to the target for its duration (see
## TACKLE_HOLD_DISTANCE and PlayerController._begin_tackle_hold).
## Lengthened from 0.55s: rulebook §6 asks for the two players to be held
## together for 1-2s, and 0.55s was short enough that the wrap read as a
## flinch. Still clearly shorter than Lunge's own 1.3s takedown, so the
## playtest decision that the two tackle types should *feel* different
## survives — it's the gap that carried that read, not the absolute value.
##
## SMOTHERED (index 12): shorter than TACKLED — a recoil, not a fall — and
## unstunned like MARK_SAFE_MISS/MARK_RUNNING_MISS, just gated off other
## actions for its own short span by the usual _action != NONE guard.
##
## SMOTHER_DIVE (index 13): matches SMOTHER_DIVE_DURATION — the clip plays
## for exactly as long as the physical dive itself overrides locomotion.
## Lengthened from an original 0.4s alongside the rework into a genuine
## ground dive (see HumanoidAnimations._build_smother_dive) — the extra
## time is what gives the dive somewhere to actually go before snapping
## back to base.
##
## TACKLE_HELD (index 14): see TACKLE_GRAB above — same 1.0s length,
## deliberately shorter than TACKLED's own 1.3s since nobody goes to
## ground here; TACKLE_HELD_STUN_DURATION matches it the same way
## TACKLE_STUN_DURATION matches TACKLED.
##
## TACKLE_TAKEDOWN (index 15): matches TACKLED's own 1.3s so the tackler's
## drive-down-and-rise finishes around the same time the target's fall-
## and-recover does — two bodies moving through one shared beat, not two
## independently-timed animations that happen to overlap.
##
## KNOCKED_BACK (index 16): matches TACKLED's own 1.3s/0.30 contact split
## exactly — see that clip's own comment; this is a sign-mirrored variant
## of the same fall, not a differently-paced one.
const ACTION_DURATION := {
	Action.NONE: 0.0,
	Action.KICK: 0.78, Action.HANDBALL: 0.45, Action.BOUNCE: 0.50,
	Action.MARK_SAFE: 0.55, Action.MARK_RUNNING: 0.40, Action.MARK_AGGRESSIVE: 0.95,
	Action.HIT_OUT: 0.95,
	Action.MARK_SAFE_MISS: 0.35, Action.MARK_RUNNING_MISS: 0.30,
	Action.TACKLED: 1.3, Action.TACKLE_GRAB: 1.0, Action.SMOTHERED: 0.45,
	Action.SMOTHER_DIVE: 0.55, Action.TACKLE_HELD: 1.0, Action.TACKLE_TAKEDOWN: 1.3,
	Action.KNOCKED_BACK: 1.3,
}
const ACTION_CONTACT := {
	Action.NONE: 0.0,
	Action.KICK: 0.42, Action.HANDBALL: 0.20, Action.BOUNCE: 0.22,
	Action.MARK_SAFE: 0.08, Action.MARK_RUNNING: 0.06, Action.MARK_AGGRESSIVE: 0.40,
	Action.HIT_OUT: 0.40,
	Action.MARK_SAFE_MISS: 0.10, Action.MARK_RUNNING_MISS: 0.10,
	Action.TACKLED: 0.30, Action.TACKLE_GRAB: 0.40, Action.SMOTHERED: 0.12,
	Action.SMOTHER_DIVE: 0.38, Action.TACKLE_HELD: 0.27, Action.TACKLE_TAKEDOWN: 0.30,
	Action.KNOCKED_BACK: 0.30,
}

# AFL rule: a player running with the ball must bounce or touch it to
# ground every 15 metres (Prototype 1's BOUNCE_INTERVAL, which matched the
# real rule). Raised to 20 here on playtest feel — the call was landing
# early. Two reasons it reads short at 15: _carry_distance accumulates
# path length, not downfield displacement, so any curve in the run counts
# against you faster than the eye expects; and a real umpire is lenient
# about the exact metre. 20 m of path ≈ 15 m of ground made good on a
# gently curving run. Deliberate deviation from the rule number, not an
# oversight.
const BOUNCE_INTERVAL := 20.0          # metres of carry between bounces

# An actual arm's reach. P1's LOOSE_BALL_GATHER_RADIUS was 4.0 units — a
# positional abstraction for "close enough", not a reach. Nudged up from
# the original 0.85 (still nowhere near P1's abstraction) after reports
# that a slightly-off pass or a bounce just outside true arm's-length was
# reading as ungatherable — a generous arm's reach, not a lunge.
const GATHER_RADIUS := 1.05            # m
# Speed at the moment of contact matters (design brief): a player running
# through a bounce or a loose ball gets a bit more reach than one standing
# over it, same idea as GROUND_PICKUP_LUNGE_PER_SPEED's deliberate reach,
# just gentler since this is the passive walk-over gather, not a button
# press. Capped well short of GROUND_PICKUP's own bonus so the two stay
# distinguishable — a deliberate reach should still out-range a passive one.
const GATHER_LUNGE_PER_SPEED := 0.04   # m of extra reach per m/s of current speed
const GATHER_LUNGE_MAX := 0.65         # m
const GATHER_MAX_BALL_SPEED := 16.0    # m/s above which the ball is going too fast to gather
const GATHER_COOLDOWN := 0.45          # s after disposal before you can regather your own kick
const RELEASE_GRACE := 0.25            # s the disposed ball ignores its own kicker


# ── Camera rig ───────────────────────────────────────────────────────
# Same focus-follow concept as Prototype 1's HeroCamera, as a real 3D
# spring arm. P1's MAIN_CAM_BACK/HEIGHT were 50/30 logical units on a
# 166-unit field — a very high, very distant diorama view. A broadcast
# third-person rig sits far closer to the player.
## Pulled in and raised from 7.5/1.35/-14 — at the old settings the rig sat
## low and far enough behind the player that Full Game's 4-a-side spread
## read as tiny, distant dots, making it hard to track teammates/passing
## lanes or judge a kick's target. Closer + higher + a touch more pitch
## gives more field awareness per frame without going all the way to
## Full-Side's broadcast distance. DISTANCE cut again 6.0 -> 4.5 on a
## "still too far" playtest note — the player now fills more of the frame;
## tune by eye alongside CAM_FOV_BASE.
const CAM_DISTANCE := 4.5              # m behind the focus point

## Settings.camera_zoom's own range — a user-adjustable multiplier on top
## of whichever mode's own baseline framing (BroadcastCamera.zoom): CHASE
## scales the spring-arm distance by 1/zoom (shorter arm = zoomed in),
## FULL_SIDE scales its FOV by 1/zoom (narrower FOV = zoomed in), so
## "zoom" means the same visual thing in both modes. Exposed first in the
## Full Game / Career pregame screens' CAMERA preview (user ask: "basic
## ways to adjust the camera settings... just start with zoom in/out").
## 7 steps either side of the 1.0 (unzoomed) default, same stepped-options
## shape every other pregame row already cycles through.
const CAM_ZOOM_MIN := 0.8
const CAM_ZOOM_MAX := 1.4
const CAM_ZOOM_STEP := 0.1
const CAM_ZOOM_DEFAULT := 1.0

const CAM_FOCUS_HEIGHT := 1.6          # m up the player's body that the rig frames
const CAM_PITCH_DEFAULT := -18.0       # deg
const CAM_PITCH_MIN := -55.0
const CAM_PITCH_MAX := 22.0
const CAM_YAW_SPEED := 180.0           # deg/s at full right-stick deflection
const CAM_PITCH_SPEED := 110.0         # deg/s
const CAM_MOUSE_SENSITIVITY := 0.14    # deg per pixel of mouse motion

# Fundamentals-pass retune: FOLLOW_RATE down from 9.0 (was ~86% converged
# in a third of a second — tight enough that a fast direction change reads
# as the rig snapping rather than following) and LOOKAHEAD pulled in from
# 0.45s/3.5m — at full sprint the old value pushed the focus point nearly
# 3.5m ahead of the player, which on a plant-and-pivot flips almost
# instantly and was very likely a real chunk of the reported jarring,
# independent of the ball entirely. Both are still real, both just settle
# slower now.
const CAM_FOLLOW_RATE := 6.0           # exponential smoothing rate for the focus point
const CAM_ROTATE_RATE := 12.0          # ditto for yaw/pitch
const CAM_LOOKAHEAD_TIME := 0.30       # s of the target's velocity to lead by
const CAM_LOOKAHEAD_MAX := 2.5         # m cap on that lead

## Widened slightly alongside the closer CAM_DISTANCE above — a tighter
## distance without a wider lens would claw back the peripheral view the
## distance cut was meant to preserve, just from a different cause.
## Then narrowed 72 -> 64 with the further DISTANCE cut to 4.5: past a
## point a wide lens fighting a close rig just distorts, so some of the
## "zoom in" ask is spent on the lens, not only the arm.
const CAM_FOV_BASE := 64.0
const CAM_FOV_SPRINT_GAIN := 10.0      # deg added at SPRINT_SPEED — speed you can feel
const CAM_FOV_RATE := 5.0
const CAM_PUNCH_KICK := -6.0           # deg of transient tighten on a kick (§6)
const CAM_PUNCH_DECAY := 3.5

# The ball pulls the focus point toward itself once it is properly in
# flight, so you watch your own kick land instead of watching your
# player's back. This is §6's "follows the ball/play focus point" in its
# simplest honest form.
# Both cut after a direct "follows the ball a bit too long, and swivels
# too much right after a kick" report. MAX was 0.55 — over half the focus
# point's position could slide toward the ball, which is what read as a
# swivel the instant a kick sent the ball moving fast (the focus point,
# not the camera's own orientation, translates toward it; the apparent
# "swing" is the whole rig's vantage point shifting while the yaw itself
# stays exactly where the player was looking). RATE was 3.0 either
# direction, so recovery back to the player after the ball lands/is held
# was exactly as slow as the initial commit toward it; raised so letting
# go is snappier without also making the initial pull twitchy (still
# smoothed, just over a shorter window).
#
# Fundamentals-pass retune: cut again, same direction as that first pass —
# MAX 0.35 -> 0.25 (the ball can pull noticeably less of the focus now),
# RATE 4.5 -> 3.0 (slower to commit toward it in the first place). Still a
# real, smoothed blend, never a snap; just looser than before, per "follows
# the player and the ball with some blend/lag" rather than tracking the
# ball tightly.
const CAM_BALL_FOCUS_MAX := 0.25       # max weight the ball takes of the focus point
const CAM_BALL_FOCUS_MIN_HEIGHT := 1.6 # m, ball must be above this to pull focus
const CAM_BALL_FOCUS_RATE := 3.0
const CAM_MAX_FRAMING_DISTANCE := 45.0 # m, beyond which the ball stops pulling harder

# Two-shot conversation framing for the training-coach dialogue (see the
# Training coaches section below) — a deliberately different composition
# from the follow-cam above (a fixed side-on view of both parties rather
# than a spring arm behind one target), so it gets its own small set of
# constants rather than overloading the follow-cam's.
const CAM_DIALOGUE_DISTANCE := 3.2     # m to the side of the coach<->player line
const CAM_DIALOGUE_HEIGHT := 1.7       # m
const CAM_DIALOGUE_PITCH := -6.0       # deg
const CAM_DIALOGUE_FOV := 42.0         # deg, tighter for an intimate two-shot

# Full-Side (design brief; this project's own working title for it was
# "orthodox") — see BroadcastCamera._update_full_side(). A real broadcast
# full-ground rig: mounted outside the boundary and elevated, not hovering
# over the ball. Unlike the old top-down version this replaces, the rig's
# pivot sits at a genuinely fixed position outside the field on the Z axis
# (SIDE_OFFSET, just past Field.SURROUND_MARGIN's fence at ~76.5m) rather
# than reaching "outside" only as a side effect of enough arm-length/pitch
# tuning — "positioned outside the field" is where the rig actually lives.
# ARM stays short on purpose: HEIGHT does the elevation directly now
# (global_position.y), so the spring arm isn't being asked to carry both
# jobs the way the old fixed-pitch version needed it to.
# Several passes tried keeping the mount close (SIDE_OFFSET 35, inside
# FIELD_HALF_WIDTH's own 67.5) and reactively pulling it back only when
# play got close to it — that chased its tail (user report across several
# rounds: "tilts down and flips", then "gets under the camera" again right
# at the boundary once the reactive pullback had already eased back out).
# The actual ask was simpler: the rig should just always live outside the
# field, past Field.FENCE_OFFSET's fence at 76.5, full stop — a real
# broadcast camera doesn't wheel itself in and out, it has one mount and
# looks across from it. SIDE_OFFSET 90 clears the fence with real margin,
# so the horizontal gap to any point on the ground is never small enough
# for pitch/yaw to go near-singular in the first place — no reactive
# pullback needed any more. HEIGHT raised alongside it (11 -> 20) so the
# extra distance doesn't flatten the look-down angle into something that
# reads as eye-level pitch-side TV.
const CAM_FULL_SIDE_SIDE_OFFSET := 90.0    # m off the centreline (Z) — where the rig is mounted
const CAM_FULL_SIDE_HEIGHT := 20.0         # m elevation
const CAM_FULL_SIDE_ARM := 6.0             # m — short; position/height already do the work

# Cheap backstop only — SIDE_OFFSET/HEIGHT above are what actually keep
# the pitch sane now, this just catches anything that somehow still gets
# unreasonably steep.
const CAM_FULL_SIDE_PITCH_MAX_DOWN := 38.0 # deg
## FOV across the rig's actual current look-distance (BroadcastCamera.
## _update_full_side's zoom comment) — NEAR is about as close as play
## can realistically get to a mount that's now permanently outside the
## fence, FAR is the opposite far corner of the ground. Narrowed from an
## earlier 55/32 (user report: "zoom in general a little more as the
## baseline") — tighter throughout, not just at one extreme.
const CAM_FULL_SIDE_FOV_NEAR := 46.0
const CAM_FULL_SIDE_FOV_FAR := 26.0
const CAM_FULL_SIDE_ZOOM_NEAR_DIST := 25.0                          # m
const CAM_FULL_SIDE_ZOOM_FAR_DIST := 180.0                          # m — far corner at full width/length spread
const CAM_FULL_SIDE_FOLLOW_RATE := 2.2     # slower than CAM_FOLLOW_RATE — a deliberate pan, not a chase

# Player-switch reorient. The soft version of this (0.6s / rate 5.0, with
# position left to _update_focus()'s own lerp) was reported as not reading
# as a switch at all — the view just drifted. BroadcastCamera.switch_target()
# now snaps the focus position onto the new player outright, and these
# shorten/quicken the yaw/pitch swing behind them so the reorient still has
# a beat of motion without being a single-frame teleport.
const CAM_SWITCH_PAN_DURATION := 0.35      # s the rig eases toward the new target's facing
const CAM_SWITCH_YAW_RATE := 14.0          # brisk — a hard swing across, close to CAM_ROTATE_RATE


# ── Input feel ───────────────────────────────────────────────────────
# §4's per-action deadzones and response curves. Movement wants a
# generous deadzone and a gentle curve (you are steering a body);
# camera-aim wants a tight deadzone and a sharper curve (you are pointing
# at something). The Input Map keeps its own deadzones at 0.05 so these,
# applied radially, are the ones that actually govern feel.
const MOVE_DEADZONE := 0.20
const MOVE_CURVE := 1.35               # >1 = finer control near centre
const LOOK_DEADZONE := 0.12
const LOOK_CURVE := 2.0

# Input buffering (fundamentals-pass brief: a press slightly early or late
# shouldn't be silently dropped just because the game wasn't in the exact
# right state on that one physics frame). See InputManager.
# consume_buffered_press() — a press is remembered for this long after the
# real Input edge, consumed (cleared) the instant whatever was blocking it
# actually acts on it. Short enough that a buffered press still reads as
# "that responded fast", not as input queuing up.
const INPUT_BUFFER_WINDOW := 0.12      # s

const RUMBLE_KICK := Vector3(0.35, 0.55, 0.18)     # (weak, strong, duration)
const RUMBLE_GATHER := Vector3(0.12, 0.0, 0.08)


# ── Match structure ──────────────────────────────────────────────────
# Full Game mode (design doc §7 priority 1). Real AFL 18-a-side. Each
# roster index maps 1:1 onto a TeamFormation slot via
# TeamFormation.ROSTER_ORDER (on-ball unit first, then back-to-forward),
# so a smaller value here still spawns a valid formation that is a strict
# prefix of the full 18 — shrinking the roster never reshuffles who
# remains. Values above 18 are unsupported: ROSTER_ORDER wraps and two
# players would double up on one slot.
const TEAM_SIZE := 18                  # players per side (real AFL)

# A real AFL quarter is 20 minutes plus time-on. 120s is a deliberately
# short default so a full 4-quarter match is playable in one sitting while
# this is being tuned by feel; QUARTERS_PER_MATCH stays at the real 4.
const QUARTER_LENGTH := 120.0          # s
const QUARTERS_PER_MATCH := 4
const QUARTER_BREAK_DURATION := 4.0    # s, paused between quarters
const SCORE_PAUSE_DURATION := 3.0      # s, paused after a goal/behind
const MATCH_END_FLASH_DURATION := 3.0  # s the "FULL TIME" scoreboard flash holds before MatchEndScreen
# Doubled from 1.0 on playtest feedback — every stoppage was snapping back
# into play too fast to read. Shared by the centre bounce, a field ball-up
# and the holding-the-ball free kick (and it is the scoreboard flash length
# for the latter two), so all of them get the same extra beat.
const CENTRE_BOUNCE_DELAY := 2.0       # s from formation-set to the bounce
# Rulebook §3: the restart after a goal specifically was reported as too
# rushed — "wait roughly 2 seconds longer than current before triggering
# the ball-up animation". That's this beat, not SCORE_PAUSE_DURATION above,
# which is the celebration/flash *before* the teams reset and is shared
# with the behind kick-in. Its own constant because CENTRE_BOUNCE_DELAY is
# also a field ball-up's delay, and a ball-up mid-play wants to stay snappy.
const GOAL_RESTART_BOUNCE_DELAY := CENTRE_BOUNCE_DELAY + 2.0   # s
const OUT_OF_BOUNDS_PAUSE_DURATION := 2.0   # s, paused for a boundary throw-in

# The field umpire's throw-up itself: the beat between the players being
# set and the ball actually leaving their hands, during which the umpire
# crouches, winds up and tosses (see Umpire.throw_up). Every stoppage that
# resolves through a ruck contest waits this out on top of its own delay
# above, so a ball-up reads as being *thrown up by someone* rather than
# the ball simply appearing in the air. Playtest feedback: ball-ups ran
# too fast to see what had happened.
const BALL_UP_THROW_DURATION := 1.4     # s

# Vertical speed the umpire's toss actually leaves his hands at (see
# FullGame._release_ruck_contest). This used to borrow BOUNCE_SPEED (10 m/s
# — a figure tuned for driving a *player's* manual bounce hard into the
# turf), which threw the ball ~6.8 m into the air: a ruckman's contest jump
# is MARK_AGGRESSIVE_JUMP_SPEED (4 m/s, ~0.8 m of lift), so the ball was
# physically unreachable and had not fallen back to a contestable height
# before RUCK_CONTEST_WINDOW expired — the hit-out was unwinnable on a
# centre bounce. A gentle lob between the two ruckmen, peaking ~1 m above
# his hands, keeps the ball inside RUCK_HIT_OUT_REACH through the 0.4 s of
# jump. Verified with a scripted centre-bounce contest.
const BALL_UP_TOSS_SPEED := 5.0         # m/s of lift on the umpire's throw-up

# The ruck contestants are only nominated when the ball is released, not
# when the throw-up starts — otherwise RUCK_CONTEST_WINDOW would be
# burning down through the whole wind-up. See FullGame._begin_ruck_contest.


# ── Contests ─────────────────────────────────────────────────────────
# Tackling splits into two commitments, Slide (held tackle button — the
# original binding) and Lunge (a tap, see TACKLE_LUNGE_TAP_* below), both
# resolved by PlayerController._resolve_tackle_contact from real closing
# speed / approach angle / carrier speed at contact — never a probability
# table (design doc §5; RULES_REFERENCE.md §3 notes Prototype 1's old
# TACKLE_BREAK_CHANCE=0.45 coin-flip was deliberately dropped for exactly
# this reason). Holding-the-ball adjudication (free kick vs ball-up) is not
# modelled yet — see RULES_REFERENCE.md §4.
const TACKLE_RADIUS := 1.4             # m, more generous than GATHER_RADIUS
# Raised from the original 0.5 alongside the original Action.TACKLED fall/
# recover clip (PlayerController._get_tackled, HumanoidAnimations._build_
# tackled) — 0.5s was tuned back when a tackle was a pure physics reaction
# with no animation to cover; now that a tackled player visibly goes down
# and gets back up, the "can't act" window needs to last as long as that
# clip does (ACTION_DURATION[TACKLED] below) or the player would be back on
# their feet and moving while the rig still reads as lying on the ground.
# Only used by Lunge's target now — a Slide connect uses TACKLE_HELD_STUN_
# DURATION just below instead, since playtest feedback wanted the two
# tackle types to read differently (see Action.TACKLE_HELD's own comment).
const TACKLE_STUN_DURATION := 1.3      # s the tackled player can't act
# Slide's target: standing, wrapped up, not knocked down — matches ACTION_
# DURATION[TACKLE_HELD] the same way TACKLE_STUN_DURATION matches TACKLED,
# just a shorter window since nobody's getting up off the ground here.
const TACKLE_HELD_STUN_DURATION := 1.0    # s

# Rulebook §6: "hold both players physically together" for the length of a
# Slide connect. How far apart they're pinned while the grab plays.
#
# Two 0.35m-radius capsules touch at 0.70m, and an earlier pass sat just
# outside that to avoid fighting move_and_slide. Playtest feedback was that
# at that range the two just collide and the arms wave near each other —
# the wrap never reads. An arm reaches 0.57m from the shoulder, so the
# hands have to get inside the other body's own radius for a wrap to look
# like a wrap. _begin_tackle_hold now adds a mutual collision exception for
# the duration instead, which is what lets this be closer than the capsules
# would otherwise allow, with no jitter from the two shoving each other.
const TACKLE_HOLD_DISTANCE := 0.55     # m between the two bodies' centres
const TACKLE_SPILL_SPEED := 3.0        # m/s the loose ball scatters at

# Slide tackle resolution (_resolve_tackle_contact(..., is_slide=true)):
# a low closing-speed bar and wide angle tolerance — it should connect even
# side-on or trailing, off almost any real motion toward the carrier ("higher
# takedown chance"). Its cost lives entirely in TACKLE_SLIDE_MISS_STUN_
# DURATION below, not in failing against a fast carrier.
const TACKLE_SLIDE_MIN_CLOSING_SPEED := 0.5     # m/s
const TACKLE_SLIDE_CLOSING_SPEED_SCALE := 0.05  # required closing speed added per m/s of carrier speed — shallow: even at CHARACTER_SPEED_MAX (11.0) this only asks for 1.05 m/s
const TACKLE_SLIDE_MAX_ANGLE_DEG := 160.0       # deg — wide; closing_speed is the real gate, this just excludes a carrier pulling straight away
# 2.6x PRIOR_OPPORTUNITY_GRACE (0.5s) — long enough that a whiffed slide
# can't reset within a single possession-grace window; longer than
# TACKLE_SLIDE_DIVE_COOLDOWN (1.1s) and BUMP_COOLDOWN (1.0s). Used to be the
# single costliest whiff in the kit outright; the hit-stick bump rework
# below gave BUMP_MISS_STUN_DURATION an even bigger number on purpose (a
# bigger swing deserves a bigger miss) — Slide stays the costliest *tackle*
# commitment, just no longer the costliest thing you can whiff, period.
const TACKLE_SLIDE_MISS_STUN_DURATION := 1.3    # s

# Lunge tackle (X tap, not carrying — a quick poke/strip at whatever's
# already within TACKLE_RADIUS, no dash, stays on feet either way). Its
# closing-speed bar starts higher than Slide's and scales up far more
# steeply with carrier speed — the concrete mechanism behind "correspondingly
# lower success chance against a strong/fast carry": at SPRINT_SPEED (8.4)
# a tackler chasing dead-straight behind a sprinting carrier nets ~0 closing
# speed and fails outright; only a genuine interception angle clears it.
const TACKLE_LUNGE_TAP_MIN_CLOSING_SPEED := 1.5    # m/s — 3x Slide's floor
const TACKLE_LUNGE_TAP_CLOSING_SPEED_SCALE := 0.35 # 7x steeper than Slide's — required closing speed hits 4.44 m/s against a SPRINT_SPEED carrier
const TACKLE_LUNGE_TAP_MAX_ANGLE_DEG := 70.0       # deg — narrower than BUMP's effective ~84° tolerance (BUMP_APPROACH_DOT_MIN=0.1), close to BUMP_CONE_DEG (55°) — roughly front-on/crossing contact only
# Deliberately "minimal" (brief: stays on feet, low commitment) — on par
# with BUMP_STUN_DURATION (0.4s) as the nearest "brief overcommit, not a
# real setback" analog in this file, well under SPOIL_COOLDOWN (0.6s), and
# ~3x below TACKLE_SLIDE_MISS_STUN_DURATION so the two moves stay clearly
# separated by miss-cost.
const TACKLE_LUNGE_TAP_COOLDOWN := 0.4    # s

# Slide's dive-in (polish-pass brief: "it's a bit hard to get the ball off
# the AI" / FIFA-style assist) — purely a movement-closing mechanic, not a
# separate resolution: once it lands the same _resolve_tackle_contact test
# every standing Slide attempt does. Not a change to TACKLE_RADIUS or a
# success-chance roll on its own — the actual bottleneck is AI_PRESSURE_
# RADIUS forcing a disposal well outside TACKLE_RADIUS, so a defender
# closing at normal run speed rarely reaches tackle range before the ball
# is gone. This gives the player a committed dash (a genuine speed burst,
# not a scripted snap onto the target) to close that exact gap. A miss here
# just means the dive didn't land — TACKLE_SLIDE_MISS_STUN_DURATION above
# is what actually makes a bad Slide costly, not this dash itself.
const TACKLE_SLIDE_DIVE_RANGE := 2.4        # m — beyond TACKLE_RADIUS, short enough to require real proximity first
# Fundamentals-pass fix: this was 7.5 — *slower* than SPRINT_SPEED (8.4)
# despite its own comment saying otherwise. SPRINT_SPEED was evidently
# raised at some point after this was tuned and this never got revisited.
# The one tool the player has for closing a gap on an AI carrier (who
# always runs at full sprint gait the instant it has the ball — see
# AIBrain._think_carrying) was quietly worse than not diving at all, which
# is a large part of why the AI could feel un-catchable. Now a genuine
# ~25% burst over sprint, same short DURATION/COOLDOWN keeping it a real
# commitment rather than a new top speed.
const TACKLE_SLIDE_DIVE_SPEED := 10.5       # m/s, faster than SPRINT_SPEED — the point of committing
const TACKLE_SLIDE_DIVE_DURATION := 0.35    # s the dash overrides normal locomotion
const TACKLE_SLIDE_DIVE_COOLDOWN := 1.1     # s between attempts — a real commitment, not spammable
const TACKLE_SLIDE_DIVE_MIN_DOT := 0.5      # facing . to-carrier must clear this — no diving sideways/backward

# Punch/Spoil (LT tap, not carrying, near an aerial contest): knocking a
# high ball away is easier than controlling it, so the reach is more
# generous than a catch's MARK_CATCH_RADIUS. Like tackle, this has no
# dedicated Tuning.Action/animation yet — an instantaneous physical contest,
# not a windup-and-contact disposal (see PlayerController._try_spoil).
const SPOIL_RADIUS := 1.6              # m
const SPOIL_IMPULSE_SPEED := 4.0       # m/s the ball is knocked away at
const SPOIL_COOLDOWN := 0.6            # s between attempts — a tap, not a battering

# Holding-the-ball ruling (RULES_REFERENCE.md §4): tackled inside this
# window since personally gaining the ball is the neutral case (ball-up,
# no signal); tackled after it has elapsed is a real ruling — see
# PlayerController._get_tackled's holding_the_ball_called signal. The
# ruling is decided here; awarding the actual free kick still needs the
# set-shot/free-kick apparatus this project doesn't have yet, so nothing
# consumes the signal today — a known, tracked gap, not a silent one.
const PRIOR_OPPORTUNITY_GRACE := 0.5   # s

# Free-kick/mark retreat distance — real AFL's "get back 10 metres" rule,
# distinct from stand-the-mark (MARK_STAND_MIN_DISTANCE above): the ONE
# nearest opponent stands exactly still (PlayerController.stand_the_mark),
# while every OTHER opponent within this radius of wherever protection was
# granted (a mark, a kick-in, a holding-the-ball free kick, an out-on-the-
# full free kick) must clear out to it. Simplified to a freeze rather than
# an active retreat-and-return (see PlayerController.grant_protection) —
# same MVP scope as everywhere else "possession + protection at the right
# spot" has been the deliberate stopping point (see docs/HANDOVER.md). This
# is a real, well-known rule number, unlike Bump's dangerous-contact
# threshold below, which genuinely has none to use.
const FREE_KICK_RETREAT_DISTANCE := 10.0   # m

# Smother (X tap, not carrying): closing down an opponent before their kick
# leaves the boot. SMOTHER_RADIUS is deliberately tighter than TACKLE_RADIUS
# — this has to be a genuine close-down, not a tackle with extra steps.
# Blocked at the boot means the ball barely moves, unlike a tackle's spill.
const SMOTHER_RADIUS := 1.1            # m
const SMOTHER_SPILL_SPEED := 1.5       # m/s

# Rebuilt from an instant "already within SMOTHER_RADIUS" check into a real
# committed dive at the kicker (PlayerController._update_smother/_try_
# smother_contact) — playtest feedback: "the X to smother does not dive the
# player onto the ground to smother the kick but rather knock the player
# over like tapping B" (that was Lunge tackle firing instead, on the same
# shared physical binding, because the old smother never actually moved —
# it only ever fired if you were already standing right on top of a kicker,
# which real play almost never lines up). Unlike Bump, this locks onto a
# specific target at launch (PlayerController._try_smother's own existing
# filter already has to find exactly one kick-aiming/mid-swing carrier to
# even trigger — "block THIS kick" is inherently targeted, not a swing at a
# spot) and re-aims at their live position every frame it's live, a
# stronger and more direct correction than Bump's own gentler assist.
const SMOTHER_COMMIT_RANGE := 3.0      # m — well beyond SMOTHER_RADIUS, close enough to require real anticipation of the kick
const SMOTHER_DIVE_SPEED := 9.0        # m/s — a genuine committed dive, just under BUMP_DASH_SPEED
# Raised from an original 0.4s after playtest feedback the dive "doesn't
# make the player dive at the ground towards oppositions player feet" —
# 0.4s wasn't enough window for the clip to actually reach the ground and
# read as a dive rather than a lunge. Matches ACTION_DURATION[SMOTHER_
# DIVE] exactly, same relationship every other paired duration in this
# file has.
const SMOTHER_DIVE_DURATION := 0.55    # s the dive overrides normal locomotion
const SMOTHER_DIVE_COOLDOWN := 0.6     # s between attempts — matches SPOIL_COOLDOWN, a committed tap, not a battering


# ── Bump ─────────────────────────────────────────────────────────────
# LB hold + Right Stick flick (design brief priority 7): Madden's hit-stick
# model. A bump disrupts balance — knockback plus a short stun, or on a
# clean connect a full knockdown — it does not itself strip the ball the
# way a tackle does (real AFL: a legal bump can put a carrier off their
# line or to ground; dispossessing them is a tackle's job, not a bump's).
# Every number below is a physics-simulation parameter (impulse speed,
# cooldown, a detection cone/window), the same category SPOIL_IMPULSE_
# SPEED/TACKLE_SPILL_SPEED already are — none of them are AFL rule
# thresholds.
#
# CRITICAL, per the brief: dangerous/high contact needs a free-kick
# consequence under the real rules, and RULES_REFERENCE.md has zero
# numbers for that judgement (no distance/angle/force/timing threshold to
# call something "dangerous" by). That half is deliberately NOT built here
# — see PlayerController.bump_landed's own doc comment — rather than
# guessing a number and presenting it as an official rule.
#
# Rebuilt from an instant proximity+cone check into a real committed dash
# (PlayerController._update_bump/_try_bump_contact), the same "external
# velocity owns the body for a window" shape Slide's dive-in
# (TACKLE_SLIDE_DIVE_*) already uses — except a bump dash never locks onto
# a target first (direction comes straight from the flick gesture), so it
# can genuinely swing at empty air. BUMP_RANGE/BUMP_CONE_DEG keep their
# original meaning, just evaluated every physics frame the dash is live
# instead of once at the instant of the flick.
const BUMP_RANGE := 2.0                # m, contact range for an attempt to even register
const BUMP_CONE_DEG := 55.0            # deg the flick can be off dead-on the carrier and still count as aimed at them
# Faster than TACKLE_SLIDE_DIVE_SPEED (10.5) — the single fastest committed
# movement in the kit, matching the single biggest miss penalty below.
# Cut from an original 11.5/4.6m of travel after real playtesting reported
# the dash carrying the bumper "too far/fast" — still faster than a sprint,
# still the fastest committed move in the kit, just not a cross-field lunge.
const BUMP_DASH_SPEED := 9.5           # m/s
const BUMP_DASH_DURATION := 0.4        # s the dash overrides normal locomotion — ~3.8m of travel at BUMP_DASH_SPEED
# Real playtesting: the dash's direction was frozen at the exact instant of
# the flick and never corrected, so it almost never actually connected with
# a carrier who was still moving by the time the dash got there — "I cannot
# hit the other player over with the hit stick." Same fix kicks already have
# (KICK_AIM_ASSIST_*): a gentle homing correction while the dash is live,
# not a lock-on — see PlayerController._apply_bump_assist().
const BUMP_ASSIST_STRENGTH := 8.0      # per-frame turn rate toward the carrier, same shape as KICK_AIM_ASSIST_STRENGTH
const BUMP_ASSIST_CONE_DEG := 70.0     # deg — wider than BUMP_CONE_DEG (55) so assist can correct a somewhat-off flick, not just confirm an already-perfect one
const BUMP_ASSIST_RANGE := 7.0         # m — beyond BUMP_DASH_SPEED*BUMP_DASH_DURATION's own ~3.8m reach, so assist can pick up a target the dash is still closing on
# Also cut after the same report: a clean connect used to send the target
# sliding 5.5 m/s worth of ground, which read as flying rather than falling.
const BUMP_KNOCKBACK_SPEED := 3.0      # m/s, a clean connect
const BUMP_STUN_DURATION := 0.4        # s — the mistimed/glancing case only; shorter than TACKLE_STUN_DURATION, a stumble, not a wrap-up
const BUMP_COOLDOWN := 1.0             # s between attempts — a real commitment, not spammable
# "Add a bit of gravity" (playtest feedback: an all-horizontal slide read as
# floaty/unweighted) — a knockdown now gets a small vertical pop, then real
# gravity (Tuning.GRAVITY) pulls it back down over this window rather than
# the floor-snap bite in _physics_process instantly cancelling the hop the
# very next frame. See PlayerController._knockdown_hop_timer.
const BUMP_KNOCKDOWN_HOP_SPEED := 2.2      # m/s upward, on the instant of any bump-triggered knockdown
const BUMP_KNOCKDOWN_HOP_DURATION := 0.3   # s the floor-snap bite is suspended so the hop can actually arc
# A clean connect (see BUMP_APPROACH_DOT_MIN below) sends the carrier all
# the way down — reusing Action.KNOCKED_BACK's own fall/recover clip
# (mirrors Action.TACKLED's pose data but falls backward, facing unchanged
# — playtest feedback: a clean hit from the front was spinning the target
# 180° to face away before falling, when it should just go straight down
# onto their back — see that Action's own comment), so this has to cover
# the same window ACTION_DURATION[KNOCKED_BACK] does, exactly like TACKLE_
# STUN_DURATION does for ACTION_DURATION[TACKLED]. Same number as that
# constant (both clips share the same 1.3s length) but kept as its own
# named constant rather than aliased to it, since the two are conceptually
# independent — TACKLE_STUN_DURATION changing for tackle-specific reasons
# shouldn't silently retune Bump too.
const BUMP_KNOCKDOWN_STUN_DURATION := 1.3
# A clean bump on a ball-carrier now jolts the ball loose on the instant of
# the hit (playtest request: "they should drop the ball at the same time
# the animation plays"), spilling forward in the hit direction. A shade
# harder than TACKLE_SPILL_SPEED (3.0) — a hit-stick is a bigger collision
# than a wrap tackle. Same "invented physics parameter, not a rule number"
# category as TACKLE_SPILL_SPEED / SPOIL_IMPULSE_SPEED.
const BUMP_SPILL_SPEED := 4.0          # m/s the ball scatters at off a clean bump
# The whiff: the dash's own timer runs out with nobody ever found. Unlike
# Slide's dive-in (which just fizzles for free if it never reaches anyone
# — see _update_slide_dive), overcommitting a hit-stick swing at nobody
# costs the bumper the same Action.TACKLED knockdown a clean connect gives
# their target, plus real extra recovery on top: deliberately the single
# biggest miss penalty in the kit (bigger than TACKLE_SLIDE_MISS_STUN_
# DURATION's 1.3s, previously the record holder — see that constant's own
# updated comment) — the bigger the swing, the bigger the whiff.
const BUMP_MISS_STUN_DURATION := 2.0   # s
# "Timing relative to the ball carrier's approach determines the outcome"
# (design brief): a bump landed while the carrier is genuinely closing on
# the bumper is clean (full knockdown); one landed on a carrier who isn't
# closing (stationary, or moving away) still connects if in range/cone,
# but glances rather than connects properly — knockback and a brief stun,
# no clip.
const BUMP_APPROACH_DOT_MIN := 0.1     # carrier velocity . (toward bumper) at/above this = clean timing
const BUMP_MISTIMED_SCALE := 0.35      # knockback/stun fraction applied when timing wasn't clean

# Flick-gesture detection (design brief: "nothing equivalent currently
# exists" — held-axis reads and tap-edges are the only two input shapes
# InputManager had before this). A flick is the stick sweeping from near-
# neutral to a strong deflection inside FLICK_WINDOW — the shape a real
# hit-stick swing actually has — not just "the stick happens to be pushed"
# the way get_look_vector() reports every frame regardless of how it got
# there. See InputManager.flick_vector().
const FLICK_WINDOW := 0.15             # s the sweep has to complete within
const FLICK_MIN_MAGNITUDE := 0.75      # deflection that counts as "the flick landed"
const FLICK_NEUTRAL_MAGNITUDE := 0.30  # deflection below this counts as "was neutral"


# ── Marking / aerial contests ────────────────────────────────────────
# Three-tier contextual catch (design brief priority 2): Safe (A) is the
# generous, reliable default; Running/RAC (X) trades security for keeping
# your stride; Aggressive/Spectacular (Y) is a real committed jump with the
# tightest margin for error. None of these roll dice — every outcome is a
# reach-radius/timing test against the ball's actual position at the
# moment of resolution, matching RULES_REFERENCE.md §3's "physical, not a
# probability table" stance, the same one tackling already follows.

# Real AFL rule: a kick has to travel this far, uninterrupted (not touching
# the ground or another player), before a catch counts as a legal mark
# rather than just a possession. The same number is also the real trigger
# distance for stand-the-mark (RULES_REFERENCE.md's existing entry for this
# name) — one rule, two consequences, so it stays one constant.
const MARK_STAND_MIN_DISTANCE := 15.0   # m

# How long a legal mark protects its taker from being tackled, counted down
# in PlayerController._protected_timer and cleared early the instant they
# dispose. RULES_REFERENCE.md's MARK_HOLD_DURATION.
const MARK_HOLD_DURATION := 5.0         # s

# Walking back from the mark. A player who takes a legal mark retreats
# before they can kick it or play on, the way a real one backs away from
# the contest to give themselves a run-up. Playtest request: "the player
# catching the ball pushes back on the mark, so they basically have to
# move backwards about 5m then they can do the rest of the kicking
# animation or play on."
#
# Not an AFL rule with a number attached — the real rule is that the mark
# is *taken* where it was caught and the kicker may retreat as far as they
# like; 5m is the requested feel value for how far that retreat carries.
# Retreat is along the team's own defensive direction (away from the goal
# being attacked), which is what "backwards" means from a kicker's point
# of view. Comfortably inside MARK_HOLD_DURATION above, so the protection
# outlasts the walk-back with time left to actually use it.
const MARK_RETREAT_DISTANCE := 5.0      # m
const MARK_RETREAT_SPEED := 3.4         # m/s — a deliberate walk back, ~1.5s for the 5m

# Set shot for goal: pressing goal_set_shot while still under mark/free-kick
# protection (_protected_timer > 0) and within this distance of the goal
# line lines up a kick aimed dead at goal instead of wherever the camera
# happens to be looking. 55m is comfortably inside AFL kicking range.
const GOAL_SET_SHOT_MAX_DISTANCE := 55.0   # m from the goal line

# The man on the mark (PlayerController._apply_stand_the_mark) is the
# nearest opponent when the mark is taken, placed a metre goal-side of the
# mark-taker so their capsules don't overlap. They JOG onto that spot
# under real movement (velocity + move_and_slide, so it collides and the
# run clip plays) rather than being slid onto it — at 18-a-side the
# "nearest" opponent can be 15-20 m away, and the old fast position-slide
# hauled them across the ground. MARK_STAND_ARRIVE_RADIUS is where the jog
# stops and the exact hold takes over. Neither is a rule number —
# feel/readability values, same category as the retreat walk-back above.
const MARK_STAND_GOAL_SIDE_OFFSET := 1.0   # m goal-side of the mark-taker
const MARK_STAND_JOG_SPEED := JOG_SPEED    # m/s onto the mark — a jog, not a drag
const MARK_STAND_ARRIVE_RADIUS := 0.3      # m — close enough, snap and hold

# Base reach from the catch point (CarryPoint doubles as the hands here) to
# the ball's actual position, scaled per tier below. A real arm's-reach
# figure, deliberately looser than GATHER_RADIUS's "already basically in
# your hands".
const MARK_CATCH_RADIUS := 1.15         # m

## Buffed from 1.0, then again from 1.4 — "I cannot catch ball" playability
## pass (see MARK_RUNNING_REACH_SCALE/MARK_AGGRESSIVE_REACH_SCALE's own
## comments for the harness this and the other two came out of): Safe is
## meant to be the generous, no-timing-skill-required default, so it should
## be the *most* forgiving of the three on reach, not merely tied with a
## tight baseline. The second bump was needed because the harness's own
## misses at 1.4 traced to ordinary delivery-aim scatter (the same one-pass
## inverse-ballistics MarkChallenge itself uses, ~1-2m of miss at typical
## coach-drill distances — see MarkChallenge._launch_speed_for's own
## comment) landing just outside reach, not a timing problem — reach is the
## only thing that can absorb that for a tier that's supposed to need no
## timing skill at all.
const MARK_SAFE_REACH_SCALE := 2.2
## Buffed from 0.8 — same "still bugging, I cannot catch ball" report that
## drove the other tiers' second widening pass below. A scripted multi-trial
## harness run at pace (real Field/Player/Ball physics, not anecdote) found
## Running's own reach envelope was the tightest of all three tiers, on top
## of demanding a same-frame press while sprinting — not a fair combination.
const MARK_RUNNING_REACH_SCALE := 1.15
## Buffed from 1.55 — a fresh multi-trial scripted verification (real
## Field/Player/Ball physics, many geometries + a timing spread, not one
## anecdote) after the previous pass's mark_timing_offset() ETA fix still
## measured 0% catches at the ring cue's own advertised "press now" instant:
## the jump's fixed ACTION_CONTACT[MARK_AGGRESSIVE] rise time (0.4s) reliably
## outlasts the ball's genuine close-approach window for a typical 16-28m
## coach-drill-style delivery, so by the time the jump peaks and resolution
## actually runs, the ball's carry-point distance has already grown back out
## past the old reach (observed regularly landing ~2.5-2.8m at resolution,
## against the old reach's 2.28m) even off a well-timed commit. Since
## reworking the jump's fixed rise time is out of scope (it's real gravity-
## integrated jump physics, not a tunable delay) and the timing-window widen
## below only helps once the ball is *within* reach, reach itself has to
## carry the rest of the fix.
const MARK_AGGRESSIVE_REACH_SCALE := 2.7   # a genuinely full-stretch, ball-still-a-bit-out grab

# Movement cost while committed to each tier — see
# PlayerController._update_locomotion / Tuning.action_speed_scale. Safe
# plants you properly; Running barely interrupts your stride, which is the
# whole point of taking it on the run; Aggressive's mid-air control comes
# from AIR_ACCELERATION instead (it's airborne), so this only governs its
# brief landing recovery.
const MARK_SAFE_SPEED_SCALE := 0.30
const MARK_RUNNING_SPEED_SCALE := 0.88
const MARK_AGGRESSIVE_SPEED_SCALE := 0.45

# The vertical impulse a spectacular attempt launches with — real jump
# physics through the same gravity/is_on_floor integration every other
# airborne frame already uses (see PlayerController._physics_process), not
# a scripted hop. v^2 = 2*g*h -> ~0.82m of standing reach at the peak:
# elite-athlete territory without being cartoonish.
const MARK_AGGRESSIVE_JUMP_SPEED := 4.0    # m/s

## The little pop a Safe (A) mark takes on catch — not a jump commitment
## like MARK_AGGRESSIVE_JUMP_SPEED above (Safe never leaves the ground
## before the catch resolves, it's a plant-and-wait tier), just a small
## reactive hop the instant the ball is secured, so a Safe take doesn't
## read as completely inert next to Running's stride and Aggressive's
## leap. v^2 = 2*g*h -> ~0.16m of lift, a hop not a jump.
const MARK_SAFE_HOP_SPEED := 1.8           # m/s

# How far out an airborne ball has to be before an aggressive attempt is
# even considered live — no point committing to a leap for a ball still the
# length of the ground away.
const MARK_CONTEST_RANGE := 6.0            # m

## Minimum distance the ball must already have travelled from wherever it
## was launched before an Aggressive attempt is considered live at all.
## Without this, a ball that's only just left the boot (still is_airborne()
## by BALL_SEMI_MINOR*2.5's low bar) sat well inside MARK_CONTEST_RANGE of
## its own kicker — the (Y) prompt would flash on the kicker's own head for
## an instant right after every kick, since nothing else was gating "is
## this ball actually in a real flight yet". See Ball.distance_since_launch().
## Scoped to Aggressive only, and to no particular player — a genuinely
## short kick shouldn't draw a leap prompt from *anyone* nearby yet.
const MARK_AGGRESSIVE_MIN_FLIGHT_DISTANCE := 3.5   # m

## How far the ball has to travel from wherever *this player* just launched
## it before they can attempt (or be prompted for) any mark tier on it
## again — scoped per-disposer via Ball.last_disposer(), unlike
## MARK_AGGRESSIVE_MIN_FLIGHT_DISTANCE above which applies to everyone.
## Bigger than that one on purpose: GATHER_COOLDOWN's flat 0.45s already
## turned out not to reliably correlate with "the ball has actually gone
## somewhere" (a short or blocked kick can still be well inside every
## tier's reach at the 0.45s mark) — see PlayerController._mark_attempt_
## blocked()'s own comment.
##
## Widened again (user report: "apply the 1. changes even more, it still
## happens") after two compounding root causes: Ball._apply_catch_gravity()
## had no idea a kicker shouldn't be treated as a valid catch target for
## their own fresh disposal, so it was physically dragging the ball
## straight back toward them regardless of what the UI/attempt gates
## decided (see _nearest_uncontested_catcher()'s own comment, which now
## shares this same window) — and this constant's *previous* value (3.5m)
## was still less than MARK_CONTEST_RANGE (6.0m), so there was a real dead
## band between "the self-clear gate just lifted" and "the ball has left
## Aggressive's own 6m contest range" where the (Y) prompt could still
## flash on the kicker for exactly that gap. Pushed past MARK_CONTEST_RANGE
## entirely so the two can no longer overlap: by the time this gate lifts,
## the ball is already outside every tier's reach, contest range included.
const MARK_SELF_CLEAR_DISTANCE := 7.5   # m, deliberately > MARK_CONTEST_RANGE

const RUMBLE_MARK := Vector3(0.20, 0.35, 0.12)

# Timing-mechanic haptics (user brief: "subtle... on the press itself" plus
# "a distinct pulse for a successful mark vs a missed one"). PRESS is
# deliberately tiny — a tick confirming the input registered, not a second
# RUMBLE_MARK — fired at the moment of a graded press (Safe's first held
# frame, Aggressive's jump commit; Running resolves the same physics frame
# as its tap, so a separate press pulse there would just be clobbered by
# the outcome pulse a moment later — see PlayerController._attempt_running_
# mark). MISS is duller/longer than RUMBLE_MARK on purpose, so a catch and
# a drop are felt as different, not just "rumble happened."
const RUMBLE_MARK_PRESS := Vector3(0.05, 0.0, 0.05)
const RUMBLE_MARK_MISS := Vector3(0.30, 0.10, 0.20)

## Fired once by MarkPrompt itself (not PlayerController — this is a UI
## timing cue, not a gameplay outcome) the instant the loading-circle ring
## completes its lap, i.e. the real "press now" instant. Same tiny-tick
## weight as RUMBLE_MARK_PRESS but on the strong motor instead of the weak
## one, so the two read as distinct even though both are subtle: "you
## pressed" (weak tick) vs "this is the moment" (strong tick).
const RUMBLE_MARK_TIMING_CUE := Vector3(0.0, 0.10, 0.06)

## Which countdown the MarkPrompt ring (and so RUMBLE_MARK_TIMING_CUE) runs
## on in real matches — a MarkCueModel.CueSource, as an int so this file
## needn't depend on that class: 0 ANALYTIC (the ring as it shipped),
## 1 GATED (same countdown, but Aggressive's ring won't complete until a
## press could actually register — the shipped ring cues a press the
## controller ignores on fast run-ins from in front), 2 MLP (Aggressive on
## the trained MarkCueModel countdown + the same gate). Only ever a cue —
## catch resolution never reads it (RULES_REFERENCE.md §3).
##
## Set to 1 (GATED) by the user's call on 2026-10-24, closing the ML page's
## MLP stage (docs/ML_AI_AUDIT.md §9). On the 27-delivery probe grid, real
## presses on each cue caught 23/27 (shipped), 24/27 (GATED) and 25/27
## (MLP). Every one of the shipped ring's misses was a press that expired
## before the range gate opened. GATED fixes that with no model in the
## loop. MLP stays a dev-page option.
##
## The ML page and MARK DELIVERY still switch their own cue without
## touching this. How GATED FEELS at match speed is still unplaytested.
const MARK_CUE_SOURCE := 1

# Madden-style contest prompt (polish-pass brief: an (A)/(X)/(Y) icon over
# the receiver's head showing which mark tiers are live right now). Height
# is above the player's own origin, not the chest-height CAM_FOCUS_HEIGHT —
# a Madden-style prompt floats over the head, a camera frames the chest.
const MARK_PROMPT_HEIGHT := 2.05       # m above player origin

# Timing-based skill mechanic (user brief): a graded press against the
# ball's live arrival, synced to its actual flight rather than a fixed
# timer — see PlayerController.mark_timing_offset(). Inside IDEAL_WINDOW is
# a full-strength attempt; inside OK_WINDOW but outside IDEAL is a
# contested one (reach narrowed by MARK_TIMING_OK_REACH_MULT, still
# physically resolved, never a probability roll — RULES_REFERENCE.md §3:
# "contests are decided by collision, timing and momentum, not by a
# probability table"); outside OK_WINDOW entirely is a drop, same as a
# missed contest today.
#
# SAFE's window is deliberately ~3x wider than RUNNING/AGGRESSIVE's, not
# uniform across tiers: Safe's whole reason to exist is "generous, reliable
# default, no timing skill required" (see this file's own comment on
# MARK_SAFE_REACH_SCALE below) — a tight gate on a held button would either
# punish the normal "plant early and wait" play style or, if graded
# leniently enough not to, do nothing at all. At realistic ball closing
# speeds a 0.65s window corresponds to a distance well outside any tier's
# reach radius, so reach — not timing — stays the practical gate for Safe;
# the window still bites at the genuine margins (a very late first hold, a
# ball that's already grounding) without eroding the tier's identity.
# Fundamentals-pass retune: RUNNING/AGGRESSIVE were 0.12/0.24 — tight
# enough that a well-positioned player mistiming a press by what's a very
# ordinary margin under real reaction pressure (more so while still
# learning the mechanic) would drop a catch that needed no timing skill at
# all before this feature existed. That's very likely a real chunk of
# "catching feels unreliable even when positioned right" — the reach math
# itself isn't at fault, the window it's being graded against was too
# small. Widened, still meaningfully tighter than SAFE's 0.35/0.65 so the
# tier spread survives.
## Widened again (still "cannot catch ball" after the previous pass above) —
## real numbers this time, not a guess: a scripted multi-trial harness (many
## geometries, many press-timing offsets, real Field/Player/Ball physics)
## found the *mark_timing_offset() estimate itself* still lands with real
## error even after this file's other fixes (the quadratic-ETA correction in
## mark_timing_offset(), the premature-sentinel-at-the-true-minimum fix —
## see that function's own comments), on the order of several tenths of a
## second for a typical delivery. A window has to be wider than the error
## it's meant to absorb or it isn't absorbing it. Safe stays the widest of
## the three (still "no timing skill required" by design), but all three
## grew.
const MARK_SAFE_IDEAL_WINDOW := 0.55   # s
const MARK_SAFE_OK_WINDOW := 0.95      # s
const MARK_RUNNING_IDEAL_WINDOW := 0.35   # s
const MARK_RUNNING_OK_WINDOW := 0.65      # s

## Split from RUNNING's profile (they used to share one) and widened again
## — "I cannot catch it" — Aggressive is graded against a *predicted*
## instant (the jump's fixed-length rise means resolution always lands
## ACTION_CONTACT[MARK_AGGRESSIVE] seconds after the press, not on it), so
## even a player who reads the ball correctly is fighting their own
## reaction time on top of the read itself, which Running's same-frame
## resolution never asks of them. The MarkPrompt ring's redesign into a
## completing loading-circle (see mark_prompt.gd) is the other half of
## this fix — a clearer "press now" cue — but the window itself needed
## real headroom too, not just a better cue for the same tight target.
##
## Widened again alongside SAFE/RUNNING above for the same "still bugging"
## report — see that comment for the harness this came out of. Aggressive
## stays the tightest of the three by design (it's the skill-reward tier),
## but "tightest" no longer means "a few tenths of a second," which the
## fresh verification pass showed was still landing inside the
## mark_timing_offset() estimate's own error margin, not a real skill gate.
const MARK_AGGRESSIVE_IDEAL_WINDOW := 0.45   # s
const MARK_AGGRESSIVE_OK_WINDOW := 0.85      # s

## Reach multiplier for a contested (in-OK, outside-IDEAL) attempt — applied
## to the tier's own REACH_SCALE before MARK_ASSIST_RADIUS_BONUS, same
## layering that bonus itself already uses. A genuine miss (outside OK
## entirely) scales reach to nothing at all: the user asked for "too early,
## too late, or not at all" to read as a real drop, same as a missed
## contest today, not a softened one — MARK_ASSIST_RADIUS_BONUS's flat
## +0.35m is the only forgiveness a bad-timed attempt keeps, same as it
## already applies uniformly to every tier regardless of timing.
##
## Fundamentals-pass retune: OK_REACH_MULT 0.55 -> 0.65 — a contested catch
## should still feel meaningfully live, not barely-there. MISS_REACH_SCALE
## stays at 0.0 on purpose: the wider windows above are the actual fix for
## "unreliable", not softening what a genuine drop means once you're
## outside them — that would blur the exact distinction the user asked for.
const MARK_TIMING_OK_REACH_MULT := 0.65
const MARK_TIMING_MISS_REACH_SCALE := 0.0

## Below this closing speed, mark_timing_offset() stops dividing distance by
## an near-zero rate (which would blow up toward +/-inf) and instead checks
## MARK_TIMING_ARRIVED_RADIUS below — the ball is no longer meaningfully
## closing on this player, whether because it's already arrived (radial
## closing speed naturally craters toward zero right at a true closest
## approach — see mark_timing_offset()'s own comment) or because it's
## genuinely drifting past/away.
const MARK_TIMING_MIN_CLOSING_SPEED := 0.6   # m/s
const MARK_TIMING_PAST_PEAK_OFFSET := 1.0    # s — sentinel, larger than every OK window above

## How close counts as "might as well already be here" — checked in
## mark_timing_offset() unconditionally, before any velocity-based read, and
## graded as offset 0 (ideal) rather than the past-peak sentinel. Set to
## Aggressive's own full reach (the widest of the three tiers, so this
## radius never grades a tier's own genuine miss as an arrival) plus the
## flat assist bonus every tier already gets.
##
## Originally gated behind closing speed dropping below
## MARK_TIMING_MIN_CLOSING_SPEED first (only treat "close" as "arrived" once
## the ball had also stopped visibly closing) — multi-trial scripted
## verification (real Field/Player/Ball physics, a moving Running-tier
## player, many geometries) found that gate could miss the ball's true
## closest approach entirely: a fast crossing can swing the radial closing
## speed from clearly-closing to clearly-departing within a single 60Hz
## physics step, so a frame sampled right at the crossing can read neither
## condition and fall straight through to the sentinel despite the ball
## being well inside reach. Distance alone doesn't have that blind spot, so
## it's checked first, unconditionally.
const MARK_TIMING_ARRIVED_RADIUS := MARK_CATCH_RADIUS * MARK_AGGRESSIVE_REACH_SCALE + MARK_ASSIST_RADIUS_BONUS


# ── Ruck contests ────────────────────────────────────────────────────
# Design brief priority 4: one shared contest mechanic for the centre
# bounce, a field ball-up (a tackle resolved inside PRIOR_OPPORTUNITY_GRACE
# — the neutral case, RULES_REFERENCE.md §4) and a boundary throw-in. All
# three differ only in where the contest happens and which two players are
# nominated to contest it (see FullGame._begin_ruck_contest and its call
# sites) — the contest itself, below, is the same every time.
#
# Ruckmen contest it with the exact same vertical jump a spectacular mark
# already uses (MARK_AGGRESSIVE_JUMP_SPEED, via PlayerController.
# _pending_jump — no separate arc code, see _begin_hit_out), so REACH is
# deliberately the aggressive mark's own catch radius, not a new number:
# it is the identical leap, just resolved as a palm instead of a grab.
const RUCK_HIT_OUT_REACH := MARK_CATCH_RADIUS * MARK_AGGRESSIVE_REACH_SCALE
## How far out a hit-out attempt can even be committed from — tighter than
## MARK_CONTEST_RANGE, since a ruck contest is point-blank by nature (two
## players standing either side of where the ball is about to come down),
## not a leap in from open play.
const RUCK_CONTEST_JUMP_RANGE := 3.0    # m
## The palm itself — a physical velocity given to the ball on a successful
## hit-out, same "invented physics parameter, not an invented rule number"
## category as SPOIL_IMPULSE_SPEED/TACKLE_SPILL_SPEED elsewhere in this
## file. Directed by _hit_out_aim_dir in _resolve_hit_out — where Left
## stick was held on the RB press ("tap direction = pass direction", user
## brief) — falling back to body-forward on a neutral stick.
const RUCK_HIT_OUT_SPEED := 6.0         # m/s, horizontal
const RUCK_HIT_OUT_UP_SPEED := 1.5      # m/s of lift, so it reads as a palm, not a grounder
## How long a nominated contestant reads RB as a hit-out at all (see
## PlayerController.set_ruck_contestant) — self-expiring like
## _protected_timer, so the flag can't linger past the one contest it was
## armed for. 2.0 s (up from 1.5): with the gentler BALL_UP_TOSS_SPEED the
## ball is contestable both on the way up and as it drops back to head
## height, and a human reacting to the visible throw-up rather than a
## frame-perfect input still gets a genuine shot at it.
const RUCK_CONTEST_WINDOW := 2.0        # s

# The same A press that attempts a Safe Mark becomes this once the ball
# isn't in the air (design brief: the action comes from "ball state +
# player state + proximity + input", not just the button). Wider and
# speed-responsive versus the passive walk-over GATHER_RADIUS, modelling a
# deliberate reach for a contested ground ball rather than the ball simply
# ending up underfoot.
const GROUND_PICKUP_RADIUS := 1.3              # m
const GROUND_PICKUP_LUNGE_PER_SPEED := 0.05    # m of extra reach per m/s of current speed


# ── Catch assist ─────────────────────────────────────────────────────
# "Make marking a little easier" — two independent, additive forgiveness
# levers rather than one blunt one, both still resolved physically (a
# wider real reach / a real attractive force) rather than a hidden
# probability bump, so RULES_REFERENCE.md §3's stance holds even while
# being more forgiving.

# Widens every mark tier's reach uniformly — applied as a flat bonus on
# top of MARK_CATCH_RADIUS (see PlayerController._ball_in_catch_reach)
# rather than folded into the per-tier scales, so the *relative*
# safe/running/aggressive risk relationship — the whole point of having
# three tiers — doesn't get flattened out by making them all easier by
# the same multiple.
## Nudged up from 0.35 — still a flat, tier-independent bonus (see the
## comment above), just a bit more forgiving so a reasonably-timed mark
## attempt isn't lost purely to reach.
const MARK_ASSIST_RADIUS_BONUS := 0.5    # m

# "Catch gravity": a genuine small attractive force pulling the ball
# toward whichever uncontested (not-carrying) player is nearest while
# it's airborne — the same physical-forces mechanism drag/Magnus already
# are (Ball._integrate_forces), not a scripted snap onto a player. Full
# strength at point-blank range, fading to nothing at CATCH_GRAVITY_RADIUS.
# Both widened a little from 2.75/2.2 — the assist now reaches out and
# pulls a shade harder, so a pass that lands near but not exactly on a
# receiver still has a real chance of ending up in their hands.
const CATCH_GRAVITY_RADIUS := 3.25       # m
const CATCH_GRAVITY_ACCEL := 2.6         # m/s^2 at point-blank range


# ── Character screen ─────────────────────────────────────────────────
# Ported from Prototype 1's character_state.py / character_render.py: a
# live attributes screen with two adjustable stats (Speed, Height) and a
# pixel-wipe entry/exit. P1's CHARACTER_SPEED_MIN/MAX (12..26) were
# abstract logical units/s on its diorama grid; here Speed is the
# player's effective SPRINT_SPEED in real m/s, so PLAYER_CONTROLLER's
# speed_scale (speed / CHARACTER_SPEED_DEFAULT) multiplies WALK/JOG/
# SPRINT uniformly. Height stays real centimetres — HumanoidRig's
# proportions already assume a 185cm baseline, so CHARACTER_HEIGHT_
# DEFAULT matches it exactly and height_scale becomes a uniform rig
# scale rather than a re-derived skeleton.
const CHARACTER_SPEED_MIN := 6.0        # m/s
const CHARACTER_SPEED_MAX := 11.0       # m/s
const CHARACTER_SPEED_STEP := 0.25      # m/s per Left/Right nudge
const CHARACTER_SPEED_DEFAULT := SPRINT_SPEED

const CHARACTER_HEIGHT_MIN := 165.0     # cm
const CHARACTER_HEIGHT_MAX := 205.0     # cm
const CHARACTER_HEIGHT_STEP := 1.0      # cm per Left/Right nudge
const CHARACTER_HEIGHT_DEFAULT := 185.0 # matches HumanoidRig's HIP_HEIGHT rig

# Kicking Power is a straight multiplier on KICK_MIN/MAX_SPEED (see
# PlayerController._kick_parameters), so it scales range the same way a
# harder-struck ball naturally would. Kicking Accuracy is inverted from
# how it reads on screen: 1.0 (full bar) is pinpoint, 0.0 (empty bar) is
# KICK_ACCURACY_MAX_SPREAD_DEG of random aim error in every direction —
# see PlayerController._dispose's KICK branch for where the error is
# actually rolled (at the moment of the kick, not before — the on-screen
# trajectory cue shows the aimed path, since the error isn't knowable
# ahead of it).
const CHARACTER_KICK_POWER_MIN := 0.7
const CHARACTER_KICK_POWER_MAX := 1.3
const CHARACTER_KICK_POWER_STEP := 0.05
const CHARACTER_KICK_POWER_DEFAULT := 1.0

const CHARACTER_KICK_ACCURACY_MIN := 0.0
const CHARACTER_KICK_ACCURACY_MAX := 1.0
const CHARACTER_KICK_ACCURACY_STEP := 0.05
const CHARACTER_KICK_ACCURACY_DEFAULT := 0.8

# Agility is a unitless multiplier (1.0 == baseline tuning), not an SI
# quantity like Speed/Height. It drives how fast a player turns out of a
# backpedal (Tuning.backpedal_turnout_duration) and, more gently, the
# plant-and-pivot / rig-facing turn rates (Tuning.agility_turn_rate_mult).
# PlayerController.agility_scale is CharacterProfile.agility / DEFAULT.
const CHARACTER_AGILITY_MIN := 0.6
const CHARACTER_AGILITY_MAX := 1.5
const CHARACTER_AGILITY_STEP := 0.05
const CHARACTER_AGILITY_DEFAULT := 1.0

const KICK_ACCURACY_MAX_SPREAD_DEG := 12.0  # deg of random error at zero accuracy

const CHARACTER_TRANSITION_TIME := 0.3  # s, pixel-wipe cover/reveal duration


# ── AI ───────────────────────────────────────────────────────────────
# Deliberately simple: chase the loose ball, run the carry toward goal,
# press the opposing carrier, otherwise drift toward a kickoff slot. Not
# a tactics system — a baseline to prove the match loop, tuned by feel
# from here.
const AI_KICK_RANGE := 45.0            # m from goal at which a carrier shoots
const AI_PRESSURE_RADIUS := 4.0        # m opponent proximity that forces a quick disposal
const AI_SUPPORT_PULL := 0.35          # 0..1, how far off-ball players drift toward the ball

## Off by default, and not to be turned on in real matches without the
## user's say-so (docs/NEXT_AGENT_MARKING_BRIEF.md Part 2.5). On, AIBrain
## stops being Safe-only. It leaps (Aggressive) for a contested kick, on
## the MarkCueModel countdown with its press gate. It taps Running in
## stride when it's moving at pace and the ball is in Running's reach.
## Otherwise it holds Safe as before. The model only times the press;
## the tier choice is a fixed rule, and the catch is still decided by
## reach + timing (RULES_REFERENCE.md §3). AIBrain.use_mark_cue_model
## starts from this, so a dev check can flip it for one run.
const AI_MARK_USE_CUE_MODEL := false
## With the flag on: only take a ball in stride (Running) when its
## straight-line closest approach comes this far inside Running's reach —
## the prediction ignores gravity's curve, so not right at the edge.
## Unplaytested feel guess.
const AI_MARK_RUNNING_TAKE_FRACTION := 0.75

## Team Edit expansion (polish-pass brief: Ball Movement preference — see
## AIBrain._lateral_target_z()). How close to the actual boundary a fully
## boundary-committed lateral target sits — short of 1.0 so "commits to the
## wing" still means "runs it down the flank", not "hugs the out-of-bounds
## line".
const AI_BOUNDARY_LEAN_FRACTION := 0.85

# A human notices a loose ball and starts moving with a beat of reaction
# time; an AI polling ball.holder() every frame does not. Without this, AI
# wins effectively every race to a loose ball (it also defaults to sprint
# gait, see _think_loose_ball) and the human can end up never touching the
# ball in a full match. Randomised per player so a whole team doesn't react
# in lockstep.
const AI_LOOSE_BALL_REACTION_MIN := 0.15   # s
const AI_LOOSE_BALL_REACTION_MAX := 0.40   # s

# ── AI disposal target selection (ai_brain.gd _best_disposal_target / _think_carrying) ──
# Feel-tuned AI judgement, the same standing as AI_KICK_RANGE / AI_SUPPORT_
# PULL above — NOT AFL rule numbers. They decide which teammate a carrying
# AI gives it to when a shot at goal isn't on; before this pass there was
# nothing here at all (the AI fired every disposal down its own run line).
const AI_DISPOSAL_MIN := 6.0            # m — nearer than this isn't a real disposal option
const AI_HANDBALL_MAX := 18.0          # m — inside this the AI handballs the pass; past it, kicks
const AI_KICK_MAX := 50.0              # m — no target further than this is weighed
const AI_DISPOSAL_MIN_FORWARD := -0.15 # dot(dir-to-mate, dir-to-goal); below = backwards, rejected unless pressured
const AI_LANE_BLOCK_RADIUS := 1.6      # m — an opponent within this of the pass line kills that option
const AI_DISPOSAL_SCORE_FLOOR := 0.35  # 0..1 — no teammate above this: keep running / blind fallback
const AI_DISPOSAL_W_FORWARD := 0.50    # weight: how far toward goal the pass advances it
const AI_DISPOSAL_W_OPEN := 0.35       # weight: how much room the receiver has (nearest opponent to them)
const AI_DISPOSAL_W_DIST := 0.15       # weight: shorter is safer
const AI_PASS_KICK_CHARGE := 0.55      # kick charge fraction for a pass to a teammate (vs 0.75 for a goal shot)
const AI_AIM_TURN_FRAMES_HANDBALL := 2 # physics frames the body pre-turns onto a handball target before release
const AI_AIM_TURN_FRAMES_KICK := 6     # ditto for a kick — longer, an AI kick's aim locks to body facing at stance start

# A carrying AI bounces at this fraction of BOUNCE_INTERVAL, so it disposes
# or bounces before ever conceding the 15 m free kick
# (PlayerController.run_too_far_called). Judgement value, not a rule.
const AI_BOUNCE_AT_FRACTION := 0.75

# ── AI off-ball spacing & contest commit (ai_brain.gd, "close the audit points" pass) ──
const AI_SPACING_RADIUS := 4.0          # m — off-ball teammates inside this push apart so they don't stack
const AI_TACKLE_CLOSING_MARGIN := 0.6   # m/s — carrier may be this much faster than us and we still commit the tackle
const AI_LOOSE_BALL_CEDE_MARGIN := 2.0  # m — an opponent this much nearer the drop zone: ease off rather than overrun

# ControlMode.Scheme.TEAM_COMMAND (control-mode pass): how far ahead of the
# selected player an issued "lead here" order's target point sits. Not an
# AFL number — there's nothing to cite — just a placeholder distance long
# enough to look like a real lead run and short enough to stay on-screen
# from the follow cam. Expect this to move once someone actually plays the
# mode; see docs/HANDOVER.md's control-mode entry.
const COMMAND_LEAD_DISTANCE := 12.0     # m

# Call for the ball (Settings.PlayerControlMode.SINGLE_PLAYER — see
# FullGame._call_for_ball). Not an AFL rule: there is no "calling" mechanic
# in the laws of the game, so nothing here has a rule number to cite. It
# exists because SINGLE_PLAYER locks the human to one body for the whole
# match, which removes switch_player's escape hatch and leaves them with no
# way at all to influence a teammate's disposal. Every number below is
# either derived from an existing constant in this file or explained where
# it sits.
#
# Range is the one number that IS derived rather than felt out: the flat
# ballistic range of this project's own handball (HANDBALL_SPEED 15 m/s at
# HANDBALL_ANGLE 9 deg) is v^2 * sin(2*theta) / g = 225 * 0.309 / 9.80665
# ~= 7.1 m, doubled because a handball is a lead pass onto a running
# receiver, not a pass to the chest — the receiver covers the back half.
# Past that a handball simply cannot reach, so the call is refused outright
# rather than rolled for and then thrown short.
const CALL_FOR_BALL_RANGE := 14.0       # m, ~2x a handball's own flat range

# A player can shout for it, not machine-gun it. Without a cooldown the
# probability below is meaningless — mashing the key converts any non-zero
# chance into a certainty within a second. Roughly the length of one called
# lead; short enough that a genuine second effort is still allowed.
const CALL_FOR_BALL_COOLDOWN := 1.2     # s

# Chance = BASE + PRESSURE_BONUS*p + OPENNESS_BONUS*o - RANGE_PENALTY*r,
# clamped to MIN..MAX. See FullGame._call_for_ball_success_chance() for what
# p/o/r actually measure and why pressure on the carrier RAISES the chance.
# BASE sits below even money: a called handball is a request, and the
# carrier's own AI is entitled to back its own judgement most of the time.
# The three weights are sized so pressure is the dominant term (it's the
# factor the human can actually create, by drawing a defender), openness
# second (it rewards leading into space rather than standing still), and
# range a modest tax rather than a cliff (the hard cliff is
# CALL_FOR_BALL_RANGE above).
const CALL_FOR_BALL_BASE_CHANCE := 0.35
const CALL_FOR_BALL_PRESSURE_BONUS := 0.30
const CALL_FOR_BALL_OPENNESS_BONUS := 0.25
const CALL_FOR_BALL_RANGE_PENALTY := 0.20
# Never a certainty and never impossible — the same reason this project
# resolves contests physically rather than on a die roll applies to the
# edges of a die roll it does keep: a guaranteed outcome stops being a
# decision.
const CALL_FOR_BALL_MIN_CHANCE := 0.05
const CALL_FOR_BALL_MAX_CHANCE := 0.95


# ── Training coaches ────────────────────────────────────────────────
# All three now exist (design brief): kicking, marking, and tackling —
# all sharing the same proximity-trigger / dialogue / challenge shape
# (kick_to_kick.gd's CoachKind-parameterised state machine) — wiring any of
# this into Full Game is explicitly later work.
const COACH_INTERACT_RADIUS := 2.5             # m, proximity that shows the prompt
const COACH_STAND_OFFSET := Vector3(18.0, 0.0, 10.0)   # from field centre, kick_to_kick only
const MARK_COACH_STAND_OFFSET := Vector3(-18.0, 0.0, 10.0)   # opposite half, clear of the kicking drill's target zone
## Same X as the rival's own stand offset below, mirrored to +Z so it's
## clear of both the kicking/marking coaches' shared Z=10 row and the
## rival's own Z=-18 anchor.
const TACKLE_COACH_STAND_OFFSET := Vector3(0.0, 0.0, 18.0)

const KICK_CHALLENGE_TARGET_DISTANCE := 40.0   # m downfield of the player when accepted
const KICK_CHALLENGE_TARGET_RADIUS := 3.0      # m, hit tolerance

# Kick-to-kick rival (polish-pass brief: "build out kick-to-kick so we can
# use this for testing" — a solo sandbox has nobody to tackle, bump, or
# contest a mark against, so none of Full Game's live contests could ever
# actually be practised here). Reuses AIBrain outright rather than a new
# "practice partner" behaviour tree — the same chase/mark/dispose/press-and-
# tackle loop Full Game's AI already runs is exactly the sparring partner
# this needs, and a chase-and-return loop against one real opponent is also
# just what "kick to kick" already means. Frozen (KickToKick.set_physics_
# process(false)) for the duration of a coach dialogue/challenge so a drill
# stays a clean 1-on-0 loop — see kick_to_kick.gd's _coach_state gate.
const KICK_TO_KICK_RIVAL_OFFSET := Vector3(0.0, 0.0, -18.0)   # from field centre, clear of both coach zones
const KICK_CHALLENGE_ATTEMPTS := 5

const MARK_CHALLENGE_ATTEMPTS := 6
const MARK_CHALLENGE_ELEVATION_DEG := 48.0     # deg, a generous hang-time arc
const MARK_CHALLENGE_MIN_DISTANCE := 16.0      # m, just past MARK_STAND_MIN_DISTANCE so every delivery is legal-mark eligible
const MARK_CHALLENGE_MAX_DISTANCE := 28.0      # m
const MARK_CHALLENGE_TARGET_SPREAD := 4.0      # m random offset from the player's current spot per delivery
## Widened from 1.4 (user report: "I miss the first kick because I don't
## have a chance to run before the coach kicks it") — 1.4s wasn't enough
## runway to come out of the accept-challenge camera cut, get moving, and
## actually be in position before the very first delivery left the coach.
## MARK_CHALLENGE_NEXT_DELAY (the gap between every later delivery) is
## untouched — by then the player is already warmed up from the previous
## rep and doesn't need the same head start.
const MARK_CHALLENGE_DELIVERY_DELAY := 2.6     # s, the coach "calling for it" before the ball leaves
const MARK_CHALLENGE_NEXT_DELAY := 1.6         # s after an attempt resolves before the next delivery

## Delivery cycles through all three tiers (MarkChallenge._deliver()) rather
## than always aiming a generic floaty ball at wherever the player already
## stands — the old single delivery shape only ever really trained Safe
## (a ball landing on your own spot never asks you to run onto it or leap
## for it), so Running/Aggressive went essentially untaught by "the marking
## coach". Values above (ELEVATION_DEG/TARGET_SPREAD) are now specifically
## the Safe delivery's own numbers; these two below are Running's and
## Aggressive's.
##
## Running: the target leads the player's current facing/motion by this
## much (plus the usual TARGET_SPREAD jitter) — a ball you have to run
## onto, not one that arrives on your own two feet.
const MARK_CHALLENGE_RUNNING_LEAD_DISTANCE := 5.0   # m

## Aggressive: the target sits this far off the player's current spot —
## inside Aggressive's own extended reach (MARK_CATCH_RADIUS *
## MARK_AGGRESSIVE_REACH_SCALE + MARK_ASSIST_RADIUS_BONUS ≈ 2.28m) but
## outside Safe's (≈1.65m), so standing still and waiting genuinely can't
## take it — only committing to the leap can. A steeper arc than the
## default buys extra hang time to actually read the timing cue.
const MARK_CHALLENGE_AGGRESSIVE_OFFSET := 1.9       # m
const MARK_CHALLENGE_AGGRESSIVE_ELEVATION_DEG := 60.0   # deg

# Tackling tutorial (design brief's third coach, reworked): a guided,
# step-by-step walk through the tackle kit rather than the old chase-from-
# behind drill. Each step freezes the game to show the binding (keyboard +
# controller, both at once), then sends the kick-to-kick rival — driven by
# TutorialDummyBrain, not its usual AIBrain — jogging straight at the player
# to apply that one control. See TackleTutorial's own header for the step
# list. Steps: close the gap / slide dive-in / standing slide / lunge / hit
# stick.
const TACKLE_TUTORIAL_APPROACH_DISTANCE := 16.0   # m, where the "close the gap" step spawns the dummy
const TACKLE_TUTORIAL_CONTACT_LEAD := 9.0         # m in front of the player a contact-range rep spawns the dummy
# The dummy holds here for the dive-in step: past TACKLE_RADIUS (1.4m) so a
# standing tackle can't reach, inside TACKLE_SLIDE_DIVE_RANGE (2.4m) so the
# dive can — the one gap only the dive-in closes.
const TACKLE_TUTORIAL_DIVE_HOLD_DISTANCE := 2.2   # m
const TACKLE_TUTORIAL_SPRINT_CLEAR_RANGE := 3.0   # m from the dummy that counts as "you closed the gap"
const TACKLE_TUTORIAL_STALE_REP_TIME := 4.0       # s a no-result rep runs before it silently restarts (a tutorial retries, it doesn't fail)
const TACKLE_TUTORIAL_STEP_GAP := 1.2             # s beat between a cleared step and the next card
const TACKLE_TUTORIAL_DUMMY_GAIT := 0.85          # 0..1 — a jog, not a sprint, so there's time to read the approach

# Padded tackle bags — training-ground dressing beside the tackling coach.
# Player-sized flat-topped red cylinders, no branding (see TackleBag).
# Offsets are from the tackling coach's own stand point; index 0 is the
# prominent upright bag right by the coach, indices 1+ are spares tipped
# over on the ground a couple of metres to the side (TACKLE_BAG_LIE_YAWS
# spins each so they don't line up).
const TACKLE_BAG_HEIGHT := 1.8                    # m, player height
const TACKLE_BAG_RADIUS := 0.33                   # m
const TACKLE_BAG_COLOUR := Color(0.78, 0.11, 0.11)
const TACKLE_BAG_BASE_COLOUR := Color(0.09, 0.09, 0.1)
const TACKLE_BAG_OFFSETS: Array[Vector3] = [
	Vector3(2.0, 0.0, 0.5),
	Vector3(4.4, 0.0, 2.4),
	Vector3(2.6, 0.0, 3.6),
]
## Yaw (radians) for each lying bag, i.e. TACKLE_BAG_OFFSETS[1..]. One shorter
## than the offsets list — the upright bag at index 0 doesn't use it.
const TACKLE_BAG_LIE_YAWS: Array[float] = [0.35, -0.95]


## Maps a 0..1 gait scalar onto the three named speeds, so WALK_SPEED,
## JOG_SPEED and SPRINT_SPEED stay meaningful tunables rather than being
## smeared into one linear ramp.
static func speed_for_gait(gait: float) -> float:
	var g := clampf(gait, 0.0, 1.0)
	if g <= 0.001:
		return 0.0
	if g < GAIT_WALK:
		return remap(g, 0.0, GAIT_WALK, 0.0, WALK_SPEED)
	if g < GAIT_JOG:
		return remap(g, GAIT_WALK, GAIT_JOG, WALK_SPEED, JOG_SPEED)
	return remap(g, GAIT_JOG, 1.0, JOG_SPEED, SPRINT_SPEED)


## How long a backpedal shuffle may run before the body turns out of it,
## for a player of the given agility_scale (CharacterProfile.agility_scale,
## 1.0 == baseline). Higher agility turns out sooner, clamped so it never
## drops below a readable shuffle (BACKPEDAL_TURNOUT_MIN_DURATION) and a
## sluggish player (agility CHARACTER_AGILITY_MIN) never exceeds the old
## ~1s feel.
static func backpedal_turnout_duration(agility_scale: float) -> float:
	return clampf(BACKPEDAL_MAX_DURATION / maxf(agility_scale, 0.01),
		BACKPEDAL_TURNOUT_MIN_DURATION, BACKPEDAL_MAX_DURATION / CHARACTER_AGILITY_MIN)


## Multiplier on turn rates (plant-and-pivot sweep + rig facing) for the
## given agility_scale. clampf keeps agility 1.0 at exactly 1.0x.
static func agility_turn_rate_mult(agility_scale: float) -> float:
	return clampf(agility_scale, AGILITY_TURN_RATE_MIN_MULT, AGILITY_TURN_RATE_MAX_MULT)


static func action_duration(action: Action) -> float:
	return float(ACTION_DURATION.get(action, 0.0))


static func action_contact_time(action: Action) -> float:
	return float(ACTION_CONTACT.get(action, 0.0))


## Fraction of target speed available while `action` is active. KICK/
## HANDBALL/BOUNCE all share the one historical ACTION_SPEED_SCALE; the
## mark tiers each cost a different amount because that cost is the whole
## point of choosing between them (see the Marking section above).
static func action_speed_scale(action: Action) -> float:
	match action:
		Action.MARK_SAFE, Action.MARK_SAFE_MISS:
			return MARK_SAFE_SPEED_SCALE
		Action.MARK_RUNNING, Action.MARK_RUNNING_MISS:
			return MARK_RUNNING_SPEED_SCALE
		Action.MARK_AGGRESSIVE, Action.HIT_OUT:
			return MARK_AGGRESSIVE_SPEED_SCALE
		Action.TACKLED:
			# Redundant with _stun_timer (which already forces gait to 0 for
			# this action's entire duration — see TACKLE_STUN_DURATION's own
			# comment) but explicit rather than incidental: a player lying on
			# the ground moves at 0, full stop, not "reduced".
			return 0.0
		_:
			return ACTION_SPEED_SCALE
