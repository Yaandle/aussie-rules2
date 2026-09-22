# scripts/dev/tackle_lab.gd
## Instrumentation layer that sits between the animation viewer's contest
## runner and the real _resolve_tackle_contact path.
## Observe mode: connects to tackle_resolved signal on both contest players,
## accumulates samples, writes CSV, calls fit().
## Sweep mode: runs TackleExperiment.sweep() on the fitted or default model.
## No visual of its own — results go to the status label and CSV.
class_name TackleLab
extends RefCounted

const Model  = preload("res://scripts/dev/tackle_model.gd")
const Exp    = preload("res://scripts/dev/tackle_experiment.gd")

signal sweep_done(rows: Array, param: String)
signal fit_done(model: Resource, sample_count: int)
signal status_changed(text: String)

var _samples: Array = []
var _connected_players: Array = []
var _active_model: Resource = null

# ── Observe ──────────────────────────────────────────────────────────

## Call after each contest launch with the two PlayerControllers.
## Disconnects automatically when replaced or when stop_observe() is called.
func start_observe(player_a: PlayerController, player_b: PlayerController) -> void:
	_disconnect_all()
	_connected_players = [player_a, player_b]
	for p in _connected_players:
		p.tackle_resolved.connect(_on_tackle_resolved)
	status_changed.emit("OBSERVE — waiting for contact")

func stop_observe() -> void:
	_disconnect_all()
	status_changed.emit("OBSERVE stopped — %d samples" % _samples.size())

func clear_samples() -> void:
	_samples.clear()
	status_changed.emit("samples cleared")

func save_and_fit(path: String = "user://tackle_observe.csv") -> void:
	if _samples.is_empty():
		status_changed.emit("no samples yet")
		return
	_write_observe_csv(path)
	_active_model = Exp.fit(_samples)
	fit_done.emit(_active_model, _samples.size())
	status_changed.emit(
		"fit done  n=%d  w=(%.2f, %.2f, %.2f)  b=%.2f" % [
			_samples.size(),
			_active_model.w_speed,
			_active_model.w_angle,
			_active_model.w_stamina,
			_active_model.bias,
		])

func _on_tackle_resolved(closing_speed: float, angle_deg: float,
		carrier_speed: float, broke: bool) -> void:
	# Normalise to the ranges the model expects (same convention as
	# tackle_selftest.gd's neutral inputs).
	var dspeed  := closing_speed / Tuning.SPRINT_SPEED
	var angle   := clampf(angle_deg / Tuning.TACKLE_SLIDE_MAX_ANGLE_DEG, 0.0, 1.0)
	var stamina := 1.0   # stub until fatigue exists
	_samples.append({"dspeed": dspeed, "angle": angle, "stamina": stamina,
		"broke": 1 if broke else 0})
	status_changed.emit("OBSERVE — %d samples" % _samples.size())

func _disconnect_all() -> void:
	for p in _connected_players:
		if is_instance_valid(p) and p.tackle_resolved.is_connected(_on_tackle_resolved):
			p.tackle_resolved.disconnect(_on_tackle_resolved)
	_connected_players.clear()

func _write_observe_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("dspeed,angle,stamina,broke")
	for s in _samples:
		f.store_line("%.4f,%.4f,%.4f,%d" % [s.dspeed, s.angle, s.stamina, s.broke])

# ── Sweep ─────────────────────────────────────────────────────────────

func run_sweep(param: String, values: Array, inputs: Dictionary,
		attempts: int = 1000, path: String = "") -> void:
	var m: Resource = _active_model if _active_model != null else Model.new()
	var rows: Array = Exp.sweep(m, param, values, inputs, attempts)
	if path != "":
		Exp.to_csv(rows, path)
	var sens := Exp.sensitivity(rows, 0, rows.size() - 1)
	status_changed.emit(
		"SWEEP %s  slope=%.1f pp/unit  saved=%s" % [
			param, sens, path if path != "" else "no"])
	sweep_done.emit(rows, param)

func active_model() -> Resource:
	return _active_model