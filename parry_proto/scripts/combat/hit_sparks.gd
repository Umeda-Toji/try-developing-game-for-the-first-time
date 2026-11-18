# Godot 4.7.2 / GDScript
# res://scripts/combat/hit_sparks.gd
#
# ヒット・パリィ・体幹ブレイクの火花（F-06）
#  ・GameFeel.spark(pos, kind) が呼ばれたら、その場所に1回だけ火花を飛び散らせる
#  ・内蔵GPUでも軽いように CPUParticles3D を使い、粒は少なめ・寿命は短め
#  ・出し終わった火花は自動で消す
#  ・見た目は下の SPARKS 表の数字を変えるだけで調整できる
class_name HitSparks
extends Node3D

# 種類ごとの見た目
#   amount   粒の数         lifetime  寿命（秒。見た目だけなので秒でよい）
#   speed    飛び散る速さ    size      粒の大きさ（m）
#   color    色             gravity   下へ落ちる強さ
const SPARKS := {
	"hit": {"amount": 10, "lifetime": 0.25, "speed": 5.0, "size": 0.07,
		"color": Color(1.0, 0.6, 0.2), "gravity": 9.0},
	"parry": {"amount": 24, "lifetime": 0.35, "speed": 9.0, "size": 0.13,
		"color": Color(0.75, 1.0, 1.0), "gravity": 4.0},
	"break": {"amount": 28, "lifetime": 0.5, "speed": 7.0, "size": 0.14,
		"color": Color(1.0, 0.9, 0.25), "gravity": 6.0},
}

# テスト用：種類ごとに何回出したか
var spawn_counts := {}

var _meshes := {}  # 種類ごとの粒の形と色（毎回作らないよう、最初に1回だけ作っておく）
var _scale_curve: Curve


func _ready() -> void:
	# 粒は時間とともに小さくなって消える
	_scale_curve = Curve.new()
	_scale_curve.add_point(Vector2(0.0, 1.0))
	_scale_curve.add_point(Vector2(1.0, 0.0))
	for kind in SPARKS.keys():
		var cfg: Dictionary = SPARKS[kind]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # 光の影響を受けず、いつも明るい
		mat.albedo_color = cfg["color"]
		var mesh := BoxMesh.new()
		var s: float = cfg["size"]
		mesh.size = Vector3(s, s, s)
		mesh.material = mat
		_meshes[kind] = mesh
		spawn_counts[kind] = 0
	GameFeel.spark_requested.connect(_on_spark_requested)


func _on_spark_requested(pos: Vector3, kind: String) -> void:
	if not SPARKS.has(kind):
		push_warning("知らない火花の種類: " + kind)
		return
	var cfg: Dictionary = SPARKS[kind]
	var p := CPUParticles3D.new()
	p.mesh = _meshes[kind]
	p.amount = cfg["amount"]
	p.lifetime = cfg["lifetime"]
	p.one_shot = true
	p.explosiveness = 1.0               # 全部の粒を同時に出す＝パッと散る
	p.direction = Vector3.UP
	p.spread = 180.0                    # 全方向へ
	p.initial_velocity_min = float(cfg["speed"]) * 0.5
	p.initial_velocity_max = float(cfg["speed"])
	p.gravity = Vector3.DOWN * float(cfg["gravity"])
	p.scale_amount_curve = _scale_curve
	p.finished.connect(p.queue_free)    # 出し終わったら消す
	add_child(p)
	p.global_position = pos
	p.emitting = true
	spawn_counts[kind] = int(spawn_counts[kind]) + 1


# 今、画面に残っている火花の数（テスト用）
func active_count() -> int:
	return get_child_count()
