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

enum Action { NONE, KICK, HANDBALL, BOUNCE }


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
const ACCELERATION := 9.0              # m/s^2 speeding up
const BRAKING := 14.0                  # m/s^2 slowing down
const AIR_ACCELERATION := 2.0          # m/s^2 while airborne (very little authority)

# Turn rate falls off with speed — this is the single biggest contributor
# to "weight". At a standstill you pivot on the spot; at a full sprint you
# describe an arc. Turn radius = speed / turn_rate, so SPRINT here gives
# 8.4 / 2.79 rad/s ~= 3.0m — tight enough to stay playable, wide enough
# that a sprint commits you.
const TURN_RATE_STANDING := 900.0      # deg/s at zero speed
const TURN_RATE_SPRINT := 160.0        # deg/s at SPRINT_SPEED

# How much a change of direction costs you in speed. Running back against
# your own momentum drives target speed to REVERSE_SPEED_SCALE, so you
# brake, and braking raises your turn rate, so you plant and swing round.
# Two coupled rules, one emergent plant-and-pivot — no special case.
const REVERSE_SPEED_SCALE := 0.0       # target speed multiplier at 180 deg off heading

# Below this speed there is no momentum worth fighting, so the heading
# snaps straight to intent and you simply turn on the spot.
const PIVOT_SPEED_THRESHOLD := 0.4     # m/s

# The rig's facing turns faster than the velocity heading does, so the
# body leads the change of direction and the velocity lags behind it.
# That lag is what feeds the blend space's strafe axis (see
# player_animation.gd) — a hard turn genuinely blends lateral animation
# instead of the model just snapping round.
const FACING_TURN_RATE := 720.0        # deg/s

const GRAVITY := 9.80665               # m/s^2

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
const BALL_BOUNCE := 0.45
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
# is an outcome rather than an input. 30 m/s at 40 degrees lands around
# 55-60m with drag applied, which matches a long AFL drop punt.
# (P1: KICK_MAX_RANGE = 88 logical units, BALL_FLIGHT_SPEED = 95 — both
# scripted-flight parameters with no physical meaning here.)
const KICK_CHARGE_TIME := 0.85         # seconds held to reach full power
const KICK_MIN_SPEED := 13.0           # m/s, a tapped stab pass
const KICK_MAX_SPEED := 30.0           # m/s, a full-blooded drop punt
const KICK_MIN_ANGLE := 22.0           # deg elevation at zero charge (flat, fast)
const KICK_MAX_ANGLE := 40.0           # deg elevation at full charge (long, high)
const KICK_BACKSPIN := 26.0            # rad/s end-over-end, the drop punt signature

const HANDBALL_SPEED := 15.0           # m/s (P1: HANDBALL_RANGE = 34 units)
const HANDBALL_ANGLE := 9.0            # deg elevation — flat and fast
const HANDBALL_SPIN := 4.0             # rad/s

const BOUNCE_SPEED := 8.0              # m/s driving the ball into the turf
# Down, but far enough ahead that a running player runs onto the rebound.
const BOUNCE_ANGLE := -52.0            # deg

# A kick on the run goes further than the same kick standing still.
# Fraction of the player's horizontal velocity added to the ball.
const DISPOSAL_MOMENTUM_TRANSFER := 0.55

# You plant to kick. Fraction of target speed available mid-action.
const ACTION_SPEED_SCALE := 0.4

# Action timing, indexed by Action. CONTACT is when the ball actually
# leaves — partway through the swing, not at either end of it.
#
# These are constants only because the placeholder animations are
# generated from them (see placeholder_animations.gd). When real Mixamo
# clips arrive, contact becomes a call track on the animation and the
# CONTACT row is deleted; nothing else changes.
const ACTION_DURATION := [0.0, 0.78, 0.45, 0.50]
const ACTION_CONTACT := [0.0, 0.42, 0.20, 0.22]

# AFL rule: a player running with the ball must bounce or touch it to
# ground every 15 metres. Carried over unchanged from Prototype 1's
# BOUNCE_INTERVAL = 15.0, which was already the real rule.
const BOUNCE_INTERVAL := 15.0          # metres of carry between bounces

# An actual arm's reach. P1's LOOSE_BALL_GATHER_RADIUS was 4.0 units — a
# positional abstraction for "close enough", not a reach.
const GATHER_RADIUS := 0.85            # m
const GATHER_MAX_BALL_SPEED := 14.0    # m/s above which the ball is going too fast to gather
const GATHER_COOLDOWN := 0.45          # s after disposal before you can regather your own kick
const RELEASE_GRACE := 0.25            # s the disposed ball ignores its own kicker


# ── Camera rig ───────────────────────────────────────────────────────
# Same focus-follow concept as Prototype 1's HeroCamera, as a real 3D
# spring arm. P1's MAIN_CAM_BACK/HEIGHT were 50/30 logical units on a
# 166-unit field — a very high, very distant diorama view. A broadcast
# third-person rig sits far closer to the player.
const CAM_DISTANCE := 7.5              # m behind the focus point
const CAM_FOCUS_HEIGHT := 1.35         # m up the player's body that the rig frames
const CAM_PITCH_DEFAULT := -14.0       # deg
const CAM_PITCH_MIN := -55.0
const CAM_PITCH_MAX := 22.0
const CAM_YAW_SPEED := 180.0           # deg/s at full right-stick deflection
const CAM_PITCH_SPEED := 110.0         # deg/s
const CAM_MOUSE_SENSITIVITY := 0.14    # deg per pixel of mouse motion

const CAM_FOLLOW_RATE := 9.0           # exponential smoothing rate for the focus point
const CAM_ROTATE_RATE := 12.0          # ditto for yaw/pitch
const CAM_LOOKAHEAD_TIME := 0.45       # s of the target's velocity to lead by
const CAM_LOOKAHEAD_MAX := 3.5         # m cap on that lead

const CAM_FOV_BASE := 68.0
const CAM_FOV_SPRINT_GAIN := 10.0      # deg added at SPRINT_SPEED — speed you can feel
const CAM_FOV_RATE := 5.0
const CAM_PUNCH_KICK := -6.0           # deg of transient tighten on a kick (§6)
const CAM_PUNCH_DECAY := 3.5

# The ball pulls the focus point toward itself once it is properly in
# flight, so you watch your own kick land instead of watching your
# player's back. This is §6's "follows the ball/play focus point" in its
# simplest honest form.
const CAM_BALL_FOCUS_MAX := 0.55       # max weight the ball takes of the focus point
const CAM_BALL_FOCUS_MIN_HEIGHT := 1.6 # m, ball must be above this to pull focus
const CAM_BALL_FOCUS_RATE := 3.0
const CAM_MAX_FRAMING_DISTANCE := 45.0 # m, beyond which the ball stops pulling harder


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

const RUMBLE_KICK := Vector3(0.35, 0.55, 0.18)     # (weak, strong, duration)
const RUMBLE_GATHER := Vector3(0.12, 0.0, 0.08)


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


static func action_duration(action: Action) -> float:
	return float(ACTION_DURATION[clampi(int(action), 0, ACTION_DURATION.size() - 1)])


static func action_contact_time(action: Action) -> float:
	return float(ACTION_CONTACT[clampi(int(action), 0, ACTION_CONTACT.size() - 1)])
