# Career mode audit and plan

2026-10-26. Scope: Career mode only. This covers what's built, what's
missing or broken, ideas that fit, and a phased plan for the changes the
user asked for. Each phase is one commit on `update`, verified headless
(see `docs/LESSONS.md`). Visual feel still needs the user's eyes.

## Your earlier notes on Career

- **Original brief (2026-10-17):** start in Juniors U18s with generated
  teams and players, a 12-game season, a NEXT GAME card with a yellow pixel
  exclamation mark, a Career-styled pregame, track player stats, a
  full-time screen (score, top 3 goalkickers, top 3 disposals), then a
  locked page because nothing past game 1 existed yet. The palette is
  `#2a2a2a` / `#d4b5a0` / `#fefefe`, laid out left-aligned "to avoid AI
  look".
- **W42 notes:** "play a full season in juniors and work our way up,
  similar to the Aussie Rules Hero from the arcade aussierules1 prototype",
  and "in juniors we would start at a local oval and work our way up to a
  full stadium environment".
- **Prototype 1 Hero mode** (`E:\aussie-rules_game\hero_levels.py`) has a
  league ladder: JUNIORS → REPRESENTATIVE → ACADEMY → SENIORS → STATE →
  COUNTRY.
- **W44 board, 4B:** "decide if Career needs its own kit editor". The new
  Customise button on the Create screen answers this: yes.
- **Later playtest asks, all built:** a roster spreadsheet, the camera and
  zoom preview on the pregame screen, quitting returns to the Dashboard,
  and position changeable on the pregame screen. That last one moves to
  Edit Player in this plan.

## Have

| Area | What exists | Files |
| --- | --- | --- |
| Entry | Main menu CAREER card opens the Create screen | `main_menu.gd` |
| Create | Parchment RetroWindow card over the 3D backdrop: NAME, POSITION, NUMBER, FOOT, then five free attribute sliders (SPEED, KICK POWER, KICK ACCURACY, AGILITY, HEIGHT). CONFIRM generates the roster and 12 fixtures | `career_character_screen.gd` |
| Save | `CareerProfile` writes `user://career_profile.cfg`: identity, attributes, kit colours (fields exist, but no Career screen sets them), team name, an 18-player roster, 12 fixture names, `games_played`, `last_result` | `career_profile.gd` |
| Generation | Teams are seeded off their own name, so they rebuild the same without being saved. `overall()` rates a player 0–100 | `roster_generator.gd` |
| Dashboard | Left-aligned. NEXT GAME card, VIEW ROSTER (spreadsheet page), VIEW STATS (reopens the last full-time card), and a locked overlay after game 1 | `career_dashboard_screen.gd` |
| Pregame | PLAYER CONTROL, CAMERA + ZOOM with a live preview, FORMATION, BALL MOVEMENT, DEFENSIVE PRESSURE, YOUR POSITION, START MATCH | `career_pregame_screen.gd` |
| Match | Both teams play to their roster attributes, weight sets body mass, `roster_name` drives the per-player goal and disposal tallies, Career kit colours win in `TeamKit`, and quitting returns to the Dashboard | `full_game.gd`, `team_kit.gd`, `pause_screen.gd` |
| Full time | Both scores, top 3 goalkickers, top 3 disposals. It's persisted so VIEW STATS can reopen it | `career_match_end_screen.gd` |
| Palette | `CareerTheme`: dark/tan plus POSITIVE green and NEGATIVE brick. Keep it separate from the other two UI families (a documented decision) | `career_theme.gd` |

## Don't have: gaps and bugs

**Bugs, in order of how much they'd hurt a season:**

1. **Every visit to CAREER wipes the save.** The card always opens Create
   (`has_player()` is never used for routing), and CONFIRM calls
   `start_season()`, which overwrites the roster, fixtures and results.
   Nothing offers Continue or New.
2. **Stats are keyed by display name across both teams.** Names come from
   24 first × 20 last names (480 combinations). With 36 players a match,
   about 3 in 4 matches have two players sharing a name, and their goals
   and disposals merge. About 1 in 4 home rosters has a duplicate within
   the team itself. Your own name can also match a generated player.
   Season stats need a stable per-player id.
3. **Changing YOUR POSITION on the pregame screen makes you play as a
   teammate.** `full_game.gd` puts the human on `Settings.home_human_slot`,
   but applies your Career stats to the slot for `CareerProfile.position`.
   So you run around as a generated teammate, with their name and stats,
   while your Career player is an AI in the old slot. Your goals are
   credited to the teammate.
4. **Career leaks into quick play.** The Career pregame writes
   `Settings.home_human_slot` and `Settings.player_control_mode`, the same
   fields the quick-play Full Game uses.
