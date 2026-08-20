extends Area3D
class_name GoalArea
## Marks the end of the course. Completes the level when the eraser enters.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Eraser and body.player_index >= 0:
		GameManager.complete_player(body.player_index)
