extends Node3D
class_name LevelController
## Builds the procedural course (see CoursePath), starts a hotseat match for
## GameManager.pending_player_count players - one real, distinctly colored
## Eraser instance per player, all spawned at the start with a brief
## collision guard so they don't shove each other apart - and wires the
## Player rig / TurnManager to whoever's turn it is.
## IMPORTANT: this node must come BEFORE StartMarker/Checkpoint1-3/Goal in
## the scene tree, since it repositions them in _enter_tree() - which runs
## top-down (parent/earlier-sibling first) - before those nodes' own _ready()
## (which runs bottom-up) reads their position.

const ERASER_SCENE := preload("res://scenes/objects/Eraser.tscn")

@export var course_root_path: NodePath
@export var start_marker_path: NodePath
@export var checkpoint_paths: Array[NodePath] = []
@export var goal_path: NodePath
@export var erasers_root_path: NodePath
@export var player_path: NodePath
@export var turn_manager_path: NodePath

var _pieces: Array = []
var _checkpoint_indices: Array = []


func _enter_tree() -> void:
	_pieces = CoursePath.generate()
	_checkpoint_indices = CoursePath.pick_checkpoint_indices(_pieces)
	_build_course_geometry()
	_position_markers()


func _ready() -> void:
	start_match(GameManager.pending_player_count)


## Starts (or restarts, for a rematch) a match for `player_count` players:
## resets GameManager, spawns one distinctly colored Eraser per player at the
## start with a spawn-collision-guard, and (re)wires the Player rig /
## TurnManager to the newly created erasers. Public and reusable - in
## particular the test suite calls this directly instead of duplicating the
## spawn logic, which is what real gameplay always goes through too, so
## there's only one code path to keep correct.
func start_match(player_count: int) -> Array:
	var start_marker: Marker3D = get_node(start_marker_path)
	var player: Node3D = get_node(player_path)
	var turn_manager: TurnManager = get_node(turn_manager_path)
	var erasers_root: Node3D = get_node(erasers_root_path)

	GameManager.setup_players(player_count, start_marker.global_transform)

	for child in erasers_root.get_children():
		child.queue_free()

	var erasers: Array = []
	for i in range(GameManager.players.size()):
		var eraser: Eraser = ERASER_SCENE.instantiate()
		erasers_root.add_child(eraser)
		eraser.player_index = i
		eraser.teleport_to(start_marker.global_transform)
		eraser.begin_spawn_guard(start_marker.global_position)
		var mesh_instance: MeshInstance3D = eraser.get_node("Mesh")
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GameManager.PLAYER_COLORS[i % GameManager.PLAYER_COLORS.size()]
		mat.roughness = 0.85
		mesh_instance.material_override = mat
		erasers.append(eraser)

	var camera_rig: CameraRig = player.get_node("Camera")
	var club: ClubController = player.get_node("ClubController")
	turn_manager.erasers = erasers
	turn_manager.camera_rig = camera_rig
	turn_manager.club = club
	turn_manager.retarget_active(0)
	camera_rig.snap_to_target()

	if not GameManager.turn_changed.is_connected(turn_manager.on_turn_changed):
		GameManager.turn_changed.connect(turn_manager.on_turn_changed)

	return erasers


const PILLAR_COLORS := [
	Color(0.75, 0.15, 0.15), Color(0.2, 0.45, 0.75), Color(0.85, 0.75, 0.2), Color(0.3, 0.6, 0.3),
]


func _build_course_geometry() -> void:
	var course_root: Node3D = get_node(course_root_path)
	for child in course_root.get_children():
		child.queue_free()

	var shape_cache: Dictionary = {}
	var mesh_cache: Dictionary = {}
	for piece in _pieces:
		var key: String = "%s_%s_%s" % [piece.size.x, piece.size.y, piece.size.z]
		if not shape_cache.has(key):
			var shape := BoxShape3D.new()
			shape.size = piece.size
			var mesh := BoxMesh.new()
			mesh.size = piece.size
			shape_cache[key] = shape
			mesh_cache[key] = mesh

		# The StaticBody3D (and its collision shape) stays perfectly
		# axis-aligned at piece.pos - that's the tested, guaranteed-walkable
		# footprint. Only the visual mesh gets the cosmetic tilt, as a child
		# with its own small rotation, so the pile *looks* like a kid's
		# precarious stack of found objects without actually being one.
		var body := StaticBody3D.new()
		body.name = piece.piece_name
		body.position = piece.pos

		var collision := CollisionShape3D.new()
		collision.shape = shape_cache[key]
		body.add_child(collision)

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh_cache[key]
		mesh_instance.rotation_degrees = piece.visual_tilt_deg
		# Second safety margin on top of the small tilt angles themselves:
		# shrunk a hair so a rotated corner still can't reach the touching
		# neighbor's zero-gap seam.
		mesh_instance.scale = Vector3.ONE * 0.93
		var mat := StandardMaterial3D.new()
		mat.albedo_color = piece.color
		mesh_instance.material_override = mat
		body.add_child(mesh_instance)

		course_root.add_child(body)

		_add_pillar(course_root, piece)

	for i in range(1, _pieces.size()):
		if not _pieces[i].has_gap_before: # a real jump gap - no bridge, no cheating it
			_add_bridge(course_root, _pieces[i - 1], _pieces[i])