5. **Every career gets the same opponents and teammates.** Fixture names
   use a fixed seed (`"career_fixtures"`), and the roster is seeded off the
   default team name, so each new career has the same 12 opponents in the
   same order and the same 17 teammates.
6. **Your number can clash with a teammate's.** Teammates get 1–18
   shuffled, and you pick any of 1–99.
7. **Tackles only count when a ball-up or holding-the-ball free kick is
   called.** A tackle that just knocks the ball loose isn't counted. A
   per-player tackle stat needs a thin `tackle_landed` hook in
   `player_controller.gd`.

**Missing features:**

- No game past round 1 (the locked overlay), no results history (only
  `last_result`), no win/loss record, no ladder, no end of season, no
  leagues, no promotion, no multi-season.
- Per-player stats are goals and disposals for one match only. Kicks,
  handballs, marks and tackles are team-level only. Nothing persists
  across games, so there are no averages.
- No difficulty, no progression, and attributes can be set freely at
  creation.
- No Career kit editor.
- The roster table is sorted by number, has no position grouping, and the
  POS column shows duplicate labels (two "BP", two "HBF" and so on) with
  no L/R.
- "JUNIORS U18s" is hard-coded in the Dashboard header and the Create
  subtitle.
- The away AI has no difficulty knobs (always `AIBrain` defaults).

## Could have

Ideas from your notes, plus things that fit cheaply once a ladder exists:

- **League pathway with environments:** P1's ladder, with Juniors on the
  local Oval 1 and a stadium dressing for the higher leagues (W42).
- **Finals:** top 4, two semis and a grand final, once the ladder works.
- **Match votes:** 3-2-1 from match stats each round, a season best and
  fairest, and a match rating shown on fixture cards.
- **Season goals:** for example, kick 10 goals this season for bonus
  upgrades.
- **Milestones:** 50 games, 100 goals.

Leave out for now: injuries, form, contracts, trades. They're a lot of
system for a minimal indie career.

## Decisions (recommended default first)

1. **Upgrades per game:** Easy 5, Hard 2. This replaces the "3 for now",
   which came before difficulty did. Kept as Tuning constants marked
   unplaytested.
2. **HEIGHT is not an upgrade.** Under the 1-square start rule a ruckman
   would be 169 cm. Default: set it from position (ruck about 200 cm, key
   positions about 192, mids about 183, small forwards and backs about 178)
   and re-set it when you change position.
3. **Cap attributes per league.** With HEIGHT out there are 4 × 9 = 36
   squares. Easy starts on 4, so you'd max out after 7 games, inside the
   first season. Hard takes 18 games. Default: the cap starts at 4 squares
   in Juniors and rises by 1 per league. Unspent upgrades are banked, so
   promotion is what unlocks growth.
4. **Promotion:** finishing top 2 of the 12-team ladder moves you up a
   league. Finals come later.
5. **On promotion you join a new club** (new teammates, opponents and team
   name) at the new tier, like a pathway draft. Your player carries over.
6. **Fixture carousel left arrow** steps back one card, and LB or Home
   jumps to the first card. Your note said the left arrow goes "back to
   first card", so this needs confirming.
7. **"Field 2"** means Oval 1, the second FIELD option in Settings.
8. **Sim match** is dev-only (a debug key) to run seasons fast for
   testing. It also drives the headless season harness.

## Plan

Phases are in dependency order: the save model comes first because every
screen reads it.

### Phase 0: save model and the bugs above (done 2026-10-26)

Landed as below, except `difficulty`, `league_index`, `season_index`,
`upgrades_available`, `season_stats` and `career_history`. Those join
the save in the phase that first reads them (1, 2, 6, 7), since a
ConfigFile key with a default needs no migration. HEIGHT now follows
position (decision 2), so the Create screen shows it read-only until
Phase 6 removes the attribute rows. YOUR POSITION stays on the pregame
screen, but it now moves your roster entry (`set_position()`) until
Phase 7 moves it into Edit Player.

- `CareerProfile` v2 adds `save_version`, `difficulty` (EASY/HARD),
  `league_index`, `season_index`, attribute **levels** 0–9 (the floats are
  derived: `MIN + level/9 × (MAX − MIN)`), `upgrades_available`, a stable
  `id` on every roster entry, `rounds` (one dict per round with
  opponent/result/scores), `season_stats` and `career_history`. v1 saves
  migrate by converting each float to its nearest level, with difficulty
  set to Easy.
- Routing: the CAREER card opens the Dashboard when `has_player()`, and
  Create otherwise. A "New Career" control on the Dashboard asks before it
  overwrites.
