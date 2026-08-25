# Feature audit & development roadmap

> **Status (2026-08-21, later same day):** actively being worked through in
> priority order. Done so far: both "implemented but buggy" items; stand-
> the-mark, out on the full, and the general 10m free-kick/mark retreat
> (extending stand-the-mark's freeze mechanism to every nearby opponent,
> not just the direct one — a real, well-known AFL number, unlike bump's
> threshold below); both orphaned screens wired in (`PauseScreen`,
> `MatchEndScreen`); and a full placeholder-SFX pass (`AudioManager`,
> synthesized in code, wired to every mechanic that already had a signal
> for it, plus Master Volume in the settings screen actually made live).
> See `docs/HANDOVER.md`'s matching entries for the full writeup and
> verification detail. Continuing further down the P1/P2 list, also done:
> a third training coach (tackling — run the kick-to-kick rival down
> before it disposes), post-match box-score stats (kicks/handballs/marks/
> tackles, tallied via `MatchState.record_*` and shown on
> `MatchEndScreen`), and a keyboard control-remapping screen
> (`RemapScreen` + `Settings.apply_keybind`, reachable from Settings' own
> now-real REMAP CONTROLS row).
>
> Still deliberately not built: bump's dangerous-
> contact free kick (no AFL rule number exists to judge it by — this is
> the one item on this list that stays blocked on the user rather than
> getting a best-effort default) and a real shot clock / explicit shoot-
> vs-play-on moment (the retreat distance is done; the timing/choice half
> of the set-shot apparatus is pure invented feel, not a rule, so it's
> being left for a deliberate design pass rather than guessed at). AI
> behaviour scope (spoil/smother/bump/hit-out/Running-Aggressive marks)
> also untouched — still the project's own long-standing "not a tactics
> system" decision, not revisited. Real controller hardware verification,
> free player/roster assignment, Goal Kicking mode, real art import, and
> Scenario mode remain open. Everything below is left as originally
> written — strike-through-by-note in the tables, not rewritten — so this
> stays a record of the original audit as well as a live roadmap.

Point-in-time audit of the actual codebase (not `docs/HANDOVER.md`'s prose,
though that was the single richest source and is cited throughout — this
document cross-checked its claims against the current files rather than
trusting them). Methodology: read every gameplay/AI/mode/UI script in full,
read every constant in `scripts/tuning.gd`, read `project.godot`'s input map
and autoloads, and ran the project headless (`--headless --editor --quit` to
force a class-cache rescan, then `--fixed-fps 60 --quit-after 300` against
`full_game.tscn`, `kick_to_kick.tscn`, `main_menu.tscn`, `character_screen.tscn`,
`team_list_screen.tscn`, `settings_screen.tscn`) — all six exit 0, zero
errors, confirming the tree is in a clean, working state as of this pass
(2026-08-21, commit `bbb43d9`).

**The one limitation every session on this project has flagged, this one
included: nobody has ever played this game with a human hand on a keyboard or
a controller.** No GUI/screenshot tool was available here either. Every claim
below about what "works" means "compiles, runs error-free, and was verified
numerically via scripted physics against the real Jolt simulation" — not
"feels right." That gap is itself the top item on the roadmap below.

---

## 1. Feature inventory

### Implemented and working (code-verified, unplayed)

