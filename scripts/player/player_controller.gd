class_name PlayerController
extends CharacterBody3D

## Velocity-based movement with real momentum (design doc §5).
##
## Prototype 1 moved a player by adding `speed * dt` to a position every
## frame — instant starts, instant stops, instant reversals. Everything
## here exists to take that away:
##
##   - speed changes through an acceleration, and braking is faster than
##     accelerating, so a body has to be got going and got stopped
##   - the turn rate falls off as speed rises, so a sprint commits you to
##     an arc while a standstill lets you pivot
##   - running against your own momentum drives target speed toward zero,
##     which brakes you, which raises your turn rate, which swings you
##     round and lets you go again
##
## That last one is the whole plant-and-pivot move, and it is not a
## special case anywhere in this file — it falls out of the first two
## rules being coupled. Which is the point: weight should be a property
## of the simulation, not an animation played on top of a teleport.
##
## The rig's facing turns faster than the velocity heading does, so the
## body leads and the velocity lags. That lag is the strafe axis the
## blend space reads (see player_animation.gd) — the animation system is
## being driven by the physical state, not running alongside it.

signal action_started(action: Tuning.Action)
signal ball_gathered(ball: Ball)
signal ball_disposed(action: Tuning.Action)
signal mark_caught(tier: Tuning.Action, legal_mark: bool)
signal mark_missed(tier: Tuning.Action)

## Fired from _get_tackled only when the tackled player had already had
## Tuning.PRIOR_OPPORTUNITY_GRACE seconds of personal possession — a real
## holding-the-ball ruling (RULES_REFERENCE.md §4), as opposed to the
## neutral case (tackled inside the grace window), which stays silent since
## nothing about it differs from a plain tackle today. Nothing consumes
## this yet: awarding the actual free kick needs a set-shot/free-kick
## apparatus this project doesn't have — the ruling is decided correctly,
## the consequence is the next piece.
signal holding_the_ball_called(tackler: PlayerController)

## Fired from _get_tackled only in the *neutral* case — tackled inside
## Tuning.PRIOR_OPPORTUNITY_GRACE, the mirror image of
## holding_the_ball_called above (RULES_REFERENCE.md §4: "tackled inside
## the grace window is neutral, a ball-up"). Whoever owns match flow
## resolves the actual ball-up through the shared ruck contest — see
## FullGame._begin_ruck_contest.
signal field_ball_up_called(tackler: PlayerController, tackled: PlayerController)

## Fired from _track_carry_distance the instant a carry passes
## Tuning.BOUNCE_INTERVAL (15 m — the real AFL run-without-bouncing limit,
## RULES_REFERENCE.md §1) with no bounce. Latched so it fires once per
## overrun, not every frame past 15 m; the latch clears on the next
## gather / bounce / disposal / drop. FullGame turns it into a free kick to
## the nearest opponent at the spot — the same restart shape
## holding_the_ball_called already uses. An AIBrain carrier bounces well
## before this (Tuning.AI_BOUNCE_AT_FRACTION), so in practice it only ever
## catches a human who didn't bounce.
signal run_too_far_called(carrier: PlayerController)

## Fired when a ruck contest's Hit-Out resolves — see _resolve_hit_out.
## `connected` is false on a clean miss (nothing about the ball changes).
signal hit_out_resolved(player: PlayerController, connected: bool)

## Fired on the TACKLER the frame a tackle connects and holds (a broken one
## doesn't count) — `is_slide` true for a standing/dive-in Slide
## (_try_tackle), false for a Lunge (_try_lunge_tackle).
## The tackled-side outcome is already covered by holding_the_ball_called /
## field_ball_up_called; this exists so something watching the tackler can tell
## *which* commitment landed (the tackling tutorial keys its per-step success on
## it). Career's per-player TACKLES stat counts it too (FullGame) — only an
## on-the-ball tackle emits it, so a tackle off the ball never counts.
signal tackle_committed(is_slide: bool)

## Fired on the bumper when a Bump connects (design brief priority 7).
## `clean` reflects timing (Tuning.BUMP_APPROACH_DOT_MIN), not legality —
## whether contact was *dangerous* enough to warrant a free kick is a real
## AFL rule this project has no numbers for yet (RULES_REFERENCE.md has no
## distance/angle/force/timing threshold for "high contact"), so nothing
## here judges that. This signal exists so a future pass that *does* have
## real numbers has an event to hook rather than needing to re-derive one.
signal bump_landed(bumper: PlayerController, carrier: PlayerController, clean: bool)

## Fired on the OFFENDER when a human's tackle or bump lands on an
## opponent it isn't allowed to touch (playtest): one without the ball (a
## tackle off the ball, a late hit) — a free kick to them where they stand
## — or one holding the ball under protection (a mark or free kick) — a
## 50 m penalty (`fifty`). Nothing physical happens to `fouled`: no spill,
## no ragdoll; whoever owns match flow (FullGame._on_infringed) stops play
## and awards it. AI never tackles off the ball, so only a human can
## concede one.
signal infringed(fouled: PlayerController, fifty: bool)

@export var team: Tuning.Team = Tuning.Team.HOME

## Identity only, not gameplay — Career mode's per-player goal/disposal
## stats (MatchState's player-keyed dictionaries, see match_state.gd) are
## keyed by roster_id and shown under roster_name. The id is unique across
## both teams ("H<roster id>" / "A<index>"); the name isn't. Both empty for
## every non-Career spawn (Kick-to-Kick, a quick-play Full Game), so
## nothing outside Career ever reads or writes a per-player stat row. Set
## by full_game.gd's _spawn_team() from CareerProfile.roster/the generated
## opponent roster, only when GameState.career_active is true.
var roster_name := ""
var roster_id := ""

## Uniform multiplier over WALK/JOG/SPRINT_SPEED — 1.0 leaves Full Game
## and the sandbox exactly as tuned. The character screen's SPEED stat
## (CharacterProfile.speed_scale()) is the only thing that sets this to
## anything else, on whichever player it hands off to.
var speed_scale := 1.0

## Multiplier on KICK_MIN/MAX_SPEED — see _kick_parameters(). 1.0 leaves
## Full Game/the sandbox exactly as tuned, same as speed_scale above.
var kick_power_scale := 1.0

## Unitless nimbleness multiplier (1.0 == tuned baseline). Shortens the
## backpedal turn-out (Tuning.backpedal_turnout_duration) and nudges the
## plant-and-pivot / facing turn rates (Tuning.agility_turn_rate_mult).
## CharacterProfile.agility_scale() is the only thing that sets this to
## anything other than 1.0, on whichever player(s) it's applied to.
var agility_scale := 1.0

## 0..1, where 1.0 is pinpoint and 0.0 is KICK_ACCURACY_MAX_SPREAD_DEG of
## random aim error — see _dispose()'s KICK branch, the only place this
## is actually rolled.
var kick_accuracy := 1.0

## Body mass, kg. Not the CharacterBody3D's (kinematic bodies have none) —
## it's what a tackle weighs the two players by (TackleBalance's mass
## ratio, the push's size) and what this player's ragdoll is built at.
## Career sets it from the roster's weight (FullGame._apply_career_rosters);
## everywhere else every player is the same Tuning.PLAYER_DEFAULT_MASS_KG.
var body_mass := Tuning.PLAYER_DEFAULT_MASS_KG

## Set by whatever owns the view — movement is camera-relative, as every
## third-person game's is. Left null the player still works, just in
## world axes, which keeps this node testable headless.
var camera: Node3D = null

## The rig `camera` belongs to, set alongside it by the same owner — only
## so _current_look_yaw() can tell FULL_SIDE apart from CHASE (see there).
## Left null wherever `camera` is too (sandbox/kick_to_kick never switch
## modes, so this is always CHASE there and nothing reads it).
var camera_rig: BroadcastCamera = null

@onready var _animation: PlayerAnimation = $PlayerAnimation
@onready var _carry_point: Marker3D = $CarryPoint
@onready var _boot_point: Marker3D = $BootPoint
@onready var _gather_zone: Area3D = $GatherZone
@onready var _kick_trajectory: KickTrajectory = $KickTrajectory

## Defaults to a HumanBrain so a bare instance (the milestone-1 sandbox,
## scenes/main.tscn) behaves exactly as it always did. Full Game assigns
## AIBrain to everyone but the one human-controlled player.
var _brain: PlayerBrain = HumanBrain.new()

## Seconds left unable to move or act after being tackled. Zero the rest
## of the time.
var _stun_timer := 0.0

## Playtest feedback on the bump rework specifically (tackle's own knockdown
## feel was never flagged, so this is scoped to bump's two knockdown call
## sites, not the shared _knockdown() helper itself): an all-horizontal
## slide read as floaty. While positive, _physics_process's floor-snap bite
## is suspended so a small upward hop (BUMP_KNOCKDOWN_HOP_SPEED) can
## actually arc under real gravity instead of being cancelled the very next
## frame — see _resolve_bump_contact()/_resolve_bump_miss().
var _knockdown_hop_timer := 0.0

## Seconds left immune to _try_tackle() after taking a legal mark — the
## stand-the-mark protection window (Tuning.MARK_HOLD_DURATION). Cleared
## early the instant this player disposes of the ball; also doubles as the
## protection mechanism a future kick-in's goal square will use.
var _protected_timer := 0.0

## Seconds left frozen in place — the *other* half of stand-the-mark
## (RULES_REFERENCE.md's MARK_STAND_MIN_DISTANCE entry): a legal mark
## doesn't just protect the taker from being tackled, it obliges the
## nearest opponent onto the mark (see _frozen_anchor) — or, for the wider
## retreat crowd, to stand where they are — until the mark-taker plays on.
## Purely a movement freeze (see _update_locomotion) — unlike _stun_timer,
## a frozen player can still act, they just can't reposition. Set on the
## OPPONENT by _apply_stand_the_mark(), not on the mark-taker themselves.
var _frozen_timer := 0.0

## World-space spot the frozen player is being held on, or Vector3.INF for
## "just hold wherever you already are". Only the one direct opponent named
## by _apply_stand_the_mark() gets a real spot — the mark itself — so the
## man on the mark ends up standing *on the mark* instead of frozen
## wherever they happened to be when it was taken. The 10m retreat crowd
## (_apply_retreat_freeze) passes no spot and just stops where they are.
## Cleared alongside _frozen_timer.
var _frozen_anchor := Vector3.INF

## Every opponent this player is currently obliging to hold position, for
## whatever reason — the one direct opponent standing the mark exactly
## (_apply_stand_the_mark) plus anyone else caught inside the 10m retreat
## radius (grant_protection's own _apply_retreat_freeze) — kept so a
## disposal can release all of them early (real AFL: everyone's free to
## move the instant the kick is taken or the mark-taker plays on, not just
## once the full 5s window lapses). Cleared alongside _protected_timer in
## _dispose()/drop_ball().
var _frozen_opponents: Array[PlayerController] = []

## 0.0 = no jump pending. Set for exactly one physics frame by
## _begin_aggressive_mark()/_begin_hit_out() (to Tuning.MARK_AGGRESSIVE_
## JUMP_SPEED) or _complete_mark() on a Safe catch (to Tuning.MARK_SAFE_
## HOP_SPEED), consumed by the gravity block in _physics_process so the
## impulse lands after the floor-snap/gravity assignment rather than being
## immediately overwritten by it. A float rather than the bool this used to
## be, so the same hand-off serves both a real committed leap and a much
## smaller reactive hop on catch.
var _pending_jump_speed := 0.0

## Held-stance flag for a Safe Mark, exactly parallel to _charging for a
## kick — true only while the ball is airborne, in reach range hasn't
## resolved yet, and the brain still wants it. Read by _update_locomotion
## for MARK_SAFE_SPEED_SCALE, same mechanism KICK_STANCE_SPEED_SCALE uses.
var _mark_readying := false

## Seconds left before another Punch/Spoil attempt can connect — a tap
## action with no windup, so this is the only thing stopping it being held
## down for a continuous battering (see _try_spoil).
var _spoil_cooldown := 0.0

## True while nominated into a live ruck contest (centre bounce / field
## ball-up / boundary throw-in — see FullGame._begin_ruck_contest and
## set_ruck_contestant below) — the only context RB reads as a Hit-Out.
## Self-expires via _ruck_contest_timer so it can never linger past the
## one contest it was armed for.
var _is_ruck_contestant := false
var _ruck_contest_timer := 0.0

## An RB press latched for this contest but not yet jumped on — see
## _update_ruck_contest. Cleared with the contestant flag.
var _hit_out_armed := false

## Seconds left before another Bump attempt can commit — a real hit-stick
## commitment, not spammable (see _update_bump).
var _bump_cooldown := 0.0

## Bump's hit-stick dash (see _update_bump/_try_bump_contact): while
## _bump_dash_active is true, _update_locomotion overrides normal
## input-driven movement with a committed dash toward _bump_dash_direction
## — the same "external velocity owns the body for a window" shape Slide's
## dive-in (_slide_dive_timer, just below) already uses. Direction comes
## straight from the flick gesture, not a locked target — a bump never
## picks a target ahead of time, it swings at a spot and physics decides
## whether anyone was there. _bump_dash_active outlives the last frame
## _bump_dash_timer is positive by exactly one frame — that final frame is
## when _try_bump_contact() (running after move_and_slide, like every
## other contest resolution in this file) gets to check "did the dash's
## own clock run out with nobody found," which is the whiff case.
var _bump_dash_timer := 0.0
var _bump_dash_direction := Vector3.FORWARD
var _bump_dash_active := false

## Seconds this dash has spent driving in on a carrier it reached, before
## the bodies meet (Tuning.BUMP_IMPACT_DISTANCE) — see _try_bump_contact.
var _bump_close_in_time := 0.0

## Seconds left before another Smother attempt can launch — see
## _update_smother.
var _smother_dive_cooldown := 0.0

## Smother's own committed dive (see _update_smother/_try_smother_contact):
## while _smother_dive_timer is positive, _update_locomotion overrides
## normal movement with a dive toward _smother_dive_direction, the same
## "external velocity owns the body for a window" shape every other
## committed movement in this file uses — except this one re-aims every
## frame at _smother_dive_target's live position rather than a direction
## frozen at launch, since smother (unlike Bump) already has a specific,
## known target the instant it's triggered.
var _smother_dive_timer := 0.0
var _smother_dive_direction := Vector3.FORWARD
var _smother_dive_target: PlayerController = null

## Slide tackle's dive-in (see _update_slide_dive): while _slide_dive_timer
## is positive, _update_locomotion overrides normal input-driven movement
## with a committed dash toward _slide_dive_direction, same "external
## velocity owns the body for a window" shape _knockback already uses below.
var _slide_dive_timer := 0.0
var _slide_dive_cooldown := 0.0
var _slide_dive_direction := Vector3.FORWARD
var _slide_was_pressed := false
## The tackle button's rising edge this frame (set in _update_slide_dive) —
## only a fresh press can concede a free kick off the ball, never B held
## down while running past someone on the way to the carrier.
var _slide_just_pressed := false

## Seconds left before another Lunge tackle attempt can fire — see
## _try_lunge_tackle. Unlike a missed Slide (which sets _stun_timer, a real
## off-balance penalty), a missed Lunge only pays this short cooldown: it
## never leaves the ground, so nothing else about the player is affected.
var _lunge_tap_cooldown := 0.0

## A Lunge pressed at a carrier just out of reach (Tuning.TACKLE_LUNGE_REACH):
## while _lunge_dash_timer is positive the body drives at the live target
## at _lunge_dash_speed, the same "committed movement owns the body" shape
## as Smother's dive, and _try_lunge_tackle lands it the frame they're in
## TACKLE_RADIUS or whiffs it when the clock runs out.
var _lunge_dash_timer := 0.0
var _lunge_dash_speed := 0.0
var _lunge_dash_target: PlayerController = null

## Residual horizontal knockback velocity from being bumped, decaying via
## BRAKING each frame — see _update_locomotion's early branch and
## receive_bump(). While nonzero this overrides normal input-driven
## movement entirely: the hit is what's moving the body, not the stick.
var _knockback := Vector3.ZERO

## Rulebook §6's "hold both players physically together": while
## _tackle_hold_timer is positive these two bodies are locked to each
## other, the same "something external owns the body for a window" shape
## _knockback and the various dives already use. Only the tackler drives
## the pair (_tackle_hold_is_tackler) — the target simply stands — so the
## two can never fight each other over the same offset. Both face each
## other for the duration. See _begin_tackle_hold/_end_tackle_hold.
var _tackle_hold_timer := 0.0
var _tackle_hold_partner: PlayerController = null
var _tackle_hold_is_tackler := false

## This player's active ragdoll (Tuning's "Active ragdoll tackles"), made
## on their first ragdoll tackle and kept (parked) after — see
## _begin_ragdoll. While it's active the ragdoll owns the body: the player
## can't act, and _update_locomotion just follows the hips.
var _ragdoll: PlayerRagdoll = null

## The other player in the tackle that ragdolled this one. Their capsules
## pass through each other until this ragdoll ends: each capsule follows its
## own body's hips, and a tackler falling on through the carrier otherwise
## jammed on the carrier's capsule — far enough behind its own body, on a
## long fall, to trip PlayerRagdoll's teleport check and snap upright.
var _ragdoll_partner: PlayerController = null

## A held Lunge's arms round the carrier while both fall (TackleWrap), on
## the tackler; null otherwise.
var _tackle_wrap: TackleWrap = null

## The last tackle this player made, for headless checks and readouts:
## TackleBalance.resolve's read of it (empty when it never landed) plus
## "slide", "held" and, for a whiff, "missed".
var last_tackle := {}

## Seconds this player personally has held the ball since their own last
## gather/mark. Distinct from MatchState.possession_seconds(), which
## tracks the whole TEAM's unbroken hold and does not reset on a same-team
## handball — holding-the-ball's "prior opportunity" (RULES_REFERENCE.md
## §4) is about this individual player's own chance to dispose, so
## _get_tackled reads this instead.
var _possession_held_seconds := 0.0

## Unit XZ direction the body is actually travelling. Kept as state
## rather than re-derived from velocity every frame so it survives a
## complete stop — you keep facing where you were going.
var _heading := Vector3.FORWARD
var _wish_dir := Vector3.ZERO
var _speed := 0.0
var _facing_yaw := 0.0

## True while reading the play backward — see the Backpedal section of
## Tuning. Feet answer the stick directly (heading = wish_dir, no turn-rate
## sweep); facing is deliberately left alone by _update_facing while this
## is true, which is the whole mechanic: eyes stay on the play, only the
## feet move.
var _backpedaling := false

## How long the current backpedal has been running, and whether one just
## timed out. Facing is frozen while backpedalling, so nothing about
## holding the stick behind you can ever bring facing_alignment back up to
## BACKPEDAL_EXIT_DOT on its own — without a cap the shuffle is a state you
## can be parked in indefinitely. The lockout is what stops the timeout
## from immediately re-entering on the very next frame, when the body has
## only turned a few degrees and is still well inside BACKPEDAL_ENTER_DOT;
## it lifts as soon as facing has caught up (or the stick is released).
## See Tuning.BACKPEDAL_MAX_DURATION and _end_backpedal().
var _backpedal_seconds := 0.0
var _backpedal_locked_out := false

## Walking back from a legal mark (Tuning.MARK_RETREAT_DISTANCE) — metres
## still to cover, and which way "back" is. While this is running the body
## is driven by it rather than by the stick or the AI, and the kick is
## blocked: the player has to get off the mark before they can go at goal
## or play on. _heading is snapped to the attacking goal the instant the
## retreat begins (see _begin_mark_retreat), so _update_facing turns the
## body to face goal while the feet carry it backwards — matches the real
## kicker's look, not whichever way they happened to be facing on the take.
var _mark_retreat_remaining := 0.0
var _mark_retreat_dir := Vector3.ZERO

## True from the instant goal_set_shot is pressed (in range, still under
## mark/free-kick protection) until the kick actually fires or is lost —
## keeps _update_charge's kick-stance branch alive even though nothing is
## being held down, the way wants_kick() being true every frame normally
## would. See _update_charge.
var _goal_set_shot_locked := false

## The set shot's run-up (Tuning.SET_SHOT_RUN_UP_*): metres still to walk in
## along the aim before the kick begins, and which way. Like the mark
## walk-back it owns the body while it runs; the kick charge and aim are
## the ones the stance had when the kick button went. _set_shot_kick is the
## kick at its end, which flies without the run-up's momentum (_dispose).
var _set_shot_run_up_remaining := 0.0
var _set_shot_run_up_dir := Vector3.ZERO
var _set_shot_kick := false

## Seconds left of the acceleration spike that fires the instant a
## backpedal resolves into a real direction (Tuning.TURN_BURST_*) — see
## _update_locomotion.
var _turn_burst_timer := 0.0

var _carried_ball: Ball = null
var _gather_cooldown := 0.0
var _carry_distance := 0.0
## Whether run_too_far_called has already fired for the current unbroken
## carry — so FullGame gets one call, not one per frame past 15 m. Reset
## wherever _carry_distance is (see _track_carry_distance / _complete_gather
## / drop_ball).
var _run_too_far_latched := false

