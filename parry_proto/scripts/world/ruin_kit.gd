# Godot 4.7.2 / GDScript
# res://scripts/world/ruin_kit.gd
#
# 廃墟の見た目を自動で作る（W-06）。すべて箱の組み合わせ。外部の素材は使わない
#  ・崩れたビル：窓（暗い箱。ところどころ板でふさがれている）、各階の帯、崩れてギザギザの屋上
#  ・植物：壁を垂れるツタと葉（葉は葉を描いた画像の板。shaders/foliage.gdshader）
#  ・地面の草・植物・瓦礫・木は nature_kit.gd（11/18 に箱から置き換えた）
#  ・屋上の塊・帯・柱は、角を削った箱（ShapeKit.beveled_box）
#  ・建物の細かい形（W-10）：窓枠・窓台・へこんだ窓の奥、ベランダ（手すり付き。壊れたものもある）、
#    壁の穴（暗いへこみ＋縁の崩れた塊＋むき出しの鉄筋）、屋上から突き出た崩れた床（鉄筋付き）
#  ・放置された車（塗装があせて錆びた車体・窓・タイヤ。ひっくり返った車もある）、倒れた看板
#  ・乱数はシード固定（SEED）。毎回同じ街になる。SEED を変えると別の街並みになる
#  ・数の多い物は MultiMeshInstance3D でまとめて描く（1つの描画で何百個も描ける）
#  ・小物には当たり判定を付けない（歩く邪魔にならず、軽い）。遠くの小物は visibility_range で消す
class_name RuinKit
extends RefCounted

const SEED := 20261118

# ---- 建物 ----
const FLOOR_HEIGHT := 3.0           # 1階ぶんの高さ（窓の段・帯の間隔）
const WINDOW_SIZE := Vector3(1.1, 1.5, 0.14)
const WINDOW_SPACING := 2.6
const WINDOW_SKIP_RATE := 0.18      # 窓を描かない割合（崩れて壁だけ）
const WINDOW_BOARDED_RATE := 0.12   # 板でふさがれた窓の割合
const LEDGE_THICKNESS := 0.16
const VINES_PER_METER := 0.45       # 壁の幅1mあたりのツタの本数
const VINE_LEAF_STEP := 0.55        # ツタに付く葉の間隔（m）
const FRAME_THICKNESS := 0.09       # 窓枠の太さ（m）
const BALCONY_RATE := 0.12          # ベランダを付ける窓の割合（2階より上）
const BALCONY_BROKEN_RATE := 0.35   # 壊れて傾いたベランダの割合
const HOLES_MAX := 3                # 1つの壁の穴の数（最大）
const COLLAPSED_FLOOR_RATE := 0.55  # 屋上から崩れた床が突き出ている建物の割合
const CAR_PAINTS := [Color(0.55, 0.62, 0.7), Color(0.68, 0.38, 0.32), Color(0.85, 0.83, 0.78), Color(0.4, 0.46, 0.36), Color(0.7, 0.62, 0.45)]
# ---- 描く距離 ----
const MEDIUM_VISIBLE_DISTANCE := 70.0   # 窓・ツタ・葉
const TILE := 80.0                      # 飾りをまとめて描くマスの大きさ（m）。遠いマスは描かない

var rng := RandomNumberGenerator.new()
var _items := {}     # 種類 → {"t": Array[Transform3D], "c": Array[Color]}
var stats := {}      # 種類 → 数（テスト・報告用）


func _init() -> void:
	rng.seed = SEED


