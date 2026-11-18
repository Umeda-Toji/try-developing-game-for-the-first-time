# Godot 4.7.2 / GDScript
# res://scripts/visual/character_model.gd
#
# キャラクターの3Dモデルとアニメーション（P-16）
#  ・モデルとアニメーションは Quaternius の CC0 素材（models/ フォルダ）
#  ・アニメーションは「見た目だけ」。当たり判定のタイミングは今まで通り ATTACKS 表のフレーム数で決まる
#  ・AnimationPlayer は自動では進めない（手動モード）。持ち主が毎tick「今このポーズ」と指定する
#    → ヒットストップ中はポーズが止まり、スローも物理tickに合わせて自然に遅くなる
#  ・状態の色（パリィ受付の水色など）は、モデルの上に色を重ねて表す（shaders/tint_overlay.gdshader）
#  ・アニメーション名は「ライブラリ名/アニメ名」で指定する（例 "ual2/Sword_Regular_A"）
#    ual1 = Universal Animation Library、ual2 = Universal Animation Library 2
class_name CharacterModel
extends Node3D

const TICK_SEC := 1.0 / 60.0  # 1tick ぶんの時間（ポーズを進めるときに使う。判定には使わない）
const ANIMATION_FILES := {
	"ual1": "res://models/animations/UAL1_Standard.glb",
	"ual2": "res://models/animations/UAL2_Standard.glb",
}
const OVERLAY_SHADER := preload("res://shaders/tint_overlay.gdshader")
# 剣（見た目だけ。当たり判定は Hitbox の箱のまま）
#  モデルは Quaternius の Medieval Weapons（CC0）。素材の剣は +Y 方向に刃が伸びていて、長さは約5.4（単位はばらばら）
#  → attach_sword で、指定した長さ（m）になるように縮める
const SWORD_BONE := "hand_r"
const SWORD_MODEL_LENGTH := 5.4                    # 素材の剣の長さ（拡大・縮小の計算に使う）
const SWORD_OFFSET := Vector3(0.0, 0.08, 0.0)      # 手の骨（手首）から握る位置までのずらし（m）。絵を見て合わせる
const SWORD_ROTATION_DEG := Vector3(0, 0, 0)

# アニメーションは全キャラで共通なので、1回だけ読み込んで使い回す
static var _libraries := {}
static var _head_meshes := {}  # 切り出した頭（同じモデルなら使い回す）
static var _colored_materials := {}  # 塗り替えた材質（同じ色なら使い回す）
const HEAD_BONES: Array[String] = ["Head", "neck_01"]  # 顔を借りるときに切り出す骨
const HAIR_COLOR := Color(0.28, 0.18, 0.1)  # 眉毛の色（こげ茶）

var anim_player: AnimationPlayer
var current_clip := ""
var current_time := 0.0
var _overlay: ShaderMaterial
var _loop_time := 0.0


# model_path：キャラクターのモデル（.gltf / .glb）
# height：この高さ（m）になるように拡大・縮小する。0 なら素材の大きさのまま
# head_path：服のモデル（顔が無い）を使うときに、顔を借りてくるモデル。"" なら借りない
func setup(model_path: String, height: float = 0.0, head_path: String = "") -> void:
	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	model.name = "Mesh"
	model.rotation.y = PI  # 素材は +Z 向き、このゲームの前は -Z なので半回転させる
	add_child(model)
	if head_path != "":
		_attach_head(model, head_path)
	# アニメーション素材の中のマネキンを使うときは、素材に付いている AnimationPlayer を外す（下で自分のを付ける）
	for old in model.find_children("*", "AnimationPlayer", true, false):
		old.get_parent().remove_child(old)
		old.free()
	if height > 0.0:
		var top := 0.0
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var box := (mi as MeshInstance3D).get_aabb()
			top = maxf(top, box.position.y + box.size.y)
		if top > 0.0:
			scale = Vector3.ONE * (height / top)

	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	model.add_child(anim_player)  # root_node は ".."（＝ model）。トラックは "Armature/Skeleton3D:骨" を指す
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for lib_name in ANIMATION_FILES.keys():
		anim_player.add_animation_library(lib_name, _get_library(lib_name))

	_overlay = ShaderMaterial.new()
	_overlay.shader = OVERLAY_SHADER
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _overlay


