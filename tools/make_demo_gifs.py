"""Turns demo_recorder frames into the README's demo GIFs.

scenes/dev/demo_recorder.tscn writes one PNG per frame under Godot's movie
writer (see the header of scripts/dev/demo_recorder.gd). This script drops
every other frame (30 -> 15 fps), scales to WIDTH and gives every frame its
own 256-colour palette. One palette shared by the whole GIF went to the
studio's whites and greys and lost the small bright things: the cue rings,
the boots, the landing marker. No dithering keeps the files small.

    python tools/make_demo_gifs.py <frames root> docs/media

where <frames root> holds one folder of frames per demo (marking/,
tackling/, ruck/, kicking/). Needs Pillow.
"""

import os
import sys

from PIL import Image

WIDTH = 720
FRAME_STEP = 2          # 30 fps recording -> 15 fps GIF
FRAME_MS = 1000 * FRAME_STEP // 30
SKIP_START = 6          # the viewer's first frames, before the take starts
COLOURS = 256


def load_frames(folder):
    names = sorted(n for n in os.listdir(folder) if n.endswith(".png"))
    names = names[SKIP_START::FRAME_STEP]
    frames = []
    for name in names:
        image = Image.open(os.path.join(folder, name)).convert("RGB")
        height = round(image.height * WIDTH / image.width)
        frames.append(image.resize((WIDTH, height), Image.LANCZOS))
    return frames


def make_gif(folder, out_path):
    frames = load_frames(folder)
    quantized = [f.quantize(colors=COLOURS, method=Image.Quantize.MEDIANCUT,
                            dither=Image.Dither.NONE) for f in frames]
    quantized[0].save(out_path, save_all=True, append_images=quantized[1:],
                      duration=FRAME_MS, loop=0, optimize=True, disposal=1)
    size_mb = os.path.getsize(out_path) / 1e6
    print(f"{out_path}: {len(quantized)} frames, {size_mb:.1f} MB")


def main():
    root, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    for demo in sorted(os.listdir(root)):
        folder = os.path.join(root, demo)
        if os.path.isdir(folder):
            make_gif(folder, os.path.join(out_dir, demo + ".gif"))


if __name__ == "__main__":
    main()
