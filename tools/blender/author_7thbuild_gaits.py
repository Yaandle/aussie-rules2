"""Authors Build 7's forward gait clips (walk, jog_fwd, run_fwd, run_fwd_l,
run_fwd_r) from a parametric running model, as real actions on
assets/blender/7thbuild.blend's Armature. Build 6's clips (and its .blend)
are never touched; the two builds share the skeleton but not these clips.

    blender assets/blender/7thbuild.blend --background --python tools/blender/author_7thbuild_gaits.py -- [clip ...] [--no-save]

WHY: the gait clips Build 7 inherited were authored for ~2.7 m/s (jog) and
~3.4 m/s (run) of ground under the planted foot, against the game's 4.8
and 8.4 m/s. PlayerAnimation plays them faster to keep up, but only up to a
believable cadence, so a planted foot skated 1.6 m/s at a jog and 3 m/s at
a sprint (scenes/dev/anim_audit.tscn). Their pelvis and chest never turned
(no counter-rotation), the arm swing was lopsided, the toe dipped through
the turf, and there was no walk: below a jog the feet were an idle/jog
blend sliding under a walking body.

THE MODEL: each foot's ball (the sole's contact under the toes) sweeps back
under the hip at exactly the design speed while it's down, so a played clip
plants its feet; the ankle is worked out from the ball and the foot's pitch
(heel strike, flat, heel-off rolling over the ball). Off the ground the
ankle swings forward on an arc that kicks the heel up behind at pace. Both
legs use the rig's own leg IK (iktarget, ikpole), with each knee's pole kept
in front of the knee as the foot rises (LESSONS.md: a pole left at knee
height flips a raised knee). On top: the pelvis drops through each stance
and rises through flight (walking the other way round), turns with the
swinging leg, and the chest counter-turns past it; the head undoes what's
left so it faces the way the body runs; the arms swing opposite their legs
from the shoulders, elbows bent more the faster the gait.

TIMING: every clip is one 16-frame cycle at 24 fps, the jog's length, so
PlayerAnimation's gait phase lock lines them up without stretching. That
makes each clip's design speed (what the planted foot sweeps at)
stride / (duty * cycle); PlayerAnimation's stride matching plays it at
the body's real speed over that, so a sprint's 8.4 m/s turns over ~4.8
steps a second. The left foot lands at frame 1.

GAITS below is the whole design: tune it and re-run, then export
(export_7thbuild.py) and import. Gameplay never reads these clips' shapes;
the ragdoll does read the pose a player is in when a tackle lands
(PhysicsRagdoll builds from the animated pose), so tackle_sweep.tscn on
Build 7 moves with any change here (Build 6's doesn't).
"""

import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import author_6thbuild_clips as A  # noqa: E402  (the rig helpers: IK, keying, frames)

FRAMES = 16          # one cycle; the jog's length, so phase lock never stretches
## The stance foot's contact point, m from the ankle along the foot: the
## toe tip. The foot is one rigid bone (no toe bone), so a heel-off that
## rolled over the ball of the foot sank the toe 6 cm into the turf and
## slid it; rolling over the toe tip keeps the whole boot above ground.
BALL = 0.30
REST_ANKLE_Z = 0.082