# 右手に剣を持たせる（素材のキャラクターは何も持っていないので、別の剣のモデルを付ける）
#  BoneAttachment3D で手の骨にくっつけるので、アニメーションに合わせて一緒に動く
#  sword_path：武器のモデル、length：武器の長さ（m。キャラクターを拡大していれば、その分さらに大きくなる）
#  model_length：素材の武器の長さ（剣以外の武器は長さが違うので渡す）
#  bone：持たせる手の骨（左手に持たせるときは "hand_l"。名前は "Sword_L" になる）
func attach_sword(sword_path: String, length: float, model_length: float = SWORD_MODEL_LENGTH, bone: String = SWORD_BONE) -> void:
	var skel := find_child("Skeleton3D", true, false) as Skeleton3D
	var left := bone != SWORD_BONE
	var att := BoneAttachment3D.new()
	att.name = "SwordAttach_L" if left else "SwordAttach"
	att.bone_name = bone
	skel.add_child(att)
	var sword: Node3D = (load(sword_path) as PackedScene).instantiate()
	sword.name = "Sword_L" if left else "Sword"
	sword.position = SWORD_OFFSET
	sword.rotation_degrees = SWORD_ROTATION_DEG
	sword.scale = Vector3.ONE * (length / model_length)
	att.add_child(sword)
	for mi in sword.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _overlay  # 状態の色は剣にも重ねる


# 服のモデルには顔が無いので、素体モデル（head_path）から「頭の骨で動く部分」だけを切り出して付ける
#  ・素体と服は同じ骨組み（骨の名前が同じ）なので、切り出した頭は服の骨組みでそのまま動く
#  ・頭の骨（HEAD_BONES）の影響が半分以上の頂点だけでできた三角形を残す
func _attach_head(model: Node3D, head_path: String) -> void:
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var src: Node = (load(head_path) as PackedScene).instantiate()
	for mi in src.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin == null:
			continue
		var head := MeshInstance3D.new()
		head.name = "Head_" + m.name
		head.mesh = _head_only_mesh(m.mesh as ArrayMesh, m.skin)
		head.skin = m.skin
		skel.add_child(head)
		head.skeleton = NodePath("..")
	src.free()


static func _head_only_mesh(src: ArrayMesh, skin: Skin) -> ArrayMesh:
	var key := "%s|%d" % [src.resource_path, src.get_instance_id()]
	if _head_meshes.has(key):
		return _head_meshes[key]
	# スキンの何番目が頭の骨か
	var head_binds := {}
	for i in skin.get_bind_count():
		if HEAD_BONES.has(String(skin.get_bind_name(i))):
			head_binds[i] = true
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)  # 1頂点あたりの骨の数（4 か 8）
		var is_head := PackedByteArray()
		is_head.resize(verts.size())
		for v in verts.size():
			var w := 0.0
			for k in per:
				if head_binds.has(bones[v * per + k]):
					w += weights[v * per + k]
			is_head[v] = 1 if w >= 0.5 else 0
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			if is_head[idx[t]] == 1 and is_head[idx[t + 1]] == 1 and is_head[idx[t + 2]] == 1:
				kept.append(idx[t])
				kept.append(idx[t + 1])
				kept.append(idx[t + 2])
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		# 追加のデータ（CUSTOM0〜3）は使わないので外す（形式の指定が要り、そのままでは作り直せないため）
		for c in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[c] = null
		var flags := src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		var mat := src.surface_get_material(s)
		# 眉毛（髪のマテリアル）のテクスチャは明るい灰色（色を掛けて使う前提）で、そのままだと白く見える → 髪の色を掛ける
		if mat is BaseMaterial3D and mat.resource_name.begins_with("MI_Hair"):
			mat = mat.duplicate()
			(mat as BaseMaterial3D).albedo_color = HAIR_COLOR
		out.surface_set_material(out.get_surface_count() - 1, mat)
	_head_meshes[key] = out
	return out


