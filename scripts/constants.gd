class_name Constants
extends RefCounted

## Prototype tuning values per brief section 03 "Controls and rules",
## subsequently re-tuned against the HTML reference prototype
## (One_More_Putt preview.html) on 2026-11-13.
##
## TRANSLATION SCALE: the reference's canvas/course (360x490, green
## 316x431) isn't a uniform rescale of ours (320x480, green 280x440) — the
## aspect ratios differ slightly, so there is no single exact conversion
## factor. We translate using the play-area HEIGHT ratio,
## S = 440/431 = 1.02088, since both comparison shots that matter most
## (a straight vertical putt, and a wall hit partway up/down the course)
## run mostly along that axis. A distance or speed value (their units) is
## translated as value * S; a plain time duration is left unscaled; a
## dimensionless ratio (like the resistance-vs-speed coefficient, or a
## drag-length fraction already expressed relative to course width) is
## also left unscaled. This is a judgment call, not a derivation — the
## alternative (scaling by the ball-radius ratio 8/7 = 1.143) would have
## pushed PUTT_MAX_SPEED to ~749 instead of leaving it alone; flagging
## this choice rather than asserting it's the only correct one.

# Course / ball geometry (local course units, matching the 320x480 playfield)
const COURSE_SIZE := Vector2(320, 480)
const PLAY_BOUNDS := Rect2(20, 20, 280, 440)
const BALL_RADIUS := 8.0
const HOLE_CAPTURE_RADIUS := 10.0
const HOLE_CAPTURE_MAX_SPEED := 60.0

# Aiming
# Reference's aim-start touch tolerance (27, their units) translates to
# 27.6 — already matched by our existing 28, so left unchanged.
const AIM_TOUCH_RADIUS := 28.0
const CANCEL_DRAG_PIXELS := 8.0
# Reference's maxDrag (113px of a 360-wide canvas) is ~31.4% of course
# width; applied to our 320-wide course that's ~100px, down from our
# previous 120 (meaning max power now needs a slightly shorter drag).
const MAX_DRAG_PIXELS := 100.0

# Putting
# Reference's max putt speed (655, their units) translated by S is ~669 —
# close enough to our existing 650 (<3%) that it's left as-is rather than
# chasing a sub-3% difference.
const PUTT_MAX_SPEED := 650.0
# Rolling resistance ported structurally from the reference, not just
# retuned as a single number: reference uses resistance = base + k*speed
# (real friction + rolling resistance combine this way), not a flat
# deceleration. base is a distance/time^2 term, translated by S; k is
# dimensionless (resistance-per-unit-speed = 1/time) and left unscaled.
# This means a soft putt now decelerates more gently than before at low
# speed (base 276 < old flat 380) but a hard putt decelerates *harder*
# initially (base + k*650 ≈ 484) before tapering off — a floatier finish
# and a punchier start, versus the old single-rate decay.
const PUTT_RESISTANCE_BASE := 276.0  # 270 * S
const PUTT_RESISTANCE_K := 0.32      # unscaled (1/time)
# Sand resistance while putting: reference uses a flat (not speed-
# dependent) value here, so this stays a flat constant rather than a
# base+k model.
const SAND_PUTT_RESISTANCE := 1695.0  # 1660 * S
# Lowered from 0.82 to the reference's outer-wall value (.8; its internal
# walls use .78 — we use one constant for both, splitting the difference
# is unnecessary since .8 is close to both).
const WALL_RESTITUTION := 0.80
# Small forgiveness margin added to the ball radius only for wall collision
# checks, so near-grazes still register as a bounce (playtest feedback:
# "you have to hit it very close to bounce off the wall"). Independent of
# this reference pass — kept as-is.
const WALL_COLLISION_MARGIN := 4.0
# Reference stops the instant speed drops below 3 (their units), with no
# dwell time at all. Translated: threshold 3*S ≈ 3.06, rounded to 3; dwell
# time dropped to ~0 (one tick) to match the reference's immediate stop —
# our own added "sustained for 0.2s" dwell wasn't in the reference and
# wasn't needed (no jitter in either model at these resistance values).
const REST_SPEED_THRESHOLD := 3.0
const REST_TIME_REQUIRED := 0.0

# Hole rim "lip out": a ball passing near the cup too fast to be captured
# gets gently curved around the rim instead of rolling straight past it.
# Not present in the reference at all (its capture check is a simple
# distance+speed test with no near-miss curve) — kept as our own addition
# from the previous round, untouched by this pass.
const LIP_OUT_RADIUS := 26.0
const LIP_OUT_STRENGTH := 2.4

# Chipping
# Reference: max chip distance 202, peak height 44, flight duration 0.68s
# (ours was 180/60/0.7). Distances/heights scaled by S; duration left as a
# plain time value and taken ~verbatim since it's already close to ours.
const CHIP_MAX_RANGE := 206.0   # 202 * S
const CHIP_FLIGHT_TIME := 0.68
const CHIP_PEAK_HEIGHT := 45.0  # 44 * S
const LOW_WALL_HEIGHT := 20.0
# Landing roll-out: reference keeps 29% of the ball's actual speed at the
# moment it touches down (a simple post-bounce velocity retention). Our
# chip flight is parametric (lerp to a precomputed target over a fixed
# duration) rather than velocity-integrated like the reference, so there
# is no real "impact velocity" to retain the same way — this was already
# flagged as an interpretation call in VALIDATION_LOG.md ("equivalent putt
# speed"). We keep that existing architecture and only port the fraction
# itself (0.10 -> 0.29), applied to the same equivalent-putt-speed value
# as before. This is the one constant here that is not a clean structural
# port — flagging it as a judgment call, not a measured match.
const LANDING_ROLL_FRACTION := 0.29

# Physics stepping (prevents tunnelling through thin geometry)
const MAX_SUBSTEP_DISTANCE := 4.0

# Screen layout
const SCREEN_SIZE := Vector2(390, 844)
const MIN_TOUCH_TARGET := 44.0
