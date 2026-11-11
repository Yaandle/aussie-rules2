class_name PhysicsRagdollLab
extends Node3D

## Dev-only Physics Ragdoll Lab (docs/MECHANICS_AUDIT.md §B4). Stage 1 —
## PASSIVE ragdoll only: one isolated 6thbuild HumanoidRig standing in the
## same white studio as the animation viewer, a PhysicsRagdoll hung off its
## skeleton, and three ways to knock it over — GO LIMP (no impulse, just
## stop holding the pose), PUSH (an impulse straight into one body part)
## and THROW (a heavy ball from IMPACT FROM's direction that switches the
## body to rigid just before it arrives, so it stands until it's hit).
## Readouts track what stage 1 has to prove: peak speed (no explosion),
## lowest shape point (floor contact, no tunnelling), worst joint-limit
## overshoot, and whether it settles.
##
## Stages 2-5 now run in live tackles (PlayerRagdoll); this is where their
## numbers get tuned. MUSCLE is the ragdoll's strength for PUSH / THROW
## (stage 3: at 1 a small push staggers and recovers, near 0 it's the old
## passive fall; GO LIMP is always 0). TACKLE mode (stage 4) adds a second
## body, the tackler, at IMPACT FROM's bearing and runs the exact numbers a
## live Lunge connect does — TackleBalance.resolve on CLOSING / CARRIER
## speeds and the two masses, with the ML page's saved weights — except b
## isn't floored at Tuning.TACKLE_RAGDOLL_MIN_BALANCE_LOSS, so the staggers
## a match never shows can be explored. The tackler goes physical too when
## b clears Tuning.TACKLE_RAGDOLL_TACKLER_MIN_B; below it they stay posed.
## A match no longer does that: since 2026-10-27 every held Lunge takes the
## tackler down with their arms round the carrier (TackleWrap), which this
## lab doesn't model. The live tackles' headless check was a scratch scene
## driving PlayerController's own connects.
## The posed body is the 6thbuild skeleton's rest pose (arms in an A-pose),
## which is also the motors' target here; in a match it's whatever the
## animation was doing at contact. No get-up — that needs the AnimationTree
## and is a playtest item.
##
## Not reachable from the main menu. Open it from the animation viewer's
## CONTROL row (RAGDOLL), or open scenes/dev/physics_ragdoll_lab.tscn directly
## in the editor and press F6. Esc / C goes back to the animation viewer.

const MODEL_ID := "6thbuild"

## Impact presets, all relative to the player. IMPACT FROM is a compass
## bearing around them (0 = from in front, 90 = from their right, 180 =
## from behind); PUSH is an impulse in N·s (roughly a 90 kg body arriving
## at that many/90 m/s); BALL is the projectile's speed. Both maxima are the
## hardest hits the lab's headless check ran — no explosion at either.
const ANGLE_DEFAULT := 0.0
const PUSH_MIN := 50.0
const PUSH_MAX := 700.0
const PUSH_DEFAULT := 260.0
const BALL_SPEED_MIN := 5.0
const BALL_SPEED_MAX := 35.0
const BALL_SPEED_DEFAULT := 18.0

## TACKLE mode ranges: closing speed (the tackler's into the carrier),
## the carrier's own running speed (straight ahead), and both masses
## (RosterGenerator's 58-92 kg plus some headroom).
const CLOSING_MIN := 1.0
const CLOSING_MAX := 10.0
const CLOSING_DEFAULT := 6.0
const CARRIER_SPEED_MAX := 8.0
const MASS_MIN := 55.0
const MASS_MAX := 110.0
const MASS_DEFAULT := 80.0
## How far the tackler stands from the carrier at contact — inside
## TACKLE_RADIUS, where a Lunge connects.
const TACKLER_DISTANCE := 0.9

## A PUSH is delivered as a constant force over this long rather than one
## instantaneous impulse — a real shove lasts about this long, and dumping
## the whole thing into one ~10 kg body in a single tick gives that one
## link tens of m/s relative to its neighbours, which the joint solver then
## has to claw back in a frame. Same total impulse either way.
const PUSH_DURATION := 0.12

