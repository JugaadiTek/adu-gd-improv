extends Node3D
class_name ClubController
## Swing a stationery "whacker" at the eraser to strike it. The whacker head
## tracks the mouse (projected onto the ground plane at ball height); it only
## makes contact while the left mouse button is held, and only counts as a
## strike if it crosses close to the eraser fast enough. Holding Shift softens
## the hit into a flat "slide" (no loft) instead of a lofted "whack". Press
## 1/2/3 to switch whacker (Pencil="Putter" / Pen="5 Iron" / Toothbrush=
## "Driver") - each swings like its golf namesake: different power, loft, and
## swing speed needed to trigger a hit.

@export var camera_path: NodePath
@export var hit_radius: float = 0.35
@export var min_swing_speed: float = 1.5
@export var max_swing_speed: float = 8.0
@export var slide_power_multiplier: float = 0.6
@export var strike_cooldown: float = 0.35

var camera: Camera3D
var eraser: Eraser
var previous_mouse_world: Vector3
var has_previous: bool = false
var cooldown_timer: float = 0.0
var whacker_index: int = 0
var current_whacker_height: float = 0.7

@onready var whacker: MeshInstance3D = $Whacker

## Golf-club-inspired profiles, vertical lift explicitly tiered: putter
## (little to none, for precise control/slides along the ground), 5 iron
## (medium), driver (heavy - needed to clear the course's jump gaps too -
## see CoursePath) - each also needing a faster swing to trigger than the
## last, a mishit at driver speed just doesn't connect.
const WHACKERS := [
	{"name": "Pencil", "role": "Putter", "color": Color(0.95, 0.8, 0.1), "radius": 0.015, "height": 0.7,
		"max_power": 2.4, "loft_factor": 0.02, "min_speed_mult": 0.75},
	{"name": "Pen", "role": "5 Iron", "color": Color(0.1, 0.15, 0.5), "radius": 0.02, "height": 0.65,
		"max_power": 3.2, "loft_factor": 0.18, "min_speed_mult": 1.0},
	{"name": "Toothbrush", "role": "Driver", "color": Color(0.9, 0.9, 0.95), "radius": 0.025, "height": 0.55,
		"max_power": 4.0, "loft_factor": 0.34, "min_speed_mult": 1.3},
]

## Real low-poly, textured models (see ClaudeNotes/collab/2026/08_008.md),
## one per WHACKERS entry, keyed by "name" so the mapping is explicit rather
## than relying on array order. Each is normalized to an exact 1x1x1
## bounding box with its business end (pencil point / pen nib / toothbrush
## head) at local Y=-0.5 and its handle/cap end at Y=+0.5 - so scaling by
## Vector3(radius*2, height, radius*2) reproduces the same width/height the
## old CylinderMesh(top_radius, bottom_radius, height) used, and the contact
## end still lands exactly at the whacker's origin the way
## _physics_process()'s `whacker.global_position = current + Vector3(0,
## height*0.5, 0)` expects.
const WHACKER_MODELS := {
	"Pencil": preload("res://assets/models/Pencil.glb"),
	"Pen": preload("res://assets/models/Pen.glb"),
	"Toothbrush": preload("res://assets/models/Toothbrush.glb"),
}
var _whacker_mesh_cache: Dictionary = {}


func _ready() -> void:
	camera = get_node(camera_path)
	_apply_whacker(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			_apply_whacker(0)
		elif event.keycode == KEY_2:
			_apply_whacker(1)
		elif event.keycode == KEY_3:
			_apply_whacker(2)


func _apply_whacker(index: int) -> void:
	whacker_index = index
	var cfg: Dictionary = WHACKERS[index]
	var whacker_name: String = cfg["name"]
	var mesh: Mesh = ModelLib.get_mesh(WHACKER_MODELS.get(whacker_name), _whacker_mesh_cache, whacker_name)
	if mesh:
		whacker.mesh = mesh
		# Model is normalized to an exact 1x1x1 box (tip at Y=-0.5, handle
		# at Y=+0.5) - this reproduces the same width/height the old
		# CylinderMesh(radius, height) used. No material_override: let the
		# model's own baked texture show (see _update_opacity - opacity is
		# now done via GeometryInstance3D.transparency instead of an
		# override material, so it doesn't blot out the real texture).
		whacker.scale = Vector3(cfg["radius"] * 2.0, cfg["height"], cfg["radius"] * 2.0)
		whacker.material_override = null
	else:
		# Fallback if a model is ever missing.
		var fallback := CylinderMesh.new()
		fallback.top_radius = cfg["radius"]
		fallback.bottom_radius = cfg["radius"]
		fallback.height = cfg["height"]
		whacker.mesh = fallback
		whacker.scale = Vector3.ONE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cfg["color"]
		whacker.material_override = mat
	current_whacker_height = cfg["height"]
	_update_opacity()


func _get_mouse_world_point() -> Vector3:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var ground_plane := Plane(Vector3.UP, eraser.global_position.y)
	var hit = ground_plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return eraser.global_position
	return hit


## Ghost-when-idle / solid-when-swinging feedback, via GeometryInstance3D's
## own transparency (a blend applied on top of whatever material is on the
## mesh) instead of editing a material's alpha - the real models keep their
## baked textures either way, unlike the old approach of forcing a single
## flat-color override material just to get an alpha channel to animate.
func _update_opacity() -> void:
	whacker.transparency = 0.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0.5


func _physics_process(delta: float) -> void:
	if eraser == null or camera == null:
		return
	if cooldown_timer > 0.0:
		cooldown_timer -= delta

	var current := _get_mouse_world_point()
	whacker.global_position = current + Vector3(0.0, current_whacker_height * 0.5, 0.0)
	_update_opacity()

	if not has_previous:
		previous_mouse_world = current
		has_previous = true
		return

	var swing_vel := (current - previous_mouse_world) / delta
	swing_vel.y = 0.0
	previous_mouse_world = current

	var cfg: Dictionary = WHACKERS[whacker_index]
	var dist := current.distance_to(eraser.global_position)
	var speed := swing_vel.length()
	var required_speed: float = min_swing_speed * float(cfg["min_speed_mult"])
	var button_held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if should_strike(dist, speed, hit_radius, required_speed, button_held, cooldown_timer > 0.0,
			eraser.is_settled(), GameManager.turn_ready):
		_strike(swing_vel, speed, cfg)


## Pure decision logic (no Input/viewport/autoload access) so it can be unit
## tested without a live mouse. turn_ready comes from GameManager: false
## during the "your turn" popup buffer between players.
static func should_strike(distance: float, speed: float, radius: float, required_speed: float,
		button_held: bool, on_cooldown: bool, is_settled: bool, turn_ready: bool) -> bool:
	return turn_ready and button_held and is_settled and not on_cooldown \
		and distance <= radius and speed >= required_speed


func _strike(swing_vel: Vector3, speed: float, cfg: Dictionary) -> void:
	cooldown_timer = strike_cooldown
	var dir := swing_vel.normalized()
	var max_power: float = cfg["max_power"]
	var loft: float = cfg["loft_factor"]
	var power := clampf(speed / max_swing_speed, 0.0, 1.0) * max_power
	var is_slide := Input.is_key_pressed(KEY_SHIFT)
	var impulse := dir * power
	if is_slide:
		impulse = dir * power * slide_power_multiplier
	else:
		impulse.y += power * loft
	eraser.strike(impulse)
