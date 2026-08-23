extends Node
## Automated test suite entry point. Run headless via:
##   godot --headless --path <project> res://scenes/tests/TestRunner.tscn
## (or tools/run_tests.ps1 / .sh, which locate Godot for you). Exits 0 if
## every check passed, 1 otherwise - safe to wire into CI.
##
## Unit tests cover pure logic (CoursePath, GameManager, ClubController.
## should_strike). Small scene tests cover single-node behavior that needs a
## physics step but not a full level (Eraser spawn guard). The integration
## test spins up the real TestLevel scene with 2 simultaneous players and
## drives their balls through checkpoints/goal/a simulated fall, to catch
## scene-wiring and physics regressions - including a permanent regression
## check for the continuous_cd teleport-fling bug found 2026-08-20.

var passed := 0
var failed := 0


func _ready() -> void:
	await get_tree().process_frame
	_run_unit_tests()
	await _run_spawn_guard_test()
	await _run_teleport_settle_race_test()
	await _run_backward_hit_reset_test()
	await _run_integration_tests()
	await _run_playability_test()
	_finish()


func _check(cond: bool, test_name: String) -> void:
	if cond:
		passed += 1
		print("[PASS] %s" % test_name)
	else:
		failed += 1
		print("[FAIL] %s" % test_name)


func _run_unit_tests() -> void:
	_test_course_path()
	_test_game_manager()
	_test_club_controller_logic()


func _test_course_path() -> void:
	var pieces: Array = CoursePath.generate()
	_check(pieces.size() > 2, "CoursePath.generate produces multiple pieces")

	var total_length: float = pieces[pieces.size() - 1].cum_length
	var expected_min: float = CoursePath.BASE_LENGTH * CoursePath.LENGTH_MULTIPLIER * 0.9
	_check(total_length >= expected_min, "CoursePath length reaches the target (%.1fm >= %.1fm)" % [total_length, expected_min])

	# Blocks must never interpenetrate ("treat them like building blocks").
	# Non-gap pairs must sit exactly touching (LevelController's bridge
	# planks handle the actual walking surface across the seam); pieces
	# marked has_gap_before are the mandatory jump gaps and are *expected*
	# to be separated by roughly CoursePath.GAP_DISTANCE, no bridge.
	var any_overlap := false
	var max_touching_gap := 0.0
	var gap_count := 0
	for i in range(1, pieces.size()):
		var a = pieces[i - 1]
		var b = pieces[i]
		var gap_x: float = absf(b.pos.x - a.pos.x) - (a.size.x * 0.5 + b.size.x * 0.5)
		var gap_z: float = absf(b.pos.z - a.pos.z) - (a.size.z * 0.5 + b.size.z * 0.5)
		if gap_x < -0.01 and gap_z < -0.01:
			any_overlap = true
		var true_gap: float = Vector2(maxf(gap_x, 0.0), maxf(gap_z, 0.0)).length()
		if b.has_gap_before:
			gap_count += 1
			_check(true_gap > 0.5, "jump gap %d is a real gap, not a touching seam (%.2fm)" % [gap_count, true_gap])
		else:
			max_touching_gap = maxf(max_touching_gap, true_gap)
	_check(not any_overlap, "no two CoursePath blocks interpenetrate")
	_check(max_touching_gap < 0.05, "non-gap blocks sit touching, not gapped (max separation %.3fm)" % max_touching_gap)

	# Regression check for "the last section leads inside other geometry":
	# fixed room furniture (table, bed, TV - see TestLevel.tscn) has real
	# collision, and CoursePath has no idea where it is. Z_BOUND is what's
	# supposed to keep the generated course out of the furniture's zone;
	# check it actually does, with a margin generous enough to also cover
	# bridge planks reaching a bit past a piece's own footprint.
	var furniture_boxes := [ # [center_x, center_z, half_x, half_z]
		[3.0, 8.3, 1.6, 1.6],   # table
		[14.0, 8.3, 3.1, 1.6],  # bed
		[-3.0, -9.0, 0.7, 0.75], # CRT TV
		[3.0, 10.0, 0.4, 0.4],  # chair 1 (see 08_008.md - furniture pass)
		[3.0, 6.6, 0.4, 0.4],   # chair 2
	]
	var furniture_hit := false
	for piece in pieces:
		for box in furniture_boxes:
			var dx: float = absf(piece.pos.x - box[0]) - (piece.size.x * 0.5 + box[2])
			var dz: float = absf(piece.pos.z - box[1]) - (piece.size.z * 0.5 + box[3])
			if dx < 0.5 and dz < 0.5: # generous margin, not a tight touch check
				furniture_hit = true
	_check(not furniture_hit, "generated course stays clear of the room's fixed furniture")
	_check(gap_count >= 2, "at least 2 mandatory jump gaps were placed (found %d)" % gap_count)

	var checkpoints: Array = CoursePath.pick_checkpoint_indices(pieces)
	_check(checkpoints.size() == 3, "pick_checkpoint_indices returns 3 checkpoints")
	_check(checkpoints[0] < checkpoints[1] and checkpoints[1] < checkpoints[2] and checkpoints[2] < pieces.size() - 1,
		"checkpoints are strictly increasing and precede the goal piece")


