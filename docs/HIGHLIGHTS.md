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

## Checking an export

`scenes/dev/highlight_check.tscn` (headless is fine) reads a folder and checks
frame counts against the AVI headers, event frames, the generated flag, and
that a goal's `kick_distance` is within 3 m of the ball's travel from
`kick_frame` to `event_frame` with the kicker at the ball. `-- --cameras` also
replays each clip on every camera preset and reports how far it strays.
