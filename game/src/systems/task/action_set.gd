class_name ActionSet
extends TaskBase

## Actions where order does NOT matter. Every action must be done, but any
## remaining action whose prerequisites are met may be worked on.

@export var actions: Array = []

func _ready() -> void:
	for a in actions:
		if a is Action:
			a.assign_owner(null, self)

func current_action() -> Action:
	# Keep the in-flight action until it finishes, then pick any pending one.
	for a in actions:
		if a is Action and a.is_active():
			return a as Action
	for a in actions:
		if a is Action and a.is_pending():
			return a as Action
	return null

func available_actions() -> Array:
	var out: Array = []
	for a in actions:
		if a is Action and a.is_pending() and a.check_begin() == TaskBase.BeginResult.OK:
			out.append(a)
	return out

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
