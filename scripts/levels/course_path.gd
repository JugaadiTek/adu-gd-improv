class_name CoursePath
extends RefCounted
## Pure course-layout generator - no scene tree / nodes involved, so it can
## be unit tested directly. Places "household object" platforms like actual
## building blocks: each next piece sits exactly touching the previous one
## (zero gap, zero overlap - computed via each box's exact support distance
## along the direction of travel) along a winding heading that turns left
## and right for real minigolf-style dogleg routing, not just a straight
## corridor with a gentle side-to-side wobble. LevelController additionally
## lays a connecting "bridge" plank across every seam (see
## level_controller.gd) - that's the actual guaranteed-walkable surface;
## the blocks are the (non-overlapping) load-bearing pile under it, the way
## a kid's real backyard obstacle course would be built.

const TOUCH_GAP := 0.0 # exact touching: no gap, no overlap, between blocks
## Kept well above 0: the floor below the course is lava (see FloorSensor) -
## every piece must stay clearly above it, never at or near floor level.
const MIN_CENTER_Y := 0.4
const MAX_CENTER_Y := 4.0 # raised again (was 3.2) - "more verticality" ask
const BASE_LENGTH := 8.6 # original hand-built course's approximate path length (m)
const LENGTH_MULTIPLIER := 2.0 # halved from the earlier 4x pass per feedback
## Winding: a turn of this many degrees (either way) every ~2-4 pieces,
## with a gentle pull back toward straight-ahead so it still nets forward
## progress instead of coiling in place.
const TURN_DEGREES_MIN := 25.0
const TURN_DEGREES_MAX := 55.0
const STRAIGHTEN_PULL := 0.12
const Z_BOUND := 5.0   # hard steer back inward past this much side-to-side drift - keeps clear of the room's fixed furniture (see TestLevel.tscn)
const X_MIN_BOUND := -1.0 # soft steer forward if heading takes it behind the start

## Verticality: main platforms sit on genuine slopes, not just small steps -
## every 2-4 pieces a new target slope angle is picked in this range and
## held until the next change, so several consecutive pieces climb (or
## descend) together at one real, consistent grade.
const SLOPE_DEGREES_MIN := 5.0
const SLOPE_DEGREES_MAX := 38.0
## Absolute cap on how much height one single step can gain/lose regardless
## of the target angle - a 45' slope over a long step would otherwise demand
## an unplayable climb in one hop; the bridge across a held slope run is
## still a real 5-45' ramp, just spread over more than one piece for a
## steep angle.
const MAX_STEP_HEIGHT_ABS := 0.28
## Chance, at each slope-interval change, that the new climb/descend
## direction matches the previous one rather than a flat coin flip - a flip
## every interval is a random walk in height that rarely sustains a real
## climb (measured: with a flat 50/50, the generated course topped out
## around y=1.1 even with MAX_CENTER_Y raised well past the old 3.2 cap -
## the ceiling was never the actual bottleneck to "more verticality", this
## was). See where it's used below.
const CLIMB_PERSISTENCE := 0.70

## Mandatory jump gaps: real air gaps with no bridge, placed at roughly
## these fractions of the total path length (kept off the checkpoint/goal
## fractions of .25/.5/.75/1.0 so a gap doesn't land exactly on one).
const GAP_LENGTH_FRACTIONS := [0.35, 0.6, 0.85]
const GAP_DISTANCE := 1.1

const FLAVOR_NAMES := ["Book", "Ruler", "StationeryTray", "ToyBlock", "BoardGameBox", "MugCoaster", "RemoteBridge", "Cup", "Battery"]
## Sized so household objects visibly dwarf the eraser (~0.35 x 0.15 x 0.22)
## the way a book or remote would dwarf a real eraser - only the battery is
## left in the same size class as the eraser itself.
const FLAVOR_SIZES := [
	Vector3(2.2, 0.18, 1.6),  # Book
	Vector3(2.6, 0.08, 0.55), # Ruler
	Vector3(1.8, 0.20, 1.8),  # StationeryTray
	Vector3(1.2, 0.35, 1.2),  # ToyBlock
	Vector3(2.4, 0.26, 1.9),  # BoardGameBox
	Vector3(1.4, 0.18, 1.4),  # MugCoaster
	Vector3(2.0, 0.10, 0.55), # RemoteBridge
	Vector3(1.2, 0.18, 1.2),  # Cup
	Vector3(0.45, 0.16, 0.45), # Battery - eraser-scale
]
const FLAVOR_COLORS := [
	Color(0.65, 0.12, 0.12), Color(0.92, 0.8, 0.15), Color(0.85, 0.45, 0.05), Color(0.15, 0.35, 0.85),
	Color(0.5, 0.2, 0.6), Color(0.95, 0.95, 0.9), Color(0.15, 0.15, 0.17), Color(0.95, 0.55, 0.7),
	Color(0.25, 0.55, 0.3),
]