| System | Where | Notes |
|---|---|---|
| Movement/weight model | `player_controller.gd` `_update_locomotion` | Accel/brake asymmetry, speed-coupled turn rate, plant-and-pivot, backpedal + turn-burst. Numerically verified, never felt. |
| Kick (ADS stance + hip-fire) | `player_controller.gd` `_update_charge` | Two-stage LT-hold/RT-tap, aim decoupled from facing (starts from camera yaw), live reversible power off stick/mouse/keyboard, aim-assist toward teammates. |
| Handball, Bounce | `player_controller.gd` `_dispose` | Handball aims at stick direction, bounce is body-forward. |
| Gathering | `_try_gather`, `_update_ground_pickup` | Passive walk-over (speed-scaled lunge) + deliberate ground pickup (wider, faster reach). |
| Marking (3-tier) | `_update_aerial_contest` | Safe/Running/Aggressive, reach-radius tests against live ball position, no RNG. Timing-graded: `PlayerController.mark_timing_offset()` narrows the effective reach off-centre and drops it outside the window entirely (still physical, never a roll) — Running/Aggressive tightly, Safe leniently by design. 15m legal-mark rule (`Ball.is_mark_eligible`) correctly gates stand-the-mark protection. |
| Tackling (Slide + Lunge split) | `_try_tackle`, `_try_lunge_tackle`, `_resolve_tackle_contact`, `_update_slide_dive` | Two commitments sharing one physical resolver (closing speed / approach angle / carrier speed, no RNG). Slide (held, E/B) has a low bar and wide angle tolerance but a real miss cost (`_stun_timer` for `TACKLE_SLIDE_MISS_STUN_DURATION`); its dive-in is a committed dash closing gaps AI pressure otherwise makes unreachable. Lunge (tap, Q/X) needs a steeper closing-speed bar against fast carriers and a narrower angle but only pays a short cooldown on miss, no stun. AI only ever attempts Slide, matching the existing AI scope limit. A successful connect (either kind, not a bump) now plays a real fall/recover clip (`Action.TACKLED`, `HumanoidAnimations._build_tackled`) facing away from the hit — `TACKLE_STUN_DURATION` raised to 1.3s to match. Collision shape stays the standing capsule the whole time; visual-only pass, not yet a gap fix. |
| Spoil, Smother | `_try_spoil`, `_try_smother` | Physical deflect / kick-cancel, both out-of-possession only. |
| Bump | `_update_bump`, `_try_bump` | Real flick-gesture detection (`InputManager.flick_vector`), timing-based clean/mistimed knockback. |
| Ruck contests (unified) | `full_game.gd` `_begin_ruck_contest` + call sites | One mechanic for centre bounce, field ball-up, boundary throw-in. Correct 1-ruck+3-on-baller centre square formation. |
| Scoring + correct restarts | `field.gd` scoring zones, `full_game.gd` `_on_scored` | Goal→centre bounce, behind→protected kick-in — the two are handled differently, correctly. |
| Holding-the-ball ruling + consequence | `_get_tackled`, `full_game.gd` `_on_holding_the_ball` | Ruling and free-kick both fire; stops at "possession + protection at the spot" (no set-shot). |
| Out-of-bounds | `full_game.gd` `_check_out_of_bounds` | Real stoppage (not a silent nudge), resolved through the same ruck contest. |
| Ball physics | `ball.gd` | RigidBody3D, prolate-spheroid hull, quadratic drag, Magnus spin, "catch gravity" marking assist. |
| Full Game mode | `scripts/modes/full_game.gd` | 4-a-side (`Tuning.TEAM_SIZE`), real clock/quarters, AI on every non-human player, player-switch. |
| Kick-to-Kick mode | `scripts/modes/kick_to_kick.gd` | Solo practice + an AI "rival" (stock `AIBrain`) + two training coaches (kicking, marking) with mini-games. |
| AI (baseline) | `mechanics/ai_brain.gd` | Deliberately simple: chase/support/press/dispose state machine. Two Team Edit dials (lateral bias, press intensity) reach it. |
| Camera | `camera/broadcast_camera.gd` | Chase rig (lookahead, ball-focus pull, FOV punch), Full-Side broadcast rig, dialogue two-shot, player-switch pan. |
| Input | `autoload/input_manager.gd` | Full keyboard+mouse+gamepad parity, per-action deadzone/curve, rumble, flick-gesture primitive, device auto-detect. |
| Character screen | `ui/character_screen.gd` | 4 live stats (Speed/Height/Kick Power/Kick Accuracy) against one global `CharacterProfile` — no roster. |
| Team Edit | `ui/team_list_screen.gd` | 3 curated formation presets + Ball Movement + Defensive Pressure, all persisted (`Settings` autoload → `user://settings.cfg`), all actually change HOME's AI/spawn. |
| Scoreboard, DebugHud | `ui/scoreboard.gd`, `ui/debug_hud.gd` | Always-on readout; F3 diagnostic overlay. |
| Main menu, scene transitions | `ui/main_menu.gd`, `autoload/scene_wipe.gd` | Card-based mode select, pixel-wipe transitions. |
| Placeholder humanoid rig | `player/humanoid_rig.gd` | Real `Skeleton3D` + bone-track `AnimationTree`, matches Godot's humanoid bone profile — a genuine drop-in target for a future Mixamo import, not a rebuild. |

### Implemented but buggy

