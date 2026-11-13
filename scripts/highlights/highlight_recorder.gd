class_name HighlightRecorder
extends Node

## Records a Full Game into a rolling replay buffer and picks out the
## moments worth a highlight. The Highlights autoload adds one of these to
## each Full Game scene once it's ready; it's freed with the match.
##
## Strictly an observer. It connects extra listeners to signals the match
## already emits (Field.scored, PlayerController's mark/tackle/bump/
## disposal/hit-out signals) and reads public state (positions,
## current_action(), is_ragdolled()). It never sets anything on a player,
## the ball or the match, so a match plays exactly the same with it there
## or not.
##
## Poses are read inside each Skeleton3D's `skeleton_updated`: since Godot
## 4.3 the skeleton's modifiers (the leg IK, the hands, and the ragdoll's
## PhysicalBoneSimulator3D) apply their poses only for that update and the
## un-modified pose comes back afterwards, so that signal is the one place
## the pose on screen can be read. docs/LESSONS.md's "read a ragdoll's
## position from its bodies, not the skeleton" is the same effect seen from
## a physics frame.
##
## Detection runs on events; HighlightTable holds every threshold and
## weight. A moment waits until its play-out has been recorded, then its
## window is copied out of the ring into a ReplayClip and handed to the
## Highlights autoload.
##
## Every disposal, mark, tackle, bump, score and siren is also logged with
## its time (`_events`), and a moment's clip carries those that fall inside it
## as `events` ({frame, kind, player}), so the video side can cut and add
## sound on exact frames. A goal or behind records the kick that actually
## scored it (`_flight`: the last kick nobody has gathered since), not the
## scoring team's last kick, which was often an earlier one (2026-11-10).

signal moment_detected(moment: Dictionary)

const FIELD_SCENE := "res://scenes/modes/full_game.tscn"

var _game: Node
var _ball: Ball
var _field: Field
var _players: Array[PlayerController] = []
var _bodies: Array[Dictionary] = []
var _meta := {}

## The ring: frames and the recorder time each was taken at.
var _ring: Array[PackedByteArray] = []
var _ring_times := PackedFloat64Array()
var _ring_head := 0
var _ring_count := 0

var _t := 0.0
var _since_frame := 0.0
var _capture_due := false
## Ball height over the last few frames, for a mark's catch height.
var _ball_heights: Array[float] = []

var _pending: Array[Dictionary] = []
## Rolling log of what happened and when: {t, kind, player (index or -1)}.
var _events: Array[Dictionary] = []
var _evaluating: Array[Dictionary] = []
var _next_id := 1

# Match context the detector keeps for itself.
var _active_kick := {}
var _last_kick := {}           ## team -> kick dict
var _set_shot_player: PlayerController = null
var _chain_team: Tuning.Team = Tuning.Team.NONE
var _chain_count := 0
## The last kick anyone took that nobody has gathered since: the kick a score
## is credited to. A handball, bounce or gather puts it out.
var _flight := {}
## The passage of play the chain above is part of (general play).
var _chain_bounces := 0
var _chain_start_t := 0.0
var _chain_start_x := 0.0
var _chain_last_t := 0.0
var _chain_last_x := 0.0
var _chain_last_player: PlayerController = null
var _siren_latched := false
var _team_names := {}


## `game` is the Full Game scene root, already ready (its players spawned).
func setup(game: Node) -> void:
	_game = game
	_ball = game.get_tree().get_first_node_in_group(&"ball") as Ball
	for node in game.find_children("*", "Field", true, false):
		_field = node as Field
		break
	for node in game.find_children("*", "PlayerController", true, false):
		_players.append(node as PlayerController)
	# HOME first, then AWAY, each in spawn order: the order FullGame built
	# them, so "#n" in a caption is that player's roster slot.
	_players.sort_custom(func(a: PlayerController, b: PlayerController) -> bool:
		return int(a.team) < int(b.team))

	if GameState.career_active:
		_team_names = {Tuning.Team.HOME: CareerProfile.team_name, Tuning.Team.AWAY: CareerProfile.current_fixture()}
	else:
		_team_names = {Tuning.Team.HOME: "Home", Tuning.Team.AWAY: "Away"}

	_build_body_table()
	var frames := int(ceil(HighlightTable.BUFFER_SECONDS * HighlightTable.RECORD_FPS))
	_ring.resize(frames)
	_ring_times.resize(frames)
	_connect_events()


