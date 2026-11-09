class_name RunManager
extends Node

signal run_finished(won: bool)

enum Phase { BOARDING, WINDOW, OVER }

@export var run_seconds := 660.0
@export var extraction_window := 180.0
@export var loot_goal := 750
@export var failed_system_limit := 3
@export var max_danger_seconds := 60.0
@export var flood_grace := 30.0


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
var _danger_bar: ProgressBar
var _danger_label: Label
var _systems_panel: Label
var _tasks_panel: Label
var _banner: Label
var _warning_label: Label
var _over_t := 0.0
var _all_down_t := 0.0
var _hold_bar: ProgressBar
var _hold_label: Label
var _objectives_label: Label
var _loot_panel: Label
var _status_label: Label
var _health_label: Label


var _system_down_time: Dictionary = {}
var _task_active_time: Dictionary = {}
var _peak_flood := 0.0
var _loss_cause := ""


func _ready() -> void:
	add_to_group("run_manager")
	time_left = run_seconds
	window_left = extraction_window
	_build_hud()
	call_deferred("_bind_pad")
	call_deferred("_show_objectives")


func _show_objectives() -> void:
	if _objectives_label != null:
		_objectives_label.text = "FIX RED SYSTEMS   CLEAR TASKS   HAUL LOOT TO THE PAD   SURVIVE UNTIL THE PILOT ARRIVES"
		_objectives_label.visible = true
		call_deferred("_hide_objectives")


func _hide_objectives() -> void:
	if _objectives_label != null:
		_objectives_label.visible = false


func _bind_pad() -> void:
	_pad = get_tree().get_first_node_in_group("extraction_pads") as ExtractionPad


func _input(event: InputEvent) -> void:
	if phase == Phase.OVER and event.is_action_pressed("restart_run"):
		get_tree().reload_current_scene()


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

	_update_all_down(delta)
	_update_danger(delta)
	_update_hud()


func _update_all_down(delta: float) -> void:
	var any := false
	var all_down := true
	for n in get_tree().get_nodes_in_group("players"):
		var p := n as Node3D
		if p == null:
			continue
		any = true
		if not (p.has_method("is_down") and p.is_down()):
			all_down = false
			break
	if any and all_down:
		_all_down_t += delta
		if _all_down_t >= 4.0:
			_loss_cause = "THE CREW TOOK EVERYONE DOWN"
			_finish(false, _loss_cause)
	else:
		_all_down_t = 0.0


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
	var tasks: Array[String] = []
	var pump_failed := false
	var task_danger := 0.0
	for n in get_tree().get_nodes_in_group("ship_systems"):
		var s := n as ShipSystem
		if s == null or not s.is_failed():
			continue
		var task := s as TaskStation
		if task != null:
			tasks.append(task.display_name)
			match task.task_kind:
				"fire":
					task_danger += 0.12
				"fuel":
					task_danger += 0.08
				"leak":
					pump_failed = true
				"debris":
					task_danger += 0.03
			continue
		failed += 1
		names.append(s.display_name)
		if s.system_id == "pump":
			pump_failed = true

	_track_contributors(names, tasks, pump_failed, delta)

	if pump_failed:
		flood = minf(flood_grace + 20.0, flood + delta * 0.25)
	else:
		flood = maxf(0.0, flood - delta * 1.5)
	_peak_flood = maxf(_peak_flood, flood)

	var sinking := failed >= failed_system_limit or flood > flood_grace
	if sinking:
		danger = minf(max_danger_seconds, danger + delta * (0.35 + (0.15 if pump_failed else 0.0)))
	else:
		danger = maxf(0.0, danger - delta * 0.5)
	danger = minf(max_danger_seconds, danger + task_danger * delta)

	var reason: Array[String] = []
	if pump_failed:
		reason.append("flooding")
	for n in names:
		reason.append(n)
	for t in tasks:
		reason.append(t)
	_set_danger_label(reason, sinking)

	var status_parts: Array[String] = []
	if failed >= failed_system_limit:
		status_parts.append("CRITICAL: " + ", ".join(PackedStringArray(names)))
	elif pump_failed and flood > 0.0:
		status_parts.append("FLOODING: fix the leak / pump")
	if not tasks.is_empty():
		status_parts.append("TASKS: " + ", ".join(PackedStringArray(tasks)))
	_set_status("  |  ".join(PackedStringArray(status_parts)))

	if danger >= max_danger_seconds:
		_loss_cause = "THE SHIP WENT DOWN"
		_finish(false, _loss_cause)


func _track_contributors(names: Array[String], tasks: Array[String], pump_failed: bool, delta: float) -> void:
	for n in names:
		var cur := float(_system_down_time.get(n, 0.0))
		_system_down_time[n] = cur + delta
	for t in tasks:
		var cur := float(_task_active_time.get(t, 0.0))
		_task_active_time[t] = cur + delta


func _set_danger_label(reason: Array[String], sinking: bool) -> void:
	if _danger_label == null:
		return
	if not sinking:
		_danger_label.text = "SAFE"
		_danger_label.modulate = Color(0.6, 1.0, 0.65)
		return
	_danger_label.text = "RISING." + ", ".join(PackedStringArray(reason)) if not reason.is_empty() else "RISING"
	_danger_label.modulate = Color(1.0, 0.95, 0.4)