## Test projectile — heavy on purpose (a medicine ball, not a football) so
## a throw carries enough momentum to move an ~86 kg body.
const BALL_MASS := 10.0
const BALL_RADIUS := 0.13
const BALL_SPAWN_DISTANCE := 4.0

## Distance at which the posed body goes rigid as a ball approaches. Must
## cover more than one physics tick of travel at BALL_SPEED_MAX (35 m/s /
## 60 Hz ~= 0.58 m) — a posed PhysicalBone3D has collision switched off,
## so a ball that reaches it before start() passes straight through.
const BALL_TRIGGER_DISTANCE := 1.0

## Target body for PUSH/THROW: label -> bone.
const TARGETS := [
	["HEAD", &"head"],
	["CHEST", &"Chest"],
	["HIPS", &"Hips"],
	["THIGH", &"LeftUpperLeg"],
]

## "Settled" = every body below both thresholds for SETTLE_TIME.
const SETTLE_LINEAR := 0.05
const SETTLE_ANGULAR := 0.2
const SETTLE_TIME := 0.5

const CAMERA_TARGET_HEIGHT := 1.0
const CAMERA_DISTANCE := 5.5
const CAMERA_YAW := 35.0
const CAMERA_PITCH := -14.0
const CAMERA_FOLLOW_RATE := 4.0

const GRID_HALF_EXTENT := 6.0
const GRID_STEP := 0.5
const GRID_COLOUR := Color(0.72, 0.75, 0.79)
const AIM_COLOUR := Color(0.85, 0.3, 0.15)

## The docked menu and the readout card (UIStyle's "Dev tool shell").
const MENU_POSITION := Vector2(UIStyle.DEV_EDGE, UIStyle.DEV_EDGE)
const MENU_WIDTH := 330.0
const READOUT_WIDTH := 340.0

enum State { POSED, FALLING, SETTLED }

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $Overlay/UI

var impact_angle_deg := ANGLE_DEFAULT
var push_impulse := PUSH_DEFAULT
var ball_speed := BALL_SPEED_DEFAULT
var target_bone: StringName = &"Chest"
var muscle := 1.0
var closing_speed := CLOSING_DEFAULT
var carrier_speed := 0.0
var carrier_mass := MASS_DEFAULT
var tackler_mass := MASS_DEFAULT

## The tackler's own rig and ragdoll (TACKLE mode), built on first use.
var _tackler_subject: Node3D
var _tackler_ragdoll: PhysicsRagdoll
var _tackler_push := Vector3.ZERO
var _tackle := {}
var _contact_origin := Vector3.ZERO

var _subject: Node3D
var _rig: HumanoidRig
var _ragdoll: PhysicsRagdoll
var _debug_shapes: Array[MeshInstance3D] = []
var _skin_meshes: Array[MeshInstance3D] = []
var _ball: RigidBody3D
var _ball_armed := false
var _push_remaining := 0.0
var _push_force := Vector3.ZERO
var _aim: MeshInstance3D

var _state := State.POSED
var _sim_time := 0.0
var _settle_timer := 0.0
var _peak_speed := 0.0
var _lowest := INF
var _worst_joint := {"bone": "", "over": 0.0, "angle": 0.0}

var _cam_yaw := CAMERA_YAW
var _cam_pitch := CAMERA_PITCH
var _cam_distance := CAMERA_DISTANCE
var _cam_target := Vector3(0.0, CAMERA_TARGET_HEIGHT, 0.0)

var _state_label: Label
var _speed_label: Label
var _floor_label: Label
var _joint_label: Label
var _status_label: Label
var _menu_panel: PanelContainer
var _menu_scroll: ScrollContainer
var _menu_root: VBoxContainer
var _first_focus: Control


func _ready() -> void:
	add_child(_build_ground_plane())
	add_child(_build_grid())
	add_child(_build_physics_floor())
	add_child(_build_fill_light())
	_aim = MeshInstance3D.new()
	_aim.name = "AimIndicator"
	_aim.mesh = ImmediateMesh.new()
	_aim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aim_material := StandardMaterial3D.new()
	aim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aim_material.vertex_color_use_as_albedo = true
	_aim.material_override = aim_material
	add_child(_aim)
	_build_subject()
	_build_ui()
	_update_camera(1.0)


