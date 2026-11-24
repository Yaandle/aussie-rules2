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
| Reference renders | `scenes/dev/reference_match.tscn` (run windowed): the model in the reference's kit, light and framing (`ref_*`) |
| Review images | `docs/review/8thbuild/` (`.gdignore`d): `reference_vs_build8.png` side by side, `ref_*` reference-matched, `cmp_*` Build 7 vs 8 in Godot |

```powershell
& "F:\blender\blender.exe" assets/blender/8thbuild.blend --background --python tools/blender/build_8thbuild_mesh.py -- --save
& "F:\blender\blender.exe" assets/blender/8thbuild.blend --background --python tools/blender/check_8thbuild_deform.py
& "F:\blender\blender.exe" assets/blender/8thbuild.blend --background --python tools/blender/export_8thbuild.py
& "D:\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" --headless --path . --import
```

Before/after in Godot (windowed): `build_compare.tscn -- --models=7thbuild,8thbuild --captions="BUILD 7,BUILD 8" --out=res://docs/review/8thbuild/ --prefix=cmp`.
The review script's output path must be absolute (a relative one lands
somewhere other than the repo).

## Accuracy pass against the reference (same day)

Reviewed against the reference with `reference_match.tscn` (the same kit,
low warm sun and front-on framing). What differed, and what was done:

| Reference | First Build 8 | Now |
|---|---|---|
| A loose, boxy guernsey hanging over the shorts | tucked in, a narrow waist | worn out: straight from the lats to a hem over the top of the seat, clear of the shorts all round, with a folded lining |
| No contrasting trim | off-white collar and armholes | collar and armholes in the guernsey's colour (`TRIM_SLOT`) |
| A wide, steep sash | 11.6 cm, 34° off vertical | 13.6 cm, 29°, down to the lower hem |
| Socks at mid-calf, the calf bare above them | socks just under the knee | the top at mid-calf, the band 2 cm under it |
| Short back and sides, a full, swept top | a smooth helmet, long sideburns | a tight taper, short sideburns, fullness over the temples, a low quiff swept right |
| A bigger head, eye whites, a stronger nose | Build 7's face | head and hair 7% bigger, 16 segments turned half a step, whites and irises (slot 13, `eyewhite`), a longer nose |
| Broad shoulders, thick forearms, big hands | Build 7's arms +6% | deltoids and guernsey cap wider, arms `ARM_BULK` 1.14, hands `HAND_SCALE` 1.12 |

On the back the sash stops at a jersey-coloured panel round the number
(`NUMBER_PANEL_MARGIN`), so the digits read as on a plain guernsey. An
outline round the digits, the first try, made them read as hollow shapes.

**What can't match:** the reference is a stylised figure with short legs
and a big head. Limb lengths come from the skeleton, which the clips, the
ragdoll and every gameplay anchor are built on, so this pass matched shapes,
not proportions. Its skin and hair colours are per player (`kit_skin`,
`kit_hair`), and the red comes from the kit's accent (below).

## Turnaround pass (2026-11-21)

Matched to a cleaner front/side/back turnaround,
`docs/review/8thbuild/reference_turnaround.webp`. Side by side in the game's
renderer: `turnaround_vs_build8.png` (from `reference_match.tscn`'s
`ref_front`/`ref_side`/`ref_back`); in Blender, arms-down:
`render_8thbuild_review.py -- OUT.png --idle` (`blender_idle_turnaround.png`).