# ---------------------------------------------------------
# 建物の飾り
# ---------------------------------------------------------
# face：窓を付ける面の向き（外向き）。Vector3.ZERO なら窓なし。ground_y：その建物の前の地面の高さ
# roof：崩れた屋上の塊も足すか（同じ建物の2つ目の面からは false にする）
func decorate_building(center: Vector3, size: Vector3, face: Vector3, ground_y: float, tint: Color, roof: bool = true) -> void:
	var top := center.y + size.y * 0.5
	var bottom := center.y - size.y * 0.5
	# 屋上：崩れてギザギザ（上に高さの違う塊をいくつか載せる）
	var blocks := rng.randi_range(2, 5) if roof else 0
	for i in blocks:
		var w := rng.randf_range(1.0, 3.2)
		var d := rng.randf_range(1.0, maxf(size.z, size.x) * 0.4)
		var h := rng.randf_range(0.4, 2.6)
		var pos := Vector3(center.x + rng.randf_range(-size.x, size.x) * 0.35, top + h * 0.5,
			center.z + rng.randf_range(-size.z, size.z) * 0.35)
		var s := Vector3(minf(w, size.x), h, minf(d, size.z))
		_add("block", _box_xform(pos, s, Vector3(0, rng.randf_range(-0.08, 0.08), rng.randf_range(-0.05, 0.05))), tint.darkened(rng.randf_range(0.18, 0.32)))
	if face == Vector3.ZERO:
		return
	# 面の位置と、面に沿った向き（tangent）
	var along_x := absf(face.x) < 0.5          # 面が ±Z 向きなら、横に x 方向へ並べる
	var tangent := Vector3.RIGHT if along_x else Vector3.BACK
	var width := size.x if along_x else size.z
	var half_depth := (size.z if along_x else size.x) * 0.5
	var plane := center + face * half_depth
	var start_y := maxf(ground_y, bottom) + 1.6
	# 窓と帯
	var y := start_y
	while y + WINDOW_SIZE.y * 0.5 < top - 0.6:
		# 帯（各階の床の位置）
		var ledge_pos := Vector3(plane.x, y - 1.15, plane.z) + face * 0.08
		var ledge_size := Vector3(width if along_x else LEDGE_THICKNESS * 1.5, LEDGE_THICKNESS, LEDGE_THICKNESS * 1.5 if along_x else width)
		_add("block", _box_xform(ledge_pos, ledge_size, Vector3.ZERO), tint.darkened(0.3))
		var x := -width * 0.5 + WINDOW_SPACING * 0.5
		while x < width * 0.5 - 0.6:
			if rng.randf() >= WINDOW_SKIP_RATE:
				_add_window(Vector3(plane.x, y, plane.z) + tangent * x, face, tangent, along_x, y > start_y + 1.0, tint)
			x += WINDOW_SPACING
		y += FLOOR_HEIGHT
	# 壁の穴（W-10）
	if width > 4.0:
		for i in rng.randi_range(0, HOLES_MAX):
			var hx := rng.randf_range(-width * 0.5 + 1.5, width * 0.5 - 1.5)
			var hy := rng.randf_range(start_y, maxf(start_y, top - 2.0))
			_add_hole(Vector3(plane.x, hy, plane.z) + tangent * hx, face, tangent, along_x, Vector2(rng.randf_range(1.2, 2.8), rng.randf_range(1.0, 2.2)))
	# 屋上から突き出た、崩れた床（W-10）
	if rng.randf() < COLLAPSED_FLOOR_RATE:
		var cx := rng.randf_range(-width * 0.5 + 1.5, width * 0.5 - 1.5)
		var w := rng.randf_range(2.0, 3.8)
		var d := rng.randf_range(1.4, 2.4)
		var tilt := rng.randf_range(0.25, 0.6)
		var base := Vector3(plane.x, top - 0.3, plane.z) + tangent * cx + face * d * 0.4
		var rot_axis := tangent
		var b := Basis(rot_axis, tilt * (1.0 if face.dot(rot_axis.cross(Vector3.UP)) > 0.0 else -1.0))
		_add("block", Transform3D(b * _fbasis(w, 0.25, d, along_x), base), tint.darkened(0.2))
		for r in rng.randi_range(4, 8):
			_add_rebar(base + tangent * rng.randf_range(-w * 0.45, w * 0.45) + face * d * 0.45, face, rng.randf_range(0.5, 1.3))
	# ツタ：屋上から垂れ下がる。葉を付ける
	var vines := int(width * VINES_PER_METER)
	for i in vines:
		var vx := rng.randf_range(-width * 0.5 + 0.3, width * 0.5 - 0.3)
		var length := rng.randf_range(1.5, minf(8.0, top - start_y + 1.0))
		var vpos := Vector3(plane.x, top - length * 0.5, plane.z) + tangent * vx + face * 0.06
		var vsize := Vector3(0.09, length, 0.05) if along_x else Vector3(0.05, length, 0.09)
		_add("vine", _box_xform(vpos, vsize, Vector3.ZERO), Palette.LEAF.darkened(rng.randf_range(0.0, 0.2)))
		# 葉：葉のかたまりを描いた板を、壁から外向きに付ける
		var ly := 0.0
		while ly < length:
			var lpos := vpos + Vector3.UP * (length * 0.5 + 0.2 - ly) + tangent * rng.randf_range(-0.25, 0.25) + face * rng.randf_range(0.08, 0.2)
			var ls := rng.randf_range(0.5, 0.95)
			var lb := Basis.looking_at(-face, Vector3.UP) * Basis(Vector3.BACK, rng.randf_range(-0.6, 0.6))
			lb = lb * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.2))  # 少し上を向いたり、垂れたり
			_add("leaf", Transform3D(lb.scaled(Vector3(ls, ls, ls)), lpos), Color.WHITE.darkened(rng.randf_range(0.0, 0.3)).lerp(Color(1.1, 1.05, 0.8), rng.randf() * 0.25))
			ly += VINE_LEAF_STEP * rng.randf_range(0.6, 1.3)


