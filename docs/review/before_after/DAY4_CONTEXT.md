# Day 4: before and after, handover for the video editor

Folder: `F:\dev\aussie-rules2\docs\review\before_after\`. Open `index.html` in it to browse everything.

## The angle

Day 4 is about the changes, not the match. Narrate in first person, as if I've just made them:
"Three weeks ago my game looked like this. Here's what I changed." Cut from my Day 4 highlights into a
before-and-after section, then back to the match.

The "before" is real. It's the build from **25 Oct 2026** (commit `b09e434`, Release 1.3), rendered on
16 Nov from that exact code. Nothing was mocked up. The "after" is the game as it is now.

## Clips and stills to use

**Main before/after (25 Oct build v now):**

| File | Shows | Narration idea |
|---|---|---|
| `old_build_2026-10-25/clip_centre_bounce.gif` (4.5 s) | the old build's centre bounce: mannequin players, flat turf, debug readout on screen | "This is where it was three weeks ago." |
| `old_build_2026-10-25/clip_tackle.gif` (3.8 s) | an old tackle ending in a holding-the-ball free kick | "Tackles were stiff, canned animations." |
| `then_now_centre_bounce.png` | old centre bounce v the 13 Nov ruck demo | the ground and the players |
| `then_now_tackle.png` | old tackle v a Day 3 slide tackle (ragdoll on the turf) | tackles now play out on physics |
| `then_now_match_view.png` | old match view v a Day 3 contested mark | the whole look |
| `old_build_2026-10-25/menu.png` | the old main menu (v1.3.0; Scenario and Goal Kicking "Not built yet") | still only (no "now" menu shot was taken) |

**Same demo, 29 Oct v 13 Nov.** The README GIFs were re-recorded. The old versions are
`<demo>_2026-10-29.gif` and the new ones are `docs/media/<demo>.gif`; MP4s are in `docs/media/video/`.
There are stills for each in `demo_<marking|tackling|ruck|kicking>_<1-3>.png`. These are different takes,
so compare the look, not the moment.

**Further back (optional).** `p1_*.png` shows Prototype 1 (16 Aug, a pixel-art top-down game) against
AR2 now. That's the "where it started" beat.

**Player model.** `../7thbuild/build6_vs_build7_*.png` compares the old body (Build 6) with the current
one (Build 7, 8–9 Nov), already side by side.

Skip the `dev_*.png` pairs for this video. They show internal dev tools.

## What changed, 25 Oct to 16 Nov (from git, in my words)

- **The grounds (26 and 31 Oct):** two real ovals, a park with a scoreboard and a bush oval with a
  timber scoreboard, both dressed from reference art. Before, it was flat green with a few trees.
- **Career mode (26–27 Oct):** 12-round seasons, a ladder, promotion through six leagues, create
  your player, upgrades, Easy/Hard.
- **Tackles on physics (25 Oct – 11 Nov):** tackles moved from canned clips to an active ragdoll.
  Tap X to wrap and go down together, hold B to sling. Who wins the collision decides the outcome.
  Held-up tackles are now a wrestle, the hands land on the other body, and the AI's tackles ragdoll
  too.
- **Kicking (28 Oct):** a real drop punt, the ball carried in both hands.
- **The player model (8–9 Nov):** Build 7, a new athletic body with team kits, numbers and hair. It
  has planted running gaits and a walk.
- **Contact (9–11 Nov):** bodies sway and brace when they meet, and runners pressed together push
  shoulder to shoulder.
- **Highlights (8 and 11 Nov):** the game records its own highlights, replays them and exports clips.
  This series is made from them.
- **Training drills (2–8 Nov):** a kicking and leading circuit.
- **New moves (11 Nov):** fend off and fist on RB, snap and banana kicks on LB, calling for the ball.
- **Marking (12 Nov):** a jump stat, and contested marks decided by timing, position, height and
  body. Nothing is random. There's also an optional slow-motion timing assist.
- **Goal kick (15 Nov):** mark it inside 60 m, press Y, and the camera swings behind you to line up
  the shot.
- **Today, 16 Nov: the fend you can see.** The fend arm used to be invisible unless you were already
  being hit. Now the arm always shows, and if a defender runs into it your hand lands on their chest
  and pushes them about a metre back, off balance. You keep the ball.

## Patch notes card, changed since Day 3

- New · Goal kick: mark inside 60 m, press Y to line up the shot (`1cc2b39`)
- Changed · Fend off: you can see the arm, and it pushes defenders back (`1ec5c33`)

## Be careful with

- The fend change and the goal kick were checked headless but **not played before Day 4**. Only say
  they work if the Day 4 footage shows it.
- I said I get a lot of intercepts from the AI's kick-outs and back-50 kicks. A fix was tried and
  measured, but it didn't help, so it was reverted. **Don't claim it's fixed.** It's an honest "still
  working on it" line if you want one.
- The old build's debug readout (left side, white text) was on by default in that version. It's real,
  but it makes the old game look more like a dev build than it played.
- The old clips are 640×360 GIFs and the stills are 1600×900. Nothing in the old frames is staged:
  it's a normal Full Game kickoff with nobody touching the pad.
