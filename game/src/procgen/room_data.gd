class_name RoomData
extends Resource

@export_range(0.0, 1.0) var probabilities: Array[float]
@export var maximum_count: int = 0
@export var tag: StringName = &""
@export var cannot_border_tag: Array[StringName]
@export var name: StringName
@export var type: RoomType = RoomType.Fourway
@export var scene: PackedScene

enum RoomType {
	### doors on all sides
	Fourway,
	### doors on all sides (top and bottom), but with stairs
	Stairs,
	### doors only on the bottom
	DeadEnd,
	### doors on the left and right
	Hallway,
	### doors on the bottom and right
	Corner,
	### doors on the bottom, left, and right
	Threeway,
}

### bits are bit 4,8 = up, 3,7 = left, 2,6 = down, 1,5 = right
### this is so that u4 shift right is +90 deg
### it's also repeated so that it is possible to do up to 4 >>1
static func ty_to_doors(ty: RoomType) -> int:
	match ty:
		RoomType.Fourway, RoomType.Stairs: return 0b11111111
		RoomType.DeadEnd: return 0b00100010
		RoomType.Hallway: return 0b01010101
		RoomType.Corner: return 0b00110011
		RoomType.Threeway: return 0b01110111
		_: return 0b11111111