var _action: Tuning.Action = Tuning.Action.NONE
var _action_elapsed := 0.0
var _action_fired := false
var _kick_charge := 0.0
var _charging := false

## World-space yaw the kick is currently aimed along, decoupled from body
## facing (design brief's CONTROLS section: "aim is fully decoupled from
## movement/facing"). Snapped to _facing_yaw when stance begins, then
## nudged by the right stick/mouse for a human for as long as stance
## holds — see _update_kick_aim(). Frozen the instant the swing begins,
## same as _kick_charge, so waggling the stick after committing can't
## retroactively change where an already-struck kick goes.
var _kick_aim_yaw := 0.0

## Where a HANDBALL launches, captured once in _begin() at the moment the
## button is pressed — not read fresh in _dispose(), which fires later at
## the animation's contact time and would otherwise pick up wherever the
## stick had drifted to by then.
var _handball_aim_dir := Vector3.FORWARD

## Where a HIT_OUT palms the ball, captured in _begin() on the RB press the
## same way _handball_aim_dir is — a ruck tap is aimed with Left stick
## ("tap direction = pass direction", user brief), not just punched
## straight ahead off the body. Falls back to body-forward if the stick is
## neutral at the instant of the press (see _resolve_hit_out).
var _hit_out_aim_dir := Vector3.ZERO

## True for exactly the one KICK currently in flight through _action, set
## when it was fired as a hip-fire (RT with no prior LT) rather than an
## aimed one — _dispose() reads this once to decide whether the extra
## hip-fire scatter applies, then clears it.
var _hip_fire_kick := false


func _ready() -> void:
	# PlayerRegistry replaces the old &"players" group as the source for
	# every proximity/contest query (see SpatialQuery, docs/MECHANICS_AUDIT.md
	# A1). Nothing reads the group any more.
	PlayerRegistry.add(self)

	_facing_yaw = rotation.y
	_heading = -global_transform.basis.z
	_heading.y = 0.0
	_heading = _heading.normalized()

	# Own the gather shape rather than editing the one in the .tscn, so
	# GATHER_RADIUS stays single-sourced in Tuning and instances of this
	# scene do not share a mutated resource. Sized to the largest reach a
	# sprinting player could ever get (GATHER_LUNGE_MAX) rather than the
	# base radius — the physics shape only has to generate candidates, the
	# real speed-scaled cutoff is an explicit distance test in
	# _try_gather(), same pattern _update_ground_pickup already uses. That
	# avoids resizing a live Area3D shape and querying its (one-physics-
	# -step-stale) overlap list in the same frame.
	var reach := SphereShape3D.new()
	reach.radius = Tuning.GATHER_RADIUS + Tuning.GATHER_LUNGE_MAX
	($GatherZone/CollisionShape3D as CollisionShape3D).shape = reach


func _exit_tree() -> void:
	PlayerRegistry.remove(self)


func set_brain(brain: PlayerBrain) -> void:
	_brain = brain


func brain() -> PlayerBrain:
	return _brain


## Every cooldown/timer field on this controller follows this same
## "subtract delta, clamp at zero" shape — shared here so they can't drift
## out of sync with each other (see _update_slide_dive, the one timer
## that used to decrement without the clamp).
func _tick_down(value: float, delta: float) -> float:
	return maxf(0.0, value - delta)


func _physics_process(delta: float) -> void:
	_brain.update(self, delta)

	_gather_cooldown = _tick_down(_gather_cooldown, delta)
	_stun_timer = _tick_down(_stun_timer, delta)
	_protected_timer = _tick_down(_protected_timer, delta)
	_frozen_timer = _tick_down(_frozen_timer, delta)
	if _frozen_timer <= 0.0 and _frozen_anchor.is_finite():
		_frozen_anchor = Vector3.INF
	_spoil_cooldown = _tick_down(_spoil_cooldown, delta)
	_bump_cooldown = _tick_down(_bump_cooldown, delta)
	_slide_dive_cooldown = _tick_down(_slide_dive_cooldown, delta)
	_lunge_tap_cooldown = _tick_down(_lunge_tap_cooldown, delta)
	_smother_dive_cooldown = _tick_down(_smother_dive_cooldown, delta)
	_possession_held_seconds = _possession_held_seconds + delta if is_carrying() else 0.0
	if _is_ruck_contestant:
		_ruck_contest_timer = maxf(0.0, _ruck_contest_timer - delta)
		if _ruck_contest_timer <= 0.0:
			_is_ruck_contestant = false
			_hit_out_armed = false

	if is_ragdolled():
		_ragdoll.step(delta)
		# Down (or about to be) for as long as physics has the body; the
		# get-up sets its own stun in on_ragdoll_getup.
		if is_ragdolled() and _ragdoll.phase() != PlayerRagdoll.Phase.GETTING_UP:
			_stun_timer = maxf(_stun_timer, 0.1)
	if _tackle_wrap != null:
		_tackle_wrap.step(delta)
		if _tackle_wrap.is_done():
			_tackle_wrap = null
	if _ragdoll_partner != null and not is_ragdolled():
		if is_instance_valid(_ragdoll_partner):
			remove_collision_exception_with(_ragdoll_partner)
		_ragdoll_partner = null

	_update_charge(delta)
	_update_marking(delta)
	_update_ruck_contest(delta)
	_update_bump(delta)
	_update_tackle_hold(delta)
	_update_slide_dive(delta)
	_update_smother(delta)
	_update_action(delta)

	if _knockdown_hop_timer > 0.0:
		# A bump knockdown's hop (BUMP_KNOCKDOWN_HOP_SPEED) is already sitting
		# in velocity.y — let it arc under real gravity instead of the
		# floor-snap bite below instantly cancelling it back to -0.5 the very
		# next frame. See _resolve_bump_contact()/_resolve_bump_miss().
		_knockdown_hop_timer = _tick_down(_knockdown_hop_timer, delta)
		velocity.y -= Tuning.GRAVITY * delta
	elif is_on_floor():
		velocity.y = -0.5   # a little bite into the floor keeps is_on_floor stable
	else:
		velocity.y -= Tuning.GRAVITY * delta
	if _pending_jump_speed > 0.0:
		# Applied after the floor-snap above, not before — is_on_floor() is
		# still true for one more frame at the instant a jump is triggered
		# (the physics server hasn't seen us leave the ground yet), so
		# setting this any earlier would just get overwritten by the -0.5
		# floor bite on the very frame that matters.
		velocity.y = _pending_jump_speed
		_pending_jump_speed = 0.0

	_update_locomotion(delta)

	var before := global_position
	move_and_slide()
	_push_rigid_bodies()
	_contain_to_field()

	_update_facing(delta)
	_track_carry_distance(before)
	_try_gather()
	_try_tackle()
	_try_lunge_tackle()
	_try_bump_contact()
	_try_smother_contact()

	# The real ground speed sets how fast the legs turn over (PlayerAnimation's
	# "Stride matching"), not just which clips blend.
	if is_ragdolled():
		_animation.drive(Vector2.ZERO, delta, 0.0)
	else:
		_animation.drive(locomotion_blend(), delta, Vector2(velocity.x, velocity.z).length())


# ── Locomotion ───────────────────────────────────────────────────────

func _update_locomotion(delta: float) -> void:
	# A ragdoll owns the body outright: while it falls the capsule just
	# follows its hips along the ground, so where the body lands is where
	# the player is; while it waits to go rigid or blends into the get-up,
	# the capsule holds still. Through velocity, like the tackle hold below,
	# so move_and_slide still keeps it out of other players and the fence.
	if is_ragdolled():
		_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		if _ragdoll.is_falling():
			var follow := (_ragdoll.hips_ground_position() - global_position) / delta
			follow.y = 0.0
			if follow.length() > Tuning.TACKLE_SLIDE_DIVE_SPEED * 2.0:
				follow = follow.normalized() * Tuning.TACKLE_SLIDE_DIVE_SPEED * 2.0
			velocity.x = follow.x
			velocity.z = follow.z
		return

	# A bump's knockback overrides normal input-driven movement entirely
	# while it's still decaying — the hit is what's moving this body right
	# now, not the stick (see receive_bump()). Applied here, before
	# anything reads velocity for _speed/_heading, so the knocked-back
	# motion is what the rest of this frame (animation blend included)
	# actually sees.
	if _knockback.length_squared() > 0.0001:
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		_knockback = _knockback.move_toward(Vector3.ZERO, Tuning.BRAKING * delta)
		var horizontal_kb := Vector3(velocity.x, 0.0, velocity.z)
		_speed = horizontal_kb.length()
		if _speed > Tuning.PIVOT_SPEED_THRESHOLD:
			_heading = horizontal_kb / _speed
		return

	# A tackle hold owns both bodies the same way — the tackler closes and
	# stays welded to the target, the target simply can't go anywhere.
	# Driven through velocity rather than by writing global_position so it
	# still goes through move_and_slide's own collision response on the
	# very next line of _physics_process, and neither body can be shoved
	# into geometry by the lock. See _begin_tackle_hold.
	if _tackle_hold_timer > 0.0 and is_instance_valid(_tackle_hold_partner):
		var to_partner := _tackle_hold_partner.global_position - global_position
		to_partner.y = 0.0
		if to_partner.length_squared() > 0.000001:
			_heading = to_partner.normalized()
		_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		if _tackle_hold_is_tackler:
			# Where the tackler wants to be: TACKLE_HOLD_DISTANCE back
			# along the line to the target, closed within this one frame.
			var hold_spot := _tackle_hold_partner.global_position - _heading * Tuning.TACKLE_HOLD_DISTANCE
			var correction := hold_spot - global_position
			correction.y = 0.0
			# Closed in one frame, but never faster than the dive that got
			# here could have travelled — if the target is ever moved a
			# long way while the lock is live (it shouldn't be; see
			# _end_tackle_hold's callers) this drags rather than teleports.
			var closing := correction / delta
			velocity.x = closing.x
			velocity.z = closing.z
			var closing_speed := Vector2(closing.x, closing.z).length()
			if closing_speed > Tuning.TACKLE_SLIDE_DIVE_SPEED:
				var scale := Tuning.TACKLE_SLIDE_DIVE_SPEED / closing_speed
				velocity.x *= scale
				velocity.z *= scale
		return

	# Walking back off a legal mark (Tuning.MARK_RETREAT_DISTANCE) owns the
	# body the same way. _heading is snapped to the attacking goal once, in
	# _begin_mark_retreat() — not touched here every frame — so the body
	# faces goal while the feet carry it backwards, locomotion_blend()
	# picking the backward run clip off the heading/velocity mismatch
	# rather than off facing ever pointing the wrong way. Distance is
	# retired at the intended rate rather than by measured displacement,
	# so being blocked by the fence or another body can't leave the
	# retreat running forever.
	if _mark_retreat_remaining > 0.0:
		_mark_retreat_remaining = maxf(0.0,
			_mark_retreat_remaining - Tuning.MARK_RETREAT_SPEED * delta)
		_speed = Tuning.MARK_RETREAT_SPEED
		velocity.x = _mark_retreat_dir.x * _speed
		velocity.z = _mark_retreat_dir.z * _speed
		if _mark_retreat_remaining <= 0.0:
			# The retreat's own velocity is still sitting in `velocity` the
			# instant it ends — left alone, next frame's generic heading
			# read a few lines down ("if _speed > PIVOT_SPEED_THRESHOLD:
			# _heading = horizontal/_speed") would snap _heading straight
			# back to this frame's backward retreat direction, undoing the
			# goal-facing _begin_mark_retreat() just set and spinning the
			# body 180° the instant it's allowed to move again. Zeroing it
			# here, on the exact frame the walk-back finishes, is what
			# actually makes the goal-facing stick afterward.
			velocity.x = 0.0
			velocity.z = 0.0
			_speed = 0.0
		return

	# A set shot's run-up owns the body the same way: a walk into a jog
	# along the aim, and the kick the moment it's covered the distance.
	if _set_shot_run_up_remaining > 0.0:
		var progress := 1.0 - _set_shot_run_up_remaining / Tuning.SET_SHOT_RUN_UP_DISTANCE
		_speed = lerpf(Tuning.SET_SHOT_RUN_UP_SPEED.x, Tuning.SET_SHOT_RUN_UP_SPEED.y, progress)
		_set_shot_run_up_remaining = maxf(0.0, _set_shot_run_up_remaining - _speed * delta)
		_heading = _set_shot_run_up_dir
		velocity.x = _heading.x * _speed
		velocity.z = _heading.z * _speed
		if _set_shot_run_up_remaining <= 0.0:
			_cancel_goal_set_shot()
			_set_shot_kick = true
			_begin(Tuning.Action.KICK)
		return

	# Slide's dive-in owns the body the same way knockback does above, just
	# driving forward at a fixed speed instead of decaying — a committed
	# dash, not a bounce being absorbed. See _update_slide_dive.
	if _slide_dive_timer > 0.0:
		_heading = _slide_dive_direction
		_speed = Tuning.TACKLE_SLIDE_DIVE_SPEED
		velocity.x = _heading.x * _speed
		velocity.z = _heading.z * _speed
		return

	# Bump's hit-stick dash owns the body the same way Slide's dive-in does
	# just above — a committed lunge toward _bump_dash_direction, not the
	# stick. See _update_bump/_try_bump_contact.
	if _bump_dash_timer > 0.0:
		_heading = _bump_dash_direction
		_speed = Tuning.BUMP_DASH_SPEED
		velocity.x = _heading.x * _speed
		velocity.z = _heading.z * _speed
		return

	# Smother's own committed dive owns the body the same way — a lunge
	# toward _smother_dive_direction, re-aimed at the live target every
	# frame in _update_smother rather than frozen at launch. See
	# _update_smother/_try_smother_contact.
	if _smother_dive_timer > 0.0:
		_heading = _smother_dive_direction
		_speed = Tuning.SMOTHER_DIVE_SPEED
		velocity.x = _heading.x * _speed
		velocity.z = _heading.z * _speed
		return

	# A Lunge's dash the same way, re-aimed at the carrier every frame — see
	# _try_lunge_tackle.
	if _lunge_dash_timer > 0.0 and is_instance_valid(_lunge_dash_target):
		var to_target := _lunge_dash_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			_heading = to_target.normalized()
		_speed = _lunge_dash_speed
		velocity.x = _heading.x * _speed
		velocity.z = _heading.z * _speed
		return

	# Stand-the-mark: this player has been obliged to hold their ground by
	# an opponent's legal mark (see _apply_stand_the_mark). Input is simply
	# ignored for movement purposes — facing/actions are untouched, only
	# repositioning is blocked, same as the real rule.
	if _frozen_timer > 0.0:
		# The man on the mark stands *on the mark*, not wherever they were
		# when it was taken. While still short of it, jog there under real
		# movement — a capped velocity, so the body collides and the run
		# clip plays — rather than being slid across the ground. Once within
		# MARK_STAND_ARRIVE_RADIUS, snap the last few centimetres and hold
		# exactly. The 10m retreat crowd has no anchor and just stops where
		# they are, so all of this is skipped for them.
		if _frozen_anchor.is_finite():
			var to_mark := Vector3(_frozen_anchor.x - global_position.x, 0.0,
				_frozen_anchor.z - global_position.z)
			if to_mark.length() > Tuning.MARK_STAND_ARRIVE_RADIUS:
				_heading = to_mark.normalized()
				_speed = Tuning.MARK_STAND_JOG_SPEED
				velocity.x = _heading.x * _speed
				velocity.z = _heading.z * _speed
				return
			global_position = Vector3(_frozen_anchor.x, global_position.y, _frozen_anchor.z)
		_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var wish := _brain.wish_direction(self)
	var gait := 0.0 if _stun_timer > 0.0 else _brain.gait()

	# move_and_slide()'s own collision response can leave `velocity` with a
	# sub-millimetre horizontal residue even for a player standing dead
	# still on flat ground (the floor-snap "bite" below re-triggers a
	# resting contact every physics frame, and each contact's slide
	# resolution can nudge velocity by a hair). That residue is otherwise
	# read straight into _speed/_heading, which locomotion_blend() then
	# reports to the AnimationTree as genuine motion — a standing player
	# would visibly twitch toward whatever clip that phantom direction
	# blends in. Snapping it to exact zero below the threshold nothing
	# gameplay-relevant ever needs kills the feedback loop at its source,
	# for every player this runs on, not just one screen's preview.
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length_squared() < Tuning.LOCOMOTION_VELOCITY_DEADZONE ** 2:
		horizontal = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
	_speed = horizontal.length()
	if _speed > Tuning.PIVOT_SPEED_THRESHOLD:
		_heading = horizontal / _speed

	_turn_burst_timer = maxf(0.0, _turn_burst_timer - delta)

	var target_speed := 0.0
	if wish.length_squared() > 0.000001:
		_wish_dir = wish.normalized()

		# Backpedal gate: how far behind where the body is currently
		# *facing* (not travelling) the new input is. Hysteresis between
		# ENTER/EXIT so a diagonal push near the threshold doesn't flicker
		# in and out every frame.
		var facing_alignment := _yaw_direction(_facing_yaw).dot(_wish_dir)
		if _backpedaling:
			_backpedal_seconds += delta
			if _backpedal_seconds >= Tuning.backpedal_turnout_duration(agility_scale):
				# Held it long enough that this stopped being a defender
				# reading the play and became a request to go that way.
				# Dropping out here hands this frame to the normal branch
				# below, which turns the body toward _heading (already the
				# stick direction, tracked every frame of the shuffle) at
				# the usual turn rate — so it reads as planting and running
				# out of the backpedal, not as a snap. No turn burst: that
				# belongs to the EXIT_DOT case, where facing has already
				# come around and there is only the drive-off left.
				_end_backpedal(true)
		if facing_alignment <= Tuning.BACKPEDAL_ENTER_DOT \
				and _speed <= Tuning.JOG_SPEED + Tuning.BACKPEDAL_ENTRY_SPEED_MARGIN \
				and not _backpedal_locked_out:
			_backpedaling = true
		elif facing_alignment >= Tuning.BACKPEDAL_EXIT_DOT:
			# Facing has caught up with the stick, whether it got here by
			# the player swinging it around or by the body turning after a
			# timeout — either way there is nothing left to lock out.
			_backpedal_locked_out = false
			if _backpedaling:
				# _heading was tracking the *old* (backward) wish_dir every
				# frame of the backpedal, not this frame's new one — left
				# stale it would read as a full reversal against the new
				# wish_dir below (alignment -1, REVERSE_SPEED_SCALE braking,
				# exactly the plant-and-pivot's brake instead of a drive-off).
				# Snap it to the new direction now: facing is already there
				# (that is what just triggered the exit), so there is
				# nothing left to turn through, only to drive off from —
				# that drive-off is the burst.
				_heading = _wish_dir
				_turn_burst_timer = Tuning.TURN_BURST_DURATION
			_end_backpedal(false)
		# Else: inside the hysteresis band — hold whatever state we're already in.

		if _backpedaling:
			# A defensive shuffle, not a sprint commitment: feet answer the
			# stick directly every frame, capped at BACKPEDAL_SPEED
			# regardless of gait input — you cannot backpedal at a sprint
			# with any control. _update_facing() leaves facing alone while
			# this is true.
			_heading = _wish_dir
			# _stun_timer forces gait to 0 above for every other path via
			# Tuning.speed_for_gait(0) == 0; BACKPEDAL_SPEED is a flat
			# constant that never reads gait, so it needs the same guard
			# explicitly or a stunned player could still shuffle backward.
			target_speed = Tuning.BACKPEDAL_SPEED * speed_scale if _stun_timer <= 0.0 else 0.0
		else:
			# From a near standstill there is no momentum to fight, so the
			# heading just snaps to intent. Without this a player stopped
			# facing north who presses south would compute a target speed
			# of zero forever and never get moving.
			if _speed <= Tuning.PIVOT_SPEED_THRESHOLD:
				_heading = _wish_dir

			# How much of your requested speed you get, given how far off
			# your current momentum it is. Dead ahead is full, square
			# across is half, straight back is REVERSE_SPEED_SCALE — this
			# is the plant-and-pivot case, a full-speed reversal, distinct
			# from the backpedal shuffle above.
			var alignment := _heading.dot(_wish_dir)
			target_speed = Tuning.speed_for_gait(gait) * speed_scale \
				* remap(alignment, -1.0, 1.0, Tuning.REVERSE_SPEED_SCALE, 1.0)

			var speed_ratio := clampf(_speed / Tuning.SPRINT_SPEED, 0.0, 1.0)
			var turn_rate := deg_to_rad(
				lerpf(Tuning.TURN_RATE_STANDING, Tuning.TURN_RATE_SPRINT, speed_ratio)) \
				* Tuning.agility_turn_rate_mult(agility_scale)
			var to_turn := _heading.signed_angle_to(_wish_dir, Vector3.UP)
			var step := clampf(to_turn, -turn_rate * delta, turn_rate * delta)
			_heading = _heading.rotated(Vector3.UP, step).normalized()
	else:
		_wish_dir = Vector3.ZERO
		_end_backpedal(false)

	# Planting to kick or handball costs you your legs for a moment; the
	# kick stance ahead of that (LT held, still aiming/repositioning) costs
	# less, same relationship as ADS-walk vs. firing in a shooter. Each mark
	# tier costs its own amount — see Tuning.action_speed_scale — and
	# readying a Safe Mark (held, not yet resolved) costs the same as the
	# mark itself will, so there's no free lunch in holding it early.
	if _action != Tuning.Action.NONE:
		target_speed *= Tuning.action_speed_scale(_action)
	elif _charging:
		target_speed *= Tuning.KICK_STANCE_SPEED_SCALE
	elif _mark_readying:
		target_speed *= Tuning.MARK_SAFE_SPEED_SCALE

	var accel: float
	if _backpedaling:
		accel = Tuning.BACKPEDAL_ACCELERATION
	elif not is_on_floor():
		accel = Tuning.AIR_ACCELERATION
	else:
		accel = Tuning.ACCELERATION if target_speed > _speed else Tuning.BRAKING
	if _turn_burst_timer > 0.0 and target_speed > _speed:
		accel *= Tuning.TURN_BURST_ACCEL_MULT
	_speed = move_toward(_speed, target_speed, accel * delta)

	velocity.x = _heading.x * _speed
	velocity.z = _heading.z * _speed


