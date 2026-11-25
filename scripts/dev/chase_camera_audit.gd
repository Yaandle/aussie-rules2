extends Node

## The 3rd-person (CHASE) camera, measured on a real AI-v-AI Full Game
## (2026-11-25, "a camera the player never notices"). The home player the
## camera follows gets an AI brain, the rig stays on CHASE behind them, and
## every frame is logged: how much the lens shakes (position acceleration),
## how hard it turns (angular acceleration), how often the arm jumps, how
## often the lens is inside something solid, and how far the view points
## from where the player is running.
##
## Godot --headless --fixed-fps 60 --path . res://scenes/dev/chase_camera_audit.tscn -- --seconds=90
## Prints one CHASE_AUDIT line. Run it on the old and new camera to compare.

const FULL_GAME := "res://scenes/modes/full_game.tscn"

var _game: Node
var _camera: BroadcastCamera
var _player: PlayerController
var _seconds := 90.0
var _sim := 0.0
var _pos: Array[Vector3] = []
var _fwd: Array[Vector3] = []
var _arm: Array[float] = []
var _inside := 0
var _off_heading: Array[float] = []
var _probe := PhysicsShapeQueryParameters3D.new()
## Frames the automatic view was fully in / turning the view (new rig only).
var _auto_full := 0
var _auto_turning := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			_seconds = float(arg.get_slice("=", 1))
	HighlightPrefs.transient = true
	GameState.career_active = false
	Settings.player_control_mode = Settings.PlayerControlMode.SINGLE_PLAYER
	_game = (load(FULL_GAME) as PackedScene).instantiate()
	add_child(_game)
	_player = ControlMode.controlled_player(Tuning.Team.HOME)
	var slot: int = (_game.get("_home_players") as Array).find(_player)
	_player.set_brain(_game.call("_configure_ai_brain", AIBrain.new(), Tuning.Team.HOME, 1.0,
		_game.call("_kickoff_slot", slot, 1.0, Tuning.Team.HOME)))
	_camera = _game.get("_camera") as BroadcastCamera
	_camera.set_mode(BroadcastCamera.Mode.CHASE)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	_probe.shape = sphere
	_probe.collision_mask = 1


func _process(delta: float) -> void:
	_sim += delta
	if _camera.mode != BroadcastCamera.Mode.CHASE:
		_camera.set_mode(BroadcastCamera.Mode.CHASE)
	if _camera.target != _player:
		_camera.target = _player
	var cam := _camera.camera()
	if _sim > 3.0:
		var t := cam.global_transform
		_pos.append(t.origin)
		_fwd.append(-t.basis.z)
		_arm.append(cam.position.z)
		_probe.transform = Transform3D(Basis.IDENTITY, t.origin)
		if not cam.get_world_3d().direct_space_state.intersect_shape(_probe, 1).is_empty():
			_inside += 1
		if float(_camera.get("_auto") if _camera.get("_auto") != null else 0.0) >= 0.99:
			_auto_full += 1
		if absf(float(_camera.get("_yaw_vel") if _camera.get("_yaw_vel") != null else 0.0)) > 0.01:
			_auto_turning += 1
		var v := _player.velocity
		v.y = 0.0
		if v.length() > 3.0:
			var f := -t.basis.z
			f.y = 0.0
			_off_heading.append(rad_to_deg(f.normalized().angle_to(v.normalized())))
			if OS.has_environment("AUDIT_DEBUG") and Engine.get_process_frames() % 30 == 0:
				var face := -_player.global_transform.basis.z
				face.y = 0.0
				var sv: Vector3 = _camera.get("_vel_smooth")
				print("DBG off=%.0f face_vs_vel=%.0f cam_vs_smooth=%.0f speed=%.1f ball_air=%s auto=%.2f" % [rad_to_deg(f.normalized().angle_to(v.normalized())),
					rad_to_deg(face.normalized().angle_to(v.normalized())), rad_to_deg(f.normalized().angle_to(sv.normalized())), v.length(),
					str(_camera.ball.is_airborne()) if _camera.ball != null else "-", float(_camera.get("_auto"))])
	if _sim >= _seconds + 3.0:
		_report(delta)
		get_tree().quit()


func _report(dt: float) -> void:
	var accel: Array[float] = []
	var turn: Array[float] = []
	var cuts := 0
	var arm_jumps := 0
	for i in range(2, _pos.size()):
		var a := (_pos[i] - 2.0 * _pos[i - 1] + _pos[i - 2]).length() / (dt * dt)
		# A teleport (a restart, a switch) is a cut, not shake.
		if (_pos[i] - _pos[i - 1]).length() > 2.0 or (_pos[i - 1] - _pos[i - 2]).length() > 2.0:
			cuts += 1
			continue
		accel.append(a)
		var w1 := _fwd[i - 1].angle_to(_fwd[i]) / dt
		var w0 := _fwd[i - 2].angle_to(_fwd[i - 1]) / dt
		turn.append(rad_to_deg(absf(w1 - w0)) / dt)
		if absf(_arm[i] - _arm[i - 1]) > 0.3:
			arm_jumps += 1
	print("CHASE_AUDIT frames=%d cuts=%d shake_m_s2 p50=%.1f p95=%.1f p99=%.1f max=%.0f turn_accel_deg_s2 p50=%.0f p95=%.0f p99=%.0f arm_jumps=%d inside=%d off_heading_deg p50=%.0f p90=%.0f auto_full=%d auto_turning=%d" % [
		_pos.size(), cuts, _pct(accel, 0.5), _pct(accel, 0.95), _pct(accel, 0.99), _pct(accel, 1.0),
		_pct(turn, 0.5), _pct(turn, 0.95), _pct(turn, 0.99), arm_jumps, _inside,
		_pct(_off_heading, 0.5), _pct(_off_heading, 0.9), _auto_full, _auto_turning])


static func _pct(values: Array[float], q: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return float(s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)])
