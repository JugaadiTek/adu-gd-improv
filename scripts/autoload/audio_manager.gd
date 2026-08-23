extends Node
## Autoload singleton ("AudioManager"). Plays short, procedurally synthesized
## SFX (sine-wave blips, generated in code - no external audio assets) for
## hits/checkpoints/turns/finishes. Hooked to GameManager's signals so no
## other script needs to know audio exists.
##
## NOTE: this is SFX only. Background music lives separately -
## MainMenu.tscn has its own AudioStreamPlayer for the main-menu theme (see
## audio/music/README.md for the track's license/source) - in-course music
## is still out of scope.

const SAMPLE_RATE := 22050
const POOL_SIZE := 4

var _players: Array = []
var _pool_index := 0
var _stream_cache: Dictionary = {}


func _ready() -> void:
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	GameManager.stroke_taken.connect(func(_i, _c): _play("hit"))
	GameManager.checkpoint_reached.connect(func(_i, _o): _play("checkpoint"))
	GameManager.player_finished.connect(func(_i): _play("finish"))
	GameManager.turn_changed.connect(func(_i): _play("turn"))
	GameManager.match_completed.connect(func(): _play("match_complete"))


func _play(kind: String) -> void:
	var stream := _get_stream(kind)
	var p: AudioStreamPlayer = _players[_pool_index]
	_pool_index = (_pool_index + 1) % _players.size()
	p.stream = stream
	p.play()


func _get_stream(kind: String) -> AudioStreamWAV:
	if _stream_cache.has(kind):
		return _stream_cache[kind]
	var stream: AudioStreamWAV
	match kind:
		"hit":
			stream = _tone([440.0], 0.07, 0.5)
		"checkpoint":
			stream = _tone([523.25, 659.25, 783.99], 0.1, 0.5)
		"finish":
			stream = _tone([659.25, 987.77], 0.16, 0.6)
		"turn":
			stream = _tone([330.0], 0.05, 0.3)
		"match_complete":
			stream = _tone([523.25, 659.25, 783.99, 1046.5], 0.13, 0.6)
		_:
			stream = _tone([440.0], 0.07, 0.5)
	_stream_cache[kind] = stream
	return stream


## Builds a short WAV of one or more sequential sine-wave notes with a linear
## fade-out envelope (avoids clicks). 16-bit mono PCM.
func _tone(freqs: Array, note_duration: float, volume: float) -> AudioStreamWAV:
	var data := PackedByteArray()
	for freq in freqs:
		var sample_count := int(SAMPLE_RATE * note_duration)
		for s in range(sample_count):
			var t := float(s) / SAMPLE_RATE
			var envelope := 1.0 - (float(s) / sample_count)
			var sample := sin(TAU * float(freq) * t) * volume * envelope
			var v := int(clampf(sample, -1.0, 1.0) * 32767.0)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