func _update_facing(delta: float) -> void:
	# The whole backpedal mechanic: the body keeps reading the play instead
	# of chasing the direction the feet are shuffling in. Facing simply
	# doesn't move — see _update_locomotion for where the feet do.
	if _backpedaling:
		return
	# A ragdoll's get-up has placed the body to match the clip's lying
	# pose; turning it now would spin the clip on the turf.
	if is_ragdolled():
		return
	var desired := _heading
	if _speed <= Tuning.PIVOT_SPEED_THRESHOLD and _wish_dir != Vector3.ZERO:
		desired = _wish_dir
	# A node's forward is -Z, so the yaw that points -Z along `desired`.
	var target_yaw := atan2(-desired.x, -desired.z)
	_facing_yaw = rotate_toward(_facing_yaw, target_yaw,
		deg_to_rad(Tuning.FACING_TURN_RATE) * Tuning.agility_turn_rate_mult(agility_scale) * delta)
	rotation.y = _facing_yaw


## (strafe, forward) in -1..1, relative to where the body is facing.
## Non-zero on the strafe axis exactly when the velocity has fallen
## behind the facing — i.e. mid-turn — which is what makes the blend
## space earn its keep even in a game where you mostly run forwards.
func locomotion_blend() -> Vector2:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	# This is called after move_and_slide() has already run for the frame
	# (see _physics_process), so `velocity` here is move_and_slide's own
	# collision-response output, not the value _update_locomotion() set —
	# a standing player's velocity can pick up sub-millimetre horizontal
	# noise from the floor-contact slide resolution even when nothing is
	# actually moving. The deadzone in _update_locomotion() guards a
	# different, earlier read of velocity and does not catch this one;
	# this is the read that actually feeds the AnimationTree, so it needs
	# its own guard, applied at the one place its output is used, rather
	# than trusting an upstream snap that runs before move_and_slide has
	# had its say.
	if horizontal.length_squared() < Tuning.LOCOMOTION_VELOCITY_DEADZONE ** 2:
		horizontal = Vector3.ZERO
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	return Vector2(
		clampf(right.dot(horizontal) / Tuning.SPRINT_SPEED, -1.0, 1.0),
		clampf(forward.dot(horizontal) / Tuning.SPRINT_SPEED, -1.0, 1.0))


## CharacterBody3D does not shove rigid bodies on its own. Running
## through a loose ball has to actually move it, or the ball reads as
## scenery.
func _push_rigid_bodies() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null:
			continue
		if body is Ball and (body as Ball).is_held:
			continue
		var push := -collision.get_normal()
		push.y = 0.0
		if push.length_squared() < 0.000001:
			continue
		var strength := Tuning.PLAYER_PUSH_FORCE * body.mass \
			* clampf(_speed / Tuning.SPRINT_SPEED, 0.15, 1.0)
		body.apply_impulse(
			push.normalized() * strength,
			collision.get_position() - body.global_position)


## Nothing about CharacterBody3D's collision stops it walking off the
## ground slab's edge into the void — the slab is finite (Field.SURROUND_
## MARGIN past the oval boundary) but there is no wall there. Keep every
## player (human or AI) inside that slab, a small buffer short of its
## true edge. AI never deliberately paths past the boundary, but a chase
## or a plant-and-pivot can carry it there anyway, so this is enforced for
## both brains in one place rather than trusted to AI target selection.
const FIELD_CONTAINMENT_BUFFER := 1.5   # m short of the slab's true edge

func _contain_to_field() -> void:
	var limit_x := Tuning.FIELD_HALF_LENGTH + Field.SURROUND_MARGIN - FIELD_CONTAINMENT_BUFFER
	var limit_z := Tuning.FIELD_HALF_WIDTH + Field.SURROUND_MARGIN - FIELD_CONTAINMENT_BUFFER
	var pos := global_position
	var nx := pos.x / limit_x
	var nz := pos.z / limit_z
	var radial := sqrt(nx * nx + nz * nz)
	if radial > 1.0:
		global_position.x = pos.x / radial
		global_position.z = pos.z / radial


# ── Possession ───────────────────────────────────────────────────────

func is_carrying() -> bool:
	return is_instance_valid(_carried_ball) and _carried_ball.is_held


func carried_ball() -> Ball:
	return _carried_ball


## True while a stand-the-mark protection window (Tuning.MARK_HOLD_DURATION)
## from a legal mark is still running — _try_tackle() skips a protected
## carrier entirely. Also the hook a future protected kick-in state reuses
## for goal-square immunity (see docs' Priority 5).
func is_protected() -> bool:
	return _protected_timer > 0.0


## Grants tackle immunity for `duration` seconds — the exact same
## _protected_timer a legal mark already uses (design brief priority 5:
## "do not build a new protection system... reuse _protected_timer/
## is_protected() directly"), for a protected kick-in's goal-square
## immunity. Already clears itself early the moment this player disposes
## (_dispose()'s existing "playing on forfeits protection" line) — a
## kick-in that plays on loses its immunity exactly like a mark that does,
## with no extra code needed here for that.
func grant_protection(duration: float) -> void:
	_protected_timer = maxf(_protected_timer, duration)
	_apply_retreat_freeze(duration)


## True while obliged to stand the mark — see _frozen_timer.
func is_standing_the_mark() -> bool:
	return _frozen_timer > 0.0


## Called on the opponent by whoever just took a legal mark
## (_apply_stand_the_mark) or granted a free-kick retreat
## (_apply_retreat_freeze) — freezes movement for `duration` seconds. When
## `hold_at` is a real point (the mark itself), the player is also slid
## onto it and held there; the default Vector3.INF means "hold your current
## ground", which is what the 10m retreat crowd gets.
func stand_the_mark(duration: float, hold_at := Vector3.INF) -> void:
	_frozen_timer = maxf(_frozen_timer, duration)
	if hold_at.is_finite():
		_frozen_anchor = hold_at


## Releases early — called on every entry in _frozen_opponents the instant
## the mark-taker/free-kick-taker disposes, so a frozen player isn't held
## past the moment the rule actually requires (real AFL: free to move once
## the kick is taken or the mark-taker plays on, not just once the full
## window lapses).
func release_stand_the_mark() -> void:
	_frozen_timer = 0.0
	_frozen_anchor = Vector3.INF


## Public entry point onto the same shared attach/possession/signal path
## every other way of gaining the ball already goes through
## (_complete_gather) — for placements that hand a player the ball outright
## rather than having them reach for it, like a protected kick-in.
func give_possession(ball: Ball) -> void:
	_complete_gather(ball)


## Let go without disposing — for resets and, later, for a tackle
## stripping the ball.
func drop_ball() -> void:
	if is_instance_valid(_carried_ball):
		_carried_ball.detach()
	_carried_ball = null
	_carry_distance = 0.0
	_run_too_far_latched = false
	_kick_charge = 0.0
	_charging = false
	_cancel_goal_set_shot()
	# Otherwise a hip-fire windup broken by a tackle before it reaches
	# _dispose() would leave this stuck true — the next kick to actually
	# fire, possibly a properly-aimed one with a fresh ball, would wrongly
	# inherit hip-fire's extra scatter.
	_hip_fire_kick = false
	# No ball, no mark to walk back off — covers disposing early, being
	# stripped, and every stoppage reset, all of which come through here.
	# Same for a set shot's run-up and the kick it was walking into.
	_end_mark_retreat()
	_set_shot_run_up_remaining = 0.0
	_set_shot_kick = false
	_gather_cooldown = Tuning.GATHER_COOLDOWN
	_protected_timer = 0.0
	_release_frozen_opponents()
	if MatchState.possession == team:
		MatchState.possession = Tuning.Team.NONE


## Metres run since the last bounce. AFL requires a bounce every 15m
## (Tuning.BOUNCE_INTERVAL, unchanged from Prototype 1's already-correct
## BOUNCE_INTERVAL). Tracked now because it shapes how running with the
## ball feels; the free kick for running too far is a match rule and
## waits for the milestone that owns match rules.
func carry_distance() -> float:
	return _carry_distance


func bounce_overdue() -> bool:
	return is_carrying() and _carry_distance >= Tuning.BOUNCE_INTERVAL


func speed() -> float:
	return _speed


## Diagnostic — see DebugHud. True while reading the play backward (see the
## Backpedal section of Tuning / _update_locomotion).
func is_backpedaling() -> bool:
	return _backpedaling


## The one place a backpedal ends, so its timer can never be left running
## into the next one. `locked_out` is true only for the
## BACKPEDAL_MAX_DURATION timeout, where the stick is still behind the
## body and re-entry has to be held off until facing catches up — every
## other exit (facing came around, stick released) is already clear.
func _end_backpedal(locked_out: bool) -> void:
	_backpedaling = false
	_backpedal_seconds = 0.0
	_backpedal_locked_out = locked_out


func kick_charge() -> float:
	return _kick_charge


func animation_state() -> StringName:
	return _animation.current_state()


func _track_carry_distance(previous_position: Vector3) -> void:
	if not is_carrying():
		_carry_distance = 0.0
		_run_too_far_latched = false
		return
	var moved := global_position - previous_position
	moved.y = 0.0
	_carry_distance += moved.length()
	# 15 m run rule (RULES_REFERENCE.md §1). Only while genuinely running
	# with it — a disposal already underway (_action) means the run's over,
	# and a stunned player isn't running anywhere. Latched so FullGame gets
	# one call, not one per frame past the line.
	if not _run_too_far_latched and _carry_distance >= Tuning.BOUNCE_INTERVAL \
			and _action == Tuning.Action.NONE and _stun_timer <= 0.0:
		_run_too_far_latched = true
		run_too_far_called.emit(self)


## Passive walk-over gather (design brief: bringing the ball to hand must be
## affected by the player's speed at the moment of contact rather than being
## independent of movement). The Area3D shape is sized generously (see
## _ready()); the real cutoff is this explicit distance test against the
## current speed-scaled reach, so a player running through a bounce
## genuinely gets more reach than one standing still over it — not by much,
## GATHER_LUNGE_MAX keeps it well short of the deliberate GROUND_PICKUP
## reach, but real.
func _try_gather() -> void:
	# A bounce is taken back on the run, before its clip has finished: the
	# clip's own last beat is the hands taking it again (Tuning's
	# "Bouncing at pace").
	var bouncing := _action == Tuning.Action.BOUNCE and _action_fired
	if is_carrying() or _gather_cooldown > 0.0 or (_action != Tuning.Action.NONE and not bouncing) \
			or _stun_timer > 0.0:
		return
	if ruck_contest_locked():
		return
	var reach := Tuning.GATHER_RADIUS \
		+ minf(_speed * Tuning.GATHER_LUNGE_PER_SPEED, Tuning.GATHER_LUNGE_MAX)
	for body in _gather_zone.get_overlapping_bodies():
		if not (body is Ball):
			continue
		var ball := body as Ball
		if ball.is_held or ball.awaiting_own_bounce(self):
			continue
		if ball.linear_velocity.length() > Tuning.GATHER_MAX_BALL_SPEED:
			continue
		if _carry_point.global_position.distance_to(ball.global_position) > reach:
			continue
		_complete_gather(ball)
		return


## Shared attach/possession/signal path for every way of gaining the ball —
## the passive walk-over gather just above, an explicit ground pickup and
## every mark tier (see the Marking section below) — so none of them can
## drift out of sync about what "gained possession" actually does.
func _complete_gather(ball: Ball) -> void:
	# Whoever has the ball is no longer wrestling for it — covers both a
	# free kick/kick-in placement (give_possession) and the tackler simply
	# picking up what they just stripped while the grab is still playing.
	# Same for a ragdoll: a free kick awarded to a tackler still on the
	# ground puts them on their feet with the ball.
	_end_tackle_hold()
	_cancel_ragdoll()
	ball.attach_to(_carry_point, self)
	_carried_ball = ball
	_carry_distance = 0.0
	_run_too_far_latched = false
	MatchState.possession = team
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_GATHER)
	ball_gathered.emit(ball)


# ── Contests ─────────────────────────────────────────────────────────
# Tackling splits into two commitments sharing one physical resolver
# (_resolve_tackle_contact): Slide (held tackle button, this section) and
# Lunge (a tap, see _try_lunge_tackle further down). Design doc §5: decided
# by real closing speed / approach angle / carrier speed at contact, never a
# dice roll (RULES_REFERENCE.md §3 notes Prototype 1's old flat
# TACKLE_BREAK_CHANCE=0.45 coin-flip was deliberately dropped for exactly
# this reason). Two steps, both off the contact's own numbers: the gate
# decides whether it lands (a miss is a whiff), then TackleBalance's model
# decides whether a landed tackle holds or the carrier breaks it (Tuning's
# "Whether a tackle holds") — evaluated against a threshold, never rolled.
# A held tackle, of either kind, spills the ball loose for a fresh contest
# (holding-the-ball vs ball-up is _get_tackled's call, RULES_REFERENCE.md §4).

## Shared physical gate for both tackle commitments. closing_speed is the
## tackler-minus-target relative velocity dotted along the tackler→target
## line — positive means the gap is shrinking; a stationary tackler standing
## square in a sprinting carrier's path reads a HIGH closing_speed here
## because the carrier's own momentum is doing the work, which is exactly
## why a well-placed stand should almost always win. approach_angle is the
## angle between "target→tackler" and the target's own heading — 0° means
## the tackler is sitting in the carrier's path, 180° means chasing from
## directly behind — and falls back to the most favourable 0° when the
## target is below PIVOT_SPEED_THRESHOLD, since a near-stationary carrier
## has no meaningful heading to be "ahead of." carrier_speed stands in for
## carrier momentum: CharacterProfile has no weight stat, every
## PlayerController shares one physics mass, so speed alone is the proxy.
## Slide and Lunge feed the same three numbers into different thresholds
## (see Tuning's TACKLE_SLIDE_*/TACKLE_LUNGE_TAP_* constants) rather than
## being two separate contest mechanics.
## The three numbers themselves come from TackleBalance.contact_metrics, the
## same ones the ragdoll's balance loss is worked out from. `tackler_velocity`
## is what the tackler hits with — _tackle_velocity, not their raw velocity.
func _resolve_tackle_contact(tackler: PlayerController, target: PlayerController, is_slide: bool,
		tackler_velocity: Vector3) -> bool:
	var to_target := target.global_position - tackler.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return true
	var m := TackleBalance.contact_metrics(tackler.global_position, tackler_velocity,
		target.global_position, target.velocity)
	var closing_speed: float = m.closing_speed
	var carrier_speed: float = m.carrier_speed
	var approach_angle: float = m.approach_angle

	if is_slide:
		var required := Tuning.TACKLE_SLIDE_MIN_CLOSING_SPEED \
			+ Tuning.TACKLE_SLIDE_CLOSING_SPEED_SCALE * carrier_speed
		return closing_speed >= required and approach_angle <= Tuning.TACKLE_SLIDE_MAX_ANGLE_DEG
	var required := Tuning.TACKLE_LUNGE_TAP_MIN_CLOSING_SPEED \
		+ Tuning.TACKLE_LUNGE_TAP_CLOSING_SPEED_SCALE * carrier_speed
	return closing_speed >= required and approach_angle <= Tuning.TACKLE_LUNGE_TAP_MAX_ANGLE_DEG


## The velocity a tackle hits with: this body's own, topped up so it's
## driving at `target` at no less than `drive` m/s (the Lunge's lunge, the
## Slide's dive or step-in — Tuning's TACKLE_LUNGE_SPEED /
## TACKLE_SLIDE_*_SPEED). Contacts resolve after move_and_slide, which has
## already taken out whatever part of `velocity` ran into the target's
## capsule, so a tackler standing on a carrier otherwise reads as not
## moving at them at all. Topping up the tackler's own speed, not the
## closing speed, keeps a chase a chase: driving at 7 m/s after a carrier
## running away at 8 still closes on nothing.
func _tackle_velocity(target: PlayerController, drive: float) -> Vector3:
	var dir := target.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return velocity
	dir = dir.normalized()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	return flat + dir * maxf(0.0, drive - flat.dot(dir))


## FIFA-style ball-steal assist (polish-pass brief: "it's a bit hard to get
## the ball off the AI"). See Tuning's own "Slide's dive-in" comment for the
## actual diagnosis (AI_PRESSURE_RADIUS forces a disposal outside
## TACKLE_RADIUS, so a defender closing at normal run speed rarely gets
## there in time) and why this is a speed burst rather than a radius/chance
## change. Triggers on the tackle button's rising edge, not the held state
## _try_tackle() reads directly — holding tackle at standing range still
## works exactly as it always has; this only adds a commit option the one
## time it's actually needed, just out of that reach. Purely a movement-
## closing mechanic — once it lands, _try_tackle() below still has to pass
## _resolve_tackle_contact like any other Slide attempt; a miss here just
## means the dive didn't land, TACKLE_SLIDE_MISS_STUN_DURATION is what
## actually makes a bad Slide costly.
func _update_slide_dive(delta: float) -> void:
	var pressed := _brain.wants_tackle()
	var just_pressed := pressed and not _slide_was_pressed
	_slide_was_pressed = pressed
	_slide_just_pressed = just_pressed

	if _slide_dive_timer > 0.0:
		_slide_dive_timer = _tick_down(_slide_dive_timer, delta)
		return
	if _slide_dive_cooldown > 0.0 or is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE:
		return

	# A press landing a frame or two before the guards above actually
	# cleared shouldn't just vanish (fundamentals-pass input buffering) —
	# fall back to InputManager's short buffer window before giving up on
	# this frame. Checked only after every other blocking guard, so a
	# buffered press is never consumed on a frame it wouldn't actually
	# fire on. Human only: AI's wants_tackle() is a fresh proximity
	# decision every physics frame, not a real button press — there's
	# nothing to buffer for it.
	if not just_pressed \
			and not (_brain is HumanBrain and InputManager.consume_buffered_press(&"tackle")):
		return

	var carrier := _nearest_opposing_carrier()
	if carrier == null or carrier.is_protected():
		return
	var to_carrier := carrier.global_position - global_position
	to_carrier.y = 0.0
	var dist := to_carrier.length()
	if dist <= Tuning.TACKLE_RADIUS or dist > Tuning.TACKLE_SLIDE_DIVE_RANGE:
		return   # already close enough for a standing tackle, or too far to commit to
	var direction := to_carrier / dist
	if (-global_transform.basis.z).dot(direction) < Tuning.TACKLE_SLIDE_DIVE_MIN_DOT:
		return   # not roughly facing them — no diving sideways or backward

	_slide_dive_direction = direction
	_slide_dive_timer = Tuning.TACKLE_SLIDE_DIVE_DURATION
	_slide_dive_cooldown = Tuning.TACKLE_SLIDE_DIVE_COOLDOWN


