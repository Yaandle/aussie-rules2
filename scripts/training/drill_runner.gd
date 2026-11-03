class_name DrillRunner
extends Node3D

## Plays one drill (DrillLibrary) on the field: spawns its cones and a
## player per role, puts the ball with ball_to, then runs the beats in
## order, looping. Every role is a DrillBrain bot, except `human_role` when
## you play it, who's yours on a HumanBrain: your beats wait for you, and
## the bots around you carry on with theirs.
##
## A beat that stalls (a kick nobody took, a bot that never got there)
## runs again from where it started after its timeout: everyone involved
## goes back to where they stood when it began and the ball goes back to
## whoever had it. A drill on a loop has to recover by itself, and it's
## the same retry a coach calls.
##
## A beat with "rotate" moves every player that many roles along once
## it's done (1: A's player is B from then on, B's is C, ..., the last
## role's is A), and one with "flip" turns the drill round: the layout
## mirrors about the drill's "mirror_x" line and every spot after that
## (starts, runs, the ring) is read in the mirrored frame until the next
## flip. The kicking circuit does both when D marks: D is A and kicks it
## back the way it came, and everyone else has already run on to the next
## role's spot, following their pass. Roles keep their spots and what beats
## tell them; it's the players who move between them, and you go with
## your player.

signal beat_changed(index: int, text: String)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CONE_COLOUR := Color("#FF6A2B")
const MARKER_COLOUR := Color(0.8, 0.96, 0.27, 0.8)
const DEFAULT_TIMEOUT := 10.0
## A ball left loose and still this long after the beat's disposal is dead:
## the beat runs again.
const DEAD_BALL_TIME := 1.6

var ball: Ball = null
## The drill's centre on the field, and which way its +x faces.
var origin := Vector3.ZERO
var yaw := 0.0
## Set on the human's PlayerController when playing.
var human_camera: Node3D = null
var human_camera_rig: BroadcastCamera = null

var drill: Dictionary = {}
var human_role := -1
var players: Array[PlayerController] = []

var _brains: Array = []
## True while the drill runs the mirrored way ("flip").
var _flipped := false
var _cones: Array[Node3D] = []
var _marker: MeshInstance3D
var _beat := 0
var _beat_time := 0.0
var _started: Array[bool] = []
var _beat_positions: Array[Vector3] = []
var _beat_holder := -1
var _dead_time := 0.0


func _ready() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.75
	ring.outer_radius = 0.95
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = MARKER_COLOUR
	ring.material = material
	_marker = MeshInstance3D.new()
	_marker.mesh = ring
	_marker.visible = false
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)


func start(p_drill: Dictionary, p_human_role := -1) -> void:
	stop()
	drill = p_drill
	human_role = p_human_role
	_flipped = false
	# Both ways' cones, when the drill turns round; one cone where the two
	# land on top of each other.
	var cones: Array[Vector2] = []
	for at: Vector2 in drill.get("cones", []):
		cones.append(at)
		if drill.has("mirror_x"):
			cones.append(Vector2(2.0 * float(drill.mirror_x) - at.x, at.y))
	var placed: Array[Vector2] = []
	for at in cones:
		if placed.any(func(other: Vector2) -> bool: return other.distance_to(at) < 1.0):
			continue
		placed.append(at)
		_add_cone(to_world(at))
	var roles: Array = drill.roles
	for i in roles.size():
		players.append(_spawn(i, _start(i)))
	_put_ball_with(int(drill.get("ball_to", 0)))
	_begin_beat(0)


func stop() -> void:
	for player in players:
		if is_instance_valid(player):
			player.drop_ball()
			player.queue_free()
	for cone in _cones:
		cone.queue_free()
	players.clear()
	_brains.clear()
	_flipped = false
	_cones.clear()
	drill = {}
	human_role = -1
	if _marker != null:
		_marker.visible = false


func is_running() -> bool:
	return not drill.is_empty()


func human() -> PlayerController:
	return players[human_role] if human_role >= 0 and human_role < players.size() else null


func to_world(at: Vector2) -> Vector3:
	if _flipped:
		at.x = 2.0 * float(drill.get("mirror_x", 0.0)) - at.x
	return origin + Basis(Vector3.UP, yaw) * Vector3(at.x, 0.0, at.y)


## Where role `role` starts, the way the drill's facing now.
func _start(role: int) -> Vector3:
	return to_world(drill.roles[role].at)


func _spawn(role: int, at: Vector3) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.team = Tuning.Team.HOME
	player.position = at
	add_child(player)
	AudioManager.register_player(player)
	player.face_toward(origin)
	if role == human_role:
		player.camera = human_camera
		player.camera_rig = human_camera_rig
		_brains.append(null)   # keeps the default HumanBrain
	else:
		var brain := DrillBrain.new()
		brain.ball = ball
		player.set_brain(brain)
		_brains.append(brain)
	return player


