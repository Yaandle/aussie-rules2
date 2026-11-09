# Playtest checklist

Things that need a person playing the game, with one check each. Newest
first. Tick or strike an item when it's been played; anything that fails
goes back to its doc. Older "needs your eyes" lists still live in their
own docs: `ANIMATION_RAGDOLL_AUDIT.md` (kick, carry, phase lock, bank,
tackles), `MECHANICS_AUDIT.md` (ragdoll stages 2-5) and the 2026-10-30
playtest commit (HUD, park turf, ruck, training).

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
