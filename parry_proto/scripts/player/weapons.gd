# Godot 4.7.2 / GDScript
# res://scripts/player/weapons.gd
#
# 武器の持ち替え（G-01。NEXT_FEATURES 1.6・ステップ5a。11/19 決定）
#  ・剣・AR・SMG・SG の4つ。持ち替えには SWAP_FRAMES かかる（半分の所で見た目が入れ替わる）
#  ・持ち替え中も、移動・ジャンプ・回避はできる（player.gd が見る）。攻撃（パリィ）はできない
#  ・銃を持っている間は、剣を背中にしまう（背中の骨 spine_03 の位置に、斜めに負う）
#  ・銃の見た目は、右手の骨（hand_r）の位置に、体の前の向きに合わせて毎フレーム置き直す
#    （骨の回転はアニメで大きく変わるので使わない。頭の花と同じやり方）
#  ・銃の素材：Quaternius「Ultimate Gun Pack」（CC0）。素材は 1/100 の大きさで、銃身が +X、上が +Z
#  ・撃つ・反動・リロード（5b）、弾を拾う（5c）の数値は GUNS にまとめておく（11/19 決定）
class_name Weapons
extends Node3D

signal changed(id: String)   # 持ち替えが終わった

const SWAP_FRAMES := 20
const IDS := ["sword", "ar", "smg", "sg"]
const LABELS := {"sword": "剣", "ar": "AR", "smg": "SMG", "sg": "SG"}
const GUN_DIR := "res://models/guns/"
# 銃の数値（11/19 決定）。フレームは物理フレーム。spread は度（腰だめ／構え）。range は m
const GUNS := {
	"ar": {"model": "AssaultRifle_1", "length": 0.85, "damage": 2, "pellets": 1, "interval": 6, "mag": 30, "reserve_max": 120,
		"recoil": "small", "spread_hip": 2.5, "spread_aim": 0.6, "range": 60.0, "reload": 120},
	"smg": {"model": "SubmachineGun_1", "length": 0.6, "damage": 1, "pellets": 1, "interval": 4, "mag": 35, "reserve_max": 140,
		"recoil": "tiny", "spread_hip": 4.0, "spread_aim": 1.5, "range": 35.0, "reload": 100},
	"sg": {"model": "Shotgun_1", "length": 0.95, "damage": 1, "pellets": 8, "interval": 50, "mag": 6, "reserve_max": 36,
		"recoil": "large", "spread_hip": 7.0, "spread_aim": 5.0, "range": 15.0, "reload": 150},
}
const HAND_BONE := "hand_r"
const BACK_BONE := "spine_03"
const HAND_OFFSET := Vector3(0.0, 0.0, 0.05)   # 手の骨から、銃の握りへのずらし（体の向き：x 右、y 上、z 前。m）
const BACK_OFFSET := 0.16                      # 背中の骨から、後ろへのずらし（m）
const GRIP_RATIO := 0.3                        # 銃の後ろの端から、握る所までの割合

var current := "sword"
var target := ""            # 持ち替え中の行き先（持ち替えていなければ ""）
var swap_left := 0          # 持ち替えの残りフレーム
var shown := "sword"        # 今見えている武器（持ち替えの半分で切り替わる）
var _body: Node3D
var _skel: Skeleton3D
var _hand_sword: Node3D     # 手に持つ剣（CharacterModel が付けたもの）
var _back_sword: Node3D     # 背中の剣（手の剣の複製）
var _guns := {}             # "ar" など → 銃の見た目
var _hand_idx := -1
var _back_idx := -1


