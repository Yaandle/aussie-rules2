# Highlights capture audit and plan (2026-11-24)

Goal: highlights that film themselves well from the game's own events, with
nothing to do in game. The export format only gains fields (HIGHLIGHTS.md
lists every one). Frames: `docs/review/highlights_camera/`.

## How it works (the part that matters)

Highlight video is never captured from the screen. The recorder stores
poses (`.replay`, `match.replay`), and the export re-shoots them on the
`ReplayStage` with its own cameras. So the export already is a "replay-based
re-render". The in-game camera (BroadcastCamera, Settings.camera_zoom) never
reaches a highlight.

## Audit (evidence)

Measured with `scenes/dev/highlight_camera_audit.tscn` on five real exports
(11-12, 11-16, 11-18, 11-21, 11-24; 188 moments), old code (HEAD 99de983) vs
new. "px" is the main subject's on-screen height at 1080 lines.

| finding | evidence | status |
|---|---|---|
| Broadcast players tiny | old broadcast preset: mean 67 px, 232 of 240 moment-runs under 80 px (fixed 37 m offset, 40° lens) | fixed: size rule; auto 231 px mean |
| Goal camera misses the ball at the posts | old third person: ball in frame on the scoring frame in 6 of 12 goals | fixed: auto 42/42 goals and behinds |
| Kicks and marks from behind | third person sits behind the kicker/marker by design | fixed: side-on shots (frames) |
| Ball reset snaps the camera | the hold-on-jump rule was goal/behind only | fixed for every type |
| Camera inside a tree | not reproduced: 0 frames inside a tree/prop box for every old preset, every export, both grounds, and the whole 11-24 match on the match camera. The report's clip may be older than the fence clamp. | guarded anyway: `CameraOccluders` + `_clear_view` |
| Camera jolts | old follow rig moved the lens over 1 m a frame for 3 to 38 frames per goal/general clip | fixed: 0 across the five exports |
| Goal tail cut | 11-24 moment 9: 104 post-goal frames recorded, 77 in highlight.mp4 (dead-time cut at 2.5 s after the clock stopped) | fixed: moments are protected; generated test kept 105/105 |
| FULL TIME vs match.json | the screen reads MatchState, where `marks` counts every take (legal or not); match.json counted only legal `mark` events; tackles come from two different hooks | `match.json.full_time` = the screen's numbers, `event_counts` beside it |
| Rolled-through goals, score_before | Field `scored` can fire twice for one score; FullGame ignores the second, the recorder made a second moment with score_before a goal too high. No kick in flight gives kicker null. | fixed: re-trigger ignored; `score_method`, `last_touch` |
| In-game zoom range | 0.8-1.4, 7 steps; Full-Side far side ~25 px players | 0.5-3.0 with presets; Full-Side min size |
| Setting sync | pregame (Full Game, Career) and pause all write `Settings.camera_zoom` (saved, live signal) | kept; they now share `CameraZoom` labels and steps |
| Mid-match zoom vs recording | replay stores poses only: zoom can't change a recording or its alignment | by design; documented |
| Headless occlusion | the dummy renderer reads MultiMesh instances back as identity (the whole park at the centre bounce) | builders now keep `instance_transforms` meta |

## Done in this pass

- **Director (`auto`, every type's new default)** in `ReplayStage`: goals
  and behinds = kick side-on from 35° behind, flight follow, cut behind the
  posts (tilted only as far as the ball needs, settling on the goal square
  after); marks = flight follow, cut to a low side-on two-shot 0.9 s before
  the catch; tackles, bumps, rucks = side-on to the pair, from the side with
  fewer bystanders in the way; long kicks = kick then flight; general and
  the match camera = smart broadcast follow (pans, holds kicker and ball
  while the ball is up).
- **Framing** (`HighlightPrefs.framing`, export window row): WIDE, STANDARD,
  CLOSE, TIGHT = the subject at least 10/16/22/30% of the frame height. The
  highlights use their own framing, not the match zoom: a zoom chosen to
  play is the wrong zoom for a phone clip, and a replay never sees it anyway.
- **Scenery and bodies**: lift (crane) then pull in, never a frame inside.
- **Tail/lead protection**: moments plus 0.5 s before and 1 s after are never
  cut as dead time; the Highlights MATCH view uses the same cut.
- **Export reliability**: `export_status.json` (running/complete/cancelled,
  fraction, step); `highlight.mp4` and `match_video.json` are written under
  partial names and renamed together at the end.
- **Data**: see HIGHLIGHTS.md (scores: set_shot, score_method, last_touch;
  marks: contested; time left; full_time block; time_convention).
- **In-game camera**: zoom 0.5-3.0 in 13 steps with WIDE/STANDARD/CLOSE/TIGHT
  presets (the pause menu's Enter cycles presets, arrows step), the label
  names the preset; Full-Side never lets the player at the ball drop below
  4.5% of the frame (×zoom); 3rd person arm never under 2.2 m.

## Plan for what's left (priority order, effort)

1. **Visibility ranking on the Highlights page** (M, 1 day): run the audit's
   measure (subject px, ball in frame, occlusion) per moment at match end,
   add `camera_quality` to moments.json and a small "why" line per moment on
   the page. The measuring code exists (`highlight_camera_audit.gd`).
2. **Slow motion around the key frame** (M): a time-remap per moment
   (0.5x/0.25x ramps over the kick, catch or impact) in the full-match
   render, recorded in match_video.json `cameras` runs as `speed`. Changes
   frame counts, so the video tool must read the new field first.
3. **9:16 full match from the same replay** (M): render a second pipe in
   portrait in the same pass (the director already reframes; frames above).
4. **Quality options** (S-M): CRF/preset as prefs (CRF 16 "slow" for
   uploads), 60 fps needs a 60 Hz recording (the recorder samples at 30), a
   no-HUD option is moot (exports have no HUD), 4K is one constant away but
   ~4x the 15 min render.
5. **Background/headless export** (L): the render needs a GPU, so it can't
   be `--headless`; a separate windowed process
   (`highlight_generator`-style scene with `--folder`) that resumes by part
   is the way. Parts already resume.
6. **Audio stems** (L): log each SFX play (AudioManager) with its frame into
   match.json, and render stems with ffmpeg from the same sound files.
7. **DOF and grading for close shots** (S): CameraAttributesPractical on the
   side-on shots (far blur), a contrast/saturation preset for OLED.

All new camera numbers are unplaytested framing guesses; checks are in
PLAYTEST_CHECKLIST.md.
