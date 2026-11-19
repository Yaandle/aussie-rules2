# Fable 5.2 — Pass 1 prompt (AR2)

Paste everything below the line into a new Code session in
`F:\dev\aussie-rules2` on branch `update`, model Fable 5.2, high effort.

---

You're picking up Aussie Rules 2 (Godot 4.6, Jolt), branch `update`. The
foundation is designed and working; your job is to continue it, not
redesign it. You have this model for a short window, so spend it on the
hard physics and motor-control work, keep everything else lean, and stop at
each checkpoint below with a short report.

## Ground rules

- Read `CLAUDE.md`, then `docs/LESSONS.md`, then only what each phase names.
  Don't open archived docs. Read a script's header before changing it.
- Work on `update`. Commit per phase, your own files only (other sessions
  share this checkout). Never push.
- Verify headless the way `docs/LESSONS.md` describes (scratch scene, not
  `--script`). Say plainly what you measured and what needs my eyes, and
  add each of those to `docs/PLAYTEST_CHECKLIST.md`.
- New feel numbers go in `scripts/tuning.gd`, named, marked "unplaytested
  feel guess". Never rename or renumber `Tuning.Action`.
- Don't touch `TackleBalance`'s formula, `data/ml/tackle_weights.json` or the
  MLP mark cue. Read them; feed from them.
- About 48 checklist items are still unplayed. Don't widen scope beyond this
  prompt; anything you notice goes in your report as a follow-up, not code.

## Architecture principles (the design you're building on)

Written 20/09/26 at the end of my technical architecture study. Every change
should fit them:

1. **Separation of concerns:** logic, rendering, physics and visuals stay in
   their own layers.
2. **Data driven:** telemetry, configs and assets; numbers live in `Tuning`
   or data files, not inline.
3. **Modular and extensible:** features, mechanics and AI plug in without
   rewiring the rest.
4. **Physics is authoritative for gameplay:** contests are decided by bodies,
   mass, speed and timing, never a probability roll
   (`docs/RULES_REFERENCE.md` §3).
5. **Maintainable and scalable:** clean code, short accurate docs.
6. **Rendering and animation are decoupled:** gameplay never reads the
   animated pose; the visual layer follows the simulation.

**Phase 0 (small):** these aren't in the repo yet. Add them as a short
"Architecture principles" section at the top of `docs/LESSONS.md` (one line
each, plus one line on where each shows up in the code). Commit it with
Phase 1.

## Phase 1: dev tool UI consolidation (time-box this; it's the test bench for Phase 2)

Files: `scripts/dev/animation_viewer.gd` (CONTESTS, CONTACT, EXPERIMENTS,
RAGDOLL), `scripts/dev/ml_experiment_viewer.gd`,
`scripts/dev/physics_ragdoll_lab.gd`, and the shared `UIStyle`.

The design is good; keep its look. Fix what's in the way:

- Nothing important below the fold. In CONTESTS the RESULTS panel needs a
  scroll to reach: results must be visible next to the controls that
  produce them at 1920×1080 and 1280×720.
- Audit all three screens together: duplicated controls, inconsistent
  labels, sizes and spacing, contrast, keyboard / controller focus order,
  text that clips. Consolidate shared pieces into `UIStyle` helpers rather
  than copying them.
- Minimal and readable: fewer words on buttons, one clear hierarchy per
  panel, readouts aligned and monospaced where numbers update live.
- No behaviour change to what the contests run. Screenshot before and after
  (windowed run) into `docs/review/devtools/`.

**Checkpoint 1:** commit, then report in five lines or fewer and carry on.

## Phase 2: contact and ragdoll movement (the main job)

Read first: `docs/ANIMATION_RAGDOLL_AUDIT.md` ("Phase 3 contact" and
"2026-11-10: Contact on the motor ragdoll"), `docs/MECHANICS_AUDIT.md` §B4,
then `player_controller.gd`'s contest code, `player_ragdoll.gd`,
`physics_ragdoll.gd` and `TackleBalance`. The regression checks are
`scenes/dev/contact_sweep.tscn` and `scenes/dev/tackle_sweep.tscn`; record
both before you start and after each step.

What I want, in my words: the physics should decide the contest. If the
tackle result is HOLD (players met without enough speed or stamina to knock
either over), both keep their feet and fight for a second, and the pair
moves the way the forces say. If I'm hit from an angle, my body goes in the
direction the physics and the tackle algorithm give, applied through the
players' motor control, not a canned clip. The motion should be fluid in,
during and out of contact.

