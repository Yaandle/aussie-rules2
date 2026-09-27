class_name AnimationViewer
extends Node3D

## Dev-only viewer for the placeholder animation set (docs/FEATURE_AUDIT.md
## "unbuilt but planned" tooling): a bare HumanoidRig driven by the real
## AnimationTree, standing still, with buttons to force each locomotion
## blend point and fire each discrete action clip in isolation. Not reachable
## from the main menu — open scenes/dev/animation_viewer.tscn directly in the
## editor and press F6, same precedent as scenes/main.tscn's own sandbox.
##
## Locomotion is previewed "on the spot" by driving PlayerAnimation's blend
## space directly rather than moving a CharacterBody3D — the locomotion
## clips only ever write hip bob + joint rotation tracks (see
## player_animation.gd's own "NOT YET WIRED: root motion" note), so nothing
## about the rig's own position needs to change for a gait to read.
##
## Deliberately shows only what has a real clip. Spoil stays a pure physics
## reaction today (knockback — see PlayerController._try_spoil) with no
## AnimationTree state behind it (and no Tuning.Action of its own to hang
## one on); player_animation.gd's ACTION_STATES map is the source of truth
## for which Tuning.Action values actually animate. It shows as a disabled
## button here rather than being left out silently, so this screen stays an
## honest map of what exists versus what's still physics-only.
##
## Every tackle-family clip (TACKLED, TACKLE_GRAB, TACKLE_HELD, TACKLE_
## TAKEDOWN, KNOCKED_BACK, SMOTHERED, SMOTHER_DIVE) is an OUTCOME of a real
## contest, not a canned pose — none of them have their own button in the
## plain ACTIONS list below. Instead the CONTESTS
## group spawns a second, real PlayerController (design brief: "if I select
## the tackle features just generate another character in and run the
## simulation of the player doing the action") and runs a short, fixed,
## non-interactive scripted approach through the same real gameplay code
## every contest resolves through in a match (_resolve_tackle_contact,
## _try_bump_contact, _try_smother_contact) — not a simplified stand-in.
## This replaces the previous pass's free-roam "Tackle Sandbox" mode
## entirely (full field, switch_player, live human input) — deliberately
## removed per direct feedback: this screen is a fixed preview you click and
## watch, the same shape as every other button here, not a second thing to
## learn how to drive.
##
## The SEQUENCES group (same column as CONTESTS) covers the motions that
## aren't a single clip and aren't an opponent contest either: a bounce on
## the run (carrier + real ball, driven into the turf and re-gathered), the
## walk-back off a legal mark (Tuning.MARK_RETREAT_*, run_back blend while
## facing stays downfield), and the field Umpire's ball-up throw-up (its own
## rig and hand-posed crouch/wind/toss — see umpire.gd — with a real Ball
## riding the grip then launched at Tuning.BALL_UP_TOSS_SPEED, the same
## release FullGame._begin_ruck_contest performs). All run through the real
## gameplay code, same as the contests.
##
## A CONTROL group sits above the three preview columns with a FREE MOVE
## toggle: swaps the bare preview rig for a real, solo PlayerController
## under real input (see _ensure_free_player_built), roaming a bigger
## bounded grid built by the same code the pose-preview studio floor uses.
## Solo only for now — no second body to kick to, no camera changes while
## moving; both are natural follow-ups once this lands. Toggling off
## routes back through the same _show_single_subject every other button
## already uses.

const STAND_ON := Vector3.ZERO

const CAMERA_DISTANCE := 8.0
const CAMERA_HEIGHT := 1.0

const SUBJECT_SCREEN_FRACTION := 0.667


## How far left of the subject the camera sits — pushes the figure right of
## centre in frame (same trick character_backdrop.gd uses via its own
## CAMERA_SIDESTEP) so it clears the three button columns on the left
## rather than standing directly behind them.
const CAMERA_SIDESTEP := 2.5

## Pulled back and raised from the single-subject framing above — a contest
## needs room for two bodies and a few metres of approach, not a portrait
## crop of one standing figure.
const CONTEST_CAMERA_DISTANCE := 8.0
const CONTEST_CAMERA_HEIGHT := 1.6
const CONTEST_CAMERA_SIDESTEP := 1.5

## Wireframe floor grid, drawn in code with ImmediateMesh (same technique
## as skeleton_wireframe.gd, which this scene also attaches to the rig —
## no turf here, just a bounded reference square so the figure reads
## against something instead of floating in flat white).
const GRID_HALF_EXTENT := 1.6
const GRID_STEP := 0.4
const GRID_COLOUR := Color(0.72, 0.75, 0.79)

## Free-move floor: same grid technique as the pose-preview one, just
## bigger — enough room to actually walk/run rather than stand on the
## spot. Kept inside the existing contest floor's physics bound (half-
## extent 10, see _build_contest_floor) so the visible grid never outruns
## what you can actually stand on.
const FREE_MOVE_GRID_HALF_EXTENT := 9.0
const FREE_MOVE_GRID_STEP := 1.0

## Locomotion buttons: label -> blend target. Must agree with
## PlayerAnimation.BLEND_POINTS.
const LOCOMOTION := [
	["IDLE", Vector2(0.0, 0.0)],
	["JOG FWD", Vector2(0.0, 0.55)],
	["RUN FWD", Vector2(0.0, 1.0)],
	["RUN BACK", Vector2(0.0, -1.0)],
	["STRAFE L", Vector2(-1.0, 0.0)],
	["STRAFE R", Vector2(1.0, 0.0)],
	["RUN FWD L", Vector2(-0.75, 0.75)],
	["RUN FWD R", Vector2(0.75, 0.75)],
]

## Action buttons: label -> Tuning.Action. Matches player_animation.gd's
## ACTION_STATES minus the tackle-family entries (TACKLED/TACKLE_GRAB/
## SMOTHERED/SMOTHER_DIVE) — those are contest outcomes, not standalone
## poses, and live in the CONTESTS group below instead.
const ACTIONS := [
	["KICK", Tuning.Action.KICK],
	["HANDBALL", Tuning.Action.HANDBALL],
	["BOUNCE", Tuning.Action.BOUNCE],
	["MARK — SAFE", Tuning.Action.MARK_SAFE],
	["MARK — RUNNING", Tuning.Action.MARK_RUNNING],
	["MARK — AGGRESSIVE", Tuning.Action.MARK_AGGRESSIVE],
	["MARK — SAFE MISS", Tuning.Action.MARK_SAFE_MISS],
	["MARK — RUNNING MISS", Tuning.Action.MARK_RUNNING_MISS],
	["HIT-OUT", Tuning.Action.HIT_OUT],
]

## No AnimationTree state exists for this yet (see class doc) — listed so
## the gap is visible on the screen itself rather than a silent omission.
const UNIMPLEMENTED := ["SPOIL"]

## Contest scenarios: label -> ContestKind. Each spawns/reuses a second real
## PlayerController and runs a short scripted approach ending in the real
## contest resolver, exactly the "generate another character and run the
## simulation" the brief asked for.
enum ContestKind { TACKLE_SLIDE, TACKLE_LUNGE, BUMP_CLEAN, BUMP_MISS, SMOTHER }

const CONTESTS := [
	["TACKLE — SLIDE", ContestKind.TACKLE_SLIDE],
	["TACKLE — LUNGE", ContestKind.TACKLE_LUNGE],
	["BUMP — CLEAN HIT", ContestKind.BUMP_CLEAN],
	["BUMP — MISS", ContestKind.BUMP_MISS],
	["SMOTHER", ContestKind.SMOTHER],
]