- Fixes bugs 2–6: tallies keyed by roster id; Career always plays
  single-player (`full_game.gd` gets one `_full_team_control()` gate that's
  false when `career_active`, instead of reading
  `Settings.player_control_mode` in five places); the human slot comes from
  `CareerProfile.position`; Career stops writing quick-play Settings;
  fixtures and the roster get a per-career seed; picking a taken number
  swaps it with that teammate.

### Phase 1: season loop, ladder, leagues (done 2026-10-26)

Landed as below. Extras: a `season_history` of finished seasons (shown
on the Season Summary as CAREER SO FAR), the ladder as a panel on the
Dashboard, and generated club names in place of "YOUR JUNIORS U18s" for
new careers. An older save's season is rebuilt into a 12-team league,
keeping any round already played. Its opponents keep their names but now
have Juniors-strength squads. F8 is the dev sim key (debug builds only).

- 12 rounds against a 12-team league (you plus 11 opponents: a round robin
  over 11 rounds, then a round-12 rematch). Win 4 points, draw 2, and
  percentage is points for ÷ against × 100.
- Other teams' games are simulated deterministically: a margin from the
  team OVR difference plus noise seeded off (season, round, teams). This
  is off-screen only and never touches an in-match contest, so the
  RULES_REFERENCE §3 rule holds.
- The locked overlay goes. NEXT GAME walks through the rounds. After round
  12 a Season Summary shows your ladder finish, your season line and
  promoted or not, then Start Next Season.
- Leagues use P1's ladder. Generated attribute ranges rise with tier. The
  Dashboard header shows league · season · round · ladder position.
- A headless harness sims 3 seasons and checks the ladder sums, promotion
  and save round-trips. Back up the real save first (see LESSONS).

### Phase 2: per-player stats and VIEW STATS (done 2026-10-26)

Landed as below, with two changes. Tackles needed no new signal:
`tackle_committed` already fires on the tackler only for an on-the-ball
tackle that holds. "Last Match" is a button rather than a tab. The
"+5 upgrades" line waits for Phase 7, when upgrades exist. Your season
line also shows on the Season Summary and is filed in `season_history`.

The per-player TACKLES stat counts every held on-ball tackle. At first
the team tally didn't match it: in a 60 s live run, 4 of 15 landed while
the holding-the-ball or running-too-far whistle had left the ball live.
Fixed in full_game.gd (`_dead_ball_at()`), and the two now agree.

- `MatchState` keeps per-player tallies by id: kicks, handballs, marks
  (legal only), tackles, goals, behinds, hit-outs. Disposals are derived.
  This needs a thin `tackle_landed(tackler, carrier)` signal in
  `player_controller.gd`, flagged as a gameplay-file touch.
