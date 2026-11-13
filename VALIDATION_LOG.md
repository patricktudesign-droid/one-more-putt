# Validation log

Prepared 2026-11-10, Godot 4.7.2.stable (installed fresh via Homebrew for
this task), macOS/Apple Silicon.

## What ran, and what passed

| Check | How | Result |
|---|---|---|
| Full-project headless smoke run (`--headless --quit-after 120`) | Boots every autoload + Main + a Hole, runs ~2s of physics ticks | No errors, no warnings |
| `tests/test_ball_sim.gd` — 22 checks | `godot --headless -s res://tests/test_ball_sim.gd` | **22/22 passed** |
| `tests/test_hole_e2e.gd` — 18 checks | `godot -s res://tests/test_hole_e2e.gd` (real window, synthetic mouse events through the actual GUI input pipeline) | **18/18 passed** |
| Visual spot-checks | Rendered each hole, the completion panel, and the hole-select screen to PNG and inspected them | All 5 holes match the brief's geometry; completion panel and hole-select screen render correctly |

`test_ball_sim.gd` covers: stroke counting (exactly once per valid shot,
blocked while moving), undo restoring position/mode/strokes/completion,
terminal hole capture, terrain mode switching (including the hole-3 bug
below), deterministic repeatability (settles within 2 units across
identical repeats), wall bounce/energy loss, and a stress pass driving all
5 holes × 10 runs with randomised shots to check for hangs or exceptions
(a simulation-level proxy for the brief's "ten consecutive full five-hole
runs, no crashes" acceptance item).

`test_hole_e2e.gd` additionally proves the *real* input path works, not
just the simulation in isolation: a synthetic drag-release through Godot's
actual GUI event system correctly aims and fires a shot, a calibrated
full-power putt sinks hole 1 and shows the completion panel with the best
score saved, and a chip shot fired the same way clears the sand on hole 3.

### Bugs found and fixed during this pass

- **`Control.set_anchors_preset()` on a freshly-created, zero-size node
  preserves the current (zero) rect instead of filling the parent** — every
  full-rect/top-wide/bottom-wide container was collapsing to size (0,0) or
  zero-width. Fixed by switching to `set_anchors_and_offsets_preset()`,
  which explicitly zeroes offsets. Caught by rendering an actual screenshot
  and comparing it against the brief's mockup, not by the unit tests (which
  don't exercise Control layout).
- **The background `ColorRect` (and other full-rect containers) defaulted
  to `MOUSE_FILTER_STOP`**, silently swallowing every click/tap before it
  reached gameplay input (`_unhandled_input` never fired). Fixed by setting
  `mouse_filter = MOUSE_FILTER_IGNORE` on every non-interactive background
  container. Caught by the end-to-end input test, not the pure-simulation
  one — this is exactly the class of bug that only shows up when you drive
  the real GUI pipeline.
- **`BallSim.reset()` hardcoded `mode = PUTT`** regardless of whether the
  hole's start position is actually in sand, so hole 3 (which starts in a
  bunker) would incorrectly offer a putt instead of a chip on the very
  first shot. Fixed to compute `in_sand`/`mode` from the actual start
  position; added a regression check for it.

## Outer-wall collision bug (2026-11-10, from a gameplay recording)

**Symptom** (confirmed by scrubbing the submitted recording frame-by-frame
from 3.8s–5.3s): a putt on hole 2 reaches the right outer boundary around
4.5s and sits frozen there — no visible rebound, for as long as recorded.

**Root cause**: in `_step_rolling` (`ball_sim.gd`), the outer-wall branch
checked `_outer_blocked(tentative)` (the about-to-move-to position —
correctly detects the breach) but then derived the bounce normal from
`_outer_normal(position)` — the *current*, still-legitimately-inside-bounds
position. `_outer_normal`'s four checks are the same threshold tests as
`_outer_blocked`, so run against a position that hasn't crossed anything,
none of them fire, and the function falls through to its fallback:
`return Vector2.UP`. `Vector2.UP` is `(0, -1)` in Godot's 2D convention — a
*horizontal*-surface normal. `velocity.bounce(Vector2.UP)` only flips the Y
component; the real offending component (X, for a left/right wall) passes
through completely untouched. Since X velocity never reverses, every
subsequent substep recomputes the same blocked `tentative`, so `position`
never advances (the branch that assigns `position = tentative` is skipped
every time) — the ball is permanently re-colliding with itself at the same
point, frozen, while only the Y component visibly jitters and decays under
repeated `* WALL_RESTITUTION`. This is why only the **left/right** walls
were affected: a vertical (top/bottom) collision happens to need exactly a
vertical normal, so the wrong fallback is accidentally harmless there —
confirmed by reverting the fix and rerunning the test matrix below, which
failed only the right/left cases (16 of them), never top/bottom.

