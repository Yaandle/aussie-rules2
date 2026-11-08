# Build 7 player model

2026-11-08. Build 7 (`7thbuild`) is a visual upgrade of Build 6 (`6thbuild`).
It keeps Build 6's skeleton and clips as they are and replaces the skin. The
skeleton, every clip and every gameplay anchor are Build 6's, so it plays
exactly the same. Build 6 is untouched and still selectable. Build 7 isn't
the default.

## Where things are

| What | Path |
|---|---|
| Blender source | `assets/blender/7thbuild.blend`: started as a byte copy of `6thbuild.blend`, then its four Build 6 meshes were swapped for five generated ones |
| Mesh generator | `tools/blender/build_7thbuild_mesh.py` |
| Exporter | `tools/blender/export_7thbuild.py`: `export_6thbuild.py` with only the meshes and the output path changed |
| Deformation check | `tools/blender/check_7thbuild_deform.py` |
| Runtime asset | `assets/characters/7thbuild.glb` |
| Godot entry | `HumanoidRig.CHARACTER_MODELS["7thbuild"]` |
| Side-by-side capture | `scenes/dev/build_compare.tscn` (run windowed) |
| Review images | `docs/review/7thbuild/` (`.gdignore`d) |

Build 6 still lives at `F:\dev\learning-&-development\New Folder\6thbuild.blend`
(outside the repo) and `assets/characters/6thbuild.glb`. Neither was written to.

## Rebuild and export

```powershell
& "F:\blender\blender.exe" assets/blender/7thbuild.blend --background --python tools/blender/build_7thbuild_mesh.py -- --save
& "F:\blender\blender.exe" assets/blender/7thbuild.blend --background --python tools/blender/check_7thbuild_deform.py
& "F:\blender\blender.exe" assets/blender/7thbuild.blend --background --python tools/blender/export_7thbuild.py
& "D:\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe" --headless --path . --import
```

Each script also runs from Blender's Scripting tab or the Blender MCP. The
generator is the source of truth for the mesh: tune its tables and re-run
rather than hand-editing the result. Hand edits are fine, but a re-run
replaces them, so pick one way of working and say which in the commit.
Don't commit `assets/blender/7thbuild.blend1`.

The active action in the .blend is `tackled` with NLA on, as 6thbuild left
it. The export reads the actions, not the viewport pose, but leave
`Armature.data.pose_position` on `POSE`.

## What changed visually

- **Proportions.** The guernsey widens from a 0.158 m half-width at the
  waist to 0.216 m across the chest. That gives a V-taper, pec and lat
  bulges, and deltoids that cap out over a sleeveless guernsey. The thighs
  run to 0.10 m and the calves to 0.078 m. The head is a little larger, at
  about 0.24 m from chin to crown. Height and skeleton are unchanged; the
  bulk comes from the mesh only (approved decision).
- **Face.** A faceted head with a square jaw, cheekbones, a brow ridge, a
  wedge nose, ears, dark eye slits, hair-coloured brows, and a hair shell
  with a hairline and nape.
- **Kit.** Sleeveless guernsey with a crew collar (shallow V) and a "17" on
  the back. AFL shorts with a waistband and folded hems. Socks to just below
  the knee with a top band. Low-cut boots with a contrasting sole and six
  studs.
- **Hands.** A palm, four two-segment fingers and a thumb, in a relaxed
  half-curl. There are no finger bones, so they're rigid on the hand bone.
