# Build 6 rework (2026-11-24)

Build 6 (`6thbuild`) is the user's own hand-modelled player: a half body
with a Mirror modifier, the torso, shoulders and arms pulled out of one mesh
from the head down. This pass keeps that model and its design and makes
small changes toward the reference turnaround
(`docs/review/8thbuild/reference_turnaround.webp`), plus the fixes it
needed to deform cleanly. Every original vertex is where it was.

| What | Path |
|---|---|
| Blender source | `F:\dev\learning-&-development\New Folder\6thbuild.blend` (outside the repo) |
| Backup before this pass | `6thbuild.backup-20261124-prerework.blend`, same folder |
| Untouched originals, in the file | `Body_original` etc. in the excluded collection "6thbuild originals (untouched)" |
| Rework script | `tools/blender/rework_6thbuild.py` (rebuilds from the originals every run) |
| Arms-down idle | `tools/blender/author_6thbuild_idle.py` |
| Deformation check | `tools/blender/check_6thbuild_deform.py` |
| Review sheets from Blender | `tools/blender/render_6thbuild_review.py` (`--idle`, `--hands`, `--joints`, `--poses`, `--wire`) |
| Exporter | `tools/blender/export_6thbuild.py` |
| In-game renders | `docs/review/6thbuild/ref_*.png` (`reference_match.tscn -- --model=6thbuild`) |

```powershell
& "F:\blender\blender.exe" "F:\dev\learning-&-development\New Folder\6thbuild.blend" --background --python tools/blender/rework_6thbuild.py --python tools/blender/author_6thbuild_idle.py -- --save
& "F:\blender\blender.exe" "F:\dev\learning-&-development\New Folder\6thbuild.blend" --background --python tools/blender/check_6thbuild_deform.py
& "F:\blender\blender.exe" "F:\dev\learning-&-development\New Folder\6thbuild.blend" --background --python tools/blender/export_6thbuild.py
```

Hand edits to Body/Shirt/Shorts/Shoes are lost the next time the rework
script runs (it starts from the `_original` copies). To keep editing by
hand, edit the live objects and stop running the script, or edit the
`_original` objects and run it again.

## What changed

- **Hands.** The old hand (a mitten of 854 vertices) is cut off past the
  forearm's wrist ring and a new one is bridged onto that ring: a domed
  palm with a thenar pad, four fingers in three phalanges with knuckles, a
  thumb along the index finger. Rigid on the hand bone (no finger bones).
- **Face and hair**, laid on the original head without reshaping it: nose,
  brow ridge and brows, eyes with lids, lips, ears, and a short haircut
  grown from the head's own faces above a hairline.
- **Three edge loops** for muscle: biceps, forearm, calf. Only the new ring
  is pushed out.
- **Socks**: cuts round each shin for a sock top at mid-calf and a band
  (material only).
- **Normals**: about half the original forearm and shin faces pointed in,
  so with back faces culled (Blender's renders and the game) those limbs
  drew as two strips with a hole. Recalculated on the Body only (the
  shorts' zero-area faces mislead the recalculation, and the cloth was
  already right).
- **Skin weights**, rewritten from the bones. The automatic weights had the
  whole forearm on the hand bone, and the shirt and shorts didn't follow
  the body under them. Skin and cloth now take the same function (torso by
  height, arm and leg along their chains with a short blend at each joint),
  so they bend together.
- **Idle**: arms hanging straight down (~16 degrees of elbow), hips 3.3 cm
  higher than the old idle so the knees open from 30 to ~6 degrees. The old
  idle is kept as `idle_base`; the clip scripts build from it.
- **Export**: the parts join into one mesh with the kit shader (`Kit_Mat`,
  slots from the material names), so Build 6 gets the sash, the number, the
  red sock band (the kit's accent), team colours and per-player hair, in one
  draw.

## Deformation check, before and after

`check_6thbuild_deform.py` on the original rig and on the rework:

- Skin through the shorts: the original poked 11-28 mm in `knocked_back`,
  `smother_dive`, `tackle_sling`, `tackle_takedown` and `tackled`. None now.
- Shirt through the shorts (up to 22 mm in the original's ragdoll poses):
  none now.
- Left: 1-2 vertices of skin 7-10 mm out of the shirt's shoulder cap in
  `tackle_grab`, `tackle_held`, `tackle_takedown` and `tackled`, and hidden
  crossings inside folds (sock in boot, thigh in shorts) in the deep falls.
- The shirt's shoulder cap folds out a little behind the shoulder in the
  arms-down idle (a stiff cap over a turning arm).

## Budget

3,360 triangles mirrored (the original: about 2,300, most of them in the
old hands), one surface.
