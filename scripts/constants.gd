class_name Constants
extends RefCounted

## Prototype tuning values per brief section 03 "Controls and rules".
## All are starting points explicitly flagged for playtest tuning.

# Course / ball geometry (local course units, matching the 320x480 playfield)
const COURSE_SIZE := Vector2(320, 480)
const PLAY_BOUNDS := Rect2(20, 20, 280, 440)
const BALL_RADIUS := 8.0
const HOLE_CAPTURE_RADIUS := 10.0
const HOLE_CAPTURE_MAX_SPEED := 60.0

# Aiming
const AIM_TOUCH_RADIUS := 28.0
const CANCEL_DRAG_PIXELS := 8.0
# Drag distance (px) that maps to maximum shot power. Tunable.
const MAX_DRAG_PIXELS := 120.0

# Putting
const PUTT_MAX_SPEED := 650.0
# Lowered from the brief's 600 starting point after playtest feedback: the
# roll felt too short/abrupt. Slower decel = more "flowing" roll-out.
const PUTT_DECEL := 380.0
# Ball entering sand while putting loses speed quickly (tunable multiplier).
const SAND_PUTT_DECEL_MULT := 4.0
# Raised from 0.75 after feedback that wall bounces felt weak/rare.
const WALL_RESTITUTION := 0.82
# Small forgiveness margin added to the ball radius only for wall collision
# checks, so near-grazes still register as a bounce (playtest feedback:
# "you have to hit it very close to bounce off the wall").
const WALL_COLLISION_MARGIN := 4.0
const REST_SPEED_THRESHOLD := 5.0
const REST_TIME_REQUIRED := 0.2

# Hole rim "lip out": a ball passing near the cup too fast to be captured
# gets gently curved around the rim instead of rolling straight past it.
const LIP_OUT_RADIUS := 26.0
const LIP_OUT_STRENGTH := 2.4

# Chipping
const CHIP_MAX_RANGE := 180.0
const CHIP_FLIGHT_TIME := 0.7
const CHIP_PEAK_HEIGHT := 60.0
const LOW_WALL_HEIGHT := 20.0
# Landing roll speed as a fraction of an "equivalent putt speed" derived from
# the chip's own power. Brief: "Start with 10% of equivalent putt speed."
const LANDING_ROLL_FRACTION := 0.10

# Physics stepping (prevents tunnelling through thin geometry)
const MAX_SUBSTEP_DISTANCE := 4.0

# Screen layout
const SCREEN_SIZE := Vector2(390, 844)
const MIN_TOUCH_TARGET := 44.0
