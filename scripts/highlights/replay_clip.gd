class_name ReplayClip
extends RefCounted

## One highlight's recorded footage: what every body on the ground looked
## like, 30 times a second, for a few seconds either side of the moment.
## Not a re-simulation. Jolt contacts, ragdolls and AI timing don't replay
## bit-identically over a match (docs/LESSONS.md), so the recorder saves
## poses, and playback writes them onto puppet rigs (ReplayStage).
##
## `meta` describes the bodies once (model, kit, scale, bone count, which
## bones carry a position as well as a rotation); each frame is a packed
## byte buffer:
##
##   header   clock f32 (seconds left in the quarter), quarter u8,
##            home goals u8, home behinds u8, away goals u8, away behinds u8
##   ball     position 3×f32, rotation 4×i16
##   body ×N  root position 3×f32, root rotation 4×i16,
##            bone rotations bones×4×i16, positioned bones pos_bones×3×f32
##
## Rotations are unit quaternions stored as int16 (×32767): about 1e-4
## rad of error, well under anything visible. A .replay file is
## `store_var(meta)` then each frame as `store_32(size)` + bytes.

const VERSION := 1
const QUAT_SCALE := 32767.0

var meta: Dictionary = {}
var frames: Array[PackedByteArray] = []


func frame_count() -> int:
	return frames.size()


func fps() -> float:
	return float(meta.get("fps", HighlightTable.RECORD_FPS))


func duration() -> float:
	return maxf(0.0, float(frames.size() - 1) / fps())


func save(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var header := meta.duplicate(true)
	header["version"] = VERSION
	header["frame_count"] = frames.size()
	file.store_var(header)
	for frame in frames:
		file.store_32(frame.size())
		file.store_buffer(frame)
	file.close()
	return OK


static func load_file(path: String) -> ReplayClip:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var clip := ReplayClip.new()
	clip.meta = file.get_var()
	for i in int(clip.meta.get("frame_count", 0)):
		clip.frames.append(file.get_buffer(file.get_32()))
	file.close()
	return clip


# ── Packing helpers (shared by the recorder and the stage) ──────────

static func put_vec3(buf: StreamPeerBuffer, v: Vector3) -> void:
	buf.put_float(v.x)
	buf.put_float(v.y)
	buf.put_float(v.z)


static func get_vec3(buf: StreamPeerBuffer) -> Vector3:
	var x := buf.get_float()
	var y := buf.get_float()
	return Vector3(x, y, buf.get_float())


static func put_quat(buf: StreamPeerBuffer, q: Quaternion) -> void:
	# One hemisphere, so interpolating two frames never takes the long way.
	if q.w < 0.0:
		q = -q
	buf.put_16(int(round(clampf(q.x, -1.0, 1.0) * QUAT_SCALE)))
	buf.put_16(int(round(clampf(q.y, -1.0, 1.0) * QUAT_SCALE)))
	buf.put_16(int(round(clampf(q.z, -1.0, 1.0) * QUAT_SCALE)))
	buf.put_16(int(round(clampf(q.w, -1.0, 1.0) * QUAT_SCALE)))


static func get_quat(buf: StreamPeerBuffer) -> Quaternion:
	var x := buf.get_16() / QUAT_SCALE
	var y := buf.get_16() / QUAT_SCALE
	var z := buf.get_16() / QUAT_SCALE
	var q := Quaternion(x, y, z, buf.get_16() / QUAT_SCALE)
	return q.normalized() if q.length_squared() > 0.0001 else Quaternion.IDENTITY


## Cheap reads straight from a frame's bytes, for code that wants one body's
## position or the ball every frame of a clip (the third-person camera, the
## goal camera's hold) without decoding all ~40 skeletons.
const HEADER_BYTES := 9            ## clock f32 + quarter, 4 score bytes
const BALL_BYTES := 20             ## position 3×f32 + rotation 4×i16

var _body_offsets := PackedInt32Array()


func _offset_of(body: int) -> int:
	if _body_offsets.is_empty():
		var at := HEADER_BYTES + BALL_BYTES
		for entry: Dictionary in meta.bodies:
			_body_offsets.append(at)
			at += 12 + 8 + int(entry.bones) * 8 + (entry.pos_bones as Array).size() * 12
	return _body_offsets[body]


func ball_position(index: int) -> Vector3:
	var buf := frames[clampi(index, 0, frames.size() - 1)]
	return Vector3(buf.decode_float(HEADER_BYTES), buf.decode_float(HEADER_BYTES + 4),
		buf.decode_float(HEADER_BYTES + 8))


func body_position(index: int, body: int) -> Vector3:
	var buf := frames[clampi(index, 0, frames.size() - 1)]
	var at := _offset_of(body)
	return Vector3(buf.decode_float(at), buf.decode_float(at + 4), buf.decode_float(at + 8))


## Which way body `body` faces in frame `index` (its -Z, the way HumanoidRig
## looks), as a world vector.
func body_facing(index: int, body: int) -> Vector3:
	var buf := frames[clampi(index, 0, frames.size() - 1)]
	var at := _offset_of(body) + 12
	var q := Quaternion(buf.decode_s16(at) / QUAT_SCALE, buf.decode_s16(at + 2) / QUAT_SCALE,
		buf.decode_s16(at + 4) / QUAT_SCALE, buf.decode_s16(at + 6) / QUAT_SCALE)
	if q.length_squared() < 0.0001:
		return Vector3.FORWARD
	return q.normalized() * Vector3.FORWARD


## Decodes frame `index` into plain arrays:
## {clock, quarter, goals:[hg,hb,ag,ab], ball_pos, ball_rot,
##  bodies:[{pos, rot, bones: Array[Quaternion], bone_pos: Array[Vector3]}]}
func decode(index: int) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = frames[clampi(index, 0, frames.size() - 1)]
	var out := {}
	out.clock = buf.get_float()
	out.quarter = buf.get_u8()
	out.goals = [buf.get_u8(), buf.get_u8(), buf.get_u8(), buf.get_u8()]
	out.ball_pos = get_vec3(buf)
	out.ball_rot = get_quat(buf)
	var bodies: Array = []
	for body: Dictionary in meta.bodies:
		var entry := {}
		entry.pos = get_vec3(buf)
		entry.rot = get_quat(buf)
		var bones: Array[Quaternion] = []
		for b in int(body.bones):
			bones.append(get_quat(buf))
		entry.bones = bones
		var bone_pos: Array[Vector3] = []
		for b in (body.pos_bones as Array).size():
			bone_pos.append(get_vec3(buf))
		entry.bone_pos = bone_pos
		bodies.append(entry)
	out.bodies = bodies
	return out
