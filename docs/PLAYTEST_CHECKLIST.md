# Playtest checklist

Things that need a person playing the game, with one check each. Newest
first. Tick or strike an item when it's been played; anything that fails
goes back to its doc. Older "needs your eyes" lists still live in their
own docs: `ANIMATION_RAGDOLL_AUDIT.md` (kick, carry, phase lock, bank,
tackles), `MECHANICS_AUDIT.md` (ragdoll stages 2-5) and the 2026-10-30
playtest commit (HUD, park turf, ruck, training).

## Marking block: jump attribute and contested marks (2026-11-12, branch `update`)

- [ ] Jump (6AD): CHARACTER screen, JUMPING row now moves (0.70x-1.50x). At 1.50 the (Y) leap goes about 1.25 m off the ground, at 0.70 about 0.6 m (it was 0.82 m for everyone). Does the top end read as a big leap, not a float? The (Y) ring timing should feel unchanged. `Tuning.CHARACTER_JUMP_*`.
- [ ] Jump in Career: JUMPING is a fifth trainable row on the Career character screen. Does the card still fit with five rows? An old Career save should load with JUMPING at the default. OVERALL ratings shift a little (five attributes averaged, not four).
- [ ] Contested marks (6AE): go up against an opponent for the same ball. The one with better timing, front position, higher hands (height + jump) or more body should take it, the same way every time. Stand beside a heavier or higher-leaping opponent and hold (A): they should take it off you. Does losing one read as being out-marked, not as a dropped input? `MarkContest`, `Tuning.MARK_CONTEST_*`.
- [ ] Contested marks where nobody takes it: if the better-rated player's own hands never reach the ball, it goes through the pack and nobody marks. How often does that happen, and does it look right (a spoiled contest) or wrong (a ball you had)?
- [ ] Mark-timing assist (6AF, a test feature, off by default): Settings > HUD STYLE > MARKING > TIMING ASSIST ON. Under a kick the game drops to 0.4x as the press instant comes up, and a small dark graph over your player shows the ball's arc, a window on it and the ball as a dot; press when the dot is in the window (it goes green). Does the slow-down help or annoy, and does it come in early enough (it starts 0.6 s before the press instant)? Does the dot reach the window smoothly, or jump into it at the last moment? Pausing mid slow-down should leave the menus at normal speed. `Tuning.MARK_ASSIST_*`.
- [ ] AI in packs: do AI players still mark often enough around other players (they hold (A) under every ball, so they are in most contests)?

## Section B: fend, fist, snap/banana, call lines (2026-11-11, branch `update`)

- [ ] Fend off (6Y): carrying, tap RB (J) as a tackler closes from in front: your left arm goes out straight (ball in the right hand) and a soft or glancing tackle breaks, the tackler shoved back. A hard square one (~4 m/s+) still holds; from behind a fend does nothing. `Tuning.FEND_*`.
- [ ] Fist away (6Y): in a mark contest (prompt up), tap RB: the ruck-tap leap, and the ball is punched about 9 m/s along the right stick, or on along its line. Knee-high balls go under the leap. Does it read as a fist, not a ruck palm? `Tuning.FIST_*`.
- [ ] Snap / banana (6Z): hold LB (L) while kicking. Aimed 45°+ across your body to the left (right-footer) is a snap: flatter, softer, hooks hard left. Anything else is a banana that bends right a few metres, away from the body (flipped 2026-11-12: it used to bend left like the snap). The trajectory arc shows the bend; check the ball follows it. Everyone kicks right-footed for now. `Tuning.KICK_SNAP_*`, `KICK_BANANA_*`, `BALL_SIDESPIN_MAGNUS_COEFF`.
- [ ] Ruck tap distance (2026-11-11): the tap now leaves at its tuned 6 m/s and first lands ~6 m away; it used to fly ~15 m (a knock() bug doubled it). If it now feels too short, raise `Tuning.RUCK_HIT_OUT_SPEED` (about 12.6 gives back the old tap).
- [ ] Call lines (6V): in single-player control, call for the ball (A): a small "/ | \" shows under your feet for about a second. Big enough?

## Section A small fixes (2026-11-11, branch `update`)