Build, in this order:

1. **The HOLD wrestle.** Today a held-up tackle puts both trunks on physics
   and brakes the pair out (`TACKLE_HOLD_BRAKE`). Make it a real contest of
   bodies for ~1 s: the pair's shared momentum, mass ratio, stamina tone
   and the angle of contact drive where they go and who gives ground; legs
   step to keep balance rather than sliding. Hand back to locomotion at the
   body's own lean, not upright. The outcome still comes from
   `TackleBalance.balance_loss` and the existing threshold; you're making
   the bodies show it and move by it.
2. **Direction from the angle of contact.** For every knock (tackle, bump,
   nudge, collision), the impulse and the motor targets come from the
   contact normal and the relative velocity, so a hit from the side moves
   me sideways and turns my trunk. Check the side and rear cases in
   `contact_sweep` and add rows for them.
3. **Shoulder-to-shoulder push** (Phase 3 design item 2). Add a sideways
   force between two running players' capsules when they're pressed
   together, sized by mass and closing speed the same way `TackleBalance`'s
   drive is. The heavier or faster player moves the other off their line
   while both trunks lean in through the contact reaction. This changes who
   wins contests: give it its own Tuning constants, a Tuning switch to turn
   it off, and measure how far each side is moved across a sweep. I've
   asked for it, so build it; I'll sign off the numbers in the playtest.
4. **Hands on the other body** (item 3). Solve two-bone arm IK each frame,
   with the same elbow fit as `solve_arm`'s hinge search, aimed at the other
   player's chest or shoulder. Feed the result in as the arm motors' target
   during the knock, so the palms land on the body instead of just swinging
   forward. Keep it a solver with a target point, so the 6Q "hands on a
   wall" idea is the same code with a raycast target later.
5. **If time allows**, in this order: per-limb velocity at a full ragdoll's
   hand-off ("What's left" 3, sampled on `SceneTree.physics_frame`); the
   Build 7 elbow tear at ground impact (3 of 256 falls; profile solver
   iterations against 120 Hz before choosing). Report, don't build, the
   rest.

Also find out, without changing balance, why the AI never lands a ragdoll
tackle on the human (my note 6T). The rule "AI never ragdolls" is
deliberate, so report the cause and the options.

Constraints that bite (all in `LESSONS.md` and memory): Jolt 6DOF joints go
unstable past ~75°; CONE joints explode; joints are built at rest with
anatomical limits; body state reaches nodes a tick late
(`sync_partial_nodes()`); partial-ragdoll bodies touch only the ground.

**Checkpoint 2:** commit after steps 1–2 and again after 3–4. Report each
with the sweep numbers before and after, and the new Tuning constants.

## Phase 3: Build 7 quality pass (only if Phase 2 is done and budget remains)

Read `docs/BUILD7_MODEL.md`. This is an enhancement pass on Build 7
(`7thbuild`) itself, on the same 6thbuild skeleton and clips, so gameplay is
identical. Build 6 stays untouched and selectable. Work through Build 7's
own generator and export scripts (`tools/blender/build_7thbuild_mesh.py`,
`export_7thbuild.py`; Blender at `F:\blender\blender.exe`), never by hand
in the .blend. Use 6thbuild's design as the reference for proportions and
character.

Before building, write a one-page plan of the quality changes (mesh and
silhouette, hands, face and hair, kit shader detail, the elbow and shoulder
deformation at ragdoll limits) and stop for my go-ahead. Afterwards run
`check_7thbuild_deform.py`, render the review sheets, compare against
Build 7 before this pass in `build_compare`, and run `model_cost` against
Build 6.

## Out of scope for this pass

- **ML:** stages 1–3 are closed and Stage 4 (DQL) waits for the playtest.
  Don't build ML. If something you touch reads the ML outputs, say whether
  it still reads them correctly.
- **Game UI and new features:** maths display (6S), switch player on (A)
  (6U), call-for-ball lines (6V), HUD. A cheaper model does those.
- **Fields and venues** (6E), mocap, highlights, Career.

## Final report

Under 20 lines: what's committed (hashes), what you measured, what needs my
eyes (already in `PLAYTEST_CHECKLIST.md`), follow-ups ranked, and a two-line
`docs/LESSONS.md` addition only for lessons that will save the next agent
time.
