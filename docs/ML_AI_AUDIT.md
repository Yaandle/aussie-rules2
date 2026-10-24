# ML / AI mechanics audit

Written against two source documents handed to this pass: an internal
"AFL Game AI — Audit, ML Approaches and Stage 1 Progress" writeup (the
"ML doc" below), and a set of ML-methods notes from Dakota Nugent (the
"Dakota notes" below). Scope is gameplay/mechanics + the ML sandbox only
— no UI files touched (see `docs/ui_audit.md` / `docs/RELEASE_NOTES.md`
for the separate 1.2 UI pass this precedes).

## Correction to the Dakota notes: Stage 1 is logistic, not linear

The Dakota notes' analogy table and system-type table both list
**"Linear Regression"** as the Stage-1 / "①" method. That's stale.
Stage 1 was built and completed as **logistic regression** — a sigmoid
over a weighted sum, outputting a 0–1 probability — not a linear
(unbounded, continuous-output) model. This matches the ML doc's own
"Step 2 §1" section title and the actual implementation in
`scripts/dev/tackle_model.gd` (`sigmoid(z) = 1/(1+e^-z)`). Wherever the
Dakota notes' "Linear Regression" language gets carried into a future
doc or slide, it should read "logistic regression" instead — the
underlying worked example (speed/angle/stamina → tackle outcome) is the
same thing the ML doc and the codebase both call Stage 1, already done.

## 1. Stage 1 (logistic tackle model) — verified correct

`TackleModel` (`scripts/dev/tackle_model.gd`) implements exactly what
the ML doc specifies: weights `w_speed=6.0, w_angle=4.0, w_stamina=2.0,
bias=-5.6` over normalised inputs (`dspeed` -2..4, `angle` -2..2,
`stamina` 0..2 → each clamped to [0,1]), `P(BREAK) = σ(w·x_norm + b)`.

Hand-recomputed and confirmed against the ML doc's own verification
table:

| Case | Raw inputs | z | P(BREAK) | Doc's expected |
|---|---|---|---|---|
| Low | (0,0,0) | -1.60 | 16.80% | 16.80% ✓ |
| Baseline | (0.7,0.7,0.7) | 0.50 | 62.25% | 62.25% ✓ |
| High | (1,1,1) | 1.40 | 80.22% | 80.22% ✓ |

All three match exactly. **The model itself is implemented correctly
and matches the documented Stage 1 spec.** It's exercised in three
separate places: `scripts/dev/tackle_selftest.gd` (a standalone
headless CLI check), the animation viewer's ML Experiments page
(`scripts/dev/ml_experiment_viewer.gd` — sliders + a sweep/chart tool,
`SWEEP_VALUES`/10-seed button), and the animation viewer's live
two-body CONTESTS simulation (`scripts/dev/animation_viewer.gd`,
`_compute_tackle_model_prediction`).

## 2. Dev-tooling bugs found while verifying Stage 1

(The ML doc's "515 vs 624 breaks per 1,000" figures were a pair of
numbers tossed out informally, not a real reported discrepancy — nothing
to reconcile there. Running `tackle_selftest.gd` headlessly confirms the
model reproduces the Low/Baseline/High table above exactly at the
documented default weights, so Stage 1's own math is fine. The two bugs
below turned up independently while doing that verification, and stand
on their own regardless.)

**a) `tackle_selftest.gd`'s own inline comments are stale.**
- Line 9: `p_break(2.0, 1.0, 1.0)` is commented `(expect 0.7858)`. The
  current model actually returns **0.9168** for that call (confirmed by
  running it). 0.7858 is exactly what you get from raw, *un-normalised*
  weights `(0.8, 0.2, 0.5, -1.0)` applied directly to inputs (2,1,1) with
  no normalisation step at all (`0.8*2 + 0.2*1 + 0.5*1 - 1.0 = 1.3`,
  `σ(1.3) = 0.7858`) — i.e. this comment documents an **older, pre-
  normalisation version of the model**, never updated when the weights
  were rescaled to the current (6, 4, 2, -5.6) configuration.
