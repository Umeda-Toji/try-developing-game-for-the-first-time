# Godot 4.7.2 / GDScript
# res://scripts/combat/projectile.gd
#
# 魔法の弾（E-14 魔法使いが撃つ）
#  ・まっすぐ飛ぶ。1tick に speed / 60 m 進む（フレームで数える。敵だけのスロー中は遅くなる）
#  ・プレイヤーの被弾判定に当たったら player.receive_attack() を呼ぶ
#      ヒット → 消える ／ 回避・ジャスト回避 → すり抜けて飛び続ける
#      パリィ（攻撃の出始め）→ プレイヤーが on_parried() を呼ぶ → 撃った敵へ跳ね返る
#  ・跳ね返った弾は撃った敵を追いかけ、当たるとダメージと体幹ダメージ（REFLECT_*）
#  ・壁に当たるか、LIFETIME_FRAMES たったら消える（壁は毎tick、進む線の上を調べる。すり抜けない）
#  ・ノードはすべてコードで組み立てる
class_name Projectile
extends Area3D

const RADIUS := 0.3
const LIFETIME_FRAMES := 240           # 4秒たったら消える
const REFLECT_SPEED_MULT := 1.6        # 跳ね返った弾は速くなる
const REFLECT_DAMAGE := 20             # 跳ね返った弾が敵に当たったときのダメージ
const REFLECT_POSTURE := 35.0          # 〃 体幹ダメージ
const COLOR := Color(0.75, 0.4, 1.0)   # 紫に光る
const COLOR_REFLECTED := Color(0.3, 1.0, 1.0)  # 跳ね返った弾はパリィの水色

var speed := 8.0                       # m/秒（撃つ敵が決める）
var direction := Vector3.FORWARD
var attack := {}                       # プレイヤーに当たったときの攻撃の中身（ダメージなど）
var shooter: Node3D = null             # 撃った敵
var reflected := false
var age := 0

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _hit_done := {}                    # 同じ相手に2回当たらないように


func _ready() -> void:
	add_to_group("projectiles")
	collision_layer = 0
	collision_mask = 0
	set_collision_mask_value(1, true)  # 地形（壁）
	set_collision_mask_value(4, true)  # プレイヤーの被弾判定
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = RADIUS
	m.height = RADIUS * 2.0
	_mesh.mesh = m
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = COLOR
	_mat.emission_enabled = true
	_mat.emission = COLOR
	_mat.emission_energy_multiplier = 2.0
	_mesh.material_override = _mat
	add_child(_mesh)

	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	age += 1
	if age > LIFETIME_FRAMES:
		queue_free()
		return
	# 跳ね返った弾は、撃った敵を追いかける（逃げても当たる）
	if reflected and shooter != null and is_instance_valid(shooter):
		var to := shooter.global_position + Vector3.UP * 1.0 - global_position
		if to.length() > 0.01:
			direction = to.normalized()
	var ts := 1.0 if reflected else GameFeel.enemy_time_scale  # 敵だけのスロー中は、敵の弾も遅くなる
	var step := direction * speed * ts / 60.0
	# 壁（地形）を通り抜けないように、このtickで進む線の上に壁があるかを調べる
	# （当たり判定の箱どうしの重なりだけだと、速い弾や薄い壁ですり抜けることがある）
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step * 1.5 + direction * RADIUS, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		GameFeel.spark(hit["position"], GameFeel.SPARK_HIT)
		queue_free()
		return
	global_position += step


# プレイヤーがパリィしたときに呼ばれる（player.gd の _on_parry_success）
func on_parried(_by: Node) -> void:
	reflected = true
	speed *= REFLECT_SPEED_MULT
	direction = -direction
	_mat.albedo_color = COLOR_REFLECTED
	_mat.emission = COLOR_REFLECTED
	# これからは敵に当たる
	set_collision_mask_value(4, false)
	set_collision_mask_value(5, true)


func _on_area_entered(area: Area3D) -> void:
	if not area is Hurtbox:
		return
	var target: Node = (area as Hurtbox).entity
	if target == null or _hit_done.has(target) or not target.has_method("receive_attack"):
		return
	if reflected:
		if target != shooter:
			return  # 跳ね返った弾は撃った本人にだけ当たる
		_hit_done[target] = true
		target.receive_attack({"damage": REFLECT_DAMAGE, "posture": REFLECT_POSTURE, "hitstop": 6, "shake": 0.12}, self)
		GameFeel.spark(global_position, GameFeel.SPARK_HIT)
		queue_free()
		return
	_hit_done[target] = true
	var result: int = target.receive_attack(attack, self)
	if result == Combat.HitResult.HIT:
		GameFeel.spark(global_position, GameFeel.SPARK_HIT)
		queue_free()
	elif result == Combat.HitResult.PARRIED:
		_hit_done.clear()  # 跳ね返った後に撃った敵へ当てるため
	# 回避・ジャスト回避：すり抜けて飛び続ける


func _on_body_entered(_body: Node3D) -> void:
	queue_free()  # 壁に当たった
