# Highlights

The last Full Game's best moments, replayed and exported for the daily video
series (`F:\dev\video-editor\video-editor`, `studio/daily`). Code:
`scripts/autoload/highlights.gd` (keeps the moments), `scripts/highlights/`
(recorder, table, replay stage and clip, exporter, prefs),
`scripts/ui/highlights_screen.gd` and `highlight_export_dialog.gd`. Every
ranking number is in `highlight_table.gd`; they are unplaytested feel guesses.

## What the screen does

- **Types**: goals, behinds, marks, tackles, bumps, long kicks, rucks and
  general play (a passage of 3+ disposals in a row, or 2+ bounces, with no
  headline event; off by default). Each has a toggle (keys 1-8 or a click on
  the screen, or a row in the export window) and a count. A type that's off
  isn't listed and isn't rendered. Switching one on ticks its best few
  (`TYPES[type].keep`); off unticks them all. Each type has its own memory
  cap (`TYPES[type].cap`), so goals can't push every tackle out.
- **Cameras**: `broadcast`, `close`, `end` and `third` (the in-game chase
  camera behind the moment's main player). Per type default and per moment,
  both in the export window; defaults in `ReplayStage.DEFAULT_PRESET`.
- **Format**: 16:9 + 9:16, 16:9 only or 9:16 only (the video side uses 16:9
  only; one shape is half the render).
- The choices are saved in `user://highlights.cfg` (`HighlightPrefs`).

## Output

`highlights/<date>_<time>_<Home>-v-<Away>/` (the generator's go in
`highlights/generated/`):

    NN_<type>_16x9.avi / _9x16.avi   MJPEG, 30 fps (only the shapes asked for)
    NN_<type>.replay                 raw poses (ReplayClip), always whole
    match.replay, match.json         the whole match (see "Full match")
    match_16x9.mp4, match_video.json that match rendered, dead time cut
    match_qN_16x9.mp4                a quarter's part, only while the render
                                     is unfinished (rendering the same folder
                                     again skips finished parts); deleted once
                                     joined
    moments.json

## moments.json (version 2)

Version 2 only adds fields; every version 1 field is as it was.

Top level: `format`, `version` (2), **`footage`** (`"match"` or
`"generated"`: footage from `scenes/dev/highlight_generator.tscn`, not the
player's own play, so don't caption it as "I"), `match`, `exported_at`,
`output`, `moments`.

- `match`: `home`, `away`, `career`, `started`, `final`, `finished`, and
  **`mode`**: `"human_vs_ai"`, `"ai_vs_ai"` or `"staged"` (the generator
  writes `ai_vs_ai`).
- `output`: `folder`, `video`, `mp4`, `complete` (false if the export was
  cancelled), and **`aspect`** (`"both"`, `"16x9"`, `"9x16"`).

Per moment (v1 fields: `id`, `rank`, `type`, `label`, `caption`, `quarter`,
`game_clock`, `quarter_elapsed_s`, `match_time_s`, `duration_s`,
`event_offset_s`, `highlight_score`, `human_involved`, `players`
(`name`, `team`, `side`, `role`, `human`), `score_before`, `score_after`,
`facts`, `camera`, `files`), plus:

| field | meaning |
|---|---|
| `event_frame` | frame index of the moment itself in the clip (`event_offset_s` × 30) |
| `frames` | video frames actually rendered |
| `replay_frames` | frames in the `.replay` |
| `complete` | `frames` == `replay_frames`; false for a clip cut short by a cancelled export |
| `events` | `[{frame, kind, player}]`, `kind` one of `kick`, `handball`, `mark`, `tackle`, `bump`, `bounce`, `goal`, `behind`, `siren`; `player` is a name or `""` |
| `kick_frame`, `kicker`, `kick_distance` | goals and behinds only: the kick that scored it. `kick_distance` is the ball's horizontal travel from the boot to the line, in metres (`facts.distance` is the same number). All `null` when nothing was kicked (a ball carried or rolled through) |

`players[].human` is true only for the player's own body: in a generated
(all-AI) match every player is `human: false`.

`facts.own_goal` is set when the scoring kick was taken by the other side
(a defender kicking through his own goal): `kicker` is that defender.

Frame numbers are clip frames at 30 fps; the video and the `.replay` line up
one to one.

## Full match

Since 2026-11-16 (`docs/HIGHLIGHTS_FULLGAME_PLAN.md`, phase 1) the recorder
also writes every frame of the match to `highlights/_recording/match.replay`
as it plays (pref `full_match` in `user://highlights.cfg`, on by default;
~9 KB a frame, ~130 MB a match). The next match overwrites it; an export
copies it into the match folder. It's a ReplayClip with `frame_count` -1
in its header (frames run to the end of the file), so the video side's
`replay.py` reads it as is.

`match.json` (`format` "aussie-rules-2-match", `version` 1): `fps`,
`frame_count`, `duration_s`, `frame_times` (each frame's recorder time, s:
frames are sampled on a timer and a hitch spaces them unevenly), `segments`
(`{quarter, from, to, t_from, t_to}`, a new one at each quarter or pause),
and `events` (every `kick`, `handball`, `mark`, `tackle`, `bump`, `bounce`,
`goal`, `behind`, `siren` of the match: `{frame, t, kind, player, team}`).

moments.json adds (still version 2, fields only added) a top-level
`full_match` (`replay`, `json`, `frames`, `fps`) and per moment
`match_from`, `match_to`, `match_frame`: clip frame k is full-match frame
`match_from + k`, byte for byte.

## MATCH view (the timeline)

On the Highlights screen T (pad: View) switches to the MATCH view when the
match was recorded in full: the stage plays the whole recording, timed as
the full-match video (breaks and dead time cut, the same FullMatchCut), and a
timeline (`scripts/ui/match_timeline.gd`) sits under it: moment bands along
the top (lime when kept, outlined when selected), a tick per event coloured
by kind (goals and behinds tall), quarter dividers, the playhead. Click or
drag the bar to seek, up / down jump between moments, left / right change
the camera, [ / ] step (5 s playing, a frame paused), Esc or T goes back to
the clips. The first switch loads match.replay (~100 MB). The camera picked
here isn't saved or used by the export yet (phase 4).

## Full-match video

With the export window's FULL MATCH VIDEO row on (pref `full_video`, on by
default) an export also renders the whole recording, 16:9 1920x1080 at
30 fps from `HighlightTable.FULL_MATCH_CAMERA` (broadcast, following the
ball), with breaks and dead time cut (`FullMatchCut`: a stopped match clock
of `DEAD_MIN` s or more is cut, keeping `DEAD_KEEP_AFTER` s after it stops and
`DEAD_KEEP_BEFORE` s before play restarts; unplaytested guesses). The camera
snaps at each cut. Frames are resampled by `frame_times`, so the video's
timing is even even when the recording's wasn't.

