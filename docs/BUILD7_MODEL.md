# Build 7 player model

2026-11-08. Build 7 (`7thbuild`) is a visual upgrade of Build 6 (`6thbuild`).
It keeps Build 6's skeleton and clips as they are and replaces the skin. The
skeleton, every clip and every gameplay anchor are Build 6's, so it plays
exactly the same. Build 6 is untouched and still selectable. Build 7 isn't
the default.

The same day it had a polish pass (branch `build7-polish`): a new body,
one mesh with one material, per-player numbers and hair, and a deformation
check that covers the ragdoll's joint limits. "Build 7 before" below means
the first version (commit 467e256).

## Where things are

| What | Path |
|---|---|
| Blender source | `assets/blender/7thbuild.blend`: a byte copy of `6thbuild.blend` whose meshes are generated |
| Mesh generator | `tools/blender/build_7thbuild_mesh.py` (the source of truth for the mesh) |
| Exporter | `tools/blender/export_7thbuild.py`: `export_6thbuild.py` plus a join of the five parts |
| Deformation check | `tools/blender/check_7thbuild_deform.py`: every clip, plus ragdoll-limit poses |
| Review sheets from Blender | `tools/blender/render_7thbuild_review.py`: turnaround, poses, close-ups, wireframe |
| Kit shader | `assets/shaders/player_kit.gdshader` |
| Runtime asset | `assets/characters/7thbuild.glb` |
| Godot entry | `HumanoidRig.CHARACTER_MODELS["7thbuild"]` |
| In-game side-by-side | `scenes/dev/build_compare.tscn` (run windowed; takes `--models=`, `--shots=`) |
| Render cost | `scenes/dev/model_cost.tscn` (run windowed; a grid of N bodies, or a real match) |
| Review images | `docs/review/7thbuild/polish/` (this pass), `docs/review/7thbuild/` (Build 7 before); `.gdignore`d |

Build 6 still lives at `F:\dev\learning-&-development\New Folder\6thbuild.blend`
(outside the repo) and `assets/characters/6thbuild.glb`. Neither was written to.

## Rebuild, check, export, review

```powershell
& "F:\blender\blender.exe" assets/blender/7thbuild.blend --background --python tools/blender/build_7thbuild_mesh.py -- --save
& "F:\blender\blender.exe" assets/blender/7thbuild.blend --background --python tools/blender/check_7thbuild_deform.py
& "F:\blender\blender.exe" assets/blender/7thbuild.blend --background --python tools/blender/export_7thbuild.py
& "D:\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" --headless --path . --import
```

Each step takes seconds. To iterate on the generator without saving, chain
it in front of the checker or the review sheet in one Blender run:
`--python tools/blender/build_7thbuild_mesh.py --python tools/blender/render_7thbuild_review.py -- out.png --close --wire`.
`check_7thbuild_deform.py -- --only=tackled,rd_fetal` checks a few poses.

