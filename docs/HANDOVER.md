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
