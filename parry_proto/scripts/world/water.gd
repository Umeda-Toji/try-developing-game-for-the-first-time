# Godot 4.7.2 / GDScript
# res://scripts/world/water.gd
#
# 水（M-06 泳ぎ）。見た目の板と、範囲（箱）だけを持つ
#  ・プレイヤーは毎フレーム、group "water" の水に入っているかを contains() で調べる
#  ・当たり判定は持たない（水の底の地面に立てるのは、底の箱のほう）
class_name Water
extends Node3D

var size := Vector3(4, 2, 4)   # 範囲（中心が position、上の面が水面）
var surface_y := 0.0           # 水面の高さ（世界の座標）


func _ready() -> void:
	add_to_group("water")
	surface_y = global_position.y + size.y * 0.5
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.WATER
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.04          # つるつる：空や建物が映る
	mat.metallic_specular = 0.7
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# 点 p が水の範囲（横）にあり、水面より下か
func contains(p: Vector3) -> bool:
	var half := size * 0.5
	var c := global_position
	return absf(p.x - c.x) <= half.x and absf(p.z - c.z) <= half.z and p.y <= surface_y and p.y >= c.y - half.y - 1.0
