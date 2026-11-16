# Highlights v3 plan: full-game footage with markers

Status (2026-11-16): phase 1 (record the whole match) is built; the rest is
plan. `docs/HIGHLIGHTS.md` "Full match" has what phase 1 writes. Read
`docs/HIGHLIGHTS.md` first; this extends it.

## What you asked for

1. Render the whole match, not just the picked moments.
2. Put the full video on a timeline with markers: goals, behinds, marks,
   tackles, bumps, kicks, handballs, the ranked highlight moments.
3. Change the camera for a stretch of the timeline (a moment) and re-render
   only that stretch.
4. From that, export a highlights cut the daily-video tool
   (`F:\dev\video-editor\video-editor\studio\daily`) uses with the devlog,
   commits and your game notes.
5. Only if it doesn't hurt performance.

## Audit: what exists today

| Piece | File | What it does now |
|---|---|---|
| Recorder | `scripts/highlights/highlight_recorder.gd` | Reads every body's pose 30x a second into a **20 s ring** (`HighlightTable.BUFFER_SECONDS`). Logs every kick, handball, mark, tackle, bump, bounce, score and siren in `_events` with a time. When a moment is detected, copies its window out of the ring into a `ReplayClip`. Everything outside those windows is thrown away. |
| Clip format | `scripts/highlights/replay_clip.gd` | Poses, not pixels: header (clock, quarter, score), ball, then each body's root and bone rotations. About **8.9 KB a frame** (measured: `01_mark.replay` is 1.3 MB for 147 frames). |
| Replay stage | `scripts/highlights/replay_stage.gd` | Puppets posed from a clip, filmed from `broadcast`, `close`, `end` or `third`. Can re-film any recording from any preset; this is why a camera change is possible after the match. |
| Exporter | `scripts/highlights/highlight_exporter.gd` | Renders each kept moment off-screen, frame-exact, to MJPEG AVI (+ mp4 if ffmpeg is on PATH), writes `moments.json` v2. |
| Ranking / UI | `highlight_table.gd`, `highlights_screen.gd`, `highlight_export_dialog.gd`, `highlight_prefs.gd` | Types, caps, toggles, per-moment camera, aspect. |
| Checker | `scenes/dev/highlight_check.tscn` | Verifies frame counts, events, kick distance. |
| Video side | `studio/daily/episode.py`, `cut.py`, `angle.py` + `godot/angle_replay.gd`, `devlog.py` | Ingests the export, trims each clip from the `.replay` ball track, picks 20-45 s, re-films the key moment from a second preset, adds devlog cards (commits since last match) and the box score + your notes. |

What that means for the request:

- **Recording the whole match is cheap.** The recorder already packs a full
  frame every 1/30 s for the ring. Keeping them instead of overwriting costs
  disk, not CPU. A match is 4 x 120 s of play (`Tuning.QUARTER_LENGTH`), so
  about 480 s x 30 x 8.9 KB = **~130 MB** of poses. Streamed to a file as it
  goes, it adds no measurable frame time.
- **Rendering the whole match is the slow part, but it's after the match,**
  off-screen, so it never touches gameplay. The 2026-11-16 export rendered
  38 clips (~190 s of footage, both shapes) in about 13 min. 16:9 only, a full
  match is roughly 15-25 min of rendering. MJPEG at 1080p is ~5.8 MB/s, so a
  full-match AVI is ~2.8 GB; it should go straight to mp4 (ffmpeg pipe) or be
  deleted after the mp4 is made.
- **A camera change never needs the match replayed.** The stage re-films
  poses, so changing a stretch's camera re-renders only those frames, and
  frame N stays frame N (what `angle_replay.gd` already relies on).
- The video tool already does trims, angles, devlog and notes. Most of the
  daily-video work is pointing it at a full-match file instead of per-moment
  clips.

Known risks from the audit:

- The replay assumes evenly spaced frames (the generator runs with
  `--fixed-fps 60` for this). In a live match the recorder samples on a
  timer, so a hitch gives an uneven frame. The full recording must store
  each frame's time (the ring already has `_ring_times`) and the renderer
  should resample to an even 30 fps.
- Pauses, quarter breaks and the ball reset after a score: the full file
  should mark them (a `segments` list) so the timeline can skip breaks and
  the camera snaps instead of easing across a reset.
- `moments.json` v1/v2 fields must not change (memory rule, and the video
  side reads them). Only add.

## Plan

Five phases, each one shippable and checkable on its own.

### Phase 1: record the whole match (game)

- `HighlightRecorder` writes every committed frame to
  `highlights/<match>/match.replay` as it goes (same frame layout as
  `ReplayClip`, file version 2: a per-frame time, plus `segments` for
  quarters, breaks and pauses written at the end). The ring stays for moment
  clips.
