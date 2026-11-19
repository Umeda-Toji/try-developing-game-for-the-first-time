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
#  ・撃つ・反動・リロード（G-03。5b）：fire() で弾倉から1発使い、粒の数だけ光線（レイ）を飛ばす
#    地形（層1）と敵の被弾判定（層5）に当たる。壁の向こうには当たらない。胞子玉は線の近くを通ると消える
#    敵には ダメージ（攻撃力の強化を掛ける）と、ダメージの半分の体幹。銃では敵は怯まない（no_flinch）
#    弾の数は Discoveries.ammo（セーブに残る）。最初は弾倉ぶんだけ、予備は0（5c で街で拾う）
#  ・数値は GUNS にまとめてある（11/19 決定）
class_name Weapons
extends Node3D

signal changed(id: String)   # 持ち替えが終わった
signal fired(info: Dictionary)   # 撃った（テスト・表示用）

const SWAP_FRAMES := 20
const IDS := ["sword", "ar", "smg", "sg"]
const LABELS := {"sword": "剣", "ar": "AR", "smg": "SMG", "sg": "SG"}
const GUN_DIR := "res://models/guns/"
# 銃の数値（11/19 決定）。フレームは物理フレーム。spread は度（腰だめ／構え）。range は m。pickup は弾の箱1つで増える予備の弾（G-04）
const GUNS := {
	"ar": {"model": "AssaultRifle_1", "length": 0.85, "damage": 2, "pellets": 1, "interval": 6, "mag": 30, "reserve_max": 120,
		"recoil": "small", "spread_hip": 2.5, "spread_aim": 0.6, "range": 60.0, "reload": 120, "pickup": 30},
	"smg": {"model": "SubmachineGun_1", "length": 0.6, "damage": 1, "pellets": 1, "interval": 4, "mag": 35, "reserve_max": 140,
		"recoil": "tiny", "spread_hip": 4.0, "spread_aim": 1.5, "range": 35.0, "reload": 100, "pickup": 35},
	"sg": {"model": "Shotgun_1", "length": 0.95, "damage": 1, "pellets": 8, "interval": 50, "mag": 6, "reserve_max": 36,
		"recoil": "large", "spread_hip": 7.0, "spread_aim": 5.0, "range": 15.0, "reload": 150, "pickup": 6},
}
const HAND_BONE := "hand_r"
const BACK_BONE := "spine_03"
const HAND_OFFSET := Vector3(0.0, 0.0, 0.05)   # 手の骨から、銃の握りへのずらし（体の向き：x 右、y 上、z 前。m）
const BACK_OFFSET := 0.16                      # 背中の骨から、後ろへのずらし（m）
const GRIP_RATIO := 0.3                        # 銃の後ろの端から、握る所までの割合
const MUZZLE_RATIO := 0.7                      # 握る所から銃口までの長さ（銃の長さに対する割合）
# 反動：[縦に跳ねる量（ラジアン）, 横に揺れる幅（ラジアン）]
const RECOIL := {"tiny": [0.006, 0.003], "small": [0.012, 0.004], "large": [0.05, 0.012]}
const POSTURE_RATIO := 0.5                     # 体幹は、ダメージのこの割合だけ削る
const PROJECTILE_HIT_RADIUS := 0.35            # 胞子玉と弾の線がこれより近いと、胞子玉が消える（m）
const TRACER_FRAMES := 10                      # 弾の光の線を見せる長さ（G-07。11/19 3 → 10）
const TRACER_WIDTH := 0.05                     # 弾の光の線の太さ（m）
const IMPACT_FRAMES := 8                       # 当たった所の小さな火花を見せる長さ
# 一人称で構えた銃の位置（カメラから見て：右、下、前。m）と、反動で銃が跳ねる量
const VIEW_OFFSET := Vector3(0.2, -0.17, -0.5)
const VIEW_KICK_BACK := 0.06
const VIEW_KICK_FRAMES := 6
const HIT_MASK := 1 | 16                       # 地形（層1）と敵の被弾判定（層5）

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
var cooldown := 0           # 次に撃てるまでのフレーム
var reload_left := 0        # リロードの残りフレーム（0＝リロードしていない）
var _tracers: Array = []    # [光の線, 残りフレーム, 最初のフレーム数]
var first_person := false   # 一人称で構えている（目の前に銃を構える。体と背中の剣は隠す）
var _kick := 0              # 反動で銃が跳ねている残りフレーム


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
	cancel_reload()  # 持ち替えるとリロードはやめる
	return true