- At full time those tallies fold into `season_stats`: all 18 home players
  get +1 game (there's no interchange yet), and your player also gets
  career totals.
- New VIEW STATS page in CareerTheme: ← → cycles the stat, and the table
  is **PLAYER | TOTAL | AVG | GP**, sorted by total, with your row tinted.
  A "Last Match" tab keeps the full-time card reachable.
- The full-time card adds a "+5 upgrades" line.

### Phase 3: Dashboard layout (done 2026-10-27)

Landed as below. New Career moved up beside the team name. Edit Player
and View Fixture show a lock until Phases 5 and 6–7 build their pages.
There's no upgrades badge yet (Phase 7). The ladder widened to 560 px.

- Stack, all 520 px wide: the Next Game card, then an **Edit Player**
  button at full width and about 40 px tall (with an upgrades badge when
  you have some to spend), then a row of **View Roster | View Stats | View
  Fixture**, each about 165 px with a 12 px gap.
- Title Case labels with no letter tracking ("Next Game", "Edit Player",
  ...).
- Explicit focus neighbours so a pad moves through it as a grid.

### Phase 4: View Roster table (done 2026-10-27)

Landed as below. The table is a `CareerTable`, which gained position-line
divider rows. ↑/↓ are caught before the GUI so they scroll instead of
moving focus onto the Dashboard behind the page.

- Keep the CareerTheme look and the same six fields (#, NAME, POS,
  HEIGHT, WEIGHT, OVERALL). Take the TEAMS squad sheet's structure: a
  header row over a 2 px rule, players grouped BACK → FOLLOWERS under
  line-colour bar dividers, a zebra stripe, your row tinted, and L/R on
  POS.
- Move `TeamListScreen._position_label()` to
  `TeamFormation.position_label()` so both screens share it. That's the
  only change to the TEAMS screen.
- Scroll with keyboard or pad, like TEAMS.

### Phase 5: View Fixture carousel (the BEAT look) (done 2026-10-27)

Landed as below, with three changes. The yellow tick runs down the
card's left edge so it never crosses the opponent's name. The left arrow
shows whenever there's an earlier round, so a fresh season shows only the
right one. RB / End jumps back to the next game. The yellow is now
`CareerTheme.MARKER`.

Reference: scene 02 (BEAT) of `showcase_1080p30.mp4`, 4–8 s. It's a row
of numbered squares on a dark grid. Filled squares carry a hard offset
shadow, empty ones are outlined over a dot grid, a vertical tick marks the
current one, there's a mono caption row underneath and a progress bar
along the bottom.

- New `career_fixture_screen`. Cards use the main menu's proportions
  (216×288, sharp 3 px border, the 1.07 selected pop). Four are visible
  and slide one per press with a tween.
- Card states: a played round is filled tan with a hard offset shadow, a
  W/L chip in POSITIVE/NEGATIVE and the score. An upcoming round is an
  outline over a dot grid. The current round has the yellow tick (the
  same `#F5C518` as the Next Game marker). Each card shows "01"–"12"
  large in the top-left. No lime: the Career palette stays.
- Above the cards: a small FIXTURE eyebrow and a heavy headline ("Round
  5 — Glenroy Hawks"). Below: a caption row (ROUND 5 OF 12 · 3RD · W3 L1)
  and a season progress bar.
- A right arrow shows whenever there's a next card. The left arrow appears
  once you've moved right (decision 6). It opens on the current round.
  Mouse clicks, D-pad and LB/RB all work.

### Phase 6: Create Your Player rework (done 2026-10-27)

Landed as below. Customise Player is the CHARACTER screen's floating
button (Y / Tab). "Field 2" is the bush oval (`OVAL_1`) that another
session built. The backdrop dresses itself with it and pushes the studio
fog past the gum ring, so `field.gd` is untouched. POSITION shows its
height ("RUCK · 200 cm"). Edit mode is Phase 7.

- Rows: NAME, POSITION, NUMBER, FOOT, then a **Customise Player** button
  (reusing `CharacterScreen.CUSTOMISE_ROWS` and `SWATCHES`, with the
  backdrop's `zoom_in()`), then a divider, then **CAREER SETTINGS:
  DIFFICULTY ‹ Easy / Hard ›** with a one-line explanation ("Attributes
  start on 1 square · 5 upgrades per game"), then CONFIRM — START CAREER.
  The attribute rows are gone.
- Backdrop: `CharacterBackdrop` gets a `subject_screen_x` setting. Career
  sets it to 0.83 (the middle of the right third). The camera sidestep is
  worked out from the FOV: 50° at 4.15 m gives about 2.3 m, against 0.46
  today. The ring moves with the player. The field uses the Oval 1
  dressing, with an outdoor environment in place of the studio box.
- One script, two scenes: `career_character_screen.gd` gets
  `@export var edit_mode`. Create and Edit then can't drift apart.

### Phase 7: Edit Player and upgrades

- EDIT YOUR PLAYER has the same rows (NAME, POSITION, NUMBER, FOOT,
  Customise), plus an ATTRIBUTES section headed "5 upgrades to spend".
  Right adds a square. Left removes only squares added on this visit.
  Save commits. Difficulty shows read-only.
- A position change swaps your roster entry with the teammate in that
  slot, so you play the new position as yourself. HEIGHT re-sets from
  position (decision 2). This replaces YOUR POSITION on the pregame screen.
- The pregame screen loses PLAYER CONTROL and YOUR POSITION.
- Upgrades are granted when a played match is recorded:
  `Tuning.CAREER_UPGRADES_PER_GAME_EASY/HARD`, capped per league
  (decision 3).

### Phase 8: difficulty and the AI

- Easy and Hard shift the opponents' generated attribute band (low on
  Easy, high on Hard, both rising with the league). The away AI gets
  difficulty knobs: `press_intensity`, and a per-brain multiplier on
  `AI_LOOSE_BALL_REACTION_MIN/MAX`. No dice in contests. Every new number
  goes in `Tuning`, marked "unplaytested feel guess".
- A Hard start (Tuning minimums: 6 m/s, 0.7× kick, 0% accuracy, 0.6×
  agility) is very weak against today's opponents, whose attributes spread
  across the full range. Phases 1 and 8 put Juniors opponents near the
  bottom of the range too.

## Needs your eyes after each phase

How the BEAT-style carousel feels, where the player sits on the Create
screen, Title Case on the Dashboard, and whether Easy and Hard feel
different in a match. Headless checks can't judge any of these.