| Turnaround | Before | Now |
|---|---|---|
| A sleeveless guernsey, deep armholes, the whole deltoid bare | a 0.29 m cap over each deltoid; the arm came out from under it with a visible join | the strap runs down the trapezius and stops on the top of the deltoid (0.21 m out); the armhole drops straight to the armpit; the deltoid is the shoulder |
| A real V-neck | a shallow V on a crew collar | a 12 cm V with a binding, and skin (upper chest, the neck's base) under it |
| Round deltoids, a tapering upper arm, strong forearms | a capsule-like arm | the deltoid a near-sphere on the pivot, a step in to the biceps, the upper arm narrower from the front than the deltoid; `ARM_BULK` 1.20 |
| Athletic, not bulky, thighs | big quads | ~12% slimmer through the quads, a smaller teardrop |
| A boxy guernsey hanging to the top of the shorts' legs | hem at 1.168 m | hem at 1.136 m and a little fuller toward it |
| A thick neck | Build 7's | ~7% thicker at the base |

How the V works: the loft's rows above `V_FROM_Z` slide down their own
columns so the top ring *is* the V (cutting faces out left a staircase
edge). The skin under it is a shell `V_SHELL_INSET` under the guernsey,
weighted by the guernsey point over it (by its own position, a raised arm
moved them apart). Below the strap it's front-only: under the armholes a
raised arm folds the side wall and skin there read as coming through
(`check_8thbuild_deform.py -- --verbose` names the vertex).

`torso_w`'s share of the upper arm at the armhole's top is 10% (was 30%):
with no cap to round over the deltoid, 30% pulled the strap's end down off
the deltoid in the idle and left a notch.

Checks after the pass: `check_8thbuild_deform.py` prints the same as
before for every clip and ragdoll pose, except the diagonal runs' hidden
body-against-shorts crossings, down from 7 to 3 (slimmer thighs). The
animation audit's bones and rigid parts stay 0.00. New in the audit: the
skin ring where the V's shell meets the neck creases to 0.50-0.60x behind
the neck with the head thrown back (`tackled`, `rd_arch`), under the back
of the neckline; and to 0.59x at the front only in `rd_fetal_over`. The
shell under the strap is reported as hidden. Close-ups of the worst frames:
`audit_turnaround.png`; nothing breaks through.

**Still can't match:** the turnaround's figure has shorter legs, a bigger
head and arms hanging close to the body. Limb lengths are the skeleton's,
and the idle clip hangs the arms out a little; neither changed.

## Arms, shoulders and side-on pass (2026-11-25)

Playtest: the side-on view looked awkward and the elbows weren't smooth.
`blender ... render_8thbuild_review.py -- OUT.png --arms` is the sheet for
this (the idle arm from four sides, two bent elbows, the body side on).

- **Elbows.** A ring either side of the elbow's pivot ring, the ARM_BULK'd
  rings next to it stepped down (they were 1.45x the elbow's width, a
  pinch that read as a hinge), the olecranon no fuller than the sides, and
  a wider weight blend (E - 0.07 to E + 0.06). A run or handball bend now
  rounds over five rings instead of folding to a point behind.
- **Deltoid.** The cap's top over the joint is smaller, so the bulk sits on
  the side of the arm under the strap rather than standing above the
  shoulder line.
- **Side on.** The chest ~1.4 cm and upper back ~1 cm deeper, the neck
  deeper front to back, the thighs and calves deeper. The idle's wrist
  hangs half a centimetre behind the shoulder joint (it was 2.2 cm in
  front) and each hand turns 40 degrees about its own axis
  (`author_6thbuild_idle.WRIST_TWIST`), so side on the arm hangs down the
  middle of the torso with the palm toward the thigh. It used to hang at
  the chest's front edge, the palm forward and the fingers curling ahead.
- **Boots** `BOOT_FRONT_SCALE` 0.72 (~0.32 m long).

`check_8thbuild_deform.py` prints the same as after the side-by-side
pass. `author_6thbuild_idle.py` is shared with Build 6: Build 6's idle
gets the same arm and wrist the next time it's authored and exported.

## Side-by-side pass (2026-11-25)

Matched again against the turnaround, side by side in the game's renderer
(`turnaround_vs_build8.png`, from `reference_match.tscn`'s `ref_front`/
`ref_side`/`ref_back`). What changed in `build_8thbuild_mesh.py`:

| Reference | Before | Now |
|---|---|---|
| Relaxed hands with separate fingers | a palm and four chunky two-segment fingers touching (a mitten), `HAND_SCALE` 1.12 | Build 6's rework hand: a domed palm with a thenar pad, three-phalanx fingers with knuckles, a thumb along the index finger (`FINGERS`, `CURL`, `PALM`) |
| A defined face | a wedge nose, flat eye quads, a mouth line, box ears | `add_face`: nose with tip and wings, brow ridge, eyes with lids, lips, C-shaped ears |
| Arms hanging straight down, standing tall | Build 7's idle: elbows ~43 degrees, knees ~30 | `author_6thbuild_idle.py` on this file: elbows ~16, knees ~6, feet planted |
| Socks to just under the calf | sock top at mid-calf, hiding the calf | top ~55% down the shin, the calf and Achilles bare (`sock_table`, two new calf rings) |
| Heavy deltoids, thick forearms, slim wrists | a deltoid ball on a tube (the insertion pinched in), wide wrists | the cap ~7% fuller, no pinch at the insertion, `ARM_BULK` 1.30, wrists ~10% slimmer |
| Big quads and calves | | quads below the hem ~10% fuller, calves ~10% fuller behind |
| Football boots, high collar | 0.41 m boots (flippers side on) | `BOOT_FRONT_SCALE` 0.80 (~0.34 m), the collar 1 cm higher, a thicker sole |
| A bigger head, a thick textured crop | `HEAD_SCALE` 1.07, a thin cap | 1.10, ~12 mm more on top, strands all over the top |

`reference_match.tscn`'s skin is a deeper tan (`#a8714c`); it still renders
paler than the reference under that scene's sun.

Checks: `check_8thbuild_deform.py` prints the same as the committed Build 8
for every clip and ragdoll pose except: the diagonal runs' hidden
body-in-shorts crossings 3 -> 6; one sock vertex 7 mm through the boot in
`smother_dive` frame 11; one crushed boot face in `kick`; boot crossings in
`tackled` 5 -> 6.

**Still not the reference:** limb lengths and the shorter legs (the
skeleton); the arms read blockier than the reference's (12 segments, flat
shading); the deltoid still sits a little outside the guernsey's edge; the
reference's skin and shading come from its renderer, not the mesh.