func _loss_report() -> String:
	var lines: Array[String] = []
	lines.append("%s\n\nLOOT SECURED: %d / %d" % [_loss_cause, total_value, loot_goal])

	lines.append("\nSKILL ISSUES:")
	var wrongs: Array[String] = []
	var top: Array[String] = []
	for k in _system_down_time.keys():
		var t := float(_system_down_time.get(k, 0.0))
		if t > 1.0:
			top.append("%s down for ~%ds" % [k, int(t)])
	for k in _task_active_time.keys():
		var t := float(_task_active_time.get(k, 0.0))
		if t > 1.0:
			top.append("%s left running ~%ds" % [k, int(t)])
	if _peak_flood > flood_grace:
		top.append("flooding reached ~%d%%" % int(_peak_flood))
	if top.is_empty():
		top.append("ran out of time")
	var ordered: Array[String] = []
	var remaining := top.duplicate()
	while remaining.size() > 0 and ordered.size() < 4:
		var best := ""
		var best_t := -1.0
		for s in remaining:
			var t := _time_of(s)
			if t > best_t:
				best_t = t
				best = s
		ordered.append(best)
		remaining.erase(best)
	for i in ordered:
		wrongs.append("• " + i)
	lines.append("\n".join(wrongs))

	lines.append("\nWHAT TO DO NEXT TIME:")
	var tips: Array[String] = []
	var has_critical := false
	var has_task := false
	var has_flood := false
	var has_loot := false
	for k in _system_down_time.keys():
		if _system_down_time.get(k, 0.0) > 1.0:
			has_critical = true
	for k in _task_active_time.keys():
		if _task_active_time.get(k, 0.0) > 1.0:
			has_task = true
	if _peak_flood > flood_grace:
		has_flood = true
	if total_value < loot_goal:
		has_loot = true
	if has_critical:
		tips.append("fix red systems first - they drive the danger bar up fast")
	if has_task:
		tips.append("clear tasks between loot runs so they don't add danger")
	if has_flood:
		tips.append("patch the hull leak and repair the bilge pump before flooding takes over")
	if has_loot:
		tips.append("carry loot to the extraction pad early - the pilot won't wait")
	if tips.is_empty():
		tips.append("try again - every run is different")
	tips.append("press R to restart")
	var tip_lines: Array[String] = []
	for t in tips:
		tip_lines.append("• " + t)
	lines.append("\n".join(tip_lines))

	return "\n".join(lines)


func _time_of(s: String) -> float:
	for k in _system_down_time.keys():
		if s.find(k) >= 0:
			return float(_system_down_time.get(k, 0.0))
	for k in _task_active_time.keys():
		if s.find(k) >= 0:
			return float(_task_active_time.get(k, 0.0))
	return 0.0


func _finish(did_win: bool, message: String) -> void:
	if phase == Phase.OVER:
		return
	phase = Phase.OVER
	won = did_win
	if did_win:
		_loss_cause = "HEIST COMPLETE"
	else:
		if message.is_empty():
			message = _loss_cause
		_loss_cause = message
	if _banner != null:
		if did_win:
			_banner.text = "RUN COMPLETE\nHEIST COMPLETE\n\nLOOT SECURED: %d / %d\n\npress R to run it again" % [total_value, loot_goal]
			_banner.modulate = Color(0.55, 1.0, 0.6)
		else:
			_banner.text = "RUN FAILED\n\n%s" % _loss_report()
			_banner.modulate = Color(1.0, 0.35, 0.3)
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
	if _loot_panel != null:
		_loot_panel.text = "LOOT: %d / %d" % [total_value, loot_goal]
	if _danger_bar != null:
		_danger_bar.value = danger
	var p := _local_player()
	if _hold_bar != null:
		var prog := -1.0
		if p != null and p.has_method("get_hold_progress"):
			prog = p.get_hold_progress()
		if prog >= 0.0:
			_hold_bar.visible = true
			_hold_bar.value = prog * 100.0
			if _hold_label != null:
				_hold_label.visible = true
				if p.has_method("get_hold_text"):
					_hold_label.text = p.get_hold_text()
		else:
			_hold_bar.visible = false
			if _hold_label != null:
				_hold_label.visible = false
	if _health_label != null:
		if p != null and p.has_method("get_health"):
			var hp := int(p.get_health())
			_health_label.text = "HP %d" % hp
			if p.has_method("is_down") and p.is_down():
				_health_label.text = "DOWNED. Wait for a friend or med bay"
			_health_label.modulate = Color(1.0, 0.35, 0.3) if hp < 40 else Color(0.9, 0.95, 1.0)
	if _systems_panel != null:
		_systems_panel.text = _systems_text()
	if _tasks_panel != null:
		_tasks_panel.text = _tasks_text()
	if _warning_label != null:
		var in_restricted := false
		for a in get_tree().get_nodes_in_group("restricted_areas"):
			if a.has_method("contains") and a.contains(p):
				in_restricted = true
				break
		_warning_label.visible = in_restricted
		if in_restricted:
			_warning_label.text = "RESTRICTED AREA - crew will turn hostile"