# 窓：へこんだ暗い奥＋窓枠＋窓台。上の階には、ときどきベランダ
func _add_window(center: Vector3, face: Vector3, tangent: Vector3, along_x: bool, upper: bool, tint: Color) -> void:
	var w := WINDOW_SIZE.x
	var h := WINDOW_SIZE.y
	var boarded := rng.randf() < WINDOW_BOARDED_RATE
	var wc := Palette.RUST.darkened(rng.randf_range(0.0, 0.3)) if boarded else Palette.WINDOW.lightened(rng.randf_range(0.0, 0.06))
	# 奥：壁より少し内側（へこんで見える）
	_add("window", Transform3D(_fbasis(w, h, 0.12, along_x), center - face * 0.05), wc)
	var ft := FRAME_THICKNESS
	var frame_col := tint.darkened(rng.randf_range(0.3, 0.45))
	var out := face * 0.04
	_add("frame", Transform3D(_fbasis(w + ft * 2.0, ft, 0.16, along_x), center + Vector3.UP * (h + ft) * 0.5 + out), frame_col)
	_add("frame", Transform3D(_fbasis(w + ft * 2.0, ft, 0.16, along_x), center - Vector3.UP * (h + ft) * 0.5 + out), frame_col)
	_add("frame", Transform3D(_fbasis(ft, h, 0.16, along_x), center + tangent * (w + ft) * 0.5 + out), frame_col)
	_add("frame", Transform3D(_fbasis(ft, h, 0.16, along_x), center - tangent * (w + ft) * 0.5 + out), frame_col)
	# 窓台（下に少し突き出た板）
	_add("frame", Transform3D(_fbasis(w + 0.35, 0.07, 0.28, along_x), center - Vector3.UP * (h * 0.5 + ft + 0.03) + face * 0.12), frame_col.darkened(0.1))
	if upper and rng.randf() < BALCONY_RATE:
		_add_balcony(center - Vector3.UP * (h * 0.5 + 0.25), face, tangent, along_x, tint)


# ベランダ：床の板と手すり。壊れたものは傾いて、手すりが欠けている
func _add_balcony(base: Vector3, face: Vector3, tangent: Vector3, along_x: bool, tint: Color) -> void:
	var w := rng.randf_range(1.8, 2.4)
	var d := 0.95
	var broken := rng.randf() < BALCONY_BROKEN_RATE
	var b := Basis.IDENTITY
	if broken:
		b = Basis(tangent, rng.randf_range(0.15, 0.35) * (1.0 if face.dot(tangent.cross(Vector3.UP)) > 0.0 else -1.0))
	var slab_center := base + face * d * 0.5
	_add("block", Transform3D(b * _fbasis(w, 0.16, d, along_x), slab_center), tint.darkened(0.25))
	var rail_col := Color(0.28, 0.24, 0.2).darkened(rng.randf_range(0.0, 0.3))
	var posts := 7
	for i in posts:
		if broken and rng.randf() < 0.4:
			continue
		var t := -w * 0.5 + w * float(i) / float(posts - 1)
		var p := slab_center + b * (tangent * t + face * (d * 0.45) + Vector3.UP * 0.5)
		_add("rail", Transform3D(b * _fbasis(0.04, 0.9, 0.04, along_x), p), rail_col)
	if not broken:
		_add("rail", Transform3D(_fbasis(w, 0.05, 0.06, along_x), slab_center + face * (d * 0.45) + Vector3.UP * 0.95), rail_col)