Internal (low) walls were never affected — `circle_rect_normal` computes
a proper closest-point projection, which is correct regardless of whether
the queried point has already crossed the rect, unlike `_outer_normal`'s
threshold branching.

**Fix**: one line, `hit_normal = _outer_normal(tentative)` instead of
`_outer_normal(position)` (`ball_sim.gd`, in `_step_rolling`'s outer-wall
branch). No tuning values were touched to fix this — it was a pure logic
bug, independent of restitution/decel/margin constants.

**What was actually tested** (`test_outer_wall_rebound_matrix` in
`test_ball_sim.gd`, 36 checks): for each of the 4 outer edges (right,
left, top, bottom) × head-on and shallow-angle (~20° off the wall) × low/
medium/high speed (150/400/650 units/s) — 24 combinations — plus a
bottom-right corner case, asserts: the ball actually rebounds, is pushed
back inward (correct sign, not just any motion), moves measurably after
the rebound (not frozen), never penetrates the boundary at any tick
afterward, and settles within a bounded tick count (catches the original
"never reaches RESTING, jitters forever" failure mode directly). For the
shallow-angle cases specifically, it also asserts the along-the-wall
(tangential) velocity component keeps its original sign — i.e. a grazing
hit keeps sliding the same way, rather than the bounce flipping or
cancelling it. Verified the matrix is non-vacuous by reverting the fix and
confirming it fails exactly the 16 left/right cases predicted by the root
cause above, then restoring the fix and confirming all 161 unit checks
(including this matrix) pass. Also replayed an equivalent hard rightward
shot on hole 2 in the actual running game (not just the isolated
simulation) and confirmed visually that the ball now rebounds well clear
of the wall instead of sticking.

## Physics pass against the HTML reference prototype (2026-11-13)

User supplied `preview.html`, a from-scratch HTML/Canvas prototype of the
same game, as the gameplay/visual reference, and asked for three specific
comparison shots to match: a gentle straight putt, a glancing wall
rebound, and a bunker chip. This section covers the physics side only —
see "Visual polish" below for the art-reference pass, done as a separate
commit per request.

### Translation scale (judgment call — flagged, not asserted as correct)

The reference's canvas/course (360x490, green 316x431) is not a uniform
rescale of ours (320x480, green 280x440) — the aspect ratios differ
(0.733 vs 0.636), so there is no single exact conversion factor between
the two. I translated distances/speeds using the play-area **height**
ratio, `S = 440/431 = 1.02088`, since the two shots that matter most for
this pass (a vertical straight putt, and a wall hit roughly a third of
the way down the course) both run mostly along that axis. Time durations
and dimensionless ratios are left unscaled (see the comment block at the
top of `constants.gd` for the full reasoning). The alternative — scaling
by the ball-radius ratio (8/7 = 1.143, since their ball radius is 7 and
ours is 8) — would have pushed `PUTT_MAX_SPEED` to ~749 instead of
leaving it at 650. **This choice of scale axis is the single biggest
judgment call in this pass** — if the three comparison shots don't feel
right side by side, this is the first thing to revisit.

### What actually changed (`constants.gd`, `ball_sim.gd`)

1. **Rolling resistance is now speed-dependent** (`PUTT_RESISTANCE_BASE`
   276 + `PUTT_RESISTANCE_K` 0.32 × current speed), replacing the flat
   `PUTT_DECEL` (380). This is a structural port, not just a retuned
   number — real friction + rolling resistance combine this way in the
   reference. Net effect: a soft putt now decelerates *more gently* at
   low speed than before (base 276 < old flat 380) but a hard putt
   decelerates *harder* right after release (base + k×650 ≈ 484) before
   tapering off. Recomputed every physics substep, not once per tick,
   since it depends on current speed.
