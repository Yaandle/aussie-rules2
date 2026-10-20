class_name HumanoidRig
extends Node3D

## A blocked-out 1.85m humanoid, built in code around a real Skeleton3D.
##
## Replaces PlaceholderRig. The old version hung primitive meshes off a
## tree of bare Node3D "joints" and animated those nodes directly — which
## worked for BlendSpace2D locomotion, but a Node3D hierarchy is not a
## retarget target. This version builds an actual Skeleton3D whose bone
## names and parent chain match Godot 4's built-in SkeletonProfileHumanoid
## (Root, Hips, Spine, Chest, Neck, Head, Left/RightShoulder,
## Left/RightUpperArm, Left/RightLowerArm, Left/RightHand,
## Left/RightUpperLeg, Left/RightLowerLeg, Left/RightFoot,
## Left/RightToes — the required core chain; finger/eye/jaw bones are
## optional in the profile and are skipped here as placeholder-scope) —
## so mocap glTF exports or a Mixamo-style rig, once retargeted through
## Godot's own BoneMap tooling, land on this skeleton with no renaming.
##
## The primitive meshes are unchanged in spirit from PlaceholderRig (boxes/
## capsules/spheres, same silhouette tricks — yoke, side panels, sock
## trim) but now hang off BoneAttachment3D nodes instead of driving their
## own transforms, so a single mesh set follows whatever pose the skeleton
## is in — procedural today, real mocap later — for free.
##
## HumanoidAnimations (formerly PlaceholderAnimations) writes bone tracks
## against this skeleton via the "Skeleton3D:BoneName" track-path
## convention; nothing else in this file drives animation.
##
## ── Import swap (4A) ─────────────────────────────────────────────────
## If selected_model() (character_model_override, else CharacterProfile.
## model_id — see CHARACTER_MODELS below) names a real file, _build() loads
## it instead of building the primitive meshes below, and uses whatever
## Skeleton3D it finds inside as this rig's skeleton() — same call, same
## "Skeleton3D" child name, same bone names, so PlayerAnimation/
## HumanoidAnimations/SkeletonWireframe need no changes either way (see
## docs/ note below for the full contract wiring and scripts/dev/rig_
## export.gd for round-tripping the current procedural rig out to Blender
## in the meantime). THE EXPORT CONTRACT a Blender-built model must
## satisfy to drop in here cleanly:
##
## 1. Bone names/hierarchy must match the BONES table below exactly (22
##    bones: Root -> Hips -> Spine -> Chest -> {Neck -> Head,
##    Left/RightShoulder -> Left/RightUpperArm -> Left/RightLowerArm ->
##    Left/RightHand}, Hips -> Left/RightUpperLeg -> Left/RightLowerLeg ->
##    Left/RightFoot -> Left/RightToes). These already match Godot's
##    SkeletonProfileHumanoid, same reasoning as the header above.
## 2. Rest pose must be identity rotation on every bone — this rig's bones
##    are pure translation at rest (see BONES below), and humanoid_
##    animations.gd's pose math assumes that convention. Blender's own
##    rest pose for a mirrored armature built by hand is usually already
##    this (bones pointing along one local axis with no twist); double-
##    check in Blender's N-panel per bone if an import comes in looking
##    sheared.
## 3. **Bake FK before export.** IK constraints/control bones (forearm,
##    shin, etc.) are a Blender posing aid only — Godot's AnimationPlayer
##    plays back flat bone transform tracks, it has no constraint solver.
##    Before exporting, select the deform bones in Pose Mode, Bake Action
##    with "Visual Keying" on (bakes the IK-solved result into plain FK
##    keys), then delete the IK constraints/control bones so only the
##    clean deform skeleton and its baked actions export. Skipping this is
##    the single most likely reason a first export comes in looking
##    twisted/broken — the control-bone hierarchy exporting alongside (or
##    instead of) the baked deform bones, or raw unbaked IK still "live".
## 4. Export as glTF2 (.glb), with the Skeleton3D + skin + all actions, to
##    res://assets/characters/<name>.glb and add an entry to
##    CHARACTER_MODELS below pointing at it. Godot's own importer picks up
##    the file as a normal PackedScene on the next project scan — no
##    custom import code needed on that side.
##
## NOT YET VERIFIED: axis convention. This rig's "-Y hangs down the limb"
## local convention (docs/HANDOVER.md's own "Rest-pose axis convention for
## retargeting is also unverified" note) has never been checked against a
## real Blender/glTF import land correctly without a 90-degree twist per
## limb — if bone #2 above still looks wrong after a careful rest-pose
## export, this is the next thing to check, via Godot's BoneMap retarget
## UI or a manual per-bone rotation fixup in Blender before export.
##
## kit_torso/kit_shorts/kit_stripes/away_kit (below) only ever recolour the
## procedural primitives — an imported mesh brings its own materials from
## Blender, so those exports become no-ops once a character is imported.
## Umpire needs the stripe override, so it sets allow_imported_character
## = false before add_child() to stay on the procedural path regardless of
## whether a player character has been imported.