- Line 29: the fitter-recovery check prints `(true 0.80, 0.20, 0.50,
  -1.00)` as the generating weights, but the model instance that
  actually generated the synthetic data (`Model.new()`, line 8) uses the
  class's real defaults — 6.0 / 4.0 / 2.0 / -5.6 — not 0.8/0.2/0.5/-1.0.
  Running it confirms this: the fitted weights come back `(6.01, 3.15,
  1.72, -5.02)` — close to the *actual* defaults, not the commented
  "true" values.

Both are comment/documentation bugs, not logic bugs — low risk to fix,
but worth fixing before anyone uses this self-test as a regression
guard, since both of its own stated expectations are currently wrong.

**b) A second, independent bug, relevant to Stage 2:**
`TackleExperiment.fit()` (`scripts/dev/tackle_experiment.gd:60`) runs
gradient descent using the **raw, un-normalised** feature values in its
gradient terms (`g0 += err * s.dspeed`, etc.), while the predictions it
fits against (`m.p_break(...)`) always normalise internally. This scale
mismatch means `fit()` cannot reliably recover a generating model's true
weights — exactly the symptom seen in 2(a)'s fit-recovery test. This
matters for Stage 2: if a genetic algorithm or any other optimiser is
built on top of `TackleExperiment`, this normalisation inconsistency
should be fixed first, or any new fitting path should normalise its
features before computing gradients, the same way `score()` already
does.

## 3. The live gameplay tackle is deterministic by design — not just "pending"

The ML doc's Stage 1 writeup frames live gameplay integration as "a
separate task," still pending. That undersells what's actually there:
the live tackle resolver already exists, and it was **deliberately
built to reject exactly this kind of probability model.**

`PlayerController._resolve_tackle_contact` (`scripts/player/
player_controller.gd:1090`) returns a hard boolean from real physics —
closing speed, approach angle, carrier speed — against fixed thresholds
(`Tuning.TACKLE_SLIDE_MIN_CLOSING_SPEED`, `TACKLE_SLIDE_MAX_ANGLE_DEG`,
etc.). Its own header comment states the design intent explicitly:

> "decided by real closing speed / approach angle / carrier speed at
> contact, never a dice roll (RULES_REFERENCE.md §3 notes Prototype 1's
> old flat TACKLE_BREAK_CHANCE=0.45 coin-flip was deliberately dropped
> for exactly this reason)."

And `docs/RULES_REFERENCE.md` §3 states the project-wide principle this
one mechanic follows: *"contests are decided by collision, timing and
momentum, not by a probability table."* Prototype 1's own
`TACKLE_BREAK_CHANCE = 0.45` coin-flip is listed there as a mechanism
that was **replaced**, not a reference value to port forward.

The Stage 1 logistic model's entire purpose — outputting `P(BREAK)` and
rolling a random draw against it — is structurally the same kind of
mechanism `RULES_REFERENCE.md` §3 already rejected once. Wiring it into
`_resolve_tackle_contact` as literally scoped would reverse a documented
decision, not complete a pending task. Two more supporting facts:

- The model's third input, `stamina`, **has no equivalent anywhere in
  live gameplay.** There is no stamina/fatigue stat on `PlayerController`
  or `CharacterProfile` — the only place `stamina` exists in this project
  is the ML sandbox, where it's always a hand-set constant (the ML
  Experiments page's slider, or the CONTESTS scene's flat
  `CONTEST_STAMINA_BASELINE = 1.0`). A stamina system would need to be
  built before this input meant anything in a real match.
- `dspeed`/`angle`'s live-gameplay analogues (`closing_speed`,
  `approach_angle` in `_resolve_tackle_contact`) already exist and are
  reasonable features to feed a model from — the gap is the output
  (probability vs. threshold gate), not the inputs.

**This needs a decision, not an assumption.** Two honest paths, not a
recommendation to pick one blindly:
1. Keep the logistic model confined to the dev/ML sandbox as a tuning
   and analysis tool — e.g. use it offline to sanity-check or calibrate
   `TACKLE_SLIDE_MIN_CLOSING_SPEED`/`TACKLE_SLIDE_MAX_ANGLE_DEG`'s
   current hand-picked values against a more systematic sensitivity
   model, without ever rolling dice in a real match.
2. Deliberately introduce a bounded probabilistic layer only in a
   narrow "genuinely contested" band near the existing threshold
   boundary (e.g. within some margin of the closing-speed/angle
   cutoffs), leaving clearly-won or clearly-lost contests fully
   deterministic as now. This is a real design change to
   `RULES_REFERENCE.md` §3's stated rule, and should be made as one,
   with the tradeoff written down, not as a side effect of finishing
   Stage 1/2.

