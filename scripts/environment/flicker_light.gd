extends OmniLight3D
## Small CRT-glow flicker for the television light. Purely cosmetic.

@export var base_energy: float = 2.0
@export var flicker_amount: float = 0.4
@export var flicker_speed: float = 18.0


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	light_energy = base_energy + sin(t * flicker_speed) * flicker_amount * 0.5 + sin(t * flicker_speed * 2.7) * flicker_amount * 0.5