- ~~**`scripts/ui/debug_hud.gd:93`**~~ — **fixed.** The on-screen control
  legend read `"K hold+release kick   Q handball..."`, describing the kick
  model from before the ADS-stance/hip-fire rework, and never mentioned
  spoil/bump/hit-out. Rewritten to match current bindings.
- ~~**`README.md`**~~ — **fixed.** Rewritten wholesale; described the
  milestone-1 state (one player, no menus, "no menus or audio yet", a
  446-line `player_controller.gd`) despite the real file being 1497+ lines
  and the project having had a full menu system, marking, ruck, bump,
  kick-ins, Team Edit and more for a long time.
- Nothing else rose to the level of a functional bug on inspection — this
  project has been unusually disciplined about scripted-physics verification
  after every change (see `docs/HANDOVER.md`'s own recurring "scratch
  harness" methodology). The real risk isn't logic bugs, it's **numbers
  nobody has felt** (below).

### Partially implemented

- **Free-kick / set-shot apparatus** — holding-the-ball, the protected
  kick-in, and boundary throw-ins all stop at "give the ball to the right
  player, protect them for 5s." None of the three ever puts the player into
  an actual "line up a shot on goal" moment — no shot clock, no
  retreat-distance for the opposition, no choice between shooting and playing
  on. This is the single most-repeated "next step" flagged across
  `docs/HANDOVER.md`'s later entries.
- ~~**Stand-the-mark**~~ — **fixed.** `is_protected()`/`grant_protection()`
  stopped the *tackle*, but nothing stopped the marked-against opponent
  simply walking up and repositioning. `PlayerController` now freezes the
  nearest opponent's movement (not their actions) for the same
  `MARK_HOLD_DURATION` window on any legal mark, releasing them early the
  instant the mark-taker disposes. Scoped to marks only — see `docs/
  HANDOVER.md` for why free kicks/kick-ins weren't folded in too.
- ~~**"Out on the full"**~~ — **fixed.** A kick crossing the boundary in the
  air was indistinguishable from a rolled-out ball. `Ball` now tracks which
  team's kick is in flight; `full_game.gd` bisects the boundary-crossing
  frame and awards a free kick to the other side from that point, reusing
  the same possession+protection pattern the kick-in already uses.
- **Bump — dangerous contact** — `bump_landed(bumper, carrier, clean)` fires
  on every connect, but nothing judges whether contact was dangerous enough
  to warrant a free kick, because `docs/RULES_REFERENCE.md` has no
  distance/angle/force threshold to judge by. Deliberately left as a hook,
  not a bug.
- **AI** never attempts Running or Aggressive marks, spoil, smother, bump, or
  a ruck Hit-Out — only Safe marks and standing tackles. This is an explicit,
  repeatedly-documented scope decision ("not a tactics system"), not an
  oversight, but it means a human opponent never sees the AI contest a mark
  aggressively or bump anyone, and a centre-bounce ruck contest is only ever
  actively *palmed* by whichever side has the human in it — the AI ruck
  nominee just falls back to ordinary loose-ball chasing once the ball
  starts coming down.

### Present in code but not exposed to the player

- ~~**`scenes/ui/pause_screen.tscn` / `pause_screen.gd`**~~ — **fixed.**
  Now pushed as a real paused overlay (`get_tree().paused = true` +
  `PROCESS_MODE_ALWAYS`) from both `full_game.gd` and `kick_to_kick.gd`'s
  `pause` handlers, replacing the old instant hard-cut to the main menu.
- ~~**`scenes/ui/match_end_screen.tscn` / `match_end_screen.gd`**~~ —
  **fixed.** `full_game.gd`'s `_finish_match()` now holds the "FULL TIME"
  flash for a few seconds, then hands off to this screen via
  `SceneWipe.change_scene()` instead of flashing forever.
- ~~**Settings screen's first three rows**~~ — **mostly fixed.** Master
  Volume is live (see Audio below); Control Scheme was removed outright
  (it had no real purpose — device switching is already automatic, see
  `InputManager`) and replaced with a real REMAP CONTROLS action row.
  Screen Shake remains the one genuinely inert row — nothing in the
  project reads a screen-shake setting yet.

### Missing entirely

- ~~**Audio.**~~ — **partially fixed.** Placeholder SFX now exist (kick,
  handball, bounce, mark catch/miss, tackle, bump, hit-out, whistle, goal,
  behind, full time), synthesized procedurally in `scripts/autoload/
  audio_manager.gd` and wired to the signals that already existed — no
  imported files, `assets/audio/` still holds only a `.gitkeep`, same
  approach the placeholder rig already uses. Still genuinely missing:
  music, crowd ambience, UI sounds (menu navigation, confirm/cancel), and
  anything mixed beyond a flat master-volume scalar.
- **Scenario mode, Goal Kicking mode** — both are locked entries on the main
  menu (`ui/main_menu.gd`'s `_entries`, `unlocked=false`, `scene_path=""`),
  with zero backing implementation. `data/scenarios/` is empty.
- **Multi-player roster / save-load.** `CharacterProfile` is a single
  session-only global (`autoload/character_profile.gd`) applied to whichever
  human player exists — there is no way to have more than one named,
  persisted player. Team Edit is 3 curated 4-a-side presets, not free
  assignment of named players to any of the 18 real AFL slots
  `TeamFormation` already models.
- **Real character art.** `HumanoidRig` is a real `Skeleton3D` now (a good
  drop-in target — see Technical Opportunities) but every mesh is still a
  primitive box/capsule/sphere; `assets/models/` and `assets/animations/`
  are empty.
- ~~**In-match pause/settings access, a match-end flow.**~~ — **fixed**,
  see "present but not exposed" above.
- ~~**Control remapping UI.**~~ — **partially fixed.** `RemapScreen`
  covers the keyboard binding on every discrete action button. Still
  missing: remapping the movement/camera axes, gamepad bindings, and
  mouse buttons (the last of those was already covered separately by
  `Settings.mouse_kick_swapped`).
- **Any automated test/regression suite.** Every verification pass in this
  project's history has been an ad hoc scratch `.tscn`/`.gd` pair, built,
  run once, and deleted.

### Unclear / needs further investigation

- **Real controller hardware.** Every gamepad binding, every rumble profile,
  every axis index in `project.godot` has shipped without ever being tested
  on physical hardware — every session in `docs/HANDOVER.md` says so
  explicitly. The axis/button indices *look* internally consistent (cross-
  checked against each other repeatedly by past sessions), but "internally
  consistent" and "correct for a real Xbox pad" are different claims.
- **Character-screen jitter.** Investigated at real depth twice; two
  previously-suspected causes (locomotion-blend noise, idle-clip keyframe
  variance) were each numerically proven innocent. If it's still visible, the
  cause is unknown and needs an actual GUI session to even see it.
- **All first-guess tuning constants.** Kick distance was numerically
  corrected once after a real playtest; backpedal speed, turn-burst
  multiplier, tackle-lunge numbers, bump knockback, aim-assist
  strength/cone, and dozens more have never been played, only reasoned
  about. Not a bug list — a "needs a human" list.

---

## 2. Missing features — what would make this feel like a complete prototype

Per the brief's own framing: not "build everything AFL has," but the
smallest set of systems that closes the gap between "a working simulation"
and "a coherent game a person can sit down and play a full match of."
Ranked by how much they're currently costing the experience:

1. **A way to leave and end a match without it feeling broken.** Right now:
   pausing mid-match is indistinguishable from rage-quitting (instant,
   silent, no confirm), and finishing a match dead-ends in a banner that
   never goes away. Both fixes already exist as built screens — this is
   wiring, not design.
2. **A real free-kick/set-shot moment.** AFL's rhythm is built on stoppages
   that turn into a deliberate shot at goal. Today every stoppage resolves
   into "here's the ball, go" — there's no moment where the player lines up
   a kick for goal under a shot clock. This is the biggest *design* gap
   (as opposed to wiring gap) in the core loop.
3. **Any audio.** A silent football match undersells every other system —
   the physical tackle model, the ball's real aerodynamics, the crowd-scale
   AI match — none of it lands the way it should without a whistle, a boot
   connecting, a crowd reacting to a goal.
4. **Stand-the-mark and out-on-the-full.** Two named, spec'd AFL rules that
   are still open; both are small, bounded pieces of work against systems
   that already exist.

Scenario mode and Goal Kicking mode are explicitly *not* on this list —
they're locked for a reason, and building them before the above would be
adding breadth the prototype hasn't earned yet.

---

## 3. Feature opportunities — building on what's already there

Ordered by leverage (cost vs. what it reuses):

- **Wire `PauseScreen` and `MatchEndScreen` in.** Near-zero cost — both
  screens are fully built. `PauseScreen.resume()`'s own header comment
  already documents exactly how to do this (add as a paused `CanvasLayer`
  child of the match scene instead of hard-cutting to the main menu).
- **Basic SFX pass.** Nearly every gameplay moment already emits a signal
  built for exactly this hook: `ball_disposed`, `mark_caught`/`mark_missed`,
  `hit_out_resolved`, `bump_landed`, `holding_the_ball_called`, `Field.scored`,
  `Ball.landed`. An `AudioManager` autoload that just listens to signals
  already wired for other purposes (camera punch, HUD flashes, rumble) could
  cover kick/handball/tackle/mark/goal/whistle sounds without touching a
  single gameplay script.
- **Post-match stats.** Once `MatchEndScreen` is wired, tally disposals/
  marks/tackles per team by counting the same signals above and display them
  there — the data source already exists, it's just never counted.
- **A tackling coach.** The third of the three coaches the design brief
  named from the start. `kick_to_kick.gd`'s `CoachKind` enum and shared
  prompt/dialogue/challenge state machine were explicitly built to take a
  third kind with no restructuring.
- **Free-kick/set-shot apparatus.** Reuse `_protected_timer`/`is_protected()`
  (already the shared primitive for marks, kick-ins, and holding-the-ball) —
  add a shot-clock UI and a "kick for goal vs. play on" input read the same
  way `_update_charge()` already reads kick-stance input.
- **Stand-the-mark.** Reuse `is_protected()` from the *opponent's* side: gate
  the marked-against player's own movement input (or at minimum their
  ability to close distance) while the mark-taker is protected and outside
  15m — the distance/duration numbers already exist.
- **Goal Kicking mode.** `KickChallenge`'s target-ring/hit-tracking
  machinery, already proven in `kick_to_kick.tscn`, is most of what a
  "shots on goal from the arc" mode (the exact menu-card subtitle already
  written for it) would need — swap the downfield ring for `Field`'s
  existing goal geometry and vary the starting distance/angle.
- **Free player assignment in Team Edit.** `TeamFormation`'s 18 real AFL
  slots already exist and are drawn on the whiteboard; the missing piece is
  a per-slot player identity, which needs the roster/persistence system
  below first.

---

## 4. Technical opportunities

- **`README.md` is badly out of date** and is the first thing anyone (human
  or agent) reads. A rewrite against current state would pay for itself
  immediately — `docs/HANDOVER.md` already contains everything needed to
  write it, just not in README form.
- **`docs/HANDOVER.md` is 2889 lines and growing every session.** It's an
  excellent decision log but a poor onboarding document at this size (this
  audit had to read the entire thing to avoid missing scope). Worth
  periodically compressing older entries into a terse changelog and keeping
  the full narrative detail only for the last few sessions.
- **`CharacterProfile` → roster array.** Its own header comment already
  flags this as the natural extension ("this port stops at the single
  always-live profile, since nothing here yet has more than one controllable
  player to apply a roster entry to") — once Team Edit wants named players,
  this is the file that has to change shape first.
- **`Settings` (autoload, `ConfigFile`-backed `user://settings.cfg`) is a
  good, proven persistence pattern** — extend it rather than inventing a
  second mechanism when audio volume, control remaps, or roster data need
  saving.
- **Formalize the scratch-test-scene pattern.** Every session in
  `docs/HANDOVER.md` reinvents a throwaway `.tscn`+`.gd` harness to drive
  real Jolt physics headless, then deletes it. A small checked-in
  `tests/` scene (or even just a documented template) would save real
  time and make the pattern discoverable to a fresh session instead of
  re-derived from this project's memory file each time.
- **`scripts/ui/debug_hud.gd:93`** — trivial, but fix the stale hint text
  while touching that file for anything else.

---

## 5. Priority roadmap

| Priority | Feature | Area | Reason | Complexity | Dependencies |
|---|---|---|---|---|---|
| P0 | ✅ Wire `PauseScreen` into live matches | Global | Esc currently discards a match instantly, no confirm | Low — screen already built | none |
| P0 | ✅ Wire `MatchEndScreen` after full time | Full Game | Match currently dead-ends in a frozen banner forever | Low — screen already built | `MatchState.scoreline()` (exists) |
| P0 | A real human playtest pass (kb + gamepad) | Global | Every tuning number across ~20 systems is unfelt | N/A — not implementation work | none — waiting on the user |
| P0 | ✅ Fix stale `debug_hud.gd` control hints | UI | Diagnostic overlay actively lies about the controls | Trivial | none |
| P1 | ✅ Basic SFX pass (kick/tackle/mark/whistle/goal) | Global | Total silence undersells every physical system already built | Medium | none — hooks existing signals |
| P1 | Free-kick / set-shot apparatus: shot clock + shoot-vs-play-on moment | Full Game | Holding-the-ball/kick-in/throw-in still have no real "line up a shot" beat — the 10m retreat (✅ done) was the ruleable half; the timing/choice half is feel, not a rule | Medium–High | `_protected_timer`, kick-aim system (exist); needs a design pass, not a rule lookup |
| P1 | ✅ Stand-the-mark | Full Game/mechanics | Named AFL rule, open since the mark system's first pass | Medium | `is_protected()` (exists) |
| P1 | ✅ Tackling coach (3rd coach) | Kick-to-Kick | Explicitly planned; pattern proven twice already | Low–Medium | `CoachKind` state machine (exists) |
| P1 | ✅ Post-match stats tally + display | Full Game/UI | High payoff now that `MatchEndScreen` is wired | Medium | `MatchEndScreen` wiring (done) |
| P2 | ✅ "Out on the full" vs. rolled-out distinction | Full Game | Named, spec'd rule, currently unresolved | Medium | boundary detection (exists) |
| P2 | Free player/roster assignment in Team Edit | Team Edit | Currently 3 presets only, no named players | High | new roster/persistence system |
| P2 | ✅ Control remapping screen | Settings/Accessibility | InputMap already supports it; no UI exposes it | Medium | `Settings.gd` pattern (exists) — keyboard only, see below |
| P2 | Real controller hardware verification | Technical | Every gamepad number has shipped unverified, project-wide | Low (verification only) | a physical controller |
| P2 | Goal Kicking mode (unlock) | New mode | Natural extension of `KickChallenge`, already proven | Medium | `KickChallenge`, `Field` scoring zones (exist) |
| P2 | Bump dangerous-contact free kick | Mechanics | Explicitly deferred pending real AFL numbers | Medium | a rule-number decision, then reuses holding-the-ball's pattern |
| P3 | Scenario mode | New mode | Locked, zero spec — lowest priority by the menu's own design | High | scenario design work |
| P3 | Real art import (Mixamo model/animations) | Art | Deliberately deferred; rig already built as a clean swap target | High (art pipeline) | none blocking — sequencing choice |
| P3 | Multi-profile save/roster persistence | Save system | Only matters once free assignment (P2) exists | High | depends on P2 roster work |
| P3 | Automated regression test harness | Technical | Nice-to-have; ad hoc scratch scenes have worked so far | Medium | none |
| P3 | Accessibility (colour/contrast options) | Settings | No evidence of urgency at this stage | Low–Medium | none |

---

## 6. Recommended development order

1. **Core gameplay.** Remarkably complete for this milestone already — don't
   add more mechanics before the ones that exist have been played. The only
   real, named gaps (stand-the-mark, out-on-the-full) are small and can wait
   until after a playtest tells you whether they're the numbers or the rules
   that need attention first.
2. **GameState/match flow.** Wire `PauseScreen` and `MatchEndScreen` first —
   both are essentially free and fix the two worst rough edges a first-time
   player would hit. Then build the free-kick/set-shot apparatus three
   separate systems are already stubbed waiting on.
3. **Kick-to-Kick/testing.** Add the tackling coach — cheap, and this mode is
   explicitly the project's own proving ground, so it's worth keeping it
   ahead of Full Game's own feature set.
4. **Team Edit.** Hold at 3 presets. Don't half-build free assignment without
   a real roster/persistence system underneath it — that's a P2/P3 concern,
   not a quick win.
5. **Full Game.** Post-match stats once `MatchEndScreen` exists; Goal
   Kicking mode as a natural, cheap sibling once the core loop is solid.
6. **AI.** Leave the deliberately-simple baseline alone. It says so in its
   own docstring, and every other item on this list is more urgent than
   teaching it to spoil or bump.
7. **UI/presentation.** Control remapping screen, the stale debug-hud text,
   a `README.md` rewrite.
8. **Polish/accessibility.** Audio belongs here by category but not by
   priority — see P1 above; don't actually leave it until last.
9. **Future.** Scenario mode, real art import, full roster persistence,
   an automated test harness.
