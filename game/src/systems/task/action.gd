class_name Action
extends TaskBase

## Single atomic piece of work (e.g. "close the coolant valve").
## Can be driven through the system's hold-E bar or interacted with directly
## as a world object (a handle, breaker, valve, etc.).

@export var id: String = ""
@export var hold_time: float = 2.0
## Action ids that must be DONE before this action may begin.
@export var requires: Array[String] = []
## If true, releasing early triggers an accident instead of just resetting.
@export var accident_on_fail: bool = false
@export var accident_reason: String = "Mistake made."
## If true, attempting to begin while `requires` are unmet causes an accident
## (e.g. opening the engine before tripping the breaker shocks you).
## If false, the attempt is simply blocked ("can't turn the valve yet").
@export var accident_on_unguarded_begin: bool = false

## Back references set by the Procedure that owns this action.
var _procedure: Procedure = null
var _stage = null
var _progress: float = 0.0
var _actor: Node3D = null

func assign_owner(procedure: Procedure, stage) -> void:
	_procedure = procedure
	_stage = stage

## Returns whether this action may begin and why.
func check_begin() -> BeginResult:
	if state != State.PENDING:
		return BeginResult.BLOCKED
	## Ordering: only the stage's current action may begin, and only when the
	## stage is ordered (Sequence). ActionSets allow any pending action.
	if _stage != null and _stage.has_method("enforces_order") and _stage.enforces_order():
		var cur: Action = _stage.current_action()
		if cur == null or cur != self:
			return BeginResult.BLOCKED
	## Prerequisites: required actions must be done.
	if _procedure != null and not _procedure.guards_met_for(id):
		if accident_on_unguarded_begin:
			return BeginResult.ACCIDENT
		return BeginResult.BLOCKED
	return BeginResult.OK

## Begin performing this action. Returns the begin result.
func begin_checked() -> BeginResult:
	var res := check_begin()
	if res == BeginResult.OK:
		begin()
	elif res == BeginResult.ACCIDENT:
		fail(accident_reason)
	return res

## Advance the hold progress by `delta`. Returns true when the action completes.
func hold(actor: Node3D, delta: float) -> bool:
	if state != State.ACTIVE:
		return false
	if _actor == null:
		_actor = actor
	_progress += delta
	if _progress >= hold_time:
		complete()
		return true
	return false

## Cancel the in-progress hold. If `failed` and the action is accident-prone,
## trigger an accident; otherwise just reset progress.
func cancel(failed: bool = true) -> void:
	if state != State.ACTIVE:
		return
	_progress = 0.0
	if failed and accident_on_fail:
		fail(accident_reason)
	else:
		reset()
	_actor = null

func progress() -> float:
	return clampf(_progress / maxf(hold_time, 0.01), 0.0, 1.0)

func reset() -> void:
	_progress = 0.0
	_actor = null
	super.reset()

func active_text() -> String:
	var text := hint
	if text.is_empty():
		text = display_name
	return text