const HIP_HEIGHT := 0.99
const THIGH_LENGTH := 0.44
const SHIN_LENGTH := 0.42
const UPPER_ARM_LENGTH := 0.30
const FOREARM_LENGTH := 0.27
const SHOULDER_HEIGHT := 0.40    # above Chest bone origin
const SHOULDER_WIDTH := 0.24
const HIP_WIDTH := 0.10
const NECK_HEIGHT := 0.44        # above Chest bone origin, split across Neck/Head
const SPINE_HEIGHT := 0.06       # Hips -> Spine
const CHEST_HEIGHT := 0.22       # Spine -> Chest

const COLOUR_GUERNSEY := Color("#e9c95e")
const COLOUR_GUERNSEY_AWAY := Color("#c95f55")
const COLOUR_SKIN := Color("#ecc9a0")
const COLOUR_SHORTS := Color("#2a2c33")
const COLOUR_HAIR := Color("#2c241d")
const COLOUR_BOOT := Color("#22241d")
const COLOUR_TRIM := Color("#f0ece0")
const COLOUR_TREAD := Color("#141513")

@export var away_kit := false

## Uniform overrides, for bodies on the ground that aren't players — the
## match officials (see Umpire). Alpha 0 means "unset": a player never
## sets these and gets COLOUR_GUERNSEY/COLOUR_SHORTS exactly as before, so
## this is additive and the on-field kit is untouched. Kept here rather
## than having Umpire reach in and re-material the meshes afterwards,
## because building the body is this file's job.
@export var kit_torso := Color(0.0, 0.0, 0.0, 0.0)
@export var kit_shorts := Color(0.0, 0.0, 0.0, 0.0)

## Same alpha-0-means-unset contract as kit_torso/kit_shorts, for the
## CHARACTER screen's Customise skin/boot colour rows.
@export var kit_skin := Color(0.0, 0.0, 0.0, 0.0)
@export var kit_boot := Color(0.0, 0.0, 0.0, 0.0)

## Vertical stripes across the torso, for the boundary umpire's black and
## white uniform (rulebook §10). 0 = none, which is every player. Each is
## one thin box slightly deeper than the chest itself, so a single mesh
## reads on the front and the back at once rather than needing two.
@export var kit_stripes := 0
@export var kit_stripe_colour := Color("#1b1c20")

## Viewer-only high-fidelity switch (scripts/dev/animation_viewer.gd sets it
## before _ready). A dev screen renders one to three bodies, not 16-a-side,
## so it can afford much rounder primitives and slightly richer materials
## than the on-field budget allows. Only vertex counts and material params
## change — no extra MeshInstance3D/draw calls, the one cost the header says
## must not scale with the roster — so the on-field default stays untouched.
@export var high_detail := false

## Segment multiplier applied to every curved primitive when high_detail is
## on. Smoother silhouettes on capsules/spheres/cylinders; boxes are flat
## either way so they're left alone.
const DETAIL_SCALE := 2.4

## See the "Import swap (4A)" header note above for the full contract.
## Known importable characters, by the id CharacterProfile.model_id (and
## the character screen's MODEL row) use -> glb path. "procedural" is
## deliberately not a key here: it means "build the primitives below" and
## is always valid, even with this table empty. Godot's own importer turns
## a .glb under res:// into a loadable PackedScene with no extra config,
## so adding a new skin is just a new entry here plus the file on disk.
const CHARACTER_MODELS := {
	"fifthbuild": "res://assets/characters/fifthbuild.glb",
	"6thbuild": "res://assets/characters/6thbuild.glb",
}

