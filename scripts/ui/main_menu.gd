extends Control
class_name MainMenu
## Configure and launch a hotseat match.

@onready var count_label: Label = $Center/VBox/PlayerCountRow/CountLabel

var player_count: int = 1


func _ready() -> void:
	_refresh()


func _on_minus_pressed() -> void:
	player_count = max(1, player_count - 1)
	_refresh()


func _on_plus_pressed() -> void:
	player_count = min(GameManager.MAX_PLAYERS, player_count + 1)
	_refresh()


func _refresh() -> void:
	count_label.text = str(player_count)


func _on_start_pressed() -> void:
	GameManager.pending_player_count = player_count
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
