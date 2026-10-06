class_name ExtractionPad
extends Area3D

signal item_secured(item: Grabbable, total: int)

const SETTLE_SPEED := 1.5

var total_value := 0

@onready var _label: Label3D = get_node_or_null("Label3D") as Label3D

func _ready() -> void:
	add_to_group("extraction_pads")
	_refresh_label()


func secured_count() -> int:
	return get_meta("secured_count", 0) as int


func _physics_process(_delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	for body in get_overlapping_bodies():
		_try_secure(body)


func _try_secure(body: Node3D) -> void:
	var item := body as Grabbable
	if item == null:
		return
	if item.is_carried or item.is_secured:
		return
	if item.linear_velocity.length() > SETTLE_SPEED:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_secure_local(item)
	_remote_secure.rpc(item.get_path(), total_value)


func _secure_local(item: Grabbable) -> void:
	item.is_secured = true
	item.set_multiplayer_authority(1)
	item.freeze = true
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	total_value += item.value
	set_meta("secured_count", secured_count() + 1)
	_refresh_label()
	print("[Extract] secured ", item.name, " value=", item.value, " total=", total_value)
	item_secured.emit(item, total_value)


@rpc("any_peer", "call_local")
func _remote_secure(item_path: String, total: int) -> void:
	total_value = total
	_refresh_label()
	var item := get_node_or_null(item_path) as Grabbable
	if item == null or item.is_secured:
		return
	item.is_secured = true
	item.freeze = true
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO


func _refresh_label() -> void:
	if _label != null:
		_label.text = "EXTRACTION\n%d" % total_value
