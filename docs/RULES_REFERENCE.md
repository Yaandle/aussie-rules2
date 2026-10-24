# AFL rules reference

Two halves. **Prototype 1 → Prototype 2** (below) records where each
number came from and how it was translated to real metres. **Core rulebook
v1** (from "Core rulebook v1" on) is the rule set itself — what the game is
meant to do, which module owns each rule, and where the current
implementation and the rulebook disagree.

# Prototype 1 → Prototype 2

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

- Rules that happen to be were written as metres
  and read as logical units — `MARK_STAND_MIN_DISTANCE = 15.0` translates
  1:1. `BOUNCE_INTERVAL` started at the real 15.0 and was later nudged to
  20.0 purely on playtest feel (see its own comment: `_carry_distance` is
  path length, not downfield displacement).
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
| Bounce every 15m while running | `BOUNCE_INTERVAL = 15.0` | `Tuning.BOUNCE_INTERVAL = 20.0` m (feel-raised from 15) | **Enforced.** `PlayerController._track_carry_distance` fires `run_too_far_called` the frame a carry's accumulated path length passes `BOUNCE_INTERVAL` with no bounce (gated out while mid-disposal or stunned); `FullGame._on_run_too_far` awards a free kick to the nearest opponent at the spot via the shared `_award_possession_at` restart, which also walks the receiver back off the mark. `AIBrain` bounces on the run at `Tuning.AI_BOUNCE_AT_FRACTION` × `BOUNCE_INTERVAL`, so in practice this only catches a human who didn't bounce. |
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
| Quarter length | `QUARTER_LENGTH = 180.0` s | `Tuning.QUARTER_LENGTH = 120.0` s | Full Game exists now; 120s is a deliberately short default for one-sitting testing, not a ruling on what a real quarter should be — `QUARTERS_PER_MATCH` stays at the real 4 |

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

---

# Core rulebook v1

Sections 1-11 below are the v1 gameplay rulebook as specified for this
project, merged in 2026-08-27. Everything above this line stays as written
— that is the Prototype 1 → Prototype 2 *translation* record, and it is
still the authority on where a number came from. This half is the *rule
set itself*: what the game is supposed to do, independent of P1.

Where a rule already has an owner in code, the module is named. Where the
rulebook and the current implementation disagree, the disagreement is
flagged inline as **Conflict** rather than silently overwriting either —
these are open items, not settled behaviour.

## 1. Objective

Score more points than the opposition by full time. `MatchState` (score,
clock, quarters), `FullGame` (the match state machine).

## 2. Scoring

- **Goal — 6 pts**: the ball passes between the two goal posts, untouched.
- **Behind — 1 pt**: the ball passes between a goal post and a point post,
  touches a post, or is touched by any player before going through the
  goals.