## Public so a headless check can read the same numbers the panel shows.
func stats() -> Dictionary:
	return {
		"state": State.keys()[_state],
		"sim_time": _sim_time,
		"peak_speed": _peak_speed,
		"lowest": _lowest,
		"worst_joint": _worst_joint,
		"tackle": _tackle,
		"landing": _landing(),
	}


func ragdoll() -> PhysicsRagdoll:
	return _ragdoll


# ── Subject ──────────────────────────────────────────────────────────

func _build_subject() -> void:
	_subject = Node3D.new()
	_subject.name = "Subject"
	_subject.rotation.y = deg_to_rad(180.0)   # face the default camera
	add_child(_subject)

	_rig = HumanoidRig.new()
	_rig.name = "Rig"
	_rig.character_model_override = MODEL_ID
	_rig.high_detail = true
	_subject.add_child(_rig)

	if not _rig.is_imported():
		push_error("PhysicsRagdollLab: %s did not import — the ragdoll is built for its skeleton only" % MODEL_ID)
		return
	var skeleton := _rig.skeleton()
	skeleton.reset_bone_poses()
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			_skin_meshes.append(child)
	_ragdoll = PhysicsRagdoll.new()
	# THROW's ball has to hit it — a match ragdoll ignores the ball.
	if not _ragdoll.build(skeleton, 1.0, PhysicsRagdoll.BALL_LAYER):
		_ragdoll = null
		return
	_debug_shapes = _ragdoll.build_debug_meshes()
	_set_shapes_visible(false)


# ── Impacts ──────────────────────────────────────────────────────────

func go_limp() -> void:
	if _ragdoll == null or _state != State.POSED:
		return
	_begin_simulation(0.0)


## TACKLE mode: a Lunge connect from IMPACT FROM's bearing, worked out the
## way PlayerController._try_lunge_tackle does it (see the header).
func tackle() -> void:
	if _ragdoll == null:
		return
	reset_pose()
	_ensure_tackler()
	if _tackler_ragdoll == null:
		return
	var source := _impact_source_dir()
	var forward := -_subject.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var carrier_vel := forward * carrier_speed
	var tackler_vel := carrier_vel - source * closing_speed
	var carrier_pos := _subject.global_position
	_tackler_subject.global_position = carrier_pos + source * TACKLER_DISTANCE
	# A rig faces -Z (HumanoidRig turns the import's +Z round), look_at's
	# own convention.
	_tackler_subject.look_at(carrier_pos, Vector3.UP)
	_tackler_ragdoll.snap_to_pose()
	_tackle = TackleBalance.resolve(_tackler_subject.global_position, tackler_vel, tackler_mass,
		carrier_pos, carrier_vel, carrier_mass, 0.0, forward)
	_contact_origin = carrier_pos
	_ragdoll.set_mass_scale(carrier_mass / _rest_mass())
	_tackler_ragdoll.set_mass_scale(tackler_mass / _rest_mass())
	target_bone = _tackle.bone
	_begin_simulation(1.0 - float(_tackle.b), carrier_vel)
	_push_force = (_tackle.impulse as Vector3) / PUSH_DURATION
	_push_remaining = PUSH_DURATION
	if float(_tackle.tackler_b) > 0.0:
		_tackler_ragdoll.capture_target_pose()
		_tackler_ragdoll.strength = 1.0 - float(_tackle.tackler_b)
		_tackler_ragdoll.start(_tackle.tackler_velocity)
		_tackler_push = (_tackle.tackler_impulse as Vector3) / PUSH_DURATION


func _rest_mass() -> float:
	var m := 0.0
	for spec: Dictionary in PhysicsRagdoll.BODIES:
		m += float(spec.mass)
	return m


func _ensure_tackler() -> void:
	if _tackler_subject != null:
		return
	_tackler_subject = Node3D.new()
	_tackler_subject.name = "Tackler"
	add_child(_tackler_subject)
	var rig := HumanoidRig.new()
	rig.character_model_override = MODEL_ID
	rig.away_kit = true
	_tackler_subject.add_child(rig)
	if not rig.is_imported():
		return
	rig.skeleton().reset_bone_poses()
	_tackler_ragdoll = PhysicsRagdoll.new()
	if not _tackler_ragdoll.build(rig.skeleton(), 1.0, PhysicsRagdoll.BALL_LAYER):
		_tackler_ragdoll = null


