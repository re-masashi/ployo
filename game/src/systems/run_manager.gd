class_name RunManager
extends Node

signal run_finished(won: bool)

enum Phase { BOARDING, WINDOW, OVER }

@export var run_seconds := 360.0
@export var extraction_window := 120.0
@export var loot_goal := 750
@export var failed_system_limit := 3
@export var max_danger_seconds := 40.0
@export var flood_grace := 8.0

var phase: Phase = Phase.BOARDING
var time_left := 0.0
var window_left := 0.0
var danger := 0.0
var flood := 0.0
var total_value := 0
var won := false

var _pad: ExtractionPad
var _hud: CanvasLayer
var _timer_label: Label
var _loot_label: Label
var _status_label: Label
var _health_label: Label
var _danger_bar: ProgressBar
var _banner: Label
var _over_t := 0.0


func _ready() -> void:
	add_to_group("run_manager")
	time_left = run_seconds
	window_left = extraction_window
	_build_hud()
	call_deferred("_bind_pad")


func _bind_pad() -> void:
	_pad = get_tree().get_first_node_in_group("extraction_pads") as ExtractionPad


func _process(delta: float) -> void:
	_bind_pad_if_needed()
	total_value = _pad.total_value if _pad != null else 0

	if phase == Phase.OVER:
		_over_t += delta
		return

	if phase == Phase.BOARDING:
		time_left = maxf(0.0, time_left - delta)
		if time_left <= 0.0:
			_pilot_arrives()
	elif phase == Phase.WINDOW:
		window_left = maxf(0.0, window_left - delta)
		if total_value >= loot_goal:
			_finish(true, "HEIST COMPLETE")
		elif window_left <= 0.0:
			_finish(false, "PILOT LEFT YOU BEHIND")

	_update_danger(delta)
	_update_hud()


func _bind_pad_if_needed() -> void:
	if _pad == null or not is_instance_valid(_pad):
		_pad = get_tree().get_first_node_in_group("extraction_pads") as ExtractionPad


func _pilot_arrives() -> void:
	phase = Phase.WINDOW
	window_left = extraction_window
	if total_value >= loot_goal:
		_finish(true, "HEIST COMPLETE")
	else:
		_set_status("PILOT IS WAITING - get %d more loot to the pad" % maxi(0, loot_goal - total_value))


func _update_danger(delta: float) -> void:
	var failed := 0
	var names: Array[String] = []
	var pump_failed := false
	for n in get_tree().get_nodes_in_group("ship_systems"):
		var s := n as ShipSystem
		if s != null and s.is_failed():
			failed += 1
			names.append(s.display_name)
			if s.system_id == "pump":
				pump_failed = true
	if pump_failed:
		flood = minf(flood_grace + 20.0, flood + delta)
	else:
		flood = maxf(0.0, flood - delta * 2.0)
	var sinking := failed >= failed_system_limit or flood > flood_grace
	if sinking:
		danger = minf(max_danger_seconds, danger + delta * (1.0 + (0.5 if pump_failed else 0.0)))
		if failed >= failed_system_limit:
			_set_status("CRITICAL: " + ", ".join(PackedStringArray(names)) + " FAILED")
		else:
			_set_status("BILGE FLOODING - fix the pump")
	else:
		danger = maxf(0.0, danger - delta * 0.6)
		if failed == 0 and flood <= 0.0:
			_set_status("")
		elif pump_failed and flood > 0.0:
			_set_status("BILGE FLOODING - fix the pump")
	if danger >= max_danger_seconds:
		_finish(false, "THE SHIP WENT DOWN")


func _finish(did_win: bool, message: String) -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	won = did_win
	if _banner != null:
		_banner.text = ("YOU WIN\n%s" if did_win else "YOU LOSE\n%s") % message
		_banner.modulate = Color(0.55, 1.0, 0.6) if did_win else Color(1.0, 0.35, 0.3)
		_banner.visible = true
	print("[Run] %s: %s (loot %d/%d)" % ["WIN" if did_win else "LOSE", message, total_value, loot_goal])
	run_finished.emit(did_win)


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _update_hud() -> void:
	if _timer_label == null:
		return
	if phase == Phase.BOARDING:
		_timer_label.text = "PILOT IN  %s" % _clock(time_left)
	elif phase == Phase.WINDOW:
		_timer_label.text = "PILOT WAITING  %s" % _clock(window_left)
	else:
		_timer_label.text = "RUN OVER"
	_timer_label.modulate = Color(1.0, 0.85, 0.45) if phase == Phase.WINDOW else Color(0.9, 0.95, 1.0)
	if _loot_label != null:
		_loot_label.text = "LOOT  %d / %d" % [total_value, loot_goal]
		_loot_label.modulate = Color(0.55, 1.0, 0.6) if total_value >= loot_goal else Color(0.9, 0.95, 1.0)
	if _danger_bar != null:
		_danger_bar.value = danger
	if _health_label != null:
		var p := _local_player()
		if p != null and p.has_method("get_health"):
			var hp := int(p.get_health())
			_health_label.text = "HP %d" % hp
			if p.has_method("is_down") and p.is_down():
				_health_label.text = "DOWNED - wait for a friend or med bay"
			_health_label.modulate = Color(1.0, 0.35, 0.3) if hp < 40 else Color(0.9, 0.95, 1.0)


func _local_player() -> Node3D:
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p != null and p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
			return p
	return get_tree().get_first_node_in_group("players") as Node3D


func _clock(t: float) -> String:
	var s := int(ceil(t))
	return "%02d:%02d" % [int(s / 60.0), s % 60]


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "RunHUD"
	add_child(_hud)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -190.0
	panel.offset_right = 190.0
	panel.offset_top = 12.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)

	_timer_label = Label.new()
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 24)
	box.add_child(_timer_label)
	_loot_label = Label.new()
	_loot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loot_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_loot_label)
	_danger_bar = ProgressBar.new()
	_danger_bar.custom_minimum_size = Vector2(320, 8)
	_danger_bar.max_value = max_danger_seconds
	_danger_bar.show_percentage = false
	_danger_bar.modulate = Color(1.0, 0.45, 0.3)
	box.add_child(_danger_bar)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.modulate = Color(1.0, 0.45, 0.35)
	box.add_child(_status_label)

	_health_label = Label.new()
	_health_label.anchor_top = 1.0
	_health_label.anchor_bottom = 1.0
	_health_label.offset_left = 16.0
	_health_label.offset_top = -42.0
	_health_label.offset_bottom = -12.0
	_health_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_health_label)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -260.0
	_banner.offset_right = 260.0
	_banner.offset_top = -80.0
	_banner.offset_bottom = 80.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 40)
	_banner.visible = false
	root.add_child(_banner)
