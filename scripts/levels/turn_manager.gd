extends Node
class_name TurnManager
## Hotseat multiplayer with real simultaneous balls: each player has their
## own Eraser instance that stays wherever it was left. This just watches
## the active player's ball settle after their stroke, hands the turn to the
## next unfinished player, and retargets the camera/club at whoever's ball
## is now active.

var erasers: Array = [] # Eraser nodes, indexed by player_index
var camera_rig: CameraRig
var club: ClubController
var was_moving: bool = false


func _physics_process(_delta: float) -> void:
	if erasers.is_empty() or GameManager.match_complete or GameManager.players.is_empty():
		return

	var active_eraser: Eraser = erasers[GameManager.active_player_index]
	var moving := not active_eraser.is_settled()

	if was_moving and not moving and GameManager.stroke_pending_turn_switch:
		GameManager.stroke_pending_turn_switch = false
		if GameManager.players.size() > 1:
			GameManager.advance_turn()

	was_moving = moving


func on_turn_changed(player_index: int) -> void:
	retarget_active(player_index)
	was_moving = false


func retarget_active(player_index: int) -> void:
	if player_index < 0 or player_index >= erasers.size():
		return
	var eraser: Eraser = erasers[player_index]
	if camera_rig:
		camera_rig.target = eraser
		camera_rig.snap_to_target()
	if club:
		club.eraser = eraser