2. **Wall-bounce formula fixed to only damp the normal component.** The
   previous code did `velocity.bounce(n) * WALL_RESTITUTION`, which
   scales the *entire* resulting vector (including the preserved
   tangential/along-the-wall component) by the restitution factor — so
   every bounce bled off some of the ball's sliding speed even on a pure
   graze. The reference's `rebound()` only modifies the into-the-wall
   component: `v -= (1+e) * (v·n) * n`. Switched to that formula exactly.
   This is the fix for "a glancing hit should keep most of its movement
   along the wall" — confirmed by reverting it and watching the new
   regression test fail (below), then restoring it and watching it pass.
3. **Sand (while putting) resistance**: flat 1695 (was `PUTT_DECEL * 4` =
   1520 under the old model), since the reference's sand resistance is
   itself flat, not speed-dependent — kept as a flat constant.
4. **Wall restitution**: 0.82 → 0.80 (reference uses 0.78 internal / 0.80
   outer; one shared constant, picked the outer value since that's what
   the comparison shot targets).
5. **Rest threshold**: speed threshold 5 → 3 (translated), dwell time
   0.2s → 0 (reference stops the instant speed crosses the threshold,
   no dwell at all; ours added a dwell last round that the reference
   doesn't have and doesn't need).
6. **Chip**: max range 180 → 206, peak height 60 → 45, flight duration
   0.7s → 0.68s (all translated from the reference's 202/44/0.68). Low-
   wall clearance for a chip in flight dropped the "+ ball radius" padding
   we'd added — the reference's clearance check is just `height > wall
   height`, no radius margin.
7. **Landing-roll fraction**: 0.10 → 0.29 (reference keeps 29% of the
   ball's actual speed at touchdown). **Judgment call, not a clean
   port**: the reference's chip is velocity-integrated throughout flight
   (real vx/vy under gravity-like z, no fixed target), so "speed at
   touchdown" is a real, measured quantity there. Ours is parametric — a
   lerp to a precomputed landing target over a fixed duration — chosen
   originally so the aim preview can show an exact landing spot. There is
   no real "impact velocity" in that model to port directly, so I kept
   our existing "equivalent putt speed" stand-in (already flagged as an
   assumption earlier in this log) and only changed the fraction applied
   to it. If the chip's landing roll doesn't feel like the reference's,
   this architecture difference is why, and reconciling it properly would
   mean switching the chip to velocity integration — a design change
   beyond "translate the values," flagging for your call.
8. **Max drag distance**: 120 → 100 course-units, derived from the
   reference's maxDrag (113px) as a *fraction of course width* (31.4%)
   rather than translated as an absolute distance, since it's a UI
   gesture mapping, not a world-physics quantity.
9. **Aim-start touch tolerance**: checked (27 theirs → 27.6 translated) —
   already matched by our existing 28, no change made.
10. **Max putt speed**: checked (655 theirs → ~669 translated) — within
    3% of our existing 650, left unchanged rather than chasing a
    difference that small.

### Checks actually run

- Full existing suite (161 unit + 25 e2e checks) re-run after every
  constant/formula change — all still pass. The existing outer-wall
  rebound matrix (36 cases) doesn't assume any particular resistance
  model, so it kept validating the collision geometry/direction
  correctly through this pass without modification.
- Two **new** regression tests added for the two structural changes:
  - `test_tangential_velocity_preserved_exactly`: a shallow-angle hit's
    along-the-wall speed must be within 5% of its pre-bounce value (not
    just same-sign, which the matrix already checked — this checks
    *magnitude*). Verified non-vacuous: reverted the bounce formula,
    confirmed this test (and only this test) fails, restored the fix,
    confirmed it passes again.
  - `test_resistance_is_speed_dependent`: measures instantaneous
    deceleration early in a hard putt (high speed) vs. late in the same
    putt (low speed, near rest) and asserts the first is measurably
    larger — confirms the base+k×speed model is actually active, not a
    flat rate in disguise.
  - Both existing closed-form putt-speed calibrations (unit + e2e tests,
    used to land a putt exactly on the hole for the capture tests) had to
    be replaced: the old `sqrt(2·decel·distance)` shortcut assumed
    constant deceleration, which no longer holds. Derived the exact
    closed-form stopping distance for the new `dv/dt = -(base+k·v)`
    model (`distance(v0) = v0/k - (base/k²)·ln(1+k·v0/base)`) and
    calibrate by bisecting on it instead.
- Stability: re-ran the e2e suite 3 times in a row after the full change
  set — no flakiness.

### What still needs your judgement

- **Whether the translation scale choice (play-height ratio vs. ball-
  radius ratio) is the right one.** I picked the one that keeps
  `PUTT_MAX_SPEED` close to where it already was; the other choice would
  have scaled nearly everything up ~14%.
- **The chip landing-roll architecture gap** (item 7 above) — I ported
  the *value* (29%) onto our existing stand-in rather than restructuring
  the chip to match the reference's velocity-integrated flight. If the
  chip roll-out still doesn't feel like the reference after this, that
  architecture difference is the likely reason, not a wrong constant.
- **Overall feel**, inherently — I can verify direction, magnitude,
  non-penetration and settling behavior mechanically (and did), but "does
  the gentle putt feel like the reference's gentle putt" is a judgment
  call only playing it side by side can answer. See the comparison-shot
  instructions below for exactly what to try.

## Rolling deceleration / stopping-threshold check (2026-11-10)

Per the request to re-tune these only after collisions were confirmed
solid: measured actual travel distance, settle time, and a tick-by-tick
position-delta trace for the last 20 ticks before resting, across low/
medium/high power (30%/60%/100% of max speed). Result: perfectly smooth,
monotonically-decreasing deltas down to exactly 0.0 with no reversals or
jitter; travel distances (52 / 203 / 227* units — *high power triggers a
real wall bounce partway, which is correct) feel proportionate to the
320x480 course. No further change made to `PUTT_DECEL` or
`REST_SPEED_THRESHOLD`/`REST_TIME_REQUIRED` — the values already set in
the previous round (in response to "stops too fast") check out, and most
of what read as "broken rolling" before was very likely the outer-wall
freeze above making ordinary medium/hard putts look stuck.

## Visual polish (2026-11-10)

- **Softly shaded ball**: a darker offset underlay circle (suggesting the
  side away from the light) plus a small fixed highlight dot (a stable
  implied light source, independent of the ball's own spin) replace the
  previous flat fill + thin outline.
- **Travel-driven rolling texture**: `BallSim.rotation` accumulates
  `distance_moved / BALL_RADIUS` (arc length / radius, i.e. rolling
  without slipping) every tick the ball actually advances — both while
  rolling and during a chip's ground-position interpolation. `course_view`
  draws three small dimples rotated by this angle (the fixed highlight
  above is drawn separately, in world space, so it does *not* spin with
  the ball — that would look wrong for a fixed light source).
- **Chip ground shadow**: now shrinks *and* fades with height (was scale-
  only, and barely shrank), a clearer "how high is it right now" cue.
- **Recessed cup**: a worn-turf rim ring, a dark bowl, and an inner shadow
  crescent offset toward the bottom-right (away from the same implied
  top-left light as the ball), instead of one flat solid disc.
- **Sink animation**: on hole completion, `course_view.play_sink_animation()`
  tweens the ball down to nothing over 0.4s (shrinking in place) before the
  completion panel appears, instead of an instant cut. `hole.gd`'s
  `_handle_hole_complete` now awaits that duration before populating/
  showing the panel; the end-to-end test was updated to wait for the panel
  rather than asserting it's visible the instant `sim.completed` flips.
- **Star graphics**: replaced the Unicode "★"/"☆" `Label` text (reported
  broken — almost certainly missing glyph coverage in whatever font the
  engine/export resolves to, a known risk with relying on Unicode symbol
  characters rather than drawn shapes) with `star_row.gd`, a small Control
  that draws real 5-point star polygons (filled coral for earned, outlined
  pale for unearned). Used on both the hole-completion panel and the
  hole-select screen's best-score rows (same underlying bug, same fix).

Verified all five visually: rendered a static hole (ball shading + dimples
+ recessed cup), captured a mid-sink-animation frame and the final
completion panel (stars + golf term together), and the hole-select
screen's per-row stars at two different scores.

## Explicit interpretation calls (brief was ambiguous or silent)

The brief asked unknowns to be flagged rather than silently guessed. These
are the non-obvious judgment calls baked into `ball_sim.gd`:

1. **"Equivalent putt speed" for a chip's landing roll** (section 03,
   Landing row) is never defined. Implemented as
   `(chip_distance / CHIP_MAX_RANGE) * PUTT_MAX_SPEED` — i.e. a full-range
   chip rolls out like a full-power putt; a short chip barely rolls. The
   10% fraction itself is taken directly from the brief.
2. **Airborne collision with a low wall vs. "invalid landing overlapping a
   wall"** (section 03, Airborne collisions row) reads as two different
   failure modes but only the second one's consequence is spelled out.
   Implemented as: a *mid-flight* obstruction (ball not high enough to
   clear) lands the ball at the last clear point with no extra penalty
   (the stroke already counted stands); only a *final landing spot* that
   itself overlaps a wall triggers "Blocked landing" + position restore.
3. **"Blocked landing" restore + undo stack interaction**: the brief says
   it "restores the pre-shot position, counts the shot" — i.e. position
   reverts but the stroke doesn't. Implemented by restoring from the same
   snapshot Undo would use, but overwriting its stroke count with the
   post-shot (incremented) value, and leaving that snapshot on the undo
   stack so Undo still works normally afterward.
4. **Drag-to-power mapping constant** (`MAX_DRAG_PIXELS = 120`,
   `constants.gd`) — the brief specifies the *gesture* (drag length →
   power, clamped) but not the exact pixel-to-power curve. Linear, tunable,
   called out explicitly as a constant.
5. **Sand putt-deceleration multiplier** (`SAND_PUTT_DECEL_MULT = 4.0`) —
   brief says "loses speed quickly," no number given. Tunable constant.
6. **Outer wall collision** modeled as "ball circle must stay inside the
   inset play bounds rectangle" rather than true geometric wall segments —
   equivalent for this prototype's rectangular courses, much simpler to
   implement and verify.
7. **Rounded course corners** from the brief's SVG mockup are omitted in
   the actual renderer (plain rects) — cosmetic only, calling out since the
   brief's reference image has them and the live course currently doesn't.
8. **Reduce-motion toggle** mentioned under "Asset checklist"/motion
   guidance is not implemented — it isn't in the section 02 locked "Build
   now" scope list, and motion was kept minimal (no confetti, short
   transitions) by default regardless.

## What was NOT verified (and why)

- **No real device/touch testing.** Everything above ran via mouse-as-touch
  emulation in the Godot editor on a Mac. That's explicitly Milestone D in
  the brief ("Test on actual phones") — a separate, human-driven step, not
  something to fake here. Do not read the automated passes above as device
  verification.
- **Hole route completability for holes 2, 4 and 5 is verified by
  geometric inspection, not an automated solve.** Hole 1 is proven
  completable by an automated full playthrough; hole 3's chip-out-of-sand
  path is proven by an automated chip test. For holes 2/4/5 I confirmed by
  inspecting the transcribed wall/sand rectangles that an un-blocked
  corridor exists to the hole (matching the brief's own route
  descriptions), and the stress test (10×5 holes, randomised shots) never
  hung, but I did not write an automated solver that proves a human can
  reliably route each one in the target stroke count. Per the brief's own
  section 08, actual tuning/target-score validation is meant to come from
  real play, not code.
- **Target stroke counts (1/2/2/2/3) are exactly what the brief specified**
  and are explicitly called "provisional" there — no retuning was done.
- **Different aspect ratios / safe areas**: the course layout recomputes
  its scale/offset reactively from the control's actual size (not
  hardcoded), so it should adapt to other portrait aspect ratios, but this
  was only rendered at the project's own 390×844 design resolution — not
  tested against other device aspect ratios.
