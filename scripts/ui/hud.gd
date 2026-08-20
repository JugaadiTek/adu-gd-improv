extends CanvasLayer
class_name HUD
## Hotseat-aware HUD: whose turn it is, their strokes/checkpoint progress,
## and a final ranked summary when the match ends.

@onready var turn_label: Label = $Margin/VBox/TurnLabel
@onready var stroke_label: Label = $Margin/VBox/StrokeLabel
@onready var checkpoint_label: Label = $Margin/VBox/CheckpointLabel
@onready var message_label: Label = $CenterMessage


func _ready() -> void:
	GameManager.stroke_taken.connect(_on_stroke_taken)
	GameManager.checkpoint_reached.connect(_on_checkpoint_reached)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.player_finished.connect(_on_player_finished)
	GameManager.match_completed.connect(_on_match_completed)
	GameManager.match_reset.connect(_on_match_reset)
	_refresh()


func _refresh() -> void:
	if GameManager.players.is_empty():
		return
	var p = GameManager.current_player()
	turn_label.text = "%s's turn" % p.player_name
	stroke_label.text = "Strokes: %d" % p.stroke_count
	checkpoint_label.text = "Checkpoint: %d / %d" % [max(p.checkpoint_order, 0), GameManager.TOTAL_CHECKPOINTS]
	message_label.text = ""


func _on_stroke_taken(player_index: int, count: int) -> void:
	if player_index == GameManager.active_player_index:
		stroke_label.text = "Strokes: %d" % count


func _on_checkpoint_reached(player_index: int, order: int) -> void:
	if player_index == GameManager.active_player_index:
		checkpoint_label.text = "Checkpoint: %d / %d" % [order, GameManager.TOTAL_CHECKPOINTS]


func _on_turn_changed(_player_index: int) -> void:
	_refresh()


func _on_player_finished(player_index: int) -> void:
	var p = GameManager.players[player_index]
	message_label.text = "%s finished in %d strokes!" % [p.player_name, p.stroke_count]


func _on_match_completed() -> void:
	var lines := ["COURSE COMPLETE!"]
	var ranked: Array = GameManager.players.duplicate()
	ranked.sort_custom(func(a, b): return a.stroke_count < b.stroke_count)
	for i in range(ranked.size()):
		lines.append("%d. %s - %d strokes" % [i + 1, ranked[i].player_name, ranked[i].stroke_count])
	message_label.text = "\n".join(lines)


func _on_match_reset() -> void:
	_refresh()