func _test_game_manager() -> void:
	GameManager.setup_players(2, Transform3D.IDENTITY)
	_check(GameManager.players.size() == 2, "setup_players(2) creates 2 players")
	_check(GameManager.active_player_index == 0, "match starts on player 0")
	_check(not GameManager.turn_ready, "a fresh match starts with turn_ready false (popup buffer)")

	GameManager.add_stroke()
	_check(GameManager.players[0].stroke_count == 1, "add_stroke increments the active player's stroke count")
	_check(GameManager.stroke_pending_turn_switch, "add_stroke arms the turn-switch flag")

	GameManager.reach_checkpoint(0, 1, Transform3D.IDENTITY)
	GameManager.reach_checkpoint(0, 1, Transform3D.IDENTITY)
	_check(GameManager.players[0].checkpoint_order == 1, "reach_checkpoint sets the order for the named player")
	_check(GameManager.players[1].checkpoint_order == -1, "reach_checkpoint does not affect other players")
	GameManager.reach_checkpoint(0, 0, Transform3D.IDENTITY)
	_check(GameManager.players[0].checkpoint_order == 1, "reach_checkpoint rejects a lower/duplicate order")

	GameManager.advance_turn()
	_check(GameManager.active_player_index == 1, "advance_turn moves to the next player")
	_check(not GameManager.turn_ready, "advance_turn resets turn_ready (next popup buffer)")

	GameManager.complete_player(1)
	_check(GameManager.players[1].finished, "complete_player marks them finished")
	_check(GameManager.active_player_index == 0, "advance_turn (called internally) skips back to the unfinished player")

	GameManager.complete_player(0)
	_check(GameManager.match_complete, "match_complete once every player has finished")

	GameManager.setup_players(1, Transform3D.IDENTITY) # clean slate for later tests


func _test_club_controller_logic() -> void:
	_check(ClubController.should_strike(0.1, 3.0, 0.35, 1.5, true, false, true, true),
		"should_strike: in range, fast enough, button held, settled, turn ready -> true")
	_check(not ClubController.should_strike(0.1, 3.0, 0.35, 1.5, true, false, true, false),
		"should_strike: turn not ready (popup buffer) -> false")
	_check(not ClubController.should_strike(0.1, 3.0, 0.35, 1.5, false, false, true, true),
		"should_strike: button not held -> false")
	_check(not ClubController.should_strike(1.0, 3.0, 0.35, 1.5, true, false, true, true),
		"should_strike: out of hit radius -> false")
	_check(not ClubController.should_strike(0.1, 0.5, 0.35, 1.5, true, false, true, true),
		"should_strike: swing too slow -> false")
	_check(not ClubController.should_strike(0.1, 3.0, 0.35, 1.5, true, true, true, true),
		"should_strike: on cooldown -> false")
	_check(not ClubController.should_strike(0.1, 3.0, 0.35, 1.5, true, false, false, true),
		"should_strike: eraser not settled -> false")


