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

## ── Dev menu design (visual only) ───────────────────────────────────
## Left-docked control panel, same hard-shell/card language as
## MLExperimentViewer (ml_experiment_viewer.gd): square corners, opaque
## parchment fill, hard offset shadow, pinned metric cards up top and the
## three preview groups as tabbed pages rather than three parallel columns.
const MENU_POSITION := Vector2(8.0, 8.0)
const MENU_WIDTH := 320.0
const MENU_PADDING := 12.0
const MENU_ROW_GAP := 2
const MENU_SECTION_GAP := 8
const HARD_SHADOW := 4.0


## Camera moves between the single-subject framing and the wider contest one
## are eased over this rather than cut — a hard jump between two quite
## different distances (4m vs 8m) reads as a glitch, not a shot change.
const CAMERA_MOVE_TIME := 0.35

const PlayerScene := preload("res://scenes/player/player.tscn")
const BallScene := preload("res://scenes/ball/ball.tscn")
const MLExperimentViewerScript := preload("res://scripts/dev/ml_experiment_viewer.gd")
const TackleModelScript := preload("res://scripts/dev/tackle_model.gd")

## Tackle model integration: baseline stamina value (not tracked in viewer; use constant).
const CONTEST_STAMINA_BASELINE := 1.0

@onready var _camera: Camera3D = $Camera3D
@onready var _ui: Control = $Overlay/UI

## Seeded RNG for tackle model roll_break() in contest simulation.
var _contest_rng := RandomNumberGenerator.new()

var _subject: Node3D
var _rig: HumanoidRig
var _wireframe: SkeletonWireframe
var _player_animation: PlayerAnimation
var _current_blend := Vector2.ZERO
var _state_label: Label
var _blend_label: Label
var _model_label: Label
var _jump_tween: Tween

var _preview_columns: Control
var _studio_floor: MeshInstance3D
var _camera_tween: Tween
var _root_layout: VBoxContainer
var _experiment_ui

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

## Tackle model prediction result (for debug display in _step_contest).
var _contest_tackle_prediction := ""
var _tackle_model_manual := false
var _tackle_model_rolled := false
var _tackle_model_manual_inputs := {
	"dspeed": 0.7,
	"angle": 0.7,
	"stamina": 0.7,
}
var _tackle_model_dspeed_slider: HSlider
var _tackle_model_angle_slider: HSlider
var _tackle_model_stamina_slider: HSlider
var _tackle_model_dspeed_value: Label
var _tackle_model_angle_value: Label
var _tackle_model_stamina_value: Label
var _tackle_model_z_label: Label
var _tackle_model_p_label: Label
var _tackle_model_panel: VBoxContainer

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


func _build_studio_floor() -> MeshInstance3D:
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
	instance.name = "StudioFloor"
	instance.mesh = mesh
	return instance


func _build_free_move_floor() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var half_steps := int(floor(FREE_MOVE_GRID_HALF_EXTENT / FREE_MOVE_GRID_STEP))
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for step in range(-half_steps, half_steps + 1):
		var x := step * FREE_MOVE_GRID_STEP
		mesh.surface_set_color(GRID_COLOUR)
		mesh.surface_add_vertex(Vector3(x, 0.0, -FREE_MOVE_GRID_HALF_EXTENT))
		mesh.surface_add_vertex(Vector3(x, 0.0, FREE_MOVE_GRID_HALF_EXTENT))
		mesh.surface_add_vertex(Vector3(-FREE_MOVE_GRID_HALF_EXTENT, 0.0, x))
		mesh.surface_add_vertex(Vector3(FREE_MOVE_GRID_HALF_EXTENT, 0.0, x))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "FreeMoveFloor"
	instance.mesh = mesh
	instance.visible = false
	return instance


func _ensure_free_player_built() -> void:
	if _free_player_built:
		return
	_free_player_built = true
	_ensure_player_construction_warmed()

	_free_player = PlayerScene.instantiate()
	_free_player.team = Tuning.Team.HOME
	_free_player.camera = _camera
	var rig := _free_player.get_node("Rig") as HumanoidRig
	if rig != null:
		rig.high_detail = true
	add_child(_free_player)
	_free_player.global_position = STAND_ON
	_free_brain = HumanBrain.new()
	_free_player.set_brain(_free_brain)

	_free_move_floor = _build_free_move_floor()
	add_child(_free_move_floor)
	_free_move_floor.visible = false