- [ ] Man on the mark (6X): after a mark AND after a free kick for a tackle, the nearest opponent jogs onto the exact spot and stands facing the kicker, turning as the kicker walks back and lines up. No man on the mark for a goal-square kick-in.
- [ ] Settings on a pad (6AB): (A) opens HUD STYLE and REMAP CONTROLS, and (A) cycles a HUD Style option.
- [ ] Remap tabs (6AB): LB / RB (or Tab) swaps KEYBOARD and CONTROLLER; it opens on the device you're using. On CONTROLLER, (A) then any button or trigger rebinds; Start cancels. Check a rebind survives a restart.
- [ ] LB switch on defence (6AB): a quick LB tap without the ball switches to the player nearest it; holding LB and flicking the right stick still bumps and doesn't switch. Never switches while your side has the ball. FULL_TEAM only. `Tuning.DEFENCE_SWITCH_TAP_MAX`.
- [ ] TEAM in FULL GAME (6AC): TEAM is gone from the main menu. FULL GAME opens a side select (your team, opposition; they can't match), then the TEAM page (A continues, B back), then match setup (B goes back to TEAM). The scoreboard and goal banner show the clubs. Career's own screens unchanged.
- [ ] Marking cue size (6T): the X/Y/A badge and ring are about two-thirds their old size. Still readable at FULL SIDE? One dial: `MarkPrompt.CUE_SCALE`.

## The held-up wrestle and contact direction (2026-11-10, branch `update`)

See `docs/ANIMATION_RAGDOLL_AUDIT.md` (last section). Numbers are Tuning's
"The held-up wrestle" and "Direction from the angle of contact".

- [ ] **Held-up tackle, head-on:** the pair fights for a second and the player with the better of the hit walks the other back about half a metre; it reads as a contest, not a slide.
- [ ] **Held-up tackle from the side:** the pair goes off diagonally and the tackler swings round the carrier; neither teleports or spins on the spot.
- [ ] **Held-up from behind:** the carrier drags the tackler on a couple of metres.
- [ ] **Legs in the hold:** the feet step the way the pair moves instead of sliding (`TACKLE_WRESTLE_LEGS`); say if the stepping legs look wrong under the grab and held clips.
- [ ] **Trunks in the hold:** both lean into each other and give when overpowered; the amount (`TACKLE_WRESTLE_LEAN_DEG` 14, `TRUNK_SHARE` 1) looks right.
- [ ] **End of the hold:** both come out of it smoothly, no snap upright and no spin to face the way they were pushed.
- [ ] **Heavy v light (Career weights):** the heavier player wins ground in a hold.
- [ ] **Glancing bump from the side:** the carrier is knocked away from the bumper, not along the bumper's run.
- [ ] **Contested mark, the loser:** watch for the trunk whipping round as they turn away (one sweep row snaps; not fixed).

## Dev tool screens (2026-11-10, branch `update`)

Before and after captures are in `docs/review/devtools/` (720 and 1080).

- [ ] **Animation viewer, CONTESTS:** RESULT sits beside the contest buttons with no scrolling at 1280×720 and 1920×1080; OUTCOME, the A/B lines and the formula lines are readable while the contest plays.
- [ ] **ML page:** every stage's cards, chart and text show in the RESULTS column beside its controls; RUN, TRAIN, APPLY and SAVE still do what they did.
- [ ] **Ragdoll lab:** the menu fits without scrolling and the readout's columns line up.
- [ ] **Keyboard and pad focus (new):** Tab or the d-pad lands on the first button, walks the panel in reading order and shows a rust outline; a mouse click doesn't leave focus behind, so the lab's Space / K / T / L / R still work after one.
- [ ] **FREE MOVE:** pad or keyboard input doesn't press a panel button while you're moving the player.

## Contact on the motor ragdoll (2026-11-10, branch `update`)

See `docs/ANIMATION_RAGDOLL_AUDIT.md` ("Contact on the motor ragdoll").
The animation viewer's CONTESTS tab has a CONTACT panel (B's pace, both
staminas) and reads out what the real tackle decided.

- [ ] **Running into someone:** both torsos give and come back; nobody looks frozen or rubbery. Head-on at a sprint should look like a real knock, a brush hardly anything.
- [ ] **A tackle that breaks:** the carrier rocks forward over the grab and runs on with the ball still in their hands; the tackler is jerked after them.
- [ ] **A held-up tackle (AI Slides, ball-ups):** both stay on their feet but visibly take it; the pair slides on a metre or two instead of stopping dead.
- [ ] **Held-up stand, bump-miss stumble, ruck stagger:** the legs come back under the body rather than staying frozen mid-stride.
- [ ] **Contested marks:** bodies meeting in the contest jolt each other; the catcher's hands stay on the ball.
- [ ] **No snaps:** nothing jerks at the end of a knock (physics fades out over 0.2 s); watch the waist for any gap between shirt and shorts.
- [ ] **Stamina:** late in a long sprint, a knock should look looser than the same knock fresh. Is that noticeable, and is it wanted?
- [ ] **The catcher flung by the ball (fixed):** a fast kick into a pack no longer launches the player who catches it.
- [ ] **Frame rate:** a crowded contest (several knocks at once) doesn't hitch. Each player builds their ragdoll (~1-1.5 ms) on their first knock.

