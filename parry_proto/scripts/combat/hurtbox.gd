# Godot 4.7.2 / GDScript
# res://scripts/combat/hurtbox.gd
# 「攻撃を受ける側」の判定。entity に receive_attack() を持つノード（プレイヤー/敵）を入れる。
class_name Hurtbox
extends Area3D

@export var entity: Node


func _ready() -> void:
	monitoring = false
	monitorable = true
	if entity == null:
		entity = get_parent()
