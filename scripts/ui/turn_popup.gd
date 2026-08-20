extends CanvasLayer
class_name TurnPopup
## A deliberate buffer between turns: dims the screen and blocks swings
## (via GameManager.turn_ready) until the incoming player clicks "Start Turn".

@onready var dim: ColorRect = $Dim
@onready var label: Label = $Center/Panel/VBox/Label
@onready var button: Button = $Center/Panel/VBox/StartButton


func _ready() -> void:
	GameManager.turn_changed.connect(_on_turn_changed)
	button.pressed.connect(_on_start_pressed)
	if not GameManager.players.is_empty() and not GameManager.turn_ready:
		_show_for(GameManager.active_player_index)
	else:
		_hide()


func _on_turn_changed(player_index: int) -> void:
	_show_for(player_index)


func _show_for(player_index: int) -> void:
	var p = GameManager.players[player_index]
	label.text = "%s's turn" % p.player_name
	dim.visible = true
	$Center.visible = true


func _hide() -> void:
	dim.visible = false
	$Center.visible = false


func _on_start_pressed() -> void:
	_hide()
	GameManager.turn_ready = true
