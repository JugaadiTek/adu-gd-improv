extends RigidBody3D
class_name Eraser
## One player's ball. High-friction physics material is set on the node (see
## Eraser.tscn); this script handles respawn-on-fall-off, the "settled"
## check so the club can't strike it while it's still rolling, and a
## spawn-collision-guard so multiple players' erasers spawned stacked at the
## same start point don't explosively shove each other apart.

const COURSE_LAYER := 1
const ERASER_LAYER := 2

## The floor is lava (see lava_floor.gd / FloorSensor): any resting height
## at or below this counts as "touched it", respawning to the last
## checkpoint. Checked directly here every physics frame instead of relying
## solely on FloorSensor's Area3D body_entered signal - that signal was
## found to sometimes never fire at all even for a ball resting stationary
## and fully geometrically overlapping the sensor (reproduced hitting the
## eraser hard backward off the course), so this is the actually-reliable
## mechanism; FloorSensor is kept as a secondary/defense-in-depth check.
## The lava floor's top sits at y=0, a resting ball on it settles around
## y=0.06-0.08. The lowest legitimate on-course height is ~0.3 (a jump-gap
## trajectory can dip well below its takeoff/landing platforms mid-arc) so
## this is set close to actual floor contact rather than partway up - it
## should catch "touched the lava", not "flew a bit low over a gap".
@export var lava_y_threshold: float = 0.15
@export var settle_linear_speed: float = 0.15
@export var settle_angular_speed: float = 0.15
@export var spawn_guard_distance: float = 0.3

## Which GameManager player this ball belongs to. Set by LevelController.
var player_index: int = -1

var _spawn_guard_active: bool = false
var _spawn_guard_origin: Vector3
var _teleporting: bool = false


func _physics_process(_delta: float) -> void:
	if not _teleporting and global_position.y < lava_y_threshold:
		respawn()

	if _spawn_guard_active and global_position.distance_to(_spawn_guard_origin) > spawn_guard_distance:
		_end_spawn_guard()


## False while a teleport_to() is mid-flight, even though velocity reads
## zero during that window (found via the playability test: polling
## is_settled() right after a respawn could see the zeroed velocity from
## teleport_to() one physics frame before `freeze` actually clears, and a
## strike landing in that gap was silently dropped by the physics server -
## a real bug, not just a test artifact, since ClubController/TurnManager
## poll is_settled() the same way).
func is_settled() -> bool:
	if _teleporting:
		return false
	return linear_velocity.length() < settle_linear_speed \
		and angular_velocity.length() < settle_angular_speed


## Call right after placing this ball at the shared start point: disables
## eraser-vs-eraser collision (course collision stays on) until this ball
## has physically moved away from that spot, so simultaneous spawns don't
## overlap-resolve into each other at full force.
func begin_spawn_guard(origin: Vector3) -> void:
	_spawn_guard_active = true
	_spawn_guard_origin = origin
	collision_layer = 0
	collision_mask = COURSE_LAYER


func _end_spawn_guard() -> void:
	_spawn_guard_active = false
	collision_layer = ERASER_LAYER
	collision_mask = COURSE_LAYER | ERASER_LAYER


## Snap back to the last checkpoint (or the start, if none reached yet).
func respawn() -> void:
	if player_index < 0:
		return
	teleport_to(GameManager.get_respawn_transform(player_index))


## Safely reposition the eraser outside of normal rolling physics. Freezes
## for one physics frame around the teleport: with continuous_cd on, an
## instant reposition of an already-moving RigidBody3D gets read as a
## high-speed sweep and Jolt launches it on landing - freezing turns the body
## kinematic for that one frame so no swept collision is resolved.
func teleport_to(t: Transform3D) -> void:
	_teleporting = true
	freeze = true
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	await get_tree().physics_frame
	freeze = false
	sleeping = false
	_teleporting = false


## Apply a swing/slide impulse and count it as a stroke.
func strike(impulse: Vector3) -> void:
	sleeping = false
	apply_central_impulse(impulse)
	GameManager.add_stroke()
