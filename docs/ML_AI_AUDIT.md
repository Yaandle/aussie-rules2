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

## 2. Resolving the "515 vs 624 breaks per 1000" discrepancy

The ML doc flags that a seed experiment "previously reported a mean of
624.2 breaks... but the latest verification output reported
approximately 515 breaks per 1,000 trials," and asks for this to be
reconciled against the real Godot model rather than a Python script.
Two findings, from actually running the Godot code:

**a) The model's own math is not the problem.** Running
`tackle_selftest.gd` headlessly (`godot --headless --script
res://scripts/dev/tackle_selftest.gd`) reproduces the Low/Baseline/High
table above exactly — fixed inputs of (0.7, 0.7, 0.7) at the default
weights give 62.25%, matching the "624.2 mean" figure (624.2/1000 ≈
62.4%, within noise of 62.25%). So **the 624.2 figure is correct and
reproducible** — it's a fixed-input, 10-seed sweep (the ML Experiments
page's "10 SEEDS" button at its default slider values does exactly
this).

**b) The 515 figure is almost certainly a different scenario, not a
bug.** The CONTESTS simulation (`animation_viewer.gd:1031`,
`_tackle_model_inputs_for_current_state`) does **not** use fixed
(0.7,0.7,0.7) inputs — it derives `dspeed` and `angle` live from the two
simulated bodies' actual velocities/positions/headings each contest, and
pins `stamina` to a flat `CONTEST_STAMINA_BASELINE = 1.0` (its own
comment admits this: *"baseline stamina value (not tracked in viewer;
use constant)"*). A contest started from a realistic approach (roughly
level speeds, closer to a head-on angle than the doc's "0.7 raw" which
skews favourable to the breaker on all three axes) will produce a lower
z and therefore a lower break rate than the fixed-baseline figure — with
no code defect required to explain the gap. **Recommended check before
trusting either number further:** log the actual `dspeed`/`angle` the
CONTESTS scene produces over ~1000 trials (the print line at
`animation_viewer.gd:1072` already has everything needed) and confirm
its *average* P(BREAK) is consistent with its own inputs, rather than
comparing its break *count* directly against the fixed-input figure.

**c) A real, separate bug found along the way:** `tackle_selftest.gd`'s
own inline comments are stale.
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

**d) A second, independent bug, relevant to Stage 2:**
`TackleExperiment.fit()` (`scripts/dev/tackle_experiment.gd:60`) runs
gradient descent using the **raw, un-normalised** feature values in its
gradient terms (`g0 += err * s.dspeed`, etc.), while the predictions it
fits against (`m.p_break(...)`) always normalise internally. This scale
mismatch means `fit()` cannot reliably recover a generating model's true
weights — exactly the symptom seen in 2(c)'s fit-recovery test. This
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
1. Fix §2(c)/(d) above (stale self-test comments; `fit()`'s
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

## Scope note

Nothing in `scripts/dev/*` or the files discussed above was changed by
this pass — this is an audit only, per the brief that handed it over
("before pushing now do an audit"). The stale-comment and `fit()`
normalisation bugs in §2(c)/(d) are flagged, not fixed; the determinism
question in §3 is flagged, not decided. No gameplay/mechanics files were
modified.