## Set false by callers whose kit_* colour overrides only work on the
## procedural primitives (Umpire's stripes) — see header note. Every other
## caller (players, menu/character backdrops) wants the real model once
## one exists, so this defaults on.
@export var allow_imported_character := true

## Explicit model choice, set before add_child like kit_torso/away_kit —
## takes priority over CharacterProfile.model_id when non-empty. Lets a
## preview (CharacterBackdrop) show a draft selection the player hasn't
## committed yet without touching the global profile. Leave empty to just
## follow CharacterProfile, which is what every in-match spawn wants.
@export var character_model_override := ""

## name, parent, rest offset from parent bone (bone-local, i.e. before the
## parent's own rotation is applied — matches Skeleton3D.set_bone_rest's
## own convention of a Transform3D relative to the parent bone). Order
## matters: parents must be added before children.
const BONES := [
	["Root", "", Vector3(0.0, 0.0, 0.0)],
	["Hips", "Root", Vector3(0.0, HIP_HEIGHT, 0.0)],
	["Spine", "Hips", Vector3(0.0, SPINE_HEIGHT, 0.0)],
	["Chest", "Spine", Vector3(0.0, CHEST_HEIGHT, 0.0)],
	["Neck", "Chest", Vector3(0.0, NECK_HEIGHT - CHEST_HEIGHT, 0.0)],
	["Head", "Neck", Vector3(0.0, 0.20, 0.0)],

	["LeftShoulder", "Chest", Vector3(0.03, SHOULDER_HEIGHT - CHEST_HEIGHT, 0.0)],
	["LeftUpperArm", "LeftShoulder", Vector3(SHOULDER_WIDTH - 0.03, 0.0, 0.0)],
	["LeftLowerArm", "LeftUpperArm", Vector3(0.0, -UPPER_ARM_LENGTH, 0.0)],
	["LeftHand", "LeftLowerArm", Vector3(0.0, -FOREARM_LENGTH, 0.0)],

	["RightShoulder", "Chest", Vector3(-0.03, SHOULDER_HEIGHT - CHEST_HEIGHT, 0.0)],
	["RightUpperArm", "RightShoulder", Vector3(-(SHOULDER_WIDTH - 0.03), 0.0, 0.0)],
	["RightLowerArm", "RightUpperArm", Vector3(0.0, -UPPER_ARM_LENGTH, 0.0)],
	["RightHand", "RightLowerArm", Vector3(0.0, -FOREARM_LENGTH, 0.0)],

	["LeftUpperLeg", "Hips", Vector3(HIP_WIDTH, -0.05, 0.0)],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(0.0, -THIGH_LENGTH, 0.0)],
	["LeftFoot", "LeftLowerLeg", Vector3(0.0, -SHIN_LENGTH, 0.0)],
	["LeftToes", "LeftFoot", Vector3(0.0, -0.05, 0.12)],

	["RightUpperLeg", "Hips", Vector3(-HIP_WIDTH, -0.05, 0.0)],
	["RightLowerLeg", "RightUpperLeg", Vector3(0.0, -THIGH_LENGTH, 0.0)],
	["RightFoot", "RightLowerLeg", Vector3(0.0, -SHIN_LENGTH, 0.0)],
	["RightToes", "RightFoot", Vector3(0.0, -0.05, 0.12)],
]

var _materials := {}
var _skeleton: Skeleton3D

## clip name -> Animation, pulled from the imported scene's own AnimationPlayer
## (if any) before it's discarded — see _extract_imported_animations(). Empty
## on the procedural path. PlayerAnimation reads this to override matching
## entries in HumanoidAnimations' generated library with real Blender-authored
## clips, falling back to the generated ones for every name not present here.
var _imported_animations := {}


func _ready() -> void:
	_build()


func skeleton() -> Skeleton3D:
	return _skeleton


func imported_animations() -> Dictionary:
	return _imported_animations


## True once an imported Blender character replaced the primitives below —
## dev tooling (animation_viewer.gd) reads this to show which path is live.
var _imported := false

func is_imported() -> bool:
	return _imported