## Scripted solo/prop sequences — no opposing player, but not a single
## canned clip either: they need real bodies/props and gameplay code to
## read right. See _launch_sequence / _step_sequence.
enum SequenceKind { BOUNCE_RUN, MARK_RETREAT, UMPIRE_BALLUP }

const SEQUENCES := [
	["BOUNCE — ON THE RUN", SequenceKind.BOUNCE_RUN],
	["MARK — RETREAT OFF MARK", SequenceKind.MARK_RETREAT],
	["UMPIRE — BALL-UP", SequenceKind.UMPIRE_BALLUP],
]

## Seconds a BOUNCE_RUN / MARK_RETREAT carrier runs (or holds) before the
## scripted trigger fires, so the action has real motion behind it rather
## than firing from a standstill. UMPIRE_BALLUP uses its own release point
## instead (Tuning.BALL_UP_THROW_DURATION * Umpire.THROW_RELEASE_END).
const SEQUENCE_TRIGGER_DELAY := 0.9

## How long a sequence runs before it stops being _step_sequence's problem
## and the bodies are just left to settle (same intent as CONTEST_TIMEOUT).
const SEQUENCE_TIMEOUT := 4.5

## Bump has no brain-mediated trigger (_update_bump reads InputManager.
## flick_vector() directly, a raw device gesture — see that function's own
## doc comment) — a scripted vignette has no device to generate one, so
## BUMP_CLEAN/BUMP_MISS below inject the dash fields directly instead, the
## same "assign the private fields, no headless device to fake" approach
## this project's own scratch physics tests already use. This is the delay
## (seconds before launch) before that injection fires, giving the carrier
## time to close some real distance and speed first so the assist has
## something genuine to correct rather than firing at point-blank range.
const BUMP_CONTEST_TRIGGER_DELAY := 0.6

## BUMP — MISS only: shortens the dash's own travel window for this
## vignette specifically (viewer-side only, does not touch Tuning.BUMP_
## DASH_DURATION or anything a real match uses) — feedback on the first
## version was the whiff carried the bumper too far and off the edge of
## the floor grid below. Distance scales directly with this (BUMP_DASH_
## SPEED unchanged), so 0.5 halves it.
const BUMP_MISS_CONTEST_DASH_SCALE := 0.5

## How long an APPROACH phase waits for a contest to resolve before giving
## up and holding anyway (a missed cue shouldn't hang the screen forever).
const CONTEST_TIMEOUT := 3.0

## Synthetic vertical hop, independent of the skeleton — there is no jump
## clip to preview (MARK — AGGRESSIVE is the only clip with a jump built
## in, and it already has its own button). Arbitrary dev-tool timing, not
## a gameplay number — does not touch Tuning.
const JUMP_HEIGHT := 0.45
const JUMP_RISE_TIME := 0.28
const JUMP_FALL_TIME := 0.32

## Every clickable control on this screen is one width/height so the three
## columns line up as a grid rather than a ragged stack of 200/220px odds.
const BUTTON_WIDTH := 180.0
const BUTTON_HEIGHT := 26.0

## Camera moves between the single-subject framing and the wider contest one
## are eased over this rather than cut — a hard jump between two quite
## different distances (4m vs 8m) reads as a glitch, not a shot change.
const CAMERA_MOVE_TIME := 0.35

const EXPERIMENT_SWIPE_TIME := 0.32
const EXPERIMENT_CAMERA_DISTANCE := 4.2
const EXPERIMENT_CAMERA_HEIGHT := 1.1
const EXPERIMENT_CAMERA_SIDESTEP := 0.0

const PlayerScene := preload("res://scenes/player/player.tscn")
const BallScene := preload("res://scenes/ball/ball.tscn")

const TackleModelScript := preload("res://scripts/dev/tackle_model.gd")
const TackleExperimentScript := preload("res://scripts/dev/tackle_experiment.gd")
const TackleChartScript := preload("res://scripts/dev/tackle_chart.gd")

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $Overlay/UI

var _subject: Node3D
var _rig: HumanoidRig
var _wireframe: SkeletonWireframe
var _player_animation: PlayerAnimation
var _current_blend := Vector2.ZERO
var _state_label: Label
var _blend_label: Label
var _jump_tween: Tween

var _preview_columns: HBoxContainer
var _studio_floor: MeshInstance3D
var _camera_tween: Tween
var _root_layout: VBoxContainer

# ML Experiments
var _experiment_layer: Control
var _experiment_panel: PanelContainer
var _experiment_status: Label
var _experiment_model_label: Label
var _experiment_results: Label
var _experiment_open := false
var _experiment_layer_tween: Tween
var _experiment_w2 := 0.2
var _experiment_attempts := 1000
var _experiment_cube: Node3D

var _contest_built := false
var _contest_floor: StaticBody3D
var _contest_ball: Ball
var _contest_a: PlayerController
var _contest_b: PlayerController
var _brain_a: ContestBrain
var _brain_b: ContestBrain
var _contest_status_label: Label

enum ContestStage { NONE, APPROACH, HOLD }
var _contest_kind := ContestKind.TACKLE_SLIDE
var _contest_stage := ContestStage.NONE
var _contest_timer := 0.0
var _contest_bump_triggered := false

## SEQUENCES state — its own stage/timer so _step_contest's resolved-
## detection never trips on a sequence. The Umpire rig is built lazily on
## the first UMPIRE_BALL-UP press, same reasoning as _contest_built.
var _umpire: Umpire
var _sequence_kind := SequenceKind.BOUNCE_RUN
var _sequence_stage := ContestStage.NONE
var _sequence_timer := 0.0
var _sequence_triggered := false

## Free move — solo real PlayerController under real input, roaming the
## bigger grid above. Built lazily on the first FREE MOVE press, same
## reasoning as _contest_built. See the "Free move" section near the
## bottom for the functions that drive this.
var _free_player: PlayerController
var _free_brain: PlayerBrain
var _free_player_built := false
var _free_move_active := false
var _free_move_floor: MeshInstance3D
var _free_move_hints: KeyHintBar
var _free_move_button: Button
var _player_construction_warmed := false


var _experiment_success_label: Label
var _experiment_z_label: Label
var _experiment_s2_label: Label
var _experiment_sf_label: Label


## Non-input brain for both contest characters — every want is a plain
## field this script sets directly, the scripted-choreography equivalent
## of HumanBrain reading real Input/InputManager. wish_direction() returns
## world space unconverted (no camera to be relative to; every scenario's
## approach direction below is already authored in world space).
class ContestBrain extends PlayerBrain:
	var wish_dir := Vector3.ZERO
	var gait_value := 0.0
	var tackle_wanted := false
	var lunge_wanted := false
	var smother_wanted := false
	var kick_wanted := false
	var bounce_wanted := false

	func wish_direction(_controller: PlayerController) -> Vector3:
		return wish_dir

	func gait() -> float:
		return gait_value

	func wants_tackle() -> bool:
		return tackle_wanted

	func wants_lunge_tackle() -> bool:
		return lunge_wanted

	func wants_smother() -> bool:
		return smother_wanted

	func wants_kick() -> bool:
		return kick_wanted

	func wants_bounce() -> bool:
		return bounce_wanted


func _ready() -> void:
	add_child(_build_ground_plane())
	add_child(_build_fill_light())
	_studio_floor = _build_studio_floor()
	add_child(_studio_floor)
	_build_subject()
	_camera.rotation = Vector3.ZERO
	_camera.position = STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE)
	_build_ui()