func _show_free_move() -> void:
	_subject.visible = false
	if _contest_built:
		_contest_a.visible = false
		_contest_b.visible = false
		_contest_ball.visible = false
	if _umpire != null:
		_umpire.visible = false
	if _free_player_built:
		_free_player.visible = true
	if _free_move_floor != null:
		_free_move_floor.visible = true
	_studio_floor.visible = false
	_preview_columns.visible = false
	_free_move_hints.visible = true
	_free_move_active = true
	_move_camera_to(STAND_ON + Vector3(-CAMERA_SIDESTEP, CAMERA_HEIGHT, CAMERA_DISTANCE))


func _on_free_move_toggled(toggled_on: bool) -> void:
	if toggled_on:
		_ensure_free_player_built()
		_show_free_move()
		return
	_show_single_subject()


func _launch_sequence(kind: SequenceKind) -> void:
	_show_single_subject()
	_sequence_kind = kind
	_sequence_stage = ContestStage.NONE
	_sequence_timer = 0.0
	_sequence_triggered = false
	match kind:
		SequenceKind.BOUNCE_RUN:
			pass
		SequenceKind.MARK_RETREAT:
			pass
		SequenceKind.UMPIRE_BALLUP:
			_ensure_umpire()
			_umpire.visible = true
			_umpire.global_position = Vector3(0.0, 0.0, 2.0)


func _step_sequence(delta: float) -> void:
	if _sequence_stage == ContestStage.NONE:
		return
	_sequence_timer += delta
	if _sequence_timer > SEQUENCE_TIMEOUT:
		_sequence_stage = ContestStage.NONE
		_sequence_triggered = false


func _process(delta: float) -> void:
	if _subject.visible and _player_animation != null:
		_player_animation.drive(_current_blend, delta)
		_state_label.text = String(_player_animation.current_state()).to_upper()
		var b := _player_animation.blend_position()
		_blend_label.text = "%.2f, %.2f" % [b.x, b.y]
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

	_update_model_label()


## Reads HumanoidRig.is_imported() so the MODEL metric card always reflects
## whichever path _rig._build() actually took, including after REBUILD.
func _update_model_label() -> void:
	if _model_label == null or _rig == null:
		return
	_model_label.text = "IMPORTED" if _rig.is_imported() else "PROCEDURAL"


