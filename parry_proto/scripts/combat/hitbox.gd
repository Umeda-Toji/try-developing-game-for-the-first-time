# Godot 4.7.2 / GDScript
# res://scripts/combat/hitbox.gd
# 「攻撃する側」の判定。activate() している間だけ、重なった Hurtbox に1回ずつヒットを通知する。
class_name Hitbox
extends Area3D

signal hit_landed(hurtbox: Hurtbox)

var attack: Dictionary = {}
var active := false
var _already_hit: Array[Node] = []


func _ready() -> void:
	monitoring = true
	monitorable = false


func activate(attack_data: Dictionary) -> void:
	attack = attack_data
	active = true
	_already_hit.clear()  # 1回の攻撃で同じ相手に何度も当たらないようにする


# 当たった場所（火花を出す位置）：攻撃判定と被弾判定の中間
func contact_point(hurtbox: Hurtbox) -> Vector3:
	return hurtbox.global_position.lerp(global_position, 0.5)


func deactivate() -> void:
	active = false


func _physics_process(_delta: float) -> void:
	if not active:
		return
	# area_entered シグナルより「毎tick重なりを調べる」方が、
	# 判定を出した瞬間にすでに重なっているケースを取りこぼさない
	for area in get_overlapping_areas():
		if area is Hurtbox:
			var hb := area as Hurtbox
			if hb.entity != null and not _already_hit.has(hb.entity):
				_already_hit.append(hb.entity)
				hit_landed.emit(hb)
				if not active:  # 受け手側の処理（パリィ等）で無効化されたら打ち切る
					return
