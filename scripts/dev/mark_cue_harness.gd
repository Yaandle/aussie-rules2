extends Node3D

## Headless data harness for the ML Experiments page's MLP stage (marking-
## cue timing — docs/ML_AI_AUDIT.md §9). Records real-physics marking
## attempts: a real kick-flight Ball delivered at a real PlayerController,
## pressed on a chosen physics frame, labelled by the controller's own
## mark_caught / mark_missed signals. Nothing here grades anything itself —
## the label is whatever the real resolution (_attempt_running_mark /
## _resolve_aggressive_mark: reach + mark_timing_offset windows) decided.
##
## Run headless (writes the CSVs under DATA_DIR, prints a summary, quits):
##   godot --headless --path . res://scenes/dev/mark_cue_harness.tscn --fixed-fps 60 -- dataset
##   godot --headless --path . res://scenes/dev/mark_cue_harness.tscn --fixed-fps 60 -- probe
## `dataset` is the seeded Latin-hypercube training/validation set; `probe`
## is the separate evaluation grid (bearing x run speed x height, see
## PROBE_*), which also runs closed-loop presses on the analytic and MLP
## cues — so it needs trained weights in MarkCueModel.WEIGHTS_DIR first.
##
## Staging is MARK DELIVERY's (animation_viewer.gd _launch_mark_preview):
## the marker runs straight along -Z at a fixed speed and the ball is a
## real Ball.launch(..., is_kick_disposal = true) solved to reach an aim
## point after a chosen flight time. The brain is AnimationViewer.
## MarkPreviewBrain — a HumanBrain, so the real controller treats it as a
## human (Safe's timing grade, rumble paths), with every input overridden.
## A tap is held live for Tuning.INPUT_BUFFER_WINDOW and then dropped, the
## same lifetime a real buffered press gets (InputManager.consume_buffered_
## press) — without that, a too-early Aggressive press would sit in the
## flag until the range gate opened and "catch" a ball a human's press
## would have long since expired on.
##
## Why bisection rather than one random press per delivery: the MLP learns
## a specific press frame per delivery, the catching press whose contact
## frame finds the ball nearest the hands (_aggressive_label;
## data/ml/mark_cue/README.md). One random press per delivery only says
## "inside or outside". Bisection on the band edges gets each delivery's
## band to BISECT_STEPS precision in ~10 attempts, and every one of those
## attempts also records its contact distance for the label's fit. Running
## needs none of that: its tap resolves the same frame
## it's read, and inside Running's arrived radius mark_timing_offset() is
## 0, so a Running tap catches exactly when the ball is inside Running's
## reach on that frame — readable straight off the no-press trace. That
## rule is CHECKED against real signals (RUNNING_CHECKS random taps per
## run, reported as an agreement %), not assumed.

const PlayerScene := preload("res://scenes/player/player.tscn")
const BallScene := preload("res://scenes/ball/ball.tscn")

## Has a .gdignore: without it Godot imports every CSV here as a
## translation table. FileAccess still reads it in editor/headless runs.
const DATA_DIR := "res://data/ml/mark_cue/"

## Same geometry conventions as MARK DELIVERY. The catch spot is where the
## marker would be at the planned arrival; LEAD moves the marker off it
## along the run (early/late), LATERAL moves the aim point sideways.
const CATCH_SPOT := Vector3(0.0, 0.0, 0.5)
const RELEASE_HEIGHT := 1.4
const AIM_AHEAD := 0.25
const FLIGHT_SIM_STEP := 1.0 / 120.0

## Latin-hypercube ranges for the dataset. Flight speed (horizontal) rather
## than distance is sampled so the hang time and the kick's pace vary
## independently; distance = speed * time, clamped to a real kick's length.
const DATASET_SEED := 20261023
const DATASET_DELIVERIES := 48
const RANGES := {
	"from_deg": Vector2(0.0, 360.0),
	"run_speed": Vector2(0.0, Tuning.SPRINT_SPEED),
	"height": Vector2(0.6, 3.2),
	"flight_time": Vector2(0.9, 2.0),
	"flight_speed": Vector2(12.0, 28.0),
	"lateral": Vector2(-1.2, 1.2),
	"lead": Vector2(-1.5, 1.5),
}
const DISTANCE_MIN := 15.0   # past Tuning.MARK_STAND_MIN_DISTANCE: every catch is a legal mark
const DISTANCE_MAX := 40.0

## Evaluation grid — every combination, at MARK DELIVERY's default kick
## (22 m in 1.45 s), dead-centre aim, no lead error. A grid on purpose, not
## more random samples: ML_AI_AUDIT §7's lesson is that a score measured
## along one path through the input space can hide a model that's wrong
## everywhere else, so the probe walks each axis end to end.
const PROBE_FROM := [0.0, 90.0, 180.0]
const PROBE_RUN := [0.0, Tuning.JOG_SPEED, Tuning.SPRINT_SPEED]
const PROBE_HEIGHT := [0.9, 1.8, 2.8]
const PROBE_FLIGHT_TIME := 1.45
const PROBE_DISTANCE := 22.0

