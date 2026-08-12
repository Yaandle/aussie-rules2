# AFL rules reference — Prototype 1 → Prototype 2

Design doc §8: Prototype 1's `settings.py` / `mechanics.py` / `outcomes.py`
are the canonical rules spec. The rule *definitions* are correct AFL-derived
design intent and carry over unchanged; only the *resolution mechanism*
changes, from probability math to physical simulation.

Prototype 1 lives at `E:\aussie-rules_game` and stays intact as living
documentation. Nothing here is ported code.

---

## The unit problem

Prototype 1 ran on abstract "logical units" on a 200×112 pixel grid, with the
oval spanning 166×88 of them. That grid was chosen to suit a fixed 16:9
diorama camera, so its scale is inconsistent on purpose:

- Rules that happen to be *actual AFL metre values* were written as metres
  and read as logical units — `BOUNCE_INTERVAL = 15.0`,
  `MARK_STAND_MIN_DISTANCE = 15.0`. These translate 1:1.
- Rules that had to fit the compressed field were scaled down —
  `SCORING_ARC_RADIUS = 40` is explicitly commented as "the 50m arc".
- Everything else (speeds, ranges, radii) was tuned to feel right on that
  grid and has no defensible metre value at all.

Prototype 2 is 1 Godot unit = 1 metre, so every number has to be classified
before it moves. Three categories below.

---

## 1. Rules that carry over exactly

Real AFL numbers that were already correct.

| Rule | Prototype 1 | Prototype 2 | Status |
|---|---|---|---|
| Bounce every 15m while running | `BOUNCE_INTERVAL = 15.0` | `Tuning.BOUNCE_INTERVAL = 15.0` m | Tracked (`PlayerController.carry_distance`); the free kick for exceeding it waits for match rules |
| Mark from ≥15m triggers stand-the-mark | `MARK_STAND_MIN_DISTANCE = 15.0` | 15.0 m | Not yet implemented — needs two teams |
| Protected/stand-the-mark window | `MARK_HOLD_DURATION = 5.0` s | 5.0 s | Not yet implemented |
| Prior opportunity grace before holding-the-ball applies | `PRIOR_OPPORTUNITY_GRACE = 0.5` s | `MatchState.possession_seconds()` reads against 0.5 s | Timer live, ruling not yet implemented |
| Goal = 6 points, behind = 1 | `outcomes.register_score` | `MatchState.GOAL_POINTS / BEHIND_POINTS` | Live |
| Goal posts 6.4m apart, behind posts 6.4m out again | implied by the diorama draw | `Tuning.GOAL_POST_SEPARATION / BEHIND_POST_OFFSET` | Drawn |
| Goal square 9m × 6.4m | implied | `Tuning.GOAL_SQUARE_DEPTH` | Drawn |
| Centre square 50m | implied | `Tuning.CENTRE_SQUARE_SIZE` | Drawn |

## 2. Rules that carry over, with the number corrected to real metres

The rule is right; Prototype 1's value was compressed to fit its grid.

| Rule | Prototype 1 | Prototype 2 | Why it changed |
|---|---|---|---|
| Scoring arc | `SCORING_ARC_RADIUS = 40` | `Tuning.SCORING_ARC_RADIUS = 50.0` m | P1's own comment calls it "the 50m arc"; 40 was the compressed value |
| Ground size | 166 × 88 units | 165 × 135 m | 88 wide was a 16:9 framing choice, not an aspect ratio any oval has |
| Quarter length | `QUARTER_LENGTH = 180.0` s | `MatchState.QUARTER_LENGTH = 180.0` s | Kept as-is for now; a real quarter is 20 min plus time-on, and this becomes a decision when Full Game exists |

## 3. Rules whose *resolution* changes — the actual point of Prototype 2

Design doc §1/§5: contests are decided by collision, timing and momentum,
not by a probability table. Prototype 1's numbers in this category are
records of a mechanism being replaced, not values to port.

| Prototype 1 | What it did | Prototype 2 |
|---|---|---|
| `MARK_RADIUS = 12.0`, `CONTEST_RADIUS = 10.0` | Positional gates deciding whether a mark counted, then a proximity-weighted roll | Physical: the ball is a rigid body, a mark is catching it |
| `TACKLE_TRIGGER_RADIUS = 3.5`, `TACKLE_BREAK_CHANCE = 0.45` | A radius check, then a flat coin flip | Physical: contact, momentum and the holding-the-ball timer |
| `KICK_BASE_ACC = 0.68`, `KICK_SCATTER_*`, `PRESSURE_*` | Accuracy rolls degraded by nearby opponents, scatter applied to the landing point | Physical: the kick is an impulse; inaccuracy will come from being under pressure while striking it, not from a roll after the fact |
| `BALL_FLIGHT_SPEED = 95.0`, `BALL_BOUNCE_*`, `BALL_ROLL_*` | A scripted lerp along a flight path, plus a cosmetic 2-hop bounce that never moved the ball's real position | `Ball` is a `RigidBody3D`: gravity, quadratic drag, Magnus spin, a prolate-spheroid hull and real restitution |
| `PLAYER_SPEED = 28.0` / `FULL_GAME_PLAYER_SPEED = 19.0` | Units/sec added straight to a position | `Tuning.WALK/JOG/SPRINT_SPEED` = 1.8 / 4.8 / 8.4 m/s, reached through acceleration curves |
| `LOOSE_BALL_GATHER_RADIUS = 4.0` | Positional abstraction for "close enough" | `Tuning.GATHER_RADIUS = 0.85` m — an actual arm's reach |
| `HANDBALL_RANGE = 34.0`, `KICK_MAX_RANGE = 88.0` | Hard caps on how far a disposal could be aimed | No caps: `Tuning.HANDBALL_SPEED` / `KICK_MIN..MAX_SPEED` are launch speeds, and range is whatever the physics produces |

## 4. Rules defined in Prototype 1 and not yet reached

All of these are correct design intent, waiting on the milestone that owns
them. Listed so nothing gets quietly lost.

- **Out on the full** — a kick crossing the boundary in the air is a free
  kick to the other side, taken where it crossed (`OOB_BOUNDARY_INSET`).
- **Boundary throw-in** — a ball that comes down and rolls out is neutral,
  resolved as a contest at that spot.
- **Holding the ball** — tackled after the prior-opportunity grace, judged
  as break-tackle or free kick to the tackler.
- **Ball-up** — tackled inside the grace window, neutral.
- **Scoring arc / angle** — `SCORING_MAX_ANGLE = 55°` off the goal axis
  counted as a shot in P1; in P2 whether it is a goal is decided by where
  the ball physically crosses the line, so the angle gate has no successor.
- **Formation shapes** (`formations.py`) and **scenario `mode_config`
  overrides** — §7 says these carry over almost directly as a data-driven
  pattern once Full Game's core loop works.

## 5. Prototype 1 audit findings worth not repeating

From `most_RECENT_AUDIT.md` (11/08/26), two design lessons rather than bugs
to port:

1. **The scoreboard displayed the opponent's score as a hardwired zero.**
   The root cause was the two teams' scores living in different places.
   `MatchState` routes both sides through one `score()` call for that reason.
2. **A kick landing in a pack could stage a contest between two players of
   the same team**, shutting the kicker's side out entirely. The loose-ball
   code had already solved it; the newer kick-landing code had not. When
   contest resolution is built here, "both sides are represented" belongs in
   one shared place, not re-derived per call site.