## Slide connect: the target is held up, not knocked down — playtest
## feedback wanted the two tackle types to read differently (see Tuning.
## Action.TACKLE_HELD's own comment). TACKLE_GRAB (tackler) and TACKLE_HELD
## (target) are a synced pair, the same "two bodies meeting" relationship
## TACKLE_TAKEDOWN/TACKLED are for Lunge just below. The tackler always
## keeps their feet. A human's Slide hard enough to pass
## Tuning.TACKLE_SLIDE_KNOCKDOWN_B knocks the carrier over instead of holding
## them up — the held Lunge's ragdoll path — while the tackler slings them
## down (TACKLE_SLING); an AI's never does, since AI tackles stay on their
## clips. A Slide that lands but breaks (_break_tackle) leaves the carrier
## running.
func _try_tackle() -> void:
	if is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE or _mark_readying \
			or _lunge_dash_timer > 0.0:
		return
	# A dive in progress is a commitment — it still has to land the same
	# proximity test below, but it doesn't need the button held throughout,
	# same as an aggressive mark's jump or a bump's flick don't need theirs
	# held either once launched.
	if not _brain.wants_tackle() and _slide_dive_timer <= 0.0:
		return
	var target := _nearest_player(Tuning.TACKLE_RADIUS, func(other: PlayerController) -> bool:
		return other.team != team and other.is_carrying() and not other.is_protected())
	if target == null:
		# A press that just launched a dive at a carrier is going for them.
		if _slide_just_pressed and _slide_dive_timer <= 0.0:
			var fouled := _foul_target(Tuning.TACKLE_RADIUS)
			if fouled != null:
				_commit_foul(fouled, &"slide")
		return
	# Landed (the gate), then held or broken on the model (Tuning's "Whether
	# a tackle holds"). A broken Slide costs the tackler what a whiff does.
	# Mid-dive it hits at the dive's speed; otherwise it steps in.
	var hit_velocity := _tackle_velocity(target, Tuning.TACKLE_SLIDE_DIVE_SPEED
		if _slide_dive_timer > 0.0 else Tuning.TACKLE_SLIDE_STEP_SPEED)
	var impact := {}
	if _resolve_tackle_contact(self, target, true, hit_velocity):
		impact = TackleBalance.resolve(global_position, hit_velocity, body_mass,
			target.global_position, target.velocity, target.body_mass, 0.0,
			-target.global_transform.basis.z)
		last_tackle = impact.merged({"slide": true, "held": float(impact.p_break) < Tuning.TACKLE_SLIDE_BREAK_P})
	else:
		last_tackle = {"slide": true, "held": false, "missed": true}
	if last_tackle.held:
		_slide_connect(target, impact, true)
	else:
		if not impact.is_empty():
			target._break_tackle()
		# A whiffed Slide used to be the single costliest miss in the kit;
		# the hit-stick bump rework gave that title to a whiffed bump instead
		# — see TACKLE_SLIDE_MISS_STUN_DURATION's own updated comment. maxf,
		# not overwrite, matches receive_bump's pattern of never shortening a
		# stun already in progress.
		_stun_timer = maxf(_stun_timer, Tuning.TACKLE_SLIDE_MISS_STUN_DURATION)


## A Slide that holds, both sides of it. A human's hard enough to pass
## Tuning.TACKLE_SLIDE_KNOCKDOWN_B knocks the target over rather than
## holding them up: the tackler slings them down on their feet
## (Action.TACKLE_SLING, facing the hit) and the target goes down the held
## Lunge's ragdoll path, thrown the way the swing goes (_sling_impact).
## `ruling` false is a tackle off the ball (_commit_foul): the same hit,
## minus the ball and the holding-the-ball call (see _get_tackled).
func _slide_connect(target: PlayerController, impact: Dictionary, ruling: bool) -> void:
	if _brain is HumanBrain and float(impact.b) >= Tuning.TACKLE_SLIDE_KNOCKDOWN_B:
		last_tackle.knocked_down = true
		_slide_dive_timer = 0.0
		target._get_tackled(self, false, _sling_impact(impact, target), ruling)
		_fall_toward(impact.direction)
		_begin(Tuning.Action.TACKLE_SLING)
	else:
		target._get_tackled(self, true, {}, ruling)
		# Never blocked here: both callers already require _action == NONE.
		_begin(Tuning.Action.TACKLE_GRAB)
		# Both sides of the same wrestle, started on the same frame.
		_begin_tackle_hold(target, true)
		target._begin_tackle_hold(self, false)
	if ruling:
		tackle_committed.emit(true)


## The push for a sling (Tuning's "Sling"): the hit's push without the
## Lunge's leg drive (TACKLE_RAGDOLL_IMPULSE_SCALE: with it a 10.5 m/s dive
## sent a standing carrier tumbling 4 m), at SLING_PUSH_SCALE, turned off the
## hit line toward the tackler's left (TACKLE_SLING swings that way) and
## tipped down; the carrier's muscles at SLING_STRENGTH_SCALE. The tackler
## plants and stays up, so whatever of the carrier's run was going into them
## stops there. Left at their own, a head-on carrier ran on straight through
## the tackler's (unsimulated, animated) body. The tackler's own dive isn't
## handed on either: counted in (a shared velocity, as a bump's), a side-on
## carrier slid 5.3 m.
func _sling_impact(impact: Dictionary, target: PlayerController) -> Dictionary:
	var out := impact.duplicate()
	var line: Vector3 = impact.direction
	var left := Vector3.UP.cross(line).normalized()
	var throw := (line * Tuning.TACKLE_SLIDE_SLING_FORWARD + left * Tuning.TACKLE_SLIDE_SLING_SIDE).normalized()
	throw = (throw + Vector3.DOWN * Tuning.TACKLE_RAGDOLL_DRAG_DOWN).normalized()
	out.impulse = throw * (impact.impulse as Vector3).length() \
		/ Tuning.TACKLE_RAGDOLL_IMPULSE_SCALE * Tuning.TACKLE_SLIDE_SLING_PUSH_SCALE
	out.strength_scale = Tuning.TACKLE_SLIDE_SLING_STRENGTH_SCALE
	var run := Vector3(target.velocity.x, 0.0, target.velocity.z)
	out.start_velocity = run - line * minf(run.dot(line), 0.0)
	return out


## A Lunge that holds, both sides of it: the target down (ragdoll on a
## 6thbuild rig), and the tackler down with them, arms wrapped round their
## waist (Tuning's "Tackle wrap", TackleWrap), going the way they were
## running. It used to take the tackler down only on a big hit (b past
## TACKLE_RAGDOLL_TACKLER_MIN_B); playtest 2026-10-27 wanted every held X to
## hug and fall together. Their strength is capped low so their balance
## can't keep them up. A target that can't ragdoll (procedural rig) still
## gets the takedown beat on the tackler's feet. `ruling` as
## _slide_connect's.
func _lunge_connect(target: PlayerController, impact: Dictionary, ruling: bool) -> void:
	target._get_tackled(self, false, impact, ruling)
	var tackler_b: float = impact.tackler_b
	if not target.is_ragdolled() or not _begin_ragdoll({
			"strength": minf(1.0 - tackler_b, Tuning.TACKLE_WRAP_TACKLER_MAX_STRENGTH),
			"impulse": impact.tackler_impulse,
			"bone": &"Chest",
			"contact_offset": Vector3.ZERO,
			"body_share": 0.0,
			"partner": target,
			"velocity": impact.tackler_velocity,
			"mass_kg": body_mass,
		}):
		_begin(Tuning.Action.TACKLE_TAKEDOWN)
	else:
		_tackle_wrap = TackleWrap.new(_ragdoll, target.ragdoll_controller())
	if ruling:
		tackle_committed.emit(false)


## Lunge tackle (Q/X tap, not carrying): a quick grab at a carrier within
## Tuning.TACKLE_LUNGE_REACH — at once if they're inside TACKLE_RADIUS,
## otherwise after a short dash at them (_lunge_dash_*), hitting as if
## driving in at TACKLE_LUNGE_SPEED either way (see that constant's comment
## for the playtest report behind it). Playtest feedback: "the lunge tackle can
## take both players to the ground" — the target still goes all the way
## down (Action.TACKLED, unchanged), and now the tackler gets their own
## synced Action.TACKLE_TAKEDOWN beat too, driving down and ending low
## rather than standing untouched. The tackler themselves still isn't
## stunned and stays on their feet physically (no _stun_timer change, no
## collision/capsule change, `_lunge_tap_cooldown` unaffected either way) —
## TACKLE_TAKEDOWN is a cosmetic crouch layered on top of that, not a
## second real knockdown; a whiffed Lunge still only pays the short tap
## cooldown below, same as always, and so does one that lands but breaks.
## On a 6thbuild rig a held Lunge ragdolls the target instead (and the
## tackler too on a big hit) — see _get_tackled. Shares its physical
## binding with wants_handball()/wants_mark_running(); Smother moved to RB,
## so a kicker lining up is a Lunge target too.
func _try_lunge_tackle() -> void:
	if _lunge_dash_timer > 0.0:
		_step_lunge_dash()
		return
	if is_carrying() or _stun_timer > 0.0 or _lunge_tap_cooldown > 0.0 \
			or _action != Tuning.Action.NONE or _mark_readying:
		return
	# A press with nobody in reach yet stays buffered (InputManager) for the
	# carrier to step in, rather than being spent on nothing.
	if _brain.lunge_tackle_pending() and _lunge_target(Tuning.TACKLE_LUNGE_REACH) == null \
			and _foul_target(Tuning.TACKLE_RADIUS) == null:
		return
	if not _brain.wants_lunge_tackle():
		return
	var target := _lunge_target(Tuning.TACKLE_LUNGE_REACH)
	if target == null:
		# Nobody legal to tackle, but someone right there who isn't (no ball,
		# or protected): a free kick or 50 against. Point-blank only — no
		# dash at somebody you can't tackle.
		var fouled := _foul_target(Tuning.TACKLE_RADIUS)
		if fouled != null:
			_commit_foul(fouled, &"lunge")
		return
	if _flat_distance_to(target) <= Tuning.TACKLE_RADIUS:
		_land_lunge(target)
		return
	_lunge_dash_target = target
	_lunge_dash_speed = maxf(Tuning.TACKLE_LUNGE_SPEED, _speed)
	_lunge_dash_timer = Tuning.TACKLE_LUNGE_DASH_DURATION


func _lunge_target(reach: float) -> PlayerController:
	return _nearest_player(reach, func(other: PlayerController) -> bool:
		return _is_lunge_target(other))


## A kicker lining up counts: Smother is on its own button now (RB, with the
## ruck tap) rather than X, so X tackles them instead of diving at the boot
## — playtest: "the X tackle is just smothering".
func _is_lunge_target(other: PlayerController) -> bool:
	return is_instance_valid(other) and other.team != team and other.is_carrying() \
		and not other.is_protected()


## Who a human's tackle within `reach` would foul, or null: the nearest
## opponent this player may not tackle — no ball, or holding it under
## protection (see `infringed`). Never while a kick is in the air: in a
## marking contest X is also the running mark, and a contest for the ball
## isn't a tackle off it. AI brains never get one (null), so an AI only
## ever tackles carriers.
func _foul_target(reach: float) -> PlayerController:
	if not _brain is HumanBrain:
		return null
	var ball := _live_ball()
	if ball != null and (ball.is_kick_flight() or ball.is_airborne()):
		return null
	return _nearest_player(reach, func(other: PlayerController) -> bool:
		return other.team != team and (not other.is_carrying() or other.is_protected()))


## A human's tackle or bump on `fouled` that isn't allowed (see `infringed`).
## The hit itself still happens (playtest: "make sure the ragdoll tackle
## animation still plays") — `kind` &"lunge", &"slide" or &"bump" plays that
## move's connect, the model setting how hard, just never the hold-or-break
## check (a free kick isn't something to break) and never a strip: a
## protected carrier only lets the ball fall at their feet, which the award
## puts straight back in their hands. Then match flow is told.
func _commit_foul(fouled: PlayerController, kind: StringName) -> void:
	var fifty := fouled.is_carrying() and fouled.is_protected()
	last_tackle = {"foul": true, "fifty": fifty}
	_lunge_tap_cooldown = Tuning.TACKLE_LUNGE_TAP_COOLDOWN
	_lunge_dash_timer = 0.0
	if fifty:
		fouled.drop_ball()
	if kind == &"bump":
		_resolve_bump_contact(fouled, true)
	else:
		var slide := kind == &"slide"
		var drive := Tuning.TACKLE_LUNGE_SPEED
		if slide:
			drive = Tuning.TACKLE_SLIDE_DIVE_SPEED if _slide_dive_timer > 0.0 else Tuning.TACKLE_SLIDE_STEP_SPEED
		var impact := TackleBalance.resolve(global_position, _tackle_velocity(fouled, drive), body_mass,
			fouled.global_position, fouled.velocity, fouled.body_mass,
			0.0 if slide else Tuning.TACKLE_RAGDOLL_MIN_BALANCE_LOSS, -fouled.global_transform.basis.z)
		last_tackle.merge(impact)
		if slide:
			_slide_connect(fouled, impact, false)
		else:
			_lunge_connect(fouled, impact, false)
	infringed.emit(fouled, fifty)


func _flat_distance_to(other: Node3D) -> float:
	var d := other.global_position - global_position
	d.y = 0.0
	return d.length()


## One frame of a Lunge's dash, after this frame's move: lands it once the
## carrier is inside TACKLE_RADIUS, whiffs it (the tap cooldown) when the
## clock runs out, and lets it go quietly if they stopped being a target
## (the ball went elsewhere).
func _step_lunge_dash() -> void:
	_lunge_dash_timer = _tick_down(_lunge_dash_timer, get_physics_process_delta_time())
	var target := _lunge_dash_target
	if not _is_lunge_target(target) or _stun_timer > 0.0 or is_carrying():
		_lunge_dash_timer = 0.0
		return
	if _flat_distance_to(target) <= Tuning.TACKLE_RADIUS:
		_lunge_dash_timer = 0.0
		_land_lunge(target)
	elif _lunge_dash_timer <= 0.0:
		last_tackle = {"slide": false, "held": false, "missed": true}
		_lunge_tap_cooldown = Tuning.TACKLE_LUNGE_TAP_COOLDOWN


## A Lunge reaching its carrier: the gate, then hold or break, then the fall.
func _land_lunge(target: PlayerController) -> void:
	var hit_velocity := _tackle_velocity(target, Tuning.TACKLE_LUNGE_SPEED)
	if not _resolve_tackle_contact(self, target, false, hit_velocity):
		last_tackle = {"slide": false, "held": false, "missed": true}
		_lunge_tap_cooldown = Tuning.TACKLE_LUNGE_TAP_COOLDOWN
		return
	# Worked out once, before either body changes, so both players react
	# to the same hit — and whether it holds at all comes off the same read
	# (Tuning's "Whether a tackle holds").
	var impact := TackleBalance.resolve(global_position, hit_velocity, body_mass,
		target.global_position, target.velocity, target.body_mass,
		Tuning.TACKLE_RAGDOLL_MIN_BALANCE_LOSS, -target.global_transform.basis.z)
	last_tackle = impact.merged({"slide": false, "held": float(impact.p_break) < Tuning.TACKLE_LUNGE_BREAK_P})
	if not last_tackle.held:
		target._break_tackle()
		_lunge_tap_cooldown = Tuning.TACKLE_LUNGE_TAP_COOLDOWN
		return
	_lunge_connect(target, impact, true)


## Called on the tackled player, by the tackler. `is_slide` picks which
## reaction plays — a Slide connect holds the target up (Action.TACKLE_
## HELD, standing, no fall); a Lunge connect still takes them all the way
## down (Action.TACKLED via _knockdown(), falling facing away from the
## hit — the same scatter direction the ball spills in, design brief: a
## tackled player goes down "in the direction it is coming from"). The
## ball's own drop differs too, on purpose: a Lunge connecting is a real
## loose-ball spill (TACKLE_SPILL_SPEED scatter impulse, the same physical
## contest a knockdown always has); a Slide connect is a held-up strip —
## playtest feedback: "the animation drops the ball, the ball typically
## would not spill out if the tackle is held" — so it just falls straight
## down from wherever it was carried (drop_ball()'s own detach(), no
## impulse at all), landing at the target's feet rather than scattering
## away from them.
##
## On a 6thbuild rig a Lunge connect goes to the active ragdoll instead of
## the TACKLED clip (Tuning's "Active ragdoll tackles"): `impact` is
## TackleBalance.resolve's read of the hit, and the body falls however that
## push and its own momentum take it. The ball spills exactly as before —
## the ragdoll changes how the player goes down, never what the tackle
## decided.
##
## `ruling` false is a tackle off the ball (PlayerController._commit_foul):
## the body reacts exactly the same — the hit is real — but there's no ball
## to spill and no holding-the-ball/ball-up call; the free kick or 50 is
## FullGame's to award.
func _get_tackled(by: PlayerController, is_slide: bool, impact := {}, ruling := true) -> void:
	var ball := _carried_ball if ruling else null
	# Captured before drop_ball() resets anything, though drop_ball() itself
	# doesn't touch this timer — is_carrying() going false next frame is what
	# actually zeroes it (see _physics_process) — read now regardless, so
	# there's no dependency on exactly when that reset happens to land.
	var holding_the_ball := _possession_held_seconds >= Tuning.PRIOR_OPPORTUNITY_GRACE
	var scatter := _scatter_from(by, 0.0)
	if ruling:
		drop_ball()
	if is_slide:
		_stun_timer = maxf(_stun_timer, Tuning.TACKLE_HELD_STUN_DURATION)
		_action = Tuning.Action.NONE
		_begin(Tuning.Action.TACKLE_HELD)
	else:
		var ragdolled := not impact.is_empty() and _begin_ragdoll({
			"strength": (1.0 - float(impact.b)) * float(impact.get("strength_scale", 1.0)),
			"impulse": impact.impulse,
			"bone": impact.bone,
			"contact_offset": impact.contact_offset,
			"body_share": impact.body_share,
			"partner": by,
			"velocity": impact.get("start_velocity", velocity),
			"mass_kg": body_mass,
		})
		if not ragdolled:
			_knockdown(scatter, Tuning.TACKLE_STUN_DURATION)
		if is_instance_valid(ball):
			ball.apply_central_impulse(scatter * Tuning.TACKLE_SPILL_SPEED * ball.mass)
	if not ruling:
		return
	if holding_the_ball:
		holding_the_ball_called.emit(by)
	else:
		field_ball_up_called.emit(by, self)


## Called on the carrier when a tackle lands but the model says it breaks
## (Tuning's "Whether a tackle holds"): they shrug it, keep the ball and
## run on, a step slower for it, and the locomotion they never left picks
## the pace back up. No ragdoll and no clip — nothing about them changes but
## their speed.
func _break_tackle() -> void:
	velocity.x *= Tuning.TACKLE_BREAK_SPEED_KEEP
	velocity.z *= Tuning.TACKLE_BREAK_SPEED_KEEP
	_speed *= Tuning.TACKLE_BREAK_SPEED_KEEP


## Rulebook §6: a Slide connect should read as one wrestle, not two clips
## that happen to play at the same time. For as long as the synced
## TACKLE_GRAB/TACKLE_HELD pair runs, the tackler is pinned at
## Tuning.TACKLE_HOLD_DISTANCE from the target and both are turned to face
## each other (see _update_locomotion's own branch, which is where the
## actual movement override lives — this only sets the state it reads).
##
## Called on both players from _try_tackle, so the two windows start on the
## same frame and can't drift. Duration is the grab clip's own length
## rather than a constant of its own: the hold IS the clip, and the two
## going out of sync is exactly the "snaps to a resolved state" the
## rulebook is describing.
func _begin_tackle_hold(partner: PlayerController, is_tackler: bool) -> void:
	_tackle_hold_partner = partner
	_tackle_hold_is_tackler = is_tackler
	_tackle_hold_timer = Tuning.action_duration(Tuning.Action.TACKLE_GRAB)
	# The two capsules would otherwise hold each other 0.70m apart — far
	# enough that the wrap can't reach and the pair reads as two bodies
	# bumping. Lifted only for the length of the hold, and only between
	# these two; everyone else still collides with both of them normally.
	if is_instance_valid(partner):
		add_collision_exception_with(partner)
	# The dive that got here has landed — it must not keep driving the body
	# forward through the player it just caught.
	_slide_dive_timer = 0.0


## Released the moment the hold's window ends, the partner goes away, or a
## stoppage takes over (give_possession/set_ruck_contestant both call this
## — a free kick or a ball-up repositions players outright, and a lock
## still pulling toward an old partner would drag them straight back off
## the spot they were just placed on).
func _end_tackle_hold() -> void:
	if is_instance_valid(_tackle_hold_partner):
		remove_collision_exception_with(_tackle_hold_partner)
	_tackle_hold_timer = 0.0
	_tackle_hold_partner = null
	_tackle_hold_is_tackler = false


func _update_tackle_hold(delta: float) -> void:
	if _tackle_hold_timer <= 0.0:
		return
	_tackle_hold_timer -= delta
	if _tackle_hold_timer <= 0.0 or not is_instance_valid(_tackle_hold_partner):
		_end_tackle_hold()


## Shared "play the fall/recover clip" beat behind every hard knockdown in
## the kit — a Lunge tackle connecting (_get_tackled above, is_slide=false)
## and, since the hit-stick bump rework, a clean bump connect or a whiffed
## bump dash landing on the bumper themselves (_resolve_bump_contact/
## _resolve_bump_miss below). Never touches the ball or possession —
## callers that need that (a Lunge tackle strips it; a clean bump now
## spills it too) do it themselves before calling this. `action` defaults to
## Action.TACKLED (fall forward, in the direction of travel); Bump's clean
## connect passes Action.KNOCKED_BACK instead (falls backward — see that
## Action's own comment) along with `snap_facing = false`, since a backward
## fall should NOT spin the body around to face the direction it's
## travelling the way TACKLED's own forward crumple wants to.
func _knockdown(direction: Vector3, stun_duration: float,
		action: Tuning.Action = Tuning.Action.TACKLED, snap_facing: bool = true) -> void:
	_stun_timer = maxf(_stun_timer, stun_duration)
	_action = Tuning.Action.NONE
	if snap_facing:
		_fall_toward(direction)
	_begin(action)


