# UI audit (Phase 0)

Written before any code change, per the UI-polish brief's own process. Covers
every screen in `scenes/ui/` plus the shared components in `scripts/ui/`.

## Starting state — read this before the rest of the doc

The brief this audit was written against assumes a generic/default UI built
around "the existing dark palette," with the usual AI-template tells (default
Godot styling, purple/blue gradients, every element a rounded card, etc.).
**None of that describes this codebase.** `docs/HANDOVER.md` records a prior
dedicated "UI & visual quality" pass (and several later mechanics passes that
touched UI alongside it) that already built:

- A real design-token system: `SoftBrutalist` (cream/white, rounded, soft
  blurred shadows, green accent — the quick-play family) and `RetroWindow`
  (warm parchment, sharp corners, hard offset shadow, rust accent — the
  "windowed retro console" family used by Settings/Pause/Remap/Team
  List/Character/pregame). `CareerTheme` is a third, deliberately distinct
  dark/tan palette, documented as intentional: *"Career reads as its own
  mode within the game."* These three palettes, not one, are "the existing
  palette" rule 2 protects — unifying them into one would undo a documented
  decision, not fix a bug.
- A real spacing/type scale (`SoftBrutalist.SPACE_1..7`, `SIZE_DISPLAY`
  down to `SIZE_CAPTION`, tracking that scales down as size goes up, tabular
  numerals via `numeric_font()` for scores/stats).
- Shared components: `KeyHintBar`, `ActionButton`, `StatRow`, `UIIcon`
  (hand-drawn line icons, no art pipeline), `SoftShadow` (real blurred-shadow
  shader, not `StyleBoxFlat.shadow_size`).
- Container+anchor layouts (not hardcoded pixel offsets) on the screens most
  recently rewritten — `main_menu.gd`, `full_game_pregame_screen.gd`,
  `team_list_screen.gd` — specifically to fix overlap/misalignment bugs at
  different window sizes.