const BISECT_STEPS := 3
## First guess of the bracket's far (missing) end, frames from a catching
## press. Aggressive's band is a few tenths wide (a 3.6 m reach sphere
## crossed at 10-25 m/s), so 30 frames is outside it nearly always; when
## it isn't, the bracket is widened by the same again.
const BRACKET_FRAMES := 30
const MAX_SEED_ATTEMPTS := 5
const RUNNING_CHECKS := 1   ## real Running taps per delivery checking the trace rule

## Frames the no-press trace keeps past the ball's closest approach, and the
## hard stop for any one run.
const TRACE_TAIL_FRAMES := 30
const RUN_TIMEOUT_FRAMES := 300

var _player: PlayerController
var _ball: Ball
var _brain: AnimationViewer.MarkPreviewBrain
var _outcome := ""
var _outcome_tier := Tuning.Action.NONE
var _attempt_rows: Array[String] = []
var _attempt_count := 0
## This delivery's Aggressive attempts so far, for _aggressive_label's fit.
var _delivery_attempts: Array[Dictionary] = []
var _tallies := {}
var _running_agree := 0
var _running_checked := 0


func _ready() -> void:
	add_child(_build_floor())
	# Same-frame-construction race (docs/HANDOVER.md): throwaway players
	# first, and a few physics frames before the real one is touched.
	for i in 3:
		var throwaway := PlayerScene.instantiate()
		add_child(throwaway)
		throwaway.queue_free()
	_ball = BallScene.instantiate()
	add_child(_ball)
	_ball.global_position = Vector3(8.0, 0.3, 8.0)
	_player = PlayerScene.instantiate()
	_player.team = Tuning.Team.AWAY
	add_child(_player)
	_player.global_position = Vector3(0.0, 0.0, 12.0)
	_brain = AnimationViewer.MarkPreviewBrain.new()
	_player.set_brain(_brain)
	_player.mark_caught.connect(func(tier: Tuning.Action, _legal: bool) -> void:
		if _outcome == "":
			_outcome = "caught"
			_outcome_tier = tier)
	_player.mark_missed.connect(func(tier: Tuning.Action) -> void:
		if _outcome == "":
			_outcome = "missed"
			_outcome_tier = tier)
	for i in 10:
		await get_tree().physics_frame

	var args := OS.get_cmdline_user_args()
	var mode := String(args[0]) if args.size() > 0 else "dataset"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_DIR))
	match mode:
		"dataset":
			await _run_dataset()
		"probe":
			await _run_probe()
		"determinism":
			await _check_determinism()
		_:
			push_error("mark_cue_harness: unknown mode '%s'" % mode)
	get_tree().quit()


func _build_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 2.0, 120.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	return body


# ── Deliveries ───────────────────────────────────────────────────────