func _add_cone(at: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.17
	mesh.height = 0.35
	mesh.radial_segments = 10
	var material := StandardMaterial3D.new()
	material.albedo_color = CONE_COLOUR
	mesh.material = material
	var cone := MeshInstance3D.new()
	cone.mesh = mesh
	add_child(cone)
	cone.global_position = at + Vector3.UP * 0.175
	_cones.append(cone)


func _put_ball_with(role: int) -> void:
	if not is_instance_valid(ball) or role < 0 or role >= players.size():
		return
	for player in players:
		player.drop_ball()
	ball.reset_at(players[role].global_position + Vector3.UP * 0.3)
	players[role].give_possession(ball)


func _beats() -> Array:
	return drill.get("beats", [])


func _begin_beat(index: int) -> void:
	var beats := _beats()
	if beats.is_empty():
		return
	_beat = posmod(index, beats.size())
	var beat: Dictionary = beats[_beat]
	_beat_time = 0.0
	_dead_time = 0.0
	if beat.get("reset", false):
		for i in players.size():
			players[i].drop_ball()
			players[i].global_position = _start(i)
			players[i].velocity = Vector3.ZERO
			players[i].face_toward(origin)
		_put_ball_with(int(drill.get("ball_to", 0)))
	# A beat that starts with a kick or handball starts with the ball in
	# that player's hands, so a dropped one earlier can't stall the loop.
	for entry: Dictionary in beat.get("do", []):
		if entry.has("kick_to") or entry.has("handball_to"):
			var role := int(entry.role)
			if not players[role].is_carrying():
				_put_ball_with(role)
	_beat_positions.clear()
	for player in players:
		_beat_positions.append(player.global_position)
	_beat_holder = _holder()
	_started.clear()
	for entry in beat.get("do", []):
		_started.append(false)
	var by := int(beat.get("by", -1))
	for i in _brains.size():
		if _brains[i] != null:
			(_brains[i] as DrillBrain).idle()
			(_brains[i] as DrillBrain).expect_ball = i == by
	_marker.visible = false
	beat_changed.emit(_beat, _beat_text(beat))


## The beat's text, plus what you have to do in it when you're playing.
func _beat_text(beat: Dictionary) -> String:
	var text := String(beat.get("text", ""))
	for entry: Dictionary in beat.get("do", []):
		if int(entry.role) != human_role:
			continue
		var roles: Array = drill.roles
		if entry.has("run_to"):
			text += "\nYou: run to the ring."
		elif entry.has("kick_to"):
			text += "\nYou: kick to %s." % roles[int(entry.kick_to)].name
		elif entry.has("handball_to"):
			text += "\nYou: handball to %s." % roles[int(entry.handball_to)].name
	if int(beat.get("by", -1)) == human_role and human_role >= 0:
		text += "\nYou: take it."
	return text


func _holder() -> int:
	for i in players.size():
		if players[i].is_carrying():
			return i
	return -1


func _physics_process(delta: float) -> void:
	if drill.is_empty():
		return
	var beats := _beats()
	if beats.is_empty():
		return
	_beat_time += delta
	var beat: Dictionary = beats[_beat]
	var entries: Array = beat.get("do", [])
	for i in entries.size():
		if _started[i] or _beat_time < float(entries[i].get("delay", 0.0)):
			continue
		_started[i] = true
		_apply(entries[i])

	if _beat_done(beat):
		if beat.has("rotate"):
			_rotate(int(beat.rotate))
		if beat.get("flip", false):
			_flipped = not _flipped
		_begin_beat(_beat + 1)
		return
	if _ball_dead():
		_dead_time += delta
	else:
		_dead_time = 0.0
	var timeout := float(beat.get("timeout", DEFAULT_TIMEOUT))
	if _human_acts(beat):
		timeout = INF
	if _dead_time >= DEAD_BALL_TIME or _beat_time >= timeout:
		_retry_beat()


func _apply(entry: Dictionary) -> void:
	var role := int(entry.role)
	var brain := _brains[role] as DrillBrain
	if entry.has("run_to"):
		var at := to_world(entry.run_to)
		if brain != null:
			brain.run_to(at, float(entry.get("gait", 0.8)))
		else:
			_marker.global_position = Vector3(at.x, 0.05, at.z)
			_marker.visible = true
	elif brain != null and entry.has("kick_to"):
		brain.kick_to(players[int(entry.kick_to)])
	elif brain != null and entry.has("handball_to"):
		brain.handball_to(players[int(entry.handball_to)])


func _beat_done(beat: Dictionary) -> bool:
	match String(beat.get("until", "time")):
		"caught":
			var by := int(beat.get("by", -1))
			return by >= 0 and by < players.size() and players[by].is_carrying() and _holder() != _beat_holder
		"arrived":
			for entry: Dictionary in beat.get("do", []):
				if not entry.has("run_to"):
					continue
				var role := int(entry.role)
				var at := to_world(entry.run_to)
				if Vector2(players[role].global_position.x - at.x,
						players[role].global_position.z - at.z).length() > DrillBrain.ARRIVE_DISTANCE * 1.5:
					return false
			return true
	return _beat_time >= float(beat.get("time", 1.0))


## Nobody has it, it's on the ground and it's stopped: whatever this beat
## was doing with it didn't come off.
func _ball_dead() -> bool:
	return is_instance_valid(ball) and not ball.is_held and _beat_holder >= 0 \
		and not ball.is_airborne() and ball.linear_velocity.length() < 0.5


func _human_acts(beat: Dictionary) -> bool:
	if human_role < 0:
		return false
	for entry: Dictionary in beat.get("do", []):
		if int(entry.role) == human_role:
			return true
	return false


func _rotate(by: int) -> void:
	var count := players.size()
	var moved_players: Array[PlayerController] = []
	var moved_brains: Array = []
	for role in count:
		var from := posmod(role - by, count)
		moved_players.append(players[from])
		moved_brains.append(_brains[from])
	players = moved_players
	_brains = moved_brains
	if human_role >= 0:
		human_role = posmod(human_role + by, count)


func _retry_beat() -> void:
	for i in players.size():
		players[i].drop_ball()
		players[i].global_position = _beat_positions[i]
		players[i].velocity = Vector3.ZERO
	if _beat_holder >= 0:
		_put_ball_with(_beat_holder)
	_begin_beat(_beat)