## "procedural" or a CHARACTER_MODELS key — character_model_override if
## set, else whatever CharacterProfile.model_id currently says. The single
## place that decides which model a given rig instance wants, so the
## character screen, CharacterBackdrop and every in-match spawn agree.
func selected_model() -> String:
	if character_model_override != "":
		return character_model_override
	return CharacterProfile.model_id


func _build() -> void:
	if allow_imported_character and _try_build_from_import():
		_imported = true
		return

	var guernsey := COLOUR_GUERNSEY_AWAY if away_kit else COLOUR_GUERNSEY
	if kit_torso.a > 0.0:
		guernsey = kit_torso
	var shorts := kit_shorts if kit_shorts.a > 0.0 else COLOUR_SHORTS
	var skin := kit_skin if kit_skin.a > 0.0 else COLOUR_SKIN
	var boot := kit_boot if kit_boot.a > 0.0 else COLOUR_BOOT

	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton3D"
	add_child(_skeleton)

	for entry: Array in BONES:
		var bone_name: String = entry[0]
		var parent_name: String = entry[1]
		var offset: Vector3 = entry[2]
		var idx := _skeleton.add_bone(bone_name)
		if parent_name != "":
			_skeleton.set_bone_parent(idx, _skeleton.find_bone(parent_name))
		_skeleton.set_bone_rest(idx, Transform3D(Basis.IDENTITY, offset))
		_skeleton.set_bone_pose_position(idx, offset)

	# Offsets below are relative to each bone's own rest position, which
	# for Hips/Chest/Head already lands exactly where the equivalent
	# placeholder-era joint used to sit (see the BONES table comment) — so
	# a mesh that used to be centred on its joint is centred on its bone
	# (Vector3.ZERO), and one that used to hang some distance off its
	# joint only needs that same distance minus however far the bone
	# itself moved from the old joint to get there.
	_box_on("Hips", "Pelvis", Vector3(0.23, 0.18, 0.20), Vector3.ZERO, shorts)
	_box_on("Chest", "Chest_Mesh", Vector3(0.32, 0.44, 0.22), Vector3.ZERO, guernsey)
	# Shares the Chest attachment with everything else on the torso, same
	# as the Yoke/SidePanels/Collar below — no extra BoneAttachment3D.
	# Spread across the chest's own 0.32 width, inset far enough that the
	# outermost stripe doesn't hang off the side.
	for stripe: int in kit_stripes:
		var span := 0.24
		var offset_x := -span * 0.5 + span * (float(stripe) / maxf(kit_stripes - 1, 1))
		_box_on("Chest", "Stripe%d" % stripe, Vector3(0.035, 0.445, 0.225),
			Vector3(offset_x, 0.0, 0.0), kit_stripe_colour, 0.7)
	_box_on("Chest", "Yoke", Vector3(0.42, 0.09, 0.235), Vector3(0.0, 0.165, 0.0), COLOUR_TRIM, 0.55)
	for panel_side: int in [-1, 1]:
		_box_on("Chest", "SidePanel" + ("L" if panel_side < 0 else "R"),
			Vector3(0.045, 0.34, 0.20), Vector3(0.17 * panel_side, -0.07, 0.0), COLOUR_TRIM, 0.55)

	_sphere_on("Head", "Head_Mesh", 0.115, Vector3.ZERO, skin, 16, 10)
	var hair := _sphere_on("Head", "Hair", 0.125, Vector3(0.0, 0.035, -0.012), COLOUR_HAIR, 16, 10)
	hair.scale = Vector3(1.0, 0.85, 1.0)

	# Collar: shares the Chest attachment Chest_Mesh/Yoke/SidePanels already
	# use (see _attach()'s per-bone cache) rather than adding a whole new
	# BoneAttachment3D just for one more small mesh. Sits a touch above the
	# Yoke, at the base of the neck.
	_cylinder_on("Chest", "Collar", 0.075, 0.075, 0.035, Vector3(0.0, 0.20, 0.0), COLOUR_TRIM, 0.55)

	for side: int in [-1, 1]:
		var suffix := "L" if side < 0 else "R"
		_capsule_on("UpperArm" + suffix, "UpperArm" + suffix, 0.055, UPPER_ARM_LENGTH,
			Vector3(0.0, -UPPER_ARM_LENGTH * 0.5, 0.0), skin)
		_capsule_on("LowerArm" + suffix, "Forearm" + suffix, 0.048, FOREARM_LENGTH,
			Vector3(0.0, -FOREARM_LENGTH * 0.5, 0.0), skin)
		# A small capped end at the wrist — cheap (one more low-poly
		# sphere per arm) but the forearm capsule used to just stop dead
		# in empty air past the elbow, which read as an amputee at any
		# distance closer than broadcast.
		_sphere_on("LowerArm" + suffix, "Hand" + suffix, 0.045,
			Vector3(0.0, -FOREARM_LENGTH - 0.02, 0.0), skin)
		# A pair of bunched-finger blocks past the hand sphere, same
		# reasoning as the wrist cap above (an open palm past the wrist
		# with nothing beyond it reads as a mitt at close range) — two
		# blocks rather than five separate fingers to keep this cheap.
		# Shares the Hand sphere's own LowerArm attachment.
		for finger_x in [-0.014, 0.014]:
			_box_on("LowerArm" + suffix, "Fingers" + suffix + ("A" if finger_x < 0 else "B"),
				Vector3(0.024, 0.05, 0.03),
				Vector3(finger_x, -FOREARM_LENGTH - 0.075, 0.006), skin)

		_capsule_on("UpperLeg" + suffix, "Thigh" + suffix, 0.085, THIGH_LENGTH,
			Vector3(0.0, -THIGH_LENGTH * 0.5, 0.0), skin)
		_capsule_on("LowerLeg" + suffix, "Shin" + suffix, 0.062, SHIN_LENGTH,
			Vector3(0.0, -SHIN_LENGTH * 0.5, 0.0), COLOUR_TRIM)
		_box_on("Foot" + suffix, "Boot" + suffix, Vector3(0.10, 0.07, 0.26),
			Vector3(0.0, -0.035, -0.06), boot)
		# Tread: a wider, flush-with-the-sole slab (bottom edge lines up
		# exactly with the Boot box's own -0.07 bottom, not below it —
		# player_animation.gd's ground-clamp IK reads that exact number as
		# BOOT_GROUND_CLEARANCE, so this must not extend past it). Shares
		# the Boot's own Foot attachment.
		_box_on("Foot" + suffix, "Tread" + suffix, Vector3(0.105, 0.02, 0.27),
			Vector3(0.0, -0.06, -0.06), COLOUR_TREAD, 0.9)


