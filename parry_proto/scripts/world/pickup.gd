# Godot 4.7.2 / GDScript
# res://scripts/world/pickup.gd
#
# 拾えるアイテム（W-15 ④-2）
#  ・kind："heal"（回復薬。持ち歩いて、ボタンで使う）／"hp"（最大HP+10）／"stamina"（最大スタミナ+10）／"attack"（攻撃力+5%）
#          "ammo_ar"／"ammo_smg"／"ammo_sg"（弾の箱。予備の弾が増える。上限なら拾わない。G-04）
#  ・プレイヤーが PICK_DISTANCE（m）より近づくと拾う。回復薬を持てる数がいっぱいのときは拾わない
#  ・拾ったものは Discoveries が覚えていて、リトライしても戻らない
#  ・遠くから見つけられるように、光る玉と、うすい光の柱を出す（見た目だけ）
class_name Pickup
extends Node3D

const PICK_DISTANCE := 1.4     # これより近づくと拾う（m。高さの差は PICK_HEIGHT まで）
const PICK_HEIGHT := 2.0
const ORB_HEIGHT := 0.9        # 玉を浮かべる高さ（m）
const BEAM_HEIGHT := 6.0       # 光の柱の高さ（m）
# 種類ごとの色：回復＝緑、最大HP＝赤、最大スタミナ＝黄色、攻撃力＝白
const COLORS := {
	"heal": Color(0.45, 1.0, 0.55),
	"hp": Color(1.0, 0.35, 0.3),
	"stamina": Color(1.0, 0.85, 0.3),
	"attack": Color(0.85, 0.92, 1.0),
	# 弾の箱（G-04）：箱の形。AR＝橙、SMG＝水色、SG＝紫
	"ammo_ar": Color(1.0, 0.6, 0.25),
	"ammo_smg": Color(0.35, 0.85, 1.0),
	"ammo_sg": Color(0.75, 0.45, 1.0),
}

var kind := "heal"
var item_id := -1
var orb: MeshInstance3D


func _ready() -> void:
	add_to_group("pickups")
	if Discoveries.picked.has(item_id):
		queue_free()  # もう拾ってある（リトライで作り直したとき）
		return
	var col: Color = COLORS[kind]
	orb = MeshInstance3D.new()
	orb.name = "Orb"
	if kind.begins_with("ammo_"):
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.22, 0.26)
		orb.mesh = box
	else:
		var sphere := SphereMesh.new()
		sphere.radius = 0.16 if kind == "heal" else 0.2
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		orb.mesh = sphere
	orb.material_override = _glow_material(col, 1.0, 4.0)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.position = Vector3.UP * ORB_HEIGHT
	add_child(orb)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.08
	cyl.height = BEAM_HEIGHT
	cyl.radial_segments = 8
	cyl.rings = 1
	beam.mesh = cyl
	beam.material_override = _glow_material(col, 0.18, 1.5)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3.UP * (ORB_HEIGHT + BEAM_HEIGHT * 0.5)
	add_child(beam)


func _process(_delta: float) -> void:
	if orb != null:  # ゆっくり上下する（見た目だけ）
		orb.position.y = ORB_HEIGHT + sin(Time.get_ticks_msec() * 0.003 + item_id) * 0.1


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.state == Player.State.DEAD:
		return
	var d := player.global_position - global_position
	if Vector2(d.x, d.z).length() > PICK_DISTANCE or absf(d.y) > PICK_HEIGHT:
		return
	if kind == "heal" and Discoveries.heals >= Discoveries.HEAL_CARRY_MAX:
		return  # もう持てない（置いたままにする）
	if kind.begins_with("ammo_") and Discoveries.ammo_full(kind):
		return  # 予備の弾が上限（置いたままにする）
	Discoveries.take_item(item_id, kind)
	player.apply_upgrades(kind)
	queue_free()


static func _glow_material(col: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	return mat
