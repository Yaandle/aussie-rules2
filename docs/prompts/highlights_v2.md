# Highlights v2: tackle and mark toggles, a third-person camera, generated footage

You're working in `F:\dev\aussie-rules2` (Godot 4.6).
- Read `CLAUDE.md` first, then `docs/LESSONS.md`.
- Then read the highlights code:
  - `scripts/autoload/highlights.gd`
  - `scripts/highlights/highlight_recorder.gd`
  - `scripts/highlights/highlight_table.gd`
  - `scripts/highlights/highlight_exporter.gd`
  - `scripts/highlights/replay_stage.gd`
  - `scripts/highlights/replay_clip.gd`
  - `scripts/ui/highlights_screen.gd`
  - `scripts/ui/highlight_export_dialog.gd`
- Work on branch `update`. Never push. Commit only your own files.

**Leave these alone:** `scripts/dev/highlight_stills.gd` and `scenes/dev/highlight_stills.tscn`. They're another session's uncommitted tool for cover stills. They use `ReplayStage` (and its `DirectionalLight3D` child), `ReplayClip.load_file()` and `ReplayClip.decode()`, so keep those working.

## Why

The user makes a daily video series from these exports: "making an AFL game every day until the AI can beat me". A separate pipeline (`F:\dev\video-editor\video-editor`, `studio/daily`) reads:
- `moments.json`
- the `NN_<type>_16x9.avi` clips
- the `.replay` files

The last two exports held only goals and marks. But the AI side lays plenty of tackles, and the user wants more general play and more varied footage.

## Build, in this order

1. **Toggles per type on the Highlights screen.**
   - The problem: `HighlightTable.TYPES` already detects tackles and bumps. But `highlights.gd` keeps one shared list of `MAX_MOMENTS` (24) and ticks only the best `DEFAULT_KEEP` (8). Goals and marks always outscore tackles, so a tackle never reaches an export.
   - Add a toggle for each type: goals, behinds, marks, tackles, bumps, long kicks, rucks.
   - Each toggle filters the list and ticks or unticks that type for export.
   - Show a count per type, and remember the choices in settings.
   - Give each type its own memory cap, so goals can't push every tackle out.

2. **A "general play" type.** A passage with no single headline event. Examples: a chain of 3 or more disposals, or a run with bounces. Give it a low base score, off by default, behind its own toggle.

3. **A third-person camera preset** in `replay_stage.gd`, alongside `broadcast`, `close` and `end`.
   - Place it behind and above the moment's main player (the kicker, marker or tackler), looking along their direction of travel.
   - Match the in-game chase camera: `scripts/camera/broadcast_camera.gd`, `Mode.CHASE`. Reuse its numbers where you can.
   - Make it selectable per moment in the export dialog, and as a default per type (for example, third-person for tackles and bumps).

4. **Cheaper exports, so more clips are affordable.**
   - Add an option to render 16:9 only, 9:16 only, or both. The video side now uses only 16:9: square posts with the 16:9 picture between black bars. 16:9-only halves the render.
   - The type toggles decide what gets rendered, not only what's listed.

5. **A generator for staged footage**: a dev scene in `scenes/dev/` with its script in `scripts/dev/`.
   - It plays an AI-vs-AI match, or staged plays: set shots from different spots, contested marks, tackles. Check whether the Training drills can set these up.
   - It runs at a fixed fps with the recorder on, then exports every goal, mark and tackle, plus some general play, from varied cameras.
   - Mark everything it makes as generated (see the schema below). It isn't the user's own play, and the video side must not caption it as "I".
   - Contests stay physics and timing (`docs/RULES_REFERENCE.md` §3). No scripted outcomes.

6. **Fix three bugs found in the 2026-11-10 and 2026-11-11 exports.**
   1. **A goal's `facts.distance` sometimes comes from an earlier kick.** In `highlights/2026-11-10_114933_Home-v-Away`:
      - Rows 05, 10 and 11 say 60, 53 and 36 m.
      - The replay's ball track shows the scoring kick travelling about 6, 4 and 5 m.
      - Row 11's scoring kick came after a mark. In row 05, the 60 m kick went out, the ball was reset at frame ~197, then a short kick scored.
      - Measure the distance from the kick that actually scored, and report that kick's kicker.
   2. **After a goal, the broadcast camera follows the ball past the posts into the trees.** See `03_goal`, from about frame 180. Stop following once the ball is a few metres past the goal line, or keep the camera inside the fence.
   3. **A cancelled export leaves a truncated clip.** In `2026-11-11_185208_Home-v-Away`, row 07's clip has 108 frames but its replay has 225, and nothing in the row says so. Mark rows like this with `"complete": false`, or drop them.

## moments.json

Bump `version` to 2. Add fields only; keep every v1 field as it is.

- `match.mode`: `"human_vs_ai"`, `"ai_vs_ai"` or `"staged"`.
- Top-level `footage`: `"match"` or `"generated"`.
- Per moment:
  - `event_frame`: the frame index in the clip.
  - `frames`: the clip's frame count.
  - `camera`: the preset used.
  - `complete`: false for a truncated clip.
  - For goals and behinds: `kick_frame`, `kicker`, and the scoring kick's distance.
  - `events`: a list of `{frame, kind, player}`, where `kind` is kick, handball, mark, tackle, bump, bounce, goal, behind or siren. This lets the video side add sound effects and cut on exact frames, instead of guessing from ball speed.
- Keep `players[].human` correct. In a dummy match, every player is `human: false`.

## Done when

- A real match exported with tackles ticked gives `NN_tackle_16x9.avi` clips and their rows, filmed with the third-person camera.
- The generator exports at least 10 clips of goals, marks and tackles, each flagged as generated.
- A 16:9-only export renders about half as many frames.
- The three bugs are fixed, each checked on a re-export. For distance: |`facts.distance` − horizontal ball travel from `kick_frame` to `event_frame`| ≤ 3 m.
- New items go in `docs/PLAYTEST_CHECKLIST.md` (camera framing, toggles). Durable lessons go in `docs/LESSONS.md`.
- New tuning numbers are marked "unplaytested feel guess".

Exports need a real renderer (windowed, not `--headless`).

Report three things: what you changed, what you checked, and what needs the user's eyes.
