extends Node

## Placeholder SFX — the design doc's own "prove the system before buying
## art" stance (already applied to the rig/animations) applied to sound:
## every clip is a short waveform synthesized in code at startup, not an
## imported audio asset. `assets/audio/` stays empty; dropping real files
## in later only ever needs `_build_clips()` changed, nothing downstream.
##
## Wires itself onto signals that already exist rather than asking
## gameplay code to know audio exists: PlayerController's disposal/mark/
## contest signals (see register_player, called once per spawned player)
## and Field.scored (register_field). The handful of match-flow moments
## with no natural per-instance signal to hook — stoppage whistles, full
## time — are called directly by full_game.gd at the exact points it
## already calls Scoreboard.flash() for the same moments, the established
## "this is where a match beat gets announced" convention in that file.
##
## A small round-robin voice pool (AudioStreamPlayer, non-positional —
## this is a broadcast-camera game, not first-person, so 2D audio reads
## fine for an MVP pass) rather than one node per event; overlapping
## sounds beyond VOICE_COUNT simply steal the oldest voice, acceptable
## since every clip here is well under half a second.

const VOICE_COUNT := 8
const MIX_RATE := 22050

enum Wave { SINE, NOISE, WHISTLE }

## Pea-whistle character for Wave.WHISTLE: the pea rattling in the chamber
## is a fast wobble in both pitch and loudness, plus a little breath noise.
## A plain sine at whistle pitch reads as a beep, not an umpire.
const WHISTLE_TRILL_HZ := 38.0
const WHISTLE_PITCH_WOBBLE := 0.012   ## fraction of the base pitch
const WHISTLE_AMP_WOBBLE := 0.25
const WHISTLE_BREATH := 0.06
const WHISTLE_ATTACK := 0.012         ## s fade-in, so it starts without a click

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0

var _clip_kick: AudioStreamWAV
var _clip_handball: AudioStreamWAV
var _clip_bounce: AudioStreamWAV
var _clip_mark: AudioStreamWAV
var _clip_miss: AudioStreamWAV
var _clip_tackle: AudioStreamWAV
var _clip_bump: AudioStreamWAV
var _clip_hit_out: AudioStreamWAV
var _clip_whistle: AudioStreamWAV
var _clip_mark_whistle: AudioStreamWAV
var _clip_full_time: AudioStreamWAV
var _clip_goal: AudioStreamWAV
var _clip_behind: AudioStreamWAV


func _ready() -> void:
	for i in VOICE_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_voices.append(player)
	_build_clips()


# ── Wiring ───────────────────────────────────────────────────────────

## Called once per spawned PlayerController (full_game.gd's _spawn_team,
## kick_to_kick.gd's _ready/_spawn_rival, main.gd's _ready) — every
## gameplay sound this file plays reaches here through one of these seven
## signals, already emitted by PlayerController for other reasons (camera
## punch, HUD, rumble), never a new hook invented just for audio.
func register_player(player: PlayerController) -> void:
	player.ball_disposed.connect(_on_ball_disposed)
	player.mark_caught.connect(_on_mark_caught)
	player.mark_missed.connect(_on_mark_missed)
	player.hit_out_resolved.connect(_on_hit_out_resolved)
	player.bump_landed.connect(_on_bump_landed)
	# Both fire only on the TACKLED player, from _get_tackled — one is the
	# real holding-the-ball ruling, the other the neutral inside-the-grace
	# case; both are audibly "a tackle just landed", just at different
	# emphasis (see _on_tackle/_on_tackle_neutral).
	player.holding_the_ball_called.connect(_on_tackle)
	player.field_ball_up_called.connect(_on_tackle_neutral)


## Called once per Field (full_game.gd only — kick_to_kick has no scoring).
func register_field(field: Field) -> void:
	field.scored.connect(_on_scored)


func play_whistle() -> void:
	_play(_clip_whistle, -3.0)


func play_full_time() -> void:
	_play(_clip_full_time, -1.0)


# ── Signal handlers ──────────────────────────────────────────────────

func _on_ball_disposed(action: Tuning.Action) -> void:
	match action:
		Tuning.Action.KICK:
			_play(_clip_kick, -2.0, randf_range(0.95, 1.05))
		Tuning.Action.HANDBALL:
			_play(_clip_handball, -4.0, randf_range(0.95, 1.05))
		Tuning.Action.BOUNCE:
			_play(_clip_bounce, -4.0, randf_range(0.95, 1.05))


## A legal mark gets the umpire's short pea-whistle blast (playtest: "the
## sound when player takes legal mark should sound like a whistle"); any
## other catch keeps the plain catch tone.
func _on_mark_caught(_tier: Tuning.Action, legal_mark: bool) -> void:
	if legal_mark:
		_play(_clip_mark_whistle, -4.0)
	else:
		_play(_clip_mark, -3.0)