## Snaps facing to `direction` immediately, bypassing _update_facing()'s
## normal rotate_toward easing — a tackle puts the body down facing away
## from the hit on the very frame it connects, not several frames later.
## Also updates _heading so every subsequent frame's _update_facing() call
## agrees with this rather than trying to rotate back toward wherever the
## body was facing a moment before impact.
func _fall_toward(direction: Vector3) -> void:
	if direction.length_squared() < 0.0001:
		return
	_heading = direction.normalized()
	_facing_yaw = atan2(-_heading.x, -_heading.z)
	rotation.y = _facing_yaw


## Hands the body to the active ragdoll (PlayerRagdoll) for a tackle — see
## its header for the phases. `hit` is PlayerRagdoll.begin's, plus an
## optional "partner" (the other player in the tackle — see
## _ragdoll_partner). Returns false
## when this player can't ragdoll (procedural rig, feature off), so the
## caller plays its canned clip instead. Whatever action was playing is cut
## — physics has the skeleton now.
func _begin_ragdoll(hit: Dictionary) -> bool:
	var rig := get_node_or_null(^"Rig") as HumanoidRig
	if not PlayerRagdoll.supported(rig):
		return false
	if _ragdoll == null:
		_ragdoll = PlayerRagdoll.new(self, rig, _animation)
	if not _ragdoll.begin(hit):
		return false
	# Tackled out of a wrap of their own: those arms aren't holding anyone.
	if _tackle_wrap != null:
		_tackle_wrap.release()
		_tackle_wrap = null
	_action = Tuning.Action.NONE
	_charging = false
	_end_tackle_hold()
	_slide_dive_timer = 0.0
	_bump_dash_timer = 0.0
	_smother_dive_timer = 0.0
	_lunge_dash_timer = 0.0
	_knockback = Vector3.ZERO
	_stun_timer = maxf(_stun_timer, 0.1)
	var partner := hit.get("partner") as PlayerController
	if is_instance_valid(partner) and partner != _ragdoll_partner:
		if is_instance_valid(_ragdoll_partner):
			remove_collision_exception_with(_ragdoll_partner)
		add_collision_exception_with(partner)
		_ragdoll_partner = partner
	return true


func _cancel_ragdoll() -> void:
	if is_ragdolled():
		_ragdoll.cancel()


## True from a ragdoll tackle connecting until its get-up blend finishes —
## physics owns this player's body for all of it.
func is_ragdolled() -> bool:
	return _ragdoll != null and _ragdoll.is_active()


## For headless checks: the active ragdoll, or null if this player has
## never been ragdoll-tackled.
func ragdoll_controller() -> PlayerRagdoll:
	return _ragdoll


## PlayerRagdoll's hand-back: the get-up clip is about to start from its
## lying frame, so put the player where that frame lines up with the landed
## body and keep them down until the clip ends.
func on_ragdoll_getup(origin: Vector3, yaw: float, stun: float) -> void:
	global_position = origin
	velocity = Vector3.ZERO
	_speed = 0.0
	_facing_yaw = yaw
	rotation.y = yaw
	_heading = -global_transform.basis.z
	_heading.y = 0.0
	_heading = _heading.normalized()
	_stun_timer = maxf(_stun_timer, stun)


## Smother (X tap, not carrying): a real committed dive at a kicker (design
## brief, after playtest feedback the old instant-radius version never
## actually moved: "does not dive the player onto the ground to smother the
## kick"). Targets anyone still carrying whose kick hasn't fired yet —
## either still in stance (is_kick_aiming()) or mid-swing but before
## contact (is_mid_kick_swing()) — since a kick already gone is nothing a
## smother can do anything about. Unlike Bump, this locks the target at
## launch (the filter below already has to find exactly one to trigger at
## all) and re-aims _smother_dive_direction at their live position every
## frame while the dive is active — see the block below and Tuning's own
## Smother section. Resolution (did the dive actually reach them in time)
## happens post-move in _try_smother_contact(), the same split every other
## contest in this file follows.
func _update_smother(delta: float) -> void:
	if _smother_dive_timer > 0.0:
		_smother_dive_timer = _tick_down(_smother_dive_timer, delta)
		if is_instance_valid(_smother_dive_target):
			var to_target := _smother_dive_target.global_position - global_position
			to_target.y = 0.0
			if to_target.length_squared() > 0.0001:
				_smother_dive_direction = to_target.normalized()
		return
	if live_smother_target() == null:
		return
	if not _brain.wants_smother():
		return
	var target := live_smother_target()

	_smother_dive_target = target
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	_smother_dive_direction = to_target.normalized() if to_target.length_squared() > 0.0001 \
		else -global_transform.basis.z
	_smother_dive_timer = Tuning.SMOTHER_DIVE_DURATION
	_smother_dive_cooldown = Tuning.SMOTHER_DIVE_COOLDOWN
	_begin(Tuning.Action.SMOTHER_DIVE)


## Who a smother tap would dive at right now, or null: the nearest opponent
## within SMOTHER_COMMIT_RANGE whose kick can still be blocked (in stance or
## mid-swing), and only while this player is free to commit. The one filter
## behind both _update_smother and MarkPrompt's SMOTHER badge, so the badge
## shows exactly when the button would do something.
func live_smother_target() -> PlayerController:
	if is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE \
			or _smother_dive_timer > 0.0 or _smother_dive_cooldown > 0.0:
		return null
	return _nearest_player(Tuning.SMOTHER_COMMIT_RANGE, func(other: PlayerController) -> bool:
		return other.team != team and other.is_carrying() \
			and (other.is_kick_aiming() or other.is_mid_kick_swing()))


## Runs every physics frame a smother dive is live, after the body has
## actually moved this frame (same ordering _try_tackle()/_try_bump_
## contact() use). The dive's own clip (Action.SMOTHER_DIVE) plays out
## regardless of outcome — this only decides the game effect: did it
## actually reach SMOTHER_RADIUS of the target while their kick was still
## blockable. If the target disposed, got tackled, or their kick already
## fired before the dive got there, this just quietly does nothing and the
## dive's own timer runs out on its own — no separate miss penalty, the
## same "stays on feet, minimal cost" precedent Lunge tackle already set
## for a low-commitment miss.
func _try_smother_contact() -> void:
	if _smother_dive_timer <= 0.0 or not is_instance_valid(_smother_dive_target):
		return
	var target := _smother_dive_target
	if not target.is_carrying() or not (target.is_kick_aiming() or target.is_mid_kick_swing()):
		return
	if global_position.distance_to(target.global_position) <= Tuning.SMOTHER_RADIUS:
		target._get_smothered(self)
		_smother_dive_timer = 0.0


## Shared spill-direction math for _get_tackled/_get_smothered: away from
## whoever caused it, flattened and re-lifted by `up_bias` (a smother pops
## the ball up slightly at the boot; a tackle spills it flat), falling back
## to straight ahead on the (near-impossible) exact-same-position case
## rather than normalizing a zero vector.
func _scatter_from(attacker: PlayerController, up_bias: float) -> Vector3:
	var scatter := global_position - attacker.global_position
	scatter.y = up_bias
	return scatter.normalized() if scatter.length_squared() > 0.0001 else Vector3.FORWARD


## Called on the smothered player, by the smotherer. Cancels the kick
## outright — whatever stage the swing was at, it doesn't complete — and
## the ball drops right at their feet rather than spilling like a tackle:
## blocked at the boot means it barely moves. Plays the Action.SMOTHERED
## recoil/stumble (design brief: "should visibly react/stumble, not just
## silently lose the ball") — a reaction, not a knockdown, so unlike
## _get_tackled/_knockdown this never touches facing or _stun_timer, just
## the usual _action != NONE gate for its own short duration. `_action` is
## force-reset to NONE first (same as _knockdown) since the player is very
## likely mid-KICK right now — that's the whole reason they were a valid
## smother target (is_kick_aiming()/is_mid_kick_swing()) — and _begin()
## would otherwise refuse to start a new action over an active one.
func _get_smothered(by: PlayerController) -> void:
	var ball := _carried_ball
	drop_ball()
	_action = Tuning.Action.NONE
	_begin(Tuning.Action.SMOTHERED)
	if is_instance_valid(ball):
		ball.knock(_scatter_from(by, 0.3) * Tuning.SMOTHER_SPILL_SPEED * ball.mass)


# ── Bump ─────────────────────────────────────────────────────────────
# Design brief priority 7: LB hold + Right Stick flick, Madden's hit-stick
# model. Out-of-possession only, same as tackle/spoil/smother. The flick
# gesture itself lives in InputManager (a raw device primitive that didn't
# exist before this pass).
#
# Rebuilt from an instant proximity+cone check into a real committed dash,
# the same "external velocity owns the body for a window" shape Slide's
# dive-in (_update_slide_dive) already uses: a completed flick launches
# _bump_dash_timer/_bump_dash_direction (see _update_locomotion's own
# dash branch for the movement side), and resolution happens after the
# body has actually moved — _try_bump_contact(), called alongside
# _try_tackle()/_try_smother_contact() post-move in _physics_process, the
# same "physics decides after the body moves" split every other contest
# here follows. Unlike Slide's dive-in, which never locks onto a target ahead
# of time either but just fizzles for free if it never reaches anyone, a
# bump dash that reaches the end of its own clock with nobody found is a
# genuine whiff (design brief: full commitment, full consequence) — see
# _resolve_bump_miss.

func _update_bump(delta: float) -> void:
	if _bump_dash_timer > 0.0:
		_bump_dash_timer = _tick_down(_bump_dash_timer, delta)
		_apply_bump_assist(delta)
		return
	if is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE or _bump_cooldown > 0.0:
		return
	if not _brain.wants_bump_stance():
		return
	var flick := InputManager.flick_vector()
	if flick == Vector2.ZERO:
		return

	_bump_dash_direction = _flick_world_direction(flick)
	_bump_dash_timer = Tuning.BUMP_DASH_DURATION
	_bump_dash_active = true
	_bump_close_in_time = 0.0
	_bump_cooldown = Tuning.BUMP_COOLDOWN


## `flick_raw` is the stick's raw (x, y) at the instant the gesture
## completed — converted to a world-space direction the same camera-
## relative way HumanBrain.wish_direction() already converts movement
## input, so "flick right" means the same thing on screen a bump does as
## it does for running.
func _flick_world_direction(flick_raw: Vector2) -> Vector3:
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	if is_instance_valid(camera):
		var flat := -camera.global_transform.basis.z
		flat.y = 0.0
		if flat.length_squared() > 0.000001:
			forward = flat.normalized()
			right = Vector3(-forward.z, 0.0, forward.x)
	var dir := right * flick_raw.x + forward * flick_raw.y
	return dir.normalized() if dir.length_squared() > 0.0001 else forward


## Gentle homing correction while a bump dash is live — the same "nudge
## toward the play, don't lock onto it" spirit _apply_aim_assist() already
## uses for kicks (KICK_AIM_ASSIST_*). Added directly off real playtesting:
## a dash frozen at the flick's exact instant direction almost never
## connects with a carrier who's still moving by the time the dash gets
## there ("I cannot hit the other player over with the hit stick"). Only
## pulls toward a carrier already roughly in front of the swing (BUMP_
## ASSIST_CONE_DEG, wider than the contact cone BUMP_CONE_DEG itself) and
## within plausible reach (BUMP_ASSIST_RANGE) — a correction on top of a
## real flick, not a substitute for aiming one.
func _apply_bump_assist(delta: float) -> void:
	var carrier := _nearest_opposing_carrier()
	if carrier == null:
		return
	var to_carrier := carrier.global_position - global_position
	to_carrier.y = 0.0
	var dist := to_carrier.length()
	if dist < 0.01 or dist > Tuning.BUMP_ASSIST_RANGE:
		return
	var to_carrier_dir := to_carrier / dist
	if _bump_dash_direction.angle_to(to_carrier_dir) > deg_to_rad(Tuning.BUMP_ASSIST_CONE_DEG):
		return
	var k := minf(1.0, Tuning.BUMP_ASSIST_STRENGTH * delta)
	_bump_dash_direction = _bump_dash_direction.slerp(to_carrier_dir, k).normalized()


## Runs every physics frame a bump dash is live, after the body has
## actually moved this frame (same ordering _try_tackle()/_try_smother_
## contact() use). No target to lock onto ahead of time — a bump is a physical
## swing, not a selection — so this just keeps asking "is anyone in range
## and roughly in front of the swing right now," the same "physically
## doing the right thing is what resolves it" stance every other contest
## here takes. The instant that's true, it connects (_resolve_bump_
## contact); if the dash's own clock runs out first, it's a whiff
## (_resolve_bump_miss). _bump_dash_active (not _bump_dash_timer) gates
## this so the one frame the timer reaches exactly zero still gets
## evaluated — see that field's own doc comment. Both resolution branches
## also zero _bump_dash_timer itself, not just _bump_dash_active — a
## connect can land well before the dash's own clock runs out (unlike
## Slide's dive-in, a bump dash has no launch-range gate, so it can
## connect on its very first frame), and _update_locomotion's dash-override
## branch keys off _bump_dash_timer > 0.0; leaving it positive would keep
## sliding the bumper forward at full dash speed, straight through whoever
## they just hit, until the leftover clock ran out on its own.
func _try_bump_contact() -> void:
	if not _bump_dash_active:
		return
	var carrier := _nearest_opposing_carrier()
	if carrier != null and _bump_reaches(carrier):
		# A carrier under protection (mark/free kick) can't be bumped off it —
		# that used to strip the ball; now it's a 50 m penalty (`infringed`).
		if carrier.is_protected() and _brain is HumanBrain:
			_commit_foul(carrier, &"bump")
		elif not carrier.is_protected():
			if _bump_closing_in(carrier):
				return
			_resolve_bump_contact(carrier)
		_bump_dash_active = false
		_bump_dash_timer = 0.0
		return
	# A late hit: the dash connecting with an opponent who hasn't got it.
	var fouled := _foul_target(Tuning.BUMP_RANGE)
	if fouled != null and not fouled.is_carrying() and _bump_reaches(fouled):
		_commit_foul(fouled, &"bump")
		_bump_dash_active = false
		_bump_dash_timer = 0.0
		return
	if _bump_dash_timer <= 0.0:
		_resolve_bump_miss()
		_bump_dash_active = false


## A swing that's reached its carrier (BUMP_RANGE, so a bump is no harder to
## land) drives the rest of the way in, straight at them, and hits when the
## bodies meet: true while it's still closing. Resolved at BUMP_RANGE, a
## ragdolled carrier was thrown back with the bumper still ~1.9 m off them
## (Tuning's "Hit stick"). BUMP_CLOSE_IN_MAX_TIME caps the wait, so a carrier
## who somehow keeps the gap still gets hit; the dash's own clock can't run
## out to a whiff meanwhile.
func _bump_closing_in(carrier: PlayerController) -> bool:
	var to_carrier := carrier.global_position - global_position
	to_carrier.y = 0.0
	if to_carrier.length() <= Tuning.BUMP_IMPACT_DISTANCE \
			or _bump_close_in_time >= Tuning.BUMP_CLOSE_IN_MAX_TIME:
		return false
	var delta := get_physics_process_delta_time()
	_bump_close_in_time += delta
	_bump_dash_direction = to_carrier.normalized()
	_bump_dash_timer = maxf(_bump_dash_timer, delta)
	return true


## Whether this frame's bump dash reaches `other`: in BUMP_RANGE and inside
## BUMP_CONE_DEG of the dash.
func _bump_reaches(other: PlayerController) -> bool:
	var to_other := other.global_position - global_position
	to_other.y = 0.0
	var dist := to_other.length()
	return dist <= Tuning.BUMP_RANGE and dist > 0.0001 \
		and _bump_dash_direction.angle_to(to_other.normalized()) <= deg_to_rad(Tuning.BUMP_CONE_DEG)


## A bump dash connecting — clean or mistimed exactly as the old
## instant-resolve version already decided it (design brief: "timing
## relative to the ball carrier's approach determines the outcome" —
## BUMP_APPROACH_DOT_MIN/BUMP_MISTIMED_SCALE, unchanged). A clean connect
## now goes further than a knockback: the carrier goes all the way down,
## Action.KNOCKED_BACK, not Action.TACKLED — a clean hit from the front
## should send them straight down onto their back, still facing roughly
## where they already were, not spin them 180° to face away first the way
## TACKLED's own "face the fall direction" convention would (playtest
## feedback caught exactly that spin). `snap_facing = false` is what skips
## it — see _knockdown()'s own doc comment. The bumper stays on their feet
## either way, the whole point of a hit-stick over a tackle. A clean
## connect also spills the ball loose on the instant of the hit
## (BUMP_SPILL_SPEED, forward in the hit direction) — playtest request, so
## a bump is now a genuine turnover, not just a knock that leaves the
## carrier holding on. A mistimed/glancing connect stays the original
## lighter physics-only reaction with no clip of its own and no strip.
## `always_clean` is a late hit (_commit_foul): the timing read assumes a
## carrier running onto the bump, so a hit on someone standing off the ball
## came out glancing and nothing played — a foul is a full hit regardless.
func _resolve_bump_contact(carrier: PlayerController, always_clean := false) -> void:
	var to_carrier := carrier.global_position - global_position
	to_carrier.y = 0.0
	var carrier_velocity := Vector3(carrier.velocity.x, 0.0, carrier.velocity.z)
	var approach_dot := 0.0
	if carrier_velocity.length_squared() > 0.01 and to_carrier.length_squared() > 0.0001:
		approach_dot = carrier_velocity.normalized().dot(-to_carrier.normalized())
	var clean := always_clean or approach_dot >= Tuning.BUMP_APPROACH_DOT_MIN
	var scale := 1.0 if clean else Tuning.BUMP_MISTIMED_SCALE

	carrier.receive_bump(_bump_dash_direction * Tuning.BUMP_KNOCKBACK_SPEED * scale,
		Tuning.BUMP_STUN_DURATION * scale, self)
	if clean:
		# The ball comes loose on the hit, synced with the KNOCKED_BACK fall
		# — a clean hit-stick jolts it out of the carrier's hands, spilling
		# forward in the hit direction. Grabbed before drop_ball() clears the
		# reference, same shape as _get_tackled's Lunge spill.
		var spilled_ball := carrier.carried_ball()
		carrier.drop_ball()
		# A 6thbuild pair both ragdoll (Tuning's "Hit stick"): the carrier
		# thrown along the dash, the bumper diving on after them. The
		# procedural rig keeps the canned fall and hop.
		if carrier._bump_ragdoll(self, _bump_dash_direction):
			_bump_dive(carrier, _bump_dash_direction)
		else:
			carrier._knockdown(_bump_dash_direction, Tuning.BUMP_KNOCKDOWN_STUN_DURATION,
				Tuning.Action.KNOCKED_BACK, false)
			carrier._apply_knockdown_hop()
		if is_instance_valid(spilled_ball):
			spilled_ball.apply_central_impulse(
				_bump_dash_direction * Tuning.BUMP_SPILL_SPEED * spilled_ball.mass)
	bump_landed.emit(self, carrier, clean)


## Called on the carrier of a clean bump by the bumper: thrown along the
## dash `direction` as a ragdoll (Tuning's "Hit stick"). Their run along the
## line is replaced by the collision's common velocity — the bumper at
## BUMP_DASH_SPEED, both by mass — and the throw goes on top of that, lifted
## off the turf. Their run across the line they keep. Returns false when this
## rig can't ragdoll, so the caller plays the canned fall instead.
func _bump_ragdoll(by: PlayerController, direction: Vector3) -> bool:
	var along := velocity.dot(direction)
	var common := (by.body_mass * Tuning.BUMP_DASH_SPEED + body_mass * along) / (by.body_mass + body_mass)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	return _begin_ragdoll({
		"strength": Tuning.BUMP_RAGDOLL_STRENGTH,
		"impulse": (direction + Vector3.UP * Tuning.BUMP_RAGDOLL_LIFT).normalized()
			* body_mass * Tuning.BUMP_RAGDOLL_LAUNCH_SPEED,
		"bone": &"Chest",
		"contact_offset": -direction * Tuning.TACKLE_RAGDOLL_CONTACT_SIDE_OFFSET,
		"body_share": Tuning.BUMP_RAGDOLL_BODY_SHARE,
		"partner": by,
		"velocity": flat - direction * flat.dot(direction) + direction * maxf(common, 0.0),
		"mass_kg": body_mass,
	})