## name -> parameters. stride: how far the ball sweeps back under the hip
## while down (m); duty: share of the cycle each foot is down; back: where
## the ball leaves the ground, metres behind the hip (set by the leg's
## reach with the heel up); pelvis: drop below the rest pose and the bob
## either way (m); swing: ankle lift at the top of the swing (m) and
## where in the swing it peaks (0-1); strike / off: the foot's angle below
## horizontal at touchdown and lift-off (deg; the rest foot is 10);
## track: feet's distance either side of the midline; turn: pelvis turn
## with the swinging leg (deg), chest counter-turns this much past
## straight; lean: forward tilt of pelvis and torso (deg); arms: hand
## range fore-aft from the shoulder (m back, m forward), hand height at
## the back and front (m below the shoulder), elbow pole; toe_up: how
## far into the swing the toe starts to lift (a walk clears the turf at
## once, a sprint's heel kick keeps the toe pointed); travel: the
## direction the body is running relative to its facing (deg, + = to the
## character's left), for the diagonals.
## Every pose stays inside PhysicsRagdoll.BODIES' joint limits (hip 30 deg
## back / 65 forward, arm 75 swing): a tackle can land on any frame, and
## the ragdoll starts from the animated pose. The first cut of these gaits
## went 50 deg back at the hip and started tackle_sweep's falls at 100
## rad/s; contact is short (duty) instead, as a sprinter's is.
GAITS = {
	"walk": {"stride": 0.99, "duty": 0.58, "back": 0.30, "pelvis": (0.040, -0.014), "swing": (0.12, 0.30), "toe_up": 0.0,
		"strike": -8.0, "off": 42.0, "track": 0.135, "turn": 6.0, "counter": 9.0, "lean": 2.0,
		"arms": (0.16, 0.16, 0.56, 0.54), "elbow": 0.35, "travel": 0.0},
	"jog_fwd": {"stride": 0.77, "duty": 0.24, "back": 0.27, "pelvis": (0.045, 0.022), "swing": (0.25, 0.38), "toe_up": 0.25,
		"strike": -2.0, "off": 44.0, "track": 0.125, "turn": 8.0, "counter": 12.0, "lean": 5.0,
		"arms": (0.20, 0.24, 0.40, 0.30), "elbow": 0.8, "travel": 0.0},
	"run_fwd": {"stride": 0.70, "duty": 0.20, "back": 0.28, "pelvis": (0.055, 0.026), "swing": (0.30, 0.34), "toe_up": 0.35,
		"strike": 20.0, "off": 46.0, "track": 0.115, "turn": 10.0, "counter": 15.0, "lean": 9.0,
		"arms": (0.24, 0.26, 0.38, 0.16), "elbow": 1.0, "travel": 0.0},
}
## The run diagonals: the sprint, running 45 deg off the facing, the pelvis
## turned 40% of the way toward where it's going. run_fwd_l runs to the
## character's left (blend point (-0.75, 0.75)).
DIAGONALS = {"run_fwd_l": ("run_fwd", 45.0), "run_fwd_r": ("run_fwd", -45.0)}


def smooth(t):
	t = max(0.0, min(1.0, t))
	return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
	return a + (b - a) * t


def foot_state(g, phi):
	"""Ball position along the travel axis (m, + ahead of the hip), ankle
	height and foot angle below horizontal for one foot at cycle phase phi
	(0 = touchdown). Stance: the ball moves back linearly at the design
	speed. Swing: the ankle arcs forward."""
	d = g["duty"]
	front = g["stride"] - g["back"]
	back = -g["back"]
	if phi < d:
		s = phi / d
		ball = lerp(front, back, s)
		# Heel strike rolls to flat over the first 20%, heel-off from 55%.
		if s < 0.2:
			ang = lerp(g["strike"], 10.0, smooth(s / 0.2))
		elif s > 0.55:
			ang = lerp(10.0, g["off"], smooth((s - 0.55) / 0.45))
		else:
			ang = 10.0
		ankle = ankle_from_ball(ball, ang)
		return ankle, ang, True
	s = (phi - d) / (1.0 - d)
	lo = ankle_from_ball(back, g["off"])
	td = ankle_from_ball(front, g["strike"])
	# The foot leaves and lands still on the turf: it keeps sweeping back
	# at the stance speed as it lifts, turns forward (heel recovery, then
	# the knee drives it through), and is sweeping back again as it lands.
	# A cubic with those end velocities; stopping dead under the hip as the
	# swing began skated the toe forward at full body speed (the audit).
	peak = g["swing"][1]
	# 75% of the stance speed: the full speed overshot the touchdown point
	# mid-swing and took the thigh past the ragdoll's 65 deg hip stop.
	m = -0.75 * g["stride"] / g["duty"] * (1.0 - d)   # d x / d s
	h00, h10 = 2 * s ** 3 - 3 * s ** 2 + 1, s ** 3 - 2 * s ** 2 + s
	h01, h11 = -2 * s ** 3 + 3 * s ** 2, s ** 3 - s ** 2
	x = h00 * lo[0] + h10 * m + h01 * td[0] + h11 * m
	base_z = lerp(lo[1], td[1], s)
	arc = smooth(s / peak) * (1.0 - smooth((s - 0.62) / 0.38) * 1.0)
	arc *= lerp(1.0, 0.8, smooth((s - peak) / (0.62 - peak)))
	z = base_z + g["swing"][0] * arc
	# Toe down as it leaves, toe up as it lands.
	up = g["toe_up"]
	ang = lerp(g["off"], g["strike"], smooth((s - up) / (0.95 - up)))
	return (x, z), ang, False


def ankle_from_ball(ball, ang):
	"""Ankle (along-travel offset, height) for the ball at `ball` on the
	turf with the foot `ang` deg below horizontal."""
	a = math.radians(ang)
	ball_z = REST_ANKLE_Z - BALL * math.sin(math.radians(10.0))
	if ang < 10.0:
		# Toe up at heel strike: the heel is the contact, so the ankle sits
		# at its rest height and the ball rises.
		return (ball - BALL * math.cos(a), REST_ANKLE_Z)
	return (ball - BALL * math.cos(a), ball_z + BALL * math.sin(a))