func _systems_text() -> String:
	var lines: Array[String] = []
	for n in get_tree().get_nodes_in_group("ship_systems"):
		var s := n as ShipSystem
		if s == null:
			continue
		var ok := not s.is_failed()
		lines.append("%s: %s" % [s.display_name, "OK" if ok else "FAILED"])
	return "\n".join(lines) if not lines.is_empty() else ""


func _tasks_text() -> String:
	var lines: Array[String] = []
	for n in get_tree().get_nodes_in_group("task_stations"):
		var t := n as TaskStation
		if t == null or not t.is_failed():
			continue
		lines.append("%s" % t.display_name)
	return "\n".join(lines) if not lines.is_empty() else ""


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
	_danger_label = Label.new()
	_danger_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_danger_label.add_theme_font_size_override("font_size", 14)
	_danger_label.modulate = Color(0.6, 1.0, 0.65)
	box.add_child(_danger_label)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.modulate = Color(1.0, 0.45, 0.35)
	box.add_child(_status_label)

	var side := PanelContainer.new()
	side.anchor_left = 1.0
	side.anchor_right = 1.0
	side.anchor_top = 0.25
	side.anchor_bottom = 0.5
	side.offset_left = -300.0
	side.offset_right = -16.0
	side.offset_top = 12.0
	side.offset_bottom = -16.0
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(side)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 2)
	sbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(sbox)
	var stitle = Label.new()
	stitle.text = "SHIP STATUS"
	stitle.add_theme_font_size_override("font_size", 16)
	stitle.modulate = Color(0.9, 0.95, 1.0)
	sbox.add_child(stitle)
	_systems_panel = Label.new()
	_systems_panel.add_theme_font_size_override("font_size", 15)
	_systems_panel.modulate = Color(0.9, 0.95, 1.0)
	sbox.add_child(_systems_panel)
	_tasks_panel = Label.new()
	_tasks_panel.add_theme_font_size_override("font_size", 15)
	_tasks_panel.modulate = Color(0.9, 0.95, 1.0)
	sbox.add_child(_tasks_panel)
	var lootp = Label.new()
	lootp.text = "LOOT: %d / %d" % [total_value, loot_goal]
	lootp.add_theme_font_size_override("font_size", 15)
	lootp.modulate = Color(0.9, 0.95, 1.0)
	sbox.add_child(lootp)
	_loot_panel = lootp

	_health_label = Label.new()
	_health_label.anchor_top = 1.0
	_health_label.anchor_bottom = 1.0
	_health_label.offset_left = 16.0
	_health_label.offset_top = -42.0
	_health_label.offset_bottom = -12.0
	_health_label.add_theme_font_size_override("font_size", 18)
	root.add_child(_health_label)

	_hold_label = Label.new()
	_hold_label.anchor_left = 0.5
	_hold_label.anchor_right = 0.5
	_hold_label.anchor_top = 1.0
	_hold_label.anchor_bottom = 1.0
	_hold_label.offset_left = -180.0
	_hold_label.offset_right = 180.0
	_hold_label.offset_top = -100.0
	_hold_label.offset_bottom = -72.0
	_hold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hold_label.add_theme_font_size_override("font_size", 18)
	_hold_label.visible = false
	root.add_child(_hold_label)

	_hold_bar = ProgressBar.new()
	_hold_bar.anchor_left = 0.5
	_hold_bar.anchor_right = 0.5
	_hold_bar.anchor_top = 1.0
	_hold_bar.anchor_bottom = 1.0
	_hold_bar.offset_left = -140.0
	_hold_bar.offset_right = 140.0
	_hold_bar.offset_top = -66.0
	_hold_bar.offset_bottom = -54.0
	_hold_bar.max_value = 100.0
	_hold_bar.show_percentage = false
	_hold_bar.visible = false
	root.add_child(_hold_bar)

	_objectives_label = Label.new()
	_objectives_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_objectives_label.offset_left = -300.0
	_objectives_label.offset_right = 300.0
	_objectives_label.offset_top = 120.0
	_objectives_label.offset_bottom = 120.0
	_objectives_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objectives_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_objectives_label.add_theme_font_size_override("font_size", 20)
	_objectives_label.modulate = Color(0.95, 0.9, 0.8)
	_objectives_label.visible = false
	root.add_child(_objectives_label)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -260.0
	_banner.offset_right = 260.0
	_banner.offset_top = -120.0
	_banner.offset_bottom = 120.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 32)
	_banner.visible = false
	root.add_child(_banner)

	_warning_label = Label.new()
	_warning_label.set_anchors_preset(Control.PRESET_CENTER)
	_warning_label.offset_left = -220.0
	_warning_label.offset_right = 220.0
	_warning_label.offset_top = -140.0
	_warning_label.offset_bottom = -80.0
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warning_label.add_theme_font_size_override("font_size", 18)
	_warning_label.modulate = Color(1.0, 0.42, 0.3)
	_warning_label.visible = false
	root.add_child(_warning_label)
