@tool
extends Node3D

enum NextStep {
	LEFT,
	RIGHT,
}

var next_step: NextStep = NextStep.LEFT
var step_at: float = 0

func _process(_delta: float) -> void:
	if next_step == NextStep.LEFT:
		$LCast.target_position = Vector3.DOWN\
			+ ($LFootIdeal.position - $LFootTarget.position).normalized()
		if $LCast.is_colliding():
			var next: Vector3 = $LCast.get_collision_point()
			if next.distance_squared_to($LFootTarget.position) > 1:
				$LFootTarget.position = next
				next_step = NextStep.RIGHT
	else:
		if $RCast.is_colliding():
			var next: Vector3 = $LCast.get_collision_point()
			if next.distance_squared_to($RFootTarget.position) > 1:
				$RFootTarget.position = next
				next_step = NextStep.LEFT