# 1フレームぶん進める（player.gd が毎フレーム呼ぶ）
func tick() -> void:
	if cooldown > 0:
		cooldown -= 1
	if reload_left > 0:
		reload_left -= 1
		if reload_left == 0:
			_finish_reload()
	_update_tracers()
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
	if first_person and shown != "sword":
		_follow_view()
	elif _hand_idx != -1 and shown != "sword":
		var hand := _skel.global_transform * _skel.get_bone_global_pose(_hand_idx).origin
		var pos := hand + (right * HAND_OFFSET.x + Vector3.UP * HAND_OFFSET.y + fwd * HAND_OFFSET.z) * s
		# 素材の向き：銃身 +X → 体の前、上 +Z → 上、横 +Y → 左
		var g: Node3D = _guns[shown]
		g.global_transform = Transform3D(Basis(fwd, -right, Vector3.UP).scaled(Vector3.ONE * float(g.get_meta("scale"))), pos)
	if _back_sword != null:
		_back_sword.visible = shown != "sword" and not first_person
	if _back_idx != -1 and _back_sword != null and shown != "sword":
		var back := _skel.global_transform * _skel.get_bone_global_pose(_back_idx).origin
		# 背中に斜めに負う：剣の向き（+Y）を、右上から左下へ
		var blade := (Vector3.DOWN + right * 0.35).normalized()
		var side := fwd.cross(blade).normalized()
		_back_sword.global_transform = Transform3D(Basis(side, blade, side.cross(blade)).scaled(_hand_sword.global_basis.get_scale()), back - fwd * BACK_OFFSET * s)


# ---------------------------------------------------------
# 弾・リロード・撃つ（G-03）
# ---------------------------------------------------------
func ammo(id: String) -> Dictionary:
	return Discoveries.ammo_of(id)


func is_reloading() -> bool:
	return reload_left > 0


func can_fire() -> bool:
	return is_gun() and not is_swapping() and not is_reloading() and cooldown <= 0


# リロードを始める。弾倉が満タン・予備が無い・持ち替え中なら始めない
func start_reload() -> bool:
	if not is_gun() or is_swapping() or is_reloading():
		return false
	var a := ammo(current)
	if int(a["mag"]) >= int(GUNS[current]["mag"]) or int(a["reserve"]) <= 0:
		return false
	reload_left = int(GUNS[current]["reload"])
	GameFeel.play_sound("reload_" + current)
	return true


# 回避したら、リロードはやり直し（最初から数え直す）
func restart_reload() -> void:
	if is_reloading():
		reload_left = int(GUNS[current]["reload"])


func cancel_reload() -> void:
	reload_left = 0


func _finish_reload() -> void:
	var a := ammo(current)
	var take := mini(int(GUNS[current]["mag"]) - int(a["mag"]), int(a["reserve"]))
	a["mag"] = int(a["mag"]) + take
	a["reserve"] = int(a["reserve"]) - take


func muzzle_position() -> Vector3:
	if not is_gun():
		return global_position
	var g: Node3D = _guns[current]
	# 銃身の向き（+X）の先が銃口
	return g.global_position + g.global_basis.x.normalized() * float(GUNS[current]["length"]) * MUZZLE_RATIO