In Godot, `build_compare.tscn` renders the in-game look (match lighting, the
kit shader, the game's chase and full-side cameras). For a before/after,
copy an old `.glb` anywhere under `res://` and pass its path as a model:
`-- --models=6thbuild,res://tmp/7thbuild_before.glb,7thbuild`.

The generator replaces the meshes on every run, so tune its tables rather
than hand-editing the result. Don't commit `7thbuild.blend1`. The active
action in the .blend is `tackled` with NLA on, as 6thbuild left it; the
export reads the actions, not the viewport pose.

## What it looks like

- **Proportions.** An athlete's V: the guernsey is 0.49 m across its
  shoulder yoke (the deltoids sit outside that) and 0.32 m at the waist,
  over 0.46 m shorts (Blender units on the 2.15 m rig; Build 7 before had
  0.43 m of guernsey over 0.49 m of shorts). The guernsey runs out to a shoulder yoke with a
  trapezius slope up to the collar, and each yoke end tucks under its
  deltoid. Height and skeleton are unchanged; the bulk is mesh only.
- **Kit.** A sleeveless guernsey with a crew collar in the trim colour and
  the player's number on the back. Fitted AFL shorts with the waistband on
  the hips, so the guernsey is the biggest colour block at any distance.
  Socks to just below the knee, low-cut boots with a sole a shade off the
  boot colour.
- **Body.** Quads (the outer sweep and the teardrop over the knee),
  hamstrings, a kneecap, calves with the inner head lower. Deltoid,
  biceps and triceps, a forearm bulge below the elbow. A thick neck.
- **Head.** A V jaw, cheekbones, a brow ridge, a wedge nose, almond eyes in
  the brow's shade, a mouth line, ears. Short back and sides with the
  volume on top and a lift at the front.
- **Hands.** A palm, four chunky fingers that touch, and a thumb, in a
  half-curl. Rigid on the hand bone (there are no finger bones).
- **Shading.** Flat. The profiles run in straight tapers between a few
  kinks, so the facets are big planes, and the joints' support rings sit
  on straight runs where they can, so they don't show as bands.
- **Budget.** 4,154 triangles in one surface, against Build 7 before's 3,502
  in ten and Build 6's 4,666 in six (four materials plus two sock capsules).

## One mesh, one material, per-player kit

The five generated parts (`B7_Body`, `B7_Hair`, `B7_Guernsey`, `B7_Shorts`,
`B7_Boots`) share one material, `Kit_Mat`, and `export_7thbuild.py` joins
them, so a player is one skinned mesh with one surface. Each face carries a
kit slot as the integer part of its second UV (Godot's `UV2`):

| Slot | Colour |
|---|---|
| 0 skin | `kit_skin` (the model's own tone unless the kit sets one) |
| 1 jersey, 2 number | `kit_jersey`; the number faces draw the digits in `kit_trim` |
| 3 trim (collar) | `kit_trim`: dark on a jersey brighter than luminance 0.55, else off-white |
| 4 shorts, 5 socks, 6 boot | the kit's |
| 7 sole | the boot colour darkened |
| 8 studs, 10 eyes | fixed |
| 9 hair | `kit_hair` |
| 11 mouth | the skin darkened |

The numbers are a contract between `SLOTS` in the generator and the
shader's `SLOT_*` constants: change both or neither.

`HumanoidRig._apply_kit_shader` puts one shared `ShaderMaterial` on every
Build 7 and sets each player's colours as instance shader parameters. Two
kits and 36 numbers cost no extra materials. Build 6, fifthbuild and the
procedural rig don't have a "Kit" material and are recoloured as before.

- **Number.** `HumanoidRig.guernsey_number`: the Career roster's number,
  else the team slot (1-18) in a Full Game; 0 shows 17, the number
  every Build 7 before wore (character previews, practice). The back
  faces carry a planar projection of the number box (`NUMBER_CENTRE`/
  `NUMBER_SIZE` in the generator, `NUMBER_BOX_ASPECT` in the shader) and the
  shader draws chamfered block digits as a signed distance, crisp at any
  size. They fade once a stroke is under about two pixels, rather than
  shimmer. Highlights record each body's number and the replay wears it.
- **Hair.** `HumanoidRig.kit_hair`, else one of `HAIR_COLOURS` picked by
  the number.

## Topology and skin weights

Every part is a loft of rings along a bone, so each vertex's weight is
written from where it sits rather than guessed by Blender's heat diffusion:

- Every joint gets a ring on the pivot, weighted 50/50, plus a support ring
  either side.
- Cloth uses the same weight function as the skin under it (`torso_w`,
  `ankle_foot`), so they bend together. Sock and boot are weighted per
  vertex by height: a sock ring weighted by its centre slid out of the boot
  when the foot pointed.
- Ball joints overlap rather than weld: the arm, hand and neck end in domes
  rigid to their own bone, so they turn in place without a gap.
- **The thigh under the shorts is a slim cone from the hip pivot, not a
  thigh.** 6thbuild's hip joints sit far out on the hips, so the shorts in
  front of each pivot are only ~5 cm away. Anything of the thigh further
  out than that sweeps through the shorts as the hip bends, and a blended
  crease caves in toward the pivot on a deep bend. The visible thigh starts
  under the hem.
- **The shorts' lower rings are centred on the hip joints**, not on the
  spine 2.4 cm behind them, and a little squarer, for room in front of the
  hips.
- The shorts' legs split at an inseam of three vertices shared by both legs
  (front seam, crotch, back seam). With the crotch alone, each leg's inner
  side was one flat chord and the inner thigh came through it at rest.
- The shorts' leg opening is weighted by side: front 55% thigh, seat 72%. The
  front panel over each hip takes 12-34% of its thigh (a lifted knee shoves
  real shorts up), and the lower seat 22% (a trailing leg in a dive).
- The top of the guernsey and the collar are centred on the neck's line, 1.2
  cm behind the spine's, so the collar sits between the neck and the
  guernsey all the way round.

## Deformation check

`check_7thbuild_deform.py` samples every clip and twelve ragdoll poses
(each joint at `PhysicsRagdoll.BODIES`' limits from the rest pose, with leg
IK muted; the `_over` poses add the 10-45° a landing spine overshoots). A
vertex counts as poking when the line from its own bone to it crosses the
layer over it; the nearest face's normal misread vertices deep in a folded
crease. Crossings are inner faces cutting an outer face with their corners
still inside.

| | Build 7 before (same checker) | Build 7 now |
|---|---|---|
| Rest pose | clean | clean |
| Gait, marks, kick, handball | skin through the shorts in 12 of 17 clips, 4-13 mm | no pokes; 3-6 hidden crossings at the crease in some |
| Ragdoll poses within the limits | pokes in fetal, sit, splits, tuck, 7-11 mm | clean (a 9-face crossing in the wide tuck) |
| `knocked_back` | 13 verts, 30 mm; guernsey 16 mm | 6 verts, 14 mm |
| `smother_dive`, `tackled`, `tackle_takedown` | 29-36 mm (the earlier checker) | 22, 17 and 12 mm, inside the folded crotch, under the body |
| Sock and boot, fully pointed foot (`tackled`) | 26 mm | 10 mm |

The deepest frames were rendered from four sides (`compare_dive`,
`compare_sit`); nothing shows. The remaining numbers are hidden geometry
inside the fold.

## Cost (GTX 1660 SUPER, 1600x900, v-sync off, `model_cost.tscn`)

| | Build 6 | Build 7 before | Build 7 now |
|---|---|---|---|
| 72 bodies: frame | 4.40 ms | 6.18 ms | 3.99 ms |
| 72 bodies: render CPU | 1.56 ms | 2.74 ms | 0.42 ms |
| 72 bodies: draws | 1,975 | 3,306 | 340 |
| 72 bodies: GPU | 3.68 ms | 3.79 ms | 3.59 ms |
| Quick-play match, 20 s: frame | 7.62 ms | 7.92 ms | 7.24-7.50 ms (two runs) |
| Quick-play match: render CPU / draws | 1.19 ms / 990 | 1.48 ms / 1,233 | 0.89 ms / 728 |

A match frame is mostly game CPU (AI, physics, animation); the model's
share is the render CPU and draws.

## Skeleton, animation and ragdoll compatibility

Build 7's skeleton is Build 6's armature, unchanged: the same 18 bones,
parents, rests and inverse bind matrices, and the same 26 clips key for key.
The ragdoll reads only the skeleton. `scenes/dev/tackle_sweep.tscn`, run on
a temporary copy with `MODEL_ID = "7thbuild"`, prints byte-identical output
to the 6thbuild run and to the 2026-10-30 baseline (SUMMARY: c spin 82,
hip_back 60, joint +38; t spin 47, hip_back 54, joint +42).

## Replacing the mesh later (LiDAR or a scan)

Keep the Armature and swap the meshes:

1. Import the scan into `7thbuild.blend` (or a copy, as a new build id) in
   the rest pose: an A-pose with arms about 53° off the sides, knees bent
   12° and elbows 27°. Match its scale to the bones, not the other way round.
2. Parent it to `Armature` with an Armature modifier and vertex groups
   named after the Blender bones. Weight only to deform bones.
3. Colours, either way: materials named `Skin`, `Shirt`, `Short`, `Sock`,
   `Boot`, `Trim` (the older recolour by name), or one `Kit` material and a
   second UV map whose U is each face's slot + 0.5 (the kit shader, one
   draw). Keep team colours out of textures.
4. Add the objects to `SOURCE_MESHES` and the checker's `MESHES`/`PAIRS`,
   run the checker, export, and run `build_compare.tscn`.

Limits a scan lives with: 18 bones (no fingers, toes, neck or twist bones);
the ragdoll's body sizes (a much wider body sinks into the turf when down);
the gameplay anchors (`CatchPoint`, `BootPoint`); boot soles about 0.08 m
below the ankle bone; and cloth needs its own weights matched to the skin
under it, as above.

## What a new armature (4D) should fix

Build 7 works round these; a rebuilt skeleton could remove them:

- **Hip joints set in.** They sit ~0.29 m apart on a 2.15 m figure, out at
  the sides of the hips. That forces the slim hidden cone, a slight flare
  at the shorts' hem, and very little room in front of each hip.
- **A neck bone.** The `head` bone pivots at the base of the neck, so the
  collar has to take a share of the head's turn.
- **Twist bones** in the upper arm and forearm (the forearm's twist is skin
  only), **finger and toe bones** (hands and boots are rigid), and more
  clavicle range (a mark's arms go 115-152° up on a clavicle that turns
  22°).
- **Identity rests** (HumanoidRig's contract point 2), so procedural poses and
  imported clips share frames.
- Ragdoll bodies would need refitting to any new bones, and every gameplay
  anchor re-checked.

## Needs your eyes

- **The look at match distance and close up**, in your own matches:
  proportions, the face, the hair (the weakest part up close), the hands.
- **Numbers**: the digit style, size and placement, and the dark/light
  flip (luminance 0.55, an unplaytested guess).
- **Hair colours** per player (`HAIR_COLOURS`, an unplaytested pick).
- **The sprint, dives and falls**: no skin at the shorts' crease should
  show anywhere now.
- The character screens show 17 (no number is passed to a preview yet).
