extends Camera3D
class_name CameraRig
## Follows the active player's eraser from a fixed 45-degree downward angle,
## keeping the course feeling small and distant like a tabletop obstacle
## course. Middle-mouse-drag orbits the camera horizontally around the ball
## (the elevation angle stays fixed at `angle_deg` per spec).
## `target` is assigned at runtime by TurnManager, since the eraser(s) live
## in the level scene, not the player scene.

@export var distance: float = 2.0
@export var angle_deg: float = 45.0
@export var follow_speed: float = 4.0
@export var rotate_sensitivity_deg: float = 0.4 # degrees of orbit per pixel of middle-drag
@export var zoom_step: float = 0.2
@export var zoom_min: float = 0.8
@export var zoom_max: float = 6.0

var target: Node3D
var orbit_yaw_deg: float = 0.0
var _rotating: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_rotating = event.pressed
	elif event is InputEventMouseMotion and _rotating:
		orbit_yaw_deg = fmod(orbit_yaw_deg - event.relative.x * rotate_sensitivity_deg, 360.0)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		distance = clampf(distance - zoom_step, zoom_min, zoom_max)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		distance = clampf(distance + zoom_step, zoom_min, zoom_max)


func _process(delta: float) -> void:
	if target == null:
		return
	var desired_position := target.global_position + _offset()
	global_position = global_position.lerp(desired_position, clampf(follow_speed * delta, 0.0, 1.0))
	look_at(target.global_position, Vector3.UP)


func _offset() -> Vector3:
	var angle_rad := deg_to_rad(angle_deg)
	var base := Vector3(0.0, sin(angle_rad), cos(angle_rad)) * distance
	return base.rotated(Vector3.UP, deg_to_rad(orbit_yaw_deg))


## Jumps straight to the framing shot instead of lerping - used when the
## active player changes, since panning smoothly across a long course to a
## different player's ball would be slow and disorienting.
func snap_to_target() -> void:
	if target == null:
		return
	global_position = target.global_position + _offset()
	look_at(target.global_position, Vector3.UP)
