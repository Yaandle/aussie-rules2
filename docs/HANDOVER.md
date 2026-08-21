# Handover — end of session 1

## What this session did

Scaffolded the Godot project from an empty directory and built design doc
§11's first milestone: **one `CharacterBody3D` player with blend-space
locomotion and a physically simulated `RigidBody3D` ball**. Nothing beyond
that milestone was attempted.

Sources read: `PROTOTYPE2_DESIGN.md` (the brief), and Prototype 1 at
`E:\aussie-rules_game` — `README.md`, `settings.py`, `most_RECENT_AUDIT.md`.
No Prototype 1 code was ported. Its rule numbers were translated into real
metres and recorded in [RULES_REFERENCE.md](RULES_REFERENCE.md).

## Verification status

The project **loads and runs clean**:

```
godot --headless --path . --quit-after 300   →  exit 0, no output
```

Five seconds of the real main scene with no errors clears script parsing,
scene loading, autoloads, the rig build, animation-library generation,
AnimationTree assembly, the ball's runtime-built convex hull and the field
mesh generation — all of which push errors or throw on failure.

One real bug was found this way and fixed: a partial rename left
`field.gd:_stripe` calling `tool.*` on a parameter renamed to `surface`,
which took the whole Field script out.

**Not yet verified: anything requiring input or a human eye.** Nobody has
driven the player, so the weight model, the blend-space output, kick arcs and
camera behaviour are all unobserved. The most likely remaining failure is
cosmetic rather than structural — see risk 1 below.

## The four design decisions worth knowing

1. **Weight is emergent, not scripted.** `player_controller.gd` has two
   coupled rules: turn rate falls as speed rises, and running against your
   own momentum drives target speed toward zero. Braking then raises the
   turn rate, which swings you round. The plant-and-pivot move is not
   special-cased anywhere — do not add a special case for it.

2. **The strafe axis is fed by physics, not input.** The rig's facing turns
   faster (`FACING_TURN_RATE = 720°/s`) than the velocity heading does
   (`TURN_RATE_SPRINT = 160°/s`), so mid-turn the velocity lags behind the
   body and `locomotion_blend()` reports genuine lateral motion. This is why
   a 2D blend space earns its place in a game where you mostly run forwards.

3. **The AnimationTree graph is built in GDScript, not authored in the
   .tscn.** There are no animation assets, so the clips are generated at
   load and the graph has to be assembled around them at the same moment.
   `player_animation.gd` explains the swap path. This was also the lower-risk
   choice given the scene files could not be validated in an editor.

4. **Everything tunable lives in `scripts/tuning.gd`** — the descendant of
   Prototype 1's `settings.py`. It also holds the two shared enums (`Team`,
   `Action`) because it is the one leaf module everything may depend on.
   Note: `MatchState.Team` deliberately does *not* exist; autoload enums
   cannot be used as type annotations, which is why they moved to `Tuning`.

## Placeholder code, clearly fenced

`placeholder_rig.gd` and `placeholder_animations.gd` are marked for deletion.
They build a blocked-out 1.85m figure and sample gait clips from a sine-based
parametric function. Both go away when a Mixamo `.glb` is imported; the blend
point layout, state names, parameter paths and all of `player_controller.gd`
already match what the real version uses.

## Known risks, highest first

1. **`_gait_pose` sign conventions** (`placeholder_animations.gd`). Limbs
   hang along -Y, the torso runs along +Y, so a positive X rotation swings a
   limb *forward* and the torso *backward*. If the run cycle moonwalks or
   leans the wrong way, a sign is flipped — the physics underneath is fine
   and nothing outside that one function needs touching.
2. **Feel tuning.** Every number in `tuning.gd` is a first guess made without
   playing it. `TURN_RATE_SPRINT`, `ACCELERATION`/`BRAKING` and
   `KICK_MIN/MAX_SPEED` are the ones most likely to want moving.
3. **Gather ergonomics.** `GATHER_RADIUS = 0.85` m with a 14 m/s speed cap may
   make picking the ball up fiddlier than it should be.

## What was NOT built, and why

AI, a second player, a second team, tackling, marking, scoring, the match
clock, menus, audio. The brief's own ordering (§11): prove the physical feel
first. `scripts/mechanics/`, `scripts/ai/`, `scenes/modes/` and
`data/scenarios/` exist as empty placeholders from §10.

Root motion is **not** wired. §5 wants it for impacts only (tackles, marks)
with locomotion staying code-driven. The hook is
`AnimationTree.root_motion_track` plus `get_root_motion_position()` in the
controller's move step — it needs contest mechanics to exist first.

## Next milestone

Contest mechanics: a second player, tackling and marking resolved by
collision and momentum rather than a probability table. That is the pillar
in §1 that Prototype 2 exists for. `RULES_REFERENCE.md` §3 lists exactly
which Prototype 1 numbers are being replaced by it, and §5 of that document
records two audit findings from Prototype 1 worth designing against.

---

## Handover — visual/UI pass (Agent: UI & visual quality)

Look-and-feel pass over the existing scaffold per the brighter-indie
direction brief. No physics, contests, or game state touched. Verified by
headless parse (`godot --headless --path . --quit-after N`) after every
change, plus visual screenshots via a temporary `-s` SceneTree script
(instance a scene, wait N frames, save the viewport to PNG, quit) — not
committed, deleted at the end of the session.

### 1. Field/environment brightened, lighting centralised

`main.tscn`, `kick_to_kick.tscn`, `full_game.tscn`, `menu_backdrop.tscn`
and `character_backdrop.tscn` each carried their own copy of the same
Sky/Environment sub-resources — five places to go out of sync. Extracted
to one file, **`materials/broadcast_environment.tres`**, referenced by all
five as an `ext_resource`. Sun `light_energy` raised 1.15 → 1.7 in each
(the one field left un-shared, since it's a per-node property, not part
of the Environment resource).

Turf shader (`assets/shaders/turf.gdshader`): `turf_a`/`turf_b` brightened
and saturated, `surround` lightened so it doesn't read as near-black,
`turf_roughness` dropped slightly. Mowing-stripe contrast is now visible
at broadcast-camera distance, which it was not before (before/after was a
literal "muddy dark green" → "vivid pitch green with visible stripes").

Sky colours in the shared Environment pushed more saturated/blue rather
than pale grey-white — a flat grey top-of-frame in early screenshots
turned out to be the (working-as-intended) dark UI scrim over a correctly
blue sky underneath, not a bug; confirmed by sampling raw pixel values and
back-solving through the scrim's alpha blend. Added a modest
`glow_enabled` bloom (intensity 0.35) for a bit of broadcast sheen.

`Field.SURROUND_MARGIN` (`scripts/field/field.gd`) raised 25.0 → 60.0 m so
wide establishing camera angles (the menu backdrop's flyover shot) don't
run past the ground plane's edge; `field.tscn`'s placeholder mesh/collision
sizes updated to match (both are overwritten at runtime by `field.gd`
anyway, this just keeps the editor preview honest).

**Files touched outside strict ownership**: `main.tscn`, `kick_to_kick.tscn`,
`full_game.tscn` are level-assembly scenes not on either agent's ownership
list. Only their `WorldEnvironment`/`Sun` nodes were touched (swapped to
the shared ext_resource, bumped light energy) — no Player/Ball/script
nodes or gameplay properties were changed. Flagging per instructions;
nothing here overlaps Agent 2's actual working files
(`kick_to_kick.gd`, `player_controller.gd`, `tuning.gd`,
`kick_trajectory.gd`, which all had pre-existing uncommitted changes on
disk at session start and were left untouched).

### 2. Glowing white menu border

New shader **`assets/shaders/ui_glow_border.gdshader`** (canvas_item): an
SDF rounded-rect outline with a soft exponential glow falloff, added to
`main_menu.tscn` as a `ColorRect` (a bare `Control` doesn't draw anything,
so the material never rasterized — first attempt was invisible for that
reason). Sized to preserve the requested 1720×880 aspect ratio scaled down
to fit the project's actual 1280×720 viewport (confirmed with the user —
the literal 1720×880 would have rendered almost entirely off-screen).
Visible border rect: 1152×589, centred, ~64px margin to the viewport edge.

### 3. Player silhouette pass

`scripts/player/placeholder_rig.gd`: narrowed the pelvis box (0.30 → 0.23m)
and the chest box (0.36 → 0.32m) so they no longer read as the same width,
widened `SHOULDER_WIDTH` (0.21 → 0.24m), and added a **Yoke** box (a
contrasting guernsey-style shoulder band) and two **SidePanel** boxes —
these are the widest points of the torso now, which is what actually sells
a V-taper silhouette at distance (limb capsules alone read too thin to do
it). Shins recoloured from bare skin to a sock colour (`COLOUR_TRIM`,
off-white, shared with the yoke/panels) — AFL players play in long socks;
before, the whole leg hip-to-ankle was one flat skin tone.
`COLOUR_TRIM` (`#f0ece0`) intentionally echoes `Field.COLOUR_LINE` so
player and pitch read as one system. All new geometry is primitive boxes
(no added tris budget concern — still well within per-instance cost for
many players on field). `_material()` now takes an optional roughness so
the trim/yoke can have a bit less roughness (0.55) than skin/shorts (0.78)
for a faint jersey sheen, cached per (colour, roughness) pair.

### 4. UI colour consistency

`main_menu.gd`'s selected-row colour changed from reusing the title's
off-white to gold (`#e9c95e`) — the same gold as the home guernsey.
Previously the only selection cue was cursor position; now the cursor row
visibly pops. (Note: at the time this was written `character_screen.gd`
used the same gold for its live-value highlight; it has since been rebuilt
with its own accent — see §5 below. Main menu and scoreboard still share
the gold/rust guernsey-accent system described here.)

`scoreboard.tscn`'s `Label` converted to `RichTextLabel` (`bbcode_enabled`)
so `scoreboard.gd` can colour the HOME segment gold and AWAY rust-red —
the literal home/away guernsey colours from `placeholder_rig.gd` — so the
scoreboard reads at a glance without parsing the words "HOME"/"AWAY".
`flash()` (GOAL!/QUARTER TIME banners) now centres and golds its text too.

DebugHud's smaller font/denser layout was left as-is — it's a deliberately
different tier (diagnostic overlay vs. primary UI) and was already
internally consistent.

### 5. Character screen rebuilt as a real component UI

The BBCode/RichTextLabel table described in §4 above has been replaced
with an actual `Control`-based component system, built from a small shared
library rather than one-off per-screen code:

- **`scripts/ui/ui_style.gd`** — `UIStyle`: the palette, type scale
  (`FontVariation` over the engine's default face, weight via
  `variation_embolden`, tracking via `spacing_glyph` — no font asset), and
  a `rounded()` `StyleBoxFlat` factory. One accent colour, teal/cyan
  `ACCENT` (`#4fd1c5`), means "selected/interactive" on this screen.
- **`scripts/ui/ui_icon.gd`** — `UIIcon`: single-colour line icons drawn
  in `_draw()` from a shape table (poly/loop/arc/ring/dot/fill primitives
  on a 24-unit grid), one per stat (speed, jump, kick, accuracy, strength,
  height, weight, foot, play). No icon assets or import step.
- **`scripts/ui/stat_row.gd`** — `StatRow`: one attribute line (icon,
  label, optional "· LOCKED", a 9-segment bar, value text), column
  positions as explicit px offsets rather than a container, so the bar
  starts at the same x regardless of label length.
- **`scripts/ui/key_hint_bar.gd`** / **`scripts/ui/action_button.gd`** —
  the bottom control-legend chips and the PLAY button.
- **`character_screen.gd`** now builds its whole left column from
  `ATTRIBUTE_ROWS` in code (eight `StatRow`s + header + button + hints);
  `character_screen.tscn` is just the 3D backdrop plus an `Overlay`
  CanvasLayer holding a scrim and an empty `UI` Control to hang it on.

Backdrop (**`character_backdrop.gd`**, **`character_backdrop.tscn`**) was
rebuilt to match: a dedicated dark navy-to-green **"studio"** environment
(**`materials/character_studio_environment.tres`**) — deliberately *not*
`broadcast_environment.tres`, kept separate on purpose rather than
parameterised, since a moody portrait box and a bright match day are
different problems. A glowing selection ring
(**`assets/shaders/selection_ring.gdshader`**, additive-blended so it
lights the turf under it rather than painting over it) sits under the
player's feet, camera side-stepped so the figure sits right of the stat
column instead of dead-centre. Legibility over the 3D backdrop comes from
**`assets/shaders/ui_side_scrim.gdshader`**, a horizontal gradient wash
(not a flat panel — a flat one has an edge, which reads as an unintended
panel divider) rather than the old full-screen flat scrim.

Net effect: the character screen now has its own distinct visual identity
(dark/teal "studio") separate from the bright broadcast look used
everywhere else (menu, match, scoreboard). That's an intentional split,
not a consistency gap — see the comment at the top of
`character_studio_environment.tres`.

### 6. Follow-up round (user feedback on the above)

- **Glow border was too bright.** `ui_glow_border.gdshader` defaults
  toned down: `glow_strength` 0.85 → 0.4, `glow_radius` 22 → 14,
  `line_width` 2.5 → 2.0, `glow_color` alpha 1.0 → 0.85.
- **Main menu backdrop read as "night time."** Scoped to the menu only,
  per instruction — match/character scenes were left alone:
  - `main_menu.tscn`'s `Scrim` alpha dropped 0.45 → 0.22.
  - `menu_backdrop.tscn` given its own **`materials/menu_environment.tres`**
    (brighter sky/ambient/tonemap than the shared broadcast one) instead of
    reusing `broadcast_environment.tres`, so gameplay scenes' lighting is
    untouched.
  - The wide establishing flyover shot still had one very dark diagonal
    band even after that — turned out to be ordinary Lambertian falloff
    (the sun grazing the outer grass at a shallow angle from that specific
    camera angle), not a bug. Fixed with a second, dimmer **`FillLight`**
    `DirectionalLight3D` in `menu_backdrop.tscn` from a complementary
    angle — a standard stylised-lighting trick, not a physically-accurate
    one, and scoped to that one scene.
- **Stadium/oval feel requested**: `turf.gdshader` gained a running-track
  **apron** ring (`apron`/`apron_width` uniforms) between the playing oval
  and the outer grass, layered outside-in (outer grass → apron → striped
  turf) rather than the old flat "surround" colour. `field.gd` gained
  `_build_fence()`: a continuous low white ribbon (same
  `SurfaceTool`-around-an-ellipse technique as the line markings, cheaper
  than instancing individual pickets and reads the same way a real picket
  fence does from broadcast distance) plus support posts every 8th
  segment, ~9m outside the boundary. This is shared `Field` code, so it
  appears in every scene that instances the field (menu backdrop included)
  — only the brightness fixes above were menu-scoped, the stadium dressing
  is global by design.

### 7. Character screen matched to the design reference

Second pass over §5's screen against a supplied mock image. Layout and
component structure from §5 survived; this round was metrics, the 3D
preview's lighting, and one real bug underneath it.

**How it was verified.** The real scene rendered at 1280x720 *and*
1920x1080 through a temporary `-s` SceneTree harness (deleted), with
pixel values sampled out of the PNGs rather than eyeballed — which is how
the lighting bug below was actually caught, since it looks plausible
until you read the numbers. Plus a scripted input test that pushed real
`InputEventAction`s through `_unhandled_input` and asserted: cursor
starts on row 0, W/S moves it, A/D nudges an unlocked stat, A/D on a
locked row changes nothing, HEIGHT drives the preview rig's scale, and
the cursor wraps onto the PLAY row. All passed.

**Metrics.** The reference is 1358x772 and the project renders 1280x720
(`project.godot` `[display]`), so every measurement off the image was
scaled by 0.94 before being used. Landed on: title 36px / tracking 6,
subtitle 13/2, labels 15/1, values 15/0 (values are the one untracked
run of text, as in the reference); rows on a 53px pitch from y=184;
button at 613, hint bar at 678. Title, subtitle and longest label all
render within ~5px of the scaled reference width.

**The bug worth knowing about: `Transform3D` literals are row-major.**
The 12 numbers in a `.tscn` `Transform3D(...)` are the basis **rows**,
while `basis.x/y/z` are its **columns**. Write the axis you want along a
triple instead of down the triples and you silently get the transpose —
which is still orthonormal, so the scene loads clean and nothing warns.
Here it aimed the sun *upward*: every +Y surface in the scene (the whole
pitch, every line marking) was lit by ambient alone, while the player,
whose front faces +Z, looked correctly lit. That is why the turf went
black the moment the studio environment replaced the bright broadcast
one — the old environment's bright sky had been standing in for a sun
that was never reaching the ground. Raising the sun 1.15 → 8.0 changed
the ground by *one* 8-bit level; that ruled out every tuning explanation
and pointed at geometry.

**`character_backdrop.tscn` is fixed. The same literal is still in
`main.tscn`, `kick_to_kick.tscn`, `full_game.tscn` and
`menu_backdrop.tscn`** (§1 shared the Environment between them but left
`Sun` as a per-node property in each). Those are level-assembly scenes,
outside this pass, and correcting them is a real lighting change to
gameplay — worth doing deliberately, not as a drive-by. Check
`-sun.global_transform.basis.z` has a negative Y before assuming any of
them is lit as intended.

**Two lights, not one.** The reference is a lit figure on a nearly black
pitch, which no single directional light gives. Split by cull mask:
`Sun` (energy 0.14, mask excludes layer 2) does the ground, `Key`
(energy 1.05, mask = layer 2 only) does the subject.
`character_backdrop.gd` moves the previewed player's `MeshInstance3D`s
onto `SUBJECT_LAYER` after `add_child()` — only ever on the instance
this scene spawns, so the shared player scene is untouched. Ground and
figure now tune independently, one light each.

**Depth fog, not exponential.** This portrait box happens to stand on a
165x135m oval, and seen edge-on from 1m off the ground everything past
~50m — the boundary ellipse, the apron, §6's new fence — flattened into
a hard near-white streak straight across the horizon, and straight
across the KICKING ACCURACY row. `fog_mode = 1` with a 5→55m ramp erases
that while leaving the near turf its colour; exponential fog can't,
it takes the foreground green with it. `fog_light_color` is set just
under the sky's horizon colour so the ground fades into the sky with no
seam and the small remaining step *is* the horizon glow.