## Where the carrier's hips ended up relative to where they were hit, in
## their own frame — {"left", "forward"} metres — plus whether they're down.
func _landing() -> Dictionary:
	if _ragdoll == null or _state == State.POSED or _tackle.is_empty():
		return {}
	var moved := _ragdoll.body(&"Hips").global_position - _contact_origin
	var forward := -_subject.global_basis.z
	var right := _subject.global_basis.x
	return {"left": -moved.dot(right), "forward": moved.dot(forward), "down": _ragdoll.is_down()}


## PUSH and THROW also work on a body that's already down — a second hit
## on a fallen (even sleeping) ragdoll is as much a stage-1 check as the
## first. IMPACT FROM stays relative to the way the player faced while posed.
func push() -> void:
	if _ragdoll == null:
		return
	if _state == State.POSED:
		_begin_simulation()
	_tackle = {}   # a plain push from here on, even onto a tackled body
	_push_force = -_impact_source_dir() * push_impulse / PUSH_DURATION
	_push_remaining = PUSH_DURATION


func throw_ball() -> void:
	if _ragdoll == null:
		return
	_clear_ball()
	var target := _ragdoll.body(target_bone).global_position
	_ball = _build_ball()
	add_child(_ball)
	_ball.global_position = target + _impact_source_dir() * BALL_SPAWN_DISTANCE
	# Lofted just enough to arrive at the target's height despite gravity.
	var flight := BALL_SPAWN_DISTANCE / ball_speed
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	_ball.linear_velocity = -_impact_source_dir() * ball_speed + Vector3.UP * gravity * flight * 0.5
	_ball_armed = _state == State.POSED


func reset_pose() -> void:
	_clear_ball()
	_push_remaining = 0.0
	_tackle = {}
	_tackler_push = Vector3.ZERO
	if _ragdoll != null and _ragdoll.is_simulating():
		_ragdoll.stop()
	if _tackler_ragdoll != null and _tackler_ragdoll.is_simulating():
		_tackler_ragdoll.stop()
	_state = State.POSED
	_sim_time = 0.0
	_settle_timer = 0.0
	_peak_speed = 0.0
	_lowest = INF
	_worst_joint = {"bone": "", "over": 0.0, "angle": 0.0}
	_update_readouts()


## `strength` < 0 = the MUSCLE slider. The motors hold the rest pose the
## body is posed in.
func _begin_simulation(strength := -1.0, velocity := Vector3.ZERO) -> void:
	_ragdoll.capture_target_pose()
	_ragdoll.strength = muscle if strength < 0.0 else strength
	_ragdoll.start(velocity)
	_state = State.FALLING
	_sim_time = 0.0
	_settle_timer = 0.0
	_peak_speed = 0.0
	_lowest = INF
	_worst_joint = {"bone": "", "over": 0.0, "angle": 0.0}


## World-space unit vector from the player toward where the impact comes
## from, on the ground plane. Player-local forward is -Z, right is +X.
func _impact_source_dir() -> Vector3:
	var a := deg_to_rad(impact_angle_deg)
	return (_subject.global_basis * Vector3(sin(a), 0.0, -cos(a))).normalized()


func _build_ball() -> RigidBody3D:
	var ball := RigidBody3D.new()
	ball.name = "ImpactBall"
	ball.mass = BALL_MASS
	ball.continuous_cd = true
	ball.collision_layer = 1 << 2
	ball.collision_mask = (1 << 0) | (1 << 1)
	var material := PhysicsMaterial.new()
	material.bounce = 0.2
	material.friction = 0.6
	ball.physics_material_override = material
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = BALL_RADIUS
	shape.shape = sphere
	ball.add_child(shape)
	var mesh := SphereMesh.new()
	mesh.radius = BALL_RADIUS
	mesh.height = BALL_RADIUS * 2.0
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var colour := StandardMaterial3D.new()
	colour.albedo_color = Color(0.55, 0.2, 0.12)
	colour.roughness = 0.7
	visual.material_override = colour
	ball.add_child(visual)
	return ball