# 壁の穴：暗いへこみ、縁の崩れた塊、むき出しの鉄筋
func _add_hole(center: Vector3, face: Vector3, tangent: Vector3, along_x: bool, size: Vector2) -> void:
	_add("window", Transform3D(_fbasis(size.x, size.y, 0.1, along_x), center - face * 0.02), Palette.WINDOW.darkened(0.3))
	_add("window", Transform3D(_fbasis(size.x * 0.7, size.y * 0.75, 0.1, along_x), center + tangent * size.x * 0.12 - face * 0.01), Palette.WINDOW.darkened(0.5))
	for i in rng.randi_range(6, 11):
		var ang := rng.randf_range(0, TAU)
		var p := center + tangent * cos(ang) * size.x * 0.5 + Vector3.UP * sin(ang) * size.y * 0.5 + face * 0.05
		var s := rng.randf_range(0.25, 0.55)
		_add("chunk", Transform3D(Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))).scaled(Vector3(s, s * 0.7, s)), p), Color.WHITE.darkened(rng.randf_range(0.05, 0.3)))
	for i in rng.randi_range(3, 7):
		var ang := rng.randf_range(0, TAU)
		var p := center + tangent * cos(ang) * size.x * 0.45 + Vector3.UP * sin(ang) * size.y * 0.45
		_add_rebar(p, face, rng.randf_range(0.3, 0.9))


# 鉄筋：壁や床の縁から、曲がって突き出た細い錆びた棒
func _add_rebar(start: Vector3, face: Vector3, length: float) -> void:
	var dir := (face + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.6, 0.4), rng.randf_range(-0.5, 0.5))).normalized()
	var b := Basis(Quaternion(Vector3.UP, dir))
	_add("rebar", Transform3D(b.scaled(Vector3(0.025, length, 0.025)), start + dir * length * 0.5), Palette.RUST.darkened(rng.randf_range(0.0, 0.3)))


# 放置された車（見た目。当たり判定は world_builder.gd が付ける）。flipped：ひっくり返っている
func add_car(base: Vector3, yaw: float, flipped: bool) -> void:
	var paint: Color = CAR_PAINTS[rng.randi() % CAR_PAINTS.size()]
	paint = paint.lerp(Palette.RUST, rng.randf_range(0.15, 0.45)).darkened(rng.randf_range(0.0, 0.2))  # あせて錆びている
	var root := Transform3D(Basis(Vector3.UP, yaw), base)
	if flipped:
		root = root * Transform3D(Basis(Vector3.RIGHT, PI), Vector3.UP * 1.55)  # 屋根を下にして転がっている
	# 車体（ShapeKit.car_mesh：ボンネット・斜めの窓・屋根・トランク・バンパー・ライト）
	_add("car", root, paint)
	# タイヤ：空気が抜けて少し沈んだものもある
	for wx in [-0.82, 0.82]:
		for wz in [-1.35, 1.35]:
			var sink := rng.randf_range(0.0, 0.08) if rng.randf() < 0.4 else 0.0
			_add("wheel", root * Transform3D(Basis.IDENTITY, Vector3(wx, 0.33 - sink, wz)), Color.WHITE)
	# 窓の下から草が生えている（中まで植物が入りこんでいる）
	for i in 3:
		var leaf_p := root * Vector3(rng.randf_range(-0.8, 0.8), 0.9, rng.randf_range(-1.8, 1.8))
		_add("leaf", Transform3D(Basis.from_euler(Vector3(rng.randf_range(-1, 1), rng.randf_range(-PI, PI), 0)).scaled(Vector3.ONE * rng.randf_range(0.6, 0.9)), leaf_p), Color.WHITE.darkened(rng.randf_range(0.0, 0.2)))


# 倒れた看板：柱と板。tilt で傾ける
func add_sign(base: Vector3, yaw: float, tilt: float) -> void:
	var root := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt), base)
	var col: Color = [Color(0.85, 0.85, 0.8), Color(0.5, 0.6, 0.75), Color(0.75, 0.5, 0.4)][rng.randi() % 3]
	_add("block", root * Transform3D(Basis.from_scale(Vector3(0.14, 3.0, 0.14)), Vector3(0, 1.5, 0)), Color.WHITE.darkened(0.3))
	_add("block", root * Transform3D(Basis.from_scale(Vector3(2.6, 1.3, 0.1)), Vector3(0, 3.0, 0.1)), col.darkened(rng.randf_range(0.1, 0.3)))


# 面の向きに合わせた大きさの変換（w：面に沿った幅、h：高さ、d：面から外への厚さ）
static func _fbasis(w: float, h: float, d: float, along_x: bool) -> Basis:
	return Basis.from_scale(Vector3(w, h, d) if along_x else Vector3(d, h, w))