Owner: `Field`'s three Area3D score triggers per end → `scored(team,
is_goal)` → `FullGame._on_scored` → `MatchState.score()`. Point values are
`MatchState.GOAL_POINTS / BEHIND_POINTS`.

**Conflict — "untouched" is not modelled.** Scoring is decided purely by
which trigger volume the ball enters (`field.gd`, `_add_score_zone`).
There is no touched-off-the-boot downgrade and no post-strike detection,
so a ball deflected by any player, or one that hits a post and goes
through, still registers as a goal. Implementing this needs a "last
touched since the kick" flag on `Ball` (which already tracks
`last_disposer()` / `is_kick_flight()`) and a collider on the posts
themselves.

## 3. Match structure

- 4 quarters, quarter length configurable — `Tuning.QUARTERS_PER_MATCH`
  (4, real) and `Tuning.QUARTER_LENGTH` (120s, a deliberately short
  testing default; see §2 of the translation record above).
- 18 players per team (`Tuning.TEAM_SIZE`, the real number) — was 4 while
  the mode was proven out.
- Centre bounce / throw-up starts each quarter —
  `FullGame._prepare_centre_bounce` → `_begin_ruck_contest`.
- **Centre square (4-player rule).** Real AFL: at a centre bounce only 4
  players per team (the ruck plus 3 on-ballers) may start inside the 50 m
  centre square; the rest start outside it. `FullGame._centre_bounce_slot`
  — roster indices 0-3 take the ruck-contest ring, indices 4+ hold their
  matchday formation slot, which `TeamFormation.ROSTER_ORDER` keeps
  outside the square by construction. **Not policed as a live free kick**
  (there is no umpire adjudication apparatus — same scope note as
  deliberate out-of-bounds); it is only enforced as where players are
  placed for the bounce.
- **After a goal**: ball and teams reset to the middle. Once the reset
  completes, wait roughly **2 seconds longer than current** before
  triggering the ball-up animation — the current gap is too short and
  feels rushed.
- **After a behind**: the defending team kicks in from the goal square,
  with a shorter run-up — `FullGame._prepare_kick_in` (protected kick-in,
  already implemented).

**Done.** The goal restart got its own constant rather than a longer
`SCORE_PAUSE_DURATION`, which is shared with the behind kick-in and is also
the scoreboard flash length. The beat that was rushed is the one *after*
the teams have reset, so `Tuning.GOAL_RESTART_BOUNCE_DELAY`
(`CENTRE_BOUNCE_DELAY + 2.0`) is now passed to
`FullGame._prepare_centre_bounce()`, which takes the delay as a parameter.
`CENTRE_BOUNCE_DELAY` itself was then doubled (1.0s → 2.0s) on further
playtest feedback that every stoppage snapped back into play too fast —
that one is shared by the quarter start, a field ball-up and the
holding-the-ball free kick, so all of them got the same extra beat. Net:
4.0s from the teams resetting to the ball going up after a goal (measured
at 4.02s in a scripted match), 2.0s everywhere else.

On top of that, every ball-up now has the throw-up itself in front of it —
`Tuning.BALL_UP_THROW_DURATION` (1.4s), during which the field umpire
crouches over the ball, holds, and tosses it up. See §7 and §10.

**The ball is locked for the whole dead-ball window**, not merely parked:
`Ball.lock_at()` freezes it kinematic and makes `is_held` report true, so
gathering, marking and hit-outs all refuse until `unlock()`. Playtest
report — players were picking it up off the ground before the umpire had
thrown it. `reset_at()` and `launch()` both unlock, so no call site has to
remember to. Every dead-ball path now locks: the centre bounce and the
restart after a goal, a field ball-up, a boundary throw-in, and out on the
full. Measured end to end: 3.4s dead for a throw-in (2.0s pause + 1.4s
throw), 8.4s from a goal to the next ball-up (3.0s celebration + 4.0s
walk-back + 1.4s throw), and zero frames in which any player held a locked
ball.

**A score is the exception** — `_on_scored` calls `Ball.set_unplayable(true)`
instead of `lock_at()`. That keeps `is_held` true (nobody gathers/marks it,
`_check_out_of_bounds` ignores it) but does *not* pin the transform, so the
ball flies on through the posts under its own physics the way a real one
does rather than freezing on the goal line mid-flight. The restart
(`_rest_ball_at` for a centre bounce, `reset_at` for a kick-in) clears the
flag.

## 4. Ball movement

- **Kick** — the primary way to move the ball a long distance. Drop punt
  only for v1: `Tuning.KICK_BACKSPIN` is the drop punt's end-over-end
  signature, and no other kick type exists.
- **Handball** — short-range pass, punched off the hand
  (`Tuning.HANDBALL_SPEED / _ANGLE / _SPIN`).

Both resolve as real impulses on the `Ball` rigid body; range is an
outcome of the physics, not a capped input (§3 of the translation record).

## 5. Marking (three-tier)

**Trigger condition**: the marking contest icon/UI must appear **only**
when the ball is in flight from a kick.

Tiers:

| Tier | Timing window | Reward |
|---|---|---|
| Standard | routine catch, safe window | no bonus |
| Strong | tighter window | small control/momentum bonus |
| Aggressive | high-risk window | big reward if caught, high fail chance if missed |

A successful mark is free possession — the player can play on or take a
set shot. Owner: `PlayerController._update_marking` (resolution),
`live_mark_prompt()` (which tier the UI recommends), `MarkPrompt` (the
icon/ring itself).

**Walking back off the mark.** A *legal* mark (one that clears
`MARK_STAND_MIN_DISTANCE`, the same test that grants protection and
stand-the-mark) now pushes its taker back before they can go at goal:
`PlayerController._begin_mark_retreat()` drives them
`Tuning.MARK_RETREAT_DISTANCE` (5 m) along their own defensive direction
at `MARK_RETREAT_SPEED`, and the kick is blocked until it finishes. Facing
is deliberately untouched, so they walk back still looking downfield the
way a real kicker does. Handball and simply running are untouched —
"play on" stays available; it is the set shot that has to wait. A
scrambled catch in general play isn't a mark and gets none of this.
Measured: 4.99 m of the 5.0 m target over 1.47s, kick refusing to charge
throughout and charging normally afterwards.

**Fixed.** `live_mark_prompt()` gated on `ball.is_airborne()`, true of any
ball off the ground — so an opponent's handball, or a teammate's handball
going past, lit the prompt in close general play. It now gates on
`Ball.is_kick_flight()`, the same "live, untouched kick" test the
out-of-bounds decision tree uses; the flag clears on landing and on
`knock()`, so a bounced or spoiled ball stops prompting too. Deliberately
gated in `live_mark_prompt()` and *not* in the shared
`_mark_attempt_blocked()`: taking a teammate's handball out of the air is
still a legitimate catch, it just isn't a marking contest — which is
already what `Ball.is_mark_eligible()` says when it decides whether a take
earns real mark protection. Verified with a scripted scenario: the same
ball arriving at the same player shows no prompt as a handball, and
`MARK_SAFE` as a kick.

**Conflict — tier naming.** The code's three tiers are `MARK_SAFE`,
`MARK_RUNNING`, `MARK_AGGRESSIVE`, and the middle one is a *gait*
distinction (a snap-grab taken at pace, chosen by `live_mark_prompt()`
when `_speed > JOG_SPEED`), not a difficulty step between Standard and
Aggressive. The rulebook's Standard/Strong/Aggressive describes a pure
risk ladder. Either the rulebook's "Strong" is a rename of `MARK_RUNNING`
and its "tighter window / small bonus" is the correct description of the
running grab, or a fourth tier is intended. Unresolved — do not rename the
`Action` enum entries in the meantime, they are positionally indexed by
`ACTION_DURATION` / `ACTION_CONTACT`.

## 6. Tackling & contests

- A tackler must be in range of the ball-carrier to attempt a tackle
  (`Tuning.TACKLE_RADIUS`, plus Slide's `TACKLE_SLIDE_DIVE_RANGE` closing
  dash).
- **Tackle animation**: on a successful tackle, hold both players
  physically together for **1-2s** — the ball-carrier should visibly be
  grabbed and hugged, not snap instantly to a resolved state.
- A tackle landed before disposal is a turnover.
- The ball-carrier must dispose within a short window after being tackled
  or concede a free kick (holding the ball) —
  `Tuning.PRIOR_OPPORTUNITY_GRACE`, `MatchState.possession_seconds()`.
- **Bump**: a shoulder charge that can dislodge a ball-carrier or spoil a
  mark attempt. A mistimed bump exposes the bumping player
  (`Tuning.BUMP_MISS_STUN_DURATION`). Bump is flick-gesture driven via
  `InputManager`.

**Done, both halves.** The Slide connect pair (`TACKLE_GRAB` /
`TACKLE_HELD`, and `TACKLE_HELD_STUN_DURATION` with them) went from 0.55s
to 1.0s — inside the asked-for range and still clearly shorter than
Lunge's 1.3s takedown, so the playtest decision that the two tackle types
should feel different survives: it was the gap that carried that read, not
the absolute value. The clips stretch on their own, since
`HumanoidAnimations` builds them from `ACTION_DURATION`/`ACTION_CONTACT`.

The bodies are now genuinely locked together for that window
(`PlayerController._begin_tackle_hold`): the tackler is pinned at
`Tuning.TACKLE_HOLD_DISTANCE` (0.72 m — two 0.35 m capsules, just clear of
interpenetrating) and both players turn to face each other. It is driven
through velocity in `_update_locomotion`, the same "something external owns
the body for a window" branch `_knockback` and the dives already use, so it
still goes through `move_and_slide()` and cannot shove either body into
geometry. The lock releases on its own timer and on `_complete_gather()` /
`set_ruck_contestant()`, since a free kick or a ball-up repositions players
outright and a stale lock would drag them back off the spot. Verified
against five real AI tackles in a headless match: each held exactly 1.00s,
closing from contact range to 0.72 m and staying there.

## 7. Out of bounds (action-system logic)

**Detection rule**: out of bounds is called the instant the ball entity is
fully rolled over the boundary line. This detection belongs directly in
the rules → action system, not as a separate bolted-on check.

Decision tree once out of bounds is called:

1. Is it out on the full?
   - **Yes** → identify which player last kicked it → free kick to the
     opposing team *[action]*.
   - **No** → boundary throw-in, contested *[action]*.

Owner: `FullGame._check_out_of_bounds` → `_trigger_out_on_the_full` /
`_trigger_out_of_bounds`. The throw-in itself is performed by the *field*
umpire, not a boundary umpire — this project resolves the centre bounce, a
field ball-up and a boundary throw-in through one shared contest
(`_begin_ruck_contest`), so one official performs all three. A real
boundary throw-in is the boundary umpire's, thrown over their head from
off the ground; that distinction is not modelled. Out on the full bisects the boundary crossing
between physics frames and awards possession via the shared
`_award_possession_at()` restart; the throw-in routes through the same
`_begin_ruck_contest()` as the centre bounce and a field ball-up.

**Fixed.** The rolled-out case was gated on `_ball.is_settled()`, so a ball
that rolled or bounced over the line kept playing until it came to a
complete stop somewhere outside — exactly the "works for clear kicks,
fails in general play and after a bounce" symptom. `_check_out_of_bounds()`
now tracks the ball's position every live frame and fires on the crossing
itself, bisecting last frame's in-play position against this frame's out
one for the exact spot. "Fully rolled over the line" is one shared
predicate, `_is_in_play()`, which expands the oval test by the ball's own
radius so a ball still fractionally touching the line stays in play; the
bisection uses the same predicate, so the two cannot disagree about where
the line is. The pause/`is_held` re-entry guards are unchanged, and
`is_settled()` survives only as a fallback for a ball that is somehow
already out with no crossing ever observed. Verified with a scripted
scenario: a ball rolling out in general play is now called 0.38s in, while
it is still moving, 0.65 m past the line.

**Partly addressed — still open.** The two tests are now one decision tree
in the order §7 writes it: the ball leaving play is a single call, and only
then does "was it out on the full?" pick the restart, so `_check_out_on_
the_full()` is gone as a separate mechanism. It is still a per-physics-
frame poll inside `full_game.gd` rather than a distinct rules/action
system, because no such system exists here — the "[action]" outcomes map
onto `FullGame`'s `_start_pause(...)` + callback restart shape, which every
other dead-ball moment already uses. Whether that shape should be
generalised into a real action system is a project-wide question, not an
out-of-bounds one.

**Note — "which player last kicked it"** is currently answered by
`Ball.kick_team()` (team, not player) read at the instant of crossing,
because the ball's carrier reference is cleared by `RELEASE_GRACE` well
before a long kick lands. Team is all the free-kick award needs; if the
individual is ever wanted (stats, replays), `Ball.last_disposer()` already
holds it.

## 8. Ball physics

- The ball should bounce slightly higher / livelier after landing from a
  kick than it currently does — `Tuning.BALL_BOUNCE` (restitution off
  turf, currently 0.45).
- Manual bounce (B button): the ball should come back up higher than its
  current bounce height — `Tuning.BOUNCE_SPEED` (8.0 m/s into the turf)
  and `Tuning.BOUNCE_ANGLE` (-52°), resolved against the same
  `BALL_BOUNCE` restitution.

**Done, and tuned together, since they interact** — `BALL_BOUNCE` is the
restitution the manual bounce also rebounds off. `BALL_BOUNCE` 0.45 → 0.55,
and `BOUNCE_SPEED` 8.0 → 10.0 m/s with `BOUNCE_ANGLE` deliberately
untouched, so the up-versus-ahead split that makes a running player run
onto the rebound is unchanged and only the scale grew. The manual bounce
now rebounds at ~4.3 m/s for a ~0.95 m apex before drag, against ~0.4 m
before: chest-high on the run rather than a scuff off the boot. Both are
feel targets, not rule numbers — they want a real playtest, which is the
standing caveat on everything in this project.

## 9. Infringements (free kick to the opposition)

- Out on the full (§7) — **implemented**.
- High contact or in-the-back during a tackle or bump — **not
  implemented**. This is the same open item `FEATURE_AUDIT.md (archived)`
  records as deliberately blocked: there is no AFL rule *number* to judge
  dangerous contact by, so it stays unbuilt pending a real design decision
  rather than getting an invented default.
- Deliberately rushing a behind — **not implemented**, and it depends on
  §2's untracked "who touched it last", since a rushed behind is defined
  by the defender's own deliberate touch.

Holding the ball (§6) is the other free kick and is tracked separately.

## 10. Match officials

- **Boundary umpire**: black/white vertical-striped uniform.
- **Goal umpire**: one stationed in each goal square, behind the goal
  line, in white overalls, holding two white flags — raised to signal a
  goal.

**Done, as cosmetic actors** — `scripts/field/umpire.gd` (`Umpire`), built
by `Field._build_umpires()` alongside the rest of the ground furniture.
Five of them: the **field umpire**, a boundary umpire either side on the
line, and a goal umpire at each end standing 2.5 m behind the goal line,
facing back down the ground.

The field umpire is the one official who moves and the one who actually
puts the ball into play. `FullGame._begin_ruck_contest()` sends him to
whatever the next stoppage is — centre bounce, field ball-up or boundary
throw-in — standing to the side of the two contestants rather than between
them, and he performs the crouch/hold/toss over
`Tuning.BALL_UP_THROW_DURATION` before the ball is released. He wears the
same black-and-white vertical stripes as the boundary umpires (a field
umpire's uniform in the real game, and the one the rulebook describes).

They are built from the same procedural `HumanoidRig` the players use, via
new `kit_torso` / `kit_shorts` / `kit_stripes` overrides on it — the
boundary umpire gets five black vertical stripes over white, the goal
umpire plain white overalls and a white flag in each hand (a pole and a
cloth, parented to the hand bones). On a goal, `Field.scored` raises both
of that end's flags: the two upper-arm bones are posed directly and eased
up over 0.28 s, held for 4 s, then eased back down. The raised pose holds
the arms dead straight, out in front and up (about 35° above horizontal),
in a shallow V so the two flags read as two flags rather than one. The rig has no
`AnimationTree` — an umpire has one moving part, so a whole animation
graph would be machinery for a single lerp.

Deliberately **no collision at all**: a player runs straight through one
and the ball is never deflected. Umpiring decisions are made by `FullGame`
and `PlayerController` as they always were; giving an official a body that
could interfere with play would add a class of physics bug for no rules
benefit. A behind is one flag waved in the real game — not modelled, for
the same reason. The rest of the officiating stays implicit
(`AudioManager.play_whistle()` at each stoppage).

## 11. Player control modes

- **Single Player**: control one on-field player. Call for the ball (A) is
  probability-based, not guaranteed —
  `FullGame._call_for_ball_success_chance()`, tuned by
  `Tuning.CALL_FOR_BALL_*` (base chance modified by pressure, openness and
  range). Explicitly not an AFL rule; `tuning.gd` says so.
- **Full Team**: direct control switches between teammates; AI runs
  everyone else — `ControlMode` (`SINGLE_PLAYER` / `TEAM_COMMAND`),
  `CommandBrain` for the non-selected teammates.

Both modes are implemented and route through the same `PlayerBrain`
interface.