# ── Import swap ──────────────────────────────────────────────────────

## Resolves selected_model() through CHARACTER_MODELS and, if it names a
## real file, loads it and hoists its Skeleton3D up to be a direct child
## of this node (same place the procedural build puts its own) so every
## downstream reader — PlayerAnimation's
## `_rig.get_node_or_null(^"Skeleton3D")`, HumanoidAnimations'
## "Skeleton3D:BoneName" track paths, SkeletonWireframe — keeps working
## against a fixed path regardless of which path built it. Returns false
## (procedural fallback stays in charge) if "procedural" is selected, the
## model id is unrecognised, the file doesn't exist, fails to load, or has
## no skeleton inside — never partially builds.
func _try_build_from_import() -> bool:
	var model_path: String = CHARACTER_MODELS.get(selected_model(), "")
	if model_path == "" or not ResourceLoader.exists(model_path):
		return false
	var packed: PackedScene = load(model_path)
	if packed == null:
		push_error("HumanoidRig: failed to load " + model_path)
		return false

	var imported := packed.instantiate()
	var found := _find_skeleton(imported)
	if found == null:
		push_error("HumanoidRig: " + model_path + " has no Skeleton3D")
		imported.queue_free()
		return false

	# Before any reparenting below touches the tree, pull out whatever clips
	# Godot's glTF importer already generated from the .blend's own actions
	# (tools/blender/export_fifthbuild.py bakes these with bone names matching
	# BONES below) — the AnimationPlayer itself is discarded either way, only
	# PlayerAnimation's own _player plays anything.
	_imported_animations = _extract_imported_animations(imported)

	if found == imported:
		# Imported scene's own root IS the Skeleton3D (Blender's Armature
		# object was the single root) — nothing to hoist.
		_clear_owner(imported)
		add_child(imported)
		_skeleton = found
		_skeleton.name = "Skeleton3D"
		_fix_imported_forward_axis([imported])
		return true

	# Move every child of the skeleton's own parent up to be a direct child
	# of this node, not just the skeleton in isolation — a Blender "Parent
	# (With Automatic Weights)" export can place skinned MeshInstance3D
	# nodes as siblings of the Skeleton3D rather than nested under it, and
	# extracting only the skeleton would silently drop those meshes. Any
	# other sibling (a stray light/camera Blender's exporter added) rides
	# along too; harmless clutter, not a correctness problem.
	var holder := found.get_parent()
	var hoisted: Array = []
	for child in holder.get_children():
		holder.remove_child(child)
		_clear_owner(child)  # must happen before add_child — Godot checks owner consistency as part of the call itself, not after
		add_child(child)
		hoisted.append(child)
	_skeleton = found
	_skeleton.name = "Skeleton3D"
	imported.queue_free()
	_fix_imported_forward_axis(hoisted)
	return true