func team_name(team: Tuning.Team) -> String:
	return String(_team_names.get(team, "Home" if team == Tuning.Team.HOME else "Away"))


func body_meta() -> Dictionary:
	return _meta


func _build_body_table() -> void:
	var metas: Array = []
	var counts := {Tuning.Team.HOME: 0, Tuning.Team.AWAY: 0}
	for player in _players:
		var rig := player.get_node_or_null(^"Rig") as HumanoidRig
		counts[player.team] += 1
		# The player's own guernsey number where the spawn set one, so the
		# replay's body wears it too; else the order within the team.
		var number: int = rig.guernsey_number if rig.guernsey_number > 0 else counts[player.team]
		var kit: Dictionary = rig._resolved_kit()
		var kit_html := {}
		for slot: String in ["jersey", "shorts", "socks", "boot", "skin"]:
			kit_html[slot] = (kit[slot] as Color).to_html()
		metas.append({
			"kind": "player", "team": int(player.team), "number": number,
			"name": _player_name(player, number),
			"model": rig.selected_model() if rig.is_imported() else "procedural",
			"kit": kit_html, "away_kit": rig.away_kit,
			"scale": rig.global_transform.basis.get_scale().x,
		})
		_add_body(player, rig, metas[-1])
	var officials := _field.get_node_or_null(^"Umpires") if _field != null else null
	if officials != null:
		for i in officials.get_child_count():
			var umpire := officials.get_child(i) as Umpire
			if umpire == null:
				continue
			var rig: HumanoidRig = null
			for child in umpire.get_children():
				if child is HumanoidRig:
					rig = child
			if rig == null:
				continue
			metas.append({"kind": "umpire", "slot": i, "role": int(umpire.role), "scale": 1.0})
			_add_body(umpire, rig, metas[-1])
	_meta = {
		"fps": HighlightTable.RECORD_FPS,
		"bodies": metas,
		"teams": {"home": team_name(Tuning.Team.HOME), "away": team_name(Tuning.Team.AWAY)},
		"field_style": int(Settings.field_style) if "field_style" in Settings else 0,
	}


func _add_body(owner: Node3D, rig: HumanoidRig, meta: Dictionary) -> void:
	var skeleton := rig.skeleton()
	var pos_bones := PackedInt32Array()
	for b in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(b)
		if parent == -1 or skeleton.get_bone_parent(parent) == -1:
			pos_bones.append(b)
	meta["bones"] = skeleton.get_bone_count()
	meta["pos_bones"] = Array(pos_bones)
	var index := _bodies.size()
	_bodies.append({
		"owner": owner, "rig": rig, "skeleton": skeleton, "pos_bones": pos_bones,
		"xform": rig.global_transform,
		"rots": _rest_rotations(skeleton), "pos": _rest_positions(skeleton, pos_bones),
	})
	skeleton.skeleton_updated.connect(_on_skeleton_updated.bind(index))


func _rest_rotations(skeleton: Skeleton3D) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	for b in skeleton.get_bone_count():
		out.append(skeleton.get_bone_pose_rotation(b))
	return out