func _on_mark_missed(_tier: Tuning.Action) -> void:
	_play(_clip_miss, -9.0)


func _on_hit_out_resolved(_player: PlayerController, connected: bool) -> void:
	if connected:
		_play(_clip_hit_out, -3.0)


func _on_bump_landed(_bumper: PlayerController, _carrier: PlayerController, clean: bool) -> void:
	_play(_clip_bump, -1.0 if clean else -6.0)


func _on_tackle(_tackler: PlayerController) -> void:
	_play(_clip_tackle, -1.0)


func _on_tackle_neutral(_tackler: PlayerController, _tackled: PlayerController) -> void:
	_play(_clip_tackle, -3.0)


func _on_scored(_team: Tuning.Team, is_goal: bool) -> void:
	_play(_clip_goal if is_goal else _clip_behind, 0.0)


# ── Playback ─────────────────────────────────────────────────────────

func _play(clip: AudioStreamWAV, volume_db := 0.0, pitch := 1.0) -> void:
	if clip == null or Settings.master_volume <= 0.0:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = clip
	voice.volume_db = volume_db + linear_to_db(Settings.master_volume)
	voice.pitch_scale = pitch
	voice.play()


# ── Synthesis ────────────────────────────────────────────────────────
# Every clip below is one call: a duration, an exponential decay rate (how
# quickly it fades — higher = shorter/punchier), a peak volume, a
# waveform, and (for tones) a start/end frequency. Impact-shaped events
# (bounce/tackle/bump) use noise, which reads as a physical hit; signal-
# shaped events (mark/whistle/goal) use a sine, which reads as a clean
# cue. No filtering/mixing beyond that — a genuinely minimal synth, same
# spirit as the placeholder rig's boxes-and-capsules geometry.

func _build_clips() -> void:
	_clip_kick = _synth(0.18, 18.0, 0.9, Wave.SINE, 90.0)
	_clip_handball = _synth(0.09, 34.0, 0.6, Wave.SINE, 380.0)
	_clip_bounce = _synth(0.07, 45.0, 0.55, Wave.NOISE)
	_clip_mark = _synth(0.12, 20.0, 0.5, Wave.SINE, 520.0)
	_clip_miss = _synth(0.08, 40.0, 0.3, Wave.NOISE)
	_clip_tackle = _synth(0.26, 9.0, 1.0, Wave.NOISE)
	_clip_bump = _synth(0.20, 13.0, 1.0, Wave.NOISE)
	_clip_hit_out = _synth(0.10, 24.0, 0.6, Wave.SINE, 300.0)
	_clip_whistle = _synth(0.35, 4.0, 0.5, Wave.SINE, 2200.0)
	_clip_mark_whistle = _synth(0.32, 3.0, 0.45, Wave.WHISTLE, 2600.0)
	_clip_full_time = _synth(1.4, 1.2, 0.55, Wave.SINE, 900.0)
	_clip_goal = _synth(0.55, 3.0, 0.6, Wave.SINE, 660.0, 990.0)
	_clip_behind = _synth(0.25, 6.0, 0.5, Wave.SINE, 440.0)


## `freq_end >= 0` sweeps linearly from `freq` to `freq_end` over the clip's
## duration (used for the goal siren's rising two-note read); otherwise the
## tone stays flat.
func _synth(duration: float, decay: float, volume: float, wave: Wave,
		freq := 220.0, freq_end := -1.0) -> AudioStreamWAV:
	var sample_count := maxi(1, int(duration * MIX_RATE))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var sweeping := freq_end >= 0.0
	var phase := 0.0
	for i in sample_count:
		var t := float(i) / MIX_RATE
		var f := lerpf(freq, freq_end, t / duration) if sweeping else freq
		var envelope := exp(-decay * t)
		var sample: float
		match wave:
			Wave.SINE:
				sample = sin(TAU * f * t)
			Wave.NOISE:
				sample = randf_range(-1.0, 1.0)
			Wave.WHISTLE:
				# Phase accumulated, not sin(TAU * f * t): the pitch wobbles
				# every sample, and a time-based phase would smear it.
				var trill := sin(TAU * WHISTLE_TRILL_HZ * t)
				phase += TAU * f * (1.0 + WHISTLE_PITCH_WOBBLE * trill) / MIX_RATE
				sample = sin(phase) * (1.0 - WHISTLE_AMP_WOBBLE + WHISTLE_AMP_WOBBLE * trill) \
					+ randf_range(-1.0, 1.0) * WHISTLE_BREATH
				sample *= minf(1.0, t / WHISTLE_ATTACK)
			_:
				sample = 0.0
		var value := clampf(sample * envelope * volume, -1.0, 1.0)
		data.encode_s16(i * 2, int(value * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	return stream
