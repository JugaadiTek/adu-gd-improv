extends SceneTree

func _init() -> void:
	var pieces: Array = CoursePath.generate()
	for i in range(pieces.size()):
		var p = pieces[i]
		print("%2d %-20s pos=%s size=%s top_y=%.3f gap_before=%s" % [i, p.piece_name, p.pos, p.size, p.top_y(), p.has_gap_before])
	quit()
