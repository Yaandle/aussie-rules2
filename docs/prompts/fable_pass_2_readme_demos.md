# README and feature demos: make them accurate, clean and realistic

You're working in `F:\dev\aussie-rules2` (Godot 4.6). Read `CLAUDE.md` first, then `docs/LESSONS.md`, then `README.md`. Follow the repo's rules: the branch, never push, commit only your own files, verify headless where you can.

## Why

The project's opening video (84 s, made in the separate video-editor repo) is built from this README and its demo GIFs:
- the three marks
- the timing ring "timed from the ball's real flight"
- the drop punt at 13–24 m/s with end-over-end backspin
- "two ruckmen, a palm not a catch"
- the tackle/officiating signal code snippet
- tackles handing players to an active ragdoll
- 18-a-side
- two ovals built in Blender
- Career mode
- the AI ladder (logistic regression → GA → MLP 5-8-8-1 → deep Q-learning next)

Some of these examples are out of date or look rough. The game has moved on since they were recorded. Since day 2 alone:
- contested marks now weigh timing, position, height and body
- there's a new fend-off that can break tackles
- there's a mark-timing assist (`12c6761`)

Update the README and the demos so they're accurate and look like the game today. A video session will then rebuild the intro from your output.

## 1. Check the README against the code

- Go through every factual claim in `README.md`: controls, numbers, mechanics, the architecture snippets, the release and status lines.
- Check each against the current code (`scripts/tuning.gd`, `player_controller.gd`, `ball.gd`, `ai_brain.gd` and the rest).
- Fix what's wrong. Add what's missing (the fend-off, the contested-mark changes, the timing assist). Remove what no longer exists.
- Every number you keep or change must come from code or docs you can point to (file and constant).
- Contests are decided by physics and timing, never a dice roll (`docs/RULES_REFERENCE.md` §3). Keep every description true to that.
- Keep the README's voice: plain, short, specific.

## 2. Re-record the feature demos so they look like the game

Today's demos are marking, kicking, tackling and ruck:
- recorded by `scenes/dev/demo_recorder.tscn` in the animation viewer's dark studio;
- written as 1600×900 PNG frames;
- shrunk by `tools/make_demo_gifs.py` to 720×405 GIFs at about 16.7 fps.

What hurt when they were used in the video:
- **Dark studio backdrop:** a stylised treatment turned them almost black, and they read as "not a real match".
- **Low resolution and low frame rate:** soft and choppy at video size.
- **Too short:** kicking is 3.4 s and had to be slowed to 0.67×.
- **Cluttered:** some on-screen captions and prompts compete with the action.

Wanted:
- **A real ground with match lighting.** Use the bush oval or the park (`Settings.field_style`, CLASSIC or OVAL_1) and the match sun, as the highlights replay stage now lights it. If the studio is the only place a demo can stage its contest, light it like a match and give it a ground.
- **A clean frame:** only the HUD element the demo is about (for example the mark badge and timing ring), with no debug text. Keep the README GIFs' short control caption only if it helps the reader. Leave the video copies clean, without captions.
- **Real gameplay code, as now.** The recorder presses buttons and moves the camera; nothing scripts an outcome. Note any staging you add in the recorder's header, as it already does for the ruck and the sling.
- **Length and smoothness:** at least 6–8 s each, at 30 fps or better, with a camera that frames the action closely and moves smoothly.
- **Coverage:** marking (safe, running, aggressive; contested), kicking (stance, drop punt, a set shot), tackling (wrap and sling into the active ragdoll, and the new fend-off breaking one), and ruck (centre bounce, tap to a runner).
- **Two outputs per demo:**
  - `docs/media/<demo>.gif` for the README. Keep each one reasonable in size: the same width or a bit bigger, and smoother than now.
  - `docs/media/video/<demo>.mp4` for video use: the full recording size (1600×900 or larger), constant 30 fps, H.264, no audio track, first frame at t = 0. The video renderer seeks by frame number, so a late-starting stream shows every frame one late.
- Reuse and extend `demo_recorder.gd` and `tools/make_demo_gifs.py` rather than starting over.

## 3. Leave these alone

`scripts/dev/highlight_stills.gd` and `scenes/dev/highlight_stills.tscn` are the video pipeline's in-game stills and camera-move tool. They're uncommitted and in use. Its flags are `--shots`, `--out`, `--size`, `--jpg` and `--field`, and it needs per-shot `t`. It relies on `ReplayStage` (and its `DirectionalLight3D` child), `ReplayClip.load_file()`, `ReplayClip.decode()` and `Settings.field_style`, so keep all of those working.

## 4. Hand back

Write `docs/media/demos.json`, listing for each demo:
- `{name, gif, mp4, seconds, fps, size, ground, what_it_shows, controls, readme_section}`

and `changed_facts`, a list of `{was, now, source}` for every README claim you changed: anything the intro might be saying or showing.

The video session uses this file to update the intro's text, narration and shots. Don't edit the video-editor repo yourself.

## Done when

- Every README claim matches the code, with the sources noted in your report.
- The four demos (five if the fend-off gets its own) are re-recorded on a lit ground, with both the GIF and the MP4 versions.
- `docs/media/demos.json` lists them, plus the changed facts.
- New items to playtest go in `docs/PLAYTEST_CHECKLIST.md`.

Report what changed, how you checked it, and what needs the user's eyes. The user will pass your report to the video session for the final intro render.