# ── UI ───────────────────────────────────────────────────────────────
# Same hard-shell card language as MLExperimentViewer (ml_experiment_viewer.
# gd): square corners, opaque parchment fill, hard offset shadow, pinned
# metric cards, tabbed pages. See that file's own STYLE HELPERS section —
# _box/_button/_metric_card/_section_heading/_muted_caption below are the
# same shapes, kept local since the two build off separate roots (Node3D
# vs RefCounted) with no shared base to hang them on.

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override(&"separation", MENU_SECTION_GAP)

	var panel := PanelContainer.new()
	panel.position = MENU_POSITION
	panel.custom_minimum_size.x = MENU_WIDTH
	var panel_box := _box(Color(RetroWindow.PANEL), 2, HARD_SHADOW, MENU_PADDING)
	panel.add_theme_stylebox_override(&"panel", panel_box)
	panel.add_child(root)
	_ui.add_child(panel)
	_root_layout = root
	# When the experiment view hides the layout, drop the empty frame too.
	root.visibility_changed.connect(func() -> void:
		panel.add_theme_stylebox_override(&"panel",
			panel_box if root.visible else StyleBoxEmpty.new()))

	root.add_child(UIStyle.label("ANIMATION VIEWER", UIStyle.SIZE_TITLE,
		UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_HEAVY, UIStyle.TRACK_TITLE))

	# Pinned live metrics — same sunken metric-card pair as the ML
	# Experiments page's P(BREAK)/SUCCESS row.
	var metrics := HBoxContainer.new()
	metrics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	metrics.add_theme_constant_override(&"separation", 8)
	root.add_child(metrics)

	var state_card := _metric_card("STATE")
	_state_label = state_card.value_label
	_state_label.text = "—"
	state_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(state_card.node)

	var blend_card := _metric_card("BLEND")
	_blend_label = blend_card.value_label
	_blend_label.text = "0.00, 0.00"
	blend_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(blend_card.node)

	# 4B's "development menu" half in miniature: proves HumanoidRig's import
	# swap (see humanoid_rig.gd's own header) actually took effect, without
	# having to read code or attach a debugger. REBUILD already re-runs
	# _build_subject() -> HumanoidRig._ready() -> _build(), so it's already
	# a full end-to-end exercise of the swap path once a real res://assets/
	# characters/player.glb exists — this just surfaces which path won.
	var model_card := _metric_card("MODEL")
	_model_label = model_card.value_label
	model_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	metrics.add_child(model_card.node)
	_update_model_label()

	_experiment_ui = MLExperimentViewerScript.new(self)

	root.add_child(_build_control_group())

	# Tabs: LOCOMOTION / ACTIONS / CONTESTS swap page visibility inside a
	# scrolling pane — the same single-active-tab pattern the ML
	# Experiments page uses for its MODEL / SWEEP pages, in place of the
	# three always-visible columns this panel used before.
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_theme_constant_override(&"separation", 6)
	root.add_child(tabs)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 420.0
	root.add_child(scroll)
	_preview_columns = scroll

	var pages := VBoxContainer.new()
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)

	var locomotion_page := _build_locomotion_group()
	var action_page := _build_action_group()
	var contest_page := _build_contest_group()
	action_page.visible = false
	contest_page.visible = false
	pages.add_child(locomotion_page)
	pages.add_child(action_page)
	pages.add_child(contest_page)

	var tab_group := ButtonGroup.new()
	var loc_tab := _button("LOCOMOTION", true)
	loc_tab.button_group = tab_group
	loc_tab.button_pressed = true
	loc_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(loc_tab)

	var action_tab := _button("ACTIONS", true)
	action_tab.button_group = tab_group
	action_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(action_tab)

	var contest_tab := _button("CONTESTS", true)
	contest_tab.button_group = tab_group
	contest_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(contest_tab)

	loc_tab.pressed.connect(func() -> void:
		locomotion_page.visible = true
		action_page.visible = false
		contest_page.visible = false)
	action_tab.pressed.connect(func() -> void:
		locomotion_page.visible = false
		action_page.visible = true
		contest_page.visible = false)
	contest_tab.pressed.connect(func() -> void:
		locomotion_page.visible = false
		action_page.visible = false
		contest_page.visible = true)

	var hints := KeyHintBar.new()
	hints.position = Vector2(24.0, 674.0)
	hints.set_hints([
		{"keys": "Esc / C", "label": "Back to menu"},
	])
	_ui.add_child(hints)

	_free_move_hints = KeyHintBar.new()
	_free_move_hints.position = Vector2(MENU_POSITION.x, 118.0)
	_free_move_hints.visible = false
	_free_move_hints.set_hints([
		{"keys": "WASD", "label": "Move"},
		{"keys": "Kick / Handball / Bounce", "label": "Action inputs"},
	])
	_ui.add_child(_free_move_hints)

	_experiment_ui.build(_ui)


func _build_control_group() -> HBoxContainer:
	var group := HBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", 6)

	var title := _section_heading("CONTROL")
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	group.add_child(title)

	var toggle := _button("FREE MOVE", true)
	toggle.toggled.connect(_on_free_move_toggled)
	group.add_child(toggle)
	_free_move_button = toggle

	var experiment_button := _button("EXPERIMENTS", true)
	experiment_button.toggled.connect(_experiment_ui.on_toggled)
	group.add_child(experiment_button)

	_add_misc_buttons(group)
	return group


## Reset / rebuild live in the control row now (was its own MISC column).
func _add_misc_buttons(group: HBoxContainer) -> void:
	var reset_button := _button("RESET")
	reset_button.tooltip_text = "Reset contest"
	reset_button.pressed.connect(func() -> void:
		_reset_contest_state()
		_show_single_subject())
	group.add_child(reset_button)

	var rebuild_button := _button("REBUILD")
	rebuild_button.tooltip_text = "Rebuild subject"
	rebuild_button.pressed.connect(func() -> void:
		# Rebuild the single-subject rig in-place.
		if _subject != null:
			_subject.queue_free()
			_build_subject())
	group.add_child(rebuild_button)


func _build_locomotion_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", MENU_ROW_GAP)

	var toggle_group := ButtonGroup.new()
	for entry: Array in LOCOMOTION:
		var label: String = entry[0]
		var blend: Vector2 = entry[1]
		var button := _button(label, true)
		button.button_group = toggle_group
		button.button_pressed = blend == Vector2.ZERO
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			_show_single_subject()
			_current_blend = blend)
		group.add_child(button)
	return group


func _build_action_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", MENU_ROW_GAP)

	for entry: Array in ACTIONS:
		var label: String = entry[0]
		var action: Tuning.Action = entry[1]
		var button := _button(label)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			_show_single_subject()
			_player_animation.play_action(action))
		group.add_child(button)
	return group