**Where the player stands.** `STAND_ON` is 1.6m inside the centre
square's boundary line, not the origin. The origin is ringed by the two
centre circles, which fill this framing with white ellipses fighting the
selection ring; the offset keeps one straight line running away from
camera (the reference's faint stripe) *beside* the subject rather than
under the camera, where it fans into a white wedge across the entire
foreground.

**The 3D preview now renders at native resolution.** It was in a
`SubViewportContainer`, which sizes its viewport in *design* units — so
under `canvas_items` stretch the 3D rendered at a fixed 1280x720 and got
scaled up by the canvas transform, visibly soft on any window bigger
than 720p (confirmed: viewport reported 1280x720 while the root was
1920x1080). The backdrop is now a plain child of the scene root and the
UI moved into an `Overlay` CanvasLayer. Nothing was lost — the isolation
a SubViewport buys is meaningless when the scene *is* the whole scene.
**`main_menu.tscn` still has this exact problem** and was left alone.

**Three deliberate deviations from the mock**, all so the screen shows
the truth rather than the picture:

1. **SPEED reads 4/9 filled, the mock shows 5.** 8.40 m/s in a 6.0–11.0
   range is 48%. The mock was drawn by eye; the bar is computed.
2. **Locked rows render an empty bar; the mock shows JUMPING at 4/9.**
   `StatRow` honours a fill level on locked rows — locked disables
   interaction, it does not hide a value — but there is no jumping stat
   in `CharacterProfile` to read, and inventing one would be inventing
   gameplay. The moment a stat backs it, it fills.
3. **KICKING FOOT has no bar at all** (`"bar": false`), matching the
   mock. It is a side, not a level; nine empty squares would read as
   "zero" for something that has no zero.

**Control hints are device-keyed, not hardcoded.** `_hint_sets` in
`character_screen.gd` is a dictionary keyed by `InputManager.Device`,
already wired to `device_changed`. Only the keyboard set is filled in —
the Xbox bindings are being settled elsewhere, so the controller legend
is one more entry in that dictionary and no restructuring. Until it
exists a plugged-in pad falls back to the keyboard legend, which is what
every other screen does today.

### Not done / left for later

- No real screenshot-diff regression suite exists — verification this
  session was manual (temporary `-s` SceneTree scripts + eyeballing
  renders), not automated.
- The transposed `Sun` transform (§7) is fixed only in
  `character_backdrop.tscn`. `main.tscn`, `kick_to_kick.tscn`,
  `full_game.tscn` and `menu_backdrop.tscn` still carry it.
- No gamepad control legend yet — the hook is in place (§7), the data
  isn't, pending the Xbox binding set.
- The character in the preview is still `PlaceholderRig`, so the figure
  itself doesn't match the mock's proportions or kit. That's the
  placeholder plan, not a gap in this pass.
- `PlaceholderRig` is still explicitly a placeholder per the original
  handover; the silhouette pass improves it but doesn't replace the plan
  to drop in real art later.
- Camera movement/trigger logic in `broadcast_camera.gd` was **not**
  touched (Agent 2's territory per the brief); only the Environment
  resource it renders through was touched, and that lives in the level
  scenes, not in `broadcast_camera.gd` itself.
- Main menu (`main_menu.gd`) still uses its older ad hoc `COLOUR_*` string
  constants and BBCode text rather than `UIStyle`/`UIIcon` — §5's component
  system only covers the character screen so far. A future pass could
  bring the menu and scoreboard onto the same system for real type/spacing
  parity rather than just matched accent colours.
- The boundary fence is a flat ribbon, not real picket geometry — correct
  at broadcast distance, would read as fake up close (e.g. if a future
  camera mode ever gets near the boundary).

---

## Handover — kick stance/execute + decoupled aim (Agent: mechanics/engine)

First pass at the Xbox+KBM control scheme the design brief specifies,
scoped to the one piece that was fully numerically specified: the two-stage
kick, its independent aim, and handball's independent aim. Marking (3-tier),
punch/spoil, smother, bump and the ruck hit-out are deliberately **not**
built this pass — see "Deferred" below for why and what each still needs.
No visuals, contests-beyond-tackle, or RULES_REFERENCE.md numbers touched.

### 1. Kick is now LT-hold-stance / RT-tap-execute, not hold-then-release

`player_controller.gd`'s `_update_charge()` used to fire the kick on the
same button's release (hold `kick` to charge, let go to fire). The brief
wants two separate controls — hold to enter a slowed aiming stance, tap a
different button to strike — so release-without-firing had to become a
real option (**cancel**), which the old model had no way to express.

New flow: `wants_kick()` (LT / `K`) only ever charges and holds stance;
`wants_kick_execute()` (RT / `F`, new on `PlayerBrain`) is the one thing
that fires, and only while stance is already held. Releasing LT before ever
tapping RT zeroes `_kick_charge` and drops out of stance with no kick fired.
`AIBrain` needed the same shape — it used to just flip its simulated button
false when its hold timer ran out (which the old release-fires model read
as "let go"); now it pulses `_kick_execute_pressed` true for one frame
while keeping `wants_kick()` true that same frame, i.e. it "holds LT and
taps RT" like a human would. Traced the frame-by-frame interaction with the
existing windup/contact timing (`Tuning.ACTION_DURATION`/`ACTION_CONTACT`)
by hand: because `is_carrying()` always goes false at contact time (~0.42s
into the swing) well before `_action` resets to `NONE` (~0.78s), a brief
window where `AIBrain` can spuriously re-`_commit_kick()` while its own
swing is still playing is real but inert — `_update_charge()` early-returns
on `_action != NONE` the entire time, so nothing it sets during that window
is ever read before the top-level `is_carrying()` check wipes it.

### 2. Aim is decoupled from body facing — kick and handball each got their own source

The brief is explicit that this is new: "aim is fully decoupled from
movement/facing... two different aim sources feeding the same shared
launch-math helper." `_launch_from()` (the shared helper every disposal
already funnelled through) took an implicit `forward := -global_transform.
basis.z` before; it now takes `horizontal_dir` explicitly, so it can no
longer quietly default to body-forward for whichever action is calling it.

- **Kick**: a new `_kick_aim_yaw` float, snapped to `_facing_yaw` the
  instant stance begins, then nudged by the right stick/mouse for a human
  only (`_update_kick_aim()`) — reusing the exact same
  `InputManager.get_look_vector()`/`take_mouse_look()` calls and sign
  convention `broadcast_camera.gd` already used for its own yaw, so "push
  the stick right" turns the aim the same way it already turns the camera.
  Frozen the moment the swing begins (RT consumes it once, waggling the
  stick after that can't retroactively redirect an already-struck kick).
  AI never nudges it, so its kicks stay body-forward exactly as before —
  just captured a moment earlier (when its simulated stance begins, not at
  contact time), a difference too small to matter for a baseline explicitly
  "not a tactics system" (`ai_brain.gd`'s own docstring).
- **Handball**: no persistent aim state — captured once in `_begin()` at
  the instant `X` is pressed, from `_wish_dir` (falling back to
  body-forward if the stick's neutral right then), matching "toward
  wherever Left stick is currently held" precisely rather than reading it
  again later at the animation's contact time, where it could have drifted.
- **Bounce**: untouched, still body-forward — the brief doesn't ask for a
  bounce aim source, and AFL's real bounce-while-running doesn't need one.

`kick_trajectory.gd` itself needed no changes — it was already a dumb
ballistic previewer fed an origin/velocity by `player_controller.gd`; once
`_kick_parameters()` started resolving that velocity from the aim yaw
instead of body facing, the preview correctly followed without knowing
anything changed. ("The active source" the brief means to be read correctly
lives in `_kick_parameters()`/`_launch_from()`, not in the trajectory node.)

### 3. Kick stance slows movement; camera stops eating the aim stick

`Tuning.KICK_STANCE_SPEED_SCALE` (0.55) applied in `_update_locomotion()`
while `_charging` — less restrictive than the existing swing-lock
`ACTION_SPEED_SCALE` (0.4), since the brief wants you still moving while
aiming, just slower, not planted. `Tuning.KICK_AIM_YAW_SPEED` (180°/s,
starts equal to `CAM_YAW_SPEED` but is a separate dial) governs how fast
the stick/mouse swings the aim.

`broadcast_camera.gd._update_rotation()` now early-returns while the human
target is in kick stance (`is_kick_aiming()`, new on `PlayerController`),
so the right stick/mouse drives aim instead of fighting the camera for the
same input. Position/lookahead (`_update_focus`) and FOV (`_update_fov`)
keep running unaffected — the rig still tracks the player, it just holds
its current orientation instead of re-centring on stick input until aiming
ends. This is the one change in `broadcast_camera.gd`; no lens/visual
treatment touched, per the ownership split with Agent 1.

### 4. Tackle: renamed from `mark_contest`, moved to B, switched to hold

The old `mark_contest` action (E / Y, edge-triggered) only ever meant
"attempt a tackle" — there is no marking system yet, so the name was
already misleading and would only get worse once marking exists. Removed
it outright and added `tackle` (E / **B**, `is_action_pressed` — a hold,
per "B hold near opponent: Tackle") rather than leaving a dead action name
bound to nothing. `PlayerController._try_tackle()`'s existing guards
already required `not is_carrying()` on the tackler, so switching from tap
to hold is safe by inspection: it only re-attempts a tackle on a target
still in range, and the moment one lands, `other.is_carrying()` goes false
and removes them as a valid target — no re-tackle-spam from holding B down.

Y is now fully unbound (was tackle, freed for the brief's own "Aggressive
mark" reservation). B keeps its existing Bounce binding *as well* —
Bounce needs `is_carrying()`, Tackle needs `!is_carrying()`, so the two are
mutually exclusive by possession state and can safely share the physical
button, exactly the "buttons remap by phase" pattern the brief describes
for the defensive phase generally (confirmed against a pre-existing
precedent already in this file: `camera_recenter` and `character_menu`
already shared physical `C` before this change).

### 5. Input map bookkeeping

`project.godot [input]`: removed `kick` (K/A) and `mark_contest` (E/Y).
Added `kick_stance` (K / LT axis4), `kick_execute` (**F**, not a mouse
button — see below / RT axis5, physically shared with the pre-existing
`sprint` action, same "one physical control, two named logical actions,
gameplay code picks which applies" pattern already used for LT elsewhere),
`tackle` (E / B button1). Left `bounce`, `handball`, `sprint`, `walk`,
`camera_*`, `switch_player`, `pause`, `debug_*`, `character_menu` untouched.
A is now fully unbound (was `kick`), reserved for the brief's marking tier.

**Deliberate deviation from the brief's literal RT-tap-execute /
LMB-adjacent instinct**: used keyboard `F` rather than Left Mouse Button
for `kick_execute`. This project has never bound a mouse *button* to
anything (only mouse *motion*, for camera look), so there were no verified
examples of Godot 4's `InputEventMouseButton` text-resource format in this
file to pattern-match against, and no way to headless-verify a guess (see
§6). `F` is a plain `InputEventKey` identical in shape to the eight other
key bindings already in the file, eliminating that risk for the same
functional outcome. Worth revisiting for real mouse-click support once
this can be tested in-editor.

### 6. Verification — and the gap in it

No `godot`/`godot4` executable was found on `PATH`, in `Program Files`, in
`%LOCALAPPDATA%`, or anywhere else searched — this environment cannot run
`godot --headless --path . --quit-after 300`, the project's own standard
smoke test (see this file's top section and `README.md`). Everything above
was instead verified by:

- Full re-reads of every touched file post-edit (not just diffing the
  intended change) to catch anything the edit tool matched wrong.
- Hand-tracing the state machine frame-by-frame for: a minimum-charge tap
  kick, hold-then-cancel, hold-to-execute at partial and full charge, the
  `AIBrain` timing interaction in §1, handball while moving vs. stationary,
  and tackle-hold while closing distance.
- Re-deriving `_yaw_direction()` against `_update_facing()`'s existing
  `atan2(-desired.x, -desired.z)` and confirming they're exact inverses
  (yaw→direction round-trips to the same direction that produced it),
  rather than trusting a fresh derivation by eye.
- Grepping for every remaining reference to the removed `kick`/
  `mark_contest` action names across the whole project — the only hits
  left are unrelated animation/icon lookup keys that happen to also be
  spelled `"kick"` (`player_animation.gd`, `placeholder_animations.gd`,
  `ui_icon.gd`, `character_screen.gd`), not `Input` action reads.
- Checking every new `project.godot` `[input]` block character-for-character
  against an existing verified block of the same event type (`InputEventKey`
  / `InputEventJoypadMotion` / `InputEventJoypadButton`) rather than
  reconstructing the format from memory.

**What this hasn't caught**: anything that only shows up at actual engine
parse time or in play — whether the two new axis-4/5 bindings read the
Xbox triggers the way I expect, whether the stance slow/aim-swing feels
right, whether `_kick_aim_yaw` drifting from `_facing_yaw` looks correct on
the rig. Needs a real `godot --headless` pass and then hands-on-pad time in
`kick_to_kick.tscn` before this is more than "should be correct by
inspection." Point me at the executable, or run the standard smoke test
yourself, before relying on this beyond that.

**Flag for Agent 1 (UI/visual, out of my scope)**: `debug_hud.gd`'s
hardcoded control hint — `"K hold+release kick   Q handball   Space bounce
R reset ball   F3 hud"` — describes the removed model. Not edited here;
`HUD` is explicitly out of scope for this agent.

### Deferred: marking, punch/spoil, smother, bump, hit-out

Not started. Unlike the kick, these have no numeric spec anywhere yet —
building them now would mean inventing detection radii, timing windows and
risk/reward resolution unsupervised. Concretely still open before any of
these can be built:

- **Marking (A/X/Y tiers)**: needs "ball in flight" + timing-window
  detection (nothing in the codebase currently distinguishes a mark from
  `_try_gather()`'s passive proximity pickup), and per RULES_REFERENCE.md
  §4 holding-the-ball/free-kick adjudication isn't resolved yet either —
  the brief's "mistimed aggressive mark ≈ free-kick-against" has no home
  until that lands.
- **Punch/Spoil (LT tap, not carrying)**: needs a contest-detection radius
  and a resolution (does it just knock the ball loose faster, cancel a
  mark attempt, or both).
- **Smother (X, not carrying)**: needs a way to read that an opponent is
  mid-disposal-windup (nothing public exposes `_action` today) plus a
  timing window and a resolution.
- **Bump (LB hold + RT stick flick)**: needs the hit-stick timing model
  itself designed — flick-direction-vs-carrier-approach-angle scoring,
  plus the free-kick-for-high-contact rule RULES_REFERENCE.md doesn't have
  numbers for yet.
- **Hit-out (RB, ruck stoppage only)**: needs a ruck/stoppage phase to
  exist first; `GameState.Phase.STOPPAGE` exists but nothing currently
  enters it for a ball-up the way it will need to.

---

## Handover — playtest fixes + kicking coach (Agent: mechanics/engine)

First real playtest of the kick-stance/execute work above happened in the
gap between sessions (commit `aa34a6a`) — this pass is the fixes that
playtest surfaced, plus the kicking-coach mini-game.

### 1. Kick was going ~100m at max power, wanted ~60m+

`Tuning.KICK_MAX_SPEED` (30 m/s) was never actually simulated when it was
picked — the old comment's "55-60m" was a hand estimate. Numerically
stepped the real drag+gravity model this time (matching
`KickTrajectory._simulate`'s own integration): 30 m/s at 40° comes out to
~65m of *flight* standing, ~75m kicking on the run, before any bounce/
roll-out is added on top — consistent with "~100m" once a real landing's
bounce and roll are included. Dropped `KICK_MAX_SPEED` to 24.0 (~46m
flight standing, ~55m on the run), leaving room for roll-out to land the
*total* travelled distance around 60-70m instead of 100m+. `KICK_MIN_SPEED`
untouched — only the top end was reported as too far.

### 2. Kick charge could only ramp up, never back down

The charge model was pure hold-duration (`_kick_charge += delta /
KICK_CHARGE_TIME` while LT held, reset to 0 on release) — an Xbox
trigger's actual pull depth was never read, so there was no way to ease
power back down short of fully releasing and re-charging from zero, which
is what got reported as "I can move direction but not the power back and
forth."

Added `InputManager.kick_stance_strength()`: returns the trigger's real
analog pull (`Input.get_action_strength`) on a gamepad, or a negative
sentinel on keyboard (K has no pull depth to read — nothing analog to
fall back to there). New `PlayerBrain.kick_charge_override()` — negative
by default (AI and keyboard both keep the old time-ramp), `HumanBrain`
returns the live trigger read. `PlayerController._update_charge()` uses
the override directly as `_kick_charge` whenever one's available, instead
of accumulating. Also dropped `kick_stance`'s InputMap deadzone 0.5→0.2
(matching `MOVE_DEADZONE`) — at 0.5 half the trigger's travel was dead
zone, leaving almost no usable analog range once it *was* being read.

### 3. Character appears to move backward when running forward

Investigated but **not fixed here** — re-derived and hand-verified the
entire movement/facing pipeline in `player_controller.gd` (camera-relative
input → `_heading` → `_facing_yaw`/`rotation.y` → `locomotion_blend()`)
and confirmed it's mathematically correct; also checked every `Transform3D`
literal in `player.tscn` for the row/column transpose bug this project has
hit before (§7 above) and found none carry a non-identity rotation to even
be vulnerable to it. That rules out this agent's own code. Most likely
remaining suspect is `placeholder_animations.gd`'s `_gait_pose` — exactly
the risk this project's own milestone-1 notes predicted — or something in
the rig/animation wiring; both are character-model/animation, outside
this agent's ownership. Flagged with the full diagnostic trail as a
spawned task rather than guessing blind edits into files this agent
doesn't own.

### 4. Ball read as floating away from the carried hand

`CarryPoint` (`player.tscn`) was still at the offset (`0.26, 1.02, -0.3`)
it was presumably tuned at before the visual pass narrowed the torso
(pelvis 0.30→0.23m, chest 0.36→0.32m — see §3 in the visual-pass section
above). Checked it against the *current* rig geometry in
`placeholder_rig.gd`: at carry height (~hip level), the only nearby
geometry is the Pelvis box, half-width 0.115m — 0.26 sits more than
double that width out, past everything. Moved it to `(0.16, 1.20, -0.22)`,
which lines up with the SidePanel boxes (offset `0.17, 0.15` from torso,
added in the same visual pass) — carried at the ribs, snug against
existing geometry instead of floating past all of it. Not visually
verified (see the environment note below) — likely still wants a final
eyeball-and-nudge pass in-editor.

### 5. Kicking coach + target-practice mini-game (kick_to_kick only)

New: walk up to a coach standing on the field, `X`/interact to talk,
`Y`/`confirm` to accept a kick-at-the-target challenge, camera does a
two-shot for the conversation and pans back out behind the player for the
challenge, 5 kicks at a downfield ring, hit/miss tracked. Scoped to
`kick_to_kick.tscn` only and to the kicking coach only — a marking coach
and a tackling coach, and wiring any of this into Full Game, are next per
the brief, once this one's been played.

**New, mine**: `scripts/mechanics/coach_npc.gd` + `scenes/mechanics/
coach_npc.tscn` (proximity trigger + a bare instance of the existing
placeholder rig as a stand-in body — no `PlayerController`, so it can't
gather a loose ball or take a tackle just by existing on the field).
`scripts/mechanics/kick_challenge.gd` + `scenes/mechanics/
kick_challenge.tscn` (the mini-game: target ring is a mechanics-owned
gizmo — `Area3D` + unshaded `TorusMesh`, the same category of thing
`KickTrajectory`'s landing ring already is, not a modelled prop — hit/miss/
attempts state machine, signals for the rest to hook). Kept deliberately
separate from `kick_to_kick.gd`'s own body rather than folded in, since
what actually ends up shared once the marking/tackling coaches exist isn't
knowable yet — that's a refactor for when there are three of these, not a
shape to guess at with one.

**`broadcast_camera.gd`**: added `enter_dialogue(left, right)` /
`exit_dialogue()` — a fixed side-on two-shot (position off to the side of
the left↔right line, spring arm collapsed to ~0, yaw/pitch aimed at the
midpoint) as a genuinely different composition from the follow-cam's
spring-arm-behind-one-target model, not a variation of it. `exit_dialogue()`
is just `recenter()` — which now also restores `spring_length`/`fov`, since
dialogue framing is the first thing that ever moved them and nothing was
putting them back. New `CAM_DIALOGUE_*` constants in `tuning.gd`.

**`kick_to_kick.gd`**: owns the state machine (`NONE → PROMPT → DIALOGUE →
CHALLENGE`), reads new `interact`/`confirm`/`decline` actions directly
(same pattern it already used for `pause`/`debug_reset`), freezes movement
during dialogue via the existing `InputManager.gameplay_input_enabled`
gate (already built for exactly this — menus/dialogue owning input — see
`input_manager.gd`'s own docstring), re-offers the prompt immediately on
decline if still in range, and polls once a frame for "was carrying when
I walked up, not carrying anymore" so the prompt doesn't get stuck
withheld until the player leaves and re-enters the coach's radius.

**Placeholder UI, clearly fenced**: a bare `Label` in a `CanvasLayer`,
built in code inside `kick_to_kick.gd` (not a scene file, not styled)
stands in for the real chat-bubble dialogue the brief describes. This is
UI, out of this agent's ownership — built only as a rough, load-bearing
placeholder so the feature is actually testable end to end right now,
exactly the same "prove it before it's pretty" posture this whole project
already takes with `PlaceholderRig`. **For whoever owns UI**: replace
`kick_to_kick.gd`'s `_build_placeholder_prompt()`/`_set_hint_text()` with
the real coach-left/bubble-right presentation; the hook is `hint_changed`
off `KickChallenge` plus the four state-transition points in
`kick_to_kick.gd` (`_on_coach_range_entered`, `_begin_dialogue`,
`_accept_challenge`, `_on_challenge_ended`) — none of that needs to
change shape, just what renders it.

**New input actions**: `interact` (`Q`/X — physically shared with
`handball`, same "one physical control, two logical actions, game state
picks which" pattern as everywhere else in this input map; only matters
while not carrying, so no real collision with handball), `confirm`
(`Y`/A — A freed up last session when marking hadn't claimed it yet),
`decline` (`N`/B — shared with `bounce`/`tackle`, a third context on an
already phase-remapped button).

**Input actions verified**: while writing this pass I re-derived and
cross-checked every physical keycode against ASCII (Y=89, N=78 — matches
the same convention every other letter key in this file already uses) and
pattern-matched the new `project.godot` blocks character-for-character
against existing verified blocks of the same event type, same discipline
as last session's input-map work.

### Bug caught and fixed before it shipped

`kick_to_kick.gd` originally connected both `KickChallenge.target_hit`
(2 args: hits, attempts_used) and `target_missed` (1 arg: attempts_used)
to the same two-parameter handler. That would have thrown the first time
a kick actually missed — not caught by any static read-through, only by
tracing what each signal actually emits against what its handler
declares. Removed the handler entirely; both signals' only real consumer
was already `hint_changed`, which is correctly wired.

### Verification, and its limits (same gap as last session)

Still no Godot binary available in this environment — same limitation as
last time, see §6 there. Everything above was checked by full re-reads of
every touched/new file, tracing the coach/dialogue/challenge state machine
by hand for the whole flow (approach → prompt → accept/decline → re-prompt
→ challenge → hit/miss/out-of-bounds → end), and specifically auditing
every new signal `.connect()` call's parameter count against what the
corresponding `signal` declaration actually emits (which is what caught
the bug above — worth calling out as a category, since it's exactly the
kind of thing that reads fine top-to-bottom and only breaks at the moment
a particular signal actually fires). The kick-distance fix was checked
numerically (a standalone script stepping the same drag+gravity model
`KickTrajectory` uses), not just eyeballed. None of this substitutes for
an actual playtest — that's still the next real step, same as last time.

No RULES_REFERENCE.md numbers were relied on for any of this pass — kick
distance is tuned by feel/observation against the brief's own "usually
60+ metres," not an AFL rule number, and the coach/challenge system is
new mechanics of this project's own design, not a P1 rule being ported.

**Addendum, same session**: the verification gap above is now closed. The
user surfaced the Godot binary path
(`C:\Users\Bozzy\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-
stable_win64_console.exe`) via a real launch that hit `Could not find
type "CoachNPC"/"KickChallenge" in the current scope` — not a code bug,
a stale `.godot/global_script_class_cache.cfg` from before those two
scripts existed, which a plain game/headless launch trusts rather than
rescanning. Fixed with `--headless --editor --quit`, which forces the
scan and registers new global classes without needing a GUI. With that
done, actually ran headless: the project's own documented smoke test
clean, plus `kick_to_kick.tscn` and `full_game.tscn` each booted directly
(`--headless --path . "res://scenes/modes/X.tscn" --quit-after 180`) with
zero errors — the first real (not just static) verification this agent
has been able to do this project. Binary path and the exact incantations
are saved to this agent's memory so future sessions don't have to
rediscover them.

---

## Handover — coach fixes + P1-informed aim rework (Agent: mechanics/engine)

Second playtest round. Three quick coach bugs, then a real rework of kick
aiming after consulting Prototype 1 directly (`E:\aussie-rules_game`) at
the user's explicit request, rather than guessing at "smooth."

### Coach fixes

1. **Coach floated 0.5m off the ground.** `_setup_coach()` positioned it
   at `Field.centre() + COACH_STAND_OFFSET` wholesale — but `centre()`
   returns `Vector3(0, 0.5, 0)`, tuned for resting a *ball* there, not a
   standing rig whose own local origin already means "feet on the
   ground." Now takes only centre's X/Z, Y forced to 0.
2. **No ball at the start of a challenge.** Coach interaction is gated on
   `not is_carrying()` by design (§5 last entry), so the player is always
   empty-handed when `_accept_challenge()` runs — but nothing was giving
   them a fresh ball. Now calls the existing `_reset_ball()` (same
   placement the debug-reset/out-of-bounds paths already use) right
   before `KickChallenge.begin()`.
3. **Gamepad sprint moved to L3 click** (FIFA-style, per direct request),
   off RT — RT can no longer safely double as sprint now that it's the
   kick trigger regardless of ADS state (see below). `walk`'s gamepad
   binding (also L3, a direct conflict) is gone rather than relocated —
   a gamepad's stick is already analog, so the discrete "walk" tier it
   provided was really only ever necessary for keyboard, which has no
   analog input to fall back on and keeps `Ctrl`. No `get_gait()` logic
   changed, `InputMap` only.

### Kick aim, actually checked against Prototype 1 this time

Last session's "hold LT to aim" model was engineered from the design
brief's prose alone. The user played it, said it wasn't smooth on a pad,
and specifically asked to check how Prototype 1 did it before touching
anything — so an Explore agent went and read `controller.py`/
`gameplay.py`/`mechanics.py`/`settings.py` directly rather than guessing.
Findings that actually changed the plan:

- **P1 gates aiming behind a hold too** (`K_2`/LT → `enter_aim_mode`,
  *then* the stick moves things). The brief's "I just used right stick
  for aiming" describes what happens *inside* that gated mode, not a
  ungated always-on aim — so last session's LT-gate structure was
  already right and did not need removing. Good to have checked before
  ripping it out.
- **P1's aim is a velocity-driven cursor** (`_aim_cursor += stick *
  AIM_CURSOR_SPEED * raw_dt`, unprojected through the camera each frame),
  not a raw angle-rate rotation — plus the whole world runs at
  `SLOWMO_FACTOR = 0.25` while aiming, with the cursor itself exempted
  (moves on `raw_dt`, not the dilated one) so aim input stays crisp while
  everything else slows down. Both are real, cited contributors to "felt
  fine." **Neither is ported here** — a full 2D-cursor/ground-unprojection
  system and a selective time-dilation layer are both significant,
  invasive rearchitectures that touch far more than kicking (the dilation
  in particular would need to reach animation timing, AI decision timers
  and ball physics without slowing the very input it's meant to keep
  crisp), and neither was explicitly asked for — noted here so the option
  is visible, not silently dropped. What *did* change: `KICK_AIM_YAW_SPEED`
  180→100 deg/s, the simplest available lever toward "controlled, not
  twitchy" without either of those.
- **P1 has a real, deliberate, separately-implemented aim-assist**
  (`apply_aim_assist`/`AIM_ASSIST_RADIUS`/`AIM_ASSIST_STRENGTH = 6.0`,
  soft-pulls the cursor toward the nearest teammate, controller-only,
  confirmed structurally distinct from the `KICK_SCATTER_*`/`PRESSURE_*`
  accuracy-under-pressure system a previous research pass had already
  found). Ported the constant directly — the blend formula
  (`k = min(1, STRENGTH·dt)`) is a dimensionless fraction, so it carries
  over even though P1 blends 2D screen pixels and this blends a 1D world
  yaw. `CONE_DEG`/`RANGE` have no P1 equivalent (P1's radius gate is in
  screen-space pixels around a cursor, which doesn't translate to a
  world-space angle system) — first pass at the same idea, not a port.
- **P1 has no hip-fire/ADS split** — every kick, human or AI, goes
  through the identical aim-cursor pipeline. The "RT alone = quick,
  imprecise, facing-based kick" the user asked for (an explicit FPS
  analogy) has no P1 precedent; it's this project's own addition,
  confirmed as such so it doesn't get mistaken for a port later.

**What actually changed in `player_controller.gd`:**
`_update_charge()` is now a three-way branch instead of two: LT held →
existing ADS charge/aim/execute flow, unchanged in shape; LT released
mid-charge → cancel, unchanged; **RT tapped with LT never having been
held this attempt → new hip-fire branch** — fixed `KICK_HIP_FIRE_CHARGE`
(0.55, since there's no stance to charge power through), aim snapped
fresh to body-facing every time (not whatever `_kick_aim_yaw` was last
left at by an earlier *cancelled* ADS attempt — that would've been a real
staleness bug), fires immediately. `_apply_kick_accuracy()` split into a
shared `_apply_spread()` primitive plus the existing skill-based caller,
so the new `KICK_HIP_FIRE_SPREAD_DEG` scatter (stacks on top of the
skill-based one, doesn't replace it) can't drift out of sync with how the
existing spread already rotates a launch vector. New `_apply_aim_assist()`
+ `_nearest_teammate_for_assist()`, called from `_update_kick_aim()` each
frame while charging, gamepad-only (matches P1's own controller-only
gate — a mouse already points exactly where aimed).

**A bug caught by re-checking the tackle-interruption path**: a hip-fire
kick's swing can be interrupted by a tackle before `_dispose()` ever
reads `_hip_fire_kick`, which would have left it stuck `true` — so the
next kick to actually resolve, possibly a properly-aimed one with a
freshly gathered ball, would have wrongly inherited hip-fire's scatter.
Fixed by resetting it in `drop_ball()`, which already resets `_kick_charge`/
`_charging` for the identical "abandoned mid-kick" reason.

### Verification

Same real headless passes as last entry, now also covering this code:
`full_game.tscn` for 240 frames (AI on both teams actively commits and
fires kicks every match, so this genuinely exercises the new hip-fire-
adjacent `_update_charge` branch and the aim-assist teammate search, not
just a parse check) and `kick_to_kick.tscn` for 180, both clean, zero
errors. Re-verified by hand: the `_hip_fire_kick`/`drop_ball()` interaction
above, that AI never reaches the hip-fire branch (`wants_kick()` is always
true before AI ever pulses execute, so it can't fall through to the RT-
alone branch), and that `_apply_aim_assist` safely no-ops in `kick_to_kick`
(no other `PlayerController` exists there for the teammate search to find
— confirmed intentional, not a bug, since `CoachNPC` is deliberately not
in the `"players"` group).

No RULES_REFERENCE.md numbers relied on. Prototype 1 specifics quoted
above (`AIM_ASSIST_STRENGTH`, `SLOWMO_FACTOR`, etc.) are cited from the
research pass, not RULES_REFERENCE.md, which doesn't cover aim-assist at
all — worth adding a line there if this direction holds up under play.

---

## Handover — kick power off the aim stick, not the trigger (Agent: mechanics/engine)

Third playtest round on the same system. The user rejected the previous
entry's power model outright: LT pull-depth, even live-adjustable, is
still fundamentally a squeeze. What they wanted instead is the stick's
Y-position read directly as power — wherever the trajectory preview line
currently reaches to, full stop, pushed forward for further and eased
back for shorter, with no separate "charge" value underneath it at all.

### What changed

`InputManager.kick_stance_strength()` → renamed `kick_reach_strength()`
and re-sourced: was `Input.get_action_strength(&"kick_stance")` (LT's own
analog depth), now `clampf(get_look_vector().y, 0.0, 1.0)` — the same
right-stick vector `_update_kick_aim()` already reads `.x` off for aim
yaw. `human_brain.gd`'s `kick_charge_override()` call site updated to
match; `player_brain.gd`'s doc comment updated for the same reason.
`player_controller.gd` itself needed no logic change — `_update_charge()`
already treated any `override >= 0.0` as "this is the power, full stop,"
so swapping what feeds that override was a one-line change one layer
down. LT still gates entry into the aiming stance at its existing 0.2
deadzone (`project.godot`); it just no longer reports a depth anyone
reads for anything.

Keyboard (with or without mouse) is unaffected: `InputManager.device`
tracks mouse motion as `Device.KEYBOARD`, so `kick_reach_strength()`
returns the `-1.0` sentinel for both, same as before, and `_update_charge()`
falls through to the pre-existing `_kick_charge + delta / KICK_CHARGE_TIME`
hold-ramp. AI is likewise untouched — `AIBrain` doesn't override
`kick_charge_override()`, so it inherits `PlayerBrain`'s base `-1.0` and
always ramps too. Only a human on a gamepad reads differently than it did
last round.

### A coupling worth knowing about, not changed

`get_look_vector()` runs the raw stick through `_shape()`, which scales
the **combined 2D magnitude** by `pow(magnitude, LOOK_CURVE)` (curve =
2.0) and reapplies that as one uniform factor to both x and y. That curve
was picked for camera-look feel, back when x and y were both "look," i.e.
one job. Now x is aim yaw and y is power — two logically separate values
sharing one physical stick — and the shared magnitude curve means they
are not read fully independently: nudging aim (x) while holding a power
level (y) measurably changes the read power, and vice versa, because both
axes are scaled by whatever the *combined* deflection works out to, not
by each axis's own deflection. Concretely: holding raw `(0.3, 0.3)` — a
moderate aim nudge at moderate power — shapes down to roughly `(0.13,
0.13)`, not `(0.3, 0.3)`, because `pow(0.424, 2) ≈ 0.18` is the factor
applied to both. Small aim corrections during a held power barely move
it; a large simultaneous diagonal push (aiming hard off to one side while
holding high power) will visibly suppress the power reading versus
pushing straight forward at the same perceived effort.

Not fixed here — no playtest evidence yet that this is what anyone would
actually feel as "power feels jumpy," and the fix isn't obvious even if
it is: shaping x and y independently (two separate `pow()` calls instead
of one radial one) is a small change, but whether that's the *right* feel
for aim-yaw specifically (camera-look elsewhere still wants the radial
curve) is itself a judgment call this agent can't make from static
reading. Flagged so a future round has the actual cause on hand rather
than re-deriving it from a "kicking feels inconsistent while aiming off
to the side" bug report.

### Verification

Same two real headless passes as both prior entries: `full_game.tscn` for
240 frames and `kick_to_kick.tscn` for 180, both clean, exit 0, zero
errors — confirms the rename and re-sourcing didn't break parsing or
either scene's actual kick path (AI kicks every match in `full_game`,
exercising `_update_charge`'s ramp branch same as always; a human brain's
new stick-Y branch has no AI equivalent to exercise headless, so this
only rules out parse/runtime breakage, not feel — same limitation every
entry in this doc has flagged). Confirmed by reading, not runtime: only
`kick_reach_strength()`, its one call site, and doc comments changed —
`_update_kick_aim()`'s x-read and the aim-assist added last round are
untouched by this round's diff.

### Open questions carried forward

None of the tuning constants from the last two rounds have been
playtested since landing — `KICK_HIP_FIRE_CHARGE` (0.55),
`KICK_HIP_FIRE_SPREAD_DEG` (20°), `KICK_AIM_ASSIST_CONE_DEG`/`RANGE`
(18°/60m — `STRENGTH` at 6.0 is P1-sourced, higher confidence than the
other two), and now whether the x/y curve-coupling above is even
noticeable at the stick deflections a real kick actually uses. All first-
guess numbers or carried-over defaults, not verified by feel. Next round
should be a play pass, not another static read.

---

## Handover — trajectory preview was cut short of its own landing ring (Agent: mechanics/engine)

Bug report from actually playing this build: the dashed trajectory line
visibly stopped short of the landing ring instead of connecting to it,
and stronger kicks didn't look like they reached any further than weaker
ones. Both symptoms turned out to be the same root cause.

### Root cause

`KickTrajectory._simulate()` (`scripts/player/kick_trajectory.gd`) stepped
the flight model for exactly `MAX_DOTS` iterations (22) at `DOT_STEP_TIME`
(0.05s) each — 1.10 simulated seconds, full stop, whether or not the ball
had come back down yet. That constant was doing two unrelated jobs at
once: "how many dots to draw" (a rendering/perf concern) and "how long to
simulate" (a correctness concern) — fine while they happened to be the
same number, which they aren't once a real kick's flight time is
considered. A full-charge kick at the `Tuning.KICK_MAX_ANGLE`/`_SPEED`
this project actually uses takes on the order of 3.5s to land (confirmed
by running the restructured model standalone, see Verification) — more
than 3x the old budget. The landing ring was then placed at
`points[points.size() - 1]` with `y` force-set to ground height
regardless of whether that last point was actually on the ground — so for
any kick beyond a weak stab pass, the dashed line simply stopped in
mid-air around apex, and the ring snapped to the ground directly beneath
that mid-air point, nowhere near where the ball would really land. Since
`_kick_parameters()` already multiplies speed by `kick_power_scale` for
*both* the real kick and this preview (same function, see the previous
entry's diagram of that call graph), the underlying physics was already
scaling correctly with the character's kicking-power stat — the preview
just couldn't show more than the first ~30-100% of it depending on charge,
which reads exactly like "distance doesn't seem to follow kicking power"
even though the real kick already did.

### Fix

Split the one job into two. `_simulate()` now steps until the ball
actually reaches `GROUND_HEIGHT` (or a `MAX_SIM_SECONDS` = 8.0s safety
valve, ~2x more than the slowest realistic landing even at
`CHARACTER_KICK_POWER_MAX`, so it should never actually bind) and returns
every raw point — this is the one that has to be physically correct, so
it doesn't get to stop early for rendering-budget reasons. A new
`_downsample()` then thins that full path down to at most `MAX_DOTS`
points spread evenly from boot to landing for the dashed line — a pure
rendering concern, kept separate on purpose so neither job can
accidentally shortchange the other again. The landing ring reads from the
full (non-downsampled) path's true last point, so it always sits exactly
where the last dot is, connected, not floating below it. Short kicks that
already landed within 22 steps are unaffected — `_downsample` returns the
array unchanged when there's nothing to thin.

### Verification

Both standard headless passes (`full_game.tscn` 240 frames,
`kick_to_kick.tscn` 180 frames) clean, exit 0 — confirms no parse/runtime
break, though neither exercises the new code's actual values since the
preview only updates for a `HumanBrain` (see `_update_charge`) and
headless has no human driving one. So this was also checked numerically:
a scratch `--script` run (`extends SceneTree`, instantiated
`KickTrajectory` directly and called `_simulate`/`_downsample` with no
scene tree needed, since neither touches `_dots`/`_ring` — deleted after,
not part of the diff) confirmed, at max charge and `kick_power_scale`:
73 raw steps / 3.65s flight / lands at `y≈0` (not mid-air), downsamples
to exactly 22 dots whose last entry equals the true landing point, and
that distance scales with `kick_power_scale` as expected — 24.7m at 0.7x,
45.2m at 1.0x, 67.8m at 1.3x, all at the same full charge. A weak
min-charge/min-power kick landed in 13 raw steps, under the 22-dot cap,
confirming the unchanged path for short kicks.

---

## Handover — aim starts from the camera, not the body; keyboard/mouse power off the ramp (Agent: mechanics/engine)

Two more asks from the same play session. Both are about where a kick's
aim *starts* and how its power is *set*, not the trajectory maths from
the previous entry (untouched this round).

### Aim starts from the camera, not body facing

The concrete complaint: camera turned to line up a shot on goals while
the body's still running a different line — pull LT, and the kick used
to start aimed wherever the *body* was facing, not what was on screen.
`_update_charge()` snapped `_kick_aim_yaw = _facing_yaw` the instant
stance began; the right stick/mouse could swing it from there, but the
starting point itself ignored the camera entirely.

New `PlayerController._current_look_yaw()` reads the camera's own current
forward vector (`camera.global_transform.basis.z`, flattened to yaw —
same `atan2(-x, -z)` convention `_update_facing()`/`_nearest_teammate_for_
assist()` already use, just pointed at the camera instead of a movement/
facing direction) and that's what the aim now snaps to on entering
stance. `camera` is already the actual `Camera3D` leaf
(`BroadcastCamera.camera()`, assigned by each mode — see `main.gd`/
`kick_to_kick.gd`/`full_game.gd`), which inherits the full yaw+pitch the
rig's `$Yaw`/`$Pitch` pivots apply, so this needed no new coupling to
`BroadcastCamera` itself, and mirrors `HumanBrain.wish_direction()`'s
existing camera-forward-flattening pattern rather than inventing a
second one. Falls back to `_facing_yaw` with no camera assigned — AI
never gets one (`full_game.gd` only assigns `camera` to the one
human-controlled `PlayerController`), so **AI kicks are unaffected, still
body-forward, exactly as before**. Hip-fire is *deliberately* left on
`_facing_yaw` too — it's specifically the "didn't aim down sights"
option, so it stays tied to the body on purpose; only the ADS/stance path
changed.

**New: `KickCrosshair`** (`scripts/ui/kick_crosshair.gd`, plain
`CanvasLayer`, no `.tscn` — built in `_ready()`, same "simple enough not
to need a scene file" call `kick_to_kick.gd`'s placeholder prompt already
made). A small dot pinned to screen centre — no 3D→2D projection needed,
since for a perspective camera with no lens offset "straight down the
camera's forward axis" *is* screen centre by definition, so the widget's
position never has to know anything about the camera's actual rotation.
Faint (`IDLE_ALPHA` 0.35) normally, brighter (`AIM_ALPHA` 0.85) while
`player.is_kick_aiming()`, lerped between the two rather than snapped.
Colour matches `KickTrajectory`'s gold on purpose (same "this is the
kick-aim system" visual language as the dashed line/ring) but as its own
literal `Color` constant, not a cross-class reference — see the next
section, that turned out not to be optional. Instantiated once per mode
(`kick_to_kick.gd`, `full_game.gd`) alongside the existing `_hud.player =
...` assignment, and re-pointed at the new player in `full_game.gd`'s
`_switch_human_player()` the same way `_hud.player` already is.

**Papercut hit while building it, and a correction**: `KickCrosshair`
first read `KickTrajectory.COLOUR` directly, and briefly failed to
compile — `Parse Error: Cannot find member "COLOUR" in base
"KickTrajectory"`. First guess was a genuine GDScript limitation on
cross-`class_name` const access and said so here; that guess was wrong,
worth correcting rather than leaving stated as fact. `SoftBrutalist.
ACCENT_PRIMARY`/`.INK`/`.panel_style()` are the exact same shape of
access (`class_name` script, `const`/`static func`, referenced from
`debug_hud.gd` by class name) and work fine, including in this entry's
own `KickCrosshair` once pointed at `SoftBrutalist` instead — so cross-
class const access isn't the problem. Far more likely: `kick_trajectory.
gd` was being actively hand-edited in the Godot editor, in parallel with
this session, for the entire second half of this round — dot tapering
(size/alpha gradient along the trail), a two-layer pulsing landing ring,
and its colour switched from a local literal to `SoftBrutalist.
ACCENT_PRIMARY.lightened(0.35)` (an *instance* field now, computed in
`_ready()`, not the `const COLOUR` this entry's first draft above was
written against — see that file directly, not this doc, for its current
shape). The compile error most likely caught a mid-save/transient state
of that file, not a real language limitation. Once noticed,
`KickCrosshair` was pointed at the same `SoftBrutalist.ACCENT_PRIMARY.
lightened(0.35)` source directly (not read live off `KickTrajectory`,
which is a per-instance field there now, not a class-level constant
anything else could reach into) so the dot keeps matching the trail/ring
it's meant to visually agree with. `kick_trajectory.gd`'s other visual
changes are untouched by this session — not this agent's work, not
reverted, not reviewed for correctness, purely noted so the diff makes
sense to whoever reads it next.

### Keyboard/mouse power off the ramp

The complaint: keyboard still used last round's outdated model — hold K,
power ramps up over `KICK_CHARGE_TIME`, one-way, release-and-recharge to
go back down. Gamepad got a live/reversible reach in the "kick power off
the aim stick" entry above; keyboard didn't.

The fix reuses machinery that was already half-there rather than
inventing a parallel system. Two things were sitting idle during aim:

- **Arrow up/down**, bound to the same `camera_up`/`camera_down` actions
  `InputManager.get_look_vector()` already reads for `.y` — already
  flowing through that function for keyboard players, just never
  consumed, since `_update_kick_aim()` only ever read `.x` off it (for
  yaw) and `kick_charge_override()`/`kick_reach_strength()` explicitly
  gate `.y` to gamepad only.
- **Mouse vertical motion**, drained every frame by `take_mouse_look()`
  alongside `.x` (which drives yaw), with `.y` simply discarded.

`_update_kick_aim()` now spends both, for any non-gamepad device: arrow
up/down as a held *rate* (`stick.y * delta / KICK_CHARGE_TIME` — same
pacing the ramp and AI's ramp both already use, deliberately not a second
independent knob), mouse motion as a raw per-frame delta
(`Tuning.KICK_MOUSE_REACH_SENSITIVITY`, new constant, pixels→power-
fraction same idea as `CAM_MOUSE_SENSITIVITY` but unitless instead of
degrees). Both added into `_kick_charge`, clamped 0..1, live and
reversible either direction — arrow-up/mouse-forward raises it, arrow-
down/mouse-back lowers it, matching the sign convention `_update_rotation
()`'s existing mouse-pitch term already set (`_pitch -= mouse.y`, i.e.
mouse-up increases the value it's steering).

Getting there took a wrong turn worth recording: the first draft tried
making `kick_reach_strength()` device-agnostic (drop its `device !=
GAMEPAD` gate, since `get_look_vector().y` already reads arrow keys) and
let `_update_charge()`'s existing `override >= 0.0` branch handle
keyboard too, same as gamepad. That's wrong — that branch treats the
value as an absolute position (`_kick_charge = override`, a hard snap
every frame), which is correct for a stick that physically holds its
deflection but not for a digital key: a keyboard player not currently
holding either arrow reads `0.0` — still `>= 0.0`, so it *snaps* `_kick_
charge` back to zero every single frame arrows aren't held, wiping out
any mouse-driven adjustment made a moment earlier before it could
persist. `kick_charge_override()`/`kick_reach_strength()` were left
exactly as they were (still gamepad-only); the keyboard path lives
entirely in `_update_charge()`'s new `elif not (_brain is HumanBrain)`
branch (skips the ramp for a human on keyboard, since `_update_kick_aim`
handles it) plus the accumulation in `_update_kick_aim()` itself — an
accumulator that's nudged, never snapped, which is what actually makes it
reversible without self-erasing.

**Not carried over on purpose**: the x/y shared-radial-curve coupling
flagged in the "kick power off the aim stick" entry (`LOOK_CURVE`
shaping `get_look_vector()`'s combined magnitude before x/y split) also
applies to two arrow keys held together — e.g. up+right for power+yaw at
once shapes to roughly 71% of either held alone. Same root cause as the
gamepad note, not re-litigated in full here; flagging once more since
this is now the second control scheme it quietly touches.

### Verification

Both standard headless passes clean, exit 0, after first re-running the
`--headless --editor --quit` global-class-cache rescan this project's
memory already documents (`KickCrosshair` is a brand-new `class_name` —
skipping the rescan reproduces exactly the stale-cache failure that note
warns about, confirmed by hitting it, not just reading about it, on the
first attempt before the `COLOUR` fix was even in yet). Neither headless
pass exercises `_current_look_yaw()`'s human path or the new keyboard
power accumulation directly — headless generates no real input events, so
`_charging` never goes true for a `HumanBrain` there — but both do
exercise `KickCrosshair._process()` every frame (idle-alpha path, no
errors) and confirm AI's unchanged body-forward/ramp paths still compile
and run through a full match/practice session. The yaw maths itself
wasn't re-verified numerically this round — it's the same `atan2(-x,-z)`
pattern already proven correct three other places in this file, applied
to a fourth vector, not new maths.

### Open questions carried forward

All new this round, none playtested: `Tuning.KICK_MOUSE_REACH_SENSITIVITY`
(0.0035, a first guess at how many pixels should swing empty-to-full),
whether arrow-key power (a purely binary 0-or-1 input, unlike the
gamepad's or mouse's continuous one) feels acceptable as a fallback or
needs its own easing, and the crosshair's own idle/aim alpha and fade
rate (0.35/0.85/rate 10). Plus everything already open from the last two
entries — none of that has been played either.

---

## Handover — three-tier marking, ground pickup, spoil/smother, holding-the-ball ruling (Agent: mechanics/engine)

Design brief priorities 2 and part of 3. The "Deferred" section several
entries up explicitly declined to build marking/spoil/smother without a
spec — this pass builds them against the brief's own three-tier
description plus RULES_REFERENCE.md §4, and calls out exactly where an
invented value sits versus a real AFL rule.

### 1. Movement (priority 1) — verified, not rebuilt

Read `player_controller.gd` end to end against the brief's Madden/FIFA
movement ask before touching anything: asymmetric ACCELERATION/BRAKING,
TURN_RATE_STANDING→TURN_RATE_SPRINT falloff producing the plant-and-pivot
emergently, REVERSE_SPEED_SCALE, momentum-driven `_heading` distinct from
`_facing_yaw` feeding the animation strafe axis — all already there and
already matches the brief closely (this is the same system multiple past
entries in this doc built/tuned). Left alone. No Godot binary access to
actually feel it on a pad — verified by headless boot + code reading only,
same caveat every past entry here has flagged for anything requiring a
human hand.

### 2. Three-tier marking (priority 2)

New `Tuning.Action` entries `MARK_SAFE`/`MARK_RUNNING`/`MARK_AGGRESSIVE`,
appended (not inserted) so `ACTION_DURATION`/`ACTION_CONTACT`'s existing
KICK/HANDBALL/BOUNCE indices don't shift. New
`Tuning.action_speed_scale(action)` generalises the old flat
`ACTION_SPEED_SCALE` so each tier can cost a different amount of
movement — Safe plants (0.30), Running barely breaks stride (0.88),
Aggressive's mid-air control comes from the existing `AIR_ACCELERATION`
instead.

**Ball eligibility** (`ball.gd`): `launch()` gained a 5th param
`is_kick_disposal` — only `PlayerController._dispose()`'s KICK branch
passes `true`. Ball tracks `_flight_origin`/`_is_kick_flight`, cleared on
landing (the `landed` signal path) or on `attach_to()`/`reset_at()`.
`is_mark_eligible()` is straight-line distance from `_flight_origin` ≥
`Tuning.MARK_STAND_MIN_DISTANCE` (15m, the same real number
RULES_REFERENCE.md already names for stand-the-mark — one rule, two
consequences, one constant). Centre bounces/handballs/bounces never set
the flag (default `false`), so they can never be marked, matching real
AFL.

**Resolution** (`player_controller.gd`, new "Marking" section): no RNG
anywhere, matching RULES_REFERENCE.md §3's stance. Safe (A, held) is a
per-frame reach test against the ball's live position while held —
generous, no commitment, matches "lowest risk, default option." Running
(X, tap) is a single-frame reach test at a tighter radius, full speed,
silent whiff if it doesn't connect (same "button press with nothing to
act on no-ops" precedent `wants_handball()` already sets). Aggressive (Y,
tap) always commits — a real vertical impulse
(`Tuning.MARK_AGGRESSIVE_JUMP_SPEED`, ~0.82m of added reach) through the
*existing* gravity/`is_on_floor()` integration, no separate jump-arc
code — resolved at the jump's timed peak via the same `_action`/
contact-time machinery kick/handball/bounce already use, just dispatched
to `_resolve_aggressive_mark()` instead of `_dispose()`. A clean miss
leaves the ball untouched — no contact, no effect, physically honest
rather than a scripted bounce-off.

Legal marks grant `_protected_timer` (`Tuning.MARK_HOLD_DURATION`, 5s —
RULES_REFERENCE.md's already-named constant) which `_try_tackle()` now
checks (`other.is_protected()`) — the actual stand-the-mark mechanic
doesn't exist yet (needs an opponent obligated to stand still, not just
tackle-immunity), but the *protection* half is live and correct, and it's
the same primitive a kick-in's goal-square immunity (priority 5) will
want. Cleared early on disposal (`_dispose()`) or losing the ball
(`drop_ball()`) — playing on forfeits it, matching the real rule's
spirit.

**Ground pickup**: same `A`/`mark_safe` input, but once
`Ball.is_airborne()` is false it means something else
(`_update_ground_pickup`) — a wider, speed-responsive reach
(`GROUND_PICKUP_RADIUS` plus a per-m/s lunge term) than the pre-existing
passive `_try_gather()`, which is untouched and still fires on simple
walk-over overlap (zero regression — verified both paths independently,
see below). This is the brief's "ball state + player state + proximity +
input, not just the button" line applied literally.

**Brains**: `PlayerBrain` gained `wants_mark_safe/running/aggressive`
(default false), `HumanBrain` reads three new InputMap actions, `AIBrain`
gets a Safe-only stub (holds up for a catch when it's the closest
teammate to an airborne ball within `MARK_CONTEST_RANGE`) — deliberately
not smarter than that, matching the existing "not a tactics system" AI
philosophy `ai_brain.gd`'s own docstring already states.

**Input map**: `mark_safe` (G / gamepad A), `mark_running` (Q / X —
shares the physical control with `handball`/`interact`, the established
"one control, several logical actions, game state decides" pattern this
file already uses 3-4 deep on B/C/X), `mark_aggressive` (H / gamepad
**Y** — the physical Xbox Y button was fully free; the `confirm` action's
keyboard `Y` is a different, coincidental thing, see below). Confirmed
via a full audit of every existing `button_index` in the file before
assigning — worth being explicit about since an earlier entry in this doc
already flagged Y as "reserved" for exactly this.

**A note on "Y" that's easy to get backward**: `confirm` (accept the
coach's challenge) is bound to keyboard letter **Y** (mnemonic "yes")
*and* gamepad button **A** (Xbox's actual confirm button) — not gamepad
Y. Gamepad button_index 3 (the physical Y button) was genuinely unused
before this pass, freed up by an earlier session specifically "for the
brief's own 'Aggressive mark' reservation" (see the tackle-rework entry
above) — confirmed by grep before relying on it, not assumed. That same
audit is also what confirmed **RT stays the kick trigger, not sprint**:
an earlier session already moved gamepad sprint to L3 click specifically
because "RT can no longer safely double as sprint now that it's the kick
trigger regardless of ADS state" — so the brief's "RT: Sprint/chase"
line for priority 3 is read here as already satisfied by the existing
`sprint` action (which has nothing to do with possession state either
way), not as an instruction to rebind a trigger that's already carrying
kick charge/execute.

**Animation**: `PlaceholderAnimations` gained
`_build_mark_safe/_running/_aggressive` (same pose-keyframe machinery as
kick/handball/bounce — nothing new architecturally), registered in
`PlayerAnimation.ACTION_STATES`, fully data-driven from there (the
state-machine builder already iterates the dict generically).
Aggressive's clip is the one with a real lead-in (crouch/reach/peak/land)
rather than pure follow-through, timed against
`ACTION_CONTACT[MARK_AGGRESSIVE]` to land near the jump's physical peak.

**Marking coach + MarkChallenge** (`kick_to_kick.gd`, new
`scripts/mechanics/mark_challenge.gd` + `.tscn`): mirrors the kicking
coach almost exactly, per the note two entries up ("what actually ends up
shared once the marking/tackling coaches exist isn't knowable yet —
that's a refactor for when there are three of these"). This is that
refactor's first half: `kick_to_kick.gd`'s single-coach state machine
(`CoachState` plus one `_coach`/`_challenge` pair) is now parameterised
by a `CoachKind` enum (`KICKING`/`MARKING`) so the prompt/dialogue/
challenge flow is genuinely shared, not duplicated —
`_spawn_coach(offset, kind)`, `_coach_node(kind)`, every handler takes or
branches on `kind`. A third coach (tackling) slots into the same shape
later. `MarkChallenge` differs from `KickChallenge` in one structural way
worth knowing: it's the *deliverer*, not just an observer — the coach
launches real kick-flight balls at the player (`Ball.launch(...,
is_kick_disposal=true)`, so coach feeds count as legal marks same as any
boot) on its own pacing rather than reacting to player-initiated kicks,
using a small inverse-ballistics helper (closed-form no-drag range
estimate plus one simulated correction pass, not a full iterative
solver — a training delivery only needs to arrive somewhere reactable,
not land on an exact spot).

### 3. Spoil and Smother (priority 3, partial)

Reuses the marking contest's reach-test primitives directly. **Spoil**
(`_try_spoil`, LT tap — `P` / axis4, shares the physical LT with
`kick_stance`, mutually exclusive by `is_carrying()` same as everywhere
else): a cooldown-gated punch at any airborne ball in reach, applies
`Ball.knock()` (new small public method — an external hit that clears
mark eligibility the same way landing does, kept encapsulated rather than
letting callers reach into `_is_kick_flight` directly). No target player
to name: physically deflecting the ball is sufficient to spoil whoever
else was reaching for it, since their own `_ball_in_catch_reach` reads
the ball's real post-knock position — nothing needed to coordinate across
players.

**Smother** (`_try_smother`/`_get_smothered`, X tap — shares Q/X with
handball/interact/mark_running, a fourth meaning on that one physical
control, mutually exclusive by state in every mode that actually has more
than one player type on the field at once): targets an opponent still
carrying whose kick hasn't left yet (new `is_mid_kick_swing()` public
getter, paired with the existing `is_kick_aiming()`), cancels the kick
outright and drops the ball right at their feet (`SMOTHER_SPILL_SPEED`,
much lower than a tackle's spill) rather than the fuller tackle-style
scatter — no stun, since blocking a kick isn't knocking a player down.

Neither has a dedicated Tuning.Action/placeholder animation yet — same as
tackle, which has shipped without one for several sessions already (an
instantaneous physical contest, not a windup-and-contact disposal).
Cosmetic gap, not a functional one.

### 4. Holding-the-ball ruling (RULES_REFERENCE.md §4)

The ruling only — not the free kick itself, which needs a set-shot
apparatus this project doesn't have. New `_possession_held_seconds` on
`PlayerController`, reset whenever `is_carrying()` goes false, distinct
on purpose from `MatchState.possession_seconds()`: that one tracks the
*team's* unbroken hold and, by inspection of its setter, does **not**
reset on a same-team handball (`if possession == value: return`
short-circuits before the reset) — which would wrongly blame a player
tackled the instant they receive a handball for time their teammate
already spent holding it. `_get_tackled` now checks the per-player timer
against new `Tuning.PRIOR_OPPORTUNITY_GRACE` (0.5s, RULES_REFERENCE.md's
already-named number) and fires `holding_the_ball_called(tackler)` when
it's a real ruling — silent for the neutral case, since nothing about a
tackle inside the grace window differs from what already happened.
Nothing consumes the signal yet.

### Verification

No GUI/pad access this session either (see the priority-1 note above) —
same limitation every entry in this doc has hit. Compensated with three
levels, same discipline as the trajectory-bug and kick-distance entries
above:

1. **Static**: full re-reads of every touched file post-edit,
   `--headless --editor --quit` global-class-cache rescan after every new
   `class_name` (`MarkChallenge`), `--headless --path . <scene>
   --quit-after N` for `kick_to_kick.tscn`/`full_game.tscn`/the main menu
   after every meaningful chunk — all clean, zero errors, throughout.
2. **Scripted physics, not just parse-clean**: two temporary scenes
   (`_scratch_mark_test.tscn`/`.gd`, `_scratch_defense_test.tscn`/`.gd` —
   deleted, not part of the diff, same "not committed" precedent this
   doc's very first `KickTrajectory` scratch script set) instantiated
   real `Player`/`Ball`/`Field` scenes under real Jolt physics with a
   scripted `PlayerBrain` standing in for input, driving actual kicks/
   marks/tackles through the real code paths rather than reimplementing
   or mocking any of it. First attempt used `--script extends SceneTree`,
   which turned out **not** to bootstrap `[autoload]` singletons
   (`Identifier not found: MatchState` at compile time, only in that
   mode) — a genuinely new gotcha for this project's headless toolkit,
   worth remembering: use a real scene plus the positional-scene-argument
   form for anything that touches an autoload, not bare `--script`.
   Saved to this agent's memory alongside the existing Godot-binary/
   global-class-cache notes.
3. **Results, all passing**: a 20m kick caught (Safe, held) grants
   exactly `MARK_HOLD_DURATION` (5.00s) protection and
   `legal_mark=true`; an 8m kick is caught but grants none
   (`legal_mark=false`) — confirms the eligibility gate is live, not just
   present. Ground pickup succeeds at ~1.05m (outside the passive 0.85m
   `GATHER_RADIUS`, inside the new 1.3m `GROUND_PICKUP_RADIUS`) —
   confirms it's genuinely a *new* reach, not the old one relabelled.
   Aggressive mark: real positive `velocity.y` observed, then a real
   landing (`is_on_floor()` true again) — and, unprompted, a bonus
   confirmation that the catch itself connected and correctly read as
   `legal_mark=false` for a sub-15m flight, exercising the same
   eligibility gate a third way. Smother: kicker stops carrying, stops
   aiming, ball speed drops to near-zero, within one second of the
   defender closing in mid-stance. Spoil: a genuinely mark-eligible,
   still-airborne, still-loose ball has its `is_mark_eligible()` flip to
   false and its velocity visibly deflect off-axis (a nonzero
   X-component appearing on a flight that had none) the instant the
   defender's reach connects — caught mid-flight by a diagnostic print,
   not inferred after the fact.

One test-harness bug worth recording, not a game bug: an early version
of the spoil test kept force-tracking the defender onto the ball's
position every frame *after* the spoil connected too, which then
triggered the pre-existing passive `_try_gather()` a few frames later and
made the ball read `held=true` — briefly looked like a real failure until
the diagnostic log showed the deflection had already happened correctly
a full 0.28s before that. Latching the check the instant a spoil is first
observed fixed it. Recorded because it's exactly the "looks like a bug,
is actually the test" trap worth recognising quickly rather than chasing
into the real code.

### Known limitations, honestly scoped rather than silently dropped

- **Bump (LB hold + right-stick flick) — not built.** Genuinely new
  ground unlike spoil/smother (a flick-gesture detector doesn't exist
  anywhere in this input system yet — `InputManager` only has held-axis
  and tap-edge patterns today) *and* RULES_REFERENCE.md has zero numbers
  for the dangerous-contact/free-kick side of it. A previous session
  already declined exactly this feature for exactly these two reasons
  (see "Deferred" above) — this pass had headroom to close marking/
  spoil/smother but not to also invent a gesture-detection primitive and
  a contact-danger heuristic unsupervised in the same sitting. Sketch for
  next time: reuse `Ball.knock()`-style external-hit plumbing for the
  physical push; the flick itself is probably a magnitude-over-time
  threshold on `InputManager.get_look_vector()`, sampled a few frames
  back, rather than anything stateful in the Input Map; the danger
  judgement needs either real numbers from whoever owns
  RULES_REFERENCE.md or an explicit "not yet enforced" stub matching this
  pass's holding-the-ball pattern (decide the ruling, defer the
  consequence).
- **Holding-the-ball has no consequence yet**, by design this pass — see
  §4 above. The natural next step shares an apparatus with kick-in
  (priority 5): both need "give a player the ball, freeze the opponent's
  ability to contest, let them dispose freely" as a state, which is
  exactly what `_protected_timer` already models for marks. A free-kick/
  set-shot phase built on that primitive would close both gaps in one
  pass.
- **Stand-the-mark itself** (the mark-taker's opponent frozen in place,
  ≥15m marks only) **is still not modelled** — `is_protected()` stops the
  *tackle*, but nothing stops the opponent moving/repositioning. Needs
  Full Game's two-team context to matter at all; inert in solo
  `kick_to_kick`.
- **AI only ever attempts a Safe mark**, never Running/Aggressive, and
  has no spoil/smother/tackle-avoidance awareness at all. Matches the
  existing "deliberately simple, not a tactics system" AI baseline
  already in place for kicking/handballing — noted so it doesn't read as
  an oversight.
- **Ruck contests (priority 4) and protected kick-in (priority 5) are
  untouched** — next in the brief's own ordering. `_protected_timer`/
  `is_protected()` (this pass) is directly reusable for kick-in's
  goal-square immunity; ruck can reuse the aggressive mark's exact
  jump-impulse pattern (`_pending_jump` → gravity integration, no bespoke
  arc code) for ruckmen contesting a bounce.
- **Full Game integration**: marking/ground-pickup/spoil/smother all
  already work in `full_game.tscn` as-is (same `PlayerController`,
  verified via the standard headless AI-match smoke test) — nothing
  mode-specific was assumed. What's *not* done: AI never attempts spoil/
  smother, and there's no human-facing HUD callout for a legal mark or a
  holding-the-ball ruling beyond `DebugHud`'s diagnostic readout.

### Files changed

`scripts/tuning.gd`, `scripts/ball/ball.gd`,
`scripts/player/player_controller.gd`, `scripts/mechanics/player_brain.gd`
/`human_brain.gd`/`ai_brain.gd`, `scripts/player/placeholder_animations.gd`,
`scripts/player/player_animation.gd`, `scripts/modes/kick_to_kick.gd`,
`scripts/ui/debug_hud.gd`, `project.godot` (`[input]` only). New:
`scripts/mechanics/mark_challenge.gd`, `scenes/mechanics/mark_challenge.tscn`.
Not touched: anything UI-owned (`ui_side_scrim.gdshader`/
`team_list_screen.gd` had pre-existing uncommitted changes on disk at
session start from another agent, left exactly as found),
`broadcast_camera.gd`, `full_game.gd` (works unmodified — see Full Game
integration note above), `field.gd`, `team_formation.gd`.

---

## Handover — placeholder rig replaced with a real Skeleton3D (Agent: UI/visual model)

Design brief's own escape hatch for `PlaceholderRig` ("dropping in a
Mixamo character replaces this node and the generated clips; the blend
space, the state machine, the parameter names... stay exactly as they
are") is now built the way that promise actually needs: a real
`Skeleton3D` with a bone hierarchy matching Godot 4's built-in
`SkeletonProfileHumanoid`, driven by `AnimationPlayer`/`AnimationTree`
bone tracks instead of `Node3D` property tracks on bare "joint" nodes.
Pulled current state from this file rather than assuming what a
concurrent mechanics-agent pass might have changed underneath
`player_controller.gd` — nothing there touched the rig/animation API this
pass depends on (its most recent change was `_ball_in_catch_reach`'s
assist-radius bonus and a new `catch_point_position()` getter, both
unrelated).

### Bone hierarchy, and why it's this one

22 bones: `Root → Hips → Spine → Chest → Neck → Head`,
`Chest → Left/RightShoulder → Left/RightUpperArm → Left/RightLowerArm →
Left/RightHand`, `Hips → Left/RightUpperLeg → Left/RightLowerLeg →
Left/RightFoot → Left/RightToes`. This is exactly
`SkeletonProfileHumanoid`'s **required** bone set and parent chain — the
profile also defines optional eye/jaw/finger bones, skipped here since
they carry no gameplay or silhouette weight at this project's current
art fidelity and Godot's own retargeter treats them as optional, not
required, for a BoneMap to resolve. Naming and parenting is what a mocap
importer or Mixamo-via-BoneMap retarget actually matches on; getting that
right (not rest-pose axis perfection — see Known limitations) is what
unlocks "drop in real clips later with no renaming."

### What replaced what

- **`scripts/player/humanoid_rig.gd`** (`class_name HumanoidRig`) replaces
  `placeholder_rig.gd`/`PlaceholderRig` outright (deleted, not kept
  alongside — this was the "likely removed" file the brief flagged, and
  the swap is a straight 1:1 API replacement, confirmed by grepping every
  call site first: `away_kit`, the `HIP_HEIGHT` constant, and the `Rig`
  node name/type are the only things anything outside this file ever
  touched, and all three still exist with the same names). Builds a
  `Skeleton3D` child in code (bone rests from a `BONES` table: name,
  parent, offset — mirrors the old joint-offset table almost line for
  line) and hangs the same box/capsule/sphere placeholder meshes (yoke,
  side panels, sock trim, all of it) off `BoneAttachment3D` nodes instead
  of off the bones' former stand-in `Node3D`s. Visual output is
  deliberately close to identical — this pass is the rig plumbing, not a
  new art pass; a couple of mesh offsets shifted a few centimetres where
  the old single "Torso" joint became a Spine/Chest split, not worth
  hand-tuning further at placeholder fidelity.
- **`scripts/player/humanoid_animations.gd`** (`class_name
  HumanoidAnimations`) replaces `placeholder_animations.gd`/
  `PlaceholderAnimations` outright, same reasoning. The parametric gait
  math (`_gait_pose`, every per-action keyframe pose, the sign-convention
  comments, all of it) is **untouched** — only the track target changed,
  from `Animation.TYPE_ROTATION_3D`/`POSITION_3D` tracks on `NodePath`s
  like `"Hips/Torso"` to the same track types on `NodePath`s like
  `"Skeleton3D:Chest"`, Godot's own bone-track convention. The old
  `PATHS` dict (joint key → node path) became `BONES` (joint key → bone
  name); `_assemble()`'s two track-building loops are the only functions
  that actually changed shape.
- **`scripts/player/player_animation.gd`**: two lines. The
  `PlaceholderAnimations.build_library(PlaceholderRig.HIP_HEIGHT)` call
  became `HumanoidAnimations.build_library(HumanoidRig.HIP_HEIGHT)`,
  plus doc-comment updates. `rig_path`/`animation_player_path`/
  `animation_tree_path` exports, `drive()`, `play_action()`,
  `current_state()`, `blend_position()` — the whole public contract the
  brief said to extend, not redesign — are byte-for-byte unchanged.
  Nothing in `player_controller.gd` needed touching: it only ever calls
  through `PlayerAnimation`'s public methods, never reaches into the rig
  directly (confirmed by grep before assuming, not after finding a bug).

### Fully wired vs. stubbed

**Fully wired**: the whole pipeline — `HumanoidRig` builds the skeleton
and attaches meshes on `_ready()`, `PlayerAnimation._ready()` points
`AnimationPlayer.root_node`/`AnimationTree.root_node` at the `Rig` node
exactly as before, `HumanoidAnimations.build_library()` generates bone
tracks against that skeleton, the `AnimationNodeStateMachine`/
`BlendSpace2D` graph is unchanged and plays them the same way. Every call
site that reached into the old rig (`full_game.gd`, `menu_backdrop.gd`,
`character_backdrop.gd`, `coach_npc.tscn`) is updated to the new class
name and confirmed working by the headless passes below —
`character_backdrop.gd`'s `find_children("*", "MeshInstance3D", true,
false)` recursive mesh-layer reassignment still finds every mesh despite
them now sitting two levels deeper (`Rig/Skeleton3D/BoneAttachment3D/
Mesh` instead of `Rig/Joint/Mesh`), since it was already recursive.

**Stubbed / explicitly not attempted**: real skinning. `BoneAttachment3D`
gives rigid-body-per-bone motion (a mesh rides its bone's transform
wholesale, no per-vertex blend weights) — correct for primitive boxes/
capsules standing in for limbs, and it's what makes bone tracks the right
choice now rather than after a real mesh import, but it is not a smooth-
skinned character and won't become one until an actual skinned mesh
(Blender/Mixamo export with vertex weights) replaces these primitives.
**Rest-pose axis convention for retargeting** is also unverified: this
rig's bones inherit the same "-Y hangs down the limb" local convention
the old joint hierarchy already used, which is internally consistent and
matches this file's own `_gait_pose()` sign-convention comments, but
whether it's byte-for-byte what Godot's `BoneMap`/humanoid retargeter
expects for automatic axis correction hasn't been checked against a real
mocap import — that importer step (`BoneMap` UI, or manual axis fixup) is
still ahead of this rig, not proven clear by it. Root motion
(`AnimationTree.root_motion_track`) remains unwired, exactly as every
prior entry in this file has flagged — still blocked on contest mechanics
existing, unrelated to this pass.

### Verification

Same toolkit this project's memory already documents: `--headless
--editor --quit` to force a class-cache rescan after the two new
`class_name` scripts (`HumanoidRig`/`HumanoidAnimations` both showed up
in the rescan log, confirming registration), then the three standard
headless passes — `--quit-after 300` on the main scene, `kick_to_kick.tscn`
for 180 frames, `full_game.tscn` for 240 frames (AI-driven matches, so
this exercises the animation state machine's action states, not just
locomotion) — all exit 0, zero errors. The first `kick_to_kick.tscn` run
caught a real miss: `scenes/mechanics/coach_npc.tscn` had its own direct
`ext_resource` reference to the now-deleted `placeholder_rig.gd`, not
reachable by grepping `.gd` scripts alone — worth remembering that
`.tscn` `ext_resource` lines need their own sweep whenever a script gets
renamed or deleted, not just call sites in code. Fixed, re-ran, clean.
Also grepped the whole repo (`.gd` and `.tscn`) for `PlaceholderRig`/
`PlaceholderAnimations`/`placeholder_rig`/`placeholder_animations` after
all fixes; the only remaining hits are inside the two new files'
own doc comments, explaining what they replaced.

No human/pad verification possible in this environment (same limitation
every mechanics-agent entry above has flagged) — nothing here needed one,
since the deliverable is rig/animation plumbing verifiable by the
animation system actually building and running without error, not by
feel.

---

## Handover — character-screen standing-twitch fix + skeleton wireframe (Agent: UI/visual model)

Follow-up to the rig replacement above, from a direct playtest report:
the character screen's preview figure was visibly jittering/twitching
while standing still. Root-caused rather than papered over, plus a
wireframe overlay so the rig reads as a real skeleton at a glance, plus a
small mesh-completeness pass — all per this round's brief.

### Root cause: collision-response noise re-entering the animation blend

`PlayerController._update_locomotion()` reads `velocity.x`/`.z` at the
top of every physics frame to derive `_speed`/`_heading`, which
`locomotion_blend()` then reports to the `AnimationTree` as real motion.
`velocity` is a `CharacterBody3D` built-in that `move_and_slide()` is
free to modify as part of its own collision response — and this
project's floor-contact "bite" (`velocity.y = -0.5` every frame
`is_on_floor()` is true, `_physics_process`) means a standing player
re-triggers a resting collision every single frame, each one a chance for
slide resolution to leave a sub-millimetre horizontal residue in
`velocity`. That residue read straight back into `_speed`/`_heading` next
frame, which `locomotion_blend()` reported as genuine (if tiny) motion —
enough for the BlendSpace2D to blend in a hair of a moving clip (jog/
strafe) over pure idle, and since that clip's own internal clock keeps
advancing even at a low blend weight, the visible result is a continuous
low-amplitude twitch, not a one-off. This is a general-purpose bug, not a
character-screen-only one — it affects any player standing still
anywhere, just far more visible on the screen's static close framing
than on a moving broadcast camera.

**Fix** (`player_controller.gd`, `_update_locomotion()`): a
`Tuning.LOCOMOTION_VELOCITY_DEADZONE` (0.03 m/s) — horizontal velocity
below it is snapped to exactly `Vector3.ZERO` (and `velocity.x`/`.z`
zeroed with it) before `_speed`/`_heading` are derived from it. This
kills the feedback loop at its source: even if `move_and_slide()`
reintroduces a hair of noise next frame, it gets zeroed again before
anything downstream ever reads it, so it can't accumulate into a visible
sustained twitch. One `if`, no allocation, same cost for every player on
the field — the "simple maths, stays cheap at team scale" ask, and it
happens to fix the exact screen that surfaced it too.

**Scope note**: this touches `player_controller.gd`'s movement code,
which earlier passes in this doc were deliberately kept out of (see the
original rig-replacement brief's own constraint). Direct instruction this
round to fix the twitch is what justifies it — flagged here rather than
silently done, per this project's own pattern of calling out when a pass
crosses another agent's usual territory.

### Skeleton wireframe overlay

New **`scripts/player/skeleton_wireframe.gd`** (`SkeletonWireframe`,
`MeshInstance3D`): given a `Skeleton3D` via `track()`, rebuilds one
short camera-facing quad per bone (parent origin → bone origin) each
frame from `get_bone_global_pose()`, in `SoftBrutalist.ACCENT_PRIMARY`
green, unshaded and lightly emissive so it pops against the studio
backdrop regardless of the two-light rig underneath it. Quads, not
`PRIMITIVE_LINES`, because line width is unsupported/ignored on several
of Godot's rendering backends — a billboard quad renders identically
everywhere for a trivial vertex cost (~21 bones × 6 verts).

**Deliberately not attached to on-field players** — only wired into
`character_backdrop.gd`, which now calls `SkeletonWireframe.new()` +
`.track(rig.skeleton())` once, after the existing mesh-layer reassignment
loop. This project is scaling toward 16-a-side, and a per-frame rebuild
that's free for one close-up preview instance would not be free times
dozens of on-field bodies — the same "keep it cheap enough for a team"
constraint this round's brief stated explicitly. `HumanoidRig.skeleton()`
(added in the previous pass, unused until now) is what makes this a
one-line hookup rather than a new lookup path.

### Small mesh-completeness pass on `HumanoidRig`

Two things, both cheap (no new bones, no added draw calls beyond what's
listed):

1. **Corrected mesh offsets.** The previous pass's `Chest_Mesh`/`Yoke`/
   `SidePanel`/`Pelvis` offsets were approximate conversions from the old
   joint-relative numbers, flagged at the time as "not hand-tuned
   further." Recomputed properly this round: `Hips`/`Chest`/`Head` bones
   sit at the *exact* world position their equivalent placeholder-era
   joint used to (confirmed by re-deriving the offset chain, not just
   eyeballing), so meshes that used to be centred on those joints now
   sit at `Vector3.ZERO` on their bone instead of carrying over a stray
   non-zero offset; `Yoke`/`SidePanel` offsets recomputed as (old offset
   from the joint) minus (how far the new bone itself sits from where
   that joint used to be), landing at 0.165/-0.07 instead of the
   previous pass's 0.225/-0.01.
2. **Hands.** The forearm capsules previously ended in empty air past
   the elbow — no geometry marked where a hand would be, which read as
   an amputee at anything closer than broadcast distance (exactly what
   the close character-screen framing exposes). Added one small sphere
   per `LowerArm` bone attachment — one extra low-poly mesh per arm, same
   cost category as everything else already there.

### Verification

Same toolkit as every other entry: `--headless --editor --quit` rescan
(`SkeletonWireframe` confirmed registered), then all four headless scene
passes — main scene (300 frames), `kick_to_kick.tscn` (180),
`full_game.tscn` (240), and this round added `character_screen.tscn`
(180, the actual scene this bug was reported on) — all exit 0, zero
errors. One real typo caught by the first attempt at the rescan, not by
inspection: a stray `//` (C-style, not GDScript) survived an earlier
edit into a comment line in `humanoid_rig.gd` and failed the parse;
fixed, re-ran clean. Not verified visually — no GUI in this environment,
same limitation as every prior entry — so the deadzone fix is verified
as "compiles and runs error-free through the same physics paths every
other pass exercises," not as "confirmed the twitch is gone on screen."
That confirmation needs eyes on the actual character screen.

---

## Handover — six-item playtest punch list: jitter round 2, scrim, out-of-bounds, centre-bounce formation, camera, mouse kick, landing shadow (Agent: UI/visual model)

A batch of direct playtest reports, spanning well outside this agent's
usual UI/visual lane (camera tuning, match phase logic, input mapping).
Handled directly rather than deferred, since no other agent was
available in-session and each item was small/targeted enough to reason
about in isolation — flagged per item below since several of these cross
into `player_controller.gd`/mechanics/camera territory prior sessions
kept separate.

### 1. Character-screen jitter, actually fixed this time

The previous pass's deadzone fix was in the wrong place. It zeroed
`velocity.x`/`.z` at the *top* of `_update_locomotion()` — before
`move_and_slide()` runs later in `_physics_process()`. But
`locomotion_blend()` (the function that actually feeds the
AnimationTree) is called at the very *end* of `_physics_process()`,
*after* `move_and_slide()` — so it was reading whatever collision-
response noise `move_and_slide()` introduced that frame, completely
unprotected by the earlier snap. The deadzone was real and correctly
reasoned about, just guarding a read nothing downstream actually used.

Fixed by adding the same deadzone check directly inside
`locomotion_blend()` itself (`player_controller.gd`), immediately before
the dot-product framing — the one place whose output actually matters,
independent of whatever `_update_locomotion()`'s own bookkeeping is
doing. Left the original `_update_locomotion()` guard in place too (it's
not wrong, just insufficient alone — it still matters for `_speed`/
`_heading` derivation).

### 2. Character-screen scrim opacity

`ui_side_scrim.gdshader`'s `tint.a` cut 0.18 → 0.10 (already reduced
twice in earlier sessions, see the shader's own comment history) after a
direct "I want to see more of the field" report. At this screen's dim
studio lighting (Sun energy 0.14), even a low-alpha cream wash reads
brighter than the turf behind it — cutting alpha further mattered more
here than narrowing the wash's screen-width window did last time.

### 3. Boundary out-of-bounds: real stoppage, not a silent nudge

`full_game.gd._check_out_of_bounds()` already pulled a settled ball back
inside the oval — but silently, on a still-live ball, with zero signal
anything happened, which is indistinguishable from "not implemented" in
play. Rebuilt as a real (if simplified) stoppage using the exact
pause/callback shape every other dead-ball moment in this file already
uses (goals, quarter breaks) rather than a bespoke third mechanism:
`GameState.Phase.STOPPAGE` (declared since the earliest version of this
file, per its own doc comment "ball-up / boundary throw-in", never
previously entered by anything), `MatchState.clock_running = false`, a
`"OUT OF BOUNDS"` scoreboard flash, `Tuning.OUT_OF_BOUNDS_PAUSE_DURATION`
(2.0s) pause, then the same radial pull-back math as before delivering
the throw-in point once play resumes. Added a `_pause_timer > 0.0` guard
at the top of `_check_out_of_bounds()` so it can't re-trigger itself
every remaining frame of its own pause window (the ball doesn't actually
move until the callback fires).

**Not built**: a real umpire/possession model or a "deliberate out of
bounds" free kick — both need the same adjudication apparatus
holding-the-ball's ruling was already left waiting on (see the marking/
spoil/smother entry above); this pass only makes the stoppage itself
real, not who gets the ball out of it (still "contestable by whoever's
nearest," unchanged).

### 4. Centre-bounce formation: ruck + 3 on-ballers around the circle, not a 30m line

`_reposition_kickoff()` used the same wide `_kickoff_slot()` spread
(`KICKOFF_DEPTH` = 30m back) for *every* centre bounce, including every
restart after a goal — real AFL only allows one ruck plus three
on-ballers per team inside the centre square for a bounce, and this
project's `Tuning.TEAM_SIZE` (4) happens to equal exactly that
allowance, so "the whole team gathers at the circle" and "a correct
centre-bounce formation" are the same thing at this roster size. New
`_centre_bounce_slot()`: index 0 (ruck) plants 1.3m either side of the
exact centre point, facing the opposing ruck across it; indices 1-3 ring
the centre circle at 7m radius (outside `CENTRE_CIRCLE_OUTER`'s 5m,
inside `CENTRE_SQUARE_SIZE`'s 50m) across three angles, mirrored per team
by `attack_direction` so the two teams' arcs don't overlap. Used only by
`_reposition_kickoff()` (i.e. every centre bounce); `_kickoff_slot()`/
`KICKOFF_DEPTH` are untouched and still used by `_spawn_team()` for the
initial pre-match layout, which is a different moment or the design.

**Known gap**: `AIBrain.home_position` (each player's "return here when
idle" anchor) is set once at spawn to the wide kickoff slot and is *not*
updated by the new centre-bounce reposition — so a player not actively
contesting the ball will start drifting back toward their original
30m-back anchor once the bounce contest settles. The formation is
correct *at the moment of the bounce* (confirmed by inspection of the
new maths), which is what was asked for; whether the post-bounce drift
is worth fixing too is a follow-up, not attempted here.

### 5. Camera: ground-clip fix, ball-focus tuning, orthodox mode + settings

**Ground clip, root-caused.** `CAM_PITCH_MAX` (22°, upward look) combined
with `CAM_DISTANCE` (7.5m arm) and `CAM_FOCUS_HEIGHT` (1.35m, chest
height) put the camera's own Y below zero at the extreme of the existing
pitch range — `1.35 - 7.5·sin(22°) ≈ -1.45m` — genuinely underground, not
a rare edge case. Fixed with a height floor applied *after* whichever
mode's update runs (`BroadcastCamera._clamp_camera_height()`, `MIN_
CAMERA_HEIGHT` = 0.4m): pushes the whole rig up by however much the
lens dipped below the floor, preserving yaw/pitch/arm framing exactly as
computed, just translated clear of the ground. Deliberately a floor on
the one thing that actually matters (rendered lens height) rather than a
re-derived safe pitch bound — robust to the orthodox mode below or any
future distance/height tuning without re-deriving anything by hand.

**Ball-focus swivel/lingering, tuned.** `CAM_BALL_FOCUS_MAX` (how much of
the focus point's position can slide toward the ball) cut 0.55 → 0.35,
`CAM_BALL_FOCUS_RATE` (how fast that slide commits *and* releases,
symmetric) raised 3.0 → 4.5. The "swivel" after a kick was never the
camera's own yaw — that stays exactly where the player was looking — it
was the whole rig's *position* sliding toward the ball while orientation
held, which reads as a swing from a shifted vantage point. Less maximum
slide, and a faster release once the ball lands/is held, address both
"follows the ball a bit too long" and "swivels too much" as the same
root tuning, not two separate fixes.

**Orthodox camera mode, new.** `BroadcastCamera.Mode` (`CHASE`/
`ORTHODOX`), `set_mode()`. `ORTHODOX` reuses the existing yaw/pitch/
spring-arm rig wholesale — no new nodes — just drives it differently:
fixed pitch (`CAM_ORTHODOX_PITCH`, -62°), no player yaw/pitch input, arm
length reused as elevation (`CAM_ORTHODOX_HEIGHT`, 34m) at that steep
pitch, slower pan (`CAM_ORTHODOX_FOLLOW_RATE`, 2.2 vs `CAM_FOLLOW_RATE`'s
9.0) tracking the midpoint of the controlled player and the ball rather
than snapping to either — Prototype 1's own high strategic-view style,
per direct request, as an *option* alongside the chase cam rather than a
replacement. Full Game only, wired through `Settings.
full_game_camera_mode` (see below); `kick_to_kick.gd` reads nothing here
and keeps the chase cam unconditionally, per the brief's explicit "kick-
to-kick stays the same."

### 6. New: `Settings` autoload — the project's first real persisted settings

`settings_screen.gd` was, by its own header comment, "deliberately not a
functioning settings system" — every row was in-memory display only,
reset on reopen. Two new features this round both needed a real,
persisted, live-applied setting (camera mode; which mouse button aims
vs. kicks), so this pass built the first one: `scripts/autoload/
settings.gd` (`Settings`), `ConfigFile`-backed (`user://settings.cfg`),
two values (`full_game_camera_mode`, `mouse_kick_swapped`), each with a
property setter that applies the change immediately (camera mode emits
`camera_mode_changed`, full_game.gd listens live; mouse-kick rewrites the
InputMap on the spot — see below) rather than only taking effect on next
load. `SettingsScreen.Row` gained an optional `on_change` callback so its
existing cycle-left/right UI could drive real state without changing its
shape; the three original placeholder rows (volume/control scheme/screen
shake) are untouched and still inert — nothing reads those yet, so
wiring them would mean inventing values, not implementing a feature.
`_back()` now calls `Settings.save()` on the way out.

### 7. Mouse kick controls: right-click aim, left-click execute, swappable

A much earlier session explicitly avoided binding any mouse *button*
(only mouse motion) because there was no way to headless-verify Godot 4's
`InputEventMouseButton` resource text format by hand, and getting it
wrong silently would corrupt `project.godot`. This session has a working
Godot binary, so rather than hand-typing the format, a throwaway
headless `--script` (extends `SceneTree`, not committed) constructed the
two `InputEventMouseButton` resources via the real engine API
(`ProjectSettings.set_setting()` + `.save()`) and let Godot itself write
the correct serialization — diffed before/after to confirm it touched
only the two intended actions, nothing else in the file. Result: `kick_
stance` (aim) now also fires on right-click, `kick_execute` (kick) on
left-click, alongside the existing LT/RT gamepad and K/F keyboard
bindings — `human_brain.gd` needed zero changes, since it already just
reads `Input.is_action_pressed(&"kick_stance")`/`is_action_just_pressed
(&"kick_execute")`, and actions don't care which physical input fired
them.

**Swappable, via the InputMap, not a branch.** `Settings.mouse_kick_
swapped` (default false = right-click aim / left-click kick, matching
the request verbatim) is applied by `Settings._apply_mouse_kick_
binding()`, which erases whichever `InputEventMouseButton` currently
sits on each action and re-adds the correct one — so every existing
`is_action_pressed`-style read anywhere in the project keeps working
unchanged regardless of which physical button is currently bound to
which logical action, rather than threading a swap flag through
`HumanBrain`. Wired into `SettingsScreen` as a new "MOUSE KICK BUTTONS"
row.

**Not verified by feel.** Headless has no way to synthesize a real mouse
click for an end-to-end test; confirmed only that the InputMap entries
exist with the right button indices and that every affected scene still
boots and runs clean. Needs a hands-on pass.

### 8. Landing shadow marker

New `scripts/ball/landing_shadow.gd` (`LandingShadow`), a child of `Ball`
in `ball.tscn` — one per ball, not per player, so the cost is flat
regardless of team size. Visible whenever `Ball.is_airborne()` is true
(any kick, lob, or spoiled deflection back into the air — not gated to
the kicker or to a human's own charge, unlike `KickTrajectory`'s pre-kick
preview), showing a small flat "(v)" chevron at the estimated landing
point. Reuses `KickTrajectory._simulate()`'s exact gravity+drag step
rather than a second implementation of the same approximation, just run
from the ball's live position/velocity each frame instead of a
not-yet-launched one, and only keeps the final point (nothing here needs
the whole path). `top_level = true` so the marker's own orientation
never inherits the ball's spin.

### Verification

Every touched scene re-run headless after each change and again as a
full batch at the end — main scene (300 frames), `kick_to_kick.tscn`,
`full_game.tscn` (both 200+, and once each for an extra 1800-frame/30s
pass specifically to give centre-bounce/out-of-bounds/scoring code paths
time to actually fire, not just parse), `character_screen.tscn`,
`settings_screen.tscn`, `main_menu.tscn` — all exit 0, zero errors,
including one pass with `full_game_camera_mode` forced to `ORTHODOX` and
`mouse_kick_swapped` forced `true` via a throwaway `user://settings.cfg`
(deleted afterward, along with the scratch scripts used to write it and
the mouse-button InputMap entries) to actually exercise both new code
paths rather than only the defaults. `--headless --editor --quit`
class-cache rescan run after every new `class_name` script (`Settings`,
`LandingShadow`). No visual/feel verification was possible in this
environment for any of the eight items above — every fix here is
verified as "reasoned-through and runs error-free," not as "confirmed
correct on screen." All eight want a real playtest pass before being
trusted beyond that.

---

## Handover — movement backpedal/burst, ruck contests, kick-ins, holding-the-ball, camera rename, bump (Agent: mechanics/engine + UI)

A pass through the design brief's own priority order (movement first, then
ruck/kick-in/camera, then bump/holding-the-ball as room allowed) plus the
character-screen punch list. Same no-GUI limitation every prior entry has
flagged — verification here is real, scripted Jolt-physics runs (a new
`.tscn`+`.gd` scratch harness per system, positional-scene-argument form so
autoloads resolve, deleted after — same discipline the marking/spoil/
smother entry set), not eyeballing, plus the standard headless boots. Two
real test-harness bugs were caught and fixed *in the tests*, not the game
code, worth naming since both looked like game bugs at first: a scratch
player floating with no floor under it (`AIR_ACCELERATION` firing instead
of ground `ACCELERATION`, which happened to make a burst multiplier look
absent), and a scripted tackle fired before the match's own opening centre
bounce had finished (so `_on_holding_the_ball`'s `phase != PLAY` guard
correctly no-opped, which looked like the ruling not firing). Both are
recorded under their own sections below since the same trap is worth
recognising quickly next time, not just once here.

### 1. Movement (priority 1) — a real backpedal, not just a bigger read of the existing plant-and-pivot

`player_controller.gd`'s existing model (asymmetric ACCELERATION/BRAKING,
speed-coupled turn rate, `REVERSE_SPEED_SCALE = 0` driving a full-speed
reversal to a hard brake-and-swing) already gives the "plant-and-drive"
half of the brief unchanged — verified again by reading, not rebuilt. What
it had no way to express is the *other* named technique: "backpedal-to-
turn transitions for defenders reading the play" — a defender holding a
cushion, eyes on the ball, shuffling backward, not sprinting-then-
reversing. Structurally these are different moves at different speeds/
contexts, not one dial.

**New state**: `_backpedaling`/`_turn_burst_timer` on `PlayerController`,
gated in `_update_locomotion()` on how far the *new* wish direction is
from where the body is currently **facing** (not travelling) —
`Tuning.BACKPEDAL_ENTER_DOT`/`_EXIT_DOT` (hysteresis band so a diagonal
push near the threshold doesn't flicker), and only from a speed at/under
`JOG_SPEED + BACKPEDAL_ENTRY_SPEED_MARGIN` — a player already at sprint
who reverses still gets the existing plant-and-pivot, a faster, more
committed move for a different moment (chasing/leading) than this one
(holding a defensive cushion). While backpedaling, `_heading` tracks
`_wish_dir` directly every frame (a shuffle answers the stick immediately,
it isn't a turn-rate-limited sprint commitment) at a flat capped
`BACKPEDAL_SPEED`, and `_update_facing()` returns immediately without
touching `_facing_yaw` at all — the entire mechanic *is* that one early
return: eyes stay on the play, only the feet move.

**The burst** ("acceleration bursts when starting a lead or chase"): the
instant the wish direction swings back toward where the body is already
facing (`facing_alignment >= EXIT_DOT`), `_turn_burst_timer` arms for
`Tuning.TURN_BURST_DURATION` and accel gets `TURN_BURST_ACCEL_MULT` for
as long as it's counting down and still accelerating. **A real bug caught
by the scratch test, not by reading**: the first version left `_heading`
holding whatever the backpedal shuffle had last set it to (the *old*,
backward wish direction) instead of snapping it to the new one on exit —
so the very next frame's alignment check read a full reversal against the
stale heading and applied `REVERSE_SPEED_SCALE` braking instead of a
drive-off, i.e. exactly backwards from the intended effect. Fixed by
snapping `_heading = _wish_dir` in the same branch that arms the burst —
facing is already there (that's what triggered the exit), so there's
nothing left to turn through, only to drive off from. Verified
numerically after the fix: 14 frames into the burst window, speed had
climbed to 6.51 m/s from a 3.0 m/s backpedal-speed start, against a
computed "no burst" prediction of ~5.10 m/s at plain `ACCELERATION` over
the same window — comfortably distinguishing burst-applied from not.

**Speed-dependent gather** ("bringing the ball to hand must be affected by
the player's speed at the moment of contact"): the passive walk-over
`_try_gather()` used a flat `GATHER_RADIUS` regardless of how fast the
player was moving, unlike the deliberate `_update_ground_pickup()` (A
press on a loose ball) which already had a speed-scaled lunge. Gave the
passive path the same idea, gentler: `GatherZone`'s physics shape is now
sized to the *maximum* possible reach (`GATHER_RADIUS + GATHER_LUNGE_MAX`)
so it always has the real candidate available, and `_try_gather()` adds an
explicit distance test against `GATHER_RADIUS + speed * GATHER_LUNGE_PER_
SPEED` (capped at `GATHER_LUNGE_MAX`) on top — deliberately *not* just
resizing the live Area3D shape and reading `get_overlapping_bodies()` in
the same frame, since that list is a physics-step-stale cache, not a
live query (same reasoning `_update_ground_pickup()`'s own explicit
distance test already used, now shared). Verified: a player sprinting
through a stationary ball (starting 15m back, at full speed by arrival)
gathered it at ~1.20m from the carry point — meaningfully past the 0.85m
base radius, and consistent with the vertical carry-point-to-ball offset
plus the expected horizontal lunge budget at 8.4 m/s.

**Not changed**: `ACCELERATION`/`BRAKING`/`TURN_RATE_*` themselves — no
evidence either way without a human hand on a pad, and the brief's own
"real cost to changing direction" / "no instantaneous changes" asks were
already satisfied by the existing model on inspection. `REVERSE_SPEED_
SCALE` stays 0.0, untouched — the plant-and-pivot is a separately-verified,
already-tuned system this pass was careful not to disturb.

### 2. Ruck contests (priority 4) — one shared mechanic, three launch sites

New "Ruck contests" sections in `Tuning`/`PlayerController`/`full_game.gd`.
Per the brief: reuses `PlayerController._begin_aggressive_mark`'s exact
jump pattern (`_pending_jump` into the existing gravity integration — no
new arc code) for the leap, and the existing gravity/`is_on_floor()`
machinery handles the rest, same as every other airborne frame already
does.

**The shared piece** (`FullGame._begin_ruck_contest(spot, contestant_a,
contestant_b)`): nominates two players (`PlayerController.
set_ruck_contestant(true)`, self-expiring after `Tuning.RUCK_CONTEST_
WINDOW` via a new `_ruck_contest_timer`, same shape `_protected_timer`
already uses), bounces the ball straight up from `spot`, and sets phase/
clock live. Three call sites, differing *only* in where and who (exactly
the brief's "vary only in setup/launch conditions"):

- **Centre bounce**: `_bounce_off()` now calls it with `_home_players[0]`/
  `_away_players[0]` — the existing centre-bounce formation (already
  built, a prior pass) already puts index 0 at the ruck contest spot, so
  this needed no new positioning code, only the launch itself moved into
  the shared function.
- **Field ball-up**: the *neutral* half of holding-the-ball
  (RULES_REFERENCE.md §4 — tackled inside `PRIOR_OPPORTUNITY_GRACE` is
  nobody's fault). `PlayerController._get_tackled` already computed this
  condition and did nothing with it (the marking-pass entry above left it
  silent on purpose); it now emits a new `field_ball_up_called(tackler,
  tackled)` signal, and `FullGame._on_field_ball_up` freezes the ball at
  the tackle spot (same "reposition/settle before the pause, not after"
  shape `_prepare_centre_bounce` already uses, so nobody can wander over
  and gather a still-tumbling ball during the pause) and contests it
  between the tackler and tackled — already the two nearest players by
  construction, since a tackle only lands within `TACKLE_RADIUS`.
- **Boundary throw-in**: `_resume_after_out_of_bounds` (existing, from an
  earlier pass) previously just repositioned the ball with a bare
  `reset_at`. Now selects the nearest player per side to the throw-in
  point (`_nearest_player`, P1's own "nearest player per side" model per
  this project's memory of `contest_minigame.py`) and runs the same
  contest. This is real, working code, not just "compatible" — priority
  6's out-of-bounds foundation gets most of its remaining scope for free
  from this.

**RB = Hit-Out**: new `Tuning.Action.HIT_OUT` (appended, per the enum's
own append-only rule — `ACTION_DURATION`/`ACTION_CONTACT` copy `MARK_
AGGRESSIVE`'s row verbatim, since it's the identical jump, not a new
timing to invent), new `hit_out` input action (`J` / gamepad button 10 —
**RB**, confirmed against this project's own already-verified mapping:
button 11 matches `debug_hud.gd`'s documented "F3/D-pad Up", which
anchors the rest of the enum, and button 10 was only ever bound to
`team_menu`, which nothing reads during an actual match — grepped before
assuming, not after). `PlayerController._update_ruck_contest` gates RB to
nominated contestants only, in range (`RUCK_CONTEST_JUMP_RANGE`), on a
live airborne ball; `_begin_hit_out()`/`_resolve_hit_out()` mirror
aggressive mark's begin/resolve shape exactly, except the connect knocks
the ball away (`Ball.knock()`, the same external-hit primitive spoil/
smother already use) rather than gathering it — a palm, not a catch.
`RUCK_HIT_OUT_REACH` is deliberately `MARK_CATCH_RADIUS *
MARK_AGGRESSIVE_REACH_SCALE`, not a new number — same leap, same reach.
Verified end to end with a scripted two-player contest: nomination,
timed RB press, ball knocked off its straight-up path in the hitter's
facing direction, `hit_out_resolved(player, connected=true)` fired.

**AI never attempts a hit-out** (no `wants_hit_out()` override on
`AIBrain`) — matches this project's existing "deliberately simple, not a
tactics system" AI baseline for every other contest tier, not an
oversight.

### 3. Full Game ball-up formation (priority 3) — already done, now fed by the contest above

The two-ruck/three-on-baller centre-bounce formation was already built
(an earlier pass, see above) and needed no changes — `_bounce_off()` just
now launches through the shared contest instead of a bare `Ball.launch()`
call. Confirmed still correct via the extended `full_game.tscn` runs
below.

### 4. Protected kick-in (priority 5) — and a real pre-existing rules bug found while building it

Per the brief: reuses `_protected_timer`/`is_protected()` directly, no new
protection system. New `PlayerController.grant_protection(duration)` (sets
`_protected_timer`, already clears itself early on disposal via the
existing `_dispose()`/`drop_ball()` logic — "playing on forfeits
protection" already applies here with zero extra code) and
`give_possession(ball)` (a public name for the existing shared
`_complete_gather()` path, for placements that hand a player the ball
outright rather than having them reach for it).

**The bug**: `full_game.gd._on_scored` sent *every* score — goals and
behinds alike — to a centre bounce. Real AFL: a goal restarts with a
centre bounce, a behind restarts with a kick-in by the team that
conceded, no centre bounce at all. `_on_scored` now branches on
`is_goal`; `_prepare_kick_in(scoring_team)` finds the nearest defending
player to the goal square at the scoring end (`_nearest_player`, the same
helper the throw-in above uses), places them in it, gives them the ball,
and protects them for `MARK_HOLD_DURATION` (5s — the same number stand-
the-mark protection already uses, not a new invented threshold; an
earlier pass on this project's own notes flagged this exact reuse as the
plan). Verified: after a forced behind credited to HOME, the AWAY kicker
ended up at the +X goal square (`x≈76.5`, matching `goal_line_x(1) -
GOAL_SQUARE_DEPTH/2`), carrying, protected for ~4.95s.

**Not built**: retreat distance for the non-kicking team, a shot clock, or
anything about the kicker actually *choosing* to shoot for goal versus
play on — this project has no set-shot apparatus at all yet, and the
brief's ask was specifically the placement/possession/immunity triad, not
a full kick-in flow.

### 5. Holding-the-ball consequence (priority 8) — the free-kick half, reusing the same triad

The *ruling* already fired correctly (`holding_the_ball_called`, an
earlier pass); nothing consumed it. `FullGame._on_holding_the_ball` now
does, and deliberately reuses exactly what the kick-in above reuses
(`give_possession`/`grant_protection`) rather than a third bespoke
mechanism — the tackler gets the ball back at the tackle spot, protected
long enough to dispose of it. Per the brief: the existing ruling logic
(`PlayerController._get_tackled`) was **not** touched — no bug was
identified there, only a consumer was missing. Also deliberately minimal:
no separate set-shot apparatus, same scope boundary as the kick-in.
Verified with a scripted scenario (a player held the ball ~0.6s, past
`PRIOR_OPPORTUNITY_GRACE`, then was tackled): `holding_the_ball_called`
fired, play paused (`STOPPAGE`, clock stopped), and after the pause the
tackler was carrying, protected (~4.77s remaining), phase back to `PLAY`.

### 6. Camera: Full-Side / 3rd Person rename, and a real reposition, not a rotate

Renamed throughout (code and Settings UI, not just labels) per the brief:
`BroadcastCamera.Mode.ORTHODOX` → `FULL_SIDE`, `Settings.
FullGameCameraMode.BROADCAST/ORTHODOX` → `THIRD_PERSON/FULL_SIDE` (kept
the same ordinal order so an existing `user://settings.cfg` int still
resolves correctly), Settings screen row now reads "3RD PERSON"/
"FULL-SIDE". `BroadcastCamera.Mode.CHASE` (the 3rd Person rig) keeps its
internal name — a legitimate technical term, not a player-facing label
that needed to match.

**The reposition** (brief: "do not simply rotate the existing camera
downward... reposition to achieve the perspective of a camera situated
outside the field"): the old orthodox mode hovered its rig directly above
the play at a steep -62° pitch — reaching "elevated" honestly, but never
actually "outside the field," and reading as a blimp/drone shot, not a
broadcast one. `_update_full_side()` now puts the rig's own pivot at a
**fixed position outside the boundary** (`Tuning.CAM_FULL_SIDE_SIDE_
OFFSET` = 100m on Z, well past the fence at ~76.5m) and a fixed elevation
(`CAM_FULL_SIDE_HEIGHT` = 34m, direct on `global_position.y` now rather
than smuggled in through spring-arm length) — "outside the field" is
where the rig actually lives, not a side effect of enough arm-length/
pitch tuning. It pans along the field's length (X) to track which end
play is at, and the look-down pitch is *computed* each frame from the
real geometry (`atan2(height, horizontal distance)`), not a fixed guessed
angle — so it's never aimed above or below the actual ball as play moves,
satisfying "do not just rotate it" by computing the angle instead of
picking one. Verified: after settling, the rig sits at `z≈100` (outside
`FIELD_HALF_WIDTH`=67.5m), elevated ~34-36m, pitch settling around
-18° to -19° — genuinely side-on, not top-down.

**3rd Person** (ball-follow/swivel/ground-clip): all three were already
addressed by the immediately-prior session on this same uncommitted work
(`CAM_BALL_FOCUS_MAX`/`_RATE` tuned down/up, `_clamp_camera_height()`
added) in direct response to this same feedback. Re-read and left as-is —
no new evidence to justify re-tuning numbers that were just tuned against
the identical complaint, and the brief's own engineering constraints ask
for small, evidenced changes over speculative re-tuning.

**kick_to_kick unchanged**, confirmed by inspection — it never calls
`BroadcastCamera.set_mode()`, so it stays on `CHASE` regardless of the
Settings value, exactly as the brief requires.

### 7. Bump (priority 7) — a real flick primitive, and a real, documented control conflict resolved

**The flick primitive** (`InputManager.flick_vector()`/`_update_flick()`):
tracks the last time the right stick's *raw* magnitude (before MOVE/
LOOK_CURVE shaping — that curve exists for camera/kick feel, not for
deciding whether a swing counts) was below `Tuning.FLICK_NEUTRAL_
MAGNITUDE`, and fires once, edge-triggered, if the stick then reaches
`FLICK_MIN_MAGNITUDE` within `FLICK_WINDOW` seconds of that neutral
moment — a genuine sweep-shaped gesture, not a held-axis read pretending
to be one (nothing like this existed before; the brief was explicit that
it shouldn't be faked from `get_look_vector()`). Re-arms once the stick
returns to neutral. Works unmodified on keyboard: a digital arrow-key tap
is already an instant 0→1 jump, trivially satisfying "swept from neutral
to full within the window" with no separate keyboard path needed.

**A real control conflict, found and resolved, not guessed past**: the
brief specifies LB hold for bump stance. LB (gamepad button 9) was
already bound to `switch_player` — and unlike `team_menu` (which hit_out
above shares RB with safely, since nothing reads it mid-match),
`switch_player` **is** read live during a match
(`full_game.gd._unhandled_input`), so sharing LB unmodified would fire a
player switch the instant LB is pressed, before any flick could ever
register — not a hypothetical, a guaranteed break of a verified feature.
Relocated `switch_player`'s gamepad binding to D-pad Left (button 13,
confirmed completely unused anywhere in the input map before this — a
natural fit for "cycle to the next player" besides), keeping its keyboard
Tab binding untouched, and bound the new `bump_stance` action to LB
instead. This is a deliberate, reasoned rebind of a verified control
where a literal conflict was identified by direct inspection — not the
kind of speculative change the controller-diagnostic section warns
against (that warning is about not guessing at *why* an Xbox input isn't
registering; this is a *known, certain* two-actions-one-button collision
found by grepping every existing `button_index` before adding a new one,
same audit discipline the marking pass already established as this
project's own precedent for exactly this situation).

**The mechanic** (`PlayerController._update_bump`/`_try_bump`, out-of-
possession only): finds the nearest opposing ball carrier in
`BUMP_RANGE`, checks the flick's world-space direction (camera-relative,
same conversion `HumanBrain.wish_direction()` already uses, so "flick
right" means the same thing on screen a bump does as it does for
running) against the real bearing to them within `BUMP_CONE_DEG` — no
target lock, a physical swing that has to actually line up, matching
every other contest here's "physically doing the right thing resolves
it" stance. "Timing relative to the carrier's approach" (brief) is a real
dot product against the carrier's live velocity: closing on the bumper
lands clean (full knockback/stun), anything else still connects (they
were in range and cone) but glances (`BUMP_MISTIMED_SCALE`).

**Knockback needed a new mechanism, not just an impulse** — a real bug
class avoided by testing, not just reasoning: `_update_locomotion()`
overwrites `velocity.x`/`.z` from internal `_heading`/`_speed` state every
single frame, unconditionally, so a naive `velocity += impulse` on the
bumped player would have been silently steamrolled the very next physics
tick with zero visible effect. New `_knockback` vector: while nonzero,
`_update_locomotion()` returns immediately after driving `_speed`/
`_heading` straight from it (decaying via `BRAKING` each frame) instead of
reading any brain input at all — the hit is what's moving the body, not
the stick. Verified directly: a scripted `receive_bump(Vector3(6,0,0),
0.4, ...)` moved a stationary player +0.29m in three physics frames with
velocity decaying exactly as expected (6.0 → 5.53 m/s over three frames
at `BRAKING`).

**Deliberately not built, per the brief's own explicit instruction**: any
dangerous/high-contact free-kick consequence. `RULES_REFERENCE.md` has no
distance/angle/force/timing threshold for "high contact" to judge
against — `bump_landed(bumper, carrier, clean)` fires on every connect so
a future pass with real numbers has an event to hook, but nothing here
judges legality. Flagged in the signal's own doc comment, not silently
dropped.

### 8. Character screen (priority 9)

**Background wash**: `ui_side_scrim.gdshader`'s `tint.a` cut a fourth time,
0.10 → 0.06, per the brief's explicit "do not leave the current opacity
unchanged."

**Wireframe visibility + body transparency**: the skeleton wireframe
(`SkeletonWireframe`, an earlier pass) already tracked real bone poses
every frame — "bone-following" was already true, it just had nothing to
show *through*: the placeholder body meshes in front of it are fully
opaque, so it only ever peeked past the silhouette edge. `CharacterBackdrop`
now sets every body mesh's material to `TRANSPARENCY_ALPHA` at
`BODY_ALPHA = 0.55` for this preview only — safe to mutate directly
because `HumanoidRig._materials` is a plain per-instance dict, not shared/
static (checked before touching it, not after), so this can't leak into
any on-field player's own materials. `SkeletonWireframe.LINE_WIDTH`
0.012→0.022 and its emission multiplier 1.4→1.8 for the "more visible"
half of the same ask.

**Jitter — investigated thoroughly, no further code-level cause found**.
Traced both mechanisms this project's own history has previously
implicated, from scratch, with numbers:
1. **Locomotion-blend noise** (the `move_and_slide()` collision-response
   residue leaking into the animation blend, "fixed" twice already by
   earlier passes). Verified directly: a scripted player with zero brain
   input, settled on a real floor, sampled for 270 physics frames —
   `locomotion_blend()` and horizontal velocity were bit-exact
   `Vector2.ZERO`/`Vector3.ZERO` on every single frame. This path is
   provably silent now.
2. **The idle animation clip's own keyframe data**
   (`HumanoidAnimations.GAITS["idle"]`) — a comment already on disk
   records two earlier rounds of shrinking idle's sway parameters toward
   zero and *still* reading as a twitch, landing on exact zero as a last
   resort ("revisit... if idle sway is wanted again later"). Re-derived
   `_gait_pose()` by hand against the current all-zero idle dict: every
   term in that function is linear in `stride`/`knee_lift`/`bob`/`lean`/
   `twist`/`abduct`/`yaw_bias`/`roll`, all of which are 0 or defaulted to
   0 for idle — so all 14 generated keyframes are mathematically
   *identical* (the same `Quaternion.from_euler(Vector3.ZERO)` /
   `Vector3(0, hip_height, 0)` called with the same input 14 times).
   Cubic interpolation between bit-identical control points has zero
   tangent and zero curvature to overshoot around — this clip cannot
   itself introduce per-frame variation, full stop, regardless of the
   interpolation-overshoot mechanism the on-disk comment still names as
   the suspected (but not re-confirmed) cause.

Attempted a third, independent check — pixel-diffing rendered frames of
the actual `character_screen.tscn`, the same technique the original
visual-pass session used — but this headless build's rendering driver is
the dummy/null one (`texture_2d_get` on a null texture, confirmed by
hitting the error directly), so `get_viewport().get_texture()` never
produces a real image here; that verification path isn't available in
this environment. **Net**: both previously-suspected mechanisms are now
provably eliminated at the code level. If jitter is still visible on a
real screen, the cause is something neither this nor prior sessions have
identified yet, and needs eyes on an actual GUI session to localise —
recorded here so the next session doesn't have to re-derive either proof
from scratch.

### 9. Out-of-bounds (priority 6) — mostly inherited from §2 above; one gap identified, not guessed past

Detection/stoppage/restart were already real (an earlier pass); the
restart now goes through the shared ruck contest (§2). **Not built**:
"out on the full" (RULES_REFERENCE.md §4 — a kick crossing the boundary
*in the air* is a free kick to the other side, distinct from a neutral
ball-up) isn't distinguished from a rolled-out ball at all — both hit the
same "settled outside the oval → neutral throw-in contest" path today.
Building the distinction needs checking the ball's flight *as it crosses*
the boundary while still airborne (a per-frame bisection against the
flight segment, per this project's own memory of Prototype 1's approach),
and awarding it needs the same missing free-kick/set-shot apparatus the
kick-in and holding-the-ball sections above already stop short of.
Identified and left, not guessed at — RULES_REFERENCE.md already lists
this as a known, not-yet-reached rule.

### 10. Controller diagnostics (priority 10)

`DebugHud`'s F3 diagnostic (`last gamepad button/axis`) is untouched and
still the intended next step for the reported Xbox marking/defensive-
action issue — nobody in this session had a controller attached to
generate new raw-index evidence, so no bindings were changed on the
strength of a guess. The one binding this session *did* change
(`switch_player`'s gamepad button, §7) was a certain, grepped-and-
confirmed logical conflict with a brand-new action, not a response to the
Xbox-registration report, and is called out on its own above rather than
folded in quietly.

### Verification

Every touched scene re-run headless after each system landed and again as
a full batch at the end: `--headless --editor --quit` class-cache rescan
(no new `class_name` scripts this pass, so nothing new to register, but
run anyway per this project's own standing discipline), then `main_menu`/
`kick_to_kick`/`full_game`/`character_screen`/`settings_screen`, all exit
0, zero errors — plus one extended `full_game.tscn` run at 9000 frames
(2.5 simulated minutes, well past `QUARTER_LENGTH`) specifically to give
repeated centre bounces, kick-ins, tackles and quarter transitions time to
actually fire against each other under real AI play, not just parse.
Beyond the headless boots, **seven** separate scripted-physics scratch
harnesses (positional-scene-argument form, real autoloads, deleted after
— none committed) numerically verified: backpedal entry/cap/facing-freeze,
the turn-burst acceleration spike (and the stale-heading bug it caught),
speed-scaled gather reach, a full ruck contest's nomination→jump→hit-out→
knock chain, the protected kick-in's placement/possession/protection,
Full-Side's settled position/elevation/pitch, the flick primitive plus
bump connect/timing/knockback-displacement, and the holding-the-ball
ruling→pause→free-kick chain end to end. Two of those runs hit real
test-harness bugs before landing (see this entry's own opening paragraph)
— both diagnosed and fixed in the test, confirmed not to be game bugs by
re-deriving the actual cause rather than assuming.

**No human/pad verification was possible in this environment** — same
limitation every mechanics-agent entry in this file has flagged from the
start. Everything above is verified as "reasoned through, numerically
checked against real physics, and runs error-free," not as "confirmed to
feel right." Movement in particular — the brief's own highest priority —
most needs a real hands-on pass before any of `BACKPEDAL_SPEED`/
`BACKPEDAL_ACCELERATION`/`TURN_BURST_DURATION`/`TURN_BURST_ACCEL_MULT`
(all first-guess numbers, same as every other movement constant's own
history in this file) should be trusted beyond "does what it says".

### Known limitations / unresolved

- **Dangerous-contact free-kick consequences for Bump**: not built,
  per explicit instruction — `RULES_REFERENCE.md` has no numeric
  threshold. `bump_landed` is the hook for whenever one exists.
- **"Out on the full"** vs. a rolled-out ball: not distinguished. See §9.
- **AI**: no hit-out, no bump, no spoil/smother attempts — matches this
  project's existing, deliberate "not a tactics system" AI baseline for
  every other contest tier, not new scope creep or an oversight.
- **Stand-the-mark** (the mark-taker's opponent frozen in place) is still
  not modelled — `is_protected()`/`grant_protection()` stop the *tackle*,
  nothing stops the opponent repositioning. Same gap an earlier pass
  already flagged, now shared by three protection use sites instead of
  one.
- **Character-screen jitter**: see §8 — two previously-suspected causes
  eliminated at the code level; if still visible, needs a live GUI
  session to actually localise, which no session in this project's
  history has had.
- **Free-kick/set-shot apparatus**: both the kick-in and holding-the-ball
  consequences stop at "possession + protection at the right spot" —
  retreat distance, a shot clock, and choosing to shoot vs. play on are
  all still unbuilt, same scope boundary an earlier pass's own notes
  already anticipated.

### Files changed

`scripts/tuning.gd` (backpedal/turn-burst, gather lunge, ruck contest,
bump, flick — all new constants; Full-Side's `CAM_ORTHODOX_*` renamed/
redesigned), `scripts/player/player_controller.gd` (backpedal/burst
locomotion, speed-scaled gather, ruck contest section, bump section,
kick-in/free-kick support methods, two new signals), `scripts/autoload/
input_manager.gd` (flick primitive), `scripts/mechanics/player_brain.gd`/
`human_brain.gd` (`wants_hit_out`/`wants_bump_stance`), `scripts/modes/
full_game.gd` (shared ruck-contest launch, kick-in, holding-the-ball
consumer, camera-mode rename), `scripts/camera/broadcast_camera.gd`
(Full-Side rename + reposition), `scripts/autoload/settings.gd` /
`scripts/ui/settings_screen.gd` (camera-mode rename), `scripts/ui/
debug_hud.gd` (backpedal/ruck diagnostic lines), `scripts/ui/
character_backdrop.gd` (body transparency), `scripts/player/
skeleton_wireframe.gd` (visibility), `assets/shaders/ui_side_scrim.
gdshader` (opacity), `project.godot` (`[input]` only: new `hit_out`/
`bump_stance` actions, `switch_player`'s gamepad button relocated — see
§7). Not touched: `scripts/ball/ball.gd`/`landing_shadow.gd` (both
already correct for this pass's needs — `Ball.knock()` already existed
and was reused as-is for the hit-out palm), `scripts/field/field.gd`,
`humanoid_rig.gd`/`humanoid_animations.gd` (read, not edited — see §8's
jitter investigation), anything coach/challenge-related.

---

## Handover — camera-switch pan, Madden-style mark prompt, tackle-lunge assist, kick-to-kick rival, Team Edit formation picker (Agent: mechanics/engine + UI)

A broad polish-pass brief covering code quality, accessibility/gameplay
clarity, and several named feature asks, worked in the order the brief's
own closing lines emphasised (camera-switch feel and general gameplay
first) plus every concretely-specified item (Madden-style contest icons,
a ball-steal assist, kick-to-kick and Team Edit expansion). Not attempted
this pass, and called out honestly rather than silently dropped: a full
line-by-line redundant-code/accessibility sweep of the whole codebase,
and character-interaction polish beyond what's listed below — this
entry's own scope is already large; see "Known limitations" for the rest
of the original brief still sitting on the table.

### 1. Camera-switch pan, no longer an instant cut

`BroadcastCamera.recenter()` hard-sets position, yaw and pitch in one
frame — correct for "camera, get back on me" (exiting dialogue, entering
a mode) but read as a teleport on a mid-match player switch (`switch_
player`), which the brief named directly. New `switch_target(new_target)`
(`broadcast_camera.gd`) leaves `_update_focus()`'s own per-frame lerp
(`CAM_FOLLOW_RATE`) to carry `global_position` across on its own — nothing
here calls `recenter()`, so nothing snaps it — and adds a short
`_switch_timer` window (`CAM_SWITCH_PAN_DURATION` = 0.6s) where `_update_
rotation()` eases yaw/pitch toward the new target's facing at a dedicated,
deliberately cinematic `CAM_SWITCH_YAW_RATE` (5.0, slower than `CAM_
ROTATE_RATE`'s 12.0) instead of reading stick/mouse input, then hands
control back. `FullGame._switch_human_player()` now calls `switch_target()`
instead of `target = next; recenter()`.

### 2. Madden-style mark-tier prompt — (A)/(X)/(Y) over the receiver's head

The three-tier mark system (Safe/Running/Aggressive) already maps exactly
onto Xbox A/X/Y — confirmed against `project.godot`'s own joypad bindings
(`mark_safe`→button 0/A, `mark_running`→button 2/X, `mark_aggressive`→
button 3/Y) before building anything, not assumed. New `PlayerController.
live_mark_prompts(ball)` reuses the exact reach tests `_update_aerial_
contest` itself resolves against (`_ball_in_catch_reach` for Safe/Running,
`MARK_CONTEST_RANGE` for Aggressive) rather than a UI-only approximation
that could drift out of sync. New `scripts/ui/mark_prompt.gd` (`MarkPrompt`,
same instantiate-and-assign-`player`/`ball` pattern as `KickCrosshair`/
`DebugHud`) projects the live player's head position via `Camera3D.
unproject_position()`/`is_position_behind()` and draws stacked colour
badges — green/blue/yellow, `SoftBrutalist.BUTTON_A/X/Y`, the same
convention anyone who's held an Xbox pad already has memorised rather than
a new one invented for this screen. Wired into both `full_game.gd` (kept
in sync on every `_switch_human_player()`) and `kick_to_kick.gd`.

### 3. Tackle lunge — the actual fix for "hard to get the ball off the AI"

Diagnosed before writing any code: tackling itself was never chance-based
(a tackle in `TACKLE_RADIUS` always spills the ball), and the AI's own
`AI_PRESSURE_RADIUS` (4.0m) forces a disposal well outside `TACKLE_RADIUS`
(1.4m) — a defender closing at ordinary run speed essentially never
reaches tackle range before the AI has already kicked or handballed away.
The fix is a genuine speed burst, not a radius or chance change (same
"physical, not a dice roll" stance every other contest in this file
already takes): tapping tackle (the rising edge, not `wants_tackle()`'s
held state `_try_tackle()` already reads directly — holding it at standing
range still works exactly as before) while an opposing carrier is between
`TACKLE_RADIUS` and `TACKLE_LUNGE_RANGE` (2.4m) and roughly in front
(`TACKLE_LUNGE_MIN_DOT`) commits to a `TACKLE_LUNGE_DURATION` (0.35s) dash
at `TACKLE_LUNGE_SPEED` (7.5 m/s, faster than sprint) toward them —
`PlayerController._update_tackle_lunge()`, overriding `_update_locomotion`
the same way `_knockback` already does for a bump's hit. A miss just
leaves the lunger having sprinted past/short — no separate whiff penalty
invented on top of `TACKLE_LUNGE_COOLDOWN`'s (1.1s) real commitment cost.
Reuses the existing `_nearest_opposing_carrier()` bump already added.

### 4. Kick-to-kick rival — a live opponent, not just scripted deliveries

The brief asked for kick-to-kick to actually be usable for testing — it
previously had exactly one player and nobody to tackle, bump, or contest a
mark against; every contest mechanic in the game was literally untestable
there. `kick_to_kick.gd._spawn_rival()` adds a second `PlayerController`
(`Team.AWAY`, `KICK_TO_KICK_RIVAL_OFFSET` clear of both coach zones) with
a stock `AIBrain` — reused wholesale rather than a bespoke "practice
partner" behaviour, since chase/mark/dispose/press-and-tackle already *is*
a sparring partner, and a chase-and-return loop against one real opponent
is also just what "kick to kick" already means. Frozen outright
(`set_physics_process(false)`) for the duration of any coach dialogue/
challenge so a drill stays a clean 1-on-0 loop, resuming the instant
`_coach_state` clears.

Caught by the verification harness, not by inspection: the harness's own
defender and carrier both defaulted to `Team.HOME` (`player.tscn`'s own
export default), which silently made `_nearest_opposing_carrier()` see no
target at all and reported zero tackles — not a lunge bug, a test-setup
bug, but exactly the kind of team-filtering mistake `_spawn_rival()` had
to get right for real, so it was worth fixing in the harness and
re-confirming rather than waving off.

### 5. Team Edit expansion — a matchday formation picker, wired into a real match

`TeamListScreen` and `FormationWhiteboard` both carried their own explicit
"editing is out of scope for this pass" notes across several prior
sessions — not a hard wall, a breadcrumb: `TeamFormation.world_positions()`
was already built and already commented "used by a testing mode spawning
fewer than 18 a side," describing `full_game.gd`'s own `TEAM_SIZE` (4)
exactly, and simply never connected. This pass connects it, scoped down
from "edit any of 18 named roles freely" (which would need a real
roster/persistence system this project has repeatedly and deliberately
not built yet — see `character_screen.gd`'s own header) to picking between
three curated 4-a-side presets drawn from the real 18-slot AFL data:
`Settings.FORMATION_PRESETS` (BALANCED/ATTACKING/DEFENSIVE, persisted to
`user://settings.cfg` same as `full_game_camera_mode`/`mouse_kick_swapped`
already are). `TeamListScreen`'s old static "18 A-SIDE" info card is now
a real ui_left/ui_right picker (same cycle convention `settings_screen.
gd`'s `Row` rows use) that also rings the chosen four dots on the
whiteboard (`FormationWhiteboard.selected_indices`, additive — empty by
default, so nothing else that draws the board changes). `FullGame.
_kickoff_slot()` now reads `Settings.home_formation_slots()` for HOME
directly, so a choice made on the Team List screen changes where the
human side actually lines up in the next match — AWAY keeps the old even
spread, since it's an opponent, not the side being edited.

### 6. Code-quality pass

- `BALL_LOST_BELOW` (the ball-out-of-bounds-below-the-map safety net) was
  three independent copies of the same number (`main.gd`, `kick_to_kick.
  gd`, `full_game.gd`, the last of which even said so in its own comment).
  Single-sourced to `Tuning.BALL_LOST_BELOW`.
- `for player in _home_players + _away_players: player.drop_ball()` was
  the same two lines copy-pasted at five call sites in `full_game.gd`.
  Collapsed to `_drop_all_balls()`.

### Verification

Every touched scene rescanned (`--headless --editor --quit`) then run
headless: `main_menu`/`kick_to_kick`/`full_game`/`character_screen`/
`settings_screen`/`team_list_screen`, all exit 0, zero errors.

Method note for whoever runs headless verification next: `--quit-after N`
alone, without `--fixed-fps 60`, does **not** reliably mean N physics
frames in this environment — an unthrottled headless main loop can iterate
far faster than physics catches up, so a scripted scratch harness that
needs its state machine to actually reach a later phase produced zero
output at `--quit-after 400` until `--fixed-fps 60` was added, which
locks idle/physics stepping together and made the same 400 iterations
behave as the intended ~6.7 simulated seconds. Doesn't affect a plain
boot/parse smoke test (those don't need to *reach* anything), only a
harness that scripts a sequence of state over time — this project's own
memory of the Godot binary/CLI incantations has been updated with this.

Beyond the headless boots, a scripted-physics scratch harness (positional-
scene-argument form, real autoloads, deleted after — not committed)
numerically verified all three new mechanics end to end in one run: the
tackle lunge does *not* fire beyond `TACKLE_LUNGE_RANGE` (carrier at 3.0m
keeps the ball) and *does* close a 2.0m gap and complete the tackle within
its commitment window; the camera-switch pan is provably not an instant
snap (position hasn't already reached the new target one frame after
`switch_target()`) and does converge on the new target's position and
facing within tolerance; and `live_mark_prompts()` returns the right tier
set at close range (all three live), mid range (only Aggressive, per
`MARK_CONTEST_RANGE`), and beyond it (none).

**No human/pad verification was possible in this environment** — the same
limitation every mechanics-agent entry in this file has flagged from the
start. The tackle-lunge's numbers in particular (`TACKLE_LUNGE_SPEED`/
`RANGE`/`DURATION`/`COOLDOWN`) are first-guess, same as every other new
movement constant's own history in this file — numerically verified to do
what they say, not confirmed to feel right at the stick.

### Known limitations / unresolved

- **Kick-to-kick rival is the stock match AI**, not a purpose-built
  practice partner — it will chase, mark, tackle and dispose exactly like
  a Full Game defender/attacker, including kicking "toward goal" in a mode
  with no goals. Reads fine as a sparring partner in practice, but it is
  literally `AIBrain` with no kick-to-kick-specific tuning.
- **Team Edit is still three curated presets, not free assignment** —
  picking which named role goes where, or fielding named/persisted
  players, remains the scope boundary `character_screen.gd`'s own header
  already documents (no multi-profile persistence exists yet).
- **The rest of the original brief is untouched this pass**: a systematic
  redundant-code/simplification sweep beyond the two items in §6, a
  dedicated accessibility pass (colour/contrast, remapping, readability),
  and character-interaction polish (coach dialogue, the placeholder prompt
  label) were all named in the brief and are not addressed here — this
  entry covers camera/gameplay-feel and the concretely-specified feature
  asks only.
- **Dangerous-contact free-kick consequences for Bump**, **"out on the
  full"**, **stand-the-mark**, and the **free-kick/set-shot apparatus**:
  unchanged from the previous entry, still open for the same reasons
  already documented there.

### Files changed

`scripts/tuning.gd` (camera-switch, tackle-lunge, mark-prompt, kick-to-
kick-rival constants; `BALL_LOST_BELOW`), `scripts/camera/broadcast_
camera.gd` (`switch_target`/`_ease_toward_switch_target`), `scripts/
player/player_controller.gd` (`live_mark_prompts`, tackle-lunge state +
`_update_tackle_lunge`, locomotion override), `scripts/ui/mark_prompt.gd`
(new), `scripts/ui/soft_brutalist.gd` (`BUTTON_A/X/Y`), `scripts/modes/
full_game.gd` (`switch_target` call, `_drop_all_balls`, `_kickoff_slot`
formation lookup, `BALL_LOST_BELOW` dedup), `scripts/modes/kick_to_kick.gd`
(`_spawn_rival`, rival freeze/drop wiring, `BALL_LOST_BELOW` dedup),
`scripts/main.gd` (`BALL_LOST_BELOW` dedup), `scripts/autoload/settings.gd`
(`FORMATION_PRESETS`/`home_formation_index`, persistence), `scripts/ui/
team_list_screen.gd` (formation picker, replaces the static info card),
`scripts/ui/formation_whiteboard.gd` (`selected_indices` highlight). Not
touched: `scripts/ai/team_formation.gd` (already had exactly the API this
needed — `world_position()` — nothing to add), roster/persistence, coach/
dialogue UI, anything animation- or rig-related.

---

## Handover — Team Edit tactics (ball movement + defensive pressure), mark prompt single-tier fix (Agent: mechanics/engine + UI)

Direct follow-up to the entry above, on two specific pieces of feedback:
Team Edit should change actual match behaviour, not just where the team
lines up at kickoff; and the mark prompt was showing every tier that
would technically connect instead of the one actually relevant right now.

### 1. Team Edit: two new tactics settings that genuinely change the AI

Matchday Formation (previous entry) only ever changed *where* players
start. This adds two settings that change *how* HOME's AI actually
plays, both read once per spawn/hand-back the same way formation already
is — no live mid-match re-tuning, since Team List is only reachable from
the main menu.

- **Ball Movement** (`Settings.BallMovementPreference`: CORRIDOR/MUTUAL/
  BOUNDARY) — `AIBrain._lateral_target_z(pos)` pulls a lateral world-Z
  target toward whichever boundary `pos` is already nearer to, scaled by
  a new `lateral_bias` field (0.05/0.40/0.85 per preference, `Settings.
  BALL_MOVEMENT_BIAS`). Consumed by both `_think_carrying` (a carrier's
  disposal aim — `goal_point.z` used to be hardcoded 0) and
  `_think_support` (an off-ball teammate's run target, half-weighted so
  it colours rather than overrides the existing home/ball anchor). The
  kick-range/pressure distance check in `_think_carrying` deliberately
  still measures straight-line distance to the goal *line*, not to the
  now-off-centre aim point — using the biased point there too would have
  made a strong boundary bias misreport "too far to shoot" for a carrier
  who is actually well within range straight down the middle.
- **Defensive Pressure** (`Settings.DefensivePressure`: LOOSE/BALANCED/
  TIGHT) — a new `press_intensity` field (0.65/1.0/1.3, `Settings.
  DEFENSIVE_PRESSURE_INTENSITY`) scales both the chase gait and the
  tackle-commit distance in `_think_defend` together, not as two
  separately-invented numbers: TIGHT closes at full gait and commits to
  an actual tackle attempt from further out; LOOSE closes more slowly
  *and* holds off the commit until much closer; BALANCED (1.0) is this
  file's original, un-tuned behaviour.

Both settings are HOME-only (AWAY keeps `AIBrain`'s bare defaults) and
apply the moment a `AIBrain` is created — `FullGame._configure_ai_brain()`
is now the one place that happens, used by both the initial kickoff spawn
and `_switch_human_player()`'s hand-back brain, so the two call sites
can't drift about which settings a HOME player's AI actually gets the
moment nobody's driving them (hand-back previously built its `AIBrain`
inline with no tactics applied at all).

**Team List screen restructured** to carry three real settings instead
of one: reuses `SettingsScreen.Row` directly (title/options/index/cycle,
the exact same shape a second implementation would have just copied) for
all three rows, with the same up/down-select, left/right-cycle input
convention `settings_screen.gd` already established — not a new
convention invented for this screen. Three separate `_card()` shells (each
paying the full `CARD_PAD` border/shadow overhead) did not fit this
column's existing height budget, so all three rows now live in one
lighter-weight card instead. `home_formation_name()`, added last entry,
is gone again — the `Row` pattern already owns display strings via its
own `options` array, so a second lookup for the same string was dead
code the moment this screen adopted `Row`; same reasoning removed the
unused `Settings.formation_changed` signal (declared last entry, never
connected to anything).

### 2. Mark prompt: exactly one badge, not a stack of every live tier

`live_mark_prompts()` (plural) tested each tier independently and could
easily return all three at once — Safe's reach always covers Running's
narrower one, and Aggressive's `MARK_CONTEST_RANGE` is wider again, so
nearly every live moment had all three "live" simultaneously, which the
UI then drew as a stack. Replaced with singular `live_mark_prompt()`,
picking exactly one by the same speed-scale reasoning the tiers
themselves are already built on (Tuning's own "Safe plants you properly;
Running barely interrupts your stride" comment): Running only while
actually moving faster than `JOG_SPEED`; Safe the instant you're not;
Aggressive only while the ball hasn't reached normal catching reach yet
(once it has, a leap stops being the natural read even though it would
still technically connect). `MarkPrompt` draws that one badge at the
player's head position — no more stacking offset, no more looping over an
array.

### Verification

Rescanned (`--headless --editor --quit`) then all five touched/adjacent
scenes run headless (`--fixed-fps 60`, see the previous entry's own note
on why that flag matters for anything beyond a bare boot check):
`team_list_screen`/`full_game`/`main_menu`/`settings_screen`/
`kick_to_kick`, all exit 0, zero errors.

A second scratch harness (same positional-scene-argument, real-autoloads
shape as the previous entry's, deleted after) verified the actual
behaviour change, not just that it compiles: `lateral_bias` 0.0 vs 0.9
produced clearly opposite-signed lateral aim directions from the same
starting position; `press_intensity` LOOSE/BALANCED/TIGHT at a fixed
1.8m defender-to-holder distance produced the expected gait (0.65/1.0/
1.0) *and* the expected tackle-commit decision (false/false/true) —
distance chosen specifically to sit between BALANCED's and TIGHT's commit
thresholds so only TIGHT would fire; and `live_mark_prompt()` returned
exactly the expected single tier in four cases (stationary+close → Safe,
moving+close after a real ~1.5s speed ramp → Running, mid-range →
Aggressive, beyond `MARK_CONTEST_RANGE` → None). All passed on the first
run — no bugs caught this time, unlike the previous entry's team-
assignment miss.

**No human/pad verification was possible in this environment**, same
standing limitation as every entry in this file. The three new intensity/
bias numbers (`BALL_MOVEMENT_BIAS`, `DEFENSIVE_PRESSURE_INTENSITY`) are
first-guess, same as every other new tuning number's own history here —
numerically confirmed to move the AI's behaviour in the intended
direction, not confirmed to feel like three genuinely distinct tactical
identities at the stick. The Team List screen's new three-row card height
(`TACTICS_CARD_HEIGHT`) is a hand-computed budget against the same left-
column space the whiteboard already shares — not visually confirmed; see
the screen's own header comment if it turns out to overflow in an actual
editor session.

### Known limitations / unresolved

- **Ball Movement/Defensive Pressure only affect HOME's off-ball/defending
  AI** — a human-controlled player's own aim and tackle timing are
  entirely player-input, same as Matchday Formation only ever affected
  HOME's spawn positions. Working as designed, not a gap, but worth
  stating plainly since "Team Edit" now covers three settings with three
  different reach.
- **Still no free assignment** of which of the 18 named roles plays where,
  or independent tuning of formation vs. tactics per named player — same
  scope boundary the previous entry already documented, unchanged.
- Everything the previous entry's own "Known limitations" section listed
  as still open (redundant-code sweep beyond what's been touched directly,
  a dedicated accessibility pass, coach-dialogue polish, the rest of the
  original brief) remains open — this entry only covers the two items it
  was asked for.

### Files changed

`scripts/autoload/settings.gd` (`BallMovementPreference`/
`DefensivePressure` enums + presets + persistence; removed
`home_formation_name()`/`formation_changed`), `scripts/mechanics/
ai_brain.gd` (`lateral_bias`/`press_intensity` fields, `_lateral_
target_z()`, `_think_carrying`/`_think_support`/`_think_defend` updated),
`scripts/modes/full_game.gd` (`_configure_ai_brain()`, both AIBrain call
sites routed through it), `scripts/tuning.gd` (`AI_BOUNDARY_LEAN_
FRACTION`), `scripts/ui/team_list_screen.gd` (rebuilt around `Settings
Screen.Row`, three-row tactics card, up/down navigation), `scripts/
player/player_controller.gd` (`live_mark_prompts` → singular `live_mark_
prompt`), `scripts/ui/mark_prompt.gd` (single-badge draw, no more
stacking). Not touched: `scripts/ui/settings_screen.gd` (its `Row` class
was reused as-is, nothing about it needed to change), `scripts/ui/
formation_whiteboard.gd` (last entry's `selected_indices` highlight
already covers what this needed).