func _rest_positions(skeleton: Skeleton3D, pos_bones: PackedInt32Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for b in pos_bones:
		out.append(skeleton.get_bone_pose_position(b))
	return out


func _player_name(player: PlayerController, number: int) -> String:
	if player.roster_name != "":
		return player.roster_name
	return "%s #%d" % [team_name(player.team), number]


func _name_of(player: PlayerController) -> String:
	var i := _players.find(player)
	return String(_meta.bodies[i].name) if i >= 0 else "A player"


# ── Recording ───────────────────────────────────────────────────────

func _on_skeleton_updated(index: int) -> void:
	if not _capture_due:
		return
	var body := _bodies[index]
	var skeleton: Skeleton3D = body.skeleton
	var rots: Array[Quaternion] = body.rots
	for b in rots.size():
		rots[b] = skeleton.get_bone_pose_rotation(b)
	var pos: Array[Vector3] = body.pos
	var pos_bones: PackedInt32Array = body.pos_bones
	for k in pos_bones.size():
		pos[k] = skeleton.get_bone_pose_position(pos_bones[k])
	body.xform = (body.rig as Node3D).global_transform


func _process(delta: float) -> void:
	_t += delta
	# The skeletons updated after last frame's _process: commit what they
	# gave, then decide whether this frame is another capture.
	if _capture_due:
		_commit_frame()
		_capture_due = false
	_since_frame += delta
	var step := 1.0 / HighlightTable.RECORD_FPS
	if _since_frame >= step:
		_since_frame = fmod(_since_frame, step)
		_capture_due = true
	_update_evaluations()
	_update_pending()


func _commit_frame() -> void:
	var buf := StreamPeerBuffer.new()
	buf.put_float(MatchState.seconds_remaining)
	buf.put_u8(MatchState.quarter)
	buf.put_u8(MatchState.goals[Tuning.Team.HOME])
	buf.put_u8(MatchState.behinds[Tuning.Team.HOME])
	buf.put_u8(MatchState.goals[Tuning.Team.AWAY])
	buf.put_u8(MatchState.behinds[Tuning.Team.AWAY])
	var ball_xform := _ball.global_transform if is_instance_valid(_ball) else Transform3D.IDENTITY
	ReplayClip.put_vec3(buf, ball_xform.origin)
	ReplayClip.put_quat(buf, ball_xform.basis.get_rotation_quaternion())
	for body in _bodies:
		var xform: Transform3D = body.xform
		ReplayClip.put_vec3(buf, xform.origin)
		ReplayClip.put_quat(buf, xform.basis.get_rotation_quaternion())
		for q: Quaternion in body.rots:
			ReplayClip.put_quat(buf, q)
		for p: Vector3 in body.pos:
			ReplayClip.put_vec3(buf, p)
	_ring[_ring_head] = buf.data_array
	_ring_times[_ring_head] = _t
	_ring_head = (_ring_head + 1) % _ring.size()
	_ring_count = mini(_ring_count + 1, _ring.size())

	_ball_heights.append(ball_xform.origin.y)
	if _ball_heights.size() > 12:
		_ball_heights.pop_front()


## Frames recorded between `from` and `to` (recorder time), oldest first.
## `times`, if given, gets each frame's recorder time.
func _window(from: float, to: float, times: PackedFloat64Array = PackedFloat64Array()) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var size := _ring.size()
	var oldest := (_ring_head - _ring_count + size) % size
	for k in _ring_count:
		var i := (oldest + k) % size
		var t := _ring_times[i]
		if t >= from and t <= to:
			out.append(_ring[i])
			times.append(t)
	return out


## Index of the frame (in a window whose times are `times`) nearest `t`.
static func _nearest_frame(times: PackedFloat64Array, t: float) -> int:
	var best := 0
	var best_d := INF
	for i in times.size():
		var d := absf(times[i] - t)
		if d < best_d:
			best_d = d
			best = i
	return best


func _update_pending() -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var moment := _pending[i]
		if _t >= float(moment._t_event) + float(moment.out):
			_pending.remove_at(i)
			_finish(moment)


## Copies the moment's window out of the ring and hands it on. Called early
## (cut short) when the match ends before a play-out has run.
func _finish(moment: Dictionary) -> void:
	var t_event: float = moment._t_event
	var times := PackedFloat64Array()
	var frames := _window(t_event - float(moment.lead), t_event + float(moment.out), times)
	if frames.is_empty():
		return
	var clip := ReplayClip.new()
	clip.meta = _meta.duplicate(true)
	clip.frames = frames
	# Which frame is the moment itself, for the camera and the scrub bar.
	var event_frame := _nearest_frame(times, t_event)
	clip.meta["event_frame"] = event_frame
	clip.meta["focus"] = moment.focus
	clip.meta["type"] = moment.type
	clip.meta["attack_dir"] = moment.attack_dir
	# What happened, on which clip frame.
	var events: Array = []
	var slack := 0.5 / HighlightTable.RECORD_FPS
	for ev in _events:
		var te: float = ev.t
		if te < times[0] - slack or te > times[times.size() - 1] + slack:
			continue
		var who := int(ev.player)
		events.append({"frame": _nearest_frame(times, te), "kind": ev.kind,
			"player": String(_meta.bodies[who].name) if who >= 0 else ""})
	moment["events"] = events
	clip.meta["events"] = events
	if moment.has("_t_kick"):
		# A scoring kick from before the clip began is pinned to its first
		# frame; the lead-in is stretched to reach it, so that's rare.
		moment["kick_frame"] = _nearest_frame(times, float(moment._t_kick))
		clip.meta["kick_frame"] = moment.kick_frame
		moment.erase("_t_kick")
	moment.clip = clip
	moment.duration_s = clip.duration()
	moment.erase("_t_event")
	moment_detected.emit(moment)


## The match is over (or the scene is going): cut every waiting moment
## with whatever play-out it got.
func flush() -> void:
	for moment in _evaluating:
		_score_evaluation(moment)
	_evaluating.clear()
	_end_chain()
	if _capture_due:
		_commit_frame()
		_capture_due = false
	for moment in _pending:
		moment.out = maxf(0.0, _t - float(moment._t_event))
		_finish(moment)
	_pending.clear()


func _exit_tree() -> void:
	flush()


# ── Events ──────────────────────────────────────────────────────────

func _connect_events() -> void:
	if _field != null:
		_field.scored.connect(_on_scored)
	MatchState.clock_changed.connect(_on_clock)
	for player in _players:
		player.ball_disposed.connect(_on_disposed.bind(player))
		player.ball_gathered.connect(_on_gathered.bind(player))
		player.mark_caught.connect(_on_marked.bind(player))
		player.tackle_committed.connect(_on_tackle.bind(player))
		player.bump_landed.connect(_on_bump)
		player.hit_out_resolved.connect(_on_hit_out)
		player.holding_the_ball_called.connect(_on_holding_the_ball.bind(player))


## Adds to the rolling log; what a moment's clip lists as `events`.
func _log(kind: String, player: PlayerController = null) -> void:
	_events.append({"t": _t, "kind": kind, "player": _players.find(player) if player != null else -1})
	while not _events.is_empty() and _t - float(_events[0].t) > HighlightTable.BUFFER_SECONDS:
		_events.pop_front()


func _on_clock(seconds: float) -> void:
	if seconds <= 0.0 and not _siren_latched:
		_siren_latched = true
		_log("siren")
	elif seconds > 0.0:
		_siren_latched = false


func _on_disposed(action: Tuning.Action, player: PlayerController) -> void:
	var kind := ""
	match action:
		Tuning.Action.KICK:
			kind = "kick"
		Tuning.Action.HANDBALL:
			kind = "handball"
		Tuning.Action.BOUNCE:
			kind = "bounce"
		_:
			return
	_log(kind, player)
	_note_passage(action, player)
	if action != Tuning.Action.KICK:
		_flight = {}
		return
	_end_kick()
	var kick := {
		"player": player, "team": player.team, "t": _t,
		# Where the ball left the boot, not where the player stood.
		"from": _ball.global_position if is_instance_valid(_ball) else player.global_position,
		"set_shot": player == _set_shot_player or player.is_protected(),
		"scored": false,
	}
	_set_shot_player = null
	_active_kick = kick
	_last_kick[player.team] = kick
	_flight = kick


func _on_gathered(_ball_ref: Ball, player: PlayerController) -> void:
	if _active_kick.get("player") != player or _t - float(_active_kick.get("t", 0.0)) > 0.3:
		_end_kick()
		_flight = {}
	if _set_shot_player != null and _set_shot_player != player:
		_set_shot_player = null
	if _chain_team != Tuning.Team.NONE and player.team != _chain_team:
		_end_chain()
	for ev in _evaluating:
		if ev.type == "ruck" and int(ev.team) == int(player.team) \
				and _t - float(ev._t_event) <= HighlightTable.RUCK_ADVANTAGE_WINDOW:
			ev.facts["to_advantage"] = true


# ── General play ────────────────────────────────────────────────────

## Notes a disposal in the passage this team is on, starting a new one when
## the ball changes sides or has been dead too long.
func _note_passage(action: Tuning.Action, player: PlayerController) -> void:
	if player.team != _chain_team or _t - _chain_last_t > HighlightTable.GENERAL_MAX_GAP:
		_end_chain()
		_chain_team = player.team
		_chain_start_t = _t
		_chain_start_x = player.global_position.x
	if action == Tuning.Action.BOUNCE:
		_chain_bounces += 1
	else:
		_chain_count += 1
	_chain_last_t = _t
	_chain_last_x = player.global_position.x
	_chain_last_player = player


## Closes the passage: if it was long enough it becomes a general-play
## moment (never for one that ended in a score, which has its own moment:
## _on_scored resets the chain without calling this).
func _end_chain() -> void:
	if _chain_team == Tuning.Team.NONE:
		return
	var team := _chain_team
	var disposals := _chain_count
	var bounces := _chain_bounces
	var last := _chain_last_player
	var t_start := _chain_start_t
	var t_last := _chain_last_t
	var direction := 1.0 if team == Tuning.Team.HOME else -1.0
	var metres := maxf(0.0, direction * (_chain_last_x - _chain_start_x))
	_reset_chain()
	if last == null or (disposals < HighlightTable.GENERAL_MIN_DISPOSALS and bounces < HighlightTable.GENERAL_MIN_BOUNCES):
		return
	var score := HighlightTable.GENERAL_PER_BOUNCE * bounces + HighlightTable.GENERAL_PER_METRE * metres
	if disposals >= HighlightTable.GENERAL_MIN_DISPOSALS:
		score += HighlightTable.GENERAL_PER_DISPOSAL * (disposals - HighlightTable.GENERAL_MIN_DISPOSALS + 1)
	score = minf(score, HighlightTable.GENERAL_CAP)
	var moment := _new_moment("general", t_last, score, [last], ["carrier"], {
		"player": _name_of(last), "team": team_name(team),
		"disposals": disposals, "bounces": bounces, "metres": metres,
	})
	if moment.is_empty():
		return
	moment.lead = clampf(t_last - t_start + HighlightTable.GENERAL_RUNUP, float(moment.lead),
		HighlightTable.GENERAL_MAX_LEAD)
	moment.focus = [_players.find(last)]
	moment.attack_dir = direction
	_queue(moment)


func _reset_chain() -> void:
	_chain_team = Tuning.Team.NONE
	_chain_count = 0
	_chain_bounces = 0
	_chain_last_player = null


## The kick in the air has come down (gathered, landed or scored): if it
## went far enough and didn't score, it's a long-kick moment.
func _end_kick() -> void:
	if _active_kick.is_empty() or not is_instance_valid(_ball):
		_active_kick = {}
		return
	var kick := _active_kick
	_active_kick = {}
	if kick.scored:
		return
	var from: Vector3 = kick.from
	var to := _ball.global_position
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	if dist < HighlightTable.LONG_KICK_FROM:
		return
	var player: PlayerController = kick.player
	var score := HighlightTable.LONG_KICK_PER_METRE * (dist - HighlightTable.LONG_KICK_FROM)
	var moment := _new_moment("long_kick", float(kick.t), score, [player], ["kicker"],
		{"player": _name_of(player), "distance": dist})
	if moment.is_empty():
		return
	moment.out = maxf(float(moment.out), _t - float(kick.t) + 1.0)
	_queue(moment)


func _on_scored(team: Tuning.Team, is_goal: bool) -> void:
	if not is_instance_valid(_ball):
		return
	# The kick that scored: the last one nobody gathered, whoever took it.
	# (The scoring team's last kick was often an earlier one: the ball had
	# been gathered, handballed, carried or turned over since.)
	var kick: Dictionary = _flight
	_flight = {}
	var kicker: PlayerController = kick.get("player") if not kick.is_empty() else null
	if not kick.is_empty():
		kick.scored = true
	_active_kick = {}
	var direction := 1 if team == Tuning.Team.HOME else -1
	# Metres the ball travelled over the ground from the boot to the line.
	var dist := 0.0
	if kicker != null:
		var from: Vector3 = kick.from
		var to := _ball.global_position
		dist = Vector2(to.x - from.x, to.z - from.z).length()
	# A defender's kick through his own goal counts for the other side.
	var own_goal := kicker != null and kicker.team != team
	# FullGame's _on_scored ran first (it connected in _ready), so the
	# score already counts this one.
	var other := Tuning.Team.AWAY if team == Tuning.Team.HOME else Tuning.Team.HOME
	var value := MatchState.GOAL_POINTS if is_goal else MatchState.BEHIND_POINTS
	var own_after := MatchState.points(team)
	var other_pts := MatchState.points(other)
	var own_before := own_after - value
	var facts := {
		"player": _name_of(kicker) if kicker != null else ("The ball" if is_goal else "A rushed behind"),
		"distance": dist,
		"on_the_run": kicker != null and not own_goal and not bool(kick.get("set_shot", false)),
		"after_siren": MatchState.seconds_remaining <= 0.0,
		"go_ahead": own_before < other_pts and own_after >= other_pts,
		"chain": _chain_count if _chain_team == team else 0,
		"margin_after": absi(own_after - other_pts),
	}
	if own_goal:
		facts["own_goal"] = true
	if kicker == null:
		facts["no_kick"] = true
	var type := "goal" if is_goal else "behind"
	var score := 0.0
	if is_goal:
		if not own_goal:
			score += HighlightTable.GOAL_PER_METRE * maxf(0.0, dist - HighlightTable.GOAL_DISTANCE_FREE)
		if facts.on_the_run:
			score += HighlightTable.GOAL_ON_THE_RUN
		if facts.after_siren:
			score += HighlightTable.GOAL_AFTER_SIREN
		if facts.go_ahead:
			score += HighlightTable.GOAL_GO_AHEAD
		if int(facts.margin_after) <= HighlightTable.GOAL_CLOSE_MARGIN:
			score += HighlightTable.GOAL_CLOSE_BONUS
		score += minf(HighlightTable.CHAIN_CAP,
			HighlightTable.CHAIN_PER_DISPOSAL * maxi(0, int(facts.chain) - HighlightTable.CHAIN_FREE))
	var players: Array = [kicker] if kicker != null else []
	var moment := _new_moment(type, _t, score, players, ["kicker"], facts)
	# The passage that ended in the score has its goal clip already.
	_reset_chain()
	_log(type, kicker)
	if moment.is_empty():
		return
	var points_before := {team: own_before, other: other_pts}
	var goals_before := {team: MatchState.goals[team] - (1 if is_goal else 0), other: MatchState.goals[other]}
	var behinds_before := {team: MatchState.behinds[team] - (0 if is_goal else 1), other: MatchState.behinds[other]}
	moment.score_before = _scoreline(goals_before, behinds_before, points_before)
	if kicker != null:
		moment.lead = clampf(_t - float(kick.t) + HighlightTable.GOAL_KICK_RUNUP,
			float(moment.lead), HighlightTable.GOAL_MAX_LEAD)
		moment["_t_kick"] = float(kick.t)
		moment["kicker"] = _name_of(kicker)
		moment["kick_distance"] = snappedf(dist, 0.1)
	else:
		moment["kicker"] = null
		moment["kick_distance"] = null
		moment["kick_frame"] = null
	moment.focus = [_players.find(kicker)] if kicker != null else []
	moment.attack_dir = float(direction)
	_queue(moment)


func _on_marked(tier: Tuning.Action, legal_mark: bool, player: PlayerController) -> void:
	if not legal_mark:
		return
	_log("mark", player)
	_set_shot_player = player
	_end_kick()
	_flight = {}
	var opponent := _nearest_opponent(player)
	var contested := opponent != null \
		and opponent.global_position.distance_to(player.global_position) <= HighlightTable.MARK_CONTEST_RADIUS
	var catch_height := 0.0
	for h in _ball_heights:
		catch_height = maxf(catch_height, h)
	var high := catch_height > HighlightTable.MARK_HIGH_FROM
	var direction := 1.0 if player.team == Tuning.Team.HOME else -1.0
	var inside_50 := _field != null and Vector2(_field.goal_line_x(int(direction)) - player.global_position.x,
		player.global_position.z).length() < Tuning.SCORING_ARC_RADIUS
	var score := 0.0
	if contested:
		score += HighlightTable.MARK_CONTESTED
	if tier == Tuning.Action.MARK_AGGRESSIVE:
		score += HighlightTable.MARK_AGGRESSIVE_TIER
	elif tier == Tuning.Action.MARK_RUNNING:
		score += HighlightTable.MARK_RUNNING_TIER
	if high:
		score += HighlightTable.MARK_HIGH_PER_METRE * (catch_height - HighlightTable.MARK_HIGH_FROM)
	if inside_50:
		score += HighlightTable.MARK_INSIDE_50
	var players: Array = [player]
	var roles: Array = ["marker"]
	if contested:
		players.append(opponent)
		roles.append("opponent")
	var moment := _new_moment("mark", _t, score, players, roles, {
		"player": _name_of(player), "opponent": _name_of(opponent) if opponent != null else "",
		"contested": contested, "high": high, "catch_height": catch_height, "inside_50": inside_50,
		"tier": ["safe", "running", "aggressive"][clampi(tier - Tuning.Action.MARK_SAFE, 0, 2)],
	})
	if not moment.is_empty():
		_queue(moment)


func _on_tackle(is_slide: bool, tackler: PlayerController) -> void:
	_log("tackle", tackler)
	var tackled := _nearest_opponent(tackler)
	_evaluating.append({
		"type": "tackle", "_t_event": _t, "tackler": tackler, "tackled": tackled,
		"speed": tackler.velocity.length(), "is_slide": is_slide,
		"facts": {"kind": "slide" if is_slide else "lunge"},
	})


func _on_holding_the_ball(_tackler: PlayerController, tackled: PlayerController) -> void:
	for ev in _evaluating:
		if ev.type == "tackle" and ev.tackled == tackled:
			ev.facts["holding_the_ball"] = true


func _on_bump(bumper: PlayerController, carrier: PlayerController, clean: bool) -> void:
	_log("bump", bumper)
	_evaluating.append({
		"type": "bump", "_t_event": _t, "tackler": bumper, "tackled": carrier,
		"speed": bumper.velocity.length(), "facts": {"clean": clean},
	})


func _on_hit_out(player: PlayerController, connected: bool) -> void:
	if not connected:
		return
	_evaluating.append({
		"type": "ruck", "_t_event": _t, "tackler": player, "tackled": null, "team": int(player.team),
		"facts": {},
	})


## Outcomes that show up just after the event (a sling, a ragdoll, a free
## kick, a gather off a hit-out) are watched for a short window, then the
## moment is scored.
func _update_evaluations() -> void:
	if _chain_team != Tuning.Team.NONE and _t - _chain_last_t > HighlightTable.GENERAL_MAX_GAP:
		_end_chain()
	for i in range(_evaluating.size() - 1, -1, -1):
		var ev := _evaluating[i]
		var tackled: PlayerController = ev.tackled
		if is_instance_valid(tackled):
			match tackled.current_action():
				Tuning.Action.TACKLE_SLING:
					ev.facts["kind"] = "sling"
				Tuning.Action.TACKLE_TAKEDOWN:
					if ev.facts.get("kind") != "sling":
						ev.facts["kind"] = "takedown"
			if tackled.is_ragdolled():
				ev.facts["ragdoll"] = true
		var window := HighlightTable.RUCK_ADVANTAGE_WINDOW if ev.type == "ruck" \
			else HighlightTable.TACKLE_OUTCOME_WINDOW
		if _t - float(ev._t_event) >= window:
			_evaluating.remove_at(i)
			_score_evaluation(ev)


func _score_evaluation(ev: Dictionary) -> void:
	var actor: PlayerController = ev.tackler
	var target: PlayerController = ev.tackled
	var facts: Dictionary = ev.facts
	facts["player"] = _name_of(actor)
	if target != null:
		facts["opponent"] = _name_of(target)
	var score := 0.0
	var roles: Array = []
	match String(ev.type):
		"tackle":
			match String(facts.get("kind", "")):
				"sling":
					score += HighlightTable.TACKLE_SLING
				"takedown":
					score += HighlightTable.TACKLE_TAKEDOWN
			if facts.get("ragdoll", false):
				score += HighlightTable.TACKLE_RAGDOLL
			if facts.get("holding_the_ball", false):
				score += HighlightTable.TACKLE_HOLDING_THE_BALL
			score += HighlightTable.TACKLE_PER_MS * maxf(0.0, float(ev.speed) - HighlightTable.TACKLE_SPEED_FREE)
			facts["speed"] = ev.speed
			roles = ["tackler", "tackled"]
		"bump":
			if facts.get("clean", false):
				score += HighlightTable.BUMP_CLEAN
			if facts.get("ragdoll", false):
				score += HighlightTable.BUMP_RAGDOLL
			roles = ["bumper", "bumped"]
		"ruck":
			if facts.get("to_advantage", false):
				score += HighlightTable.RUCK_TO_ADVANTAGE
			roles = ["ruckman"]
	var players: Array = [actor]
	if target != null:
		players.append(target)
	var moment := _new_moment(String(ev.type), float(ev._t_event), score, players, roles, facts)
	if not moment.is_empty():
		_queue(moment)


# ── Moments ─────────────────────────────────────────────────────────

## A new moment dictionary, or {} if its type is off or it scores under
## HighlightTable.MIN_SCORE. `score` is the bonuses; the base is added here.
func _new_moment(type: String, t_event: float, score: float, players: Array, roles: Array,
		facts: Dictionary) -> Dictionary:
	var spec: Dictionary = HighlightTable.TYPES.get(type, {})
	if spec.is_empty() or not spec.enabled:
		return {}
	var human := ControlMode.controlled_player(Tuning.Team.HOME)
	var involves_human := human != null and players.has(human)
	var total := float(spec.base) + score + (HighlightTable.HUMAN_BONUS if involves_human else 0.0)
	if total < HighlightTable.MIN_SCORE:
		return {}
	var player_rows: Array = []
	var focus: Array = []
	for i in players.size():
		var p: PlayerController = players[i]
		if p == null:
			continue
		player_rows.append({"name": _name_of(p), "team": team_name(p.team),
			"side": "home" if p.team == Tuning.Team.HOME else "away",
			"role": roles[i] if i < roles.size() else "", "human": p == human})
		focus.append(_players.find(p))
	var now := _scoreline(MatchState.goals, MatchState.behinds,
		{Tuning.Team.HOME: MatchState.points(Tuning.Team.HOME), Tuning.Team.AWAY: MatchState.points(Tuning.Team.AWAY)})
	var elapsed := Tuning.QUARTER_LENGTH - clampf(MatchState.seconds_remaining, 0.0, Tuning.QUARTER_LENGTH)
	var moment := {
		"id": _next_id, "type": type, "label": String(spec.label),
		"_t_event": t_event, "lead": float(spec.lead), "out": float(spec.out),
		"highlight_score": snappedf(total, 0.1), "human": involves_human,
		"quarter": MatchState.quarter, "quarter_elapsed_s": snappedf(elapsed, 0.1),
		"match_time_s": snappedf((MatchState.quarter - 1) * Tuning.QUARTER_LENGTH + elapsed, 0.1),
		"players": player_rows, "focus": focus, "facts": facts,
		"attack_dir": 1.0 if players.is_empty() or players[0] == null 			or (players[0] as PlayerController).team == Tuning.Team.HOME else -1.0,
		"score_before": now, "score_after": now, "keep": false,
	}
	_next_id += 1
	return moment


func _queue(moment: Dictionary) -> void:
	for key: String in moment.facts:
		var v: Variant = moment.facts[key]
		if v is float:
			moment.facts[key] = snappedf(v, 0.1)
	moment.caption = HighlightTable.caption(moment)
	_pending.append(moment)


func _scoreline(goals: Dictionary, behinds: Dictionary, points: Dictionary) -> Dictionary:
	var out := {}
	for team: Tuning.Team in [Tuning.Team.HOME, Tuning.Team.AWAY]:
		var key := "home" if team == Tuning.Team.HOME else "away"
		out[key] = "%d.%d (%d)" % [goals[team], behinds[team], points[team]]
		out[key + "_points"] = points[team]
	return out


func _nearest_opponent(player: PlayerController) -> PlayerController:
	var best: PlayerController = null
	var best_d := INF
	for other in _players:
		if other.team == player.team:
			continue
		var d := other.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best
