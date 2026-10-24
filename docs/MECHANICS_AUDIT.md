# Mechanics ("skills") code audit + next-features brief

**Date:** 2026-08-30 · **Branch:** `debug` · Companion to `FEATURE_AUDIT.md (archived)`
(feature inventory / roadmap) and `HANDOVER.md (archived, see docs/LESSONS.md)` (session log).

## Context

Requested pass: audit every player mechanic ("skill" = kick, handball,
bounce, gather, the 3-tier mark, slide/lunge tackle, spoil, smother, bump,
ruck hit-out, locomotion) for **redundant code, efficiency, and
effectiveness**, and stage two larger features for a future agent session —
(1) graphics / computational-demand testing, feeding (2) motion-capture &
animation development. Also records a new intended control (B = evade/fend,
double-tap = spin) and the earlier "vs Madden / NBA 2K / EA FC" benchmarking
context to resume.

Nothing here is a functional bug — the mechanics are code-verified and the
project's scripted-physics discipline has kept logic clean. These are
structural / performance / headroom findings.

---

## Part A — Code audit

> **Progress (2026-08-30):** A1, A2, A6 done — see `HANDOVER.md (archived, see docs/LESSONS.md)`.
> `PlayerRegistry` + `SpatialQuery` (`scripts/ai/`) replaced every
> `get_nodes_in_group(&"players")` gameplay scan; the `&"players"` group is
> gone. `ACTION_DURATION`/`ACTION_CONTACT` are now enum-keyed Dictionaries.
> A3 (contest-resolver extraction) is left for its own session.

### A1. Efficiency — `get_nodes_in_group("players")` is the hot path  ★ highest impact

Every proximity query re-fetches and re-scans the whole players group each
call. At 18-a-side that is 36 nodes, and several of these run **per physics
frame per AI player**:

| File | Sites | When |
|---|---|---|
| `scripts/mechanics/ai_brain.gd` | `_best_disposal_target` (454), `_lane_blocked` (494), `_nearest_opponent_distance_to` (530), `_nearest_teammate` (543), `_spacing_push` (576) | every `update()` — once per AI player per frame, and `_best_disposal_target` calls `_nearest_opponent_distance_to` *inside* its own loop → O(n²) within one call, ~O(n³) across the frame |
| `scripts/player/player_controller.gd` | `_release_frozen_opponents` (~1659), `_nearest_player` (1676, used by `_nearest_opponent`/`_nearest_opposing_carrier`), `ruck_contest_locked` (2223), `_live_ball`/ball group (2278), `_nearest_teammate_for_assist` (2445) | contest/aim/ruck code paths, some per-frame while a contest or kick-aim is live |
| `scripts/ball/ball.gd` | `_nearest_uncontested_catcher` (238) | **every physics frame the ball is airborne** (catch-gravity assist) |

**Fix:** a single per-tick spatial service. Options, cheapest first:
- **Cached team lists.** `ControlMode` already registers both teams
  (`register_team`) and holds `PlayerController` arrays. Expose
  `ControlMode.team_players(team)` / `all_players()` returning the stored
  arrays (no group scan, no per-call allocation) and route every helper
  through it. ~1 hr, no behaviour change, removes the group scans outright.
- **Cache the ball reference.** `_live_ball()` / `ball.gd`'s own lookups
  should resolve once (mode script injects it, as `kick_to_kick.gd` /
  `full_game.gd` already hold `_ball`) instead of scanning a group.
- **Later:** a uniform-grid or `Area3D`-based broadphase if profiling still
  shows contest queries hot after the above. Probably unnecessary at 18v18.

### A2. Redundancy — "nearest X" logic is reimplemented 8+ times

`_nearest_player(max_dist, predicate)` in `player_controller.gd` (allocates a
`Callable` lambda per call), plus five hand-rolled near-identical loops in
`ai_brain.gd`, plus two in `ball.gd`. All do: iterate players → filter by
team / carrying / self → keep min distance.

