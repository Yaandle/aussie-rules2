extends Node

## Persisted user settings — the first genuinely-saved settings this
## project has had (settings_screen.gd was, until this pass, an inert
## "PLACEHOLDER · NOT SAVED" display per its own header comment). Kept
## deliberately small: only the options this session actually wired
## behaviour to, rather than a speculative options schema for rows
## nothing reads yet.
##
## Saved to user://settings.cfg via ConfigFile — the standard, simplest
## persistence path for a handful of scalar options, no reason to reach
## for anything heavier.

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

## THIRD_PERSON/FULL_SIDE, per the design brief's own naming (this
## project's earlier working titles for these were "Broadcast"/"orthodox"
## respectively — kept as the enum's ordinal order so an existing
## user://settings.cfg int value still resolves to the same mode).
enum FullGameCameraMode { THIRD_PERSON, FULL_SIDE }

## THIRD_PERSON is this project's existing third-person chase rig
## (BroadcastCamera's default behaviour). FULL_SIDE is the elevated,
## outside-the-boundary broadcast rig — see BroadcastCamera.Mode.FULL_SIDE.
## kick_to_kick deliberately never reads this: it is single-player
## practice, not a match, and the brief that asked for this option was
## explicit that kick_to_kick "stays the same."
var full_game_camera_mode: FullGameCameraMode = FullGameCameraMode.THIRD_PERSON:
	set(value):
		if full_game_camera_mode == value:
			return
		full_game_camera_mode = value
		camera_mode_changed.emit(value)

## false (default): right-click holds kick stance/aim (like a gamepad's
## LT), left-click fires the kick (like RT). true: swapped, for players
## who expect the opposite convention (e.g. left-click-to-aim shooter
## muscle memory). Applied by rewriting the InputMap's mouse bindings on
## `kick_stance`/`kick_execute` — see _apply_mouse_kick_binding() — rather
## than branching in HumanBrain, so every existing
## `Input.is_action_pressed(&"kick_stance")`-style read elsewhere in the
## project keeps working unchanged regardless of which physical button is
## currently bound to which action.
var mouse_kick_swapped := false:
	set(value):
		if mouse_kick_swapped == value:
			return
		mouse_kick_swapped = value
		_apply_mouse_kick_binding()
		mouse_kick_binding_changed.emit(value)

## Matchday formation (Team Edit expansion, polish-pass brief): which 4 of
## TeamFormation's 18 named AFL slots the HOME side actually lines up in
## for Full Game, replacing the flat even-spread _kickoff_slot() used
## unconditionally before this. Indices into TeamFormation.SLOTS — each
## preset a plausible, curated 4-a-side shape (one from the back/centre/
## forward lines plus a ruck, weighted toward attack, or weighted toward
## defence) rather than a free "any 4 of 18" picker, which stays in scope
## for a future pass. AWAY keeps the old generic spread — only the side
## the human plays as is worth letting them shape.
const FORMATION_PRESETS := [
	{"name": "BALANCED", "slots": [3, 7, 9, 15]},     # CHB, C, CHF, RK
	{"name": "ATTACKING", "slots": [7, 9, 12, 17]},   # C, CHF, FF, ROV
	{"name": "DEFENSIVE", "slots": [0, 3, 7, 15]},    # FB, CHB, C, RK
]

## Full Game pregame setting (Player Control Mode card): whether the human
## drives exactly one on-field player for the whole match (SINGLE_PLAYER —
## full_game.gd wires a "call for the ball" action instead of switch_player
## in this mode) or can freely switch which HOME player they're directly
## driving while AIBrain runs everyone else (FULL_TEAM — this project's
## original, already-built switch_player/ControlMode.next_in_roster
## behaviour). Defaults to FULL_TEAM so an existing save/session's behaviour
## doesn't silently change underneath a returning player. Not to be confused
## with ControlMode.Scheme, which is a different, already-shipped axis
## (direct single-focus control vs. direct-drive-plus-command-orders) that
## this new setting doesn't touch.
enum PlayerControlMode { SINGLE_PLAYER, FULL_TEAM }

var player_control_mode: PlayerControlMode = PlayerControlMode.FULL_TEAM:
	set(value):
		player_control_mode = value as PlayerControlMode


var home_formation_index := 0:
	set(value):
		home_formation_index = clampi(value, 0, FORMATION_PRESETS.size() - 1)