- **Sound**: the four effects (putt, wall tap, sand landing, cup) are
  short procedurally-synthesised tones generated in `sound.gd`, not
  designed audio — functional placeholders only, as called out in the
  asset list below.

## Tuning values currently in effect

Most are still the brief's own suggested starting points (`constants.gd`),
not yet adjusted by real play: `PUTT_MAX_SPEED=650`, `CHIP_MAX_RANGE=180`,
`CHIP_FLIGHT_TIME=0.7s`, `CHIP_PEAK_HEIGHT=60`, landing roll `=10%` of
equivalent putt speed, rest threshold `5 units/s` for `0.2s`, capture
radius `10`, capture max speed `60`, ball radius `8`.

Changed after a first round of hands-on playtest feedback (2026-11-10):

- `PUTT_DECEL`: 600 → **380** — the roll felt too short/abrupt; this gives
  a noticeably longer, more "flowing" roll-out for the same drag power.
- `WALL_RESTITUTION`: 0.75 → **0.82** — bounces felt weak.
- New `WALL_COLLISION_MARGIN = 4.0` — a small forgiveness margin added to
  the ball's collision radius (walls only) so near-grazes still register
  as a bounce, addressing "you have to hit it very close to bounce off
  the wall."
- New `LIP_OUT_RADIUS = 26`, `LIP_OUT_STRENGTH = 2.4` — a ball passing the
  cup too fast to drop now curves gently around the rim instead of rolling
  a dead-straight line past it ("lip out").

