extends Node
## Autoload singleton ("GameManager"). Owns the hotseat match: one PlayerRun
## (and one real Eraser instance) per player, whose turn it is, and the
## shared level-layout facts (checkpoint count) other systems read.

signal checkpoint_reached(player_index: int, order: int)
signal stroke_taken(player_index: int, count: int)
signal player_finished(player_index: int)
signal turn_changed(player_index: int)
signal match_completed
signal match_reset

const MAX_PLAYERS := 4
const TOTAL_CHECKPOINTS := 3

## Distinct per-player ball colors.
const PLAYER_COLORS := [
	Color(0.925, 0.372, 0.639), # pink
	Color(0.2, 0.8, 0.85),      # teal
	Color(0.55, 0.85, 0.2),     # lime
	Color(0.95, 0.55, 0.15),    # orange
]

class PlayerRun:
	var player_name: String
	var stroke_count: int = 0
	var checkpoint_order: int = -1
	var respawn_transform: Transform3D = Transform3D.IDENTITY # last checkpoint (or start)
	var finished: bool = false

	func _init(p_name: String, start_transform: Transform3D) -> void:
		player_name = p_name
		respawn_transform = start_transform

var players: Array = [] # Array[PlayerRun]
var active_player_index: int = 0
var pending_player_count: int = 1 # set by the main menu before loading the level
var match_started: bool = false
var match_complete: bool = false

## True once the active player has dismissed the "your turn" popup - gates
## ClubController so a swing can't land during the buffer between turns.
var turn_ready: bool = false

## Set true by ClubController right after a strike; TurnManager watches for
## the eraser settling again while this is true, then advances the turn.
var stroke_pending_turn_switch: bool = false


func setup_players(count: int, start_transform: Transform3D) -> void:
	count = clampi(count, 1, MAX_PLAYERS)
	players.clear()
	for i in range(count):
		players.append(PlayerRun.new("Player %d" % (i + 1), start_transform))
	active_player_index = 0
	match_started = true
	match_complete = false
	turn_ready = false
	stroke_pending_turn_switch = false
	match_reset.emit()


func current_player() -> PlayerRun:
	return players[active_player_index]


func get_respawn_transform(player_index: int) -> Transform3D:
	return players[player_index].respawn_transform


func add_stroke() -> void:
	if match_complete or current_player().finished:
		return
	current_player().stroke_count += 1
	stroke_pending_turn_switch = true
	stroke_taken.emit(active_player_index, current_player().stroke_count)


func reach_checkpoint(player_index: int, order: int, transform: Transform3D) -> void:
	var p: PlayerRun = players[player_index]
	if match_complete or p.finished or order <= p.checkpoint_order:
		return
	p.checkpoint_order = order
	p.respawn_transform = transform
	checkpoint_reached.emit(player_index, order)


func complete_player(player_index: int) -> void:
	var p: PlayerRun = players[player_index]
	if p.finished or match_complete:
		return
	p.finished = true
	player_finished.emit(player_index)
	if _all_finished():
		match_complete = true
		match_completed.emit()
	elif player_index == active_player_index:
		stroke_pending_turn_switch = false
		advance_turn()


## Moves to the next player who hasn't finished yet. No-op (turn stays put)
## if everyone else is done or there's only one player.
func advance_turn() -> void:
	if match_complete or players.size() <= 1:
		return
	var start_index := active_player_index
	var idx := active_player_index
	for _i in range(players.size()):
		idx = (idx + 1) % players.size()
		if not players[idx].finished:
			active_player_index = idx
			break
	stroke_pending_turn_switch = false
	turn_ready = false
	if active_player_index != start_index:
		turn_changed.emit(active_player_index)


func _all_finished() -> bool:
	for p in players:
		if not p.finished:
			return false
	return true
