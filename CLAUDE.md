# Aussie Rules 2 — agent notes

This is a Godot 4.6 (Jolt) Aussie Rules football game. Work on branch
`update`. Never push; the user pushes after review.

## Read only what the task needs

- `docs/LESSONS.md`: design decisions, engine gotchas, how to verify. Read
  this first for any gameplay or physics task.
- `docs/RULES_REFERENCE.md`: AFL rules as implemented. §3 says contests are
  decided by physics and timing, **never a probability roll**.
- `docs/MECHANICS_AUDIT.md`: the mechanics audit; §B4 is the 5-stage
  ragdoll plan (stage 1 done).
- `docs/ML_AI_AUDIT.md`: the ML ladder (LR, GA, MLP marking cue in §9).
- `docs/CAREER_AUDIT.md`: Career mode audit, the user's decisions, and the
  8-phase plan (Phases 0–6 done).
- Code comments carry the "why". Read a script's header before changing it.

Don't go looking for `docs/HANDOVER.md`, `FEATURE_AUDIT.md`, `ui_audit.md`
or the old briefs. They were archived out of the repo on 2026-10-24 and are
superseded. `LESSONS.md` keeps what still matters from them.

## Where things are

- `scripts/tuning.gd`: every tunable plus the shared `Team` / `Action`
  enums. Never rename or renumber `Tuning.Action`.
- `scripts/player/player_controller.gd`: movement, actions, marking,
  tackling. Contest resolution lives here.
- `scripts/mechanics/ai_brain.gd`: AI. `human_brain.gd`: input.
- `scripts/dev/` and `scenes/dev/`: dev tools (animation viewer, ML page,
  ragdoll lab, data harnesses). New dev tooling goes here.
- `data/ml/`: ML datasets (`.gdignore`d) and trained weights.

## Rules of thumb

- Match the surrounding style: long `##` comments that explain why, and
  `Tuning` constants marked "unplaytested feel guess" when that's what they
  are.
- Verify headless (see `docs/LESSONS.md`). Say plainly what still needs the
  user's eyes.
- Commit only your own files; other sessions may share this checkout.
- Don't add a session log to the repo. Put durable lessons in
  `docs/LESSONS.md` (keep it short) and the rest in the commit message.