**Fix:** one module — `scripts/ai/spatial_query.gd` (static, alongside
`team_formation.gd`) — with `nearest(from, candidates, predicate)`,
`nearest_opponent(controller)`, `nearest_teammate(controller)`,
`opponents_within(point, radius)`, `lane_blocked(from, to, radius, team)`.
Takes the cached arrays from A1. Collapses ~120 lines across three files into
~40 and gives contest tuning one place to reason about.

### A3. `player_controller.gd` is 2660 lines / one class, ~14 subsystems

Locomotion + 8 contest mechanics + two-stage kick + gather + ruck +
animation glue + field containment all live in one script. It works and the
brain-query seam (`PlayerBrain`) is clean, but every mechanic change means
navigating the whole file, and the contest resolvers share helpers
(`_knockdown`, `_fall_toward`, `_scatter_from`, `_apply_knockdown_hop`) by
proximity rather than by module.

**Option (medium effort, do only if it keeps paying off):** extract the
contest resolvers into `scripts/mechanics/` units that act *on* a
`PlayerController` — `TackleResolver`, `BumpResolver`, `SmotherResolver`,
`MarkContest`, `RuckContest` — each owning its `_update_*` + `_try_*` +
`_resolve_*` + `_get_*` set and its slice of contact/knockdown helpers.
`PlayerController` keeps locomotion, kick, gather, state, and the signal
surface, and delegates. Keep `PlayerBrain` exactly as is. This is a
refactor, not a feature — schedule it between feature passes, verify with the
existing scratch-scene method per contest.

### A4. Per-frame update fan-out

