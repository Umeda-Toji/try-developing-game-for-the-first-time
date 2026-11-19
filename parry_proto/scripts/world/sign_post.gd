# Godot 4.7.2 / GDScript
# res://scripts/world/sign_post.gd
#
# 看板・端末（W-08。WORLD_PROMPT.md のステップE）
#  ・エリアに置く小さな看板（柱と板。手帳のように地面に置く物もある）
#  ・プレイヤーが SHOW_DISTANCE（m）より近づくと、上に短い文章（docs/WORLD.md の看板・端末の文章）が浮かぶ
#  ・離れると、ゆっくり消える（見た目だけ。判定には関係しない）
#  ・ノードはすべてコードで組み立てる
class_name SignPost
extends Node3D

const SHOW_DISTANCE := 4.0       # この距離まで近づくと文章が出る（m）
const FADE_SPEED := 4.0          # 出る・消える速さ（1秒あたりの不透明度の変化）
const TEXT_HEIGHT := 2.3         # 文章を浮かべる高さ（m）
const FONT_SIZE := 48
const PIXEL_SIZE := 0.006        # 文字の大きさ（1ピクセルあたりの m）
const TEXT_WIDTH := 900.0        # 1行の幅（ピクセル）。これを超えると折り返す
const TEXT_COLOR := Color(0.95, 0.93, 0.86)
const MOTE_HEIGHT := 1.1         # 綿毛を浮かべる高さ（m）

var text := ""                   # 表示する文章（80字以内）
var kind := "post"               # "post"：柱と板の看板 ／ "note"：地面に置いた手帳
var fragment_id := -1            # 記録の断片（W-15）の番号。-1 は普通の看板
var mote: MeshInstance3D         # 記録の断片の上に浮かぶ、白く光る綿毛（遠くから見つけられるように）
var label: Label3D
var shown := 0.0                 # 今の不透明度（0〜1）


func _ready() -> void:
	add_to_group("lore_fragments" if fragment_id >= 0 else "sign_posts")
	_build_marker()
	if fragment_id >= 0:
		_build_mote()
	label = Label3D.new()
	label.name = "Text"
	label.text = text
	label.font_size = FONT_SIZE
	label.pixel_size = PIXEL_SIZE
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY  # 日本語は単語の区切りがないので、どこでも折り返す
	label.width = TEXT_WIDTH
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # いつもカメラの方を向く
	label.no_depth_test = true  # 柱や壁に隠れず、いつも手前に描く（近づいたときだけ出るので、遠くから透けて見えることはない）
	label.modulate = Color(TEXT_COLOR, 0.0)
	label.outline_modulate = Color(0, 0, 0, 0.0)
	label.outline_size = 10
	label.position = Vector3.UP * TEXT_HEIGHT
	label.visible = false
	add_child(label)


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and player.global_position.distance_to(global_position) < SHOW_DISTANCE
	shown = move_toward(shown, 1.0 if near else 0.0, FADE_SPEED * delta)
	if mote != null:
		mote.position.y = MOTE_HEIGHT + sin(Time.get_ticks_msec() * 0.002) * 0.12  # ゆっくり上下（見た目だけ）
		mote.visible = not Discoveries.fragments.has(fragment_id)
	label.visible = shown > 0.0
	if near and fragment_id >= 0:
		Discoveries.find_fragment(fragment_id)
	label.modulate.a = shown
	label.outline_modulate.a = shown * 0.8


# 近づけば読める物だとわかるように、看板（柱と板）か手帳を置く
func _build_marker() -> void:
	if kind == "note":
		_part(Vector3(0.35, 0.06, 0.25), Vector3(0, 0.03, 0), Color(0.45, 0.38, 0.3))
		return
	_part(Vector3(0.1, 1.4, 0.1), Vector3(0, 0.7, 0), Color(0.55, 0.5, 0.45))
	_part(Vector3(0.9, 0.6, 0.06), Vector3(0, 1.35, 0.06), Color(0.8, 0.78, 0.72))


# 白く光る綿毛：読むと消える
func _build_mote() -> void:
	mote = MeshInstance3D.new()
	mote.name = "Mote"
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 8
	sphere.rings = 4
	mote.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.98, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.95, 0.75)
	mat.emission_energy_multiplier = 3.0
	mote.material_override = mat
	mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mote.position = Vector3.UP * MOTE_HEIGHT
	add_child(mote)


func _part(size: Vector3, pos: Vector3, tint: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = ShapeKit.beveled_box(size, 0.02)
	mi.material_override = WorldMaterials.make("rubble", tint)
	mi.position = pos
	add_child(mi)
