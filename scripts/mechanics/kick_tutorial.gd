class_name KickTutorial
extends CoachChallenge

## The kicking coach's drill as a step-by-step tutorial, built the same way
## as the tackling coach's (TackleTutorial): a card per step with the
## keyboard and pad controls (step_changed, shown by kick_to_kick.gd), the
## player dismisses it, and the rep runs until it's done. It replaced
## KickChallenge's five shots at a ring (playtest 2026-10-30: "a random
## player currently just spawns in and takes the ball — remove that.
## Instead, have a player lead on different angles: kick to the player
## first, then practice kicking in front of them or to a certain spot").
##
## The teammate is a real PlayerController on a LeadBrain, spawned by
## kick_to_kick.gd for the drill. Each rep puts the ball in the player's
## hands and the teammate KICK_TUTORIAL_LEAD_DISTANCE out, leading:
##   1-3. LEAD_TO: back at you, then 40° off to either side. Clears when
##        they mark it.
##   4.   LEAD_SPACE: across you, with a ring out in front of them. Clears
##        when they mark it in stride (KICK_TUTORIAL_IN_FRONT_MIN past where
##        they were at the kick) or it comes down in the ring.
##   5.   SPOT: no lead, a ring KICK_TUTORIAL_SPOT_DISTANCE out. Clears when
##        it lands in the ring.
## A kick that isn't taken is a retry after KICK_TUTORIAL_RETRY_DELAY. No
## score and no fail state; challenge_ended fires once, at the end, with
## steps cleared over steps.

signal step_changed(step: Dictionary)

enum Kind { LEAD_TO, LEAD_SPACE, SPOT }

const RING_COLOUR := Color(0.95, 0.35, 0.25, 0.85)

## kick_stance is K / right mouse held (pad LT), kick_execute F / left
## mouse (pad RT); the right stick or mouse aims and sets the reach.
const KB_KICK: Array[Dictionary] = [{"keys": "Hold Mouse R", "label": "Aim"},
	{"keys": "Mouse", "label": "Line + reach"}, {"keys": "Mouse L", "label": "Kick"}]
const PAD_KICK: Array[Dictionary] = [{"keys": "Hold LT", "label": "Aim"},
	{"keys": "Right Stick", "label": "Line + reach"}, {"keys": "RT", "label": "Kick"}]

const STEPS: Array[Dictionary] = [
	{
		"kind": Kind.LEAD_TO, "angle": 0.0,
		"title": "Kick to the lead",
		"instruction": "Your teammate leads straight back at you. Hold the kick stance, line them up and push the reach out to them, then kick it onto their chest.",
		"kb": KB_KICK, "pad": PAD_KICK,
	},
	{
		"kind": Kind.LEAD_TO, "angle": 40.0,
		"title": "Lead to the left",
		"instruction": "Now they lead off to one side. Aim where they're running, not where they are: they'll come to it, but only so far.",
		"kb": KB_KICK, "pad": PAD_KICK,
	},
	{
		"kind": Kind.LEAD_TO, "angle": -40.0,
		"title": "Lead to the right",
		"instruction": "And the other side. Same again: hit them on the lead.",
		"kb": KB_KICK, "pad": PAD_KICK,
	},
	{
		"kind": Kind.LEAD_SPACE, "angle": 90.0,
		"title": "Kick them into space",
		"instruction": "They run across you. Put it in the ring out in front of them so they mark it in stride. Kick to where they are and they have to stop and wait for it.",
		"kb": KB_KICK, "pad": PAD_KICK,
	},
	{
		"kind": Kind.SPOT, "angle": 0.0,
		"title": "Hit the spot",
		"instruction": "No lead this time. Land it in the ring: line, then reach.",
		"kb": KB_KICK, "pad": PAD_KICK,
	},
]

var _ball: Ball
var _player: PlayerController
var _leader: PlayerController
var _brain: LeadBrain

var _step_index := 0
var _rep_running := false
## The kick of this rep is in the air (or has landed, not yet taken).
var _kicked := false
var _landed_timer := -1.0
var _leader_at_kick := Vector3.ZERO
var _lead_direction := Vector3.FORWARD
var _ring_centre := Vector3.ZERO

var _ring: MeshInstance3D
var _ring_material: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = Tuning.KICK_TUTORIAL_RING_RADIUS - 0.3
	torus.outer_radius = Tuning.KICK_TUTORIAL_RING_RADIUS
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.albedo_color = RING_COLOUR
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = _ring_material
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


func begin(ball: Ball, player: PlayerController, leader: PlayerController) -> void:
	_ball = ball
	_player = player
	_leader = leader
	_step_index = 0
	_hits = 0
	_attempts_used = 0
	_active = true
	_rep_running = false
	_brain = LeadBrain.new()
	_brain.ball = ball
	_brain.kicker = player
	_brain.lead_gait = Tuning.KICK_TUTORIAL_LEAD_GAIT
	if is_instance_valid(_leader):
		_leader.set_brain(_brain)
		if not _leader.mark_caught.is_connected(_on_leader_marked):
			_leader.mark_caught.connect(_on_leader_marked)
	if not _ball.landed.is_connected(_on_ball_landed):
		_ball.landed.connect(_on_ball_landed)
	challenge_started.emit(STEPS.size())
	step_changed.emit(STEPS[0])


func rep_active() -> bool:
	return _rep_running


## Called by kick_to_kick.gd once the player dismisses the step card.
func begin_rep() -> void:
	if not _active:
		return
	_rep_running = true
	_set_up_rep()
	hint_changed.emit("%s — go." % STEPS[_step_index].title)