ffmpeg (`HighlightPaths.ffmpeg()`: the `ffmpeg` key in highlights.cfg, the
video tool's `tools/ffmpeg/bin/ffmpeg.exe`, then PATH) gets raw frames piped
in, one H.264 part per quarter, joined into `match_16x9.mp4`. Without ffmpeg
each quarter is an MJPEG `match_qN_16x9.avi` and `video` is null.

`match_video.json` (`format` "aussie-rules-2-match-video", `version` 1):
`fps`, `size`, `camera`, `video`, `parts` (`{quarter, file, video_from,
frames}`, `file` null once joined into `video`), `frames`, `complete`, `recorded_s`, `video_s`, `trim` (the three
numbers used), `keep` (`{from, to, quarter, video_from, video_frames}`:
recording frames kept, inclusive, and where they start in the video),
`markers` (every match.json event plus `video_frame` and `cut`: true when it
happened in cut time, then `video_frame` is the next kept frame), `moments`
(`{id, rank, type, label, video_from, video_to, video_frame, event_cut}` for
each exported moment). This is the timeline the video tool reads.

## Checking an export

`scenes/dev/highlight_check.tscn` (headless is fine) reads a folder and checks
frame counts against the AVI headers, event frames, the generated flag, and
that a goal's `kick_distance` is within 3 m of the ball's travel from
`kick_frame` to `event_frame` with the kicker at the ball. `-- --cameras` also
replays each clip on every camera preset and reports how far it strays.