- Keyboard/gamepad/mouse parity via a shared "row cursor" pattern (not
  Godot's native focus system, except where noted below) with documented
  hover-syncs-cursor behaviour, animated selection states, and
  `InputManager.device_changed` for last-used-device tracking.

So this is not a ground-up redesign. The real work is a **consistency and
completion pass**: a few screens never got the same treatment the rest did,
and one accessibility requirement from the brief (device-aware prompts) only
got wired up on two of nine player-facing screens. Both are concrete,
scoped, and listed below.

## Palette tokens (already extracted — for reference, not re-invention)

| Family | Background | Panel | Border/Ink | Accent | Muted |
|---|---|---|---|---|---|
| `SoftBrutalist` | `#F4F1EA` (wash `#F9F7F2`→`#EDEAE1`) | `#FFFFFF` | `#16261F` | `#4E9F5B` / `#B8E986` | `#808780` |
| `RetroWindow` | (sits on SoftBrutalist's wash) | `#F3E7CE` | `#1C1A17` | `#C2542F` (shadow `#2F5F5A`) | — |
| `CareerTheme` | `#2A2A2A` | `#D4B5A0` | text `#FEFEFE` / on-panel `#2A2A2A` | positive `#5B7A5E`, negative `#A3503F` | `#B9ADA3` |

Spacing: `SPACE_1..7` = 8/16/24/32/40/56/72px. Radii: `RADIUS_XS/SM/MD/LG` =
7/10/16/22 (SoftBrutalist, rounded) vs. `RetroWindow.RADIUS` = 0 (sharp, by
design — the two families are meant to look different). Type:
`SIZE_DISPLAY/TITLE/HEADING/BODY/LABEL/CAPTION` = 40/30/20/15/13/11.

## Findings, prioritised

### 1. Prompt bar exists but isn't device-aware almost anywhere (accessibility, mandatory per brief)

`KeyHintBar` deliberately takes plain strings and knows nothing about
device — by design, so it *can* show different text per device. Only
**`character_screen.gd`** and **`career_character_screen.gd`** actually wire
that up (`_hint_sets` keyed by `InputManager.Device`, refreshed on
`device_changed`). Every other screen with a hint bar
(`main_menu.gd`, `team_list_screen.gd`, `full_game_pregame_screen.gd`) prints
one static string that mixes both devices ("Enter / A", "↑ / B") instead of
switching glyphs on the last-used input. Even the two screens that *do*
wire it only have a keyboard hint set filled in — the gamepad entry is a
documented TODO (`_hint_sets` comment: "the Xbox bindings are being settled
elsewhere").

**Fix shape:** the pattern already exists and works; it just needs
pulling out of `character_screen.gd` into something every screen can call
(e.g. a small helper that takes a keyboard hint list + a gamepad hint list
and returns a `KeyHintBar` already wired to `device_changed`), then rolling
that out to the five screens below that have a legend at all.

### 2. No prompt bar at all on five screens (accessibility, mandatory per brief)

`settings_screen.gd`, `remap_screen.gd`, and `pause_screen.gd` print a
single static caption line instead of a `KeyHintBar` (so no visual chip
styling, and it never updates with context). `match_end_screen.gd` and
`career_match_end_screen.gd` have **no control legend at all** — nothing on
screen tells a player Enter/A or a click returns to the menu.

### 3. Mouse-only controls a controller/keyboard user cannot reach (accessibility, mandatory per brief)

- `main_menu.gd`'s footer SETTINGS/EXIT GAME — **acknowledged in the code's
  own comment**: *"a keyboard/gamepad user simply cannot reach them yet."*
- `career_dashboard_screen.gd`'s VIEW ROSTER button, the roster table's BACK
  button, and the locked-overlay's MAIN MENU button — all `gui_input`
  click-only, no `focus_mode`, no row-cursor equivalent. (The NEXT GAME card
  on the same screen *does* do this correctly — `FOCUS_ALL` +
  `focus_entered`/`exited` + suppressed default focus box — so the fix is
  "repeat what this screen already does once," not new design.)
- `match_end_screen.gd`'s and `career_match_end_screen.gd`'s RETURN TO MENU
  "buttons" are a static `Panel` with no selected/hover state at all —
  reachable only because `ui_accept`/`pause` are bound globally in
  `_unhandled_input`, with nothing on screen showing the control is focused.
  Fails "focus state must be unmistakable."

### 4. Pixel-position screens vs. container screens (architecture, mandatory per brief)

`main_menu.gd`, `full_game_pregame_screen.gd`, and `team_list_screen.gd` were
each rewritten onto `MarginContainer`/`VBoxContainer`/`HBoxContainer` layouts
specifically because hand-placed `.position` offsets against hardcoded
1280×720 constants caused real overlap bugs (documented in both files'
headers). `settings_screen.gd`, `remap_screen.gd`, `pause_screen.gd`,
`match_end_screen.gd`, and `character_screen.gd`/`career_character_screen.gd`
(their left card's *internal* rows) still position everything by hand
against the same 1280×720 assumption. Low risk at the project's fixed
`canvas_items` stretch mode, but it is the one place the brief's "adapts
from 16:9 to ultrawide/720p" requirement is genuinely unverified, and it's
inconsistent with the newer screens' own stated reason for moving off it.

### 5. `match_end_screen.gd` is a visually-orphaned placeholder

Its own header calls it a placeholder: a plain `SoftBrutalist` cream rounded
card with no hover/cursor state, no hint bar (#2/#3 above), built from raw
offsets (#4). Every sibling screen it could be compared to
(`career_match_end_screen.gd`, which shows the same scoreline+stats shape)
already moved to a more finished treatment. Cheapest fix: bring it to parity
with the rest of the quick-play family (RetroWindow shell, selectable/hover
RETURN TO MENU row, `KeyHintBar`) rather than a new design.

### 6. Everything else checked and found fine

- `UIIcon`, `ActionButton`, `StatRow`, `SoftShadow`, `RetroWindow`,
  `SoftBrutalist`, `CareerTheme`, `KeyHintBar` — consistent, documented,
  reused correctly everywhere; no changes needed.
- No default Godot theme look anywhere; no purple/blue gradients; no
  glassmorphism; accent colour used sparingly; type hierarchy and letter-
  spacing already systematic.
- `remap_screen.gd`'s two-column list, `settings_screen.gd`'s live camera
  preview, `full_game_pregame_screen.gd`'s two-level card cursor, and
  `career_pregame_screen.gd`'s side-by-side live camera panels are all
  genuinely good, non-generic interaction design already — no "fewer
  choices per screen" work needed there.
- `career_pregame_screen.gd` and `career_dashboard_screen.gd`'s zoom
  chevrons are the one place Godot's *native* focus system is used instead
  of the row-cursor pattern, deliberately (documented: no existing cursor
  reaches that control). Consistent within itself; not a bug.

## Not touched by this audit

Gameplay HUD overlays reached only during a live match
(`scoreboard.gd`, `debug_hud.gd`, `mark_prompt.gd`, `kick_crosshair.gd`,
`controlled_player_ring.gd`, `camera_mode_preview.gd`,
`formation_whiteboard.gd`) were skimmed, not read in full — they're
"anything else... HUD frame elements," the brief's own lowest-priority
catch-all, and nothing in them stood out as broken. Worth a pass in Phase 5
if time remains, not before.

## Proposed order of work

1. Pull `character_screen.gd`'s device-aware hint pattern into a shared
   helper; add gamepad hint text (currently missing even where the
   mechanism exists).
2. Roll real `KeyHintBar` + device-aware hints onto `settings_screen.gd`,
   `remap_screen.gd`, `pause_screen.gd`, `match_end_screen.gd`,
   `career_match_end_screen.gd`, `career_pregame_screen.gd`.
3. Give every mouse-only control listed in §3 the same `FOCUS_ALL` +
   suppressed-focus-stylebox + hover-tint treatment
   `career_dashboard_screen.gd`'s NEXT GAME card already proves.
4. Bring `match_end_screen.gd` to visual/interaction parity with
   `career_match_end_screen.gd` (RetroWindow shell, selectable return row).
5. Only if time remains: migrate `settings_screen.gd`/`remap_screen.gd`/
   `pause_screen.gd` off hand-placed `.position` onto the container pattern
   `main_menu.gd` already established, for the same overlap-safety reason.

## Status after this pass

Items 1–4 done; see `docs/HANDOVER.md`'s matching entry for the full list of
files and the fixes found along the way that weren't in the original audit
(main_menu.gd's EXIT GAME being unreachable by keyboard/gamepad,
match_end_screen.gd's RETURN TO MENU being unclickable by mouse, a gamepad
soft-lock in remap_screen.gd's key-listening mode, career_dashboard_screen.gd's
Esc/B bypassing the roster table's own back action, and career_dashboard_
screen.gd having no hint bar at all — missed by this document's own file
list in finding #2). Item 5 (the `.position`→container migration) was not
attempted: real, but lower-value than the accessibility fixes, and higher
risk to get wrong without a GUI to check it in.

Not done, and worth a follow-up pass: `debug_hud.gd` still carries its own
independent, working copy of the same device-aware-hint pattern
`DeviceHintBar` now centralises everywhere else (`_reset_hint_sets`/
`_goal_shot_hint_sets`) — a diagnostic overlay, not a player-facing screen,
so left alone rather than risked for consistency's sake alone.
`team_list_screen.gd`'s `toggle_opposition` has no working gamepad binding
at all (project.godot binds it to joypad button 12, `JOY_BUTTON_DPAD_DOWN`,
which that screen's own row-cursor already reads first as "move down" —
the gamepad branch never runs). Fixing it means rebinding the action in
project.godot (shared input config, outside this pass's UI-files-only
scope), not a UI script change.
