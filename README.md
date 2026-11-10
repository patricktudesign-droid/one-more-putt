# One More Putt — Milestone A/B/C Prototype

A pocket-sized golf puzzle prototype built in Godot 4.x / GDScript, per
`One_More_Putt_Prototype_Brief.html`. Five holes, drag-to-aim putting,
automatic sand chips, undo/restart, stars, local best scores.

This covers brief Milestones A, B and C (one-hole toy → full mechanic set
and five holes → visual tokens, UI, saves, undo, completion panel).
**Milestone D (external device playtest) has not run** — see
`VALIDATION_LOG.md`.

## Requirements

- Godot 4.x stable (built and tested on **4.7.2.stable**, installed via
  `brew install --cask godot`). No other dependencies — everything (level
  data, UI, sounds) is generated from code; there are no external art or
  audio assets to install.

## Run it

Open the project in the Godot editor and press Play, or from a terminal:

```bash
godot --path /Users/patricktu/Desktop/OMP
```

Mouse acts as a single finger touch (touch emulation is enabled in project
settings), so it plays the same on desktop as it will on a phone.

## Run the automated checks

Two headless/scripted check suites live in `tests/`:

```bash
godot --headless --path /Users/patricktu/Desktop/OMP -s res://tests/test_ball_sim.gd
```

Pure simulation checks (stroke counting, undo restoration, terminal hole
capture, terrain mode switching, deterministic repeatability, wall bounce,
and a 10×5-hole stress pass) — runs fully headless, no window needed.

```bash
godot --path /Users/patricktu/Desktop/OMP -s res://tests/test_hole_e2e.gd
```

End-to-end checks that drive the **real scene** with synthetic mouse events
through the actual Godot GUI input pipeline (aim/drag/release, stroke
counting, undo, restart, a full hole completion, and a chip shot). This one
needs a real window — Control anchor layout and GUI input routing don't
resolve under `--headless`'s dummy display driver, so omit that flag.

Both suites currently pass in full (22 and 18 checks respectively).

## Export

No export templates are installed (`brew install --cask godot` only
installs the editor, not export templates — these are a separate, large
download). This means the project **runs from the editor** but cannot
currently be exported to a standalone macOS app, iOS build, Android APK,
or HTML5 build. To enable exporting:

1. In the Godot editor: **Editor → Manage Export Templates → Download and
   Install**, or `brew install --cask godot-export-templates` if a recent
   cask build is published for this Godot version.
2. Then **Project → Export…** to add a platform preset and build.

No `export_presets.cfg` exists yet since no target platform was specified;
add one once you know which platform(s) you want first.

## Project structure

```
project.godot        Engine/display/input/autoload config (390x844 portrait)
scenes/Main.tscn      Entry point — just a root Control + scripts/main.gd
scripts/
  main.gd             Screen manager: Hole <-> hole-select screen
  hole.gd             One playable hole: UI, input, undo/restart, completion
  hole_select.gd       Replay-selection / "choose a hole" screen
  course_view.gd       All course/ball/aim-preview drawing (procedural, no images)
  ball_sim.gd         Pure deterministic physics/rules (no scene-tree dependency)
  level_data.gd        The five holes' geometry, transcribed from the brief
  constants.gd         All tunable numbers in one place (brief section 03)
  save_data.gd          Autoload: local best scores / completion / sound pref
  sound.gd              Autoload: four procedurally synthesised placeholder SFX
  app_theme.gd          Small code-built Theme (palette from brief section 05)
tests/
  test_ball_sim.gd      Headless unit tests for ball_sim.gd
  test_hole_e2e.gd       Real-scene input-pipeline tests (needs a window)
```

Level data, physics constants and the whole UI are plain GDScript — there
are no `.tscn` scene files to hand-edit besides the one-line `Main.tscn`
entry point, so every number and layout in this prototype is visible and
editable directly in the scripts above.

See `VALIDATION_LOG.md` for what was actually run, what's still unverified,
the explicit interpretation calls made on ambiguous brief wording, and the
remaining asset list.
