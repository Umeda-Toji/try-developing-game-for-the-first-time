# Godot 4.7.2 / GDScript
# res://scripts/world/water.gd
#
# 水（M-06 泳ぎ・W-12 水の質感）。水面と、映り込みの ReflectionProbe と、範囲（箱）を持つ
#  ・プレイヤーは毎フレーム、group "water" の水に入っているかを contains() で調べる
#  ・当たり判定は持たない（水の底の地面に立てるのは、底の箱のほう）
class_name Water
extends Node3D

const WATER_SHADER := preload("res://shaders/water.gdshader")
const PROBE_MARGIN := 6.0      # 映り込みを写す範囲の、水のまわりの余白（m）
const PROBE_HEIGHT := 18.0     # 映り込みを写す範囲の高さ（m。まわりの建物が入るように）

var size := Vector3(4, 2, 4)   # 範囲（中心が position、上の面が水面）
var surface_y := 0.0           # 水面の高さ（世界の座標）


func _ready() -> void:
	add_to_group("water")
	surface_y = global_position.y + size.y * 0.5
	# 水面：細かく分けた板（さざ波で頂点を少し上下させるため）。shaders/water.gdshader
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	plane.subdivide_width = int(size.x * 3.0)
	plane.subdivide_depth = int(size.z * 3.0)
	mi.mesh = plane
	mi.position = Vector3.UP * size.y * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# 映り込み：水の上にまわりの景色を1回だけ写し取る（毎フレームは写さないので軽い）
	var probe := ReflectionProbe.new()
	probe.name = "ReflectionProbe"
	probe.size = Vector3(size.x + PROBE_MARGIN * 2.0, PROBE_HEIGHT, size.z + PROBE_MARGIN * 2.0)
	probe.position = Vector3.UP * (size.y * 0.5 + PROBE_HEIGHT * 0.5 - 0.5)
	probe.origin_offset = Vector3.DOWN * (PROBE_HEIGHT * 0.5 - 2.0)  # 写す位置は水面の少し上（人の目の高さ）
	probe.box_projection = true       # 箱の形に合わせて、建物の位置がずれずに映る
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.max_distance = 80.0
	probe.intensity = 1.0
	add_child(probe)


# 点 p が水の範囲（横）にあり、水面より下か
func contains(p: Vector3) -> bool:
	var half := size * 0.5
	var c := global_position
	return absf(p.x - c.x) <= half.x and absf(p.z - c.z) <= half.z and p.y <= surface_y and p.y >= c.y - half.y - 1.0