static func latin_hypercube(count: int, seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var keys: Array = RANGES.keys()
	var strata := {}
	for k in keys:
		var order: Array[int] = []
		for i in count:
			order.append(i)
		# Fisher-Yates on the seeded rng (Array.shuffle uses the global one).
		for i in range(count - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp := order[i]
			order[i] = order[j]
			order[j] = tmp
		strata[k] = order
	var out: Array[Dictionary] = []
	for i in count:
		var d := {"id": i}
		for k in keys:
			var r: Vector2 = RANGES[k]
			var u := (float(strata[k][i]) + rng.randf()) / float(count)
			d[k] = lerpf(r.x, r.y, u)
		d["distance"] = clampf(d.flight_speed * d.flight_time, DISTANCE_MIN, DISTANCE_MAX)
		d.erase("flight_speed")
		out.append(d)
	return out


static func probe_grid() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for from_deg in PROBE_FROM:
		for run in PROBE_RUN:
			for h in PROBE_HEIGHT:
				out.append({"id": out.size(), "from_deg": from_deg, "run_speed": run, "height": h,
					"flight_time": PROBE_FLIGHT_TIME, "distance": PROBE_DISTANCE,
					"lateral": 0.0, "lead": 0.0})
	return out


## Puts the marker back on its run line and launches the ball. The marker
## is re-staged from a standstill on the floor every time (each run first
## waits for the previous one to finish), so every run of the same
## delivery starts from the same state — _check_determinism proves it.
##
## Two steps, a few frames apart: _prestage parks the ball, pinned in the
## air at the release point (Ball.lock_at — the umpire throw-up's hold, no
## freeze transition), and stands the marker on its start spot; _stage
## then sets the run going and launches. Launching straight off wherever
## the last run left the ball (resting on the floor, or carried) gave
## first-frame differences of ~1e-4 m between replays of one delivery —
## Jolt's contact warm-start from the ground contact — and the bisection
## replays every delivery ~10 times, so that had to go.
func _prestage(d: Dictionary) -> void:
	_player.drop_ball()
	_ball.lock_at(_release_point(d))
	_player.global_position = _start_point(d)
	_player.velocity = Vector3.ZERO
	_player._speed = 0.0


func _release_point(d: Dictionary) -> Vector3:
	return CATCH_SPOT + _source_dir(d) * float(d.distance) + Vector3.UP * RELEASE_HEIGHT


func _source_dir(d: Dictionary) -> Vector3:
	var a := deg_to_rad(float(d.from_deg))
	return Vector3(sin(a), 0.0, -cos(a))


func _start_point(d: Dictionary) -> Vector3:
	var arrive := CATCH_SPOT + Vector3.FORWARD * float(d.lead)
	return arrive - Vector3.FORWARD * float(d.run_speed) * float(d.flight_time)


func _stage(d: Dictionary) -> void:
	_player.drop_ball()
	_player._end_mark_retreat()
	_player._mark_readying = false
	_player._gather_cooldown = 0.0
	_player._protected_timer = 0.0
	_player._stun_timer = 0.0
	_player._action = Tuning.Action.NONE
	_player._pending_jump_speed = 0.0
	_brain.safe_hold = false
	_brain.running_tap = false
	_brain.aggressive_tap = false

	var t: float = d.flight_time
	var run: float = d.run_speed
	var yaw := 0.0   # facing -Z
	_player.global_position = _start_point(d)
	_player.rotation.y = yaw
	_player._facing_yaw = yaw
	_player._heading = Vector3.FORWARD
	_player.velocity = Vector3.FORWARD * run
	_player._speed = run
	_brain.wish_dir = Vector3.FORWARD if run > 0.05 else Vector3.ZERO
	_brain.gait_value = gait_for_speed(run)

	var side := _source_dir(d).cross(Vector3.UP).normalized()
	var target := CATCH_SPOT + Vector3.UP * float(d.height) + Vector3.FORWARD * AIM_AHEAD \
		+ side * float(d.lateral)
	var from := _release_point(d)
	var v := launch_velocity(from, target, t)
	var dir := v.normalized()
	var up_reference := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	_ball.global_transform = Transform3D(Basis.looking_at(-dir, up_reference), from)
	_ball.launch(dir, v.length(), Vector3.ZERO, null, true)
	_outcome = ""
	_outcome_tier = Tuning.Action.NONE


## Copy of AnimationViewer._gait_for_speed — the gait a brain asks for to
## hold `speed` m/s.
static func gait_for_speed(speed: float) -> float:
	if speed <= 0.0:
		return 0.0
	if speed < Tuning.WALK_SPEED:
		return remap(speed, 0.0, Tuning.WALK_SPEED, 0.0, Tuning.GAIT_WALK)
	if speed < Tuning.JOG_SPEED:
		return remap(speed, Tuning.WALK_SPEED, Tuning.JOG_SPEED, Tuning.GAIT_WALK, Tuning.GAIT_JOG)
	return clampf(remap(speed, Tuning.JOG_SPEED, Tuning.SPRINT_SPEED, Tuning.GAIT_JOG, 1.0), 0.0, 1.0)


## Copy of AnimationViewer._mark_launch_velocity (shooting method on the
## Ball's own gravity + quadratic drag) — static here so the harness has no
## viewer instance to borrow it from.
static func launch_velocity(from: Vector3, to: Vector3, t: float) -> Vector3:
	var v := (to - from) / t + Vector3.UP * 0.5 * Tuning.GRAVITY * t
	for i in 8:
		v += (to - _simulate_flight(from, v, t)) / t
	return v


static func _simulate_flight(p: Vector3, v: Vector3, t: float) -> Vector3:
	var elapsed := 0.0
	while elapsed < t:
		var dt := minf(FLIGHT_SIM_STEP, t - elapsed)
		var drag := -v * v.length() * Tuning.BALL_DRAG_COEFF / Tuning.BALL_MASS
		v += (drag + Vector3.DOWN * Tuning.GRAVITY) * dt
		p += v * dt
		elapsed += dt
	return p


## One run of delivery `d`. `tier` NONE with press_frame < 0 is the no-press
## trace (every frame's raw features recorded, until TRACE_TAIL_FRAMES past
## the closest approach); otherwise one tap of `tier` on `press_frame`,
## returning the real outcome. Frame 0 is the first frame the controller
## sees the ball in flight; features are read right after physics_frame,
## i.e. exactly the state the controller's own _physics_process reads that
## frame.
func _run(d: Dictionary, tier: Tuning.Action, press_frame: int) -> Dictionary:
	await _settle()
	_prestage(d)
	for i in 4:
		await get_tree().physics_frame
	_stage(d)
	var trace: Array[PackedFloat64Array] = []
	var closest_frame := -1
	var closest_dist := INF
	var actual_press := -1
	var press_features := PackedFloat64Array()
	# Ball-to-hands distance at the start of the frame the outcome fired on —
	# the state _resolve_aggressive_mark / _attempt_running_mark graded, i.e.
	# where the ball was on the clip's contact frame (Aggressive) or the tap
	# (Running). NAN if nothing resolved.
	var contact_dist := NAN
	var prev_dist := NAN
	var f := 0
	while f < RUN_TIMEOUT_FRAMES:
		await get_tree().physics_frame
		var raw := MarkCueModel.raw_state(_player, _ball)
		if tier == Tuning.Action.NONE:
			var dist: float = raw[MarkCueModel.RAW_DIST]
			if _ball.is_airborne() and dist < closest_dist:
				closest_dist = dist
				closest_frame = f
			trace.append(raw)
			if (closest_frame >= 0 and f > closest_frame + TRACE_TAIL_FRAMES) or not _ball.is_airborne():
				break
		else:
			if f == press_frame:
				press_features = raw
				if tier == Tuning.Action.MARK_RUNNING:
					_brain.running_tap = true
				else:
					_brain.aggressive_tap = true
			elif f == press_frame + roundi(Tuning.INPUT_BUFFER_WINDOW * 60.0):
				_brain.running_tap = false
				_brain.aggressive_tap = false
			if actual_press < 0 and f >= press_frame and _player._action == tier:
				actual_press = f
			if _outcome != "":
				contact_dist = prev_dist
				break
			if f > press_frame + 60 and not _ball.is_airborne():
				break
			prev_dist = raw[MarkCueModel.RAW_DIST]
		f += 1
	_brain.running_tap = false
	_brain.aggressive_tap = false
	_brain.wish_dir = Vector3.ZERO
	if tier != Tuning.Action.NONE:
		_attempt_count += 1
	return {"trace": trace, "closest_frame": closest_frame, "closest_dist": closest_dist,
		"outcome": _outcome if _outcome_tier == tier else "no_attempt",
		"actual_press": actual_press, "press_features": press_features, "contact_dist": contact_dist}


## Waits for the previous run to end on its own (landed, no action, stood
## still), so every run is staged from the same resting state.
func _settle() -> void:
	_brain.wish_dir = Vector3.ZERO
	_brain.gait_value = 0.0
	for i in 120:
		await get_tree().physics_frame
		if _player.is_on_floor() and _player._action == Tuning.Action.NONE \
				and _player.velocity.length() < 0.05 and i > 5:
			return


func _record_attempt(set_name: String, d: Dictionary, tier: Tuning.Action, press_frame: int,
		r: Dictionary, note: String) -> void:
	var feats: PackedFloat64Array = r.press_features
	var cols := [set_name, d.id, Tuning.Action.keys()[tier], press_frame, r.actual_press, r.outcome, note,
		"%.4f" % r.contact_dist]
	if tier == Tuning.Action.MARK_AGGRESSIVE:
		_delivery_attempts.append({"press": press_frame, "outcome": r.outcome, "contact_dist": r.contact_dist})
	for i in MarkCueModel.RAW_COUNT:
		cols.append("%.5f" % (feats[i] if i < feats.size() else NAN))
	_attempt_rows.append(",".join(cols.map(func(c): return str(c))))


# ── Band search (Aggressive) ─────────────────────────────────────────

## The label for one delivery: {lo, hi, target, target_contact, run_lo,
## run_hi, holes}. lo/hi are the outermost catching press frames, found by
## bisection from one catching press. target is the press the model learns,
## and it is always a frame a REAL attempt caught on, never an inferred one.
## target_contact is how far the ball was from the hands on that attempt's
## contact frame. run_lo/hi are the stretch of catching presses the target
## is believed to sit in.
##
## Which catching press is "best": the one whose contact frame finds the
## ball nearest the hands, because that's what the cue is for (brief Part
## 2.4: the clip's contact frame meets the ball). Every attempt records its
## contact distance. A quadratic through the catching attempts' (press,
## distance) points gives the minimum, which is clamped to the band and then
## checked with one more real press. The band's midpoint would be the
## obvious target, and it was this label's first version, but the minimum
## sits early in the band, not in the middle. Trained to the midpoint, the
## model caught as often as the analytic ring but put the ball 1.0–1.6 m
## from the hands at contact, where the ring put it at 0.5–0.8 m (MARK
## DELIVERY's CUE readout).
##
## The check is needed because the catching presses are NOT always one
## contiguous run. The ball collides with player bodies (ball.tscn's
## collision_mask includes the players layer). A leap committed at the
## wrong instant can put the body in the ball's path and deflect the ball
## before the contact frame. The determinism mode's every-frame sweep of
## probe delivery 0 (a knee-high ball at a standing player) reads
## 1111111111..1.1..111111111. If the fitted press lands in a hole, the
## label falls back to the catching attempt with the smallest contact
## distance, and `holes` records that this happened.
func _aggressive_label(set_name: String, d: Dictionary, closest_frame: int, gated_cue: int) -> Dictionary:
	var none := {"lo": -1, "hi": -1, "target": -1, "target_contact": NAN, "run_lo": -1, "run_hi": -1, "holes": 0}
	_delivery_attempts.clear()
	var band := await _aggressive_band(set_name, d, closest_frame, gated_cue)
	none.lo = band.x
	none.hi = band.y
	if band.x < 0:
		return none
	var tier := Tuning.Action.MARK_AGGRESSIVE
	var fitted := closest_contact_press(_delivery_attempts, band)
	var r := await _run(d, tier, fitted)
	_record_attempt(set_name, d, tier, fitted, r, "verify")
	var label := none.duplicate()
	if r.outcome == "caught":
		label.target = fitted
		label.target_contact = r.contact_dist
	else:
		label.holes = 1
		for a in _delivery_attempts:
			if a.outcome == "caught" and not is_nan(a.contact_dist) \
					and (is_nan(label.target_contact) or a.contact_dist < label.target_contact):
				label.target = a.press
				label.target_contact = a.contact_dist
	if label.target < 0:
		return none
	# The catching stretch around the target: bounded by the nearest missed
	# attempt on each side, or the band's edges.
	label.run_lo = band.x
	label.run_hi = band.y
	for a in _delivery_attempts:
		if a.outcome == "caught":
			continue
		if a.press < label.target and a.press >= label.run_lo:
			label.run_lo = a.press + 1
		elif a.press > label.target and a.press <= label.run_hi:
			label.run_hi = a.press - 1
	if label.run_lo > band.x or label.run_hi < band.y:
		label.holes = 1
	return label


## Least-squares quadratic through the catching attempts' (press frame,
## contact distance) points; its minimum, clamped into `band`. Falls back to
## the best sample when the points don't make an upward parabola (fewer than
## three distinct presses, or a flat or downward fit).
static func closest_contact_press(attempts: Array[Dictionary], band: Vector2i) -> int:
	var xs: Array[float] = []
	var ys: Array[float] = []
	var best := -1
	var best_d := INF
	for a in attempts:
		if a.outcome != "caught" or is_nan(a.contact_dist):
			continue
		xs.append(float(a.press))
		ys.append(float(a.contact_dist))
		if a.contact_dist < best_d:
			best_d = a.contact_dist
			best = a.press
	if xs.size() >= 3:
		# Centre x for conditioning, then solve the 3x3 normal equations.
		var mx := 0.0
		for x in xs:
			mx += x
		mx /= xs.size()
		var s := [0.0, 0.0, 0.0, 0.0, 0.0]   # sums of dx^0..dx^4
		var t := [0.0, 0.0, 0.0]             # sums of y*dx^0..dx^2
		for i in xs.size():
			var dx := (xs[i] - mx) / 10.0   # tens of frames, so dx^4 stays small for Basis floats
			for k in 5:
				s[k] += pow(dx, k)
			for k in 3:
				t[k] += ys[i] * pow(dx, k)
		var m := Basis(Vector3(s[0], s[1], s[2]), Vector3(s[1], s[2], s[3]), Vector3(s[2], s[3], s[4]))
		if absf(m.determinant()) > 1e-9:
			var coef := m.inverse() * Vector3(t[0], t[1], t[2])   # c, b, a
			if coef.z > 1e-6:
				return clampi(roundi(mx - 10.0 * coef.y / (2.0 * coef.z)), band.x, band.y)
	return best if best >= 0 else roundi((band.x + band.y) * 0.5)


## Earliest and latest press frames the real resolution catches on, found
## by bisection from one catching press — the outer edges only; see
## _aggressive_label for what happens inside them.
func _aggressive_band(set_name: String, d: Dictionary, closest_frame: int, gated_cue: int) -> Vector2i:
	var tier := Tuning.Action.MARK_AGGRESSIVE
	var lead := roundi(Tuning.action_contact_time(tier) * 60.0)
	# Seeds, most likely first: the gated analytic cue (the ungated one is
	# useless as a seed when it fires before the range gate opens — the
	# press just expires), then a leap timed to peak at closest approach,
	# then either side of it. Gate-limited deliveries (fast run-ins from in
	# front) have their band start near the gate opening, LATE relative to
	# closest - lead, which is why +8 comes before -8: an earlier version
	# tried only earlier presses and labelled real bands uncatchable.
	var guesses: Array[int] = []
	if gated_cue >= 0:
		guesses.append(gated_cue)
	for k in [0, 8, -8, 16, -16]:
		if not guesses.has(closest_frame - lead + k):
			guesses.append(closest_frame - lead + k)
	var inside := -1
	for g in guesses.slice(0, MAX_SEED_ATTEMPTS):
		if g < 0:
			continue
		var r := await _run(d, tier, g)
		_record_attempt(set_name, d, tier, g, r, "seed")
		if r.outcome == "caught":
			inside = g
			break
	if inside < 0:
		return Vector2i(-1, -1)
	var lo := await _edge(set_name, d, tier, inside, -1)
	var hi := await _edge(set_name, d, tier, inside, 1)
	return Vector2i(lo, hi)


## Walks out from `inside` (a catching press) in direction `sign` until a
## press misses, then bisects between the two. Returns the last catching
## frame on that side.
func _edge(set_name: String, d: Dictionary, tier: Tuning.Action, inside: int, sign: int) -> int:
	var catch_f := inside
	var miss_f := inside + sign * BRACKET_FRAMES
	for widen in 2:
		if miss_f < 0:
			miss_f = -1
			break
		var r := await _run(d, tier, miss_f)
		_record_attempt(set_name, d, tier, miss_f, r, "bracket")
		if r.outcome != "caught":
			break
		catch_f = miss_f
		miss_f += sign * BRACKET_FRAMES
	for step in BISECT_STEPS:
		if absi(miss_f - catch_f) <= 1:
			break
		var mid := (catch_f + miss_f) / 2
		var r := await _run(d, tier, mid)
		_record_attempt(set_name, d, tier, mid, r, "bisect")
		if r.outcome == "caught":
			catch_f = mid
		else:
			miss_f = mid
	# Bisection stops BISECT_STEPS short of a single frame: report the
	# midpoint of the remaining unresolved gap, not its catching end, so
	# the band's error is symmetric rather than biased inward.
	return roundi((catch_f + miss_f) * 0.5) if absi(miss_f - catch_f) > 1 else catch_f


## Running's band straight off the trace: frames where the ball is airborne
## and inside Running's reach (see this file's header for why that's the
## exact rule, and RUNNING_CHECKS for how it's checked).
static func running_band(trace: Array[PackedFloat64Array]) -> Vector2i:
	var reach := Tuning.MARK_CATCH_RADIUS * Tuning.MARK_RUNNING_REACH_SCALE + Tuning.MARK_ASSIST_RADIUS_BONUS
	var lo := -1
	var hi := -1
	for f in trace.size():
		var raw := trace[f]
		if raw[MarkCueModel.RAW_AIRBORNE] > 0.5 and raw[MarkCueModel.RAW_DIST] <= reach:
			if lo < 0:
				lo = f
			hi = f
		elif lo >= 0:
			break
	return Vector2i(lo, hi)


## First frame the MarkPrompt ring would complete on for `tier` — see
## MarkCueModel.analytic_cue_frame.
static func analytic_cue_frame(trace: Array[PackedFloat64Array], tier: Tuning.Action) -> int:
	return MarkCueModel.analytic_cue_frame(trace, tier)


# ── Modes ────────────────────────────────────────────────────────────

func _run_dataset() -> void:
	var t0 := Time.get_ticks_msec()
	var deliveries := latin_hypercube(DATASET_DELIVERIES, DATASET_SEED)
	var rng := RandomNumberGenerator.new()
	rng.seed = DATASET_SEED + 1
	var delivery_rows: Array[String] = [delivery_header()]
	var trace_rows: Array[String] = [trace_header()]
	_attempt_rows = [attempt_header()]
	for d in deliveries:
		var obs := await _run(d, Tuning.Action.NONE, -1)
		var trace: Array[PackedFloat64Array] = obs.trace
		var cue_a := analytic_cue_frame(trace, Tuning.Action.MARK_AGGRESSIVE)
		var cue_r := analytic_cue_frame(trace, Tuning.Action.MARK_RUNNING)
		var label_a := await _aggressive_label("dataset", d, obs.closest_frame,
			MarkCueModel.analytic_cue_frame(trace, Tuning.Action.MARK_AGGRESSIVE, true))
		var band_r := running_band(trace)
		await _check_running_rule(d, trace, band_r, rng)
		delivery_rows.append(delivery_row(d, obs, label_a, band_r, cue_a, cue_r))
		for f in trace.size():
			trace_rows.append(trace_row(d.id, f, trace[f]))
		print("delivery %2d  from %5.1f  run %.1f  h %.2f  T %.2f  D %.1f  lat %+.2f  lead %+.2f | closest f%d %.2fm | AGGR band %d-%d target %d%s cue %d | RUN band %s cue %d | attempts so far %d" % [
			d.id, d.from_deg, d.run_speed, d.height, d.flight_time, d.distance, d.lateral, d.lead,
			obs.closest_frame, obs.closest_dist, label_a.lo, label_a.hi, label_a.target,
			" HOLES" if label_a.holes else "", cue_a, band_r, cue_r, _attempt_count])
	_write(DATA_DIR + "deliveries.csv", delivery_rows)
	_write(DATA_DIR + "trace.csv", trace_rows)
	_write(DATA_DIR + "attempts.csv", _attempt_rows)
	print("dataset: %d deliveries, %d real attempts, Running trace rule agreed with %d/%d real taps, %.1f s" % [
		deliveries.size(), _attempt_count, _running_agree, _running_checked,
		(Time.get_ticks_msec() - t0) / 1000.0])


## RUNNING_CHECKS real taps per delivery — half inside the trace band, half
## just outside it when there is one, where a wrong rule would show first.
func _check_running_rule(d: Dictionary, trace: Array[PackedFloat64Array], band: Vector2i,
		rng: RandomNumberGenerator) -> void:
	for k in RUNNING_CHECKS:
		var f: int
		# Alternates inside / just outside by delivery, so one tap each still
		# checks both sides of the rule across the set.
		if band.x >= 0 and (k + int(d.id)) % 2 == 0:
			f = rng.randi_range(band.x, band.y)
		elif band.x >= 0:
			f = band.x - rng.randi_range(1, 4) if rng.randf() < 0.5 else band.y + rng.randi_range(1, 4)
		else:
			f = rng.randi_range(0, trace.size() - 1)
		var predicted := band.x >= 0 and f >= band.x and f <= band.y
		var r := await _run(d, Tuning.Action.MARK_RUNNING, f)
		_record_attempt("dataset", d, Tuning.Action.MARK_RUNNING, f, r, "rule_check")
		_running_checked += 1
		if predicted == (r.outcome == "caught"):
			_running_agree += 1
		else:
			print("  RUNNING rule disagreed: delivery %d frame %d predicted %s real %s" % [d.id, f, predicted, r.outcome])


## Evaluation: the probe grid's bands found the same way as the dataset's,
## then one real press per tier on each cue (the analytic ring as shipped,
## the analytic ring with MarkCueModel.press_registers' gate, and the
## MLP's) — the closed-loop check that the model's cue actually lands
## presses inside the band, measured by the real signals rather than
## inferred from the regression error.
func _run_probe() -> void:
	var t0 := Time.get_ticks_msec()
	var models := {}
	for tier in [Tuning.Action.MARK_AGGRESSIVE, Tuning.Action.MARK_RUNNING]:
		var m := MarkCueModel.load_for_tier(tier)
		if m == null:
			push_error("mark_cue_harness probe: no trained weights for %s in %s" % [Tuning.Action.keys()[tier], MarkCueModel.WEIGHTS_DIR])
			return
		models[tier] = m
	var grid := probe_grid()
	var delivery_rows: Array[String] = [delivery_header()]
	var trace_rows: Array[String] = [trace_header()]
	var cue_rows: Array[String] = ["delivery,tier,source,cue_frame,band_lo,band_hi,outcome,contact_dist"]
	_attempt_rows = [attempt_header()]
	for d in grid:
		var obs := await _run(d, Tuning.Action.NONE, -1)
		var trace: Array[PackedFloat64Array] = obs.trace
		var cue_a := analytic_cue_frame(trace, Tuning.Action.MARK_AGGRESSIVE)
		var cue_r := analytic_cue_frame(trace, Tuning.Action.MARK_RUNNING)
		var label_a := await _aggressive_label("probe", d, obs.closest_frame,
			MarkCueModel.analytic_cue_frame(trace, Tuning.Action.MARK_AGGRESSIVE, true))
		var band_a := Vector2i(label_a.lo, label_a.hi)
		var band_r := running_band(trace)
		delivery_rows.append(delivery_row(d, obs, label_a, band_r, cue_a, cue_r))
		for f in trace.size():
			trace_rows.append(trace_row(d.id, f, trace[f]))
		var line := "probe %2d  from %3d run %.1f h %.1f |" % [d.id, d.from_deg, d.run_speed, d.height]
		for tier in [Tuning.Action.MARK_AGGRESSIVE, Tuning.Action.MARK_RUNNING]:
			var band := band_a if tier == Tuning.Action.MARK_AGGRESSIVE else band_r
			var analytic := cue_a if tier == Tuning.Action.MARK_AGGRESSIVE else cue_r
			var gated := MarkCueModel.analytic_cue_frame(trace, tier, true)
			var mlp: int = (models[tier] as MarkCueModel).cue_frame(trace)
			for pair in [["analytic", analytic], ["analytic_gated", gated], ["mlp", mlp]]:
				var outcome := "no_cue"
				var contact := NAN
				if int(pair[1]) >= 0:
					var r := await _run(d, tier, int(pair[1]))
					_record_attempt("probe_" + String(pair[0]), d, tier, int(pair[1]), r, "cue")
					outcome = r.outcome
					contact = r.contact_dist
				cue_rows.append("%d,%s,%s,%d,%d,%d,%s,%.4f" % [d.id, Tuning.Action.keys()[tier], pair[0], pair[1], band.x, band.y, outcome, contact])
				line += " %s %s f%d %s %.2fm |" % [Tuning.Action.keys()[tier].substr(5, 4), String(pair[0]).replace("analytic_gated", "gated"), pair[1], outcome, contact]
				_tally(String(Tuning.Action.keys()[tier]) + " " + String(pair[0]), outcome, contact)
			line += " band %s%s |" % [band, " HOLES" if tier == Tuning.Action.MARK_AGGRESSIVE and label_a.holes else ""]
		print(line)
	_write(DATA_DIR + "probe_deliveries.csv", delivery_rows)
	_write(DATA_DIR + "probe_trace.csv", trace_rows)
	_write(DATA_DIR + "probe_attempts.csv", _attempt_rows)
	_write(DATA_DIR + "probe_cues.csv", cue_rows)
	print("probe: %d deliveries, %d real attempts, %.1f s" % [grid.size(), _attempt_count,
		(Time.get_ticks_msec() - t0) / 1000.0])
	for key in _tallies:
		var t: Dictionary = _tallies[key]
		print("  %-26s caught %2d / %2d   mean ball-to-hands at contact %.2f m (over %d resolved presses)" % [
			key, t.caught, t.n, t.dist / maxf(1.0, t.resolved), t.resolved])


## Closed-loop tallies for the probe summary: per "TIER source", how many
## cue presses caught and the mean contact distance of those that resolved.
func _tally(key: String, outcome: String, contact: float) -> void:
	if not _tallies.has(key):
		_tallies[key] = {"n": 0, "caught": 0, "dist": 0.0, "resolved": 0}
	var t: Dictionary = _tallies[key]
	t.n += 1
	if outcome == "caught":
		t.caught += 1
	if not is_nan(contact):
		t.dist += contact
		t.resolved += 1


## Same delivery twice, no press: every frame's raw state has to match, or
## the bisection (which replays a delivery once per attempt) is measuring
## noise. Also a dense press sweep on two deliveries, confirming the
## catching presses really are one contiguous run (the bisection's one
## assumption).
func _check_determinism() -> void:
	var d := latin_hypercube(DATASET_DELIVERIES, DATASET_SEED)[3]
	var a := await _run(d, Tuning.Action.NONE, -1)
	var b := await _run(d, Tuning.Action.NONE, -1)
	var worst := 0.0
	var n := mini(a.trace.size(), b.trace.size())
	for f in n:
		for i in MarkCueModel.RAW_COUNT:
			worst = maxf(worst, absf(a.trace[f][i] - b.trace[f][i]))
	print("determinism: %d vs %d frames, worst raw-state difference %.6f" % [a.trace.size(), b.trace.size(), worst])
	for dd in [latin_hypercube(DATASET_DELIVERIES, DATASET_SEED)[11], probe_grid()[0], probe_grid()[5]]:
		var obs := await _run(dd, Tuning.Action.NONE, -1)
		var lead := roundi(Tuning.action_contact_time(Tuning.Action.MARK_AGGRESSIVE) * 60.0)
		var from_f := maxi(0, obs.closest_frame - lead - 30)
		var s := ""
		for f in range(from_f, obs.closest_frame + 4):
			var r := await _run(dd, Tuning.Action.MARK_AGGRESSIVE, f)
			s += "1" if r.outcome == "caught" else ("." if r.outcome == "missed" else "-")
		print("contiguity delivery %d (AGGR press every frame from f%d; 1 caught, . missed, - no attempt):\n  %s" % [dd.id, from_f, s])
		# The same presses again, interleaved, after catches and misses.
		var again := ""
		for f in [from_f + 30, from_f + 36, from_f + 30, from_f + 42, from_f + 36, from_f + 42]:
			var r := await _run(dd, Tuning.Action.MARK_AGGRESSIVE, f)
			again += "f%d:%s " % [f, r.outcome]
		print("  replays: " + again)


# ── CSV ──────────────────────────────────────────────────────────────

static func delivery_header() -> String:
	return "delivery,from_deg,run_speed,height,flight_time,distance,lateral,lead,closest_frame,closest_dist,aggr_lo,aggr_hi,aggr_target,aggr_target_contact,aggr_run_lo,aggr_run_hi,aggr_holes,run_lo,run_hi,run_target,aggr_analytic_cue,run_analytic_cue"


static func delivery_row(d: Dictionary, obs: Dictionary, label_a: Dictionary, band_r: Vector2i, cue_a: int, cue_r: int) -> String:
	# Running's target is the trace's closest approach: its tap resolves on the
	# frame it's read, so that frame IS its contact, and it's inside the band
	# whenever there is one (the band is the frames within reach).
	var run_target: int = obs.closest_frame if band_r.x >= 0 else -1
	return "%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.4f,%d,%d,%d,%.4f,%d,%d,%d,%d,%d,%d,%d,%d" % [d.id, d.from_deg,
		d.run_speed, d.height, d.flight_time, d.distance, d.lateral, d.lead, obs.closest_frame, obs.closest_dist,
		label_a.lo, label_a.hi, label_a.target, label_a.target_contact, label_a.run_lo, label_a.run_hi,
		label_a.holes, band_r.x, band_r.y, run_target, cue_a, cue_r]


static func trace_header() -> String:
	return "delivery,frame," + ",".join(MarkCueModel.RAW_NAMES)


static func trace_row(id: int, f: int, raw: PackedFloat64Array) -> String:
	var cols: Array[String] = [str(id), str(f)]
	for v in raw:
		cols.append("%.5f" % v)
	return ",".join(cols)


static func attempt_header() -> String:
	return "set,delivery,tier,press_frame,actual_press_frame,outcome,note,contact_dist," + ",".join(MarkCueModel.RAW_NAMES)


func _write(path: String, rows: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("mark_cue_harness: can't write %s" % path)
		return
	file.store_string("\n".join(rows) + "\n")
	file.close()