class Piece:
	var piece_name: String
	## Which FLAVOR_NAMES entry this piece is - kept separate from
	## piece_name because the last piece's piece_name gets overwritten to
	## "GoalPad" below (goal marker), which would otherwise make its flavor
	## unrecoverable for mesh lookup (LevelController needs to know a
	## GoalPad is still, say, a Book underneath to pick the right model).
	var flavor: String
	var pos: Vector3       # center position - and the collision box's transform (axis-aligned, never rotated)
	var size: Vector3
	var color: Color
	var cum_length: float  # cumulative path length up to and including this piece
	## Small cosmetic-only tilt (degrees). Applied to the *visual* mesh alone,
	## on top of the axis-aligned collision box at `pos`/`size` - so the pile
	## of "found objects" looks like a kid stacked it without actually
	## shrinking the safe, tested walkable footprint.
	var visual_tilt_deg: Vector3 = Vector3.ZERO
	## True if this piece is deliberately NOT touching the previous one - a
	## mandatory jump gap. LevelController skips the connecting bridge plank
	## for these so it's a real gap, not just a visual one.
	var has_gap_before: bool = false

	func _init(p_name: String, p_flavor: String, p_pos: Vector3, p_size: Vector3, p_color: Color, p_cum_length: float) -> void:
		piece_name = p_name
		flavor = p_flavor
		pos = p_pos
		size = p_size
		color = p_color
		cum_length = p_cum_length

	func top_y() -> float:
		return pos.y + size.y * 0.5


## Exact center-to-center distance, along normalized direction `dir` (XZ
## only), at which two axis-aligned boxes go from overlapping to touching -
## i.e. how far the ray from the origin in direction `dir` travels before
## exiting the combined "no overlap yet" box of half-extents
## (half_a + half_b). NOT `|dir.x|*Hx + |dir.y|*Hz` (that's each box's
## support/farthest-point distance, a different quantity that only happens
## to match this one when both boxes are square AND dir is exactly 45' -
## using it as if it were the touching distance is what let non-square, or
## non-45'-turn, pieces gap by several centimeters despite "no overlap"
## still holding, and only the playability test caught it).
static func _touch_distance(half_a: Vector2, half_b: Vector2, dir: Vector2) -> float:
	var combined := half_a + half_b
	var tx: float = INF if absf(dir.x) < 0.0001 else combined.x / absf(dir.x)
	var tz: float = INF if absf(dir.y) < 0.0001 else combined.y / absf(dir.y)
	return minf(tx, tz)


