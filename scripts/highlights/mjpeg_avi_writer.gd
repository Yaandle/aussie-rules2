class_name MjpegAviWriter
extends RefCounted

## Writes a Motion-JPEG .avi, one JPEG per frame, from inside the running
## game. Godot can't encode video at runtime: its own movie writer (which
## writes this same format) only starts from the command line for the whole
## window. MJPEG AVI is what that writer makes too, and every player and
## ffmpeg reads it. The Highlights exporter converts to .mp4 as well when
## ffmpeg is on PATH.
##
## RIFF layout: hdrl (avih, strl(strh, strf)), movi (00dc chunks), idx1.
## The frame counts and sizes are patched in on close().

var _file: FileAccess
var _frames := 0
var _index := PackedByteArray()
var _riff_size_at := 0
var _avih_frames_at := 0
var _strh_length_at := 0
var _movi_size_at := 0
var _movi_start := 0
var _max_frame := 0
var _suggested_at: Array[int] = []


func open(path: String, size: Vector2i, fps: int) -> Error:
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	_fourcc("RIFF")
	_riff_size_at = _file.get_position()
	_file.store_32(0)
	_fourcc("AVI ")

	_fourcc("LIST")
	_file.store_32(4 + 8 + 56 + 8 + 4 + 8 + 56 + 8 + 40)
	_fourcc("hdrl")
	_fourcc("avih")
	_file.store_32(56)
	_file.store_32(int(round(1000000.0 / fps)))  # microseconds per frame
	_file.store_32(0)          # max bytes per second
	_file.store_32(0)          # padding granularity
	_file.store_32(0x10)       # AVIF_HASINDEX
	_avih_frames_at = _file.get_position()
	_file.store_32(0)          # total frames
	_file.store_32(0)          # initial frames
	_file.store_32(1)          # streams
	_suggested_at.append(_file.get_position())
	_file.store_32(0)          # suggested buffer size
	_file.store_32(size.x)
	_file.store_32(size.y)
	for i in 4:
		_file.store_32(0)

	_fourcc("LIST")
	_file.store_32(4 + 8 + 56 + 8 + 40)
	_fourcc("strl")
	_fourcc("strh")
	_file.store_32(56)
	_fourcc("vids")
	_fourcc("MJPG")
	_file.store_32(0)          # flags
	_file.store_16(0)          # priority
	_file.store_16(0)          # language
	_file.store_32(0)          # initial frames
	_file.store_32(1)          # scale
	_file.store_32(fps)        # rate (rate / scale = fps)
	_file.store_32(0)          # start
	_strh_length_at = _file.get_position()
	_file.store_32(0)          # length in frames
	_suggested_at.append(_file.get_position())
	_file.store_32(0)          # suggested buffer size
	_file.store_32(0xFFFFFFFF) # quality: default
	_file.store_32(0)          # sample size
	_file.store_16(0)
	_file.store_16(0)
	_file.store_16(size.x)
	_file.store_16(size.y)

	_fourcc("strf")
	_file.store_32(40)
	_file.store_32(40)         # BITMAPINFOHEADER size
	_file.store_32(size.x)
	_file.store_32(size.y)
	_file.store_16(1)          # planes
	_file.store_16(24)         # bit count
	_fourcc("MJPG")
	_file.store_32(size.x * size.y * 3)
	for i in 4:
		_file.store_32(0)

	_fourcc("LIST")
	_movi_size_at = _file.get_position()
	_file.store_32(0)
	_movi_start = _file.get_position()
	_fourcc("movi")
	return OK


func add_jpeg(jpeg: PackedByteArray) -> void:
	var offset := _file.get_position() - _movi_start
	_fourcc("00dc")
	_file.store_32(jpeg.size())
	_file.store_buffer(jpeg)
	if jpeg.size() % 2 == 1:
		_file.store_8(0)
	var entry := StreamPeerBuffer.new()
	entry.put_data("00dc".to_ascii_buffer())
	entry.put_u32(0x10)        # AVIIF_KEYFRAME
	entry.put_u32(offset)
	entry.put_u32(jpeg.size())
	_index.append_array(entry.data_array)
	_frames += 1
	_max_frame = maxi(_max_frame, jpeg.size())


func add_image(image: Image, quality: float) -> void:
	add_jpeg(image.save_jpg_to_buffer(quality))


func frame_count() -> int:
	return _frames


func close() -> void:
	if _file == null:
		return
	var movi_end := _file.get_position()
	_fourcc("idx1")
	_file.store_32(_index.size())
	_file.store_buffer(_index)
	var end := _file.get_position()
	_file.seek(_riff_size_at)
	_file.store_32(end - 8)
	_file.seek(_movi_size_at)
	_file.store_32(movi_end - _movi_start)
	_file.seek(_avih_frames_at)
	_file.store_32(_frames)
	_file.seek(_strh_length_at)
	_file.store_32(_frames)
	for at in _suggested_at:
		_file.seek(at)
		_file.store_32(_max_frame + 8)
	_file.close()
	_file = null


func _fourcc(code: String) -> void:
	_file.store_buffer(code.to_ascii_buffer())