def forwardness(g, phi):
	"""-1 (foot furthest back) .. +1 (furthest forward), smooth round the
	cycle: what the arms and pelvis turn follow."""
	(x, _), _, _ = foot_state(g, phi)
	front = g["stride"] - g["back"]
	back = -g["back"] - BALL
	return max(-1.0, min(1.0, 2.0 * (x - back) / (front - back) - 1.0))


def leg_ik(rig, basis, side, ankle, ang, turn):
	"""Keys one leg: iktarget on the ankle with the foot's pitch, ikpole in
	front of the knee in the leg's own plane."""
	pose = rig.fk(basis)
	H = pose["upperleg." + side].translation
	L1 = (rig.rest["lowerleg." + side].translation - rig.rest["upperleg." + side].translation).length
	L2 = (rig.rest["foot." + side].translation - rig.rest["lowerleg." + side].translation).length
	to_a = ankle - H
	d = max(abs(L1 - L2) + 0.02, min(L1 + L2 - 0.003, to_a.length))
	u = to_a.normalized()
	fwd = A.P(0, 1, 0)
	v = fwd - u * fwd.dot(u)
	if v.length < 1e-4:
		v = A.P(0, 0, 1)
	v.normalize()
	a = (L1 * L1 - L2 * L2 + d * d) / (2.0 * d)
	h = math.sqrt(max(L1 * L1 - a * a, 0.0))
	K = H + u * a + v * h
	pole = K + v * 0.8
	target, pole_name = "iktarget." + side, "ikpole." + side
	pitch = (ang - A.FOOT_REST_BELOW) * A.FOOT_PITCH_SIGN
	q = A.rot((1, 0, 0), pitch) @ A.rot((0, 0, 1), turn)
	basis[target] = (rig.rest_rot[target].inverted() @ (ankle - rig.rest[target].translation), q)
	basis[pole_name] = (rig.rest_rot[pole_name].inverted() @ (pole - rig.rest[pole_name].translation),
		basis[pole_name][1])


def pose_spec(rig, g, phi, travel):
	"""The spec for build_basis at cycle phase phi, plus the two feet."""
	phases = {"l": phi % 1.0, "r": (phi + 0.5) % 1.0}
	fl = forwardness(g, phases["l"])
	fr = forwardness(g, phases["r"])
	walk = g["duty"] > 0.5
	# Pelvis height: running drops through each stance (lowest mid-stance),
	# walking vaults over it (highest mid-stance).
	mid = g["duty"] * 0.5
	wave = math.cos(4.0 * math.pi * (phi - mid))   # 1 at each mid-stance
	drop, bob = g["pelvis"]
	z = -drop + abs(bob) * wave if walk else -drop - bob * wave
	# Pelvis turns with the swinging leg (left leg forward -> faces right),
	# the chest counter-turns past straight, the head faces the run.
	turn = -g["turn"] * 0.5 * (fl - fr)
	turn_travel = 0.4 * travel
	counter = g["counter"] * 0.5 * (fl - fr)   # the chest turns against the pelvis
	sway = 0.012 * (fl - fr) * (0.5 if not walk else 1.0)
	spec = {
		# The forward tilt is all in the spine: tilting the pelvis took the
		# trailing thigh past the ragdoll's 30 deg hip stop, and a tackle
		# landing mid-stride snapped it there (tackle_sweep, Build 7).
		"pelvis": {"pos": A.P(sway, 0.0, z), "rot": A.lean(turn=turn + turn_travel)},
		"spine1": A.lean(fwd=g["lean"] * 0.5, turn=(counter - turn) * 0.5 - turn_travel * 0.3),
		"spine2": A.lean(fwd=g["lean"] * 0.5, turn=(counter - turn) * 0.5 - turn_travel * 0.3),
		"head": A.lean(fwd=-g["lean"] * 0.9, turn=-counter - turn_travel * 0.4),
		"hands_in": "chest",
		# Elbows bend about the ragdoll's hinge (author_6thbuild_clips.solve_arm).
		"elbow_hinge": True,
	}
	# Arms: each swings opposite its own leg, from the shoulder, in the
	# chest's frame; elbows bend more as the hand comes forward.
	back_r, fwd_r, low, high = g["arms"]
	for side, f in (("l", fr), ("r", fl)):
		k = (f + 1.0) * 0.5
		sx = 1.0 if side == "l" else -1.0
		reach_fwd = lerp(-back_r, fwd_r, k)
		down = lerp(low, high, k)
		inward = lerp(0.02, 0.10, k) * g["elbow"]
		spec["hand_" + side] = A.P(sx * (0.02 - inward), reach_fwd, -down)
		spec["elbow_" + side] = A.P(sx * 0.35, -0.6, -0.8)
	clav = 3.0 * (fl - fr) * 0.5
	spec["clav_l"] = A.clav(lift=1.0, fwd=-clav)
	spec["clav_r"] = A.mirror_q(A.clav(lift=1.0, fwd=clav))
	return spec, phases


