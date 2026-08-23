extends SceneTree
## Standalone reimplementation of just CoursePath.generate()'s height/slope
## random walk (turns/XZ path irrelevant to max height reached), so many
## CLIMB_PERSISTENCE candidates can be swept in one process instead of
## editing the real const + relaunching Godot per candidate.

const MIN_CENTER_Y := 0.4
const MAX_CENTER_Y := 4.0
const SLOPE_DEGREES_MIN := 5.0
const SLOPE_DEGREES_MAX := 38.0
const MAX_STEP_HEIGHT_ABS := 0.28
const STEP_DIST := 1.7 # representative average touching-distance across flavor pairs
const NUM_PIECES := 11

func _init() -> void:
	for persistence in [0.5, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85]:
		var heights := []
		for trial in range(20):
			heights.append(_max_height(persistence, 1000 + trial))
		var avg := 0.0
		for h in heights:
			avg += h
		avg /= heights.size()
		print("persistence=%.2f -> avg_max_y=%.2f (min=%.2f max=%.2f)" % [persistence, avg, heights.min(), heights.max()])
	quit()

func _max_height(persistence: float, seed_value: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var y := MIN_CENTER_Y
	var max_y := y
	var steps_since_change := 0
	var interval := rng.randi_range(2, 4)
	var climbing := true
	var angle := SLOPE_DEGREES_MIN
	for i in range(NUM_PIECES):
		steps_since_change += 1
		if steps_since_change >= interval:
			steps_since_change = 0
			interval = rng.randi_range(2, 4)
			angle = SLOPE_DEGREES_MIN + pow(rng.randf(), 1.3) * (SLOPE_DEGREES_MAX - SLOPE_DEGREES_MIN)
			climbing = (rng.randf() < persistence) == climbing
		var sign := 1.0 if climbing else -1.0
		var d := clampf(STEP_DIST * tan(deg_to_rad(angle)) * sign, -MAX_STEP_HEIGHT_ABS, MAX_STEP_HEIGHT_ABS)
		y = clampf(y + d, MIN_CENTER_Y, MAX_CENTER_Y)
		max_y = maxf(max_y, y)
	return max_y
