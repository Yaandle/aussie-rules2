class_name CoachNPC
extends Node3D

## A stationary training NPC — the kicking coach now, a marking coach and a
## tackling coach later (design brief), all reusing this same shell: a
## proximity trigger and a visual body, configured per coach rather than
## subclassed. What each coach actually offers (which challenge it starts)
## is decided by whoever spawns it (kick_to_kick.gd), not hardcoded here.
##
## The body is a bare instance of the existing placeholder rig, reused
## as-is rather than authored fresh — this script owns the interaction
## trigger, not a character model (out of scope for this agent; see
## docs/HANDOVER.md's kicking-coach section). Deliberately not a full
## PlayerController: no brain, no gather zone, no tackle eligibility, so
## it can't accidentally steal a loose ball or take a tackle just by
## standing on the field.

signal player_entered_range(player: PlayerController)
signal player_left_range(player: PlayerController)

@onready var _zone: Area3D = $InteractZone


var _player_in_range: PlayerController = null


func _ready() -> void:
	var shape := SphereShape3D.new()
	shape.radius = Tuning.COACH_INTERACT_RADIUS
	($InteractZone/CollisionShape3D as CollisionShape3D).shape = shape
	_zone.body_entered.connect(_on_body_entered)
	_zone.body_exited.connect(_on_body_exited)


func player_in_range() -> PlayerController:
	return _player_in_range


## Turns to face a world point, flat (no pitch) — used to look at the
## field centre at rest and at the player once a conversation starts.
func face_toward(point: Vector3) -> void:
	var to_point := point - global_position
	to_point.y = 0.0
	if to_point.length_squared() < 0.0001:
		return
	rotation.y = atan2(-to_point.x, -to_point.z)


func _on_body_entered(body: Node3D) -> void:
	if is_instance_valid(_player_in_range):
		return
	var player := body as PlayerController
	if player == null:
		return
	_player_in_range = player
	player_entered_range.emit(player)


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		player_left_range.emit(body)
