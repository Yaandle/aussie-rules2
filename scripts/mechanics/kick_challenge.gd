class_name KickChallenge
extends Node3D

## The kicking coach's mini-game (design brief): hit a target placed
## downfield within a set number of kicks. Kept as its own small state
## machine rather than folded into kick_to_kick.gd's body — the brief's
## own plan is a marking coach and a tackling coach next, and whatever
## ends up actually shared between the three once they exist is a
## refactor for that day, not a shape to guess at now.
##
## The target ring is a mechanics-owned gameplay gizmo — an Area3D plus an
## unshaded torus, the same kind of primitive KickTrajectory's landing
## ring already is — not a modelled prop.

signal challenge_started(attempts_total: int)
signal target_hit(hits: int, attempts_used: int)
signal target_missed(attempts_used: int)
signal challenge_ended(hits: int, attempts_total: int)
signal hint_changed(text: String)

const RING_COLOUR := Color(0.95, 0.35, 0.25, 0.85)

@onready var _zone: Area3D = $TargetZone
@onready var _ring_mesh: MeshInstance3D = $TargetZone/Ring

var _ball: Ball = null
var _attempts_used := 0
var _hits := 0
var _active := false

## True from the moment a KICK leaves the player's hands until this
## attempt is resolved (hit, settled miss, or forcibly reset) — the gate
## that stops a single kick being counted twice or a stray settle from an
## earlier attempt being counted again.
var _armed := false


func _ready() -> void:
	visible = false

	var shape := CylinderShape3D.new()
	shape.radius = Tuning.KICK_CHALLENGE_TARGET_RADIUS
	shape.height = 4.0
	($TargetZone/CollisionShape3D as CollisionShape3D).shape = shape

	var ring := TorusMesh.new()
	ring.inner_radius = maxf(0.1, Tuning.KICK_CHALLENGE_TARGET_RADIUS - 0.3)
	ring.outer_radius = Tuning.KICK_CHALLENGE_TARGET_RADIUS
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = RING_COLOUR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = material
	_ring_mesh.mesh = ring

	_zone.body_entered.connect(_on_body_entered)


func begin(ball: Ball, target_position: Vector3) -> void:
	_ball = ball
	var pos := target_position
	pos.y = 0.03   # just off the turf, same reasoning as Field's line markings
	global_position = pos
	_attempts_used = 0
	_hits = 0
	_active = true
	_armed = false
	visible = true
	challenge_started.emit(Tuning.KICK_CHALLENGE_ATTEMPTS)
	hint_changed.emit("Hold K/LT to aim, tap F/RT to strike the target ring.")


func is_active() -> bool:
	return _active


func attempts_remaining() -> int:
	return Tuning.KICK_CHALLENGE_ATTEMPTS - _attempts_used


## Called by kick_to_kick.gd on every disposal — only a KICK while the
## challenge is active arms it; handballs/bounces don't count as attempts.
func notify_disposed(action: Tuning.Action) -> void:
	if _active and action == Tuning.Action.KICK:
		_armed = true


## Called by kick_to_kick.gd whenever it has to reposition the ball out
## from under an armed attempt (out of bounds, manual debug reset) instead
## of letting it settle on its own — otherwise that attempt would vanish
## uncounted rather than reading as the miss it was.
func force_miss() -> void:
	if not _active or not _armed:
		return
	_armed = false
	_attempts_used += 1
	target_missed.emit(_attempts_used)
	hint_changed.emit("Out of bounds — %d left." % attempts_remaining())
	_check_end()


func _physics_process(_delta: float) -> void:
	if not _active or not _armed or not is_instance_valid(_ball):
		return
	if _ball.is_settled():
		_armed = false
		_attempts_used += 1
		target_missed.emit(_attempts_used)
		hint_changed.emit("Missed — %d left." % attempts_remaining())
		_check_end()


func _on_body_entered(body: Node3D) -> void:
	if not _active or not _armed or body != _ball:
		return
	_armed = false
	_attempts_used += 1
	_hits += 1
	target_hit.emit(_hits, _attempts_used)
	hint_changed.emit("On target! %d/%d" % [_hits, Tuning.KICK_CHALLENGE_ATTEMPTS])
	_check_end()


func _check_end() -> void:
	if _attempts_used < Tuning.KICK_CHALLENGE_ATTEMPTS:
		return
	_active = false
	visible = false
	challenge_ended.emit(_hits, Tuning.KICK_CHALLENGE_ATTEMPTS)
