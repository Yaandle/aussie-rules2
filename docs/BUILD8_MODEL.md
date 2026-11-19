# Build 8 player model

2026-11-20 (Day 7). Build 8 (`8thbuild`) is Build 7 restyled toward the
reference image `docs/review/8thbuild/reference.webp`: a black guernsey
with a red diagonal sash, black shorts, black socks with a red band, and a
strong, athletic player. It keeps Build 6's skeleton and every clip
(Build 7's gaits and arms-down idle included), so it plays exactly as
Builds 6 and 7. Builds 6 and 7 are untouched and still selectable. Build 8
isn't the default.

Everything in `BUILD7_MODEL.md` (topology, weights, the kit-slot contract,
the number, the limits a scan lives with) holds for Build 8. This file only
covers what changed.

## Where things are

| What | Path |
|---|---|
| Blender source | `assets/blender/8thbuild.blend`: a byte copy of `7thbuild.blend`, meshes regenerated (`B8_*`) |
| Mesh generator | `tools/blender/build_8thbuild_mesh.py` (Build 7's, retuned; each change is marked "Build 8") |
| Exporter, checker, review sheets | `export_8thbuild.py`, `check_8thbuild_deform.py`, `render_8thbuild_review.py` in `tools/blender/` |
| Runtime asset | `assets/characters/8thbuild.glb` |
| Godot entry | `HumanoidRig.CHARACTER_MODELS["8thbuild"]` |
| Review images | `docs/review/8thbuild/` (`.gdignore`d): Blender sheets in the reference kit, `cmp_*` Build 7 vs 8 in Godot |

```powershell
& "F:\blender\blender.exe" assets/blender/8thbuild.blend --background --python tools/blender/build_8thbuild_mesh.py -- --save
& "F:\blender\blender.exe" assets/blender/8thbuild.blend --background --python tools/blender/check_8thbuild_deform.py
& "F:\blender\blender.exe" assets/blender/8thbuild.blend --background --python tools/blender/export_8thbuild.py
& "D:\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" --headless --path . --import
```

Before/after in Godot (windowed): `build_compare.tscn -- --models=7thbuild,8thbuild --captions="BUILD 7,BUILD 8" --out=res://docs/review/8thbuild/ --prefix=cmp`.
The review script's output path must be absolute (a relative one lands
somewhere other than the repo).

## What changed from Build 7

- **Legs.** Fuller quads (the outer sweep and the teardrop over the knee,
  ~8% more) and calves (~6%). The thigh ring that's now under the longer
  shorts stays Build 7's size. 14 segments round (12).
- **Shorts.** Longer and looser, to about mid-thigh: the hem is 5.6 cm
  lower (0.262 m down the thigh) and stands ~1.5 cm off the quads; the
  hips and seat are a little fuller. 20 segments round (16).
- **Guernsey.** Chest and lats ~4% wider and the shoulder cap 0.8 cm
  further out each side, for a stronger V; fuller pecs. The collar's V is
  wider and a touch deeper. It's still a shallow V: a true V-neck needs the
  guernsey's top cut open and a chest under it, which this loft doesn't
  have.
- **Arms.** ~6% more through the deltoid, biceps, triceps and forearm; the
  elbow stays narrower than both. 12 segments round (10).
- **Head and hair.** A squarer jaw, fuller cheekbones, the chin a touch
  forward. The hair is fuller on top, lifts more at the front and sweeps
  a little to the right. The head stays at 14 segments: 16 put a vertex
  down the middle of the face and broke the mouth and brows.
- **Kit.** The sash and the sock bands (below).
- **Budget.** 5,062 triangles in one surface (Build 7: 4,554). Still one
  material and one draw per player.

## The sash and the accent colour

The sash isn't geometry: cut from faces it would be jagged. Each guernsey
and number vertex carries its signed distance across the sash's centre
line (a plane seen front-on, from the left shoulder to the right hip) in
the Slot UV's V, plus 2.0. `player_kit.gdshader` draws the band where that
distance is under `SASH_HALF_WIDTH` (5.8 cm), crisp at any size. Because the
plane is seen front-on, the same band carries over the left shoulder and
down the back. Build 7's V is a flat 0.5, so the shader never draws a sash
on Build 7.

glTF flips V, so the shader reads `1 - UV2.y`. Forgetting that hid the
sash completely.

The sock band is geometry: the face strip between two sock rings is a new
kit slot, 12 (`accent`), in both the generator's `SLOTS` and the shader's
`SLOT_ACCENT`.

Both take the kit's **accent** colour (`kit_accent` instance parameter).
No team has an accent of its own yet, so `HumanoidRig._resolved_kit` uses
the trim colour, which always contrasts with the jersey: a dark sash on a
light guernsey, off-white on a dark one. `HumanoidRig.kit_accent` (alpha 0
= unset) overrides it, and `kit_sash = false` gives a plain guernsey.

Over the sash the number's digits get a jersey-coloured outline
(`NUMBER_OUTLINE`), so a number that crosses the sash stays one colour. Off
the sash the outline doesn't show.

## Deformation check

Same checker as Build 7, run on both. Changes from Build 7's output:

- Every clip that was clean is still clean, except **`run_fwd_l` and
  `run_fwd_r`** (the diagonal runs): 7 hidden crossings each, body against
  shorts. Changing the thigh, the shorts' hips, the leg rings and the
  segment counts didn't move the number, so it's most likely the other
  thigh meeting the longer shorts' inner leg in a crossover step. Rendered
  from four sides (`blender_diagonal_runs.png`), it's inside the folded
  hem apart from a few-millimetre sliver at the inner hem in two frames.
- **Visible pokes** are only in the two deep falls, as in Build 7:
  `knocked_back` 9 vertices at 14 mm (Build 7: 6, 14 mm) and
  `tackle_takedown` 4 at 14 mm (3, 12 mm).
- One- or two-face crush or stretch flags on the shorts in a few ragdoll
  poses (fetal, sit, splits, arch), from the looser cloth.

The tackle sweep wasn't re-run: the skeleton, clips and ragdoll are Build
7's byte for byte, and the ragdoll reads only the skeleton.

## Needs your eyes

In `docs/PLAYTEST_CHECKLIST.md` under "Build 8 player model".