## The bumper's half of a clean ragdoll bump: on at the collision's common
## velocity along the dash and diving after the carrier — the push mostly at
## the chest pitches them forward over their feet (Tuning's "Hit stick"). If
## this rig can't ragdoll they just stay up, as a bump always used to.
func _bump_dive(carrier: PlayerController, direction: Vector3) -> void:
	var along := carrier.velocity.dot(direction)
	var common := (body_mass * Tuning.BUMP_DASH_SPEED + carrier.body_mass * along) \
		/ (body_mass + carrier.body_mass)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	_begin_ragdoll({
		"strength": Tuning.BUMP_DIVE_STRENGTH,
		"impulse": direction * body_mass * Tuning.BUMP_DIVE_DRIVE,
		"bone": &"Chest",
		"contact_offset": Vector3.ZERO,
		"body_share": Tuning.BUMP_DIVE_BODY_SHARE,
		"partner": carrier,
		"velocity": flat - direction * flat.dot(direction) + direction * maxf(common, 0.0),
		"mass_kg": body_mass,
	})


## The dash ran its full course without ever finding a target — a genuine
## whiff. Overcommitting a hit-stick swing at nobody sends the bumper down
## too, tumbling forward in the direction they were already committed to
## (Action.TACKLED, unchanged — an overextending whiff reads as toppling
## forward past the swing, not backward, so this keeps the default action/
## facing-snap _knockdown() already has), with real extra recovery on top
## of Action.TACKLED's own clip length — see BUMP_MISS_STUN_DURATION's own
## comment on why this is deliberately the single biggest miss penalty in
## the kit. Playtest feedback: this used to keep sliding at the dash's own
## full speed for a good half-second after the miss was already decided
## (_update_locomotion's dash-override branch stops as soon as _bump_dash_
## timer hits zero, but nothing had ever reset the velocity IT had already
## set, so normal locomotion's own braking curve took over from wherever
## that left off) — zeroing horizontal velocity here means the fall starts
## from a dead stop exactly where the whiff happened, not several metres
## further on.
func _resolve_bump_miss() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_knockdown(_bump_dash_direction, Tuning.BUMP_MISS_STUN_DURATION)
	_apply_knockdown_hop()


## The vertical half of "add a bit of gravity" (playtest feedback on the
## bump rework — an all-horizontal slide read as floaty). A small upward
## pop, then real gravity pulls it back down over BUMP_KNOCKDOWN_HOP_
## DURATION (see _knockdown_hop_timer's own doc comment for why the
## floor-snap bite in _physics_process has to be suspended for this to
## actually arc rather than being cancelled the next frame). Scoped to
## bump's two knockdown call sites only — tackle's own knockdown feel
## wasn't part of this report.
func _apply_knockdown_hop() -> void:
	velocity.y = Tuning.BUMP_KNOCKDOWN_HOP_SPEED
	_knockdown_hop_timer = Tuning.BUMP_KNOCKDOWN_HOP_DURATION


## Stand-the-mark (RULES_REFERENCE.md's MARK_STAND_MIN_DISTANCE entry): a
## legal mark obliges the nearest opponent — no player-marking assignment
## exists in this project, so "nearest at the moment of the mark" stands in
## for "whoever the umpire would call the mark against" — to hold their
## ground until this player disposes. Scoped to marks only, not free kicks/
## kick-ins: those already reuse _protected_timer for the taker's own
## immunity, but the broader "every other opponent retreats 10m" rule is a
## separate, bigger piece of work (see FEATURE_AUDIT.md (archived)) left for when
## the rest of the free-kick/set-shot apparatus gets built.
func _apply_stand_the_mark() -> void:
	var opponent := _nearest_opponent()
	if opponent == null:
		return
	# The mark itself is where this player is standing right now — the catch
	# spot, captured before _begin_mark_retreat() walks them back off it.
	# Put the man on the mark a metre goal-side of that (this player's
	# attacking direction) so the two capsules don't overlap as the taker
	# starts their retreat from the same point.
	var attack_x := 1.0 if team == Tuning.Team.HOME else -1.0
	var mark_spot := Vector3(
		global_position.x + attack_x * Tuning.MARK_STAND_GOAL_SIDE_OFFSET,
		0.0, global_position.z)
	opponent.stand_the_mark(Tuning.MARK_HOLD_DURATION, mark_spot)
	if opponent not in _frozen_opponents:
		_frozen_opponents.append(opponent)


## The general "get back 10 metres" rule (Tuning.FREE_KICK_RETREAT_
## DISTANCE) — every opponent within range of THIS player's current
## position, not just the one _apply_stand_the_mark() names. Called from
## grant_protection() itself so all four moments that grant it (a legal
## mark, a protected kick-in, a holding-the-ball free kick, an out-on-the-
## full free kick) get the same retreat for free, with nothing extra
## needed at any of those call sites.
func _apply_retreat_freeze(duration: float) -> void:
	for other in SpatialQuery.opponents_within(self, Tuning.FREE_KICK_RETREAT_DISTANCE):
		other.stand_the_mark(duration)
		if other not in _frozen_opponents:
			_frozen_opponents.append(other)


func _release_frozen_opponents() -> void:
	for opponent in _frozen_opponents:
		if is_instance_valid(opponent):
			opponent.release_stand_the_mark()
	_frozen_opponents.clear()


## Shared "closest player matching a filter" search behind every tackle/
## smother/bump/stand-the-mark lookup — one place to change if the filter
## itself ever needs to (e.g. excluding stunned players), instead of six
## separately-maintained copies of the same loop.
## `max_dist` is INF for callers that want the nearest regardless of range
## and apply their own distance test afterward (e.g. tackle lunge's wider
## commit range vs. the standing tackle radius). Thin wrapper over
## SpatialQuery (which iterates PlayerRegistry, not a group scan).
func _nearest_player(max_dist: float, predicate: Callable) -> PlayerController:
	return SpatialQuery.nearest_where(global_position, self, max_dist, predicate)


func _nearest_opponent() -> PlayerController:
	return SpatialQuery.nearest_opponent(self)


func _nearest_opposing_carrier() -> PlayerController:
	return SpatialQuery.nearest_opposing_carrier(self)


## Called on the bumped player, by the bumper, on every connect (clean or
## mistimed) — a knockback that overrides normal movement until it decays
## (see _update_locomotion) plus a stun. Never strips the ball, distinct
## from a tackle (real AFL: dispossession is a tackle's job) — the ball
## stays carried even through a clean connect's full knockdown. A clean
## connect layers _knockdown() on top of this from _resolve_bump_contact
## (the carrier goes all the way down, not just knocked off balance); this
## function by itself only ever does the physics side.
func receive_bump(impulse: Vector3, stun_duration: float, _by: PlayerController) -> void:
	_knockback = Vector3(impulse.x, 0.0, impulse.z)
	_stun_timer = maxf(_stun_timer, stun_duration)


# ── Marking ──────────────────────────────────────────────────────────
# Design brief priority 2: a three-tier contextual catch, resolved by a
# reach-radius/timing test against the ball's live position rather than a
# probability roll (RULES_REFERENCE.md §3, same physical-not-scripted
# stance tackling already follows). Safe (A, held) plants and waits for the
# ball to arrive; Running (X, tapped) snap-grabs at pace with a tighter
# margin; Aggressive (Y, tapped) commits to a real jump. The same A button
# becomes a ground pickup once the ball isn't airborne — the brief's "ball
# state + player state + proximity + input, not just the button" framing.

## Every condition that makes a mark attempt a non-starter regardless of
## ball state — shared between _update_marking (the real resolution path)
## and live_mark_prompt (the UI hint) so the two can't silently disagree
## about when a mark is actually live. They used to: live_mark_prompt had
## its own, incomplete copy of this that never checked _gather_cooldown
## (0.45s "before you can regather your own kick," set on every disposal —
## see _dispose()), so the badge/ring briefly read as live for a player
## standing right where they just kicked from, before the ball had gone
## anywhere. _update_marking already enforced this correctly; the prompt
## just wasn't asking the same question.
##
## `ball` is optional (live_mark_prompt/_update_marking both already have
## it in hand) so this extends beyond the flat GATHER_COOLDOWN timer: user
## report — "I still see the flash on kick, it happens half a second after
## I've kicked it" — GATHER_COOLDOWN alone only guarantees the block lifts
## after a fixed 0.45s, with no guarantee the ball has actually gone
## anywhere by then (a short or blocked kick can still be sitting well
## inside every tier's reach at that exact instant). This project only
## ever has one ball in play, and Ball.last_disposer() tracks who most
## recently launched it — so while it's still this same player's own
## disposal *and* it hasn't covered Tuning.MARK_SELF_CLEAR_DISTANCE yet,
## the block holds regardless of how much time has passed. A teammate (or
## the coach, in a training drill) is a different `last_disposer()`, so
## this never blocks a genuine incoming ball from someone else.
func _mark_attempt_blocked(ball: Ball = null) -> bool:
	if is_carrying() or _stun_timer > 0.0 or _action != Tuning.Action.NONE:
		return true
	if _gather_cooldown > 0.0:
		return true
	if is_instance_valid(ball) and ball.last_disposer() == self \
			and ball.distance_since_launch() < Tuning.MARK_SELF_CLEAR_DISTANCE:
		return true
	return false


func _update_marking(delta: float) -> void:
	var ball := _live_ball()
	if _mark_attempt_blocked(ball):
		_mark_readying = false
		return

	if not is_instance_valid(ball) or ball.is_held:
		_mark_readying = false
		return

	if ball.is_airborne():
		_try_spoil(ball)
		_update_aerial_contest(ball, delta)
	else:
		# The one Safe-miss detection point: this player was genuinely
		# holding (readying) a Safe attempt and the ball has now touched
		# down uncaught — a real drop, worth the same feedback trio a
		# failed Running/Aggressive attempt gets. Deliberately scoped to
		# just this common case, not every theoretical way a held Safe
		# attempt can end (stunned mid-hold, an opponent beats them to a
		# loose ball first) — those stay silent, same as they already are
		# today, rather than chasing every exit path for a tier whose whole
		# point is staying simple.
		if _mark_readying and _brain is HumanBrain:
			InputManager.rumble(Tuning.RUMBLE_MARK_MISS)
			mark_missed.emit(Tuning.Action.MARK_SAFE)
			_begin(Tuning.Action.MARK_SAFE_MISS)
			_mark_readying = false
			return   # whiff reaction owns this frame — don't also attempt a ground pickup under it
		_mark_readying = false
		_update_ground_pickup(ball, delta)


## Punch/Spoil (LT tap, not carrying, near an aerial contest): knocks a
## contestable ball off its line rather than controlling it. No target
## player to name — physically deflecting the ball is enough on its own to
## spoil whoever else was about to mark it, since their own reach test
## (_ball_in_catch_reach) reads the ball's real position/velocity, which
## this has just changed. wants_spoil() is already edge-triggered (one tap,
## one attempt); the cooldown on top of that is what stops a volley of fast
## repeat taps from re-punching the same ball again a few frames later,
## faster than a real swing could reset.
func _try_spoil(ball: Ball) -> void:
	if _spoil_cooldown > 0.0 or not _brain.wants_spoil():
		return
	if ball.global_position.distance_to(_carry_point.global_position) > Tuning.SPOIL_RADIUS:
		return
	_spoil_cooldown = Tuning.SPOIL_COOLDOWN
	var away := ball.global_position - global_position
	away.y = 0.4   # a real punch knocks it up and away, not flat along the ground
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.UP
	ball.knock(away * Tuning.SPOIL_IMPULSE_SPEED * ball.mass)


## Safe branch splits on brain type — a HumanBrain gets the graded timing
## treatment (press rumble on the rising edge of the hold, reach narrowed
## by how well the hold's timing lines up — see mark_timing_offset), an
## AIBrain gets the exact original unconditional-reach check, byte for
## byte. Deliberate, not an oversight: AI marking is a documented, minimal
## stub (FEATURE_AUDIT.md (archived)) that this feature isn't meant to touch, and
## AI never taps Running/Aggressive by default (AIBrain only does behind
## Tuning.AI_MARK_USE_CUE_MODEL, off — and those two tiers are graded the
## same for every brain anyway), so only Safe needs the split.
func _update_aerial_contest(ball: Ball, _delta: float) -> void:
	if _brain.wants_mark_safe():
		if _brain is HumanBrain:
			# _mark_readying still holds *last* frame's value here — reading
			# it before the unconditional assignment below is what makes
			# this a rising-edge check with no extra state of its own.
			if not _mark_readying:
				InputManager.rumble(Tuning.RUMBLE_MARK_PRESS)
			_mark_readying = true
			var mult := _timing_reach_mult(mark_timing_offset(ball, Tuning.Action.MARK_SAFE),
				Tuning.MARK_SAFE_IDEAL_WINDOW, Tuning.MARK_SAFE_OK_WINDOW)
			if mult > 0.0 and _ball_in_catch_reach(ball, Tuning.MARK_SAFE_REACH_SCALE * mult):
				_complete_mark(ball, Tuning.Action.MARK_SAFE)
		else:
			_mark_readying = true
			if _ball_in_catch_reach(ball, Tuning.MARK_SAFE_REACH_SCALE):
				_complete_mark(ball, Tuning.Action.MARK_SAFE)
		return
	_mark_readying = false

	if _brain.wants_mark_running():
		_attempt_running_mark(ball)
		return

	# Gate on distance/flight-distance *before* consulting the brain —
	# consume_buffered_press() (what wants_mark_aggressive() calls under the
	# hood) erases the buffered press the instant it's read, per its own
	# doc comment: "callers must only call this at the point they are
	# actually about to act on it." With the brain check first (short-
	# circuit `and`), a press read on a frame where the ball was still a
	# hair outside MARK_CONTEST_RANGE or MIN_FLIGHT_DISTANCE got silently
	# eaten — _begin_aggressive_mark() never fired, but the buffer was
	# already gone, so a later frame (ball now genuinely in range) saw
	# nothing left to consume. That reads to the player as "I timed it
	# right and nothing happened" — issue 2's exact symptom, since the ring
	# cue's own "press now" instant is timed off mark_timing_offset() (see
	# MarkPrompt._press_target_offset), not off this distance gate, so the
	# two can legitimately disagree by a frame or two on a fast/steep
	# delivery. Checking the gates first means a press that arrives early
	# stays buffered (Tuning.INPUT_BUFFER_WINDOW) until the ball is
	# actually in range, instead of being thrown away.
	if ball.global_position.distance_to(_carry_point.global_position) <= Tuning.MARK_CONTEST_RANGE \
			and ball.distance_since_launch() >= Tuning.MARK_AGGRESSIVE_MIN_FLIGHT_DISTANCE \
			and _brain.wants_mark_aggressive():
		_begin_aggressive_mark()


## Running's tap and its resolution are the same instant (unlike Aggressive,
## whose jump defers resolution to a later contact frame — see
## _resolve_aggressive_mark), so timing is graded right here, once. A tap
## that fails outside MARK_CONTEST_RANGE is treated as no attempt at all
## (silent, matching today) rather than a graded miss — the range gate is
## the same "is this even live" test _update_aerial_contest's own
## Aggressive branch already uses, not a new number.
func _attempt_running_mark(ball: Ball) -> void:
	var mult := _timing_reach_mult(mark_timing_offset(ball, Tuning.Action.MARK_RUNNING),
		Tuning.MARK_RUNNING_IDEAL_WINDOW, Tuning.MARK_RUNNING_OK_WINDOW)
	if mult > 0.0 and _ball_in_catch_reach(ball, Tuning.MARK_RUNNING_REACH_SCALE * mult):
		_complete_mark(ball, Tuning.Action.MARK_RUNNING)
		return
	if ball.global_position.distance_to(_carry_point.global_position) <= Tuning.MARK_CONTEST_RANGE:
		if _brain is HumanBrain:
			InputManager.rumble(Tuning.RUMBLE_MARK_MISS)
		mark_missed.emit(Tuning.Action.MARK_RUNNING)
		_begin(Tuning.Action.MARK_RUNNING_MISS)


## A — Ground Pickup once the ball is loose rather than in flight (design
## brief): a deliberate reach, wider and speed-responsive versus the
## passive walk-over _try_gather() above, not an instant snap onto the ball.
func _update_ground_pickup(ball: Ball, _delta: float) -> void:
	if not _brain.wants_mark_safe():
		return
	if ball.linear_velocity.length() > Tuning.GATHER_MAX_BALL_SPEED:
		return
	if ruck_contest_locked():
		return
	var reach := Tuning.GROUND_PICKUP_RADIUS + _speed * Tuning.GROUND_PICKUP_LUNGE_PER_SPEED
	var to_ball := ball.global_position - _carry_point.global_position
	to_ball.y = 0.0
	if to_ball.length() <= reach:
		_complete_gather(ball)


## Resolved immediately rather than deferred through the _action/contact
## machinery below: Safe/Running only ever call this once they already know
## the catch connects, so the "attempt" and the "outcome" are the same
## event. _begin() just plays the catch/cradle animation after the fact.
func _complete_mark(ball: Ball, tier: Tuning.Action) -> void:
	# Cosmetic: hands the animation layer the ball's state while it's still
	# where it was caught (the gather below snaps it into the hands), so it
	# can pick a low / overhead / over-the-shoulder / braced variant. The
	# catch is already decided; nothing reads this back.
	_animation.note_mark_ball(ball)
	_finish_mark_catch(ball, tier)
	_mark_readying = false
	if tier == Tuning.Action.MARK_SAFE:
		# A small reactive hop on the catch itself — see Tuning.MARK_SAFE_
		# HOP_SPEED's own comment for why Safe gets this and not a real jump.
		_pending_jump_speed = Tuning.MARK_SAFE_HOP_SPEED
	_begin(tier)


## Shared tail for a legal-or-not catch once the gather itself has already
## happened — protection + stand-the-mark (only on a legal mark), rumble,
## and the outcome signal. _complete_mark (Safe/Running) and
## _resolve_aggressive_mark differ only in what leads up to the catch: the
## former already knows it connects before calling this, the latter is
## still mid-air and resolves contact here.
func _finish_mark_catch(ball: Ball, tier: Tuning.Action) -> void:
	var legal_mark := ball.is_mark_eligible()
	_complete_gather(ball)
	if legal_mark:
		grant_protection(Tuning.MARK_HOLD_DURATION)
		_apply_stand_the_mark()
		_begin_mark_retreat()
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_MARK)
	mark_caught.emit(tier, legal_mark)


## Walking back off the mark (Tuning.MARK_RETREAT_DISTANCE). "Back" is the
## team's own defensive direction — away from the goal being attacked —
## which is what backwards means from a kicker's point of view regardless
## of which way they happened to be facing when they took the grab. HOME
## attacks +X (Tuning's axis convention), so HOME retreats toward -X.
##
## Only ever started from a legal mark: a scrambled catch in general play
## isn't a mark and has no mark to walk off.
func _begin_mark_retreat() -> void:
	var attack_x := 1.0 if team == Tuning.Team.HOME else -1.0
	_mark_retreat_dir = Vector3(-attack_x, 0.0, 0.0)
	_mark_retreat_remaining = Tuning.MARK_RETREAT_DISTANCE
	# Face the goal being attacked while walking back off it — see this
	# var's own comment just above. _update_facing() turns the body toward
	# _heading every frame regardless of which branch of _update_locomotion
	# is actually driving the feet, so this is the one line that needs to
	# change for the retreat to turn and look at goal.
	_heading = Vector3(attack_x, 0.0, 0.0)


## Public entry to the walk-back, for the free-kick / turnover restarts that
## should read the same as a mark — holding the ball, run too far, out on
## the full (see FullGame._award_possession_at). A goal-square kick-in
## deliberately does NOT call this: the kicker is already on the line with
## nowhere to back up to.
func begin_mark_retreat() -> void:
	_begin_mark_retreat()


func _end_mark_retreat() -> void:
	_mark_retreat_remaining = 0.0
	_mark_retreat_dir = Vector3.ZERO


func is_retreating_from_mark() -> bool:
	return _mark_retreat_remaining > 0.0


## Whether goal_set_shot should do anything right now: still under mark/
## free-kick protection (_protected_timer — the same primitive a legal mark
## or a protected kick-in already grants) and within Tuning.GOAL_SET_SHOT_
## MAX_DISTANCE of the goal LINE, not whatever lateral-biased aim point an
## actual kick might use — a straight shot-distance read, same as AIBrain's
## own dist check in _think_carrying.
## Public read for UI (DebugHud's goal-shot hint chip) — same eligibility
## the goal_set_shot press itself is gated on, see _can_take_goal_set_shot.
func can_take_goal_set_shot() -> bool:
	return _can_take_goal_set_shot()