# 柱（折れたものもある）：見た目だけ
func add_pillar(base: Vector3, height: float, broken: bool, tint: Color) -> void:
	var h := height * (rng.randf_range(0.3, 0.6) if broken else 1.0)
	_add("block", _box_xform(base + Vector3.UP * h * 0.5, Vector3(0.9, h, 0.9), Vector3.ZERO), tint.darkened(0.25))
	if broken:
		# 折れた上の部分が、横に倒れている
		var fallen := height - h
		var dir := rng.randf_range(-PI, PI)
		var p := base + Vector3(cos(dir), 0, sin(dir)) * (fallen * 0.5 + 0.6) + Vector3.UP * 0.45
		_add("block", _box_xform(p, Vector3(fallen, 0.85, 0.85), Vector3(0, -dir, rng.randf_range(-0.1, 0.1))), tint.darkened(0.32))


# ---------------------------------------------------------
# まとめて描く
# ---------------------------------------------------------
# 集めた小物を、種類ごとに MultiMeshInstance3D にして parent に足す
func build(parent: Node3D) -> void:
	# 材質（W-09）と形（W-11）
	#  種類 → [材質, 描く距離, 影を落とすか, 形]
	var settings := {
		"block": [WorldMaterials.make("rubble"), MEDIUM_VISIBLE_DISTANCE * 1.5, true, ShapeKit.beveled_box(Vector3.ONE, 0.06)],
		"window": [WorldMaterials.flat(0.6), MEDIUM_VISIBLE_DISTANCE, false, null],
		"vine": [WorldMaterials.flat(0.8, true), MEDIUM_VISIBLE_DISTANCE, false, null],
		"leaf": [NatureKit.leaf_material(), MEDIUM_VISIBLE_DISTANCE, false, ShapeKit.leaf_card_mesh()],
		"frame": [WorldMaterials.make("rubble"), MEDIUM_VISIBLE_DISTANCE, true, ShapeKit.beveled_box(Vector3.ONE, 0.04)],
		"rail": [WorldMaterials.flat(0.5), MEDIUM_VISIBLE_DISTANCE, true, null],
		"rebar": [WorldMaterials.flat(0.7), MEDIUM_VISIBLE_DISTANCE * 0.8, false, null],
		"chunk": [WorldMaterials.make("rubble"), MEDIUM_VISIBLE_DISTANCE, true, ShapeKit.rock_chunk(2)],
		"car": [_car_material(), MEDIUM_VISIBLE_DISTANCE * 1.5, true, ShapeKit.car_mesh()],
		"wheel": [WorldMaterials.flat(0.9), MEDIUM_VISIBLE_DISTANCE, true, ShapeKit.wheel_mesh()],
	}
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for key in _items.keys():
		var kind: String = String(key).get_slice("|", 0)
		var items: Dictionary = _items[key]
		var transforms: Array = items["t"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		var cfg: Array = settings.get(kind, [WorldMaterials.flat(), MEDIUM_VISIBLE_DISTANCE, false, null])
		mm.mesh = cfg[3] if cfg[3] != null else box
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_color(i, items["c"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Ruin_" + String(key).replace("|", "_").replace("-", "m")
		mmi.multimesh = mm
		mmi.material_override = cfg[0]
		mmi.visibility_range_end = cfg[1] + TILE * 0.75  # マスの真ん中から測るので、マスの大きさぶん足す
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cfg[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.add_to_group("ruin_decor")
		parent.add_child(mmi)


# 種類と、置く場所のマス（TILE m 四方）ごとに分けて集める。マスごとに描くので、遠いマスは描かない
func _add(kind: String, xform: Transform3D, color: Color) -> void:
	var key := "%s|%d|%d" % [kind, floori(xform.origin.x / TILE), floori(xform.origin.z / TILE)]
	if not _items.has(key):
		_items[key] = {"t": [], "c": []}
	_items[key]["t"].append(xform)
	_items[key]["c"].append(color)
	stats[kind] = stats.get(kind, 0) + 1


# 車の塗装：あせた塗装に、汚れ（コンクリートの写真テクスチャを細かく）を重ねる。窓は頂点の色で暗い
static func _car_material() -> ShaderMaterial:
	var mat := WorldMaterials.make("rubble")
	mat.set_shader_parameter("uv_scale", 1.2)
	mat.set_shader_parameter("moss_top", 0.25)
	mat.set_shader_parameter("normal_strength", 0.4)
	return mat


# 位置・大きさ・回転（ラジアン）から、大きさ1の箱を置く変換を作る
static func _box_xform(pos: Vector3, size: Vector3, rot: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(size), pos)
