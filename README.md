# Aussie Rules 2

A 3D Aussie Rules football game prototype built in Godot 4.6. The project currently includes a full match flow, AI-controlled players, menu screens, training modes, and a physical gameplay loop built around kicking, marking, tackling, spoil/smother, bumps, ruck contests, and scoring.

## Current status

This project is still under active development, but the core game loop is in place:

- full game mode with real clock, quarters, and match flow
- AI for non-human players and team formation setup
- solo practice mode: Kick-to-Kick with coaching challenges
- keyboard + gamepad input support with remapping
- procedural placeholder art and synthesized audio
- documentation under `docs/` covering feature status and rules

See:

- `docs/FEATURE_AUDIT.md` for the feature inventory and current roadmap
- `docs/MECHANICS_AUDIT.md` for gameplay and code-quality notes
- `docs/RULES_REFERENCE.md` for the simplified AFL rule model
- `docs/HANDOVER.md` for the project history and build notes

## Quick start

### Play the packaged build

1. Download the latest release from GitHub.
2. Extract the zip.
3. Open the extracted folder.
4. Run the executable for your platform.
5. Start from the main menu and choose the full match mode.

### Run from source in Godot

1. Install Godot 4.6 or newer.
2. Clone the repository:

```powershell
git clone https://github.com/Yaandle/aussie-rules2.git
cd aussie-rules2
```

3. Open `project.godot` in Godot.
4. Press Play to run the project.
5. Choose `FULL GAME` from the main menu.

### Optional: run via the Godot console

```powershell
& "C:\Godot\Godot_v4.6-stable_win64_console.exe" --path "F:\dev\aussie-rules2"
```

## Controls

The current control set is defined in `project.godot` and can be remapped from Settings -> Remap Controls.

Core actions:

- Move: `WASD`
- Sprint: `Shift` or `Ctrl`
- Camera: mouse / arrow keys / right stick
- Kick stance: hold `K` or right mouse / LT
- Kick execute: `F` or left mouse / RT
- Handball: `Q`
- Bounce: `Space`
- Mark / spoil / smother / tackle / bump: context-driven actions 
- Pause: `Esc`
- Switch controlled player: `Tab`
- Toggle control scheme: `M`

## Project structure

```text
project.godot              Godot project configuration
scripts/                   gameplay, AI, UI, mode, and shared logic
scenes/                    scene trees that mirror the script structure
assets/                    generated art and supporting assets
materials/                 environment and visual materials
themes/                    UI styling
docs/                      audit, rules, and handover notes
builds/                    local export/build output (ignored by git)
```

## Useful docs

- `docs/FEATURE_AUDIT.md` — feature status and roadmap
- `docs/MECHANICS_AUDIT.md` — code-quality pass and design notes
- `docs/RULES_REFERENCE.md` — AFL rules adapted for the prototype
- `docs/HANDOVER.md` — long-form build history and rationale

## Notes

- The game uses procedural placeholder characters and audio while the art pipeline is still evolving.
- Local generated files such as `.godot/`, export folders, and build artifacts are intentionally ignored by Git.
- For active development, keep feature work in a branch and treat `main` as the release-focused branch.
