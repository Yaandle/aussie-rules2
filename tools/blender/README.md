# Blender ↔ Godot sync for fifthbuild / 6thbuild

Source files:
- `F:\dev\learning-&-development\New Folder\fifthbuild.blend` ->
  `assets/characters/fifthbuild.glb`
- `F:\dev\learning-&-development\New Folder\6thbuild.blend` ->
  `assets/characters/6thbuild.glb` — a second body design built around a
  direct copy of fifthbuild's own Armature (same bone names/hierarchy), so
  it drops into the same Godot pipeline. See `export_6thbuild.py`'s own
  header for the one real difference from fifthbuild's export: no
  animations yet (6thbuild has no actions/NLA stashed), and two of its
  four meshes (Body, Shirt) didn't pick up automatic-weight skinning —
  likely because Body is one coarse box spanning the whole figure and
  fully overlapping the other three, which confuses Blender's heat-
  diffusion solver. They still render in their aligned rest pose; they
  just won't deform if/when the rig is animated, until re-weighted
  (Shorts and Shoes skinned fine the same way).

## Edit a pose / animation in Blender

1. Open `fifthbuild.blend`.
2. In the **Action Editor**, use the action-browser dropdown (left end of its
   header) to pick an existing clip (`idle`, `jog_fwd`, ...) or create a new
   one. Pick a clip, scrub the timeline or hit spacebar to preview it live on
   the rig.
3. Pose/keyframe as normal. When you switch actions, Blender stashes
   whichever one was active into the NLA — that's expected, both scripts
   below read the NLA stash either way.
4. Save the file (**Ctrl+S**).

## Sync to Godot

1. In Blender's **Scripting** tab: `Open` →
   `tools/blender/export_fifthbuild.py` → **Run Script** (▶).
   This writes `assets/characters/fifthbuild.glb` with every stashed action
   whose name is in the script's `CLIP_RENAME` dict (name a new action
   directly after its target clip — `run_fwd`, `kick`, etc. — and you don't
   need to touch that dict at all).
2. Reimport in Godot — pick **one**:
   - Headless (fastest, no UI): run this, then launch the game normally.
     ```powershell
     & "D:\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe" --headless --path "F:\dev\aussie-rules2" --import
     ```
   - Or just open the project in the normal Godot editor once — it reimports
     changed files automatically on scan.

   Running the compiled scene directly (`godot --path . scene.tscn`, no
   `--editor`) never reimports on its own — step 2 is required every time,
   not optional.
3. Check it: open `scenes/dev/animation_viewer.tscn` (F6, or run it) and hit
   **REBUILD**, or just run the game.

6thbuild follows the exact same two steps with `export_6thbuild.py` instead
(its `CLIP_RENAME` lists every clip it ships; `SOURCE_MESHES` is `Body`,
`Shirt`, `Shorts`, `Shoes`). Once exported and reimported, it's already
selectable in-game: `HumanoidRig.CHARACTER_MODELS` has a `"6thbuild"` entry,
and the CHARACTER screen's MODEL row reads that dict directly, so no UI
code needs touching for a new entry there — just the export + an entry in
`CHARACTER_MODELS` pointing at the new `.glb`.

## Generating a gait clip from the procedural math (optional shortcut)

`tools/blender/generate_gait_clip.py` ports `humanoid_animations.gd`'s own
`_gait_pose()` formula into Blender keyframes on the rig's native bone names
— a generated starting point for a new locomotion clip, not hand-authored
art. Edit `TARGET_CLIP` at the top (`"jog_fwd"`, `"run_fwd"`, `"run_back"`
are already in its `GAITS` dict) and run it from the Scripting tab the same
way, then continue with the Sync steps above.

## Authoring 6thbuild's action clips (`author_6thbuild_clips.py`)

6thbuild's bone rests aren't identity, so the procedural fallbacks in
`humanoid_animations.gd` twist it apart: they write absolute local rotations
meant for the procedural rig, and every mark clip put both feet above the
head. `tools/blender/author_6thbuild_clips.py` builds those clips as real
actions on the .blend instead. It keeps the procedural clips' timing and
intent but poses the rig relative to its rests:

- Torso, head and clavicle rotations are written in the character's own
  frame (`basis = G^-1 R G`).
- Arms are placed by two-bone IK to wrist targets.
- Feet go through the rig's own `iktarget`/`ikpole` leg IK.

Each clip's length and contact time come from `ACTION_TIMING`, a copy of
Tuning's `ACTION_DURATION`/`ACTION_CONTACT`. Lengths round to whole 24 fps
frames.

Back the .blend up first (it isn't version-controlled), then run:

```powershell
& "F:\blender\blender.exe" "F:\dev\learning-&-development\New Folder\6thbuild.blend" --background --python tools/blender/author_6thbuild_clips.py -- mark_safe mark_running
& "F:\blender\blender.exe" "F:\dev\learning-&-development\New Folder\6thbuild.blend" --background --python tools/blender/export_6thbuild.py
```

With no clip names, the script builds every clip it defines. Re-running
replaces an action (and its NLA stash track) rather than duplicating it.
Then reimport in Godot as above. The authored actions are ordinary
keyframed actions, so you can refine them by hand in the Action Editor, but
a re-run of the script overwrites hand edits to any clip it's asked to
build.

## Bone names

`export_fifthbuild.py`'s `BONE_RENAME` dict maps this rig's own bone names
(`pelvis`, `upperleg.l`, ...) to the names `scripts/player/humanoid_rig.gd`'s
`HumanoidRig.BONES` expects (`Hips`, `LeftUpperLeg`, ...) — only on the
export-time duplicate, never on the actual working rig. If you add a new
bone to the rig, it needs an entry here before it'll do anything in Godot.
