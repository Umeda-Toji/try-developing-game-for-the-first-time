# Godot 4.7.2 / GDScript
# res://scripts/enemy/enemy_flower.gd
#
# 敵（苗人）の頭の花（F-01。NEXT_FEATURES 1.3・ステップ3。11/19 決定）
#  ・顔の代わりに、頭の骨（Head）に花を付ける。普段はつぼみ（Petal_4）
#  ・攻撃の合図で、つぼみが小さくなりながら、開いた花が OPEN_FRAMES かけて大きくなる
#    色はパリィできる＝白、パリィできない（棘咲き）＝赤。フェイントのニセの光では半分（FEINT_OPEN）だけ白く開く
#  ・攻撃が終わったら CLOSE_FRAMES かけて、つぼみに戻る
#  ・倒れると DEATH_OPEN（1.3倍）まで満開になり、白っぽくあせる
#  ・ボスの第2形態では、肩と背中にも花が咲く（「全身が咲く」）
#  ・花の素材：Quaternius「Stylized Nature MegaKit」（CC0）の Petal_1〜5
#  ・今までの合図（体が光る・まわりを赤く照らす E-15）は、enemy.gd がそのまま出す
class_name EnemyFlower
extends Node3D

const FLOWER_DIR := "res://models/flowers/"
const BUD_MODEL := "Petal_4"
# 素材の花の横幅（m）。大きさ（size）をこの幅で割って拡大率にする
const MODEL_WIDTH := {"Petal_1": 0.46, "Petal_2": 0.67, "Petal_3": 0.62, "Petal_4": 0.33, "Petal_5": 0.83}
const BUD_RATIO := 0.6          # つぼみの大きさ（開いた花に対して）
const OPEN_FRAMES := 6          # 開くのにかかるフレーム
const CLOSE_FRAMES := 20        # 閉じるのにかかるフレーム
const FEINT_OPEN := 0.5         # ニセの光のときの開き
const DEATH_OPEN := 1.3         # 倒れたときの開き（満開）
const COLOR_BUD := Color(0.42, 0.62, 0.32)
const COLOR_WHITE := Color(1.0, 1.0, 0.97)
const COLOR_RED := Color(1.0, 0.18, 0.12)
const COLOR_DEAD := Color(0.95, 0.9, 0.86)
const GLOW_OPEN := 1.2          # 合図で開いたときの光の強さ
const HEAD_BONE := "Head"
const FACE_FORWARD := 0.07      # 頭の骨（首の付け根にある）から、顔の前へのずらし（m。敵の大きさに合わせて拡大する）
const FACE_UP := 0.09           # 頭の骨から、顔の真ん中の高さへのずらし（m）
const EXTRA_BONES := ["clavicle_l", "clavicle_r", "spine_03"]   # 第2形態で花が咲く所（肩・背中）
const EXTRA_SIZE := 0.5

var open_amount := 0.0          # 0＝つぼみ、1＝開いた、1.3＝満開
var color := COLOR_BUD
var _bud: Node3D
var _open_nodes: Array[Node3D] = []
var _extras: Array[Node3D] = []
var _materials: Array[ShaderMaterial] = []
var _size := 0.45
var _model := "Petal_5"
var _extra_amount := 0.0
var _skel: Skeleton3D
var _body: Node3D
var _head_idx := -1
var _extra_bones: Array[int] = []


# skel：敵のモデルの骨組み。body：敵（向きを使う）
# model：開いた花の素材の名前。size：開いた花の横幅（m）。layers：重ねる枚数（ボスは2）
#  ・骨の回転はアニメによって大きく変わることがあるので、骨の「位置」だけを使い、向きは敵の前に合わせる（follow で毎フレーム）
func setup(skel: Skeleton3D, body: Node3D, model: String, size: float, layers: int) -> void:
	_skel = skel
	_body = body
	_model = model
	_size = size
	_head_idx = skel.find_bone(HEAD_BONE)
	top_level = true   # 位置と向きは follow で直接決める
	body.add_child(self)
	_bud = _make(BUD_MODEL, size * BUD_RATIO, 0.0)
	for i in layers:
		_open_nodes.append(_make(model, size * (1.0 - 0.25 * i), TAU / 10.0 * i))
	follow()
	apply()