## Generates the winding, touching piece chain. Deterministic for a given seed.
static func generate(seed_value: int = 1337, target_length: float = BASE_LENGTH * LENGTH_MULTIPLIER) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var pieces: Array = []
	var size0: Vector3 = FLAVOR_SIZES[0]
	var pos := Vector3(0.0, MIN_CENTER_Y, 0.0)
	pieces.append(Piece.new(FLAVOR_NAMES[0] + "_Start", FLAVOR_NAMES[0], pos, size0, FLAVOR_COLORS[0], 0.0))

	var prev_size := size0
	var prev_pos := pos
	var cum_length := 0.0
	var heading_rad := 0.0 # pointing +X
	var steps_since_turn := 0
	var turn_interval := rng.randi_range(2, 4)
	var i := 1

	var steps_since_slope_change := 0
	var slope_interval := rng.randi_range(2, 4)
	var slope_angle_deg := 0.0
	var slope_climbing := true

	var gap_thresholds: Array = []
	for frac in GAP_LENGTH_FRACTIONS:
		gap_thresholds.append(target_length * frac)
	var next_gap_idx := 0
	var steps_since_gap := 100 # don't let two gaps land back-to-back

	while cum_length < target_length and i < 400:
		var flavor_i: int = i % FLAVOR_NAMES.size()
		var size: Vector3 = FLAVOR_SIZES[flavor_i]

		steps_since_turn += 1
		if steps_since_turn >= turn_interval:
			steps_since_turn = 0
			turn_interval = rng.randi_range(2, 4)
			var turn_sign: float = 1.0 if rng.randf() < 0.5 else -1.0
			heading_rad += deg_to_rad(rng.randf_range(TURN_DEGREES_MIN, TURN_DEGREES_MAX)) * turn_sign

		heading_rad = lerp_angle(heading_rad, 0.0, STRAIGHTEN_PULL) # net-forward bias
		# Hard override, not a blend: fixed room furniture sits just past
		# Z_BOUND (see TestLevel.tscn) with real collision CoursePath knows
		# nothing about - a soft nudge here previously still let the course
		# overshoot into it before correcting.
		if prev_pos.z > Z_BOUND:
			heading_rad = -PI * 0.5
		elif prev_pos.z < -Z_BOUND:
			heading_rad = PI * 0.5
		if prev_pos.x < X_MIN_BOUND:
			heading_rad = lerp_angle(heading_rad, 0.0, 0.5)

		var dir2 := Vector2(cos(heading_rad), sin(heading_rad))
		var step_dist: float = _touch_distance(
			Vector2(prev_size.x, prev_size.z) * 0.5, Vector2(size.x, size.z) * 0.5, dir2) + TOUCH_GAP

		# One mandatory jump gap per threshold crossed: no bridge, real air.
		# Guarded so two gaps can never land back-to-back - a real player
		# needs at least one solid landing platform to line up the next shot.
		var is_gap_step: bool = next_gap_idx < gap_thresholds.size() \
			and cum_length >= gap_thresholds[next_gap_idx] and steps_since_gap >= 2
		if is_gap_step:
			next_gap_idx += 1
			steps_since_gap = 0
			step_dist += GAP_DISTANCE
		else:
			steps_since_gap += 1

		var delta_xz := dir2 * step_dist

		# Held slope runs, not a per-step wobble: pick a target angle every
		# 2-4 pieces and keep climbing/descending at that grade until the
		# next change, so a run of pieces forms one real ramp. Bounded by
		# the *top surface* delta (not center-y): pieces vary in thickness
		# (a chunky ToyBlock vs a thin Ruler), so bounding center-y alone
		# let the actual visible/climbable ledge between two
		# different-thickness pieces run past the intended limit even
		# though each individual delta looked small - the playability test
		# caught the course failing to cross exactly that.
		var d_top := 0.0
		if not is_gap_step: # keep gap take-off/landing pieces level
			steps_since_slope_change += 1
			if steps_since_slope_change >= slope_interval:
				steps_since_slope_change = 0
				slope_interval = rng.randi_range(2, 4)
				slope_angle_deg = SLOPE_DEGREES_MIN + pow(rng.randf(), 1.3) * (SLOPE_DEGREES_MAX - SLOPE_DEGREES_MIN)
				slope_climbing = (rng.randf() < CLIMB_PERSISTENCE) == slope_climbing
			var slope_sign: float = 1.0 if slope_climbing else -1.0
			d_top = clampf(step_dist * tan(deg_to_rad(slope_angle_deg)) * slope_sign, -MAX_STEP_HEIGHT_ABS, MAX_STEP_HEIGHT_ABS)

		var prev_top_y: float = prev_pos.y + prev_size.y * 0.5
		var next_top_y: float = prev_top_y + d_top
		var next_y: float = next_top_y - size.y * 0.5
		if next_y > MAX_CENTER_Y or next_y < MIN_CENTER_Y:
			slope_climbing = not slope_climbing # keep climbing/descending consistent with the reflected direction
			d_top = -d_top
			next_top_y = prev_top_y + d_top
			next_y = next_top_y - size.y * 0.5
		# Hard safety net regardless of the reflection above: the course must
		# never dip to/below floor level (it's lava) or wander above the
		# climbable ceiling, even if reflection alone isn't enough to recover
		# (e.g. several small steps drifting the same direction in a row).
		next_y = clampf(next_y, MIN_CENTER_Y, MAX_CENTER_Y)

		var next_pos := Vector3(prev_pos.x + delta_xz.x, next_y, prev_pos.z + delta_xz.y)
		cum_length += prev_pos.distance_to(next_pos)
		var piece := Piece.new("%s_%d" % [FLAVOR_NAMES[flavor_i], i], FLAVOR_NAMES[flavor_i], next_pos, size, FLAVOR_COLORS[flavor_i], cum_length)
		# Kept small deliberately: these blocks touch their neighbors with
		# *zero* gap (see _touch_distance), so any tilt of the visual mesh
		# beyond a few degrees pokes its corners past the collision box and
		# into the touching neighbor - LevelController also shrinks the
		# mesh slightly as a second safety margin on top of this.
		piece.visual_tilt_deg = Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-5.0, 5.0), rng.randf_range(-3.0, 3.0))
		piece.has_gap_before = is_gap_step
		pieces.append(piece)

		prev_pos = next_pos
		prev_size = size
		i += 1

	var last: Piece = pieces[pieces.size() - 1]
	last.piece_name = "GoalPad"
	last.color = Color(0.85, 0.7, 0.15)
	return pieces


## Picks 3 checkpoint indices spaced at ~25/50/75% of actual travelled path
## length (not just piece count), so they're genuinely equidistant per spec.
static func pick_checkpoint_indices(pieces: Array) -> Array:
	var total_length: float = pieces[pieces.size() - 1].cum_length
	var targets := [total_length * 0.25, total_length * 0.5, total_length * 0.75]
	var indices: Array = []
	var search_from := 1
	for target in targets:
		var idx := search_from
		while idx < pieces.size() - 1 and pieces[idx].cum_length < target:
			idx += 1
		indices.append(idx)
		search_from = idx + 1
	return indices