## What changed from Build 7 (first pass)

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
- **Budget.** 5,258 triangles in one surface after the accuracy pass
  (Build 7: 4,554); 5,530 after the turnaround pass (the V's shell and
  binding). Still one material and one draw per player.

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

On the back the sash stops at a panel round the number (see the accuracy
pass above).

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
  poses (fetal, sit, splits, arch), from the looser cloth, and 4 crushed
  faces on the guernsey's hem in `rd_fetal_over`.
- The loose guernsey over the shorts (the checker's pair is now shorts
  inside guernsey, 1.15-1.30 m) is clean in every clip and pose.

The tackle sweep wasn't re-run: the skeleton, clips and ragdoll are Build
7's byte for byte, and the ragdoll reads only the skeleton.

## Animation audit (2026-11-20)

`tools/blender/audit_8thbuild_anim.py` samples every clip (every 2nd frame)
and the twelve ragdoll poses, and measures what the layer checker can't:

- **bones**: each deform bone's length and scale against rest. **0.00 in
  every frame of every clip**: no clip stretches the skeleton.
- **strain**: each edge's length against rest, by body region (the bone,
  or the pair of bones, its vertices are weighted to). Flags past 1.35x or
  under 0.70x. Geometry covered by another layer (the thigh cone under the
  shorts, the sock inside the boot, the neck's base, the shorts' waist
  under the guernsey) is reported as "hidden" and not flagged.
- **volume**: each skin vertex's distance from its own bones against rest
  (pinched elbows, collapsed twists). Flags under 0.70 or over 1.35.
- **rigid**: the head, hair, hands and the body of each boot. **All 0.00**:
  they keep their shape exactly.

The flagged frames were rendered close up (`render_8thbuild_review.py
--audit`, framed on a bone; `audit_before.png`, `audit_after.png`,
`audit_zoom_*.png`):

| Where | Numbers | Verdict |
|---|---|---|
| **Boots at a pointed foot** (kick, tackled, takedown, dive) | the upper squashed to 11% in front of the ankle, 1.9x behind | **Fixed.** The boot bent like a sock. `ankle_foot` now starts the foot-to-shin blend at 0.11 m (0.085), so the boot is rigid on the foot up to its collar and the sock bends above it: 37% / 1.6x, at the collar's top edge only. No sock through the boot (the dive's 5 mm poke is gone); hidden sock-in-boot crossings rose from 9 to 12 (dive) and 0 to 5 (tackled). |
| Elbows in the runs | inner crease to 0.14 of its rest distance from the bones, 0.45x strain; outside 1.7-2.0x in marks and hit-outs | Looks right: a ~110° bend in a low-poly arm with no extra bones. The crease folds, it doesn't kink. |
| Knees in deep bends (bounce, mark_running, dives, falls) | back of the knee to 0.04-0.11, front 1.9x | Looks right: the calf meets the hamstring. The kneecap's ring stretches over the bend. |
| Wrists in `tackled` | one vertex to 0.06 | Not visible: inside the fist's join. |
| Shorts' crotch in strides | 3-4x on the short inseam edges | Hidden between the legs. |
| Shorts' front and seat in deep hip bends | front 0.11-0.2x, seat 2-3x | Cloth: the front folds, the seat pulls. Visible only in falls. |
| Guernsey over the shoulders in a mark | 0.41-0.48x | Bunches as the arms go up, as cloth does. |
| Guernsey's belly in the ragdoll curls | 0.22-0.28x, 0.01x in `rd_fetal_over` | Folds; the `_over` poses are stress tests past any clip. |
| Neck in `tackled` (head tipped back) | 0.51x behind the neck | The skin creases behind the head; nothing breaks through. |

Also seen: in `smother_dive` the loose guernsey's hem shows edge-on as a
thin line across the seat as the back arches (the shorts don't come
through it; the checker covers that pair).

Re-run after any change to the generator:
`blender assets/blender/8thbuild.blend --background --python tools/blender/audit_8thbuild_anim.py -- --frames`.

## Needs your eyes

In `docs/PLAYTEST_CHECKLIST.md` under "Build 8 player model".