## Blender's glTF export puts a model's forward-facing geometry at +Z (the
## standard glTF convention), but this game's own forward convention is -Z
## — see humanoid_animations.gd's _gait_pose() comment ("a positive rotation
## about X swings its far end toward -Z, which is forward") and the
## procedural rig's own Boot/Tread mesh placement (_build() above), both of
## which put "forward" at -Z. Nothing elsewhere corrects for this, so every
## imported character (fifthbuild, 6thbuild, ...) comes in facing exactly
## backward without this turn.
##
## Applied to each hoisted child's own local rotation, never to this rig's
## own `rotation` — that property is a public contract callers already use
## for their own reasons (character_backdrop.gd sets rig.rotation.y = 180°
## to turn a character toward its preview camera; adding another 180° here
## on top of that would cancel it out for imported models specifically).
## Rotating the Skeleton3D node itself only affects its whole-skeleton world
## orientation, not bone-local pose data, so every bone track/animation and
## every "Skeleton3D:BoneName" lookup elsewhere keeps working unchanged.
func _fix_imported_forward_axis(nodes: Array) -> void:
	for n: Node in nodes:
		if n is Node3D:
			(n as Node3D).rotation.y += PI


## Every node loaded from a PackedScene keeps `owner` pointing at that
## scene's original root (used for editor saving, irrelevant once we're
## just composing a runtime tree) — left set after reparenting here, it's
## a dangling reference to a root we're about to free, which Godot warns
## about loudly on every add_child above. Recurse because owner is set
## per-node, not inherited.
func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


## Flattens every library on the imported scene's AnimationPlayer into one
## name -> Animation dict and detaches the player itself (removed from the
## tree immediately, not just queued, so it can't ride along with whichever
## sibling the caller reparents next) — the Animation resources themselves
## are plain RefCounted data, so they stay valid via this dict's own
## references after the player/scene they came from is freed.
func _extract_imported_animations(imported: Node) -> Dictionary:
	var out := {}
	var player := _find_animation_player(imported)
	if player == null:
		return out
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			var anim := lib.get_animation(anim_name)
			_retarget_tracks_to_skeleton(anim)
			# Blender/glTF export never sets this, so an imported clip comes
			# in as LOOP_NONE and simply freezes on its last frame once
			# played through once — fine for a one-shot action (kick,
			# handball, ...) but every locomotion gait (HumanoidAnimations.
			# GAITS' own key list: idle, jog_fwd, run_fwd, ...) is meant to
			# cycle continuously under the BlendSpace2D for as long as the
			# player keeps moving, same as the procedural clip it replaces
			# (_build_gait always assembles those with loop = true).
			if HumanoidAnimations.GAITS.has(String(anim_name)):
				anim.loop_mode = Animation.LOOP_LINEAR
			out[String(anim_name)] = anim
	var player_parent := player.get_parent()
	if player_parent != null:
		player_parent.remove_child(player)
	player.queue_free()
	return out


## glTF import gives every bone track a path like "Armature/Skeleton3D:Hips" —
## relative to the imported scene's OWN root, one level above the skeleton.
## _try_build_from_import() always hoists the skeleton to be a direct child
## named "Skeleton3D" of this rig, so every track needs to end up reading
## just "Skeleton3D:Hips" (PlayerAnimation's AnimationPlayer.root_node is the
## rig itself) regardless of whatever node path the source scene happened to
## nest it under — only the bone name (the path's subname) is ever real
## here, so that's all this keeps.
func _retarget_tracks_to_skeleton(anim: Animation) -> void:
	for i in anim.get_track_count():
		var bone_name := anim.track_get_path(i).get_concatenated_subnames()
		anim.track_set_path(i, NodePath("Skeleton3D:" + String(bone_name)))