## A thin decorative prop (broom handle / ruler / whatever) running from a
## piece's underside down to the floor, so elevated pieces read as propped
## up rather than floating. Purely visual - no collision, so it can never
## block the ball.
func _add_pillar(course_root: Node3D, piece) -> void:
	var bottom_y: float = piece.pos.y - piece.size.y * 0.5
	if bottom_y < 0.5:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.035
	mesh.height = bottom_y
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(piece.pos.x, bottom_y * 0.5, piece.pos.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PILLAR_COLORS[piece.piece_name.hash() % PILLAR_COLORS.size()]
	mesh_instance.material_override = mat
	course_root.add_child(mesh_instance)


const BRIDGE_WIDTH := 0.5
## Negative: the plank is kept slightly *shorter* than the exact
## touch-to-touch distance, so it can never poke into either block's volume
## - "do not overlap meshes on the course" takes priority over the plank
## visually flush-resting on each block; a hairline seam at the ends is the
## trade-off.
const BRIDGE_INSET := 0.1


## A rotated plank laid across two touching (never overlapping - see
## CoursePath) blocks. The blocks are the non-overlapping "building block"
## pile; this plank, resting a little onto the top of each one, is the
## actual guaranteed-walkable surface across the seam and whatever angle it
## sits at - the "winding path of bridges" a kid would lay down between
## stacked household objects.
##
## Built between the two pieces' *top-surface* points, not their centers:
## with real 5-45' slopes now common, center-to-center Y differs from
## top-to-top Y whenever the two pieces are different thicknesses (e.g. a
## thin Ruler next to a chunky ToyBlock), so a center-based plank could tilt
## at the wrong angle and dip below the taller piece's actual top - clipping
## into its side instead of resting on it.
func _add_bridge(course_root: Node3D, piece_a, piece_b) -> void:
	var top_a: Vector3 = Vector3(piece_a.pos.x, piece_a.top_y(), piece_a.pos.z)
	var top_b: Vector3 = Vector3(piece_b.pos.x, piece_b.top_y(), piece_b.pos.z)
	var to_b: Vector3 = top_b - top_a
	var length: float = to_b.length() - BRIDGE_INSET
	if length < 0.05:
		return

	var mesh := BoxMesh.new()
	mesh.size = Vector3(BRIDGE_WIDTH, 0.05, length)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.4, 0.28)
	mesh_instance.material_override = mat

	var body := StaticBody3D.new()
	body.name = "Bridge_%s_%s" % [piece_a.piece_name, piece_b.piece_name]
	var mid: Vector3 = (top_a + top_b) * 0.5
	body.position = mid - Vector3(0, 0.018, 0)
	body.basis = Basis.looking_at(to_b.normalized(), Vector3.UP)

	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.add_child(mesh_instance)
	course_root.add_child(body)


## Uses local `position`, not `global_position`: these nodes are direct
## children of this one and haven't entered the tree yet at _enter_tree()
## time, so `global_position` would fail a not-in-tree check (and did, until
## the automated tests caught it). Local position relative to this node -
## the level root, which always sits at the world origin - is equivalent
## and doesn't require tree membership.
func _position_markers() -> void:
	var start_marker: Marker3D = get_node(start_marker_path)
	var goal_node: GoalArea = get_node(goal_path)

	var start_piece = _pieces[0]
	start_marker.position = start_piece.pos + Vector3(0, start_piece.size.y * 0.5 + 0.08, 0)

	for i in range(checkpoint_paths.size()):
		var checkpoint_node: Checkpoint = get_node(checkpoint_paths[i])
		var piece = _pieces[_checkpoint_indices[i]]
		checkpoint_node.position = piece.pos + Vector3(0, piece.size.y * 0.5, 0)

	var goal_piece = _pieces[_pieces.size() - 1]
	goal_node.position = goal_piece.pos + Vector3(0, goal_piece.size.y * 0.5, 0)
