class_name Sequence
extends TaskBase

## Actions that MUST be performed in order. Only the first incomplete action
## may be begun at any time.

@export var actions: Array = []

func _ready() -> void:
	for a in actions:
		if a is Action:
			a.assign_owner(null, self)

func enforces_order() -> bool:
	return true

func current_action() -> Action:
	# The current step is the first action that is not finished; it may be
	# PENDING (not started) or ACTIVE (being held). Failed aborts the stage.
	for a in actions:
		if a is Action:
			if a.is_done():
				continue
			if a.is_failed():
				return null
			return a as Action
	return null

func is_done() -> bool:
	for a in actions:
		if a is Action and not a.is_done():
			return false
	return true

func is_failed() -> bool:
	for a in actions:
		if a is Action and a.is_failed():
			return true
	return false

func progress() -> float:
	if actions.is_empty():
		return 1.0
	var total := 0.0
	for a in actions:
		if a is Action:
			total += 1.0 if a.is_done() else a.progress()
	return clampf(total / maxf(actions.size(), 1), 0.0, 1.0)

func active_text() -> String:
	var cur := current_action()
	if cur != null:
		return cur.active_text()
	return display_name

func cancel_current(failed: bool = true) -> void:
	var cur := current_action()
	if cur != null:
		cur.cancel(failed)