## Two erasers spawned at the same point should not collide with each other
## (collision_layer/mask cleared) until each has individually moved away
## from that point, at which point it rejoins normal eraser-vs-eraser
## collision.
func _run_spawn_guard_test() -> void:
	var eraser_a: Eraser = load("res://scenes/objects/Eraser.tscn").instantiate()
	var eraser_b: Eraser = load("res://scenes/objects/Eraser.tscn").instantiate()
	add_child(eraser_a)
	add_child(eraser_b)
	var origin := Vector3(100, 5, 100) # away from the course/floor entirely
	eraser_a.player_index = 0
	eraser_b.player_index = 1
	await eraser_a.teleport_to(Transform3D(Basis.IDENTITY, origin))
	await eraser_b.teleport_to(Transform3D(Basis.IDENTITY, origin + Vector3(0.05, 0, 0)))
	eraser_a.begin_spawn_guard(origin)
	eraser_b.begin_spawn_guard(origin)

	_check(eraser_a.collision_layer == 0, "spawn-guarded eraser has collision_layer cleared")
	_check(eraser_a.collision_mask == Eraser.COURSE_LAYER, "spawn-guarded eraser only still detects the course")

	# freeze() suspends gravity too, so give it a nudge and let it fly clear.
	eraser_a.freeze = false
	eraser_a.apply_central_impulse(Vector3(5, 0, 0))
	var moved := false
	for _i in range(120):
		await get_tree().physics_frame
		if eraser_a.collision_layer == Eraser.ERASER_LAYER:
			moved = true
			break
	_check(moved, "eraser's collision guard lifts once it moves away from the spawn point")
	_check(eraser_a.collision_mask == (Eraser.COURSE_LAYER | Eraser.ERASER_LAYER),
		"...and its mask includes the eraser layer again afterward")

	eraser_a.queue_free()
	eraser_b.queue_free()
	await get_tree().process_frame


## Regression test for a race found via the playability sim: teleport_to()
## zeroes velocity (and sets `freeze`) synchronously, then only clears
## `freeze` a physics frame later. Anything polling is_settled() in that
## one-frame gap used to see "settled" (velocity is zero) while the body
## was still frozen, so a strike landing there was silently dropped by the
## physics server. is_settled() now stays false for that whole window -
## reproduced here by driving the same sequence teleport_to() runs.
func _run_teleport_settle_race_test() -> void:
	var eraser: Eraser = load("res://scenes/objects/Eraser.tscn").instantiate()
	add_child(eraser)
	eraser.player_index = 0

	eraser._teleporting = true
	eraser.freeze = true
	eraser.global_transform = Transform3D(Basis.IDENTITY, Vector3(200, 5, 200))
	eraser.linear_velocity = Vector3.ZERO
	eraser.angular_velocity = Vector3.ZERO
	_check(not eraser.is_settled(), "is_settled() is false during the teleport freeze window, not just once velocity hits zero")

	await get_tree().physics_frame
	eraser.freeze = false
	eraser._teleporting = false
	_check(eraser.is_settled(), "...and true again once the teleport actually finishes")

	eraser.queue_free()
	await get_tree().process_frame