Either way, this is the single most important thing to settle before
spending more effort on Stage 2 GA optimisation of a model whose
live-gameplay destination hasn't actually been decided yet.

## 4. AIBrain re-audit: three of the ML doc's five opportunities are already closed

The ML doc's "Where machine learning could help" list (Step 1) describes
`ai_brain.gd` as it was when that audit was written. Re-reading the
current `scripts/mechanics/ai_brain.gd` against that list:

| # | ML doc's finding | Current state |
|---|---|---|
| 1 | Carrier aims toward goal rather than picking a teammate | **Closed (heuristically, not via ML).** `_best_disposal_target` (ai_brain.gd:449) now scores every teammate on forwardness/openness/distance (`AI_DISPOSAL_W_FORWARD/OPEN/DIST = 0.50/0.35/0.15`) and rejects blocked lanes (`_lane_blocked`) before falling back to the old blind kick. |
| 2 | Kick charge is two fixed values, not distance/pressure-aware | **Still open.** Still exactly three fixed fractions: `0.75` (unpressured shot), `0.4` (pressured fallback shot), `AI_PASS_KICK_CHARGE = 0.55` (pass to a teammate). None scale with actual distance or pressure magnitude. |
| 3 | Disposal choice relies on a manually-tuned threshold ladder | **Still open.** `AI_KICK_RANGE` (45m) / `AI_HANDBALL_MAX` (18m) / `pressured` (boolean on `AI_PRESSURE_RADIUS`) are unchanged fixed thresholds. |
| 4 | Off-ball positioning uses a global scalar, no spacing/role awareness | **Partially closed.** `_spacing_push` (ai_brain.gd:524) now nudges a player away from its single nearest teammate inside `AI_SPACING_RADIUS = 4.0m`. Still no role/zone awareness — just pairwise spacing. |
| 5 | Tackle commitment and loose-ball pursuit rely on fixed thresholds | **Partially closed.** `_think_defend` now also requires `keeping_up` (closing-speed comparison, `AI_TACKLE_CLOSING_MARGIN = 0.6`) before committing to a tackle, and `_think_loose_ball` eases to a contain gait rather than sprint-committing into an already-lost race (`AI_LOOSE_BALL_CEDE_MARGIN = 2.0m`). Both are still fixed-threshold heuristics, not learned, but no longer naive. |

Items 2 and 3 (kick power, disposal choice) are the most accurate
still-open opportunities in the original list — genuinely untouched
since the ML doc was written, and the clearest remaining candidates for
a small supervised model (MLP) per the ML doc's own Step 2 §2 proposal.
Items 1, 4 and 5 have already had a pass, so framing them as "where ML
could help" going forward would be re-solving a problem that's partially
or fully gone — reassess the brief's priority order before Stage 2/3
picks a next target.

## 5. Stage 2 (genetic algorithm) readiness

**Architecturally ready.** `TackleModel`'s four `@export` fields
(`w_speed`, `w_angle`, `w_stamina`, `bias`) are already exactly the small
genome both the ML doc and the Dakota notes describe (Dakota's worked
example: genomes `[0.1,0.4,0.5]` / `[0.2,0.3,0.4]` / `[0.4,0.4,0.2]`).
`TackleExperiment.sweep()` already does single-parameter sweeps with a
Wilson confidence interval; a GA just needs to drive that same
evaluate-many-genomes-per-generation loop instead of a hand-picked
sweep list.

**Before building the GA harness itself**, in the order the ML doc's own
"Recommended Next Experiment" section already asks for:
1. Fix §2(a)/(b) above (stale self-test comments; `fit()`'s
   normalisation mismatch) — a GA's fitness evaluation will call the
   same `p_break`/`roll_break` paths, and should not be built on top of
   tooling whose own self-check is currently wrong.
2. Resolve §3 — whether the model's destination is live gameplay at all,
   and if so, where. The GA's fitness function (realistic sensitivity to
   speed/angle/stamina, per the ML doc) depends on knowing what
   "realistic" means for the actual mechanic it will feed, not just the
   standalone model.