static func _get_library(lib_name: String) -> AnimationLibrary:
	if _libraries.has(lib_name):
		return _libraries[lib_name]
	var src: Node = (load(ANIMATION_FILES[lib_name]) as PackedScene).instantiate()
	var ap := src.get_node("AnimationPlayer") as AnimationPlayer
	var lib: AnimationLibrary = ap.get_animation_library("").duplicate(true)
	src.free()
	_libraries[lib_name] = lib
	return lib


func has_clip(clip: String) -> bool:
	return anim_player.has_animation(clip)


func clip_length(clip: String) -> float:
	return anim_player.get_animation(clip).length


# clip を time 秒の位置のポーズにする
func pose_at(clip: String, time: float) -> void:
	if clip != current_clip:
		current_clip = clip
		anim_player.play(clip)
	current_time = time
	anim_player.seek(time, true)


# ループするアニメーション（待機・走り）を 1tick ぶん進める。speed は再生の速さの倍率
func pose_loop(clip: String, speed: float = 1.0) -> void:
	if clip != current_clip:
		_loop_time = 0.0
	else:
		_loop_time += TICK_SEC * speed
	pose_at(clip, fmod(_loop_time, clip_length(clip)))


# 攻撃などの「決まったフレーム数で終わる動き」のポーズ
#  frame / total_frames の進み具合を、アニメの from 秒〜to 秒に当てはめる
#  key_frame と key_time を渡すと、そのフレームでちょうど key_time 秒のポーズになるように2区間に分けて当てはめる
#  （攻撃の当たり始めのフレームで、剣を振り切る瞬間を見せるため）
func pose_frames(clip: String, frame: int, total_frames: int, from: float, to: float, key_frame: int = -1, key_time: float = -1.0) -> void:
	var f := clampf(float(frame), 0.0, float(total_frames))
	var t: float
	if key_frame > 0 and key_frame < total_frames and key_time > from and key_time < to:
		if f <= key_frame:
			t = lerpf(from, key_time, f / float(key_frame))
		else:
			t = lerpf(key_time, to, (f - key_frame) / float(total_frames - key_frame))
	else:
		t = lerpf(from, to, f / float(maxi(total_frames, 1)))
	pose_at(clip, t)


# 色違いのテクスチャに替える（服の色違い用）。old_name を含む名前のテクスチャを new_path に置き換える
func replace_texture(old_name: String, new_path: String) -> void:
	var tex: Texture2D = load(new_path)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i) as BaseMaterial3D
			if src != null and src.albedo_texture != null and src.albedo_texture.resource_path.contains(old_name):
				var mat := src.duplicate() as BaseMaterial3D
				mat.albedo_texture = tex
				m.set_surface_override_material(i, mat)


# 体の色を塗り替える（テクスチャの無いマネキン用。テクスチャがあるモデルだと色が掛け合わされる）
func set_body_color(color: Color) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var in_weapon := false
		for w in ["Sword", "Sword_L"]:
			var sword := find_child(w, true, false)
			if sword != null and sword.is_ancestor_of(m):
				in_weapon = true
		if in_weapon:
			continue  # 武器は塗らない
		for i in m.mesh.get_surface_count():
			var src := m.get_active_material(i)
			if src is BaseMaterial3D:
				m.set_surface_override_material(i, _colored_material(src as BaseMaterial3D, color))


# 塗り替えた材質は、元の材質と色が同じなら使い回す
# （同じモデルを何体も出すときに、1体ずつ複製すると Godot がエラーを出すことがあったため）
static func _colored_material(src: BaseMaterial3D, color: Color) -> BaseMaterial3D:
	var key := "%d|%s" % [src.get_instance_id(), color.to_html()]
	if not _colored_materials.has(key):
		var mat := src.duplicate() as BaseMaterial3D
		mat.albedo_color = color
		_colored_materials[key] = mat
	return _colored_materials[key]


# 状態の色を重ねる。strength 0 で元の見た目
func set_tint(color: Color, strength: float) -> void:
	_overlay.set_shader_parameter("tint", color)
	_overlay.set_shader_parameter("strength", strength)


func tint_strength() -> float:
	return _overlay.get_shader_parameter("strength")
