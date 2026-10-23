# Marking-cue dataset (ML Experiments page, MLP stage)

This folder holds real-physics marking attempts recorded headless by
`scenes/dev/mark_cue_harness.tscn` (script `scripts/dev/mark_cue_harness.gd`).
`scripts/dev/mark_cue_trainer.gd` reads them to train `MarkCueModel`. The
background is in `docs/ML_AI_AUDIT.md` §9.

There is a `.gdignore` here on purpose. Without it, Godot imports every CSV in
a `res://` folder as a translation table. `FileAccess` still reads the files in
editor and headless runs. The trained weights live in
`res://data/ml/mark_cue_weights/`, which isn't ignored, so they ship in an
export.

## How to regenerate

```
godot --headless --path . res://scenes/dev/mark_cue_harness.tscn --fixed-fps 60 --quit-after 400000 -- dataset
godot --headless --path . res://scenes/dev/mark_cue_selftest.tscn --fixed-fps 60 --quit-after 100000 -- train
godot --headless --path . res://scenes/dev/mark_cue_harness.tscn --fixed-fps 60 --quit-after 400000 -- probe
```

Each step takes about 30 s. `train` writes the weights that `probe`'s
closed-loop MLP presses use, so run `probe` after `train`.

Everything is seeded. The dataset is a Latin hypercube (seed `20261023`), the
probe is a fixed grid, and physics replays are bit-identical. The harness's
`-- determinism` mode checks that replays match and that a catching band can
have holes.

## How a delivery is staged

A real `Ball` is launched as a kick flight (`is_kick_disposal`). It flies from
`distance` m out on the `from_deg` bearing, released at 1.4 m, and is solved to
reach an aim point at `height` m after `flight_time` s. The aim point is
`lateral` m to the side of the marker's path.

The marker is a real `PlayerController` with a HumanBrain-derived scripted
brain (`AnimationViewer.MarkPreviewBrain`). It runs along −Z at `run_speed`
m/s, timed to reach the catch spot at the planned arrival, offset by `lead` m.

Bearings use the APPROACH FROM convention: 0 = the ball comes from in front of
the marker, 90 = from the right, 180 = from behind.

A press is a tap held for `INPUT_BUFFER_WINDOW` (0.12 s), the same lifetime a
real buffered press gets. Frames are 60 Hz physics frames counted from the
first frame of flight.

## Files

### `deliveries.csv` / `probe_deliveries.csv`

One row per delivery.

| column | meaning |
|---|---|
| `delivery` | id (dataset: Latin-hypercube index; probe: grid index) |
| `from_deg`, `run_speed`, `height`, `flight_time`, `distance`, `lateral`, `lead` | the staging above |
| `closest_frame`, `closest_dist` | frame and distance (m) of the ball's closest approach to the catch point in the no-press trace |
| `aggr_lo`, `aggr_hi` | outermost press frames a real Aggressive press caught on (by bisection); −1 if none |
| `aggr_target` | **the Aggressive label**: a press frame a real attempt caught on, chosen as the one whose contact frame finds the ball nearest the hands (see `_aggressive_label`); −1 if none was verified |
| `aggr_target_contact` | ball-to-hands distance (m) on that attempt's contact frame |
| `aggr_run_lo`, `aggr_run_hi` | the stretch of catching presses the target sits in, bounded by the nearest missed attempts |
| `aggr_holes` | 1 if the band is not one contiguous run (the ball can hit the leaping body) |
| `run_lo`, `run_hi` | Running's band: trace frames with the ball inside Running's reach |
| `run_target` | **the Running label**: the closest-approach frame (a Running tap resolves on the frame it's read) |
| `aggr_analytic_cue`, `run_analytic_cue` | the frame the shipped MarkPrompt ring completes on |

### `trace.csv` / `probe_trace.csv`

Every frame of each delivery's no-press flight. The model's inputs are built
from these rows.

| column | meaning |
|---|---|
| `delivery`, `frame` | which delivery and frame |
| `ball_height` | m above ground |
| `ball_dist` | m from ball to the marker's catch point |
| `player_speed` | m/s, horizontal |
| `cos_bearing` | cos of the bearing the flight comes FROM, relative to the marker's facing |
| `offset_running`, `offset_aggressive` | `PlayerController.mark_timing_offset()` for that tier (1.0 is its not-closing sentinel) |
| `airborne` | 1 while `Ball.is_airborne()` |
| `flight_dist` | `Ball.distance_since_launch()` |

### `attempts.csv` / `probe_attempts.csv`

One row per real press. The label comes from the controller's own
`mark_caught` / `mark_missed` signals.

| column | meaning |
|---|---|
| `set` | `dataset`, `probe`, or `probe_<cue>` for the probe's closed-loop presses |
| `delivery`, `tier` | which delivery and tier |
| `press_frame` | the frame the tap went down |
| `actual_press_frame` | the frame the controller acted on it (−1 if it never did) |
| `outcome` | `caught` / `missed`, or `no_attempt` if no signal fired (for example, the buffered press expired before the range gate opened) |
| `note` | `seed` / `bracket` / `bisect` / `verify` (the band search), `rule_check` (a Running tap checking the trace rule), `cue` (probe closed loop) |
| `contact_dist` | ball-to-hands distance (m) on the frame the outcome fired |
| remaining columns | the trace columns at the press frame |

### `probe_cues.csv`

One real press per probe delivery, per tier, per cue source: `analytic`
(shipped), `analytic_gated`, or `mlp`. Columns are `delivery`, `tier`, `source`,
`cue_frame`, `band_lo`, `band_hi`, `outcome`, and `contact_dist`.
