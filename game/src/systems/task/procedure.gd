class_name Procedure
extends TaskBase

## A multi-stage repair/task. Each stage is a Sequence (ordered) or an
## ActionSet (order-free). Stages unlock one after another.
##
## Example engine repair:
##   [[close_coolant_valve, close_fuel_valve, trip_breaker],   # sequential
##    [open_engine],                                            # sequential
##    [clean, add_oil, add_fuel],                               # set (any order)
##    [close_engine],                                           # sequential
##    [open_coolant_valve, open_breaker],                       # set
##    [start_engine]]                                           # sequential

@export var stages: Array = []

var _actions_by_id: Dictionary = {}

func _ready() -> void:
	_reindex()

func _reindex() -> void:
	_actions_by_id.clear()
	for stage in stages:
		if not (stage is Sequence or stage is ActionSet):
			continue
		var stage_actions: Array = stage.actions
		for a in stage_actions:
			if a is Action and a.id != "":
				_actions_by_id[a.id] = a
				a.assign_owner(self, stage)
				if not a.succeeded.is_connected(_on_action_done):
					a.succeeded.connect(_on_action_done)
				if not a.failed.is_connected(_on_action_failed):
					a.failed.connect(_on_action_failed)

## Look an action up by its id.
func get_action(id: String) -> Action:
	return _actions_by_id.get(id)

## True when every action id in `requires` is done.
func guards_met_for(action_id: String) -> bool:
	var action := get_action(action_id)
	if action == null:
		return true
	for req in action.requires:
		var r := get_action(req)
		if r == null or not r.is_done():
			return false
	return true

## Index of the first stage that isn't done, or stages.size() when complete.
func current_stage_index() -> int:
	for i in range(stages.size()):
		var stage := stages[i] as TaskBase
		if stage != null and not stage.is_done():
			return i
	return stages.size()

## The action the player should be working on right now, or null if complete.
func current_action() -> Action:
	var idx := current_stage_index()
	if idx >= stages.size():
		return null
	var stage := stages[idx] as TaskBase
	if stage != null and stage.has_method("current_action"):
		return stage.current_action()
	return null

## Attempt to begin the given action. Handles blocking / accidents.
func begin_action(action_id: String) -> BeginResult:
	var action := get_action(action_id)
	if action == null:
		return BeginResult.BLOCKED
	return action.begin_checked()

## Call when an action completes; advances the stage/procedure automatically.
func _on_action_done(action: Action) -> void:
	if state == State.FAILED:
		return
	if all_done():
		complete()
	else:
		## The next action becomes active automatically; nothing else needed.
		pass

## Call when an action fails outright (accident or cancelled-with-accident).
func _on_action_failed(action: Action, reason: String) -> void:
	if state == State.DONE:
		return
	if action.accident_on_fail or reason == action.accident_reason:
		_on_accident(reason)
	else:
		## Non-accident failure: let the player retry by resetting.
		action.reset()

## Trigger a catastrophic accident (e.g. engine explodes, shock).
func _on_accident(reason: String) -> void:
	if state == State.DONE or state == State.FAILED:
		return
	state = State.FAILED
	state_changed.emit(self, State.PENDING, State.FAILED)
	failed.emit(self, reason)
	print("[Procedure] ACCIDENT: ", reason)

func all_done() -> bool:
	for stage in stages:
		if stage is TaskBase and not stage.is_done():
			return false
	return true

## Reset every stage and action so the procedure can be attempted again.
func reset_all() -> void:
	for stage in stages:
		if not (stage is Sequence or stage is ActionSet):
			continue
		for a in stage.actions:
			if a is Action:
				a.reset()
		stage.reset()
	var old := state
	state = State.PENDING
	state_changed.emit(self, old, State.PENDING)

func is_failed() -> bool:
	return state == State.FAILED

func progress() -> float:
	if stages.is_empty():
		return 1.0
	var total := 0.0
	for stage in stages:
		if stage is TaskBase:
			total += stage.progress()
	return clampf(total / maxf(stages.size(), 1), 0.0, 1.0)

func active_text() -> String:
	var cur := current_action()
	if cur != null:
		return cur.active_text()
	return display_name

func cancel_current(failed: bool = true) -> void:
	var cur := current_action()
	if cur != null:
		cur.cancel(failed)