func _clear_ball() -> void:
	_ball_armed = false
	if _ball != null:
		_ball.queue_free()
		_ball = null


# ── Per-frame ────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _ragdoll == null:
		return
	if _ball_armed and _state == State.POSED and _ball != null:
		var target := _ragdoll.body(target_bone).global_position
		if _ball.global_position.distance_to(target) < BALL_TRIGGER_DISTANCE:
			_ball_armed = false
			_begin_simulation()
	if _state == State.POSED:
		return

	if _push_remaining > 0.0:
		var dt := minf(delta, _push_remaining)
		if _tackle.is_empty():
			_ragdoll.apply_impact(target_bone, _push_force * dt)
		else:
			_ragdoll.apply_tackle_push(target_bone, _push_force * dt,
				_ragdoll.body(target_bone).global_position + (_tackle.contact_offset as Vector3),
				float(_tackle.body_share))
			if _tackler_ragdoll.is_simulating():
				_tackler_ragdoll.apply_impact(&"Chest", _tackler_push * dt)
		_push_remaining -= dt

	if _tackler_ragdoll != null and _tackler_ragdoll.is_simulating():
		_tackler_ragdoll.step(delta)
	_ragdoll.step(delta)
	_sim_time += delta
	var speed := _ragdoll.peak_speed()
	_peak_speed = maxf(_peak_speed, speed)
	_lowest = minf(_lowest, _ragdoll.lowest_point())
	var joint := _ragdoll.joint_report()
	if joint.over > _worst_joint.over or _worst_joint.bone == "":
		_worst_joint = joint

	# Asleep is the real "at rest" (PhysicsRagdoll.step puts a body that's
	# only buzzing in place to sleep); the speed check catches Jolt or a
	# genuinely still body getting there first. A sleeping body stops
	# reporting velocity, so its last value can't be trusted either way.
	if _ragdoll.is_asleep():
		_state = State.SETTLED
		return
	if speed < SETTLE_LINEAR and _ragdoll.peak_angular_speed() < SETTLE_ANGULAR:
		_settle_timer += delta
	else:
		_settle_timer = 0.0
	_state = State.SETTLED if _settle_timer >= SETTLE_TIME else State.FALLING


func _process(delta: float) -> void:
	_update_camera(delta)
	_draw_aim()
	_update_readouts()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_menu"):
		SceneWipe.change_scene("res://scenes/dev/animation_viewer.tscn")
		return
	if UIStyle.dev_focus_entry(get_viewport(), event, _first_focus):
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		var motion := event as InputEventMouseMotion
		_cam_yaw -= motion.relative.x * 0.3
		_cam_pitch = clampf(_cam_pitch - motion.relative.y * 0.3, -80.0, 10.0)
	elif event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_distance = maxf(_cam_distance - 0.4, 1.5)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_distance = minf(_cam_distance + 0.4, 14.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_SPACE: push()
			KEY_K: tackle()
			KEY_T: throw_ball()
			KEY_L: go_limp()
			KEY_R: reset_pose()


## Orbit camera. Follows the body's centre of mass once it's moving, so a
## big push doesn't carry the ragdoll out of frame.
func _update_camera(delta: float) -> void:
	var goal := Vector3(0.0, CAMERA_TARGET_HEIGHT, 0.0)
	if _ragdoll != null and _state != State.POSED:
		goal = _ragdoll.centre_of_mass()
		goal.y = maxf(goal.y, 0.4)
	_cam_target = _cam_target.lerp(goal, clampf(delta * CAMERA_FOLLOW_RATE, 0.0, 1.0))
	var orbit := Basis.from_euler(Vector3(deg_to_rad(_cam_pitch), deg_to_rad(_cam_yaw), 0.0))
	_camera.global_position = _cam_target + orbit * Vector3(0.0, 0.0, _cam_distance)
	_camera.look_at(_cam_target)


## Arrow along the ground from IMPACT FROM's bearing into the player, plus a
## drop line at the target's height — only while posed, so the angle and
## target can be lined up before firing.
func _draw_aim() -> void:
	var mesh := _aim.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if _ragdoll == null or _state != State.POSED:
		return
	var source := _impact_source_dir()
	var target := _ragdoll.body(target_bone).global_position
	var ground_end := Vector3(target.x, 0.01, target.z) + source * 0.45
	var ground_start := ground_end + source * (BALL_SPAWN_DISTANCE - 0.45)
	var side := source.cross(Vector3.UP).normalized() * 0.12
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(AIM_COLOUR)
	for v in [ground_start, ground_end,
			ground_end, ground_end + source * 0.2 + side,
			ground_end, ground_end + source * 0.2 - side,
			ground_start, ground_start + Vector3(0.0, target.y, 0.0),
			ground_start + Vector3(0.0, target.y, 0.0), target + source * 0.3]:
		mesh.surface_add_vertex(v)
	mesh.surface_end()


# ── Studio ───────────────────────────────────────────────────────────
# Same seamless white cove as the animation viewer (animation_viewer.gd
# _build_ground_plane/_build_fill_light), plus a real floor to land on.

func _build_ground_plane() -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(60.0, 60.0)
	var instance := MeshInstance3D.new()
	instance.name = "StudioGround"
	instance.mesh = mesh
	instance.position.y = -0.004
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.95, 0.944)
	material.roughness = 1.0
	instance.material_override = material
	return instance