3. Only then define the fitness function. The Dakota notes add a
   genuinely useful caution the ML doc doesn't state as explicitly:
   *"50/50 isn't always perfect — hiding bad gameplay... You want = good
   tackle angle + high stamina = Defender wins."* I.e. fitness should
   reward the model being *appropriately sensitive* to each input in the
   right direction, not just converge on an aggregate 50/50 success
   split (a model that's 50/50 regardless of input is a worse outcome
   than one that's 70/30 but correctly swings with speed/angle/stamina).
   Worth folding into whatever fitness function Stage 2 ends up with.

## 6. Stage 2 — implemented

Built on this audit's §5 readiness check:

- **`scripts/dev/tackle_ga.gd`** (`TackleGA`) — the GA core. Genome is
  `{w_speed, w_angle, w_stamina}` (bias held fixed at the model's
  default), matching both planning docs' stated genome shape. Fitness
  (`evaluate()`) scores a genome against the same 5-point scenario
  ladder §1/§5 already use (`extreme_tackle`/`low`/`baseline`/`high`/
  `extreme_break`) via the exact closed-form `p_break()`, not Monte
  Carlo rolls — two terms: `balance_score` (how close the ladder's mean
  tackle-success rate sits to a target, default 55%, per the kanban) and
  `sensitivity_score` (spread between the two extreme corners, penalised
  if the ladder ever runs backwards — "no dominant strategy"). `run()`
  is a standard generational GA: tournament selection, elitism, uniform
  crossover, Gaussian mutation scaled by a `mutation_rate` dial (the
  "one variable to tune" the brief calls out) and a secondary
  `mutation_strength`.
- **`scripts/dev/tackle_ga_selftest.gd`** — headless CLI check (`godot
  --headless --script res://scripts/dev/tackle_ga_selftest.gd
  --quit-after 300`). Confirms a deliberately flat/zero-weight genome
  collapses to near-zero spread (a textbook dominant strategy), and that
  a default 40-genome/40-generation run recovers a genome hitting the
  55% target almost exactly with a 0.99 spread and a correctly-ordered
  ladder (extreme_tackle 0.4% → extreme_break 99.9%).
- **`scripts/dev/ga_fitness_chart.gd`** — a small generation-vs-fitness
  line chart (best + average per generation), separate from
  `tackle_chart.gd` since that one's axes/illustrative line are specific
  to the SWEEP page.
- **ML Experiments page** (`scripts/dev/ml_experiment_viewer.gd`): the
  old static "Stage 1/4 · Logistic regression" caption is now four real
  bookmark buttons (LR / GA / MLP / DQL) that switch the whole page
  content, not just a label — Stage 1's existing MODEL/SWEEP content
  moved into `_build_lr_stage()` unchanged, and a new GA stage page
  exposes every GA parameter above plus RUN, an APPLY TO MODEL button
  (writes the winning genome straight into Stage 1's weight sliders for
  a side-by-side look) and a VERIFY button (1,000 stochastic trials at
  the "baseline" scenario, checked against the closed-form prediction —
  the same sanity-check shape as the SWEEP page's own "10 SEEDS").
- MLP and Deep Q-learning got real, reachable bookmark tabs too, each
  showing a "QUEUED" placeholder listing its planned inputs/fixes (per
  the kanban) and which `ai_brain.gd` gap it targets — infrastructure
  only, no logic yet, as asked.
- Along the way: fixed `tackle_selftest.gd` never calling `quit()` (a
  `--script` run with no explicit quit hangs the process forever — hit
  this firsthand while verifying this pass, confirmed the same mistake
  in the new GA self-test before fixing it there too) and corrected its
  two stale comments flagged in §2(a) to the real, now-verified values.

Verified: headless boot of `scenes/dev/animation_viewer.tscn` (the whole
new UI builds eagerly on scene `_ready()`, not lazily on first open, so
this exercises every new page) and the full project smoke boot — both
exit 0, no script errors. A real bug was found and fixed shortly after
shipping this (see §7) when the user actually opened the panel: the
per-stage container never got `SIZE_EXPAND_FILL`, so LR and GA rendered
empty despite building without error. Confirmed fixed in the editor.

Not done: the live-gameplay determinism question from §3 is still open
and this pass doesn't touch it — the GA stays confined to the dev/ML
sandbox, evolving a model nothing in live gameplay currently reads from.

## 7. GA review: the fitness function underconstrained the problem

Running the GA across six different seeds (same default parameters,
`seed` the only thing varied) turned up a real gap, not just
implementation noise:

| seed | w_speed | w_angle | w_stamina | score | success |
|---|---|---|---|---|---|
| 1 | 4.49 | 3.36 | 3.38 | 0.997 | 55.0% |
| 2 | 8.10 | 2.20 | 0.95 | 0.997 | 55.0% |
| 3 | 8.27 | 0.75 | 3.53 | 0.998 | 55.0% |
| 7 | 8.42 | 0.57 | 3.68 | 0.998 | 55.0% |
| 11 | 5.04 | 2.18 | 4.89 | 0.998 | 55.0% |
| 42 | 6.72 | 1.64 | 3.81 | 0.998 | 55.0% |

Every seed hits essentially the same (near-perfect) fitness score, but
the weights themselves are all over the place — `w_angle` alone ranges
from 0.57 to 3.36, nearly 6×. **The maths explain why:** the original
fitness only ever evaluated the 5-point *ladder*, where dspeed, angle
and stamina all move together from one corner to the other. That
rewards the *aggregate* swing from "tackler-favoured" to "breaker-
favoured," but says nothing about whether each input individually
matters — two strong weights can carry the whole swing while the third
goes nearly to zero, and the ladder-only fitness can't tell the
difference. "No dominant strategy" was only being enforced in aggregate,
not per input, which isn't the same guarantee.

**Fix applied:** `evaluate()` now also computes a per-axis term —
holding the other two inputs at their midpoint, measure each input's
own swing from its low extreme to its high extreme in isolation
(`axis_spreads`), then score the *worst* of the three (not the average
— an average would still let one axis collapse to ~0 as long as the
other two compensate). `score` is now `0.5·balance + 0.25·ladder
sensitivity + 0.25·axis sensitivity` (previously `0.6·balance +
0.4·ladder sensitivity`). Re-running the same six seeds against the
fixed fitness function:

| seed | w_speed | w_angle | w_stamina | score | success |
|---|---|---|---|---|---|
| 1 | 4.49 | 3.37 | 3.36 | 0.919 | 55.0% |
| 2 | 3.71 | 3.72 | 3.69 | 0.930 | 55.0% |
| 3 | 4.15 | 3.52 | 3.51 | 0.924 | 55.0% |
| 7 | 3.64 | 3.60 | 4.00 | 0.927 | 55.0% |
| 11 | 3.51 | 3.87 | 3.65 | 0.924 | 55.0% |
| 42 | 3.74 | 3.71 | 3.66 | 0.929 | 55.0% |

All six seeds now converge to genuinely similar, tightly-clustered
weights (roughly 3.5–4.5 on every axis) — a reproducible result rather
than seed noise, and one where every input demonstrably matters, not
just the aggregate. The max achievable score dropped from ~0.998 to
~0.92-0.93, which is expected and correct: the old fitness was easier to
max out precisely because it didn't check the thing that mattered.

**Conclusion:** the GA itself (selection, crossover, mutation, elitism)
was never the problem — it reliably found whatever the fitness function
actually rewarded, which is exactly what it's supposed to do. The lesson
is squarely about fitness design: a fitness function that only checks
behaviour along one path through input space will happily find a genome
that "games" that one path. Before trusting any future GA result
(Stage 2 or otherwise) as "better than hand-tuned," check whether the
fitness function tests what you actually meant, the same way this one
needed a second pass.

## 8. Applied in practice: the CONTESTS simulation now reads the dialled-in model

Separately from the fitness fix: `scripts/dev/animation_viewer.gd`'s
CONTESTS simulation (`_tackle_model_z_for_inputs`,
`_tackle_model_p_for_inputs`, `_compute_tackle_model_prediction`) always
built a *fresh default-weight* `TackleModel` of its own, regardless of
what was dialled into the MODEL page's sliders. That meant Stage 2's
APPLY TO MODEL button — the whole point of which is "see the evolved
weights in action" — silently changed nothing the simulation actually
used. Added `MLExperimentViewer.get_active_model()`, which builds a
`TackleModel` from the MODEL page's live slider values (w1/w2/w3/bias),
and pointed all three CONTESTS functions at it instead. Dialling a
weight by hand, or running the GA and hitting APPLY TO MODEL, now
genuinely changes what the two-body contest simulation predicts and
rolls — this is the concrete "apply the stage to help the simulation"
step, kept inside the dev/ML sandbox like everything else here (§3's
live-gameplay question is still untouched).

## 9. Stage 3 (MLP): marking-cue timing

Built from `docs/NEXT_AGENT_MARKING_BRIEF.md` Part 2. The MLP placeholder
tab is now a working stage.

### What it predicts

**The model decides only *when* to press, never *whether* a mark
succeeds.** Its output is the number of seconds until the best press for a
tier. Nothing in contest resolution reads it. The catch is still
`_ball_in_catch_reach` plus `_timing_reach_mult` at the real press
(RULES_REFERENCE §3).

The model is `MarkCueModel` (`scripts/mechanics/mark_cue_model.gd`), a
5 → 8 → 8 → 1 network. Its hidden layers use tanh and its output is linear.
It's written in plain packed arrays with a hand-written forward pass and
backprop, trained with Adam from a fixed seed.

"Best press" means the catching press whose contact frame puts the ball
nearest the hands, which is what the brief's "contact frame meets the ball"
asks for. A first version used the centre of the catching band instead.
That version caught as often, but put the ball 1.0–1.6 m from the hands at
contact, where the ring put it 0.5–0.8 m away. The contact minimum sits
early in the band, not in the middle.

Two weight sets are trained:

- **MARK_AGGRESSIVE.** The leap commits `ACTION_CONTACT` (0.4 s) ahead of
  contact, so its cue is a real forward prediction.
- **MARK_RUNNING.** The tap resolves on the frame it's read.

Safe is a held button that catches on reach entry anywhere inside its
0.55 s window, so it has no press instant to learn.

### Inputs

- Ball height.
- Ball distance to the catch point.
- Player speed.
- Time to arrival. This is the analytic `-mark_timing_offset()` itself, so
  the net learns a correction rather than ballistics.
- **Approach cos (the fifth input).** This is cos of the bearing the flight
  comes FROM, in APPROACH FROM's convention. It's the one thing the other
  four can't see: the same distance, height and ETA mean different things
  when the player runs into the flight than when the ball overtakes from
  behind. cos rather than degrees, because left and right are mirror images
  and the value is smooth through 0°.

Both runtime and the harness compute these with
`MarkCueModel.raw_state()`, so the dataset and the live cue can't drift.

### Data

The data is real physics, labelled from real signals
(`scenes/dev/mark_cue_harness.tscn`). Columns are documented in
`data/ml/mark_cue/README.md`.

**Staging.** Each delivery is a real kick flight at a real
`PlayerController` with a HumanBrain-based brain, so it gets the human
timing grade. A press is held live for `INPUT_BUFFER_WINDOW`, exactly like
a real buffered press. Replays of one delivery are bit-identical once the
ball is pinned in the air before launch (the harness's `determinism` mode
checks this). Launching from the ground gave about 1e-4 m of drift through
Jolt's contact warm-start.

**Dataset.** 48 deliveries, Latin-hypercube seeded across:

- bearing: 0–360°
- run speed: 0–8.4 m/s
- arrival height: 0.6–3.2 m
- hang time: 0.9–2.0 s
- kick pace: 12–28 m/s
- lateral miss: ±1.2 m
- lead error: ±1.5 m

That gave **464 real attempts**:

- 416 Aggressive: seed, bracket, bisection and verify presses.
- 48 Running rule checks.

161 of them caught.

**Aggressive label.** For each delivery, bisection finds the outer band.
Every attempt records its ball-to-hands distance on the contact frame. A
quadratic through the catching attempts gives the closest-contact press,
and one more real press verifies it, so the label is always a press a real
attempt caught on.

**Running label.** A Running tap catches exactly when the ball is inside
Running's reach on that frame, because inside that radius
`mark_timing_offset` is 0. So the band and its closest-approach target can
be read straight off the no-press trace. This is checked against real taps,
not assumed: **48/48 agreed**.

### Findings that changed the design

**1. Catching bands have holes.** The ball collides with player bodies
(the ball's collision mask includes the players layer), so a leap at the
wrong instant puts the body in the ball's path. An every-frame sweep of a
knee-high ball at a standing player reads `1111111111..1.1..111111111`. A
label taken from the band's midpoint landed in that hole, which is why
every label is now verified by a real press.

Of the dataset deliveries:

- 35 have a verified Aggressive label (2 with holes).
- 13 have no catching press.

**2. Most of the shipped ring's failures are the range gate, not the ETA.**
On fast run-ins from in front, the analytic ring completes while the ball
is still outside `MARK_CONTEST_RANGE`. The buffered press then expires
before the controller will read it.

`MarkCueModel.press_registers()` copies the controller's own gates into the
cue. With that gate, the ring can't complete until a press could register.
"GATED" is that fix applied to the analytic ring alone, reported separately
so the gate's gain and the model's gain aren't conflated.

**3. The probe grid caught a coverage gap.** The 27-delivery probe grid
covers bearing {0, 90, 180} × run {0, 4.8, 8.4} × height {0.9, 1.8, 2.8},
so each axis is walked end to end (the §7 lesson). The first band search
only seeded presses earlier than closest approach − 0.4 s. On gate-limited
deliveries, where the band starts late, that labelled real bands as
uncatchable, and the "from front, running" corner had almost no training
data. The seeds now start from the gated cue and try later presses first.

### Results

These are seed 1 with defaults (150 epochs, learning rate 0.01, batch 32),
keeping the weights from the best-validation epoch (117). Validation is a
1-in-5 split by delivery: 28 train and 7 val Aggressive deliveries.

**Aggressive.** Each cell is MLP / shipped ring / gated ring.

| | MLP | Shipped | Gated |
|---|---|---|---|
| Val cue in band | 7/7 | 6/7 | 7/7 |
| Val cue error | 0.048 s | 0.067 s | 0.050 s |
| Probe cue in band (trace) | 25/26 | 23/26 | 24/26 |
| Probe cue error | 0.060 s | 0.067 s | 0.063 s |
| **Probe, real presses on each cue** | **25/27 caught** | **23/27** | **24/27** |
| Probe, ball-to-hands at contact (resolved presses) | 1.32 m | 1.15 m (23) | 1.29 m |

- **Caught presses.** Every cue lands within 0.05–0.06 m of the closest
  contact any real attempt achieved on that delivery. The ring's timing is
  already near the physical optimum when it catches.
- **Misses.** Every miss is in the "from front, running" corner:
  - Probe 8 (8.4 m/s, 2.8 m ball) has no catching press at all.
  - The shipped ring's other three misses are presses that expired before
    the gate opened.
- **Seeds.** Seeds 1–5 give 24–25/26 probe in-band and a cue error of
  0.060–0.065 s, so the result isn't seed noise.
- **Axis sweep.** Ball distance (0.66 s) and time to arrival (0.81 s) carry
  the model. Approach cos moves it 0.15 s. Ball height and player speed
  barely do (0.04, 0.03).

**"Off by several tenths".** The analytic countdown's error grows with time
to go:

| Time to best press | Val (MLP / analytic) | Probe (MLP / analytic) |
|---|---|---|
| 0–0.25 s | 0.041 / 0.070 s | 0.080 / 0.067 s |
| 0.5–1.0 s | 0.051 / 0.091 s | 0.071 / 0.083 s |
| 1.0–1.5 s | 0.052 / 0.135 s | 0.072 / 0.172 s |

So on these deliveries it's under two tenths, not several. The MLP's real
gain is a more truthful ring sweep far out. In the final quarter-second on
the probe it is no better than the analytic.

**Running.** The model does not beat the analytic cue:

- Probe cue in band: 26/27 vs 27/27.
- Real presses on the probe: 26/27 vs 27/27.
- Contact distance is the same for both (1.72 m).

Inside Running's reach the time-to-arrival input is pinned at 0, and none
of the five inputs says how deep into the band the ball is. **Running
stays analytic under every cue source.**

### What it's applied to

All of these go through one function, `MarkCueModel.cue_time_to_press()` /
`cue_press_now()`, so the dev pages' numbers are the in-game cue's numbers.

- **MarkPrompt ring and `RUMBLE_MARK_TIMING_CUE`.** `MarkPrompt.cue_source`
  starts from `Tuning.MARK_CUE_SOURCE`, which is **1, GATED** (the
  user's call on 2026-10-24; see "Stage closed" below).
  - 0 = the shipped ring, its arithmetic unchanged.
  - 1 = GATED.
  - 2 = MLP (Aggressive only) plus the gate.
- **Clip start.** Aggressive's clip starts on the press, so the cue's press
  instant is the clip start; its contact frame plays `ACTION_CONTACT`
  later.
  - MARK DELIVERY (animation viewer) has a CUE selector (SHIPPED / GATED /
    MLP). It drives both the scripted press and a real MarkPrompt ring over
    B.
  - Its readout gives the ball-to-hands distance on the leap's contact
    frame.
  - Neither touches real matches.
- **AI, behind `Tuning.AI_MARK_USE_CUE_MODEL = false`.** With the flag on,
  AIBrain stops being Safe-only:
  - It leaps (Aggressive) on a contested kick at the MLP cue.
  - It takes the ball in stride (Running) at pace when a straight-line
    closest approach is inside 0.75 × Running's reach.
  - Otherwise it holds Safe.
  
  The tier choice is a rule; there is no learned catchability.
  
  Headless check, AI marker with a passive opponent at its shoulder, 12
  deliveries:
  - flag off: Safe 11/12 caught
  - flag on: Aggressive 7 caught, 5 missed
  
  So leaping on every contest is worse than Safe against a passive
  opponent. The model was trained on straight-line runs, and an AI arrives
  at odd angles. Leave it off until it has a catchability gate and has
  been played.

### The ML page

The MLP tab has:

- tier, epochs, learning rate, batch, near-press weight and seed controls
- TRAIN, which runs across frames with a live train/validation loss chart
  (`mlp_loss_chart.gd`) and marks the epoch it keeps
- SELF-TEST (gradient check over all 129 parameters, a toy fit, and a
  same-seed reproducibility check)
- held-out cue error against the analytic ring
- the probe-grid region breakdown and the closed-loop line from the last
  harness probe
- APPLY TO PREVIEW, which sets the model MARK DELIVERY's CUE MLP uses this
  session
- SAVE WEIGHTS, which writes `res://data/ml/mark_cue_weights/`

The headless version is `scenes/dev/mark_cue_selftest.tscn`; `-- train`
also saves the weights. A near-press loss weight (rows close to the press
up-weighted) was tried and didn't help either tier, so it defaults to 0.

### Not done, and what's open

- **Catchability.** No "is this catchable" model exists. Choosing the AI's
  tier from one is the obvious next step: 13 of 48 dataset deliveries have
  no catching Aggressive press, so the data is already there.
- **Feel.** None of this has been felt at match speed.

### Stage closed (2026-10-24)

Real matches now cue on **GATED** (`Tuning.MARK_CUE_SOURCE = 1`). It
recovers the shipped ring's expired-press misses on fast run-ins from in
front, with no model in the loop. On the probe it caught 24/27, against
23/27 shipped and 25/27 for the MLP.

What stays as it was:

- The MLP is not in real matches. It's a dev-page option only: MARK
  DELIVERY's CUE MLP, and source 2.
- Running and Safe cue exactly as before. GATED only changes Aggressive.
- The AI is unchanged (`AI_MARK_USE_CUE_MODEL = false`).
- Catch resolution is untouched.

Open:

- A learned catchability model, before any AI tier choice.
- Playtest notes on how the gated ring feels.

## Scope note

§1–§5 were an audit only, per the original brief ("before pushing now
do an audit") — no code changed for those findings. §6–§8 are later,
separate passes that did add code, entirely within `scripts/dev/*` (the
ML sandbox) — no gameplay/mechanics files were touched by any of them.

§9 does touch gameplay files. All of it sits behind switches; since
2026-10-24 the cue switch is on GATED, and the AI switch is still off:

- `mark_prompt.gd`: the countdown now goes through
  `MarkCueModel.cue_time_to_press`, which under source 0 is the ring's
  original arithmetic.
- `ai_brain.gd`: `_think_mark_tier`, gated on `AI_MARK_USE_CUE_MODEL`.
- `tuning.gd`: the two switches plus one feel guess.
- `player_controller.gd`: one comment only.

Catch resolution is untouched.