`_physics_process` unconditionally calls ~11 `_update_*` methods for all 36
players every tick. Most early-return on a cheap check
(`wants_bump_stance()`, `_smother_dive_timer <= 0.0`, etc.), so cost is
low — **not urgent**. If A3 happens, a small dispatch ("only tick the
resolver for the action currently active") falls out of it naturally.

### A5. Animation stack — *not* redundant, it's the planned replacement

`humanoid_animations.gd` (1064), `player_animation.gd` (267),
`humanoid_rig.gd` (331) are the deliberate procedural placeholder. Every
header already documents the mocap seam: `HumanoidRig` is a real
`Skeleton3D` on `SkeletonProfileHumanoid` bone names; `HumanoidAnimations`
writes `"Skeleton3D:BoneName"` bone tracks; `player_animation.gd`'s
`BLEND_POINTS` / state names / public methods are the ones an imported graph
will use. **Do not "clean this up"** — it is Feature B2's input. The one
real debt is `player_animation.gd`'s "NOT YET WIRED: root motion" note:
contest outcomes (tackle/mark end positions) are still script-driven, and §5
wants root motion there.

### A6. `tuning.gd` — the append-only `Action` array landmine

`ACTION_DURATION` / `ACTION_CONTACT` are flat arrays indexed positionally by
the `Action` enum, with a "never reorder" warning. All 17 enum values are
used. Low-risk today but one bad insert breaks every timing silently.
**Optional:** convert the two arrays to `Dictionary` keyed by `Action`
(`action_duration()` / `action_contact_time()` already wrap access, so the
call sites don't change). ~15 min, removes the ordering constraint.

### A7. Smaller items

- `_nearest_player()` allocates a lambda every call — folds away with A2.
- `skeleton_wireframe.gd` is correctly kept off field players (its own
  header explains the per-frame line-rebuild cost) — no action.
- `broadcast_camera.gd`, `mark_prompt.gd`, `debug_hud.gd`, `scoreboard.gd`
  all run `_process` every frame; all are single-target and cheap — no
  action.
- 30 `TODO`/`placeholder`/`for now` markers across `scripts/` — mostly the
  documented "needs a real playtest / needs mocap" kind, not stale code.

### Suggested order for Part A

1. A1 cached team/ball accessors on `ControlMode` (biggest win, no risk).
2. A2 `spatial_query.gd`, migrate the 8 call sites.
3. A6 `Action` dict (quick, removes a footgun).
4. A3 contest-resolver extraction — only if the file keeps getting in the
   way; treat as its own session.

---

## Part B — Next features (for an agent session with fresh context)

### B1. Graphics / computational-demand testing & build

**Goal:** find the compute ceiling — how far the player model, material,
shadow, and animation budget can go before frame time suffers at 36 bodies
on the 165×135 m oval — then rebuild the player model against that budget and
**screenshot old vs new** side by side.

- Reuse `scenes/dev/animation_viewer.gd` (already isolates a single rig and
  its `AnimationTree`, and already spawns a second real `PlayerController`
  for contest previews). Add a **stress mode**: spawn N configurable rigs
  (1 → 36 → 72), toggle shadow map size, MSAA, mesh LOD, material
  complexity; read `Engine.get_frames_per_second()` /
  `Performance.get_monitor(TIME_PROCESS / TIME_PHYSICS_PROCESS /
  RENDER_TOTAL_DRAW_CALLS_IN_FRAME / RENDER_TOTAL_PRIMITIVES_IN_FRAME)` into
  an on-screen readout.
- Run it headless where possible for numeric capture, and in-editor for the
  screenshots (this project has never had a GUI/screenshot pass — see
  `FEATURE_AUDIT.md`).
- **Deliverable:** a short budget note (draw calls / triangles / bones /
  material passes per player that hold 60 fps at 72 bodies with headroom)
  and before/after screenshots of the current primitive rig vs a new one.
- Prior context: sessions *"Game visuals and physics cleanup"*
  (`local_35765e73`), *"Player model and locomotion animation quality"*
  (`local_8933d3bf`), *"Player animation dev screen"* (`local_c42f297b`),
  *"Animation viewer polish"* (`local_8b6aef46`) — the last two built the
  isolate-the-model tooling and already discussed "higher model quality in
  this window only because it's less demanding to render."

### B2. Motion capture & animation development

Leads out of B1 (know the bone/anim budget first).

- **"Can I record and import animations?"** — Yes. Godot 4.6 imports
  skeletal animation via glTF/`.glb` and `.fbx`, and has a built-in **BVH**
  importer. Recording paths: markerless video mocap (Rokoko Video, Move.ai,
  DeepMotion), keyframe-assisted (Cascadeur), or the free Mixamo library —
  all export glTF/FBX/BVH. Retarget onto `HumanoidRig` via Godot's
  **BoneMap** / retargeting in the import dock; the rig was purpose-built on
  `SkeletonProfileHumanoid` bone names so clips land without renaming (see
  `humanoid_rig.gd` header). No gameplay code changes — `player_animation.gd`
  swaps its procedural `_build_*` half for an authored `tree_root`, keeping
  the same blend-point layout, state names, and public methods.
- **Per-player animation style** (players jump / run / kick differently):
  ship 2–3 `AnimationLibrary` variants (or blend-tree pose offsets) and
  select per player from a profile field — the `CharacterProfile` /
  new-`agility`-stat plumbing added 2026-08-30 is the natural carrier; a
  `style` enum alongside `agility` picks the library set at spawn
  (`kick_to_kick.gd` / `full_game.gd._apply_character_profile`).
- **Contact & flow-state improvements** ("more freedom and movement"):
  - Wire **root motion** for contest outcomes (the outstanding
    `player_animation.gd` note) so a tackle/mark visibly decides where
    bodies end up instead of a scripted `_fall_toward` / `_knockdown`.
  - Revisit the contact resolvers (A3) so ball + bodies keep more momentum
    through a contest — carry-through on bumps, ball spill vectors that
    respect the hit, less hard "stop then resolve".
  - Benchmark feel against Madden (hit-stick, gang tackles), NBA 2K
    (contact dribble / collision blending), EA FC (jostling, shielding,
    contextual first touch) — the direction set in the earliest sessions.
- Prior context: *"Tackle and bump animations"* (`local_5acfb635`),
  *"Player model and locomotion animation quality"* (`local_8933d3bf`),
  *"Tackle-split input mechanics"* (`local_85ab740b` — documents how AFL 23 /
  FIFA / Madden handle the input models).

### B3. New control — B = Evade / fend, double-tap = spin

Not yet designed or implemented (grep confirms "fend" appears nowhere in
`scripts/`). Intended: ball-carrier only, `B` tap = a fend/evade (brief
lateral break + push-off), **double-tap `B` = a spin** off the tackle.

Where it wires in, following existing patterns:
- `InputManager` already has a **flick-gesture primitive** (used by bump) and
  buffered-press handling — add a **double-tap detector** there (or a
  generic `consume_double_tap(action)` like `consume_buffered_press`).
- `PlayerBrain`: add `wants_evade()` / `wants_spin()` (base `false`),
  implement in `HumanBrain` (read the tap / double-tap) and leave `AIBrain`
  on the base per the standing AI-scope decision.
- `PlayerController`: an `_update_evade(delta)` in the same shape as
  `_update_bump` — a short committed lateral dash with i-frames against a
  slide tackle for the fend, a ~180° `_heading` sweep + brief speed dip for
  the spin. New `Tuning.Action` values (`EVADE`, `SPIN`) appended to the
  enum + `ACTION_DURATION` / `ACTION_CONTACT` (or the A6 dict), and matching
  entries in `player_animation.gd`'s `ACTION_STATES` once clips exist.
- New `Tuning` block for the numbers (dash distance/speed, i-frame window,
  spin arc, cooldown) with the usual "unplayed feel guess" caveat.

### B4. Physics-driven animation / active ragdoll ("Physics Ragdoll Lab")

**Scope note, written for whoever picks this up (handed to a separate
animation-focused agent, not built in this pass):** this is "Priority 3"
— a larger research problem, distinct from work that produces an asset
usable directly in the game (B1/B2 above, plus whatever the animation
agent's own 6thbuild/tackling-animation work lands). Don't start it
expecting a quick win; it's multi-stage and needs real editor/GUI
iteration to tune (joint limits, motor strength, collision shapes),
which this environment couldn't provide for any of the dev-tooling work
in this file either — same standing limitation.

**The idea (self-preserving ragdoll / active ragdoll):** more than a
conventional ragdoll. Godot already supports physical skeletons
(`PhysicalBoneSimulator3D` / `PhysicalBone3D`), joint constraints and
passive ragdoll simulation out of the box. An **active** ragdoll adds
control forces on top — joint motors that try to maintain or recover a
target pose — while physics still determines the actual outcome. The
distinction that matters: animation supplies an *intention* (the target
pose), physics decides what the body can actually do with it.

How it's meant to work, end to end:
1. **Normal animation** (running, kicking, jumping, contesting) sets the
   target pose, same as today.
2. **Collision and physical state** — measure impact direction, contact
   location, relative velocity, body mass, and current balance at the
   moment of a hit.
3. **Joint motors respond** — apply torques that resist rotation, brace
   the body, reposition limbs, or attempt to recover the target pose.
4. **Physics solver determines the result** — the player may recover
   balance, stumble, twist, fall, or go fully ragdoll. Not a predefined
   hit-reaction clip and not a simple "collapse on hit" ragdoll — the
   impact plus current body state decides the outcome, with the joint
   motors trying to preserve posture throughout.

**Build in stages (do not skip ahead — each stage needs the last
working first):**
1. **Passive ragdoll.** Skeleton, low-resolution collision shapes,
   constrained joints. Confirm the character falls and collides
   correctly before adding any control logic.
2. **Animation-to-ragdoll transition.** Switch from the existing
   animated skeleton to physical simulation during a tackle, then
   restore animation control afterward.
3. **Active joints.** Add motors that attempt to hold a target pose.
   Test whether the player can resist *small* impacts without going
   rigid or unstable.
4. **Impact-aware responses.** Vary the response by contact location,
   impulse, velocity and body orientation — e.g. a lateral impact
   triggers bracing or a balance-recovery attempt specifically, not a
   generic one.
5. **Recovery and control.** Ways to regain a standing posture, protect
   the head/limbs, or transition into a controlled fall rather than a
   flat collapse.

**Stage 1 status (2026-10-20): built.** `scenes/dev/physics_ragdoll_lab.tscn`
(F6 in the editor; not on the main menu) — one passive 6thbuild ragdoll,
knocked over by GO LIMP / PUSH / THROW with an impact bearing, strength and
target part; builder in `scripts/dev/physics_ragdoll.gd`. 14 bodies, ~86 kg,
6DOF ball joints + hinges. Headless sweep at 60 Hz (limp, pushes 150-700 N·s,
balls 8-35 m/s, second hits on a fallen body): no explosions, every body comes
to rest and sleeps in ~3.5-7.7 s, resting floor penetration ~1 cm. Known
limits, all documented in that file's header: PhysicalBone3D's CONE joint is
unstable under Jolt (hence 6DOF); hard landings sink a light link 4-15 cm for
a tick or two; elbows can transiently hyperextend well past their limit on
the hardest hits; a settle/sleep assist is needed because a jointed chain
never quite stops buzzing on its own. 6thbuild used to skin 104 vertices to its
stray `pelvis.001` control bone, which nothing animates (a sliver off the
hips in tackled/tackle_takedown); `export_6thbuild.py` now merges those
weights into Hips and exports only the deform bones, so the lab's re-parent
workaround is gone.

**Deliverable for the first pass:** a small, isolated physics prototype
— a single player reacting to an external impact, not a 36-player match.
Tune joint limits, collision shapes, motor strength and physics
stability in that isolation first; integrating with live gameplay
(tackle/bump contests, `_resolve_tackle_contact` et al.) is explicitly a
later step, after the prototype itself is stable. Motors alone don't
guarantee an intelligent-looking reaction — the control logic on top of
them is real design work, and more advanced recovery behaviour may
eventually be a genuine learned-policy candidate (same DQL direction as
the ML Experiments page's Stage 4, see `docs/ML_AI_AUDIT.md`) rather
than hand-tuned motor logic, once the physical rig itself is solid.

**Parallel research direction (not blocking the above):** player
scanning / automated game-footage analysis — i.e. extracting real
movement or contact data from recorded footage to inform either the
animation clips or the active-ragdoll tuning above, rather than hand-
guessing motor strengths and recovery thresholds. Worth tracking
alongside B2's motion-capture pipeline, not as a prerequisite for
starting B4's stage 1.

---

## Part C — Conversations to resume

Found via transcript search (all in `F:\dev\aussie-rules2` unless noted):

- **Vision / benchmarking vs Madden·2K·EA FC:**
  *"Aussie Rules 2 unified brief implementation"* `local_7d5370b8` (2026-08-21,
  the original brief) and *"Aussie Rules 2 feature audit"* `local_76b75796`
  (2026-08-22, "current mechanics and intended Madden/FIFA-inspired gameplay
  direction").
- **Graphics headroom / model isolation tooling:** `local_35765e73`,
  `local_c42f297b`, `local_8b6aef46`, `local_8933d3bf` (see B1).
- **Animation / contact:** `local_5acfb635`, `local_85ab740b` (see B2).

---

## Part D — ML / AI tackle-model audit

Full writeup moved to its own file: **[`docs/ML_AI_AUDIT.md`](ML_AI_AUDIT.md)**.
Covers: verification of the Stage 1 logistic tackle model
(`scripts/dev/tackle_model.gd`) against its spec (confirmed correct), two
real bugs found in the dev tooling along the way (stale
`tackle_selftest.gd` comments, a normalisation mismatch in
`TackleExperiment.fit()`), the live tackle resolver's
explicit no-probability design decision (`RULES_REFERENCE.md` §3) versus
Stage 1's intent to wire in a probability model, a re-audit of
`ai_brain.gd`'s five ML-opportunity items (three now partly/fully closed
by non-ML heuristics since that audit was written), and a Stage 2
(genetic algorithm) readiness check. Audit only — no gameplay/mechanics
files were changed.
- **AI structure (relevant to A1/A2):** *"Godot AFL AI brain audit and ML
  primer"* `local_a3037e42` (2026-08-29).