func _build_grid() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var half_steps := int(floor(GRID_HALF_EXTENT / GRID_STEP))
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for step in range(-half_steps, half_steps + 1):
		var x := step * GRID_STEP
		mesh.surface_set_color(GRID_COLOUR)
		mesh.surface_add_vertex(Vector3(x, 0.0, -GRID_HALF_EXTENT))
		mesh.surface_add_vertex(Vector3(x, 0.0, GRID_HALF_EXTENT))
		mesh.surface_add_vertex(Vector3(-GRID_HALF_EXTENT, 0.0, x))
		mesh.surface_add_vertex(Vector3(GRID_HALF_EXTENT, 0.0, x))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "StudioGrid"
	instance.mesh = mesh
	return instance


## A metre-thick slab, top face at y=0. PhysicalBone3D has no continuous
## collision option of its own, so thickness is what stops a fast limb from
## stepping clean through the floor in one tick.
func _build_physics_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Floor"
	body.collision_layer = 1 << 0
	body.collision_mask = 0
	var material := PhysicsMaterial.new()
	material.friction = 0.9
	body.physics_material_override = material
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	return body


func _build_fill_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "Fill"
	light.rotation_degrees = Vector3(-28.0, -46.0, 0.0)
	light.light_energy = 0.28
	light.shadow_enabled = false
	return light


func _set_shapes_visible(on: bool) -> void:
	for mesh in _debug_shapes:
		mesh.visible = on


func _set_skin_visible(on: bool) -> void:
	for mesh in _skin_meshes:
		mesh.visible = on


