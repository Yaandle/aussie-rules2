"""Turns demo_recorder frames into the README's demo GIFs and the video MP4s.

scenes/dev/demo_recorder.tscn writes one 1600x900 PNG per frame at 30 fps
under Godot's movie writer, plus a captions.json (see the header of
scripts/dev/demo_recorder.gd). For each demo folder this script writes:

  <out>/<demo>.gif        README copy: WIDTH wide, GIF_FPS, with the control
                          caption drawn bottom-left.
  <out>/video/<demo>.mp4  Video copy: full size, constant 30 fps, H.264
                          (yuv420p), no audio, no captions, no B-frames, so
                          the first frame is at t = 0 and frame n is at n/30.

Both drop the first SKIP_START frames (the ground loading, before the first
take), so they start on the same frame.

The GIF resamples 30 fps to GIF_FPS by nearest frame (GIF delays are whole
centiseconds, so 30 fps can't be written exactly) and gives every frame its
own palette: one shared palette lost the small bright things (the cue ring,
the boots, the ball). No dithering keeps the files small.

    python tools/make_demo_gifs.py <frames root> docs/media

where <frames root> holds one folder of frames per demo (marking/,
tackling/, ruck/, kicking/). Needs Pillow, and ffmpeg for the MP4s: on PATH,
or the one the imageio-ffmpeg package ships.
"""

import json
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFont

WIDTH = 640
REC_FPS = 30
GIF_FPS = 20            # 5 cs a frame
SKIP_START = 9          # demo_recorder.gd's LEAD_IN
COLOURS = 64
FONT_PATHS = ["C:/Windows/Fonts/arialbd.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]


def frame_names(folder):
    return sorted(n for n in os.listdir(folder) if n.endswith(".png"))[SKIP_START:]


def load_captions(folder):
    path = os.path.join(folder, "captions.json")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def caption_at(captions, t):
    text = ""
    for when, what in captions:
        if when <= t + 1e-6:
            text = what
    return text


def load_font(size):
    for path in FONT_PATHS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def draw_caption(image, text, font):
    if not text:
        return
    draw = ImageDraw.Draw(image)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    pad_x, pad_y, margin = 10, 6, 12
    x0 = margin
    y1 = image.height - margin
    y0 = y1 - (bottom - top) - pad_y * 2
    x1 = x0 + (right - left) + pad_x * 2
    draw.rectangle((x0 + 3, y0 + 3, x1 + 3, y1 + 3), fill=(24, 24, 24))
    draw.rectangle((x0, y0, x1, y1), fill=(245, 242, 232), outline=(24, 24, 24), width=2)
    draw.text((x0 + pad_x - left, y0 + pad_y - top), text, font=font, fill=(24, 24, 24))


def make_gif(folder, out_path):
    names = frame_names(folder)
    captions = load_captions(folder)
    font = load_font(15)
    count = int(len(names) * GIF_FPS / REC_FPS)
    frames = []
    for i in range(count):
        t = i / GIF_FPS
        source = min(round(t * REC_FPS), len(names) - 1)
        image = Image.open(os.path.join(folder, names[source])).convert("RGB")
        height = round(image.height * WIDTH / image.width)
        image = image.resize((WIDTH, height), Image.LANCZOS)
        draw_caption(image, caption_at(captions, t), font)
        frames.append(image.quantize(colors=COLOURS, method=Image.Quantize.MEDIANCUT,
                                     dither=Image.Dither.NONE))
    frames[0].save(out_path, save_all=True, append_images=frames[1:],
                   duration=1000 // GIF_FPS, loop=0, optimize=True, disposal=1)
    print(f"{out_path}: {len(frames)} frames, {len(frames) / GIF_FPS:.2f} s, "
          f"{os.path.getsize(out_path) / 1e6:.1f} MB")


def find_ffmpeg():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return None


def make_mp4(folder, out_path, ffmpeg):
    names = frame_names(folder)
    first = int(names[0][1:-4])          # f00000009.png -> 9
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", str(REC_FPS),
                    "-start_number", str(first), "-i", os.path.join(folder, "f%08d.png"),
                    "-frames:v", str(len(names)), "-an", "-c:v", "libx264", "-preset", "slow",
                    "-crf", "16", "-bf", "0", "-pix_fmt", "yuv420p", "-r", str(REC_FPS),
                    "-movflags", "+faststart", out_path], check=True)
    print(f"{out_path}: {len(names)} frames, {len(names) / REC_FPS:.2f} s, "
          f"{os.path.getsize(out_path) / 1e6:.1f} MB")


def main():
    root, out_dir = sys.argv[1], sys.argv[2]
    video_dir = os.path.join(out_dir, "video")
    os.makedirs(video_dir, exist_ok=True)
    ffmpeg = find_ffmpeg()
    if ffmpeg is None:
        print("no ffmpeg found: GIFs only")
    for demo in sorted(os.listdir(root)):
        folder = os.path.join(root, demo)
        if not os.path.isdir(folder):
            continue
        make_gif(folder, os.path.join(out_dir, demo + ".gif"))
        if ffmpeg is not None:
            make_mp4(folder, os.path.join(video_dir, demo + ".mp4"), ffmpeg)


if __name__ == "__main__":
    main()