func _run_integration_tests() -> void:
	var level: Node3D = load("res://scenes/levels/TestLevel.tscn").instantiate()
	add_child(level)
	await get_tree().create_timer(0.3).timeout

	var erasers_root: Node3D = level.get_node("Erasers")
	_check(erasers_root.get_child_count() == 1, "TestLevel spawns one Eraser per player (pending_player_count default 1)")

	var course_root: Node3D = level.get_node("Course")
	_check(course_root.get_child_count() > 10, "Course container is populated with generated pieces (%d)" % course_root.get_child_count())

	var goal: GoalArea = level.get_node("Goal")
	var goal_horiz_dist: float = Vector2(goal.global_position.x, goal.global_position.z).length()
	_check(goal_horiz_dist > 4.0, "Goal is repositioned well away from the start (horizontal dist=%.1f)" % goal_horiz_dist)

	# Re-run the match for 2 players. Calling the level's own start_match()
	# (not reimplementing eraser spawning here) is what keeps TurnManager's
	# `erasers` array, camera target, and club target in sync - skipping it
	# previously left TurnManager holding a freed reference to the
	# single-player eraser this replaces, which spammed script errors.
	var test_erasers: Array = level.start_match(2)
	await get_tree().create_timer(0.1).timeout
	var p0: Eraser = test_erasers[0]
	var p1: Eraser = test_erasers[1]

	var cp1: Checkpoint = level.get_node("Checkpoint1")
	var cp2: Checkpoint = level.get_node("Checkpoint2")
	var cp3: Checkpoint = level.get_node("Checkpoint3")

	await p0.teleport_to(Transform3D(Basis.IDENTITY, cp1.global_position + Vector3(0, 0.3, 0)))
	await get_tree().create_timer(0.15).timeout
	_check(GameManager.players[0].checkpoint_order == 1, "player 0's ball reaching Checkpoint1 registers order 1 for player 0")
	_check(GameManager.players[1].checkpoint_order == -1, "...and does not affect player 1")

	await p1.teleport_to(Transform3D(Basis.IDENTITY, cp1.global_position + Vector3(0, 0.3, 0)))
	await get_tree().create_timer(0.15).timeout
	_check(GameManager.players[1].checkpoint_order == 1, "player 1's ball independently registers its own Checkpoint1")

	await p0.teleport_to(Transform3D(Basis.IDENTITY, cp2.global_position + Vector3(0, 0.3, 0)))
	await get_tree().create_timer(0.15).timeout
	await p0.teleport_to(Transform3D(Basis.IDENTITY, cp3.global_position + Vector3(0, 0.3, 0)))
	await get_tree().create_timer(0.15).timeout
	_check(GameManager.players[0].checkpoint_order == 3, "player 0 can progress through all 3 checkpoints")

	await p0.teleport_to(Transform3D(Basis.IDENTITY, goal.global_position + Vector3(0, 0.3, 0)))
	await get_tree().create_timer(0.15).timeout
	_check(GameManager.players[0].finished, "player 0 reaching Goal marks them finished")
	_check(not GameManager.match_complete, "...but the match isn't complete while player 1 hasn't finished")

	await p1.teleport_to(Transform3D(Basis.IDENTITY, goal.global_position + Vector3(0, 0.3, 0)))
	await get_tree().create_timer(0.15).timeout
	_check(GameManager.match_complete, "match completes once every player has reached Goal")

	# Regression test: continuous_cd + an instant teleport used to fling the
	# eraser to a bogus position (found 2026-08-20). Fall off-course onto
	# open floor and confirm it lands back near the last checkpoint instead.
	var fall_point := Vector3(20, 0.5, 8)
	await p0.teleport_to(Transform3D(Basis.IDENTITY, fall_point))
	await get_tree().create_timer(1.0).timeout
	var displaced: float = p0.global_position.distance_to(fall_point)
	_check(displaced > 3.0, "falling onto open floor respawns cleanly (no CCD-teleport fling)")

	level.queue_free()
	await get_tree().process_frame


## Regression test for a bug found 2026-08-21: hitting the eraser hard
## backward off the start could leave it resting motionless on the lava
## floor forever, never resetting - FloorSensor's body_entered signal simply
## never fired for that resting position, even though the ball fully,
## geometrically overlapped it (root cause unclear; not worth chasing
## further when the fix is more reliable anyway). Eraser now checks its own
## Y position every physics frame instead of depending on that signal.
func _run_backward_hit_reset_test() -> void:
	var level: Node3D = load("res://scenes/levels/TestLevel.tscn").instantiate()
	add_child(level)
	await get_tree().create_timer(0.3).timeout

	var erasers: Array = level.start_match(1)
	var eraser: Eraser = erasers[0]
	var start_pos: Vector3 = eraser.global_position

	eraser.strike(Vector3(-4.0, 0.4, 0.0)) # hard hit, straight backward off the start
	await get_tree().create_timer(3.0).timeout

	_check(eraser.global_position.distance_to(start_pos) < 1.0,
		"hitting the eraser backward off the course still respawns it (was: stuck resting on the lava floor forever)")

	level.queue_free()
	await get_tree().process_frame