def author_gait(rig, base, name, g, travel=0.0, fps=24):
	arm_obj = rig.obj
	old = bpy.data.actions.get(name)
	if old is not None:
		for track in list(arm_obj.animation_data.nla_tracks):
			if any(s.action is old for s in track.strips):
				arm_obj.animation_data.nla_tracks.remove(track)
		bpy.data.actions.remove(old)
	action = bpy.data.actions.new(name)
	action.use_fake_user = True
	keyer = A.Keyer(rig, action, fps)
	tr = math.radians(travel)
	axis = Vector((math.sin(tr), -math.cos(tr), 0.0))   # travel, armature space (left +X, forward -Y)
	for f in range(FRAMES + 1):
		phi = (f % FRAMES) / FRAMES
		spec, phases = pose_spec(rig, g, phi, travel)
		basis, _ = A.build_basis(rig, base, spec)
		pose = rig.fk(basis)
		for side in ("l", "r"):
			(x, z), ang, _ = foot_state(g, phases[side])
			sx = 1.0 if side == "l" else -1.0
			# The feet run on two lines either side of the hips' midline.
			mid = (pose["upperleg.l"].translation + pose["upperleg.r"].translation) * 0.5
			lateral = Vector((-axis.y, axis.x, 0.0)) * sx   # left of travel for the left foot
			ankle = Vector((mid.x, mid.y, 0.0)) + lateral * g["track"] + axis * x
			ankle.z = z
			# Rest ankles sit 2.4 cm behind the hip line.
			ankle += A.P(0, -0.024, 0)
			leg_ik(rig, basis, side, ankle, ang, travel * 0.5)
		for bone in A.FK_BONES + A.LEG_CONTROL_BONES:
			loc, q = basis[bone]
			keyer.key(1 + f, bone, loc=loc if bone == "pelvis" or bone.startswith("ik") else None, q=q)
	keyer.finish()
	track = arm_obj.animation_data.nla_tracks.new()
	track.name = name
	track.strips.new(name, 1, action)
	track.mute = True
	cycle = FRAMES / fps
	speed = g["stride"] / (g["duty"] * cycle)
	print("author_7thbuild_gaits: %-10s %d frames (%.3f s), design speed %.2f m/s, %.2f steps/s as authored" % (
		name, FRAMES, cycle, speed, 2.0 / cycle))
	return action


def main():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	save = "--no-save" not in argv
	# Other scripts chained in the same Blender run may pass their own args.
	names = [a for a in argv if a in GAITS or a in DIAGONALS] or list(GAITS) + list(DIAGONALS)
	arm_obj = bpy.data.objects[A.ARMATURE]
	fps = bpy.context.scene.render.fps
	ad = arm_obj.animation_data
	saved_action = ad.action
	saved_mutes = {t.name: t.mute for t in ad.nla_tracks}
	ad.action = None
	for t in ad.nla_tracks:
		t.mute = True
	for name in A.FK_BONES + A.LEG_CONTROL_BONES:
		pb = arm_obj.pose.bones[name]
		pb.location = (0, 0, 0)
		pb.rotation_quaternion = (1, 0, 0, 0)
		pb.rotation_euler = (0, 0, 0)
	A.calibrate_foot_pitch(arm_obj)
	foot = arm_obj.data.bones["foot.r"]
	along = foot.tail_local - foot.head_local
	A.FOOT_REST_BELOW = math.degrees(math.atan2(-along.z, -along.y))
	rig = A.Rig(arm_obj)
	# The inherited idle (idle_base once author_7thbuild_idle.py has run).
	base_src = A.base_action()
	base = A.sample_action(rig, base_src, base_src.frame_range[0])
	for name in names:
		if name in GAITS:
			author_gait(rig, base, name, GAITS[name], 0.0, fps)
		elif name in DIAGONALS:
			src, travel = DIAGONALS[name]
			author_gait(rig, base, name, GAITS[src], travel, fps)
	ad.action = saved_action
	for t in ad.nla_tracks:
		t.mute = saved_mutes.get(t.name, True)
	if save:
		bpy.ops.wm.save_mainfile()
		print("author_7thbuild_gaits: saved", bpy.data.filepath)


if __name__ == "__main__":
	main()
