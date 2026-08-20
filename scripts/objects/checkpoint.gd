extends Area3D
class_name Checkpoint
## One of the 3 mandatory course checkpoints. Registers its respawn point with
## GameManager on ready, and advances the run when the eraser passes through.

@export var checkpoint_order: int = 0

@onready var respawn_marker: Marker3D = $RespawnMarker


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Eraser and body.player_index >= 0:
		GameManager.reach_checkpoint(body.player_index, checkpoint_order, respawn_marker.global_transform)