func skip_step() -> void:
	if not _active:
		return
	_advance()


## A reset ball mid-rep (out of bounds, R): run the rep again.
func force_miss() -> void:
	if _active and _rep_running and _kicked:
		_retry("Reset — again.")


func notify_disposed(action: Tuning.Action) -> void:
	if not _active or not _rep_running or _kicked:
		return
	if action != Tuning.Action.KICK:
		hint_changed.emit("Kick it — hold the stance and use the boot.")
		_schedule(Tuning.KICK_TUTORIAL_RETRY_DELAY, _set_up_rep)
		return
	_kicked = true
	_attempts_used += 1
	if is_instance_valid(_leader):
		_leader_at_kick = _leader.global_position


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	if _ring.visible:
		var pulse := sin(_time * 2.0)
		_ring.scale = Vector3.ONE * (1.0 + pulse * 0.05)
		_ring_material.albedo_color = Color(RING_COLOUR, RING_COLOUR.a * (1.0 + pulse * 0.15))
	if _tick_schedule(delta):
		return
	if not _rep_running or not _kicked:
		return
	if _landed_timer >= 0.0:
		_landed_timer += delta
		if _landed_timer >= Tuning.KICK_TUTORIAL_MISS_TIME:
			_retry("Not taken — again.")


func _set_up_rep() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_ball):
		return
	_kicked = false
	_landed_timer = -1.0
	var step: Dictionary = STEPS[_step_index]
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var from := _player.global_position
	from.y = 0.0

	# Off whoever took the last one, then into the kicker's hands.
	if is_instance_valid(_leader):
		_leader.drop_ball()
	_player.drop_ball()
	_ball.reset_at(_player.global_position + Vector3.UP * 0.3)
	_player.give_possession(_ball)

	_ring.visible = false
	if step.kind == Kind.SPOT:
		_ring_centre = from + forward * Tuning.KICK_TUTORIAL_SPOT_DISTANCE
		_show_ring(_ring_centre)
		if is_instance_valid(_leader):
			# Out of the way, off to the side and short of the ring.
			var right := Vector3(-forward.z, 0.0, forward.x)
			_leader.global_position = from + forward * 12.0 + right * 14.0
			_brain.lead_direction = Vector3.ZERO
			_brain.lead_time = 0.0
		return

	var start := from + forward * Tuning.KICK_TUTORIAL_LEAD_DISTANCE
	# Back at the kicker, turned by the step's angle (LEAD_SPACE's 90 is
	# straight across).
	_lead_direction = (-forward).rotated(Vector3.UP, deg_to_rad(float(step.angle))).normalized()
	if is_instance_valid(_leader):
		_leader.global_position = start
	_brain.lead_direction = _lead_direction
	_brain.lead_delay = Tuning.KICK_TUTORIAL_LEAD_DELAY
	_brain.lead_time = Tuning.KICK_TUTORIAL_LEAD_TIME
	_brain.restart()
	if step.kind == Kind.LEAD_SPACE:
		_ring_centre = start + _lead_direction * Tuning.KICK_TUTORIAL_SPACE_AHEAD
		_show_ring(_ring_centre)


func _show_ring(at: Vector3) -> void:
	_ring.global_position = Vector3(at.x, 0.05, at.z)
	_ring.visible = true


func _on_leader_marked(_tier: Tuning.Action, _legal_mark: bool) -> void:
	if not _active or not _rep_running or not _kicked:
		return
	var step: Dictionary = STEPS[_step_index]
	match step.kind:
		Kind.LEAD_TO:
			_clear("On the chest. Mark!")
		Kind.LEAD_SPACE:
			var gained := (_leader.global_position - _leader_at_kick).dot(_lead_direction)
			if gained >= Tuning.KICK_TUTORIAL_IN_FRONT_MIN:
				_clear("In stride. That's the lead.")
			else:
				_retry("Marked, but they had to wait for it. Further in front.")
		Kind.SPOT:
			_retry("They took it — land it in the ring.")


func _on_ball_landed(_speed: float) -> void:
	if not _active or not _rep_running or not _kicked or _landed_timer >= 0.0:
		return
	var step: Dictionary = STEPS[_step_index]
	if step.kind != Kind.LEAD_TO and _ring.visible:
		var at := _ball.global_position
		var offset := Vector2(at.x - _ring_centre.x, at.z - _ring_centre.z)
		if offset.length() <= Tuning.KICK_TUTORIAL_RING_RADIUS:
			_clear("In the ring.")
			return
	_landed_timer = 0.0


func _clear(text: String) -> void:
	if not _rep_running:
		return
	_rep_running = false
	_hits += 1
	hint_changed.emit(text)
	_advance()


func _retry(text: String) -> void:
	_kicked = false
	_landed_timer = -1.0
	hint_changed.emit(text)
	_schedule(Tuning.KICK_TUTORIAL_RETRY_DELAY, _set_up_rep)


func _advance() -> void:
	_rep_running = false
	_kicked = false
	_ring.visible = false
	_step_index += 1
	if _step_index >= STEPS.size():
		_finish()
	else:
		_schedule(Tuning.TACKLE_TUTORIAL_STEP_GAP, func() -> void: step_changed.emit(STEPS[_step_index]))


func _finish() -> void:
	_active = false
	_ring.visible = false
	if is_instance_valid(_leader) and _leader.mark_caught.is_connected(_on_leader_marked):
		_leader.mark_caught.disconnect(_on_leader_marked)
	if is_instance_valid(_ball) and _ball.landed.is_connected(_on_ball_landed):
		_ball.landed.disconnect(_on_ball_landed)
	challenge_ended.emit(_hits, STEPS.size())