## Full Game pregame setting (YOUR POSITION card): which HOME roster slot
## the human drives for the whole match in Settings.PlayerControlMode.
## SINGLE_PLAYER (and the body they start on in FULL_TEAM). Index into the
## spawned HOME roster, which maps onto TeamFormation.ROSTER_ORDER — 0 is
## the ruck (also the AI centre-bounce ruck contestant, full_game.gd
## _bounce_off), 1 the centre, and so on. Defaults to 1 (centre — an
## on-baller always near the ball) rather than 0 so a fresh single-player
## match doesn't hand the human the ruck, which HumanBrain can't actively
## palm. Clamped to the roster size so a stale save can't over-index.
var home_human_slot := 1:
	set(value):
		home_human_slot = clampi(value, 0, Tuning.TEAM_SIZE - 1)


## The currently-selected preset's slot indices into TeamFormation.SLOTS —
## the one thing FullGame._kickoff_slot() and TeamListScreen's whiteboard
## highlight both actually need, so neither has to know the preset table's
## own shape. Display names live in TeamListScreen's own Row definition
## (same convention settings_screen.gd's rows already use), not here.
func home_formation_slots() -> Array:
	return FORMATION_PRESETS[home_formation_index]["slots"]


## Ball movement preference (Team Edit expansion): where the HOME side
## prefers to move the ball up the field. Consumed by AIBrain._lateral_
## target_z() — a carrying AI's own disposal aim, and an off-ball
## teammate's support run, both lean toward the boundary by the matching
## fraction below rather than each having its own independently-tuned
## number. CORRIDOR keeps play dead through the middle; BOUNDARY commits
## hard to whichever wing a player already happens to be nearer to;
## MUTUAL (default) is a middling blend of both — not "no preference",
## an actual third choice, same as the formation presets above are three
## real shapes rather than "off plus two options".
enum BallMovementPreference { CORRIDOR, MUTUAL, BOUNDARY }

const BALL_MOVEMENT_BIAS := {
	BallMovementPreference.CORRIDOR: 0.05,
	BallMovementPreference.MUTUAL: 0.40,
	BallMovementPreference.BOUNDARY: 0.85,
}

var home_ball_movement: BallMovementPreference = BallMovementPreference.MUTUAL:
	set(value):
		home_ball_movement = value as BallMovementPreference


func home_lateral_bias() -> float:
	return BALL_MOVEMENT_BIAS[home_ball_movement]


## Defensive pressure (Team Edit expansion): how tightly the HOME side
## marks the ball carrier when defending. Consumed by AIBrain._think_
## defend() — scales both the chase gait closing on the carrier and the
## distance a defender commits to an actual tackle attempt from, together,
## rather than as two separately-invented numbers. TIGHT closes and
## commits earlier/from further out; LOOSE holds off longer on both;
## BALANCED (default) is this project's original, un-tuned _think_defend
## behaviour (multiplier 1.0) — not a new baseline, the existing one.
enum DefensivePressure { LOOSE, BALANCED, TIGHT }

const DEFENSIVE_PRESSURE_INTENSITY := {
	DefensivePressure.LOOSE: 0.65,
	DefensivePressure.BALANCED: 1.0,
	DefensivePressure.TIGHT: 1.3,
}

var home_defensive_pressure: DefensivePressure = DefensivePressure.BALANCED:
	set(value):
		home_defensive_pressure = value as DefensivePressure


func home_press_intensity() -> float:
	return DEFENSIVE_PRESSURE_INTENSITY[home_defensive_pressure]


## Master SFX volume, 0..1 — read directly by AudioManager on every
## playback (no signal needed the way full_game_camera_mode's live-apply
## does: AudioManager only ever reads this at the moment a sound actually
## plays, so there's nothing to push a change into ahead of time). Default
## 1.0 (audio on) rather than SettingsScreen.Row's own index-0 default —
## see settings_screen.gd's MASTER VOLUME row, which now seeds its cursor
## from this value instead of always starting at "MUTE".
var master_volume := 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)


## Keyboard remaps (docs/FEATURE_AUDIT.md's control-remapping item, see
## RemapScreen): action name -> physical keycode, holding only entries a
## player has actually changed — an action with no entry here keeps
## whatever project.godot's own [input] section already bound it to.
## InputMap is the live source of truth from the moment this loads, same
## "rewrite the InputMap directly, don't branch in the code that reads
## Input" pattern _apply_mouse_kick_binding() below already established for
## the mouse-kick swap.
var keybind_overrides: Dictionary = {}


signal camera_mode_changed(mode: FullGameCameraMode)
signal mouse_kick_binding_changed(swapped: bool)