These are still first-pass numbers tuned by playing it a few times, not a
rigorous playtest pass — expect to keep adjusting them.

## Added after initial feedback (this round)

- **Golf scoring terms** on the completion panel: Hole in One / Eagle /
  Birdie / Par / Bogey / +N, computed from strokes vs. the hole's target
  (par). `Hole._golf_term(strokes, par)` in `hole.gd`, unit-tested in
  `test_hole_e2e.gd`.
- **Two more sounds**: a distinct chip-release tone (separate from the putt
  tone) and a short ascending "hole in one" chime that plays instead of the
  ordinary cup sound when the hole is sunk in one stroke.
- **Longer, gradient aim line** (light red → dark red with power) plus a
  **predicted bounce trajectory** for putts: while aiming, a dotted preview
  line shows where the ball will actually travel — including wall bounces
  and the new lip-out curve — computed by running a real (throwaway)
  `BallSim` forward through the exact same physics as the live shot, not an
  approximation.
- A **web (HTML5/WebAssembly) export** now builds successfully. Export
  templates (1.2GB) were downloaded and installed, and `export_presets.cfg`
  configures a thread-free "Web" preset (threads need COOP/COEP headers
  most static hosts don't send by default, so they're disabled for
  portability). The engine `.wasm` is ~39MB uncompressed — too large for
  Claude's own Artifact hosting (16MB per-file cap) or Netlify Drop's
  anonymous-upload cap, and Netlify Drop's unclaimed links expire in an
  hour and sit behind a password besides, so neither was usable for a
  lasting link.
- **Deployed to GitHub Pages instead**: the repo at
  https://github.com/patricktudesign-droid/one-more-putt serves the web
  build from `docs/` on `main`, live at
  https://patricktudesign-droid.github.io/one-more-putt/. One gotcha hit
  along the way: GitHub Pages' legacy builder runs everything through
  Jekyll by default, which failed outright on the raw WASM/JS output
  ("Page build failed", no detail) — fixed with an empty `docs/.nojekyll`
  file, which tells Pages to serve the folder as-is. Verified live by
  loading the page and actually dragging/releasing a shot through the
  real deployed site, not just checking it returns HTTP 200.

## Remaining asset needs

- A real typeface (rounded sans per brief section 05/12) — currently the
  Godot default editor font.
- Final course-edge, low-wall and sand textures/shapes beyond the current
  flat procedural vector fills.
- Designed sound effects to replace the four placeholder synthesised tones.
- App icon beyond the simple placeholder SVG circle-and-flag in `icon.svg`.
- `export_presets.cfg` + downloaded export templates, once a target
  platform is chosen (see README "Export").