func _build_contest_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_theme_constant_override(&"separation", MENU_ROW_GAP)

	for entry: Array in CONTESTS:
		var label: String = entry[0]
		var kind: ContestKind = entry[1]
		var button := _button(label)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _launch_contest(kind))
		group.add_child(button)

	group.add_child(_make_spacer(MENU_SECTION_GAP - MENU_ROW_GAP))
	_tackle_model_panel = _build_tackle_model_panel()
	group.add_child(_tackle_model_panel)

	group.add_child(_make_spacer(MENU_SECTION_GAP - MENU_ROW_GAP))
	group.add_child(_section_heading("Sequences"))

	for entry: Array in SEQUENCES:
		var label: String = entry[0]
		var kind: SequenceKind = entry[1]
		var button := _button(label)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: _launch_sequence(kind))
		group.add_child(button)

	_contest_status_label = _muted_caption("")
	# Wrap instead of widening the column when the status line gets long.
	_contest_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	group.add_child(_contest_status_label)
	return group


func _build_tackle_model_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_constant_override(&"separation", 6)
	panel.add_child(_section_heading("Model inputs"))

	var mode_row := HBoxContainer.new()
	mode_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_row.add_theme_constant_override(&"separation", 6)
	var toggle_group := ButtonGroup.new()
	var auto_button := _button("AUTO", true)
	auto_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_button.button_group = toggle_group
	auto_button.button_pressed = true
	auto_button.pressed.connect(func() -> void:
		_tackle_model_manual = false
		_update_tackle_model_panel_state())
	var manual_button := _button("MANUAL", true)
	manual_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_button.button_group = toggle_group
	manual_button.pressed.connect(func() -> void:
		_tackle_model_manual = true
		_update_tackle_model_panel_state())
	mode_row.add_child(auto_button)
	mode_row.add_child(manual_button)
	panel.add_child(mode_row)

	var dspeed_row := _make_tackle_model_input_row("dspeed", -2.0, 4.0, "dspeed")
	panel.add_child(dspeed_row)
	var angle_row := _make_tackle_model_input_row("angle", -2.0, 2.0, "angle")
	panel.add_child(angle_row)
	var stamina_row := _make_tackle_model_input_row("stamina", 0.0, 2.0, "stamina")
	panel.add_child(stamina_row)

	var action_row := HBoxContainer.new()
	action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	action_row.add_theme_constant_override(&"separation", 6)
	var baseline_button := _button("BASELINE")
	baseline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	baseline_button.pressed.connect(func() -> void:
		_tackle_model_manual = true
		manual_button.set_pressed_no_signal(true)
		_tackle_model_manual_inputs = {"dspeed": 0.7, "angle": 0.7, "stamina": 0.7}
		_update_tackle_model_panel_state())
	var randomise_button := _button("RANDOMISE")
	randomise_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	randomise_button.pressed.connect(func() -> void:
		_tackle_model_manual = true
		manual_button.set_pressed_no_signal(true)
		_tackle_model_manual_inputs = {
			"dspeed": randf_range(-2.0, 4.0),
			"angle": randf_range(-2.0, 2.0),
			"stamina": randf_range(0.0, 2.0),
		}
		_update_tackle_model_panel_state())
	action_row.add_child(baseline_button)
	action_row.add_child(randomise_button)
	panel.add_child(action_row)

	var readouts := HBoxContainer.new()
	readouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readouts.add_theme_constant_override(&"separation", 8)
	panel.add_child(readouts)

	var z_card := _metric_card("Z")
	_tackle_model_z_label = z_card.value_label
	z_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readouts.add_child(z_card.node)

	var p_card := _metric_card("P(BREAK)")
	_tackle_model_p_label = p_card.value_label
	p_card.node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readouts.add_child(p_card.node)

	_update_tackle_model_panel_state()
	return panel


## Label / slider / readout row, same 3-column GridContainer shape as
## MLExperimentViewer._slider_row.
func _make_tackle_model_input_row(label_text: String, min_value: float, max_value: float, key: String) -> GridContainer:
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override(&"h_separation", 8)

	var label := UIStyle.label(label_text.to_upper(), UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)
	label.custom_minimum_size.x = 56.0
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = 0.01
	slider.value = _tackle_model_manual_inputs[key]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := UIStyle.label("%.2f" % _tackle_model_manual_inputs[key], UIStyle.SIZE_LABEL, UIStyle.TEXT_PRIMARY)
	value_label.custom_minimum_size.x = 36.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	slider.value_changed.connect(func(value: float) -> void:
		_tackle_model_manual_inputs[key] = value
		_update_tackle_model_panel_state())

	if key == "dspeed":
		_tackle_model_dspeed_slider = slider
		_tackle_model_dspeed_value = value_label
	elif key == "angle":
		_tackle_model_angle_slider = slider
		_tackle_model_angle_value = value_label
	else:
		_tackle_model_stamina_slider = slider
		_tackle_model_stamina_value = value_label

	return row