func _ready() -> void:
	_load()
	_apply_mouse_kick_binding()
	for action in keybind_overrides.keys():
		_apply_keybind_to_inputmap(StringName(action), int(keybind_overrides[action]))


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return   # no save file yet — defaults above stand
	full_game_camera_mode = config.get_value(SECTION, "full_game_camera_mode",
		full_game_camera_mode) as FullGameCameraMode
	mouse_kick_swapped = config.get_value(SECTION, "mouse_kick_swapped",
		mouse_kick_swapped) as bool
	player_control_mode = config.get_value(SECTION, "player_control_mode",
		player_control_mode) as PlayerControlMode
	home_formation_index = config.get_value(SECTION, "home_formation_index",
		home_formation_index) as int
	home_human_slot = config.get_value(SECTION, "home_human_slot",
		home_human_slot) as int
	home_ball_movement = config.get_value(SECTION, "home_ball_movement",
		home_ball_movement) as BallMovementPreference
	home_defensive_pressure = config.get_value(SECTION, "home_defensive_pressure",
		home_defensive_pressure) as DefensivePressure
	master_volume = config.get_value(SECTION, "master_volume", master_volume) as float
	# Loaded as a plain dict here, not applied to the InputMap yet — _ready()
	# does that once, after this returns, via _apply_keybind_to_inputmap()
	# for every entry (keeping "read the save data" and "mutate the live
	# InputMap" as two separate steps, same split every apply_keybind()
	# caller already goes through).
	keybind_overrides = config.get_value(SECTION, "keybind_overrides", {}) as Dictionary


func save() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "full_game_camera_mode", full_game_camera_mode)
	config.set_value(SECTION, "mouse_kick_swapped", mouse_kick_swapped)
	config.set_value(SECTION, "player_control_mode", player_control_mode)
	config.set_value(SECTION, "home_formation_index", home_formation_index)
	config.set_value(SECTION, "home_human_slot", home_human_slot)
	config.set_value(SECTION, "home_ball_movement", home_ball_movement)
	config.set_value(SECTION, "home_defensive_pressure", home_defensive_pressure)
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "keybind_overrides", keybind_overrides)
	config.save(SAVE_PATH)


## Removes whichever mouse button is currently on each action and puts
## the correct one back — the InputMap (not the project.godot defaults
## baked in at build time) is the live source of truth for what a click
## does from here on. Idempotent: safe to call every time either setting
## changes, or once at startup with nothing changed yet.
func _apply_mouse_kick_binding() -> void:
	var stance_button := MOUSE_BUTTON_LEFT if mouse_kick_swapped else MOUSE_BUTTON_RIGHT
	var execute_button := MOUSE_BUTTON_RIGHT if mouse_kick_swapped else MOUSE_BUTTON_LEFT
	_rebind_mouse_button(&"kick_stance", stance_button)
	_rebind_mouse_button(&"kick_execute", execute_button)


func _rebind_mouse_button(action: StringName, button_index: MouseButton) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton:
			InputMap.action_erase_event(action, event)
	var new_event := InputEventMouseButton.new()
	new_event.button_index = button_index
	InputMap.action_add_event(action, new_event)


# ── Keyboard remaps (RemapScreen) ────────────────────────────────────
# Conflict resolution (deciding which OTHER action loses this key) is
# RemapScreen's job, since it's the one that knows the full remappable
# set to scan — these three are the primitive InputMap mutation +
# persistence-bookkeeping calls it's built on, kept here so every live
# setting in this project persists through the same one place.

func apply_keybind(action: StringName, physical_keycode: int) -> void:
	keybind_overrides[action] = physical_keycode
	_apply_keybind_to_inputmap(action, physical_keycode)


## Removes a keyboard binding entirely (no fallback to whatever
## project.godot originally had — InputMap.action_erase_event() doesn't
## remember that once erased) — used when a rebind elsewhere takes this
## action's key away from it. Gamepad/mouse events on the same action are
## untouched.
func clear_keyboard_binding(action: StringName) -> void:
	keybind_overrides.erase(action)
	_erase_keyboard_event(action)


## KEY_NONE if `action` has no keyboard event bound at all (cleared, or
## never had one). Reads the live InputMap, not just keybind_overrides, so
## this reports correctly for an action's original project.godot default
## too, not only ones a player has actually remapped.
func keyboard_keycode(action: StringName) -> int:
	if not InputMap.has_action(action):
		return KEY_NONE
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return (event as InputEventKey).physical_keycode
	return KEY_NONE


func _apply_keybind_to_inputmap(action: StringName, physical_keycode: int) -> void:
	_erase_keyboard_event(action)
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	InputMap.action_add_event(action, event)


func _erase_keyboard_event(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