# ── Construction helpers ─────────────────────────────────────────────

## Bones are named without the Left/Right prefix split for arms/legs in
## the mesh helper calls above (e.g. "UpperArm" + suffix) because the
## actual bone names carry the prefix the other way round
## (LeftUpperArm/RightUpperArm) — resolved here once so callers can stay
## terse.
func _bone_name(short: String) -> String:
	if short.ends_with("L"):
		return "Left" + short.substr(0, short.length() - 1)
	if short.ends_with("R"):
		return "Right" + short.substr(0, short.length() - 1)
	return short


## Cached per bone: several parts now deliberately share one attachment
## (Chest_Mesh/Yoke/SidePanels/Collar all sit on "Chest"; Boot/Tread on
## "Foot"+suffix; Hand/Fingers on "LowerArm"+suffix) rather than each
## getting its own BoneAttachment3D — the geometry pass below adds several
## new parts per player, and 16-a-side means that cost is paid 32 times
## over, so co-located parts reusing one attachment is what keeps node
## count from scaling with mesh count.
var _attachments := {}

func _attach(bone_short: String) -> BoneAttachment3D:
	if _attachments.has(bone_short):
		return _attachments[bone_short]
	var bone_name := _bone_name(bone_short)
	var attachment := BoneAttachment3D.new()
	attachment.name = "Attach_" + bone_name
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	_attachments[bone_short] = attachment
	return attachment


func _box_on(bone_short: String, part_name: String, size: Vector3, offset: Vector3,
		colour: Color, roughness := 0.78) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_on(bone_short, part_name, mesh, offset, colour, roughness)


## radial_segments/rings bumped from 10/3 — cheap per the header's own
## "primitive geometry is fine, don't multiply node/draw-call count" brief:
## more triangles on an existing mesh costs nothing extra in draw calls,
## unlike adding more MeshInstance3D nodes would.
func _capsule_on(bone_short: String, part_name: String, radius: float, length: float,
		offset: Vector3, colour: Color, roughness := 0.78) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(length, radius * 2.0 + 0.001)
	mesh.radial_segments = _segments(12)
	mesh.rings = _segments(5)
	return _mesh_on(bone_short, part_name, mesh, offset, colour, roughness)


func _sphere_on(bone_short: String, part_name: String, radius: float, offset: Vector3,
		colour: Color, radial_segments := 14, rings := 8) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = _segments(radial_segments)
	mesh.rings = _segments(rings)
	return _mesh_on(bone_short, part_name, mesh, offset, colour)


func _cylinder_on(bone_short: String, part_name: String, top_radius: float, bottom_radius: float,
		height: float, offset: Vector3, colour: Color, roughness := 0.78) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = _segments(14)
	return _mesh_on(bone_short, part_name, mesh, offset, colour, roughness)


func _mesh_on(bone_short: String, part_name: String, mesh: Mesh, offset: Vector3,
		colour: Color, roughness := 0.78) -> MeshInstance3D:
	var attachment := _attach(bone_short)
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.position = offset
	node.material_override = _material(colour, roughness)
	attachment.add_child(node)
	return node


## Curved-primitive tessellation, scaled up only when high_detail is set —
## rounded to the nearest whole segment and floored at the on-field value so
## the low-detail path is bit-for-bit unchanged.
func _segments(base: int) -> int:
	if not high_detail:
		return base
	return maxi(base, int(round(base * DETAIL_SCALE)))


func _material(colour: Color, roughness := 0.78) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [colour, roughness, high_detail]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	# High detail gives the figure a little more form under the studio key
	# light: a touch less roughness for a soft sheen on skin/cloth, and a
	# faint rim so the silhouette separates from the flat-white backdrop the
	# viewer sits on. On-field bodies keep the plain matte look.
	if high_detail:
		material.roughness = clampf(roughness - 0.14, 0.2, 1.0)
		material.rim_enabled = true
		material.rim = 0.35
		material.rim_tint = 0.2
	_materials[key] = material
	return material