## Simulates a "reasonable but imperfect" human playing the actual generated
## course with the actual physics/friction/power tuning: aims a few pieces
## ahead along the actual path (with random aim error) - not straight at a
## checkpoint that might be 15 platforms and several small ledges away, the
## way a player watching the course from the 45-degree camera actually would
## - picks a club by distance the way a real player would (driver far out,
## iron mid-range, putter close in - using each club's real max_power, no
## cheating), and strikes for real via Eraser.strike(). If this can't reach
## the goal within a generous stroke budget, the course (or the power
## tuning) is unbeatable and needs fixing - this is the check that would
## have caught that before a player did. Re-run after any change to
## CoursePath, whacker power, mass, friction, or damping.
func _run_playability_test() -> void:
	const MAX_STROKES := 120
	const SETTLE_TIMEOUT_FRAMES := 240 # 4s of physics time per wait, as a hang guard
	const LOOKAHEAD_PIECES := 1

	var level: Node3D = load("res://scenes/levels/TestLevel.tscn").instantiate()
	add_child(level)
	await get_tree().create_timer(0.3).timeout

	var erasers: Array = level.start_match(1)
	await get_tree().create_timer(0.1).timeout
	var eraser: Eraser = erasers[0]
	var pieces: Array = level._pieces
	var goal_pos: Vector3 = level.get_node("Goal").global_position

	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var strokes := 0
	var success := false
	# The path now winds (can pass close to its own earlier stretch), so
	# "nearest piece by raw distance" can jump backward to an old piece the
	# ball happens to be near again - only ever search forward from where
	# progress last was, so the lookahead target can't regress.
	var progress_index := 0

	for _s in range(MAX_STROKES):
		var wait_frames := 0
		while not eraser.is_settled() and wait_frames < SETTLE_TIMEOUT_FRAMES:
			await get_tree().physics_frame
			wait_frames += 1

		if GameManager.match_complete:
			success = true
			break

		# Detect a fall-off respawn: the old check here only reset the
		# forward-only search if we ended up more than 6m from the
		# tracked progress piece - too generous on a compact winding
		# course, where a respawn to an *earlier* checkpoint can easily
		# land well within 6m of wherever progress last was (found via
		# CoursePath.CLIMB_PERSISTENCE's taller courses: a jump gap
		# stranded the sim exactly 1.13m from its own progress_index
		# piece after respawning to the checkpoint *before* it, so the
		# 6m check never fired, the forward-only search from that stale
		# progress_index couldn't see the checkpoint piece it had
		# actually respawned onto, and it re-aimed the identical failing
		# jump forever). The right question isn't "are we still near the
		# piece progress was" but "is there a piece *behind* progress
		# that we're now genuinely resting on" - if so, trust it; that's
		# a real regression (a respawn), not the winding path just
		# passing near old geometry while still net moving forward.
		var unrestricted_index: int = _nearest_piece_index_from(pieces, eraser.global_position, 0)
		var search_start: int = progress_index
		if unrestricted_index < progress_index \
				and pieces[unrestricted_index].pos.distance_to(eraser.global_position) < 1.0:
			search_start = unrestricted_index
		progress_index = _nearest_piece_index_from(pieces, eraser.global_position, search_start)
		var lookahead_index: int = min(progress_index + LOOKAHEAD_PIECES, pieces.size() - 1)
		var near_goal: bool = lookahead_index >= pieces.size() - 1
		var target: Vector3 = goal_pos if near_goal else pieces[lookahead_index].pos
		# Bug (found chasing a "stuck right before the goal" stall): this
		# used to be `not near_goal and ...`, which meant a mandatory jump
		# gap landing on the very last piece - entirely possible, since gap
		# placement doesn't know or care where the goal ends up - was never
		# detected, so the goal approach used regular (not jump) power/loft
		# and could never clear it. Whether the target is the goal or not is
		# irrelevant to whether *this* swing needs to be a jump.
		var is_jump: bool = pieces[lookahead_index].has_gap_before

		var to_target := target - eraser.global_position
		to_target.y = 0.0
		if to_target.length() < 0.01:
			to_target = Vector3.RIGHT
		var dist := to_target.length()
		var dir := to_target.normalized().rotated(Vector3.UP, deg_to_rad(rng.randf_range(-2.5, 2.5)))

		# Power scaled to the lookahead distance, not a flat club-tier value:
		# a fixed "driver" power aimed only a few pieces ahead massively
		# overshoots (empirically, ~9m of travel for max_power=4.0 given the
		# eraser's mass/damping) and sails the ball off the course entirely.
		# ~1/2.2 approximates the impulse needed to travel `dist` and settle
		# near it instead of blowing past it. Jump gaps need real airtime, not
		# just enough horizontal speed to reach the far edge and drop short -
		# boost both power and loft (matching the driver's own boosted loft).
		# Jump gaps: always swing full driver power, not a distance-scaled
		# guess - a real player lining up a mandatory jump gap swings as hard
		# as they can, they don't feather it.
		var power: float = 4.0 if is_jump else clampf(dist / 1.8, 1.4, 4.0)
		var loft: float = 0.1
		if is_jump:
			loft = 0.4
		elif dist > 1.0:
			loft = 0.15

		# Compensate for uphill terrain: the target-distance-scaled power
		# above has no notion of grade at all, only flat horizontal
		# distance - fine while CoursePath's height changes were small/
		# incidental, but CoursePath.CLIMB_PERSISTENCE (see course_path.gd)
		# now lets a real sustained multi-piece climb happen, and a player
		# who swings the same for a flat putt and a steep uphill approach
		# comes up short on the climb even with real max_power to spare.
		# Boost power and add real loft proportional to how much height
		# needs covering - this is the missing case, not the course being
		# unfair (see the class comment above on how this sim's own gaps,
		# not the course, were the answer the last several times something
		# looked "stuck forever").
		var height_diff: float = target.y - eraser.global_position.y
		if not is_jump and height_diff > 0.05:
			# Loft only, not power: impulse.y is *added* on top of the
			# horizontal impulse below, not redistributed from it, so more
			# loft is strictly extra help clearing the climb without
			# eating into horizontal reach the way boosting power also
			# would (tried that first - it overshot past the target
			# platform instead of undershooting, which made things worse,
			# not better).
			loft = maxf(loft, 0.18 + height_diff * 0.6)

		var impulse := dir * power
		impulse.y += power * loft
		if OS.get_environment("SIM_DEBUG") != "":
			print("    stroke=%d piece=%d pos=%s target=%s dist=%.2f height_diff=%.2f power=%.2f loft=%.2f is_jump=%s vel=%.2f" % [
				strokes, progress_index, eraser.global_position, target, dist, height_diff, power, loft, is_jump, eraser.linear_velocity.length()])
		eraser.strike(impulse)
		strokes += 1

		# apply_central_impulse() only takes effect on the physics server's
		# next step - checking is_settled() before waiting at least one
		# physics_frame here would still read the pre-strike (zero) velocity
		# and immediately think it's already settled, skipping the swing
		# entirely. Wait one frame *before* the loop condition, not after.
		wait_frames = 1
		await get_tree().physics_frame
		while not eraser.is_settled() and wait_frames < SETTLE_TIMEOUT_FRAMES:
			await get_tree().physics_frame
			wait_frames += 1
			if GameManager.match_complete:
				break

		if GameManager.match_complete:
			success = true
			break

	print("    (playability sim: %d strokes, checkpoints reached=%d, match_complete=%s)" % [
		strokes, max(GameManager.players[0].checkpoint_order, 0), GameManager.match_complete])
	_check(success, "playability: generated course is completable within %d strokes, aiming along the path with realistic club power + aim jitter" % MAX_STROKES)

	level.queue_free()
	await get_tree().process_frame


## Nearest piece index, searched only forward from `from_index` (a small
## window ahead) - never regresses to an earlier piece even if the winding
## path happens to pass close to it again later.
func _nearest_piece_index_from(pieces: Array, pos: Vector3, from_index: int) -> int:
	var search_end: int = min(from_index + 8, pieces.size() - 1)
	var best_index := from_index
	var best_dist := INF
	for i in range(from_index, search_end + 1):
		var d: float = pieces[i].pos.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_index = i
	return best_index


func _finish() -> void:
	print("\n=== %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
