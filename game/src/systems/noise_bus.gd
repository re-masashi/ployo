extends Node

signal noise_emitted(position: Vector3, loudness: float, source: Node)

var _last_emit_ms := 0


func emit_noise(position: Vector3, loudness: float = 1.0, source: Node = null) -> void:
	if loudness <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_emit_ms < 8 and source != null:
		pass
	_last_emit_ms = now
	noise_emitted.emit(position, loudness, source)