# 第2形態：肩と背中にも花を付ける（最初は閉じている。set_extra で咲かせる）。肩の花は上を、背中の花は後ろを向く
func add_extras() -> void:
	for i in EXTRA_BONES.size():
		var idx := _skel.find_bone(EXTRA_BONES[i])
		if idx == -1:
			continue
		var holder := Node3D.new()
		holder.name = "Extra_" + EXTRA_BONES[i]
		holder.top_level = true
		add_child(holder)
		var f := _instance(_model, EXTRA_SIZE)
		holder.add_child(f)
		f.scale = Vector3.ONE * 0.001
		_extras.append(f)
		_extra_bones.append(idx)
	follow()


# 骨の位置に合わせて置き直す（敵が動くたびに呼ぶ）
func follow() -> void:
	if _skel == null or _head_idx == -1:
		return
	var s := _skel.global_basis.get_scale().x
	var fwd := -_body.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := Vector3.UP.cross(fwd).normalized()
	var head := _skel.global_transform * _skel.get_bone_global_pose(_head_idx).origin
	# 花の上（+Y）を顔の前に向ける
	global_transform = Transform3D(Basis(right, fwd, right.cross(fwd)), head + fwd * FACE_FORWARD * s + Vector3.UP * FACE_UP * s)
	for i in _extras.size():
		var p := _skel.global_transform * _skel.get_bone_global_pose(_extra_bones[i]).origin
		var face := Vector3.UP if i < 2 else -fwd   # 肩は上、背中は後ろ
		var side := right if i < 2 else Vector3.UP
		(_extras[i].get_parent() as Node3D).global_transform = Transform3D(Basis(side, face, side.cross(face)), p + face * 0.12 * s)


# 開き具合（0〜1.3）と色を見た目に当てはめる
func apply() -> void:
	var bud_s := clampf(1.0 - open_amount * 1.5, 0.0, 1.0)
	_bud.visible = bud_s > 0.01
	_bud.scale = Vector3.ONE * float(_bud.get_meta("base")) * maxf(bud_s, 0.001)
	for n in _open_nodes:
		n.visible = open_amount > 0.01
		n.scale = Vector3.ONE * float(n.get_meta("base")) * maxf(open_amount, 0.001)
	var glow := GLOW_OPEN * clampf(open_amount, 0.0, 1.0) if color != COLOR_DEAD and color != COLOR_BUD else 0.0
	for m in _materials:
		m.set_shader_parameter("tint", color)
		m.set_shader_parameter("glow", glow)
	for e in _extras:
		e.visible = _extra_amount > 0.01
		e.scale = Vector3.ONE * float(e.get_meta("base")) * maxf(_extra_amount, 0.001)


# 1フレームぶん、目標の開き具合へ近づける（開くのは速く、閉じるのはゆっくり）
func step_toward(target: float, target_color: Color) -> void:
	if target > open_amount:
		open_amount = minf(open_amount + 1.0 / OPEN_FRAMES, target)
		color = target_color
	elif target < open_amount:
		open_amount = maxf(open_amount - 1.0 / CLOSE_FRAMES, target)
		if open_amount <= 0.0:
			color = COLOR_BUD
	else:
		color = target_color if target > 0.0 else COLOR_BUD
	apply()


# 第2形態の肩・背中の花：amount（0〜1）
func set_extra(amount: float) -> void:
	_extra_amount = amount
	apply()


func extra_count() -> int:
	return _extras.size()


func extra_amount() -> float:
	return _extra_amount


func _make(model: String, size: float, spin: float) -> Node3D:
	var n := _instance(model, size)
	n.rotation.y = spin
	add_child(n)
	return n


func _instance(model: String, size: float) -> Node3D:
	var n: Node3D = (load(FLOWER_DIR + model + ".gltf") as PackedScene).instantiate()
	var base: float = size / float(MODEL_WIDTH.get(model, 0.5))
	n.set_meta("base", base)
	n.scale = Vector3.ONE * base
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flower.gdshader")
	mat.set_shader_parameter("tex", load(FLOWER_DIR + "Flowers.png"))
	_materials.append(mat)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n