## Lines the set shot up: latch the kick stance, snap aim to the goal, and
## start the shot clock (Tuning.SET_SHOT_CLOCK). The clock re-grants the
## same _protected_timer the mark did, so the kicker can't be tackled while
## lining up, and re-freezes the man on the mark and the 10m crowd for as
## long (stand_the_mark keeps an existing anchor when given none, so the
## man on the mark stays on the mark).
func _arm_goal_set_shot() -> void:
	_goal_set_shot_locked = true
	_charging = true
	var aim_dir := _goal_aim_direction()
	_kick_aim_yaw = atan2(-aim_dir.x, -aim_dir.z)
	_heading = aim_dir
	# Pacing out the run-up: a few metres further back along the line from
	# goal (Tuning.SET_SHOT_RETREAT_EXTRA), on the mark walk-back's own
	# machinery, still facing goal. The stance waits for it like it waits
	# for the walk-back off the mark.
	_mark_retreat_dir = -aim_dir
	_mark_retreat_remaining = Tuning.SET_SHOT_RETREAT_EXTRA
	grant_protection(Tuning.SET_SHOT_CLOCK)
	for opponent in _frozen_opponents:
		if is_instance_valid(opponent):
			opponent.stand_the_mark(Tuning.SET_SHOT_CLOCK)
	# Borrow the normal behind-the-player Chase framing for the shot if
	# the broadcast rig is on FULL_SIDE — a no-op there already if it
	# isn't (see BroadcastCamera.enter_goal_set_shot).
	if is_instance_valid(camera_rig):
		camera_rig.enter_goal_set_shot()


## Clears the set-shot latch and hands the camera back, on every way a set
## shot ends: fired, cancelled, or the ball lost. drop_ball() calls this
## too. It used to clear only _charging, so a set shot broken by a tackle
## left the latch set and the camera stuck in its borrowed Chase framing
## (playtest: stuck behind the player until a throw-in reset things).
func _cancel_goal_set_shot() -> void:
	if _goal_set_shot_locked and is_instance_valid(camera_rig):
		camera_rig.exit_goal_set_shot()
	_goal_set_shot_locked = false


func _can_take_goal_set_shot() -> bool:
	if _protected_timer <= 0.0:
		return false
	var attack_x := 1.0 if team == Tuning.Team.HOME else -1.0
	var dist := absf(attack_x * Tuning.FIELD_HALF_LENGTH - global_position.x)
	return dist <= Tuning.GOAL_SET_SHOT_MAX_DISTANCE


## Flat, normalized direction from the boot to the centre of the goal being
## attacked — what a set shot snaps _kick_aim_yaw (and _heading) to the
## instant it's lined up. Dead centre, not AIBrain._goal_point's lateral
## bias: that bias is for a carry still choosing an angle on the move, a
## set shot is already standing still lining up the middle of the big
## sticks.
func _goal_aim_direction() -> Vector3:
	var attack_x := 1.0 if team == Tuning.Team.HOME else -1.0
	var goal_point := Vector3(attack_x * Tuning.FIELD_HALF_LENGTH, 0.0, 0.0)
	var to_goal := goal_point - _boot_point.global_position
	to_goal.y = 0.0
	if to_goal.length_squared() < 0.0001:
		return _heading
	return to_goal.normalized()


## Y commits to the jump the instant it's pressed, whether or not it will
## actually connect — that commitment is the entire risk of an aggressive
## attempt. The vertical impulse goes through _pending_jump_speed so it survives
## this frame's floor-snap (see _physics_process); everything after that is
## the same gravity integration every other airborne frame already uses —
## no separate jump-arc code, the arc just falls out of it.
func _begin_aggressive_mark() -> void:
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_MARK_PRESS)
	_pending_jump_speed = Tuning.MARK_AGGRESSIVE_JUMP_SPEED
	# Cosmetic, like _complete_mark's: lets the animation layer pick the
	# contested off-balance landing. The leap is already committed.
	_animation.note_mark_ball(_live_ball())
	_begin(Tuning.Action.MARK_AGGRESSIVE)


## Fires at the jump's contact instant (Tuning.ACTION_CONTACT), timed to
## land near its peak reach — see _update_action's dispatch. A clean miss
## leaves the ball untouched: no contact happened, so nothing about its
## flight changes.
##
## Timing is graded *here*, fresh, rather than captured back at the tap in
## _begin_aggressive_mark — the jump always takes the same fixed
## ACTION_CONTACT[MARK_AGGRESSIVE] seconds to reach this instant, so "good
## timing" for this tier really means "the ball's offset is near zero by
## the time the jump peaks," which is exactly what re-reading
## mark_timing_offset() right now measures. That also makes it automatically
## reward the real skill (committing with the right lead time before the
## ball arrives, not stabbing the button as it lands) with no extra state
## carried between the two functions.
func _resolve_aggressive_mark() -> void:
	var ball := _live_ball()
	var mult := 0.0
	if is_instance_valid(ball) and not ball.is_held:
		mult = _timing_reach_mult(mark_timing_offset(ball, Tuning.Action.MARK_AGGRESSIVE),
			Tuning.MARK_AGGRESSIVE_IDEAL_WINDOW, Tuning.MARK_AGGRESSIVE_OK_WINDOW)
	if mult > 0.0 and _ball_in_catch_reach(ball, Tuning.MARK_AGGRESSIVE_REACH_SCALE * mult):
		_finish_mark_catch(ball, Tuning.Action.MARK_AGGRESSIVE)
	else:
		if _brain is HumanBrain:
			InputManager.rumble(Tuning.RUMBLE_MARK_MISS)
		mark_missed.emit(Tuning.Action.MARK_AGGRESSIVE)


## MARK_ASSIST_RADIUS_BONUS is added after the per-tier scale, not before —
## a flat metres bonus applied uniformly to Safe/Running/Aggressive keeps
## their relative difficulty spread intact rather than compressing it.
func _ball_in_catch_reach(ball: Ball, reach_scale: float) -> bool:
	if not ball.is_airborne():
		return false
	var reach := Tuning.MARK_CATCH_RADIUS * reach_scale + Tuning.MARK_ASSIST_RADIUS_BONUS
	return ball.global_position.distance_to(_carry_point.global_position) <= reach


## Live estimate of seconds until the ball reaches this player's hands —
## negative while it's still closing (counting up to zero), or the flat
## Tuning.MARK_TIMING_PAST_PEAK_OFFSET sentinel once it no longer is
## (already arrived, or drifting past/away). Recomputed fresh from the
## ball's current position/velocity on every call rather than predicted
## once ahead of time and cached: this project already has three
## independent hand-rolled forward-simulation copies for three different
## purposes (Ball._integrate_forces itself, KickTrajectory._simulate's
## preview stepper, MarkChallenge._predicted_range's inverse-ballistics
## guess) and a fourth wasn't worth adding here — a live reactive estimate
## is simpler and self-corrects every physics frame if the ball's flight is
## perturbed after launch (catch gravity, a spoil), which a one-shot
## prediction committed to in advance wouldn't.
##
## Public (no leading underscore) because MarkPrompt needs the same number
## the resolution logic uses to draw an honest countdown — same convention
## as live_mark_prompt()/catch_point_position() below, both also written
## for an outside caller.
##
## `tier` scopes the "basically here" arrived-radius check below to the
## reach the *caller* actually cares about — MARK_SAFE/MARK_RUNNING/
## MARK_AGGRESSIVE, or NONE (the default) for a generic/tier-agnostic read
## (e.g. a ruck contest). Multi-trial scripted verification caught a real
## bug from treating every caller alike here: a single shared radius wide
## enough to rescue Aggressive's own frame-skip case (see below) was wide
## enough to read as "arrived" well before the ball was actually inside
## Running's much tighter reach, so Running's same-frame resolution (no
## forward delay to self-correct on, unlike Aggressive) was grading a press
## as ideal-timed while still genuinely out of reach — the ring cue itself
## would tell a real player to press before the ball had actually arrived.
func mark_timing_offset(ball: Ball, tier: Tuning.Action = Tuning.Action.NONE) -> float:
	var to_catch := ball.global_position - _carry_point.global_position
	var dist := to_catch.length()
	if dist < 0.001:
		return 0.0
	# "Basically here" (relative to *this tier's own* reach) beats any
	# velocity-based read, checked first and unconditionally — not just
	# when closing speed happens to be low. A fast crossing (both ball and
	# Running-tier player can easily be moving at several m/s) can swing
	# the radial closing speed from clearly closing to clearly departing
	# within a single 60Hz physics step, so a check gated on "closing speed
	# is currently low" can miss the ball's true closest approach entirely
	# — it can legitimately never sample a frame where closing speed reads
	# inside any narrow band, however wide, right as the two paths cross.
	# Multi-trial scripted verification (many geometries, a real
	# Running-tier player actually moving) caught exactly this: carry-point
	# distance bottomed out well inside reach on a frame where the
	# closing-speed-gated version of this check never fired at all, reading
	# the whole approach as "never arrived." Distance alone doesn't have
	# that blind spot.
	var arrived_radius := Tuning.MARK_TIMING_ARRIVED_RADIUS
	match tier:
		Tuning.Action.MARK_SAFE:
			arrived_radius = Tuning.MARK_CATCH_RADIUS * Tuning.MARK_SAFE_REACH_SCALE + Tuning.MARK_ASSIST_RADIUS_BONUS
		Tuning.Action.MARK_RUNNING:
			arrived_radius = Tuning.MARK_CATCH_RADIUS * Tuning.MARK_RUNNING_REACH_SCALE + Tuning.MARK_ASSIST_RADIUS_BONUS
		Tuning.Action.MARK_AGGRESSIVE, _:
			pass   # the wide, Aggressive-scoped default above already fits
	if dist <= arrived_radius:
		return 0.0
	# Relative to this player's own motion, not just the ball's — matters
	# for a Running mark taken at pace, where closing the gap is a joint
	# effort between the ball's flight and the player's own sprint toward
	# it, not the ball's velocity alone.
	var to_catch_dir := to_catch.normalized()
	var closing_speed := -to_catch_dir.dot(ball.linear_velocity - velocity)
	if closing_speed <= Tuning.MARK_TIMING_MIN_CLOSING_SPEED:
		return Tuning.MARK_TIMING_PAST_PEAK_OFFSET
	# A falling ball's closing speed keeps rising under gravity right up to
	# the catch — a real, physical acceleration, not sensor noise — so a
	# plain dist/closing_speed (constant-velocity) ETA is a systematic
	# under-estimate of urgency: it reads the *slowest* closing speed of
	# the remaining approach (now) and assumes that rate the whole way in.
	# Safe/Running never notice, because they grade the very instant the
	# button is pressed — this is only ever asked "is it here right now,"
	# never "how long until." Aggressive is the one tier that *commits*
	# ACTION_CONTACT[MARK_AGGRESSIVE] (0.4s) ahead of its own resolution
	# (the jump has to physically rise first — see _resolve_aggressive_
	# mark's own comment), so it's the one tier actually relying on this
	# number as a forward prediction, and the bias bit exactly there:
	# scripted verification (a real Ball/PlayerController physics run, not
	# just this comment) showed a steep coach-drill-style delivery's true
	# closest approach landing roughly twice as soon as the plain linear
	# estimate promised, so a jump committed off "offset == -0.4s" was
	# still mid-air, arm still rising, after the ball had already passed
	# and moved on — a real, reproducible cause of "aggressive mark misses
	# on seemingly correct timing," not player error. Folding in gravity's
	# contribution to closing acceleration (constant-acceleration ETA,
	# solved the same way a real trajectory would be — drag omitted, same
	# simplification Ball.predicted_landing_position() already makes for a
	# live in-the-loop estimate) corrects for exactly that rise.
	var closing_accel := -to_catch_dir.dot(Vector3(0.0, -Tuning.GRAVITY, 0.0))
	if absf(closing_accel) > 0.001:
		var discriminant := closing_speed * closing_speed + 2.0 * closing_accel * dist
		if discriminant >= 0.0:
			var eta := (-closing_speed + sqrt(discriminant)) / closing_accel
			if eta > 0.0:
				return -eta
	return -dist / closing_speed


## The physical (never probabilistic — RULES_REFERENCE.md §3) consequence
## of timing accuracy: full reach inside the ideal band, a narrowed one
## inside the wider "contested" band, none at all outside it. One shared
## step function behind all three tiers' timing grading, so they can't
## drift out of sync about what "inside the window" actually means.
func _timing_reach_mult(offset: float, ideal_window: float, ok_window: float) -> float:
	var magnitude := absf(offset)
	if magnitude <= ideal_window:
		return 1.0
	if magnitude <= ok_window:
		return Tuning.MARK_TIMING_OK_REACH_MULT
	return Tuning.MARK_TIMING_MISS_REACH_SCALE


## World position of this player's catch point (their hands, for marking
## purposes) — the same Marker3D carrying already uses. Exposed so Ball's
## catch-gravity assist (_apply_catch_gravity) can find the nearest live
## target without needing its own copy of where "the hands" are.
func catch_point_position() -> Vector3:
	return _carry_point.global_position


## Madden-style contest prompt (polish-pass brief) — the single tier
## actually relevant right now, not every tier that would technically
## connect (an early version of this showed all three simultaneously,
## since Safe's reach always covers Running's narrower one and Aggressive's
## MARK_CONTEST_RANGE is wider again — nearly every live moment had all
## three "live" at once, which is correct but not useful as a prompt).
##
## Reuses the exact reach tests _update_aerial_contest itself resolves
## against, picking exactly one to recommend by the same speed-scale
## reasoning the tiers themselves are already built on (Tuning's "Safe
## plants you properly; Running barely interrupts your stride" comment):
## Running is only the natural read while actually moving at pace: Safe is
## the default the instant you're not; Aggressive is only ever the one
## live option while the ball hasn't reached normal catching reach yet —
## once it has, a leap stops being the natural action even though it
## would still technically connect, so it stops being recommended.
func live_mark_prompt(ball: Ball) -> Tuning.Action:
	# Rulebook §5: the contest prompt is for a ball *kicked* at you, and
	# nothing else. This used to read is_airborne(), which is true of any
	# ball off the ground — so an opponent's handball, or a teammate's
	# handball going past, lit the prompt up in close general play.
	# is_kick_flight() is the same "is this a live, untouched kick" test
	# FullGame's out-on-the-full check already uses, and it subsumes the
	# airborne check: Ball clears the flag the moment the kick lands (and
	# on knock(), so a spoiled ball stops prompting too).
	#
	# Deliberately gated here and not in _mark_attempt_blocked(): taking a
	# teammate's handball out of the air is still a legitimate catch, it
	# just isn't a marking contest. Ball.is_mark_eligible() is what already
	# decides whether a take earns real mark protection (_complete_mark),
	# and it says no to a handball for the same reason.
	if not is_instance_valid(ball) or _mark_attempt_blocked(ball) or not ball.is_kick_flight():
		return Tuning.Action.NONE
	# An opponent's kick still within MARK_STAND_MIN_DISTANCE of the boot is
	# a smother chance, not a mark (playtest: the man on the mark saw A/X/Y
	# light up the instant the kicker struck it). It couldn't be a legal mark
	# anyway: that needs the same 15m. MarkPrompt shows the SMOTHER badge
	# while the kicker is still lining up instead.
	if ball.kick_team() != team and ball.kick_team() != Tuning.Team.NONE \
			and ball.distance_since_launch() < Tuning.MARK_STAND_MIN_DISTANCE:
		return Tuning.Action.NONE
	var running_live :=_ball_in_catch_reach(ball, Tuning.MARK_RUNNING_REACH_SCALE)
	if running_live and _speed > Tuning.JOG_SPEED:
		return Tuning.Action.MARK_RUNNING
	if _ball_in_catch_reach(ball, Tuning.MARK_SAFE_REACH_SCALE):
		return Tuning.Action.MARK_SAFE
	if running_live:
		return Tuning.Action.MARK_RUNNING
	if ball.global_position.distance_to(_carry_point.global_position) <= Tuning.MARK_CONTEST_RANGE \
			and ball.distance_since_launch() >= Tuning.MARK_AGGRESSIVE_MIN_FLIGHT_DISTANCE:
		return Tuning.Action.MARK_AGGRESSIVE
	return Tuning.Action.NONE


# ── Ruck contests ────────────────────────────────────────────────────
# Design brief priority 4: centre bounce, field ball-up and boundary
# throw-in all resolve through the same contest — see Tuning's own "Ruck
# contests" section and FullGame._begin_ruck_contest, which is the one
# place that decides *where* a contest happens and *who* contests it. This
# section only knows how to contest one, the same way regardless of which
# situation nominated it.

## Called by whoever is orchestrating a contest (FullGame._begin_ruck_
## contest) on exactly the two nominated players. Self-expiring — see
## _ruck_contest_timer in _physics_process — so a ruckman can't hold RB's
## Hit-Out meaning past the one contest they were nominated into.
##
## `window` defaults to RUCK_CONTEST_WINDOW; FullGame passes a longer one
## when it nominates at the start of the umpire's throw-up, so the window
## still covers RUCK_CONTEST_WINDOW of live ball after the release.
func set_ruck_contestant(value: bool, window: float = Tuning.RUCK_CONTEST_WINDOW) -> void:
	if value:
		# The nominated ruckmen are placed at the contest — nothing may
		# still be pulling them back toward an earlier tackle.
		_end_tackle_hold()
		_cancel_ragdoll()
	_is_ruck_contestant = value
	_ruck_contest_timer = window if value else 0.0
	if not value:
		_hit_out_armed = false


func is_ruck_contestant() -> bool:
	return _is_ruck_contestant


## True while a ruck contest is live (a centre bounce / field ball-up /
## boundary throw-in) and this player is NOT one of the two nominated
## ruckmen. Used by _try_gather / _update_ground_pickup to keep the
## on-ballers ringed around the contest from just scooping the ball
## straight off the umpire's throw-up, and by AIBrain.update() to hold
## those same non-ruckmen on their positions instead of crashing the pack
## the frame the throw-up is released. The two contestants get first use of
## it; everyone else waits for the tap (FullGame clears the flags early on
## a connected hit-out — see _on_hit_out_resolved) or for the contest
## window to lapse (RUCK_CONTEST_WINDOW, self-expiring). No-op in modes
## with no ruck contests, since nobody is ever a contestant there.
func ruck_contest_locked() -> bool:
	return SpatialQuery.any_other_ruck_contestant(self)


func _update_ruck_contest(_delta: float) -> void:
	if not _is_ruck_contestant or is_carrying() or _stun_timer > 0.0 \
			or _action != Tuning.Action.NONE:
		return
	# The press is read (and latched) before any ball checks. It used to be
	# read only once the ball was airborne, then dropped if the ball was
	# still out of range — consumed and gone — and a press during the
	# umpire's throw-up only waited INPUT_BUFFER_WINDOW (0.12 s), so RB
	# often did nothing (playtest: "the ruck tap is not always activating").
	var fresh := _brain.wants_hit_out()
	if fresh:
		_hit_out_armed = true
	if not _hit_out_armed:
		return
	var ball := _live_ball()
	if not is_instance_valid(ball) or ball.is_held or not ball.is_airborne():
		return
	if ball.global_position.distance_to(_carry_point.global_position) > Tuning.RUCK_CONTEST_JUMP_RANGE:
		return
	# A press made with the ball already live and in range jumps now — the
	# player's own timing. An early (latched) press waits for the toss to
	# slow near its peak, so it can't leap under a ball still climbing.
	if not fresh and ball.linear_velocity.y > Tuning.RUCK_ARMED_FIRE_MAX_RISE:
		return
	_hit_out_armed = false
	_begin_hit_out()


## Commits to the leap immediately, exactly like _begin_aggressive_mark —
## same _pending_jump_speed hand-off into the existing gravity integration, no
## separate arc code (design brief: "reuse the existing aggressive-mark
## jump impulse pattern... let the existing gravity integration handle the
## jump arc").
func _begin_hit_out() -> void:
	_pending_jump_speed = Tuning.MARK_AGGRESSIVE_JUMP_SPEED
	_begin(Tuning.Action.HIT_OUT)


## Fires at the jump's contact instant, same timing as an aggressive mark's
## own resolution (Tuning.ACTION_CONTACT — HIT_OUT copies MARK_AGGRESSIVE's
## row verbatim, see Tuning's comment there). A palm, not a catch: knocks
## the ball away rather than gathering it, same knock() primitive spoil/
## smother already use for "an external hit that doesn't take control".
## Directed by _hit_out_aim_dir (captured on the RB press, see _begin), or
## by the right stick if it's held right now at contact — so a ruckman taps
## to a runner, not just straight off the body.
func _resolve_hit_out() -> void:
	var ball := _live_ball()
	var connected := is_instance_valid(ball) and not ball.is_held \
		and ball.global_position.distance_to(_carry_point.global_position) <= Tuning.RUCK_HIT_OUT_REACH
	if connected:
		var direction := _brain.hit_out_aim(self)
		if direction.length_squared() < 0.0001:
			direction = _hit_out_aim_dir if _hit_out_aim_dir.length_squared() > 0.0001 \
				else -global_transform.basis.z
		direction = direction.normalized()
		ball.knock(direction * Tuning.RUCK_HIT_OUT_SPEED + Vector3.UP * Tuning.RUCK_HIT_OUT_UP_SPEED)
	hit_out_resolved.emit(self, connected)


## Right stick (brain), then left stick, then body-forward — see _begin's
## HIT_OUT capture.
func _hit_out_aim() -> Vector3:
	var aim := _brain.hit_out_aim(self)
	if aim.length_squared() > 0.0001:
		return aim
	return _wish_dir if _wish_dir.length_squared() > 0.0001 else -global_transform.basis.z