## Build 7 shoulders, idle and the character screen (2026-11-09, branch `build7-polish`)

See `docs/BUILD7_MODEL.md` ("Shoulders, arms and idle") and the images in
`docs/review/7thbuild/shoulders/`.

- [ ] **Build 7 body:** square shoulders that run into the arms, slimmer arms and elbows, a V from chest to waist; it should read closer to Build 6's build.
- [ ] **Armhole edge:** the trim band round each armhole reads as the guernsey's edge at match distance and doesn't flicker when the arms swing.
- [ ] **Raised arms (marks, spoils):** the shoulder cap lifts with the arm; nothing pokes through on top of the shoulder.
- [ ] **Standing idle (Build 7):** arms hang relaxed at the sides with a slow breath, at stoppages and on the character screens; no A-pose.
- [ ] **Tackle on a standing player (Build 7):** the ragdoll starts cleanly from the arms-down idle (no arm snap on the first frame).
- [ ] **CHARACTER screen:** the player stands on Field 1 (the park) under the match sky, centred right of the card; ATTRIBUTES / APPEARANCE tabs switch with Tab / Y or a click; the hint strip is readable.
- [ ] **APPEARANCE zoom:** the whole player, head to boots, is in frame (Career's Create/Edit screens got the same framing).

## Contact (2026-11-09, branch `build7-polish`)

Both builds; see `docs/ANIMATION_RAGDOLL_AUDIT.md`'s Phase 3 section.

- [ ] **Running into a player head-on (no tackle):** both rock back a few degrees and get their hands up to each other, then settle within a second.
- [ ] **Shoulder to shoulder at a sprint:** a small sideways sway on contact, no buzzing while you stay pressed together.
- [ ] **Glancing bump and contest nudge:** the one bumped staggers away from the hit; the nudger rocks back a little.
- [ ] **Ruck shove against the AI:** both ruckmen rock off the contact.
- [ ] **Sway size:** 6° on a head-on jog and up to 18° on a hard knock feel right (PlayerAnimation "Contact reaction").
- [ ] **Build 7 run, arms:** the elbows now point a little differently in the swing (fitted to the ragdoll's elbow); check the swing still looks natural.

## Mark prompt (2026-11-09)

- [ ] **Uncontested chest mark:** the prompt shows (A) from the start, and holding (A) on the ring takes it.
- [ ] **Contested or high ball:** the prompt still shows (Y), and the ring times the leap.

## Build 7 motion (2026-11-09, branch `build7-polish`)

Build 7 only; see `docs/ANIMATION_RAGDOLL_AUDIT.md`'s 2026-11-09 section.

- [ ] **Walk:** a player walking into position plants each foot; no sliding, no shuffling jog.
- [ ] **Jog and sprint:** feet stay put on the turf, the hips turn and the shoulders counter-turn, arms swing evenly.
- [ ] **Accelerating from a stand to a sprint and stopping:** no scissoring or pop between walk, jog and run.
- [ ] **Cuts at a sprint:** the run stays readable through a 90° cut (the bank is unchanged).
- [ ] **Smother dive:** the diver pushes up and runs on, no snap upright at the end.
- [ ] **Tackled (canned and the ragdoll get-up):** the knees never flip to the other side.
- [ ] **Running marks and bounces:** the legs keep the new stride under the catch and the bounce.
- [ ] **Tackles on Build 7:** the first frames of the fall don't snap, and the forearms don't flick (fixed in Phase 3; the hand-off now matches Build 6).
- [ ] **Turning on the spot:** still spins over idle with sliding feet (not fixed yet).

## Build 7 polish (2026-11-08, branch `build7-polish`)

Pick Build 7 on the CHARACTER screen's MODEL row first (Build 6 stays the
default). See `docs/BUILD7_MODEL.md`.

- [ ] **Overall look, chase camera:** a quick-play match reads as athletic AFL players, not mannequins.
- [ ] **Full-side camera:** you can tell the teams apart at a glance, and the guernsey reads as the main colour.
- [ ] **Numbers, chase camera:** each player wears their own number (1-18 by team slot), crisp, the right way round.
- [ ] **Numbers at distance:** they fade out cleanly far away; no shimmer or crawling digits.
- [ ] **Number colour:** dark on a light guernsey, off-white on a dark one; try a mid-tone custom kit near the 0.55 split.
- [ ] **Career match:** players wear their roster numbers, and your player wears the one you chose.
- [ ] **Highlights replay:** bodies in a replay keep their numbers and hair.
- [ ] **Hair:** the colour mix across a team looks natural; nothing pokes through the hair from any angle.
- [ ] **Sprint:** no skin shows at the front of the shorts on a high knee.
- [ ] **Smother dive, tackled, knocked back, takedown:** no skin through the shorts round the crotch or seat.
- [ ] **Marks with arms up:** the shoulders and guernsey yoke hold their shape; no gap at the armpit.
- [ ] **Ragdoll tackles and falls:** limbs, collar and boots stay clean through the fall and the get-up.
- [ ] **Kits:** home, away and a custom kit each recolour every part (guernsey, collar, shorts, socks, boots).
- [ ] **Frame rate:** a full match on Build 7 runs at least as smoothly as Build 6 on your machine.
- [ ] **Character screens:** the preview wears 17 for now (no number is passed to a preview); say if that should change.
- [ ] **Highlights export window:** E / Y or the EXPORT CLIPS button blurs the page and opens the picker; ticking, EXPORT, CANCEL, Esc-to-cancel mid-export and the done message all work with pad, keyboard and mouse, and the files land in `highlights/`.
- [ ] Shoulder push (2026-11-11): run alongside an opponent and lean in — the heavier/fresher one should move the other off their line (~0.2-0.5 m/s), both trunks leaning in. `Tuning.SHOULDER_PUSH_*`; switch off with `SHOULDER_PUSH_ENABLED`.
- [ ] Hands on the body (2026-11-11): in a held-up tackle or a front-on collision the palms should land on the other player's chest, not swing past. `ArmIK`, `PlayerAnimation.CONTACT_HANDS_*`.
- [ ] AI ragdolls you (2026-11-11, 6T): let an AI Slide-tackle you while carrying; a winning sling should put you down on the ragdoll, a stand should hold you up on physics. AI-v-AI tackles stay on clips. Watch how often it fires.
- [ ] AI-v-AI ragdoll tackles (2026-11-11): watch AI Slides on each other; slings should fall on the ragdoll, stands fight on their feet, holds wrestle. Check frame rate with many at once; `Tuning.TACKLE_RAGDOLL_AI_V_AI` turns it off.

## Highlights v2 (2026-11-11)

Needs a real match (or the generator) and the Highlights screen. See `docs/HIGHLIGHTS.md`.

- [ ] **Type toggles:** keys 1-8 (or a click) switch goals, behinds, marks, tackles, bumps, long kicks, rucks and general play. An off type disappears from the list and is never exported; on ticks its best few. The counts look right and the choices are still there after a restart.
- [ ] **Tackles reach an export:** play a half, tick TACKLES, export: `NN_tackle_16x9.avi` clips exist, filmed from behind the tackler. Goals and marks no longer crowd them out of the list.
- [ ] **Third-person camera framing:** behind and above the kicker / marker / tackler, looking the way they run, like the match's chase camera. Check it holds on a turn, when the player stops, and when the ball is in the air. `ReplayStage.THIRD_*`.
- [ ] **Third-person in 9:16:** the narrow frame still holds the tackle (`THIRD_FOV_PORTRAIT`).
- [ ] **Camera pick:** in the export window left / right on a type row changes that type's default, on a moment row changes that moment's camera; both stick.
- [ ] **Format row:** 16:9 only renders roughly half the frames of both shapes (the count line says how many), and no `_9x16` files appear.
- [ ] **General play:** switch it on; clips of a 3+ disposal chain or a bouncing run read as a passage of play, not a random cut. Say if the lead-in is too long or short (`GENERAL_*`).
- [ ] **Goal camera after the score:** the broadcast camera stops following the ball a few metres past the posts and holds, instead of chasing it into the trees or swinging to the centre.
- [ ] **End-on camera:** stays inside the boundary fence on a goal at the far end.
- [ ] **Cancelled export:** cancel part-way; the clip being rendered is in moments.json with `"complete": false` and a smaller `frames`.
- [ ] **Generator** (`scenes/dev/highlight_generator.tscn`, windowed, `--fixed-fps 60`): a run exports goal / mark / tackle clips from mixed cameras into `highlights/generated/`; the footage reads as AI play, and moments.json says `"footage": "generated"`, `"mode": "ai_vs_ai"`.