# 撃つ。aim_point：狙う所（世界）。aiming：構えているか。attack_mult：攻撃力の強化。exclude：当てない物の RID
# 戻り値：{"shot": 撃ったか, "empty": 弾切れだったか, "hits": 敵に当たった数, "enemies": 当たった敵, "projectiles": 消した胞子玉の数}
func fire(aim_point: Vector3, aiming: bool, attack_mult: float, exclude: Array) -> Dictionary:
	var info := {"shot": false, "empty": false, "hits": 0, "enemies": [], "projectiles": 0, "pellets": 0}
	if not can_fire():
		return info
	var g: Dictionary = GUNS[current]
	var a := ammo(current)
	cooldown = int(g["interval"])
	if int(a["mag"]) <= 0:
		info["empty"] = true
		GameFeel.play_sound("gun_empty")
		return info
	a["mag"] = int(a["mag"]) - 1
	var from := muzzle_position()
	var base := (aim_point - from).normalized()
	var spread := deg_to_rad(float(g["spread_aim"] if aiming else g["spread_hip"]))
	var space := get_world_3d().direct_space_state
	var dmg := int(round(float(g["damage"]) * attack_mult))
	for i in int(g["pellets"]):
		var dir := _spread_dir(base, spread)
		var to := from + dir * float(g["range"])
		var q := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, exclude)
		q.collide_with_areas = true
		var hit := space.intersect_ray(q)
		var end: Vector3 = to if hit.is_empty() else hit["position"]
		# 胞子玉：弾の線の近くを通っていれば消える（跳ね返した胞子玉は消さない）
		for pr in get_tree().get_nodes_in_group("projectiles"):
			var p3 := (pr as Node3D).global_position
			if not bool(pr.get("reflected")) and Geometry3D.get_closest_point_to_segment(p3, from, end).distance_to(p3) < PROJECTILE_HIT_RADIUS:
				pr.queue_free()
				info["projectiles"] = int(info["projectiles"]) + 1
		if not hit.is_empty() and hit["collider"] is Hurtbox:
			var ent: Node = (hit["collider"] as Hurtbox).entity
			if ent != null and ent != _body and ent.has_method("receive_attack"):
				var r: int = ent.receive_attack({"damage": dmg, "posture": float(g["damage"]) * POSTURE_RATIO, "hitstop": 0, "no_flinch": true}, _body)
				if r == Combat.HitResult.HIT:
					info["hits"] = int(info["hits"]) + 1
					(info["enemies"] as Array).append(ent)
		if GameSettings.tracers:
			_add_tracer(from, end)
			if not hit.is_empty():
				_add_impact(end)
		info["pellets"] = int(info["pellets"]) + 1
	info["shot"] = true
	_kick = VIEW_KICK_FRAMES
	GameFeel.play_sound("shot_" + current)
	fired.emit(info)
	return info


# 反動：[縦, 横]（ラジアン）
func recoil() -> Array:
	return RECOIL[GUNS[current]["recoil"]] if is_gun() else [0.0, 0.0]


# 広がり（円すいの半分の角度）の中で、ランダムな向き
static func _spread_dir(base: Vector3, spread: float) -> Vector3:
	if spread <= 0.0:
		return base
	var side := base.cross(Vector3.UP)
	if side.length() < 0.01:
		side = base.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(base).normalized()
	var r := sqrt(randf()) * spread
	var a := randf() * TAU
	return (base + (side * cos(a) + up * sin(a)) * tan(r)).normalized()


func _add_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Tracer"
	mi.add_to_group("tracers")
	var box := BoxMesh.new()
	box.size = Vector3(TRACER_WIDTH, TRACER_WIDTH, length)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.8, 0.45, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.4)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), (from + to) * 0.5)
	_tracers.append([mi, TRACER_FRAMES, TRACER_FRAMES])


# 当たった所の小さな火花（光る玉が小さくなって消える）
func _add_impact(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Impact"
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	sphere.radial_segments = 8
	sphere.rings = 4
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.85, 0.5, 1.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	_tracers.append([mi, IMPACT_FRAMES, IMPACT_FRAMES])


# 光の線と火花：だんだん薄くなって消える
func _update_tracers() -> void:
	for t in _tracers.duplicate():
		t[1] = int(t[1]) - 1
		var node := t[0] as GeometryInstance3D
		if int(t[1]) <= 0 or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_tracers.erase(t)
			continue
		var mat := node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = 0.9 * float(t[1]) / float(t[2])


# 一人称：カメラの右下に、銃身をカメラの前へ向けて構える。撃つと少し後ろへ跳ねて戻る
func _follow_view() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var k := float(_kick) / float(VIEW_KICK_FRAMES)
	if _kick > 0:
		_kick -= 1
	var cb := cam.global_basis.orthonormalized()
	var off := VIEW_OFFSET + Vector3(0, 0, VIEW_KICK_BACK * k)
	var g: Node3D = _guns[shown]
	# 素材の向き：銃身 +X → カメラの前（−Z）、上 +Z → カメラの上（+Y）、横 +Y → カメラの左（−X）
	var basis := Basis(-cb.z, -cb.x, cb.y).rotated(cb.x, 0.08 * k)
	g.global_transform = Transform3D(basis.scaled(Vector3.ONE * float(g.get_meta("scale"))), cam.global_transform * off)


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