## A large white ground the figure stands on, meeting the flat-white sky with
## no visible horizon — a seamless studio cove — so the key light's shadow
## has something to fall on and the model reads as grounded rather than
## floating. Same near-white as the background (materials/dev_studio_
## environment.tres) so the cove stays seamless; sits a hair below the y=0
## reference grid so the grid lines still read on top without z-fighting.
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


## A dim fill from the camera-right, opposite the key, so the shadow side of
## the figure keeps some form instead of crushing to flat ambient. No shadow
## of its own — one soft contact shadow from the key is the whole intent.
func _build_fill_light() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = "Fill"
	light.rotation_degrees = Vector3(-28.0, -46.0, 0.0)
	light.light_energy = 0.28
	light.shadow_enabled = false
	return light


func _process(delta: float) -> void:
	if _subject.visible and _player_animation != null:
		_player_animation.drive(_current_blend, delta)
		_state_label.text = "STATE: %s" % String(_player_animation.current_state()).to_upper()
		var b := _player_animation.blend_position()
		_blend_label.text = "BLEND: %.2f, %.2f" % [b.x, b.y]
	_step_contest(delta)
	_step_sequence(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"character_menu"):
		SceneWipe.change_scene("res://scenes/ui/main_menu.tscn")


# ── Subject: rig + the same AnimationPlayer/AnimationTree/PlayerAnimation
# trio player.tscn wires up, built in code since there are no other exported
# params to set and the default `../Rig` / `../AnimationPlayer` /
# `../AnimationTree` NodePaths on PlayerAnimation just need matching
# siblings, not a specific scene layout. ─────────────────────────────────

func _build_subject() -> void:
	_subject = Node3D.new()
	_subject.position = STAND_ON
	_subject.rotation.y = deg_to_rad(180.0)   # face the camera
	add_child(_subject)

	_rig = HumanoidRig.new()
	_rig.name = "Rig"
	_rig.away_kit = false
	_rig.high_detail = true   # one figure on screen — see HumanoidRig.high_detail
	_subject.add_child(_rig)

	# Bone-line overlay over the mesh — see skeleton_wireframe.gd's own
	# header, which names exactly this kind of single-figure preview as
	# the case it's meant for. Unused everywhere else in the project until
	# now. Flags below (set before it enters the tree, so _ready() reads
	# them) turn on the viewer-only polish — a full on-top overlay with
	# joint markers and no stray root line.
	_wireframe = SkeletonWireframe.new()
	_wireframe.name = "SkeletonWireframe"
	_wireframe.on_top = true
	_wireframe.show_joints = true
	_wireframe.skip_root = true
	_subject.add_child(_wireframe)
	_wireframe.track(_rig.skeleton())

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	_subject.add_child(player)

	var tree := AnimationTree.new()
	tree.name = "AnimationTree"
	tree.active = false
	_subject.add_child(tree)

	_player_animation = PlayerAnimation.new()
	_player_animation.name = "PlayerAnimation"
	_subject.add_child(_player_animation)