# ── UI ───────────────────────────────────────────────────────────────
# The dev-tool shell the animation viewer and the ML page use (UIStyle's
# "Dev tool shell"): the menu is controls and live cards, and the run's
# readout sits in its own card on the right, always in view.

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override(&"separation", UIStyle.DEV_GAP)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# The menu scrolls rather than running off the bottom of a short window
	# (see _fit_menu).
	_menu_panel = UIStyle.dev_panel()
	_menu_panel.position = MENU_POSITION
	_menu_panel.custom_minimum_size.x = MENU_WIDTH
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.add_child(root)
	_menu_panel.add_child(_menu_scroll)
	_ui.add_child(_menu_panel)
	_menu_root = root

	root.add_child(UIStyle.label("RAGDOLL LAB", UIStyle.SIZE_TITLE,
		UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_TITLE))

	var metrics := GridContainer.new()
	metrics.columns = 2
	metrics.add_theme_constant_override(&"h_separation", UIStyle.DEV_GAP)
	metrics.add_theme_constant_override(&"v_separation", UIStyle.DEV_GAP)
	root.add_child(metrics)
	_state_label = _add_metric(metrics, "STATE")
	_speed_label = _add_metric(metrics, "PEAK SPEED")
	_floor_label = _add_metric(metrics, "LOWEST POINT")
	_joint_label = _add_metric(metrics, "JOINT OVERSHOOT")

	var impact := _section(root, "Impact")
	var impacts := UIStyle.dev_button_row([["LIMP", go_limp], ["PUSH", push], ["THROW", throw_ball], ["TACKLE", tackle]])
	impact.add_child(impacts)
	_first_focus = impacts.get_child(0)

	var targets := []
	var selected := 0
	for i in TARGETS.size():
		var bone: StringName = TARGETS[i][1]
		targets.append([TARGETS[i][0], func() -> void: target_bone = bone])
		if bone == target_bone:
			selected = i
	impact.add_child(UIStyle.dev_button_row(targets, ButtonGroup.new(), selected))

	impact.add_child(UIStyle.dev_slider_row("From", 0.0, 355.0, 5.0, impact_angle_deg,
		func(v: float) -> void: impact_angle_deg = v,
		UIStyle.dev_bearing).node)
	impact.add_child(_unit_row("Push", "N·s", PUSH_MIN, PUSH_MAX, 10.0, push_impulse,
		func(v: float) -> void: push_impulse = v))
	impact.add_child(_unit_row("Ball", "m/s", BALL_SPEED_MIN, BALL_SPEED_MAX, 1.0, ball_speed,
		func(v: float) -> void: ball_speed = v))
	impact.add_child(_unit_row("Muscle", "%", 0.0, 100.0, 5.0, muscle * 100.0,
		func(v: float) -> void: muscle = v / 100.0))

	# FROM above is the tackler's bearing too.
	var tackle_section := _section(root, "Tackle")
	tackle_section.add_child(_unit_row("Closing", "m/s", CLOSING_MIN, CLOSING_MAX, 0.5, closing_speed,
		func(v: float) -> void: closing_speed = v))
	tackle_section.add_child(_unit_row("Carrier", "m/s", 0.0, CARRIER_SPEED_MAX, 0.5, carrier_speed,
		func(v: float) -> void: carrier_speed = v))
	tackle_section.add_child(_unit_row("Carrier", "kg", MASS_MIN, MASS_MAX, 1.0, carrier_mass,
		func(v: float) -> void: carrier_mass = v))
	tackle_section.add_child(_unit_row("Tackler", "kg", MASS_MIN, MASS_MAX, 1.0, tackler_mass,
		func(v: float) -> void: tackler_mass = v))

	var view := HBoxContainer.new()
	view.add_theme_constant_override(&"separation", 6)
	root.add_child(view)
	var shapes := UIStyle.dev_button("SHAPES", true)
	shapes.toggled.connect(_set_shapes_visible)
	var skin := UIStyle.dev_button("SKIN", true)
	skin.button_pressed = true
	skin.toggled.connect(_set_skin_visible)
	var reset := UIStyle.dev_button("RESET")
	reset.pressed.connect(reset_pose)
	for b: Button in [shapes, skin, reset]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.add_child(b)

	var hints := KeyHintBar.new()
	hints.position = Vector2(24.0, 674.0)
	hints.set_hints([
		{"keys": "Space", "label": "Push"},
		{"keys": "K", "label": "Tackle"},
		{"keys": "T", "label": "Throw"},
		{"keys": "L", "label": "Limp"},
		{"keys": "R", "label": "Reset"},
		{"keys": "Right-drag / Wheel", "label": "Orbit / zoom"},
		{"keys": "Tab", "label": "Focus"},
		{"keys": "Esc / C", "label": "Back"},
	])
	_ui.add_child(hints)
	_build_readout_panel()
	get_viewport().size_changed.connect(_fit_menu)
	_fit_menu.call_deferred()
	_update_readouts()


## A headed group of rows in the menu.
func _section(parent: Control, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UIStyle.DEV_ROW_GAP)
	col.add_child(UIStyle.dev_heading(title))
	parent.add_child(col)
	return col


