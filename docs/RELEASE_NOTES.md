# Release notes

## v1.4.0 — Career seasons, active ragdoll tackles, new ovals

Everything since v1.2.0 (the 1.3 UI pass was never released on its own).

### Career
- Full 12-round seasons with a ladder and promotion through six leagues,
  per-player season stats, a fixture carousel, a roster grouped by
  position, and continuing a saved career.
- Create Your Player (identity, Easy/Hard, kit), Edit Player with upgrades
  to spend, and Easy/Hard setting the opposition's strength.

### Contests
- Tackles and bumps hand players to an active ragdoll. The X wrap takes
  both players down together, the B sling throws the carrier while the
  tackler stays up, and a clean hit stick ragdolls both. Whether a landed
  tackle holds is the trained tackle model's formula against a threshold,
  never a roll.
- Marks need the hands on the ball. Reach is about an arm's length from
  the hands (it was 2-3 m from the hip), an aggressive leap can take the
  ball across the top of the jump, and a caught ball travels into the
  hands. The AI's marks use the same reach.
- Off-the-ball tackles and late hits give a free kick, a hit on a
  protected player gives a 50. Holding the ball and running too far stop
  the ball for the pause.
- Ruck: only the two ruckmen contest, an early RB press waits for the toss
  to peak, and the right stick aims the tap. Set shots pace back and walk
  in. Kicks after the siren still get their shot.

### Movement and animation
- Drop-punt kick, the ball carried in both hands, phase-locked gaits,
  stride cadence that matches speed, turn bank and drive lean.
- Situational marking variants (low, overhead, over the shoulder).

### Look
- Field 1 park oval and Field 2 bush oval, and kit colours with an away
  kit that contrasts.
- A seven-segment scoreboard (goals | behinds | total, quarter and clock)
  on screen and on the ground's own board.
- The pregame camera preview renders the real ground, lit as in a match.
- The full-side camera's wing is clear of the trees that blocked the play
  at either 50 m arc.
- Camera zoom can be changed from the Full Game pause menu.

### Known follow-ups (not in this release)
- Marking contests on the ragdoll (aggressive marks against an opponent).
- The new mark reach, the AI's lower mark rate and the scoreboard's look
  still need a playtest.

## v1.2.0 — UI & accessibility consistency pass

Focus of this release: presentation only. No gameplay, physics, or AI
behaviour changed. Scope was a full audit of every menu/HUD screen in the
game, closing the accessibility and consistency gaps that audit found, and
a redundant-code sweep of the UI layer.

### Design analysis (what the audit found)

The game already has a deliberate, non-generic UI design system — this was
a consistency and completion pass on top of it, not a redesign:

- Three intentional, documented visual families: **SoftBrutalist** (cream,
  rounded, soft shadow, green accent — quick-play), **RetroWindow** (warm
  parchment, sharp corners, hard offset shadow, rust accent — Settings /
  Pause / Remap / Team List / Character / pregame), and **CareerTheme**
  (dark/tan — Career mode reads as its own mode by design). These stay
  separate; unifying them would undo an intentional decision, not fix a
  bug.
- A real spacing/type scale and shared components (`KeyHintBar`,
  `ActionButton`, `StatRow`, `UIIcon`, `SoftShadow`) already existed and are
  used consistently — no default Godot styling, no generic-AI-UI tells
  (gradients, glassmorphism, uniform rounded cards) anywhere in the project.
- The real gaps were narrower and concrete: device-aware control prompts
  were wired up on only 2 of 11 player-facing screens, several controls
  were reachable by mouse only, one screen (`match_end_screen`) was a
  visually-orphaned placeholder, and one gamepad binding never fired. Full
  detail in `ui_audit.md` (archived).

### Accessibility fixes

- **Device-aware control prompts everywhere.** New shared
  `DeviceHintBar` component (pulled out of `character_screen.gd`'s one-off
  implementation) shows the correct keyboard *or* gamepad glyphs and
  switches live when the last-used input device changes. Rolled out to
  every screen that has a control legend: main menu, Full Game pregame,
  Team List, Character / Career Character, Settings, Remap, Pause,
  Match End, Career Match End, Career Pregame, and Career Dashboard (the
  last of these had no legend at all before).
- **Every control is now reachable without a mouse.** Main menu's
  SETTINGS/EXIT GAME footer, Career Dashboard's VIEW ROSTER, roster-table
  BACK, and locked-overlay MAIN MENU, and both Match End screens' RETURN TO
  MENU control all gained real focus handling (`FOCUS_ALL`, hover ≡ focus
  styling, keyboard/gamepad activation) — previously click-only.
- **Explicit default focus** added on every screen/sub-state that was
  missing it (Career Dashboard's next-game card, roster table, and locked
  overlay), so a keyboard/gamepad player always has something focused to
  start from, with focus correctly returned on close.
- **Two real soft-locks fixed:** a gamepad player opening Remap's
  "press a key" listening mode had no way to cancel it (keyboard-only
  escape path); Career Dashboard's Esc/B shortcut bypassed the roster
  table's own BACK control instead of closing the table first.
- **Dead gamepad binding fixed.** `toggle_opposition` (Team List's
  opposition-overlay toggle) was bound to the D-Pad-Down button, which
  Team List's own row cursor already consumes as "move down" — the action
  could never fire on a gamepad. Rebound to the left shoulder button
  (`project.godot`, consistent with other screens pairing shoulder buttons
  for secondary menu actions) and the on-screen hint corrected to match.

### Visual fix

- `match_end_screen.gd` brought to parity with `career_match_end_screen.gd`
  — RetroWindow shell, selectable/hover RETURN TO MENU row — instead of
  the plain placeholder card it shipped as.

### Redundant code removed

- `character_screen.gd`'s hand-rolled `_hint_sets`/`_apply_hints`/
  `_on_device_changed` glue deleted in favour of the new shared
  `DeviceHintBar` (same behaviour, one copy instead of duplicating it per
  screen going forward).
- No other dead code, unused functions, or duplicated helpers found in the
  UI layer — the existing component set (`ActionButton`, `StatRow`,
  `UIIcon`, `SoftShadow`, `KeyHintBar`) is already reused consistently
  rather than re-implemented per screen.

### Verified

Headless boot of all 12 touched/player-facing UI scenes plus the
rebuilt global class-name cache — all exit clean, no script errors.
Visual/input-feel correctness (focus order, hover styling, exact layout
fit) has not been confirmed in the editor — flag for whoever next opens
the project in a GUI.

### Known follow-ups (not in this release)

- `settings_screen.gd`, `remap_screen.gd`, and `pause_screen.gd` still lay
  out controls by hand-placed `.position` against a fixed 1280×720
  assumption, unlike the container-based layouts `main_menu.gd` /
  `full_game_pregame_screen.gd` / `team_list_screen.gd` already moved to.
  Real robustness gap at other window sizes, but higher risk to migrate
  blind without a GUI to verify in — left for a follow-up pass with
  editor access.
- `debug_hud.gd` (a diagnostic overlay, not player-facing) still carries
  its own independent copy of the device-aware-hint pattern rather than
  using `DeviceHintBar`. Left alone — not worth the risk for consistency
  alone on a dev-only screen.

See `ui_audit.md` (archived) and `HANDOVER.md`'s matching entry for
full file-by-file detail.