- **Budget.** 3,502 triangles against Build 6's 4,666 (about 3,400 of those
  are in Build 6's hands). It has 10 material surfaces against Build 6's 4
  plus two sock capsules, so more draw calls per player (see "Needs your
  eyes").

## Topology and skin weights

Every part is a loft of rings along a bone, so each vertex's weight is
written from where it sits rather than guessed by Blender's heat diffusion
(which failed on Build 6's Body):

- Every joint gets a ring on the pivot, weighted 50/50, plus a support ring
  either side. Long segments get two or three rings.
- **Cloth uses the same weight function as the skin under it** (`torso_w`,
  `ankle_foot`), so they bend together.
- **Ball joints overlap rather than weld.** The arm into the guernsey, the
  thigh into the shorts, the hand into the forearm and the neck into the
  head each end in a dome round the joint's pivot. The dome is rigid to its
  own bone, so it turns in place without opening a gap.
- **Hidden skin under the shorts is slimmer than it looks** and close to a
  sphere round the hip pivot. The shorts' centre seam can't follow either
  thigh, so a full-size thigh came through it on a stride.
- **The shorts' leg opening is weighted by side**: front 55% thigh, seat 72%,
  and the front panel over each hip takes 10-30% of its thigh. A lifted knee
  shoves the shorts up, as real ones do.

## Skeleton and animation compatibility

Build 7's skeleton is Build 6's armature, unchanged. These were checked in
Godot and on the raw glTF:

- **Bones.** The same 18, with the same parents and rests: `Hips`, `Spine`,
  `Chest`, `head`, `Left/RightShoulder`, `-UpperArm`, `-LowerArm`, `-Hand`,
  `-UpperLeg`, `-LowerLeg`, `-Foot`. There's no Neck, Toes, finger or twist
  bone, and `head` is lowercase.
- **Clips.** The same 26, key for key: 1,404 channels, 0 differences in the
  raw glTF and 0 mismatched keys after import.
- **Inverse bind matrices.** Identical (max difference 0.0).

The Blender-side names (`pelvis`, `spine1`, `upperarm.l`, ...) and the IK
helpers (`iktarget.*`, `ikpole.*`) are as in `export_6thbuild.py`'s
`BONE_RENAME`. The helpers never reach Godot.

## Kit colours

`HumanoidRig` recolours by material name, as it does for Build 6:

| Material | Kit slot |
|---|---|
| `Shirt_Mat` | jersey |
| `Shorts_Mat` | shorts |
| `Socks_Mat` | socks |
| `Boots_Mat` | boot |
| `Skin_Mat` | skin (only when a skin colour is set) |
| `Trim_Mat`, `Number_Mat` | new `trim` slot: dark on a jersey brighter than luminance 0.55, else off-white |
| `Hair_Mat`, `Eyes_Mat`, `Studs_Mat` | keep their authored colours |

Two additions to `humanoid_rig.gd` support this. Neither changes anything
for Build 6, fifthbuild or the procedural rig:

- the `trim` / `number` slots, and
- an import with its own `Sock` material doesn't get the stand-in sock
  capsules.

These were checked on your CHARACTER kit (dark), the AWAY preset and a
white/navy custom kit (`build6_vs_build7_kits.png`).

## Ragdoll alignment

The ragdoll reads only the skeleton (`PhysicsRagdoll.BODIES` sizes on the
bone rests), so nothing on the physics side changed:

- `scenes/dev/tackle_sweep.tscn` prints byte-identical output for Build 6
  and Build 7, run with a temporary copy whose only change was
  `MODEL_ID = "7thbuild"`. The SUMMARY matches the 2026-10-30 baseline: c
  spin 82, hip_back 60, joint +38; t spin 47, hip_back 54, joint +42.
- `build6_vs_build7_rest_shapes.png` draws the bodies over both skins. Build
  7's guernsey, head, arms and legs sit on their bodies about as closely as
  Build 6's do.
- The mesh is a little fuller than some bodies: thighs up to 1.5 cm over
  the 0.085 m capsule, and the chest about 2 cm wider than its box. A body
  lying on its side or front sinks that far into the turf visually. That
  only affects how it looks.

## Deformation check results

`check_7thbuild_deform.py` runs every frame of every clip. Most of what
remains is hidden geometry:

| | What's left |
|---|---|
| Idle, carry, handball, smothered, `mark_safe`, `tackle_held` | Clean, or 2-4 hidden crossings |
| Gait, marks, kick | 1-3 vertices, 5-13 mm. One frame of jog/run (high knee) is 28-34 mm at the shorts' front crease; a sliver is visible from a low side angle (below) |
| `knocked_back`, `smother_dive`, `tackle_takedown`, `tackled` | 30-50 mm at the crotch and seat in deep sits and dives, under the body; plus up to 26-35 mm of sock at the boot collar when the foot points fully (`tackled` points it to 5° off the shin) |

`tackled`, `knocked_back` and the takedown play in contests that don't go
to the ragdoll, which in practice means mostly AI against AI. When a human
is in the contest, the body ragdolls instead.

## Replacing the mesh later (LiDAR or a scan)

Keep the Armature and swap the meshes:

1. Import the scanned body into `7thbuild.blend` (or a copy, as a new build
   id) in the rest pose: an A-pose with arms about 53° off the sides, knees
   bent 12° and elbows 27°. Match its scale to the bones, not the other way
   round. Moving a bone changes the ragdoll and gameplay anchors.
2. Parent it to `Armature` with an Armature modifier and vertex groups
   named after the Blender bones (`pelvis`, `spine1`, `spine2`, `head`,
   `shoulder.l`, ...). Weight only to deform bones, never to `pelvis.001` or
   the IK helpers.
3. Split it by material name (`Skin`, `Shirt`, `Short`, `Sock`, `Boot`,
   `Trim`, `Number`) so kit colours keep working. Keep team colours out of
   textures; a texture would need a mask per slot.
4. Add the object names to `SOURCE_MESHES` and to the checker's `MESHES` /
   `PAIRS`, run the checker, then export and run
   `scenes/dev/build_compare.tscn`.

Limits a scan has to live with:

- **18 bones.** No fingers, toes, neck or twist bones, so hands and feet
  stay rigid and forearm twist is skin-only.
- **Proportions.** A body much wider than the ragdoll bodies will sink into
  the turf when down. A much longer limb will miss the gameplay anchors
  (`CatchPoint` at 1.4 m, `BootPoint` on the instep).
- **Boot soles** sit about 0.08 m below the ankle bone (the foot clamp
  allows for 0.07).
- **Clothing** needs its own weights matched to the skin under it, as
  above. A scan with cloth fused to skin will deform as skin.

## Needs your eyes

- **Art direction, proportions and face** across the review images. Things
  to judge:
  - the hair colour (fixed brown for every player)
  - the eye slits
  - the "17" on every player
  - whether the guernsey should have short cap sleeves (sleeveless now)
- **In-game at broadcast distance**: whether the detail reads, and whether
  the dark trim/number on light kits is the right call (luminance split
  0.55, an unplaytested guess).
- **GPU cost** of 10 surfaces per player × 36 players. Headless frame rate
  was the same, but headless doesn't render. Merging `Studs`/`Eyes`/`Hair`
  into fewer surfaces would cut the count if it shows.
- **The sprint's knee lift** and the deep falls in the table above.
- **Ragdoll falls look right**, but the rest pose is the only like-for-like
  comparison, because two ragdolls side by side fall a little differently.
