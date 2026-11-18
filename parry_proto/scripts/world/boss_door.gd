# Godot 4.7.2 / GDScript
# res://scripts/world/boss_door.gd
#
# 旧市民ホールの扉（W-xx）。根が絡んで閉じている
#  ・guards（広場の苗人）が全員倒れたら開く（根がほどけて、地面に沈む）
#  ・沈むのにかかる長さはフレームで数える（OPEN_FRAMES）
#  ・当たり判定は、開き始めた瞬間に消す
class_name BossDoor
extends StaticBody3D

const OPEN_FRAMES := 90          # 沈みきるまで（1.5秒）

signal opened

var size := Vector3(4, 4, 1)
var guards: Array = []           # この敵たちが全員倒れたら開く
var is_open := false
var _open_frame := -1
var _start_y := 0.0
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 0
	set_collision_layer_value(1, true)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	_shape.shape = box
	add_child(_shape)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = WorldMaterials.make("roots")  # 絡んだ根（木の皮の写真テクスチャ）
	add_child(mi)


func _physics_process(_delta: float) -> void:
	if not is_open:
		if _guards_down():
			open()
		return
	if _open_frame >= 0 and _open_frame < OPEN_FRAMES:
		_open_frame += 1
		position.y = _start_y - size.y * float(_open_frame) / float(OPEN_FRAMES)


func open() -> void:
	if is_open:
		return
	is_open = true
	_open_frame = 0
	_start_y = position.y
	_shape.set_deferred("disabled", true)
	opened.emit()


func _guards_down() -> bool:
	if guards.is_empty():
		return false
	for g in guards:
		if is_instance_valid(g) and not g.is_dead():
			return false
	return true