## A slider row whose readout carries its unit.
func _unit_row(caption: String, unit: String, min_value: float, max_value: float, step: float,
		value: float, on_change: Callable) -> Control:
	var pattern := UIStyle.dev_step_format(step) + ("%s" if unit == "%" else " %s")
	var format := func(v: float) -> String: return pattern % [v, unit]
	var row := UIStyle.dev_slider_row(caption, min_value, max_value, step, value, on_change, format)
	(row.slider as HSlider).tooltip_text = "%s (%s)" % [caption, unit]
	return row.node


## Top-right card holding the run's readout: one fact per line, in
## fixed-pitch columns.
func _build_readout_panel() -> void:
	var panel := UIStyle.dev_panel()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -READOUT_WIDTH - MENU_POSITION.x
	panel.offset_right = -MENU_POSITION.x
	panel.offset_top = MENU_POSITION.y
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UIStyle.DEV_ROW_GAP)
	panel.add_child(col)
	col.add_child(UIStyle.dev_heading("Readout · %s" % MODEL_ID))
	_status_label = UIStyle.dev_readout("")
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.x = READOUT_WIDTH - UIStyle.DEV_PAD * 2.0
	col.add_child(_status_label)
	_ui.add_child(panel)


## Caps the menu at the space above the key-hint bar; past that it scrolls.
func _fit_menu() -> void:
	if _menu_scroll != null:
		UIStyle.dev_fit_scroll(_menu_panel, _menu_scroll, _menu_root)


func _update_readouts() -> void:
	if _state_label == null:
		return
	if _ragdoll == null:
		_state_label.text = "NO RIG"
		_status_label.text = "%s didn't import or its skeleton doesn't match PhysicsRagdoll.BODIES — see the Output panel." % MODEL_ID
		return
	_state_label.text = State.keys()[_state]
	if _state == State.POSED:
		_speed_label.text = "—"
		_floor_label.text = "—"
		_joint_label.text = "—"
		_status_label.text = "bodies     %d\nmass       %.0f kg\nposed      rest pose, kinematic" % [
			_ragdoll.bodies.size(), _ragdoll.total_mass()]
		return
	_speed_label.text = "%.1f m/s" % _peak_speed
	_floor_label.text = "%+.0f mm" % (_lowest * 1000.0)
	_joint_label.text = "%.1f°" % _worst_joint.over
	var lines: Array[String] = [
		"time       %.1f s" % _sim_time,
		"worst      %s (%.0f°)" % [_worst_joint.bone, _worst_joint.angle],
		"settle     %d%%" % roundi(_ragdoll.settle_blend() * 100.0),
		"muscle     %d%%%s" % [roundi(_ragdoll.strength * 100.0), "  bracing" if _ragdoll.is_falling() else ""],
	]
	if not _tackle.is_empty():
		var landing := _landing()
		lines.append_array([
			"",
			"TACKLE     b %.2f   p(break) %.2f" % [_tackle.b, _tackle.p_break],
			# What a match would do with this hit; the lab plays the fall either way.
			"in a match Lunge %s, Slide %s" % [
				"breaks" if float(_tackle.p_break) >= Tuning.TACKLE_LUNGE_BREAK_P else "holds",
				"breaks" if float(_tackle.p_break) >= Tuning.TACKLE_SLIDE_BREAK_P else "holds"],
			"closing    %.1f m/s, %.0f° off square" % [_tackle.closing_speed, _tackle.approach_angle],
			"mass       ×%.2f" % _tackle.mass_ratio,
			"push       %.0f N·s at %s" % [(_tackle.impulse as Vector3).length(), _tackle.bone],
			"tackler    %s" % ("down too (b %.2f)" % _tackle.tackler_b if float(_tackle.tackler_b) > 0.0 else "stays up"),
			"hips       %.2f m %s, %.2f m %s" % [absf(landing.left), "left" if landing.left >= 0.0 else "right",
				absf(landing.forward), "forward" if landing.forward >= 0.0 else "back"],
			"carrier    %s" % ("DOWN" if landing.down else "on feet"),
		])
	_status_label.text = "\n".join(lines)


func _add_metric(grid: GridContainer, caption: String) -> Label:
	var card := UIStyle.dev_metric_card(caption)
	grid.add_child(card.node)
	return card.value_label