# body：プレイヤー。model：プレイヤーの見た目（CharacterModel）
func setup(body: Node3D, model: Node3D) -> void:
	_body = body
	_skel = model.find_child("Skeleton3D", true, false) as Skeleton3D
	_hand_sword = model.find_child("Sword", true, false) as Node3D
	if _skel != null:
		_hand_idx = _skel.find_bone(HAND_BONE)
		_back_idx = _skel.find_bone(BACK_BONE)
	body.add_child(self)
	top_level = true
	if _hand_sword != null:
		_back_sword = _hand_sword.duplicate() as Node3D
		_back_sword.name = "BackSword"
		_back_sword.top_level = true
		add_child(_back_sword)
	for id in GUNS.keys():
		_guns[id] = _make_gun(GUNS[id]["model"], float(GUNS[id]["length"]))
	_apply_visibility()
	follow()


func is_gun() -> bool:
	return current != "sword"


func is_swapping() -> bool:
	return target != ""


func label() -> String:
	return LABELS[target if target != "" else current]


# 持ち替えを始める。同じ武器・持ち替え中は何もしない（false）
func request(id: String) -> bool:
	if not IDS.has(id) or id == current or is_swapping():
		return false
	target = id
	swap_left = SWAP_FRAMES
	return true


# 1フレームぶん進める（player.gd が毎フレーム呼ぶ）
func tick() -> void:
	if is_swapping():
		swap_left -= 1
		if swap_left == SWAP_FRAMES / 2:
			shown = target
			_apply_visibility()
		if swap_left <= 0:
			current = target
			target = ""
			shown = current
			_apply_visibility()
			changed.emit(current)
	follow()


# 見た目を骨の位置に合わせる
func follow() -> void:
	if _skel == null or _body == null:
		return
	var fwd := -_body.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var right := Vector3.UP.cross(fwd).normalized()
	var s := _skel.global_basis.get_scale().x
	if _hand_idx != -1 and shown != "sword":
		var hand := _skel.global_transform * _skel.get_bone_global_pose(_hand_idx).origin
		var pos := hand + (right * HAND_OFFSET.x + Vector3.UP * HAND_OFFSET.y + fwd * HAND_OFFSET.z) * s
		# 素材の向き：銃身 +X → 体の前、上 +Z → 上、横 +Y → 左
		var g: Node3D = _guns[shown]
		g.global_transform = Transform3D(Basis(fwd, -right, Vector3.UP).scaled(Vector3.ONE * float(g.get_meta("scale"))), pos)
	if _back_idx != -1 and _back_sword != null and shown != "sword":
		var back := _skel.global_transform * _skel.get_bone_global_pose(_back_idx).origin
		# 背中に斜めに負う：剣の向き（+Y）を、右上から左下へ
		var blade := (Vector3.DOWN + right * 0.35).normalized()
		var side := fwd.cross(blade).normalized()
		_back_sword.global_transform = Transform3D(Basis(side, blade, side.cross(blade)).scaled(_hand_sword.global_basis.get_scale()), back - fwd * BACK_OFFSET * s)


func _apply_visibility() -> void:
	if _hand_sword != null:
		_hand_sword.visible = shown == "sword"
	if _back_sword != null:
		_back_sword.visible = shown != "sword"
	for id in _guns.keys():
		(_guns[id] as Node3D).visible = shown == id


func _make_gun(model_name: String, length: float) -> Node3D:
	var path := GUN_DIR + model_name + ".fbx"
	var holder := Node3D.new()
	holder.name = "Gun_" + model_name
	holder.top_level = true
	add_child(holder)
	if not ResourceLoader.exists(path):
		holder.set_meta("scale", 1.0)
		return holder
	var g: Node3D = (load(path) as PackedScene).instantiate()
	holder.add_child(g)
	# 素材の長さ（X の幅）から、length（m）になる拡大率を出す
	var box := AABB()
	var first := true
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var b := m.transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var sc := length / maxf(box.size.x, 0.0001)
	holder.set_meta("scale", sc)
	# 横と上は真ん中にそろえ、銃身の方向は、後ろの端から GRIP_RATIO の所を握る
	var c := box.get_center()
	g.position = -Vector3(box.position.x + box.size.x * GRIP_RATIO, c.y, c.z)
	return holder