# ── Menu building blocks ─────────────────────────────────────────────
# Ported from MLExperimentViewer's own STYLE HELPERS section so this panel
# and the Experiments overlay read as the same shell.

func _make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.y = height
	return spacer


## Flat fill, hard border, square corners, optional hard offset shadow.
func _box(fill: Color, border_w: int, shadow: float, margin: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = RetroWindow.BORDER
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(0)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	if shadow > 0.0:
		s.shadow_color = Color(0, 0, 0, 0.55)
		s.shadow_size = 1
		s.shadow_offset = Vector2(shadow, shadow)
	return s


func _button(text: String, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 30.0

	var base := Color(RetroWindow.PANEL)
	b.add_theme_stylebox_override(&"normal", _box(base.lightened(0.08), 2, 3.0, 8.0))
	b.add_theme_stylebox_override(&"hover", _box(base.lightened(0.18), 2, 3.0, 8.0))
	b.add_theme_stylebox_override(&"pressed", _box(Color(UIStyle.ACCENT), 2, 0.0, 8.0))
	b.add_theme_stylebox_override(&"hover_pressed", _box(Color(UIStyle.ACCENT), 2, 0.0, 8.0))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override(&"font_size", UIStyle.SIZE_LABEL)
	b.add_theme_color_override(&"font_color", UIStyle.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_hover_color", UIStyle.TEXT_PRIMARY)
	b.add_theme_color_override(&"font_pressed_color", Color.BLACK)
	b.add_theme_color_override(&"font_hover_pressed_color", Color.BLACK)
	return b


func _metric_card(caption: String) -> Dictionary:
	var box := PanelContainer.new()
	# Sunken look: darker fill, thin border, no shadow.
	box.add_theme_stylebox_override(&"panel", _box(Color(RetroWindow.PANEL).darkened(0.18), 2, 0.0, 8.0))

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	box.add_child(col)

	col.add_child(UIStyle.label(caption, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED))
	var value := UIStyle.label("—", UIStyle.SIZE_TITLE, UIStyle.TEXT_PRIMARY, UIStyle.WEIGHT_BOLD)
	col.add_child(value)

	return {"node": box, "value_label": value}


func _section_heading(text: String) -> Label:
	return UIStyle.label(text.to_upper(), UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED, UIStyle.WEIGHT_BOLD)


func _muted_caption(text: String) -> Label:
	return UIStyle.label(text, UIStyle.SIZE_LABEL, UIStyle.TEXT_MUTED)


func _update_tackle_model_panel_state() -> void:
	if _tackle_model_dspeed_slider == null:
		return

	var inputs := _tackle_model_inputs_for_current_state()
	_tackle_model_dspeed_slider.editable = _tackle_model_manual
	_tackle_model_angle_slider.editable = _tackle_model_manual
	_tackle_model_stamina_slider.editable = _tackle_model_manual
	_tackle_model_dspeed_slider.value = inputs["dspeed"]
	_tackle_model_angle_slider.value = inputs["angle"]
	_tackle_model_stamina_slider.value = inputs["stamina"]
	_tackle_model_dspeed_value.text = "%.2f" % inputs["dspeed"]
	_tackle_model_angle_value.text = "%.2f" % inputs["angle"]
	_tackle_model_stamina_value.text = "%.2f" % inputs["stamina"]
	_tackle_model_z_label.text = "%.2f" % _tackle_model_z_for_inputs(inputs)
	_tackle_model_p_label.text = "%.2f%%" % (_tackle_model_p_for_inputs(inputs) * 100.0)


func _tackle_model_inputs_for_current_state() -> Dictionary:
	if _tackle_model_manual:
		return _tackle_model_manual_inputs.duplicate()
	if _contest_a == null or _contest_b == null:
		return {"dspeed": 0.0, "angle": 0.0, "stamina": CONTEST_STAMINA_BASELINE}
	var vel_a := Vector3(_contest_a.velocity.x, 0.0, _contest_a.velocity.z)
	var vel_b := Vector3(_contest_b.velocity.x, 0.0, _contest_b.velocity.z)
	var pos_a := _contest_a.global_position
	var pos_b := _contest_b.global_position
	var approach_dir := pos_b - pos_a
	if approach_dir.length_squared() < 0.0001:
		return {"dspeed": 0.0, "angle": 0.0, "stamina": CONTEST_STAMINA_BASELINE}
	approach_dir = approach_dir.normalized()
	var dspeed := -(vel_b - vel_a).dot(approach_dir)
	var a_forward := Vector3(sin(_contest_a.rotation.y), 0.0, cos(_contest_a.rotation.y))
	var angle_cos := a_forward.dot(approach_dir)
	var raw_angle := acos(clampf(angle_cos, -1.0, 1.0))
	var angle := 2.0 * (1.0 - raw_angle / PI)
	return {"dspeed": dspeed, "angle": angle, "stamina": CONTEST_STAMINA_BASELINE}


## `model` is whatever the ML Experiments page's MODEL tab currently has
## dialled in (get_active_model()) — including a Stage 2 GA result after
## APPLY TO MODEL — not a fresh default-weight instance. Previously these
## three functions each built their own `TackleModelScript.new()` and
## silently ignored that page entirely, so nothing dialled in there, by
## hand or by the GA, ever reached this simulation.
func _tackle_model_z_for_inputs(inputs: Dictionary) -> float:
	# Explicitly typed: _experiment_ui itself has no static type (shared
	# instance var used for many other things in this file), so without
	# this `model` would resolve as Variant and every `:=` below would
	# fail to infer a type at parse time.
	var model: TackleModel = _experiment_ui.get_active_model()
	var nd := model.normalise(inputs["dspeed"], model.NORM_MIN["dspeed"], model.NORM_MAX["dspeed"])
	var na := model.normalise(inputs["angle"], model.NORM_MIN["angle"], model.NORM_MAX["angle"])
	var ns := model.normalise(inputs["stamina"], model.NORM_MIN["stamina"], model.NORM_MAX["stamina"])
	return model.w_speed * nd + model.w_angle * na + model.w_stamina * ns + model.bias


func _tackle_model_p_for_inputs(inputs: Dictionary) -> float:
	var model: TackleModel = _experiment_ui.get_active_model()
	return model.p_break(inputs["dspeed"], inputs["angle"], inputs["stamina"])


func _compute_tackle_model_prediction() -> void:
	var inputs := _tackle_model_inputs_for_current_state()
	var model: TackleModel = _experiment_ui.get_active_model()
	var broke := model.roll_break(_contest_rng, inputs["dspeed"], inputs["angle"], inputs["stamina"])
	var p_break := model.p_break(inputs["dspeed"], inputs["angle"], inputs["stamina"])
	var z := _tackle_model_z_for_inputs(inputs)
	var result_text := "BREAK" if broke else "TACKLE"
	var log_line := "raw: dspeed=%.2f angle=%.2f stamina=%.2f | z=%.2f | P(break)=%.2f%% | roll=%s → %s" % [
		inputs["dspeed"], inputs["angle"], inputs["stamina"], z, p_break * 100.0, broke, result_text
	]
	print("CONTEST TACKLE MODEL: " + log_line)
	_contest_tackle_prediction = "%s %.1f%%" % [result_text, p_break * 100.0]
	_update_tackle_model_panel_state()


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
func move_camera_to(target: Vector3) -> void:
	_move_camera_to(target)

func show_single_subject() -> void:
	_show_single_subject()

func set_studio_floor_visible(visible_: bool) -> void:
	_studio_floor.visible = visible_

func set_root_layout_visible(visible_: bool) -> void:
	_root_layout.visible = visible_

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

	if _contest_a == null or _contest_b == null:
		return

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

	# Initialize tackle model RNG with a fixed seed for reproducibility.
	_contest_rng.seed = 42

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
	_tackle_model_rolled = false


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

		if _contest_kind == ContestKind.TACKLE_SLIDE or _contest_kind == ContestKind.TACKLE_LUNGE:
			if not _tackle_model_rolled:
				_compute_tackle_model_prediction()
				_tackle_model_rolled = true
		else:
			_contest_tackle_prediction = ""

	_contest_status_label.text = "A: %s   B: %s   %s" % [
		Tuning.Action.keys()[_contest_a._action], Tuning.Action.keys()[_contest_b._action],
		_contest_tackle_prediction,
	]