- Write the whole event log as `match_events.json`: every `_events` entry
  with its full-match frame, not only those inside a moment.
- Each moment gets `match_frame` / `match_from` / `match_to` (where its clip
  sits in the full recording).
- Option in `HighlightPrefs`: "Record full match" (on by default; off skips
  the file).
- Check: a scratch scene plays an AI-v-AI match, asserts frame count ~ play
  time x 30, file size, and that each moment clip's frames match the full
  file at `match_from`. Log the average `_commit_frame` cost before and after.

### Phase 2: render the full match (game, offline)

- New `HighlightExporter.export_match()`: plays `match.replay` through the
  ReplayStage, 16:9, default camera `broadcast` following the ball, writes
  `match_16x9.mp4` (ffmpeg pipe if present, else AVI). Renders a quarter at
  a time so a cancel keeps finished quarters and it can resume.
- A headless-style runner beside `angle_replay.gd` so the video tool can
  start the render itself (windowed, needs a renderer).
- Button in the Highlights screen: "Render full match", with progress.
- Check: frame count of the mp4 = resampled frame count; `highlight_check`
  extended to read the full-match file.

### Phase 3: timeline markers (game writes, video tool reads)

- `moments.json` **v3**: adds a `full_match` block (`replay`, `video`,
  `frames`, `fps`, `segments`) and per moment `match_frame`, `match_from`,
  `match_to`. Every v2 field stays.
- `match_events.json` is the marker list: goal, behind, mark, tackle, bump,
  kick, handball, bounce, siren, plus `highlight` markers for the ranked
  moments (with their rank and score).
- The video tool converts these into markers for the editor you cut in (see
  open question 1): its own timeline, or an EDL / FCPXML / marker CSV for
  DaVinci Resolve or Premiere.

### Phase 4: camera per moment on the timeline

- A `camera_track` in the episode: `[{from, to, preset}]`, default one
  segment of `broadcast` for the whole match; each highlight moment starts
  with its own type's camera (`ReplayStage.DEFAULT_PRESET`).
- Changing a stretch re-renders only those frames with the stretch's preset
  (`angle_replay.gd` already takes `from`/`to`) and splices them into the
  full video at the same frame numbers. A short ease at each join so the cut
  isn't a jump, unless the edit is meant to be a hard cut.
- Where you change it: recommended in the video tool (it already owns the
  episode and the angle runner). A game-side timeline scrubber is possible
  but more work; see open question 2.

### Phase 5: the highlights cut for the daily video

- `cut.py` trims from the full-match video using `match_frame` instead of
  per-moment clips (same trim rules, which already work on frames).
- Keep per-moment clip export as a fallback, so nothing in the current daily
  pipeline breaks while this lands.
- Devlog cards and your game notes stay as they are in `devlog.py`; the box
  score can now be counted from `match_events.json` instead of typed in.

## Decisions (user, 2026-11-16)

These override the phase text above where they differ.

1. **Markers go to the daily-video tool only** (`studio/daily`), no
   EDL/FCPXML. The game also shows the same timeline on its Highlights
   page. Export writes a JSON (`moments.json` v3 + the marker list) that the
   video tool loads onto its timeline for the agent.
2. **Cameras are changed in the game's Highlights screen**, on that
   timeline (Phase 4 moves into the game). The export renders those camera
   choices into the full video and into `highlight.mp4`, so the video tool
   takes the cameras as given.
3. **The full video is trimmed**: quarter breaks, pauses and dead time
   (after a score until the bounce, ball out of play) are cut out. The
   recording keeps everything; the trim is a list of kept ranges (`keep`)
   in `full_match`, and every marker carries both its recording frame and
   its frame in the trimmed video. What counts as dead time is a
   `HighlightTable` number set (unplaytested feel guesses).
4. **16:9 only for the full match**, 1080p as now. Other resolutions later.

So the export gives:

    match_16x9.mp4      the trimmed full match, with the timeline's cameras
    highlight.mp4       the ranked moments cut from it, same cameras
    moments.json        v3: full_match {replay, video, frames, fps, keep,
                        camera_track}, per moment match_frame/video_frame
    match_events.json   every marker, recording frame + video frame
    match.replay        the full pose recording

## Order of work

1. Phase 1: record the whole match (recorder only, can't change a match).
2. Phase 2: trimmed full-match render, default cameras.
3. Highlights page timeline: scrub the full match, markers, moment list.
4. Camera track edited on that timeline; render uses it; `highlight.mp4`.
5. `moments.json` v3 + `match_events.json`; then the video tool reads them
   (that repo's change, its own session).
