extends Area3D
class_name FloorSensor
## Covers the house floor beneath the course. Solid course pieces block the
## eraser from ever reaching this area while it's still on the path, so any
## overlap means the eraser fell off the course and touched the floor -
## per spec, that resets it to the last checkpoint (or the start).


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Eraser:
		body.respawn()