# ── UI ───────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.position = Vector2(10.0, 14.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override(&"separation", 16)
	_ui.add_child(root)
	_root_layout = root

	root.add_child(UIStyle.label("ANIMATION VIEWER — DEV", UIStyle.SIZE_TITLE,
		UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_TITLE))

	var status := HBoxContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_constant_override(&"separation", 24)
	root.add_child(status)
	_state_label = UIStyle.label("STATE: —", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	_blend_label = UIStyle.label("BLEND: 0.00, 0.00", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	status.add_child(_state_label)
	status.add_child(_blend_label)

	root.add_child(_build_control_group())

	_preview_columns = HBoxContainer.new()
	_preview_columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_columns.add_theme_constant_override(&"separation", 24)
	root.add_child(_preview_columns)

	_preview_columns.add_child(_build_locomotion_group())
	_preview_columns.add_child(_build_action_group())
	_preview_columns.add_child(_build_contest_group())
	_preview_columns.add_child(_build_misc_group())

	var hints := KeyHintBar.new()
	hints.position = Vector2(24.0, 674.0)
	hints.set_hints([
		{"keys": "Esc / C", "label": "Back to menu"},
	])
	_ui.add_child(hints)

	_free_move_hints = KeyHintBar.new()
	_free_move_hints.position = Vector2(24.0, 140.0)
	_free_move_hints.visible = false
	_free_move_hints.set_hints([
		{"keys": "WASD", "label": "Move"},
		{"keys": "Kick / Handball / Bounce", "label": "Action inputs"},
	])
	_ui.add_child(_free_move_hints)

	_build_experiment_layer()


func _build_experiment_layer() -> void:
	_experiment_layer = Control.new()
	_experiment_layer.name = "ExperimentLayer"
	_experiment_layer.custom_minimum_size = get_window().size
	_experiment_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_experiment_layer.visible = false
	_ui.add_child(_experiment_layer)

	_experiment_panel = PanelContainer.new()
	_experiment_panel.position = Vector2(24.0, 24.0)
	_experiment_panel.custom_minimum_size = Vector2(380.0, 600.0)
	_experiment_panel.size = Vector2(380.0, 600.0)
	_experiment_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_experiment_layer.add_child(_experiment_panel)

	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(RetroWindow.PANEL, 0.97)
	panel_box.border_color = RetroWindow.BORDER
	panel_box.set_border_width_all(2)
	panel_box.set_corner_radius_all(RetroWindow.RADIUS)
	panel_box.content_margin_left = 18.0
	panel_box.content_margin_right = 18.0
	panel_box.content_margin_top = 16.0
	panel_box.content_margin_bottom = 16.0
	_experiment_panel.add_theme_stylebox_override(&"panel", panel_box)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(344.0, 560.0)
	_experiment_panel.add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	scroll.add_child(root)

	# ── Title ──────────────────────────────────────────
	root.add_child(UIStyle.label(
		"ML Experiments",
		UIStyle.SIZE_TITLE,
		UIStyle.TEXT_PRIMARY,
		UIStyle.WEIGHT_HEAVY
	))
	root.add_child(_muted_caption("Tackle model: adjust inputs and weights, then run a sweep."))
	root.add_child(HSeparator.new())

	# ── Metric cards: P(break) / Tackle success ─────────
	var metrics := GridContainer.new()
	metrics.columns = 2
	metrics.add_theme_constant_override(&"h_separation", 12)
	metrics.add_theme_constant_override(&"v_separation", 12)
	root.add_child(metrics)

	var pb_card := _metric_card("P(BREAK)")
	_experiment_model_label = pb_card.value_label
	metrics.add_child(pb_card.node)

	var ts_card := _metric_card("TACKLE SUCCESS")
	_experiment_success_label = ts_card.value_label
	metrics.add_child(ts_card.node)

	_experiment_z_label = _mono_caption("")
	root.add_child(_experiment_z_label)

	# ── Inputs ───────────────────────────────────────────
	root.add_child(_section_heading("Inputs"))

	var dspeed := _slider_row(root, "Δspeed", -2.0, 4.0, 0.1, 2.0)
	var angle := _slider_row(root, "Angle", -2.0, 2.0, 0.1, 1.0)
	var stamina := _slider_row(root, "Stamina", 0.0, 2.0, 0.1, 1.0)

	# ── Weights ──────────────────────────────────────────
	root.add_child(_section_heading("Weights"))

	var w1 := _slider_row(root, "w₁ speed", -1.0, 2.0, 0.1, 0.8)
	var w2 := _slider_row(root, "w₂ angle", 0.0, 1.0, 0.05, 0.2)
	var w3 := _slider_row(root, "w₃ stamina", 0.0, 1.5, 0.1, 0.5)
	var bias := _slider_row(root, "b bias", -3.0, 1.0, 0.1, -1.0)

	var recompute := func() -> void:
		var z := w1.value * dspeed.value + w2.value * angle.value \
			+ w3.value * stamina.value + bias.value
		var p := 1.0 / (1.0 + exp(-z))
		_experiment_model_label.text = "%.1f%%" % (p * 100.0)
		_experiment_success_label.text = "%.1f%%" % ((1.0 - p) * 100.0)
		_experiment_z_label.text = "z = %.2f" % z
		_experiment_w2 = w2.value

	for s in [dspeed, angle, stamina, w1, w2, w3, bias]:
		s.value_changed.connect(func(_v): recompute.call())
	recompute.call()

	# ── Experiment 01: sweep w₂ ──────────────────────────
	root.add_child(_section_heading("Experiment 01: sweep w₂"))

	var run_row := HBoxContainer.new()
	run_row.add_theme_constant_override(&"separation", 10)
	root.add_child(run_row)

	var attempts := OptionButton.new()
	attempts.add_item("100 attempts each", 100)
	attempts.add_item("1,000 attempts each", 1000)
	attempts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_row.add_child(attempts)

	var run := _make_button("RUN")
	run.pressed.connect(func() -> void:
		var n := attempts.get_selected_id()
		_run_tackle_experiment(
			dspeed.value,
			angle.value,
			stamina.value,
			w2.value,
			n
		)
	)
	run_row.add_child(run)

	var back_button := _make_button("← Back")
	back_button.add_theme_font_size_override(&"font_size", UIStyle.SIZE_LABEL)
	back_button.pressed.connect(func() -> void:
		_set_experiments_open(false)
	)
	root.add_child(back_button)

	# Legend
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override(&"separation", 16)
	root.add_child(legend)
	legend.add_child(_legend_item("Simulated", UIStyle.ACCENT))
	legend.add_child(_legend_item("Illustrative", UIStyle.TEXT_MUTED))

	_experiment_results = UIStyle.label(
		"Results\n—",
		UIStyle.SIZE_LABEL,
		UIStyle.TEXT_PRIMARY
	)
	root.add_child(_experiment_results)

	var summary := GridContainer.new()
	summary.columns = 2
	summary.add_theme_constant_override(&"h_separation", 12)
	summary.add_theme_constant_override(&"v_separation", 12)
	root.add_child(summary)

	var s2_card := _metric_card("0.2 → 0.8")
	_experiment_s2_label = s2_card.value_label
	summary.add_child(s2_card.node)

	var sf_card := _metric_card("0.0 → 0.8")
	_experiment_sf_label = sf_card.value_label
	summary.add_child(sf_card.node)

	_experiment_status = _muted_caption("Percentage points per weight unit.")
	root.add_child(_experiment_status)




# ── Helpers ───────────────────────────────────────────────

func _metric_card(caption: String) -> Dictionary:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(RetroWindow.PANEL, 0.6)
	style.set_corner_radius_all(RetroWindow.RADIUS)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	box.add_theme_stylebox_override(&"panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 2)
	box.add_child(col)

	col.add_child(UIStyle.label(caption, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED))
	var value := UIStyle.label("—", UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_BOLD)
	col.add_child(value)

	return {"node": box, "value_label": value}

func _section_heading(text: String) -> Label:
	var l := UIStyle.label(text.to_upper(), UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD)
	return l

func _muted_caption(text: String) -> Label:
	return UIStyle.label(text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)

func _mono_caption(text: String) -> Label:
	return UIStyle.label(text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)

func _legend_item(text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(10.0, 10.0)
	swatch.color = color
	row.add_child(swatch)
	row.add_child(UIStyle.label(text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED))
	return row

func _slider_row(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step: float, default: float) -> HSlider:
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override(&"h_separation", 10)
	parent.add_child(row)

	var label := UIStyle.label(label_text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	label.custom_minimum_size.x = 76.0
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = default
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var out := UIStyle.label("%.2f" % default, UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY)
	out.custom_minimum_size.x = 44.0
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(out)

	slider.value_changed.connect(func(v: float) -> void:
		out.text = "%.2f" % v
	)

	return slider
func _on_experiments_toggled(on: bool) -> void:
	_set_experiments_open(on)


# ── ML Experiments swipe transition ────────────────────────────────────

func _set_experiments_open(open: bool) -> void:
	_experiment_open = open
	if _experiment_layer_tween != null and _experiment_layer_tween.is_valid():
		_experiment_layer_tween.kill()

	var viewport_width := maxf(0.0, get_window().size.x)
	var hidden_x := viewport_width
	var shown_x := 0.0

	if open:
		_show_single_subject()
		_move_camera_to(STAND_ON + Vector3(-EXPERIMENT_CAMERA_SIDESTEP, EXPERIMENT_CAMERA_HEIGHT, EXPERIMENT_CAMERA_DISTANCE))
		_ensure_experiment_cube_built()
		if _experiment_cube != null:
			_experiment_cube.visible = true
		_studio_floor.visible = false
		_root_layout.visible = false
		_experiment_layer.visible = true
		_experiment_layer.position.x = hidden_x
	else:
		_studio_floor.visible = true
		if _experiment_cube != null:
			_experiment_cube.visible = false

	_experiment_layer_tween = create_tween()
	_experiment_layer_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_experiment_layer_tween.tween_property(
		_experiment_layer, "position:x", shown_x if open else hidden_x, EXPERIMENT_SWIPE_TIME
	)
	if not open:
		_experiment_layer_tween.finished.connect(func() -> void:
			_experiment_layer.visible = false
			_root_layout.visible = true
			_move_camera_to(STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE))
		)


## Placeholder for experiment visualization cube — build if needed for
## displaying model/simulation results in 3D space. For now, a no-op stub.
func _ensure_experiment_cube_built() -> void:
	if _experiment_cube != null:
		return
	# TODO: Build experiment visualization cube if desired
	# _experiment_cube = MeshInstance3D.new()
	# ...setup...
	# add_child(_experiment_cube)


func _build_control_group() -> HBoxContainer:
	var group := HBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 12)
	group.add_child(UIStyle.label("CONTROL", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	var toggle := _make_button("FREE MOVE")
	toggle.toggle_mode = true
	toggle.toggled.connect(_on_free_move_toggled)
	group.add_child(toggle)
	_free_move_button = toggle

	var experiment_button := _make_button("EXPERIMENTS")
	experiment_button.toggle_mode = true
	experiment_button.toggled.connect(_on_experiments_toggled)
	group.add_child(experiment_button)

	return group


func _run_tackle_experiment(
		dspeed: float,
		angle: float,
		stamina: float,
		w2: float,
		attempts: int
	) -> void:
	var model = TackleModelScript.new()
	model.w_angle = w2

	var probability := model.p_break(dspeed, angle, stamina)
	var success_probability := 1.0 - probability

	_experiment_model_label.text = (
		"P(BREAK): %.1f%%\nTACKLE SUCCESS: %.1f%%"
		% [probability * 100.0, success_probability * 100.0]
	)

	var inputs := {
		"dspeed": dspeed,
		"angle": angle,
		"stamina": stamina,
	}

	var values := [0.0, 0.2, 0.4, 0.6, 0.8]
	var rows: Array = TackleExperimentScript.sweep(
		model,
		"w_angle",
		values,
		inputs,
		attempts,
		1
	)

	var result_text := "RESULTS\n"
	for row in rows:
		result_text += (
			"w₂ %.1f  %.1f%%  [%d/%d]\n"
			% [
				row.value,
				row.rate,
				row.successes,
				row.attempts
			]
		)

	result_text += "\nSENSITIVITY\n"
	result_text += "%.1f pp / weight unit" % TackleExperimentScript.slope(rows)

	_experiment_results.text = result_text
	_experiment_status.text = "MODEL: COMPLETE  |  SIMULATION: WIRED"


func _build_locomotion_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("LOCOMOTION — ON THE SPOT", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	var toggle_group := ButtonGroup.new()
	for entry: Array in LOCOMOTION:
		var label: String = entry[0]
		var blend: Vector2 = entry[1]
		var button := _make_button(label)
		button.toggle_mode = true
		button.button_group = toggle_group
		button.button_pressed = blend == Vector2.ZERO
		button.pressed.connect(func() -> void:
			_show_single_subject()
			_current_blend = blend)
		group.add_child(button)
	return group


func _build_action_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("ACTIONS", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	for entry: Array in ACTIONS:
		var label: String = entry[0]
		var action: Tuning.Action = entry[1]
		var button := _make_button(label)
		button.pressed.connect(func() -> void:
			_show_single_subject()
			_player_animation.play_action(action))
		group.add_child(button)
	return group


func _build_contest_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("CONTESTS — SPAWNS AN OPPONENT", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	for entry: Array in CONTESTS:
		var label: String = entry[0]
		var kind: ContestKind = entry[1]
		var button := _make_button(label)
		button.pressed.connect(func() -> void: _launch_contest(kind))
		group.add_child(button)

	group.add_child(UIStyle.label("SEQUENCES — CARRIER / BALL / UMPIRE", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	for entry: Array in SEQUENCES:
		var label: String = entry[0]
		var kind: SequenceKind = entry[1]
		var button := _make_button(label)
		button.pressed.connect(func() -> void: _launch_sequence(kind))
		group.add_child(button)

	_contest_status_label = UIStyle.label("", UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	group.add_child(_contest_status_label)
	return group


func _build_misc_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 8)
	group.add_child(UIStyle.label("OTHER", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))

	var jump_button := _make_button("JUMP")
	jump_button.pressed.connect(func() -> void:
		_show_single_subject()
		_on_jump_pressed())
	group.add_child(jump_button)

	# Show/hide the bone overlay — on by default, the "pressed" style doubling
	# as the on state exactly like the LOCOMOTION toggles.
	var wire_button := _make_button("WIREFRAME")
	wire_button.toggle_mode = true
	wire_button.button_pressed = true
	wire_button.toggled.connect(func(on: bool) -> void:
		if _wireframe != null:
			_wireframe.visible = on)
	group.add_child(wire_button)

	group.add_child(UIStyle.label("PHYSICS-ONLY — NO CLIP YET", UIStyle.SIZE_LABEL,
		UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))
	for label: String in UNIMPLEMENTED:
		var button := _make_button(label)
		button.disabled = true
		group.add_child(button)
	return group


## Local-only shrink for this screen's button labels — 17.5% off
## UIStyle.SIZE_LABEL, applied as a per-button override rather than
## touching the shared constant, so nothing outside this dev tool changes.
## BUTTON_WIDTH/BUTTON_HEIGHT (the outer control's own minimum size) are
## untouched, so the smaller text just gets more breathing room.
const MENU_LABEL_SCALE := 0.825

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE   # mouse-click screen; no cursor to steal focus
	button.add_theme_font_override(&"font", UIStyle.font(UIStyle.WEIGHT_BOLD, UIStyle.TRACK_LABEL))
	button.add_theme_font_size_override(&"font_size", int(UIStyle.SIZE_LABEL * MENU_LABEL_SCALE))
	for colour: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
		button.add_theme_color_override(colour, RetroWindow.BORDER)
	button.add_theme_color_override(&"font_disabled_color", UIStyle.TEXT_MUTED)
	button.add_theme_stylebox_override(&"normal", _button_box(&"normal"))
	button.add_theme_stylebox_override(&"hover", _button_box(&"hover"))
	button.add_theme_stylebox_override(&"pressed", _button_box(&"pressed"))
	button.add_theme_stylebox_override(&"disabled", _button_box(&"disabled"))
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	return button


func _button_box(kind: StringName) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(RetroWindow.RADIUS)   # sharp, matching the shell
	box.set_border_width_all(2)
	box.border_color = RetroWindow.BORDER
	box.content_margin_left = 8.0
	box.content_margin_right = 8.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	box.anti_aliasing_size = 1.0
	match kind:
		&"hover":
			box.bg_color = RetroWindow.ACCENT.lightened(0.66)
			box.border_color = RetroWindow.ACCENT
		&"pressed":
			box.bg_color = RetroWindow.ACCENT.lightened(0.42)
			box.border_color = RetroWindow.ACCENT
		&"disabled":
			box.bg_color = Color(RetroWindow.PANEL, 0.45)
			box.border_color = SoftBrutalist.DISABLED_BORDER
		_:   # normal
			box.bg_color = RetroWindow.PANEL
	return box


func _on_jump_pressed() -> void:
	if _jump_tween != null and _jump_tween.is_valid():
		_jump_tween.kill()
	_rig.position.y = 0.0
	_jump_tween = create_tween()
	_jump_tween.tween_property(_rig, "position:y", JUMP_HEIGHT, JUMP_RISE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_jump_tween.tween_property(_rig, "position:y", 0.0, JUMP_FALL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## Swaps which subject is visible/live — the bare single-figure rig for
## every plain locomotion/action/jump button, or the two-body contest for
## CONTESTS. Both keep existing once built (contest bodies keep simulating
## physics even while hidden — there are only ever these three bodies in
## this scene, no ambiguity for _nearest_player's group scan to trip over,
## same reasoning the old sandbox mode already relied on), this just picks
## which one is on screen and getting driven by _process.
func _show_single_subject() -> void:
	_subject.visible = true
	_move_camera_to(STAND_ON + Vector3(-_screen_fraction_sidestep(), CAMERA_HEIGHT, CAMERA_DISTANCE))
	if _contest_built:
		_contest_a.visible = false
		_contest_b.visible = false
		_contest_ball.visible = false
	if _umpire != null:
		_umpire.visible = false
	if _free_player_built:
		_free_player.visible = false
	if _free_move_floor != null:
		_free_move_floor.visible = false
	_contest_stage = ContestStage.NONE
	_sequence_stage = ContestStage.NONE

	_free_move_active = false
	_studio_floor.visible = true
	_preview_columns.visible = true
	_free_move_hints.visible = false
	if _free_move_button != null:
		_free_move_button.set_pressed_no_signal(false)


func _show_contest() -> void:
	_subject.visible = false
	_contest_a.visible = true
	_contest_b.visible = true
	_contest_ball.visible = true
	if _umpire != null:
		_umpire.visible = false
	if _free_player_built:
		_free_player.visible = false
	if _free_move_floor != null:
		_free_move_floor.visible = false
	_free_move_active = false
	if _free_move_button != null:
		_free_move_button.set_pressed_no_signal(false)
	_preview_columns.visible = true
	_free_move_hints.visible = false
	_move_camera_to(STAND_ON \
		+ Vector3(-CONTEST_CAMERA_SIDESTEP, CONTEST_CAMERA_HEIGHT, CONTEST_CAMERA_DISTANCE))


## Eases the camera to a framing rather than cutting. Only the two preview
## modes are ever this far apart; every plain locomotion/action button
## re-targets the same single-subject spot, so those calls settle instantly
## (the tween is already there) and cost nothing.
func _move_camera_to(target: Vector3) -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera.rotation = Vector3.ZERO
	if _camera.position.is_equal_approx(target):
		return
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(_camera, "position", target, CAMERA_MOVE_TIME)

## Converts SUBJECT_SCREEN_FRACTION (0=left edge, 0.5=centre, 1=right edge)
## into a world-space camera sidestep at CAMERA_DISTANCE, using the
## camera's own horizontal FOV — this is what makes the 66%-across framing
## hold across window resolutions instead of a hardcoded metre offset.
func _screen_fraction_sidestep() -> float:
	var half_width_at_distance := CAMERA_DISTANCE * tan(deg_to_rad(_camera.fov) * 0.5) * _camera.get_viewport().get_visible_rect().size.aspect()
	# fraction 0.5 => sidestep 0 (centred); 1.0 => full half-width right.
	return (SUBJECT_SCREEN_FRACTION - 0.5) * 2.0 * half_width_at_distance



# ── Contests: real PlayerController/Ball physics, two bodies, a short
# scripted approach through the real gameplay resolvers, fixed camera —
# not a free-roam sandbox. See ContestKind/CONTESTS above. ───────────────

## Physics floor only — split out of _ensure_contest_built so free-move
## can get somewhere to stand without paying for two PlayerControllers it
## doesn't use. Shared by both.
func _ensure_contest_floor_built() -> void:
	if _contest_floor != null:
		return
	_contest_floor = _build_contest_floor()
	add_child(_contest_floor)


func _ensure_contest_ball_built() -> void:
	if _contest_ball != null:
		return
	_contest_ball = BallScene.instantiate()
	add_child(_contest_ball)


## Same-frame-construction-race workaround (docs/HANDOVER.md, Tackle
## Sandbox + TACKLED entries): a handful of throwaway PlayerControllers
## spawned and freed first, ahead of any PlayerController that actually
## matters. Split into its own guarded function so whichever of contests
## or free-move builds first pays this cost exactly once, rather than it
## being tied to _ensure_contest_built specifically.
func _ensure_player_construction_warmed() -> void:
	if _player_construction_warmed:
		return
	_player_construction_warmed = true
	for i in 3:
		var throwaway := PlayerScene.instantiate()
		add_child(throwaway)
		throwaway.queue_free()


func _ensure_contest_built() -> void:
	if _contest_built:
		return
	_contest_built = true

	_ensure_contest_floor_built()
	_ensure_player_construction_warmed()
	_ensure_contest_ball_built()

	# high_detail set before add_child so the rig's own _ready() builds the
	# fuller mesh — same window, same one-to-three-bodies budget as the
	# single subject (see HumanoidRig.high_detail).
	_contest_a = PlayerScene.instantiate()
	_contest_a.team = Tuning.Team.HOME
	(_contest_a.get_node("Rig") as HumanoidRig).high_detail = true
	add_child(_contest_a)
	_contest_a.global_position = Vector3(-2.0, 0.0, 0.0)
	_brain_a = ContestBrain.new()
	_contest_a.set_brain(_brain_a)

	_contest_b = PlayerScene.instantiate()
	_contest_b.team = Tuning.Team.AWAY
	var rig_b := _contest_b.get_node("Rig") as HumanoidRig
	rig_b.away_kit = true
	rig_b.high_detail = true
	add_child(_contest_b)
	_contest_b.global_position = Vector3(2.0, 0.0, 0.0)   # distinct from A's spot from frame 0
	_brain_b = ContestBrain.new()
	_contest_b.set_brain(_brain_b)


## A small, flat collision floor — deliberately not the full 165x135m
## Field scene (design brief: "remove it... instead of me being able to
## move the player around freely it is fixed"); a fixed-camera vignette
## only ever needs a few metres of ground under two bodies, not a full
## oval with markings and goalposts. Same StaticBody3D/BoxShape3D shape
## and collision_layer=1/mask=0 as Field's own "Ground" node, just sized
## for this screen instead.
func _build_contest_floor() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "ContestFloor"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 2.0, 20.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	return body


## Field Umpire rig, built on the first UMPIRE_BALL-UP press — its own
## HumanoidRig (via kit_* overrides) and hand-posed throw-up, nothing to do
## with the two contest PlayerControllers. See umpire.gd.
func _ensure_umpire() -> void:
	if _umpire != null:
		return
	_umpire = Umpire.new()
	_umpire.role = Umpire.Role.FIELD
	add_child(_umpire)
	_umpire.visible = false


## Clears both contest bodies + both brains back to a clean slate. Shared
## by _launch_contest and _launch_sequence so neither leaves the other's
## last run bleeding into the next (a live tackle hold, a pending dash, a
## still-running stage timer).
func _reset_contest_state() -> void:
	_contest_stage = ContestStage.NONE
	_sequence_stage = ContestStage.NONE

	_contest_a.velocity = Vector3.ZERO
	_contest_b.velocity = Vector3.ZERO
	_contest_a._stun_timer = 0.0
	_contest_b._stun_timer = 0.0
	_contest_a._action = Tuning.Action.NONE
	_contest_b._action = Tuning.Action.NONE
	_contest_a._bump_dash_timer = 0.0
	_contest_a._bump_dash_active = false
	_contest_a._bump_cooldown = 0.0
	_contest_a._lunge_tap_cooldown = 0.0
	_contest_a._smother_dive_timer = 0.0
	_contest_a._smother_dive_cooldown = 0.0
	_contest_a._knockdown_hop_timer = 0.0
	_contest_b._knockdown_hop_timer = 0.0
	# A Slide connect locks the two bodies together for the length of the
	# grab (PlayerController._begin_tackle_hold) — re-running a scenario
	# while one is still live would have the new setup's teleported
	# positions immediately dragged back toward the old contest.
	_contest_a._end_tackle_hold()
	_contest_b._end_tackle_hold()
	_contest_a._end_mark_retreat()
	_contest_a.drop_ball()
	_contest_b.drop_ball()
	_contest_ball.unlock()

	for brain in [_brain_a, _brain_b]:
		brain.wish_dir = Vector3.ZERO
		brain.gait_value = 0.0
		brain.tackle_wanted = false
		brain.lunge_wanted = false
		brain.smother_wanted = false
		brain.kick_wanted = false
		brain.bounce_wanted = false


## Resets both contest bodies' timers/possession/brain wants, then sets up
## whichever scenario `kind` is — see ContestKind. Re-callable: pressing
## the same CONTESTS button again just tears down and re-runs the same
## scenario from scratch, the "generate another character and run the
## simulation" behaviour applying every time, not just the first.
func _launch_contest(kind: ContestKind) -> void:
	_ensure_contest_built()
	_show_contest()
	_reset_contest_state()

	match kind:
		# TACKLE — SLIDE is the one to watch for the hold: once it
		# connects, the two bodies are pinned together at Tuning.TACKLE_
		# HOLD_DISTANCE and turned to face each other for the full 1.0s
		# grab, so the tackler is visibly wrapped around the carrier
		# rather than the two clips playing side by side. Nothing here
		# arranges that — it comes from the real _try_tackle path this
		# vignette already runs through.
		ContestKind.TACKLE_SLIDE:
			_contest_a.global_position = Vector3(0.0, 0.0, -3.0)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.0, 0.0, 0.5)
			_contest_b.rotation.y = 0.0
			_contest_b.give_possession(_contest_ball)
			_brain_a.wish_dir = Vector3(0.0, 0.0, 1.0)
			_brain_a.gait_value = 1.0
			_brain_a.tackle_wanted = true
		ContestKind.TACKLE_LUNGE:
			_contest_a.global_position = Vector3(0.0, 0.0, -1.5)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.0, 0.0, 0.5)
			_contest_b.rotation.y = 0.0
			_contest_b.give_possession(_contest_ball)
			_brain_a.wish_dir = Vector3(0.0, 0.0, 1.0)
			_brain_a.gait_value = 0.6
			_brain_a.lunge_wanted = true
		ContestKind.BUMP_CLEAN:
			_contest_a.global_position = Vector3(0.0, 0.0, -2.0)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.0, 0.0, 3.0)
			_contest_b.rotation.y = 0.0
			_contest_b.give_possession(_contest_ball)
			_brain_b.wish_dir = Vector3(0.0, 0.0, -1.0)
			_brain_b.gait_value = 1.0
		ContestKind.BUMP_MISS:
			# Half-length dash (BUMP_MISS_CONTEST_DASH_SCALE, in _step_
			# contest below) covers ~1.9m along +Z from here — B sits near
			# the far end of that run, 0.85m to the side (comfortably past
			# the 0.7m two collision capsules would need to actually touch)
			# so A visibly runs up close, whiffs just wide, and its own
			# follow-through carries it past B's position — all of it
			# inside the floor grid's ±1.6m extent.
			_contest_a.global_position = Vector3(0.0, 0.0, -1.0)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.85, 0.0, 0.5)
			_contest_b.rotation.y = 0.0
		ContestKind.SMOTHER:
			_contest_a.global_position = Vector3(0.0, 0.0, -2.5)
			_contest_a.rotation.y = deg_to_rad(180.0)
			_contest_b.global_position = Vector3(0.0, 0.0, 0.3)
			_contest_b.rotation.y = 0.0
			_contest_b.give_possession(_contest_ball)
			_brain_a.smother_wanted = true
			_brain_b.kick_wanted = true

	_contest_kind = kind
	_contest_stage = ContestStage.APPROACH
	_contest_timer = 0.0
	_contest_bump_triggered = false


## Drives the running scenario each frame. Bump's dash is injected directly
## (see BUMP_CONTEST_TRIGGER_DELAY's own doc comment); everything else is
## fully brain-mediated — _update_smother/_try_tackle/_try_lunge_tackle all
## fire on their own the moment the scripted approach brings the bodies
## into real range, through the identical resolvers a real match uses.
## Once resolved (or CONTEST_TIMEOUT expires), this goes quiet — the
## contest bodies keep simulating on their own (a knockdown's own Action
## duration naturally plays out the fall AND the recovery with no extra
## logic needed here), it just stops being this function's job.
func _step_contest(delta: float) -> void:
	if _contest_stage == ContestStage.NONE:
		return
	_contest_timer += delta

	if _contest_stage == ContestStage.APPROACH:
		if _contest_kind == ContestKind.BUMP_CLEAN or _contest_kind == ContestKind.BUMP_MISS:
			if not _contest_bump_triggered and _contest_timer >= BUMP_CONTEST_TRIGGER_DELAY:
				_contest_bump_triggered = true
				var dir: Vector3
				var dash_timer := Tuning.BUMP_DASH_DURATION
				if _contest_kind == ContestKind.BUMP_CLEAN:
					dir = _contest_b.global_position - _contest_a.global_position
				else:
					# Fixed forward, NOT aimed at B directly — B sits close
					# enough to this line to read as a deliberate near-miss
					# (see ContestKind.BUMP_MISS's own setup below) but far
					# enough to the side that the two collision capsules
					# (CapsuleShape3D radius 0.35 each, so 0.7m clears both)
					# never actually touch — aiming straight at B would just
					# collide with their capsule and stall the dash, which
					# reads as running into them, not past them. B never
					# carries the ball either way, so there's no valid
					# _try_bump_contact() target regardless of how close the
					# geometry runs — a genuine whiff, not a swing at nothing.
					dir = Vector3(0.0, 0.0, 1.0)
					dash_timer *= BUMP_MISS_CONTEST_DASH_SCALE
				dir.y = 0.0
				_contest_a._bump_dash_direction = dir.normalized() if dir.length_squared() > 0.0001 \
					else Vector3.FORWARD
				_contest_a._bump_dash_timer = dash_timer
				_contest_a._bump_dash_active = true
				_contest_a._bump_cooldown = Tuning.BUMP_COOLDOWN

		# TACKLE_GRAB/TACKLE_TAKEDOWN are safe to treat as "resolved" —
		# _try_tackle()/_try_lunge_tackle() only ever start them in the same
		# call that also resolves the target's own TACKLE_HELD/TACKLED, so
		# each pair is simultaneous. SMOTHER_DIVE is NOT: unlike a tackle,
		# launching the dive only starts a real travel window
		# (Tuning.SMOTHER_DIVE_DURATION) before it either connects or
		# doesn't — treating "started diving" as "resolved" would cut the
		# vignette off mid-flight, before _try_smother_contact() ever gets a
		# chance to actually land it. Bump has no such false-positive: its
		# own dash never sets an Action on the bumper at all while travelling
		# (see _update_bump's own doc comment), only on resolution.
		var resolved := _contest_a._action == Tuning.Action.TACKLED \
			or _contest_a._action == Tuning.Action.TACKLE_GRAB \
			or _contest_a._action == Tuning.Action.TACKLE_TAKEDOWN \
			or _contest_b._action == Tuning.Action.TACKLED \
			or _contest_b._action == Tuning.Action.TACKLE_HELD \
			or _contest_b._action == Tuning.Action.KNOCKED_BACK \
			or _contest_b._action == Tuning.Action.SMOTHERED
		if resolved or _contest_timer > CONTEST_TIMEOUT:
			_contest_stage = ContestStage.HOLD

	_contest_status_label.text = "A: %s   B: %s" % [
		Tuning.Action.keys()[_contest_a._action], Tuning.Action.keys()[_contest_b._action],
	]


# ── Sequences: one carrier / a ball / the umpire, no opponent. Same real
# gameplay code as the contests, just a solo or prop motion that isn't a
# single clip. See SequenceKind / SEQUENCES. ────────────────────────────

## Sets up whichever SequenceKind `kind` is and starts it running. Re-
## callable exactly like _launch_contest — press again, it tears down and
## replays from scratch.
func _launch_sequence(kind: SequenceKind) -> void:
	_ensure_contest_built()
	_reset_contest_state()
	_show_contest()          # wide framing (also hides the umpire); overridden below
	_contest_b.visible = false

	match kind:
		SequenceKind.BOUNCE_RUN:
			# Carrier jogs downfield (+X, camera-right) and, once it has real
			# speed under it, bounces — the ball is driven into the contest
			# floor and re-gathered through the identical _dispose()/_try_
			# gather path a match uses (nothing here fakes the rebound).
			_contest_a.visible = true
			_contest_ball.visible = true
			_contest_a.global_position = Vector3(-3.5, 0.0, 0.0)
			_contest_a.rotation.y = deg_to_rad(-90.0)   # face +X
			_contest_a.give_possession(_contest_ball)
			_brain_a.wish_dir = Vector3(1.0, 0.0, 0.0)
			_brain_a.gait_value = 0.75
		SequenceKind.MARK_RETREAT:
			# Plays the Safe-mark catch clip, then walks the 5m back off the
			# mark (Tuning.MARK_RETREAT_*) — run_back blend while facing stays
			# downfield, exactly as _finish_mark_catch chains the two.
			_contest_a.visible = true
			_contest_ball.visible = true
			_contest_a.global_position = Vector3(2.5, 0.0, 0.0)
			_contest_a.rotation.y = deg_to_rad(-90.0)   # face +X; feet carry -X
			_contest_a.give_possession(_contest_ball)
			_contest_a._animation.play_action(Tuning.Action.MARK_SAFE)
			_contest_a._begin_mark_retreat()
		SequenceKind.UMPIRE_BALLUP:
			# The field umpire's own rig performs the crouch/wind/toss
			# (umpire.gd), a real Ball riding the grip until the release point
			# FullGame._begin_ruck_contest fires at, then lobbed straight up
			# at Tuning.BALL_UP_TOSS_SPEED.
			_ensure_umpire()
			_contest_a.visible = false
			_umpire.visible = true
			_umpire.stand_at(Vector3(0.0, 0.0, 0.4), Vector3(6.0, 0.0, 0.4))   # profile to camera
			_contest_ball.visible = true
			_contest_ball.lock_to(_umpire.ball_hold_point())
			_umpire.throw_up(Tuning.BALL_UP_THROW_DURATION)

	_sequence_kind = kind
	_sequence_stage = ContestStage.APPROACH
	_sequence_timer = 0.0
	_sequence_triggered = false


## Per-frame driver for the running sequence — the SEQUENCES equivalent of
## _step_contest. Each kind's trigger is the one thing a scripted run can't
## get from a brain want: BOUNCE_RUN pulses wants_bounce() once the carrier
## has speed, UMPIRE_BALLUP launches the toss at the throw's release point,
## MARK_RETREAT needs nothing (the retreat drives itself once begun).
func _step_sequence(delta: float) -> void:
	if _sequence_stage == ContestStage.NONE:
		return
	_sequence_timer += delta

	if _sequence_stage == ContestStage.APPROACH:
		match _sequence_kind:
			SequenceKind.BOUNCE_RUN:
				if not _sequence_triggered and _sequence_timer >= SEQUENCE_TRIGGER_DELAY:
					_sequence_triggered = true
					_brain_a.bounce_wanted = true     # one-frame edge, like a real tap
				elif _sequence_triggered:
					_brain_a.bounce_wanted = false
			SequenceKind.UMPIRE_BALLUP:
				var release := Tuning.BALL_UP_THROW_DURATION * Umpire.THROW_RELEASE_END
				if not _sequence_triggered and _sequence_timer >= release:
					_sequence_triggered = true
					var from := _contest_ball.global_position
					_contest_ball.reset_at(from)
					_contest_ball.launch(Vector3.UP, Tuning.BALL_UP_TOSS_SPEED, Vector3.ZERO)
			SequenceKind.MARK_RETREAT:
				pass

		if _sequence_timer > SEQUENCE_TIMEOUT:
			_sequence_stage = ContestStage.HOLD

	_contest_status_label.text = _sequence_status_text()


func _sequence_status_text() -> String:
	match _sequence_kind:
		SequenceKind.BOUNCE_RUN:
			return "BOUNCE ON THE RUN — %s" % \
				("gathered" if _sequence_triggered and _contest_a.is_carrying() else "running")
		SequenceKind.MARK_RETREAT:
			return "MARK RETREAT — %s" % \
				("walking back" if _contest_a.is_retreating_from_mark() else "on the mark")
		SequenceKind.UMPIRE_BALLUP:
			return "UMPIRE BALL-UP — %s" % ("thrown" if _sequence_triggered else "winding up")
	return ""


# ── Free move: one real PlayerController under real input, for roaming
# and testing actions live rather than through a scripted vignette (see
# CONTESTS/SEQUENCES above, which are deliberately the opposite: fixed and
# non-interactive). Solo only — no second body to kick to, no camera
# changes while moving; both are natural follow-ups once this lands. ────

## Built lazily on the first FREE MOVE press, same reasoning as
## _ensure_contest_built — most sessions may never touch it.
func _ensure_free_player_built() -> void:
	if _free_player_built:
		return
	_free_player_built = true
	_ensure_contest_floor_built()
	_ensure_player_construction_warmed()
	_ensure_contest_ball_built()

	_free_player = PlayerScene.instantiate()
	_free_player.team = Tuning.Team.HOME
	(_free_player.get_node("Rig") as HumanoidRig).high_detail = true
	add_child(_free_player)
	_free_player.global_position = STAND_ON
	_free_player.rotation.y = deg_to_rad(180.0)
	_free_player.visible = false

	# NOTE: name-guessed. ContestBrain's own doc comment describes itself
	# as "the scripted-choreography equivalent of HumanBrain reading real
	# Input/InputManager" — swap this for whatever that class is actually
	# called if HumanBrain isn't it.
	_free_brain = HumanBrain.new()
	_free_player.set_brain(_free_brain)

	_free_move_floor = _build_free_move_floor()
	_free_move_floor.visible = false
	add_child(_free_move_floor)


func _show_free_move() -> void:
	_ensure_free_player_built()
	_subject.visible = false
	if _contest_built:
		_contest_a.visible = false
		_contest_b.visible = false
	if _umpire != null:
		_umpire.visible = false
	_contest_stage = ContestStage.NONE
	_sequence_stage = ContestStage.NONE

	_free_player.visible = true
	_contest_ball.visible = true
	if not _free_player.is_carrying():
		_free_player.give_possession(_contest_ball)

	# Same spot as the single-subject framing — camera behaviour for
	# free-move is a separate pass, not part of this toggle.
	_move_camera_to(STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE))

	_studio_floor.visible = false
	_free_move_floor.visible = true
	_preview_columns.visible = false
	_free_move_hints.visible = true


func _on_free_move_toggled(on: bool) -> void:
	if on:
		_free_move_active = true
		_show_free_move()
	else:
		_show_single_subject()


# ── Floor grids: bounded reference grid, not an infinite ground plane —
# a floor with no edge gives the eye nothing to judge scale or footing
# against, which is the opposite of what either a pose-preview or a
# roaming test needs. Drawn as flat lines (PRIMITIVE_LINES, unshaded)
# rather than a textured mesh, matching skeleton_wireframe.gd's own
# reasoning: this is a reference cue, not scenery. Studio and free-move
# share the same draw code (_build_grid_floor) at two different sizes. ──

func _build_studio_floor() -> MeshInstance3D:
	return _build_grid_floor(GRID_HALF_EXTENT, GRID_STEP, true, "StudioFloor")


## Bigger, wall-less counterpart for free-move — same wireframe technique,
## just without the corner uprights (those frame a standing figure for a
## pose preview; roaming under a 2.3m box would just get in the way).
func _build_free_move_floor() -> MeshInstance3D:
	return _build_grid_floor(FREE_MOVE_GRID_HALF_EXTENT, FREE_MOVE_GRID_STEP, false, "FreeMoveFloor")


## Shared grid-drawing code behind both floors above. `with_walls` draws
## the four corner uprights the studio floor uses to frame a standing
## figure; free-move skips them.
func _build_grid_floor(half_extent: float, step: float, with_walls: bool, floor_name: String) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.name = floor_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = GRID_COLOUR
	instance.material_override = material

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(GRID_COLOUR)

	var e := half_extent
	var steps := int(round(e * 2.0 / step))
	for i in steps + 1:
		var t := -e + i * step
		mesh.surface_add_vertex(Vector3(t, 0.0, -e))
		mesh.surface_add_vertex(Vector3(t, 0.0, e))
		mesh.surface_add_vertex(Vector3(-e, 0.0, t))
		mesh.surface_add_vertex(Vector3(e, 0.0, t))

	if with_walls:
		# Four corner uprights, open-topped — the "box" the floor grid sits
		# in, tall enough to frame the 1.85m rig with headroom.
		var box_height := 2.3
		for corner in [Vector2(-e, -e), Vector2(e, -e), Vector2(-e, e), Vector2(e, e)]:
			mesh.surface_add_vertex(Vector3(corner.x, 0.0, corner.y))
			mesh.surface_add_vertex(Vector3(corner.x, box_height, corner.y))

	mesh.surface_end()
	return instance
