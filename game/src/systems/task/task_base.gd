class_name TaskBase
extends Node

## Abstract building block for anything that can be succeeded or failed.
## A task is a single action, a sequence of actions, an unordered set of
## actions, or a procedure made of stages. Subtypes implement `begin_action`,
## `current_action`, `is_done`, `hold`, and `cancel`.

enum State { PENDING, ACTIVE, DONE, FAILED, LOCKED }
enum BeginResult { OK, BLOCKED, ACCIDENT }

signal state_changed(task, old_state, new_state)
signal succeeded(task)
signal failed(task, reason)

var state: State = State.PENDING
var display_name: String = "Task"
## Optional human readable description shown while this task is active.
var hint: String = ""

func is_done() -> bool:
	return state == State.DONE

func is_failed() -> bool:
	return state == State.FAILED

func is_active() -> bool:
	return state == State.ACTIVE

func is_locked() -> bool:
	return state == State.LOCKED

func is_pending() -> bool:
	return state == State.PENDING

## Whether this task may be begun right now. Override in subtypes.
func can_begin() -> bool:
	return state == State.PENDING

## Whether children must be performed in order (only Sequence does).
func enforces_order() -> bool:
	return false

## Mark the task active. Safe to call repeatedly.
func begin() -> void:
	if state != State.PENDING:
		return
	state = State.ACTIVE
	state_changed.emit(self, State.PENDING, State.ACTIVE)

## Mark the task done (succeeded).
func complete() -> void:
	if state == State.DONE or state == State.FAILED:
		return
	var old := state
	state = State.DONE
	state_changed.emit(self, old, State.DONE)
	succeeded.emit(self)

## Mark the task failed.
func fail(reason: String = "") -> void:
	if state == State.DONE or state == State.FAILED:
		return
	var old := state
	state = State.FAILED
	state_changed.emit(self, old, State.FAILED)
	failed.emit(self, reason)

## Reset back to pending so the task can be retried.
func reset() -> void:
	var old := state
	state = State.PENDING
	state_changed.emit(self, old, State.PENDING)

## Progress from 0.0 to 1.0 for the currently active work. Override in subtypes.
func progress() -> float:
	return 0.0

## Human readable label for what the player should be doing right now.
func active_text() -> String:
	return display_name