## The one ball in the scene, found by group rather than a wired reference —
## every mode's Ball adds itself to the "ball" group (see Ball._ready()), so
## this needs no per-mode setup the way AIBrain.ball does.
func _live_ball() -> Ball:
	var nodes := get_tree().get_nodes_in_group(&"ball")
	return nodes[0] as Ball if not nodes.is_empty() else null


# ── Disposal ─────────────────────────────────────────────────────────

## LT-hold-stance / RT-tap-execute (design brief's CONTROLS section), not
## the old single-button hold-then-release-to-fire: wants_kick() (LT) only
## ever charges and aims; wants_kick_execute() (RT) is the one thing that
## actually fires the kick. Releasing LT without ever tapping RT cancels —
## no kick, charge discarded — where the old model would have fired on
## release regardless.
##
## RT on its own (never having held LT this attempt) doesn't no-op any
## more — it hip-fires: whatever the body's facing, fixed power, extra
## scatter. Matches P1's actual structure for the aimed case (LT/enter_
## aim_mode gates the aim cursor there too, confirmed by re-reading it —
## this was never meant to lose that gate); the hip-fire option itself has
## no P1 equivalent, it's this project's own ADS-vs-hip-fire addition.
func _update_charge(delta: float) -> void:
	# Still walking back off the mark — get off it before going at goal.
	# Handball and simply running are untouched, so "play on" stays
	# available the moment the retreat finishes; it's the set shot that has
	# to wait for it (Tuning.MARK_RETREAT_DISTANCE).
	# The same for a set shot's run-up: the kick's already been called for.
	if _action != Tuning.Action.NONE or _stun_timer > 0.0 \
			or _mark_retreat_remaining > 0.0 or _set_shot_run_up_remaining > 0.0:
		_kick_trajectory.update_preview(false, Vector3.ZERO, Vector3.ZERO)
		return

	# Set shot for goal: a tap of goal_set_shot, not a hold, so it needs its
	# own latch (_goal_set_shot_locked) to keep the kick-stance branch below
	# alive on every later frame exactly as if wants_kick() itself were
	# being held — see that var's own comment. Only arms within range and
	# while still under mark/free-kick protection (_can_take_goal_set_shot);
	# a stray press outside both does nothing, same as pressing kick_stance
	# this frame already not-carrying would.
	if _brain.wants_goal_set_shot() and is_carrying() and not _charging \
			and _can_take_goal_set_shot():
		_arm_goal_set_shot()

	if (_brain.wants_kick() or _goal_set_shot_locked) and is_carrying():
		if not _charging:
			_charging = true
			# Wherever the camera/crosshair is currently pointing, not body
			# facing — see _current_look_yaw(). Camera turned toward goals
			# while still running a different line, then pull the trigger:
			# the kick starts aimed at goals, not wherever your legs
			# happened to be carrying you.
			_kick_aim_yaw = _current_look_yaw()
		var override := _brain.kick_charge_override()
		if override >= 0.0:
			# Power is wherever the trajectory line currently reaches to —
			# a gamepad's right stick sets it directly and live, not a
			# value that only ever ramps up with no way back down.
			_kick_charge = override
		elif not (_brain is HumanBrain):
			# AI has no stick/mouse to read a live position from, so it
			# keeps the original hold-duration ramp. A human on keyboard/
			# mouse gets a live, reversible read too now — see
			# _update_kick_aim(), just below, not a ramp at all any more.
			_kick_charge = minf(1.0, _kick_charge + delta / Tuning.KICK_CHARGE_TIME)
		_update_kick_aim(delta)
		if _brain.wants_kick_execute():
			_charging = false
			if _goal_set_shot_locked:
				# A set shot walks in first (Tuning.SET_SHOT_RUN_UP_*): the
				# run-up in _update_locomotion begins the kick at its end and
				# hands the camera back then. Charge and aim stay as set now.
				_set_shot_run_up_remaining = Tuning.SET_SHOT_RUN_UP_DISTANCE
				_set_shot_run_up_dir = _yaw_direction(_kick_aim_yaw)
			else:
				_cancel_goal_set_shot()
				_begin(Tuning.Action.KICK)
	elif _charging:
		# LT released without RT — cancel, no kick.
		_charging = false
		_cancel_goal_set_shot()
		_kick_charge = 0.0
	elif _brain.wants_kick_execute() and is_carrying():
		_hip_fire_kick = true
		_kick_charge = Tuning.KICK_HIP_FIRE_CHARGE
		# Fresh body-facing every time — deliberately _facing_yaw, not
		# _current_look_yaw(): hip-fire is specifically "didn't aim down
		# sights," so it stays tied to the body the way it always has,
		# not wherever the camera happens to be pointed. Also not whatever
		# _kick_aim_yaw was last left at by an earlier cancelled ADS
		# attempt — _kick_parameters() reads _kick_aim_yaw unconditionally,
		# so this is what actually makes a hip-fire go "wherever the
		# body's facing" rather than some stale aim.
		_kick_aim_yaw = _facing_yaw
		_begin(Tuning.Action.KICK)

	if _brain.wants_handball() and is_carrying():
		_begin(Tuning.Action.HANDBALL)
	elif _brain.wants_bounce() and is_carrying():
		_begin(Tuning.Action.BOUNCE)

	# Only the human player gets the on-screen cue — an AI doesn't need to
	# see its own aim, and it'd be a lot of idle preview updates for
	# nothing on every AI-controlled player every frame.
	if _charging and _brain is HumanBrain:
		var params := _kick_parameters(_kick_charge)
		_kick_trajectory.update_preview(true, params.origin, params.launch_velocity)
	else:
		_kick_trajectory.update_preview(false, Vector3.ZERO, Vector3.ZERO)


## Right stick (or mouse, off the same look input the camera would
## otherwise be reading — see BroadcastCamera._is_target_aiming) swings
## the aim yaw independently of where the body is facing or heading. AI
## has nothing to feed this, and no camera assigned either (see
## _current_look_yaw()'s fallback), so it simply never moves past the
## body-forward snapshot _update_charge took when stance began — exactly
## its old always-body-forward kick, unchanged by any of this.
func _update_kick_aim(delta: float) -> void:
	if not (_brain is HumanBrain):
		return
	var stick := InputManager.get_look_vector()
	var mouse := InputManager.take_mouse_look()
	_kick_aim_yaw -= stick.x * deg_to_rad(Tuning.KICK_AIM_YAW_SPEED) * delta \
		+ deg_to_rad(mouse.x)
	if InputManager.device != InputManager.Device.GAMEPAD:
		# No stick position for kick_charge_override() to read on keyboard
		# (see that function) — power comes from here instead, the same
		# per-axis split as aim yaw just above: arrow up/down is a held
		# rate (stick.y, the same vector's other axis, paced the same as
		# the hold-ramp everyone else still uses), mouse is a raw
		# per-frame delta. Both push the reach up AND down live, same
		# spirit as a gamepad's stick position — replaces holding K alone
		# auto-ramping power up with no way back down.
		_kick_charge = clampf(_kick_charge
			+ stick.y * delta / Tuning.KICK_CHARGE_TIME
			- mouse.y * Tuning.KICK_MOUSE_REACH_SENSITIVITY, 0.0, 1.0)
	_apply_aim_assist(delta)


## Where the camera (and the on-screen crosshair — see KickCrosshair,
## instantiated by whichever mode owns this scene) is currently pointing,
## flattened to yaw. What a freshly-entered aim stance snaps to instead of
## body facing — see _update_charge. Falls back to _facing_yaw with no
## camera assigned (AI, and this node under test headless — same reasoning
## HumanBrain.wish_direction's own camera fallback documents) or if the
## camera happens to be looking close enough to straight down/up that a
## flattened forward has nothing meaningful left to point along.
##
## Also falls back to _facing_yaw in BroadcastCamera.Mode.FULL_SIDE: that
## rig looks across the field at the play from a fixed side-on mount, not
## wherever the player means to kick, so its forward is meaningless as an
## aim base there (playtest report: the aim/trajectory snapped toward the
## far side of the field — the camera's own forward, rendered dead ahead
## on screen since screen centre always *is* camera forward — rather than
## anywhere near the body's own facing). Body facing is exactly what the
## stick/mouse then swings away from in _update_kick_aim regardless of
## camera mode, so this is the one spot that needs to know about FULL_SIDE
## at all.
func _current_look_yaw() -> float:
	if not is_instance_valid(camera):
		return _facing_yaw
	if is_instance_valid(camera_rig) and camera_rig.mode == BroadcastCamera.Mode.FULL_SIDE:
		return _facing_yaw
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return _facing_yaw
	return atan2(-forward.x, -forward.z)


## Soft pull toward the nearest teammate roughly in the aim direction — a
## per-frame blend toward their angle, not a snap-to (design brief: "not
## lock on but a small aim assist"). Ported from P1's apply_aim_assist:
## same k = min(1, STRENGTH * dt) blend fraction: dimensionless, so it
## carries over even though P1 blends a 2D screen cursor and this blends
## a yaw angle. Gamepad only, matching P1's controller-only gate — a
## mouse already points exactly where aimed, so assist would only fight
## it, and it's the stick's indirection this is actually compensating for.
##
## Off during a set shot: the target is the goal, and the assist was
## dragging the aim toward whichever teammate drifted into the cone
## (playtest: "it was following a player walk as I was in set shot mode").
func _apply_aim_assist(delta: float) -> void:
	if InputManager.device != InputManager.Device.GAMEPAD or _goal_set_shot_locked:
		return
	var target := _nearest_teammate_for_assist()
	if target == null:
		return
	var to_target := target.global_position - _boot_point.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-to_target.x, -to_target.z)
	var k := minf(1.0, Tuning.KICK_AIM_ASSIST_STRENGTH * delta)
	_kick_aim_yaw = lerp_angle(_kick_aim_yaw, target_yaw, k)


## Nearest teammate within KICK_AIM_ASSIST_RANGE and KICK_AIM_ASSIST_CONE_
## DEG of the *current* aim direction — cone gates it to "roughly where
## you're already pointing", same spirit as P1's radius gate around the
## cursor, adapted from screen-space pixels to a world-space angle since
## there's no 2D cursor here to measure a pixel radius around.
func _nearest_teammate_for_assist() -> PlayerController:
	var aim_dir := _yaw_direction(_kick_aim_yaw)
	var cone := deg_to_rad(Tuning.KICK_AIM_ASSIST_CONE_DEG)
	var best: PlayerController = null
	var best_dist := Tuning.KICK_AIM_ASSIST_RANGE
	for other in PlayerRegistry.all():
		if other == self or other.team != team:
			continue
		var to_other := other.global_position - global_position
		to_other.y = 0.0
		var dist := to_other.length()
		if dist < 0.01 or dist > best_dist:
			continue
		if aim_dir.angle_to(to_other.normalized()) > cone:
			continue
		best_dist = dist
		best = other
	return best


func is_kick_aiming() -> bool:
	return _charging


## True from the moment a KICK's swing begins until the ball actually
## leaves at its contact instant — see _update_smother, which reads this
## alongside is_kick_aiming() to find a target whose kick can still be
## blocked.
func is_mid_kick_swing() -> bool:
	return _action == Tuning.Action.KICK and not _action_fired


func is_mark_readying() -> bool:
	return _mark_readying


## The mark tier this player has already committed to and that hasn't
## resolved yet: MARK_SAFE while A is held, MARK_AGGRESSIVE from the Y jump
## until its contact frame. NONE otherwise (Running resolves on its own
## press frame, so there is nothing in between to report). MarkPrompt reads
## this so the badge shows the button actually pressed, not whichever tier
## live_mark_prompt() would recommend (playtest: "Y still comes up" while
## holding A).
func committed_mark_tier() -> Tuning.Action:
	if _mark_readying:
		return Tuning.Action.MARK_SAFE
	if _action == Tuning.Action.MARK_AGGRESSIVE and not _action_fired:
		return Tuning.Action.MARK_AGGRESSIVE
	return Tuning.Action.NONE


func protected_seconds() -> float:
	return _protected_timer


func _yaw_direction(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _begin(action: Tuning.Action) -> void:
	if _action != Tuning.Action.NONE:
		return
	if action == Tuning.Action.HANDBALL:
		# "Toward wherever Left stick is currently held" (CONTROLS section),
		# captured now rather than at _dispose()'s later contact time, and
		# falling back to body-forward if the stick is neutral at the
		# instant of the press.
		_handball_aim_dir = _wish_dir if _wish_dir.length_squared() > 0.0001 \
			else -global_transform.basis.z
	elif action == Tuning.Action.HIT_OUT:
		# Captured on the RB press so a ruckman can palm it to a runner
		# rather than only straight off the body: the right stick for a
		# human (PlayerBrain.hit_out_aim — playtest: RB + right stick, so
		# the left stick stays free to move), else the left stick, else
		# body-forward. _resolve_hit_out re-reads the right stick at
		# contact, so a flick during the leap still counts.
		_hit_out_aim_dir = _hit_out_aim()
	_action = action
	_action_elapsed = 0.0
	_action_fired = false
	_animation.play_action(action)
	action_started.emit(action)


## Disposal fires partway through its animation, not at the start and not
## at the end — the boot meets the ball when the boot meets the ball.
## Right now the contact instant is a constant that the placeholder
## animation is generated to match; once real Mixamo animations land, it
## becomes a call track on the animation itself and these constants go
## away. The rest of this function does not change either way.
func _update_action(delta: float) -> void:
	if _action == Tuning.Action.NONE:
		return
	_action_elapsed += delta

	var contact := Tuning.action_contact_time(_action)
	if not _action_fired and _action_elapsed >= contact:
		_action_fired = true
		match _action:
			Tuning.Action.MARK_AGGRESSIVE:
				_resolve_aggressive_mark()
			Tuning.Action.HIT_OUT:
				_resolve_hit_out()
			Tuning.Action.MARK_SAFE, Tuning.Action.MARK_RUNNING, \
					Tuning.Action.MARK_SAFE_MISS, Tuning.Action.MARK_RUNNING_MISS, \
					Tuning.Action.TACKLED, Tuning.Action.TACKLE_GRAB, Tuning.Action.SMOTHERED, \
					Tuning.Action.SMOTHER_DIVE, Tuning.Action.TACKLE_HELD, \
					Tuning.Action.TACKLE_TAKEDOWN, Tuning.Action.KNOCKED_BACK, \
					Tuning.Action.TACKLE_SLING:
				pass   # already resolved in _update_marking()/_get_tackled()/_get_smothered(); this leg is cosmetic only
			_:
				_dispose()

	if _action_elapsed >= Tuning.action_duration(_action):
		_action = Tuning.Action.NONE
		_action_elapsed = 0.0


## Shared elevation/speed -> direction/launch_velocity math every
## disposal action goes through, so kicks, handballs and bounces can't
## quietly diverge in how "how hard, how high" becomes a velocity.
## `horizontal_dir` is the caller's aim source made explicit (kick: the
## free-aim yaw; handball: wherever the stick was held; bounce: body
## facing) — this function no longer assumes body-forward itself, so it
## can't quietly default to the wrong source for whichever action is
## calling it.
func _launch_from(origin: Vector3, horizontal_dir: Vector3, elevation_deg: float,
		speed_out: float, carry_momentum := true) -> Dictionary:
	var elevation := deg_to_rad(elevation_deg)
	var direction := (horizontal_dir * cos(elevation) + Vector3.UP * sin(elevation)).normalized()

	# Carry the player's own momentum into the ball, the way it actually
	# works — a kick on the run goes further than the same kick standing.
	# Not a set shot's: its run-up is the routine, and the kick goes where
	# the standing stance's cue showed (Tuning.SET_SHOT_RUN_UP_*).
	var carried_momentum := Vector3(velocity.x, 0.0, velocity.z) \
		* Tuning.DISPOSAL_MOMENTUM_TRANSFER if carry_momentum else Vector3.ZERO
	return {
		"origin": origin,
		"launch_velocity": direction * speed_out + carried_momentum,
	}


## The exact KICK launch a release at `charge` (0..1) would produce, sans
## accuracy error — the aimed path, not the executed one. Called both by
## the on-screen trajectory cue (every frame while charging, see
## _update_charge) and by _dispose() (once, at execute) so the two can
## never disagree about what "the aim" actually is. Direction comes from
## _kick_aim_yaw, not body facing — see _update_kick_aim.
func _kick_parameters(charge: float, carry_momentum := true) -> Dictionary:
	var elevation_deg := lerpf(Tuning.KICK_MIN_ANGLE, Tuning.KICK_MAX_ANGLE, charge)
	var speed_out := lerpf(Tuning.KICK_MIN_SPEED, Tuning.KICK_MAX_SPEED, charge) * kick_power_scale
	return _launch_from(_boot_point.global_position, _yaw_direction(_kick_aim_yaw),
		elevation_deg, speed_out, carry_momentum)


## Rotates the whole resultant launch vector (aim + carried momentum
## together) by a random amount rather than re-deriving it, so a spread
## kick goes off-line, not further or shorter. Shared by the two things
## that make a kick less than pinpoint — skill (_apply_kick_accuracy) and
## not having aimed down sights at all (the hip-fire spread in
## _dispose()) — so neither can quietly drift out of sync with the other
## about what "how far off" actually means.
func _apply_spread(launch: Dictionary, right: Vector3, spread_deg: float) -> Dictionary:
	if spread_deg <= 0.0:
		return launch
	var spread := deg_to_rad(spread_deg)
	launch.launch_velocity = (launch.launch_velocity as Vector3) \
		.rotated(Vector3.UP, randf_range(-spread, spread)) \
		.rotated(right, randf_range(-spread, spread) * 0.5)
	return launch


## Random aim error from the character's own skill, rolled fresh here
## rather than while charging — the trajectory cue can't show it because
## it isn't knowable ahead of the actual kick. Zero at kick_accuracy ==
## 1.0, up to KICK_ACCURACY_MAX_SPREAD_DEG at 0.0.
func _apply_kick_accuracy(launch: Dictionary, right: Vector3) -> Dictionary:
	var spread_deg := Tuning.KICK_ACCURACY_MAX_SPREAD_DEG \
		* (1.0 - clampf(kick_accuracy, 0.0, 1.0))
	return _apply_spread(launch, right, spread_deg)


func _dispose() -> void:
	if not is_carrying():
		_kick_charge = 0.0
		return

	var ball := _carried_ball
	var right := global_transform.basis.x

	var launch: Dictionary
	var spin: Vector3

	match _action:
		Tuning.Action.KICK:
			launch = _kick_parameters(_kick_charge, not _set_shot_kick)
			_set_shot_kick = false
			# Backspin: the top of the ball travels backwards, which for a
			# ball moving along `forward` is a positive spin about `right`.
			spin = right * Tuning.KICK_BACKSPIN
			launch = _apply_kick_accuracy(launch, right)
			if _hip_fire_kick:
				launch = _apply_spread(launch, right, Tuning.KICK_HIP_FIRE_SPREAD_DEG)
			_hip_fire_kick = false
		Tuning.Action.HANDBALL:
			launch = _launch_from(_carry_point.global_position, _handball_aim_dir,
				Tuning.HANDBALL_ANGLE, Tuning.HANDBALL_SPEED)
			spin = right * Tuning.HANDBALL_SPIN
		Tuning.Action.BOUNCE:
			launch = _launch_from(_carry_point.global_position, -global_transform.basis.z,
				Tuning.BOUNCE_ANGLE, Tuning.BOUNCE_SPEED)
			spin = right * Tuning.HANDBALL_SPIN
		_:
			return

	var origin: Vector3 = launch.origin
	var launch_velocity: Vector3 = launch.launch_velocity
	var flight := launch_velocity.normalized()

	# Placed while the ball is still frozen, then launched — a rigid body
	# should not be teleported once it is awake. Pointing the long axis
	# along the flight path matters because the hull is a spheroid: how
	# the ball is oriented on the way down changes how it lands.
	var up_reference := Vector3.UP if absf(flight.y) < 0.98 else Vector3.FORWARD
	ball.global_transform = Transform3D(Basis.looking_at(-flight, up_reference), origin)
	ball.launch(launch_velocity, launch_velocity.length(), spin, self,
		_action == Tuning.Action.KICK, _action == Tuning.Action.BOUNCE,
		_action == Tuning.Action.HANDBALL)

	_carried_ball = null
	_carry_distance = 0.0
	# Your own bounce is gated by the ball instead — it's yours again once
	# it's back up (Ball.awaiting_own_bounce), not after a fixed wait.
	_gather_cooldown = 0.0 if _action == Tuning.Action.BOUNCE else Tuning.GATHER_COOLDOWN
	_protected_timer = 0.0   # playing on forfeits stand-the-mark protection
	_release_frozen_opponents()
	if _action != Tuning.Action.BOUNCE:
		MatchState.possession = Tuning.Team.NONE
	if _brain is HumanBrain:
		InputManager.rumble(Tuning.RUMBLE_KICK)
	ball_disposed.emit(_action)
	_kick_charge = 0.0
