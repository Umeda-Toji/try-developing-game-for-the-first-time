# Godot 4.7.2 / GDScript
# res://scripts/world/nature_kit.gd
#
# 植物・石・街灯（W-11）。写真から作った CC0 の 3D モデル（Poly Haven、models/nature/）と、コードで作る草を使う
#  ・シダ・イラクサ・雑草・低木・苔むした石・倒れた木・街灯：Poly Haven のモデル
#    （1つのファイルに何種類か並んでいるので、1つずつ取り出して、根もとを原点にそろえて使う）
#  ・草：草の葉を描いた画像を十字の板に貼って、何千本も並べる（shaders/foliage.gdshader。風でゆれる）
#  ・瓦礫：ごつごつした塊（ShapeKit.rock_chunk）にコンクリートの写真テクスチャ
#  ・木：幹と枝（木の皮の写真テクスチャ）＋ 低木のモデルを何個か重ねた葉のかたまり
#  ・乱数はシード固定。数の多い物は、場所（エリア）ごとに MultiMesh でまとめ、遠いエリアは描かない
#  ・当たり判定は付けない
class_name NatureKit
extends RefCounted

const SEED := 20261119
const MODEL_DIR := "res://models/nature/"
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")

# 1平方メートルあたりの数
const GRASS_PER_M2 := 1.1          # 草のかたまり（十字の板）
const FERN_PER_M2 := 0.05
const NETTLE_PER_M2 := 0.035
const WEED_PER_M2 := 0.06
const SHRUB_PER_M2 := 0.04
const RUBBLE_PER_M2 := 0.12
const MOSS_ROCK_PER_M2 := 0.012
const ROCK_CHUNK_VARIANTS := 6
const PLANT_VISIBLE_DISTANCE := 45.0   # 草・小さな植物はこれより遠いと描かない
const ROCK_VISIBLE_DISTANCE := 70.0
const STREET_LAMP_SCALE := 0.65       # 街灯の大きさ（11/18 に 2.6 から 1/4 に。大きすぎたため）
const LEAVES_PER_TREE := 90            # 木1本あたりの葉の板の数

var rng := RandomNumberGenerator.new()
var stats := {}            # 種類 → 数
var _groups := {}          # "エリア番号|種類|変種" → {"mesh", "mat", "t": [], "c": [], "dist", "shadow"}
var _variants := {}        # モデル名 → [{mesh, xform}]
var _area := 0


func _init() -> void:
	rng.seed = SEED


# ---------------------------------------------------------
# モデルの読み込み：1つのファイルに並んだ種類を、1つずつ取り出す
# ---------------------------------------------------------
func variants(name: String) -> Array:
	if _variants.has(name):
		return _variants[name]
	var scene: Node3D = (load("%s%s/%s_1k.gltf" % [MODEL_DIR, name, name]) as PackedScene).instantiate()
	var list: Array = []
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t := Transform3D.IDENTITY
		var p: Node = m
		while p != scene:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		var bb := t * m.get_aabb()
		# 根もと（下の面の真ん中）を原点にそろえる
		var shift := Vector3(bb.position.x + bb.size.x * 0.5, bb.position.y, bb.position.z + bb.size.z * 0.5)
		t.origin -= shift
		list.append({"mesh": m.mesh, "xform": t, "height": bb.size.y})
	scene.free()
	_variants[name] = list
	return list


# ---------------------------------------------------------
# 置く
# ---------------------------------------------------------
# エリア（長方形）に、草・植物・瓦礫・石を散らす。lane_half：道の真ん中の空ける幅
func scatter_area(center: Vector3, size: Vector2, lane_half: float) -> void:
	_area += 1
	var area := size.x * size.y
	# 草のかたまり：道の真ん中は少なめ
	for i in int(area * GRASS_PER_M2):
		var p := _random_point(center, size, 0.0)
		if lane_half > 0.0 and absf(p.x - center.x) < lane_half and rng.randf() < 0.75:
			continue
		var w := rng.randf_range(0.5, 1.1)
		var h := rng.randf_range(0.3, 0.75)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(w, h, w)), p)
		_add("grass", ShapeKit.card_mesh(), _grass_material(), xf, Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.3)).lerp(Color(1.1, 1.0, 0.7), rng.randf() * 0.3), PLANT_VISIBLE_DISTANCE, false)
	# Poly Haven の植物：道の端に寄せる
	_scatter_models("fern_02", area * FERN_PER_M2, center, size, lane_half, 0.8, 1.5)
	_scatter_models("nettle_plant", area * NETTLE_PER_M2, center, size, lane_half, 1.0, 2.0)
	_scatter_models("weed_plant_02", area * WEED_PER_M2, center, size, lane_half, 1.2, 2.4)
	_scatter_models("shrub_03", area * SHRUB_PER_M2, center, size, lane_half, 1.2, 2.2)
	_scatter_models("shrub_04", area * SHRUB_PER_M2, center, size, lane_half, 1.5, 3.0)
	# 苔むした石
	_scatter_models("rock_moss_set_01", area * MOSS_ROCK_PER_M2, center, size, lane_half, 0.25, 0.6, ROCK_VISIBLE_DISTANCE, true)
	# 瓦礫：ごつごつした塊にコンクリートの写真テクスチャ
	for i in int(area * RUBBLE_PER_M2):
		var p := _random_point(center, size, lane_half)
		var s := rng.randf_range(0.2, 0.9)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-PI, PI), rng.randf_range(-0.25, 0.25))).scaled(Vector3(s, s, s))
		var col := Color.WHITE.darkened(rng.randf_range(0.0, 0.35))
		_add("rubble_%d" % (i % ROCK_CHUNK_VARIANTS), ShapeKit.rock_chunk(i % ROCK_CHUNK_VARIANTS), _rubble_material(), Transform3D(basis, p), col, ROCK_VISIBLE_DISTANCE, true)


# 木：幹と枝（木の皮）＋ 低木のモデルを重ねた葉のかたまり
func add_tree(base: Vector3, height: float) -> void:
	_area += 1
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
	var up := (Vector3.UP + lean).normalized()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.13
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = height
	trunk_mesh.radial_segments = 10
	var trunk_basis := Basis(Quaternion(Vector3.UP, up))
	_add("trunk_%.2f" % height, trunk_mesh, WorldMaterials.make("bark"), Transform3D(trunk_basis, base + up * height * 0.5), Color.WHITE, ROCK_VISIBLE_DISTANCE * 1.5, true)
	var top := base + up * height
	# 枝：幹の上の方から、斜め上へ
	for i in rng.randi_range(3, 5):
		var ang := rng.randf_range(-PI, PI)
		var dir := (Vector3(cos(ang), rng.randf_range(0.5, 1.1), sin(ang))).normalized()
		var length := rng.randf_range(1.0, 2.0)
		var start := base + up * height * rng.randf_range(0.6, 0.95)
		var branch := CylinderMesh.new()
		branch.top_radius = 0.03
		branch.bottom_radius = 0.09
		branch.height = length
		branch.radial_segments = 6
		_add("branch_%d" % i, branch, WorldMaterials.make("bark"), Transform3D(Basis(Quaternion(Vector3.UP, dir)), start + dir * length * 0.5), Color.WHITE, ROCK_VISIBLE_DISTANCE * 1.5, true)
	# 葉のかたまり：低木（shrub_02）を何個か、幹の上に重ねる
	var crowns := variants("shrub_02")
	for i in rng.randi_range(4, 6):
		var v: Dictionary = crowns[rng.randi() % crowns.size()]
		var s := rng.randf_range(0.9, 1.4) * clampf(height / 6.0, 0.7, 1.4)
		var off := Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.4, 0.4), rng.randf_range(-1.4, 1.4))
		var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3(s, s, s)), top + off) * (v["xform"] as Transform3D)
		_add("crown_%d" % crowns.find(v), v["mesh"], null, xf, Color.WHITE, ROCK_VISIBLE_DISTANCE * 1.5, true)
	# 葉の板：葉のかたまりを描いた板を、樹冠（丸い範囲）にたくさん付けて、こんもりさせる
	var crown_r := clampf(height * 0.38, 1.6, 3.2)
	for i in LEAVES_PER_TREE:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var p := top + Vector3.UP * crown_r * 0.25 + dir * crown_r * pow(rng.randf(), 0.5)
		var s := rng.randf_range(0.9, 1.6)
		var b := Basis.from_euler(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-PI, PI), rng.randf_range(-0.8, 0.8))).scaled(Vector3(s, s, s))
		_add("leaves", ShapeKit.leaf_card_mesh(), leaf_material(), Transform3D(b, p),
			Color.WHITE.darkened(rng.randf_range(0.0, 0.35)).lerp(Color(1.1, 1.05, 0.75), rng.randf() * 0.3), ROCK_VISIBLE_DISTANCE * 1.5, true)
	stats["tree"] = stats.get("tree", 0) + 1


# 倒れた木（Poly Haven の dead_tree_trunk。横に寝ているモデル）
func add_fallen_log(base: Vector3, yaw: float, scale: float) -> void:
	_area += 1
	var v: Dictionary = variants("dead_tree_trunk")[0]
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), base) * (v["xform"] as Transform3D)
	_add("log", v["mesh"], null, xf, Color.WHITE, ROCK_VISIBLE_DISTANCE, true)


# 街灯（Poly Haven の street_lamp_02）。tilt：傾き（ラジアン。倒れかけた街灯）
func add_street_lamp(base: Vector3, yaw: float, tilt: float) -> void:
	_area += 1
	var v: Dictionary = variants("street_lamp_02")[0]
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	var xf := Transform3D(basis.scaled(Vector3.ONE * STREET_LAMP_SCALE), base) * (v["xform"] as Transform3D)
	_add("lamp", v["mesh"], null, xf, Color.WHITE, ROCK_VISIBLE_DISTANCE * 1.5, true)


# ---------------------------------------------------------
# まとめて描く
# ---------------------------------------------------------
func build(parent: Node3D) -> void:
	for key in _groups.keys():
		var g: Dictionary = _groups[key]
		var transforms: Array = g["t"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = g["mesh"]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_color(i, g["c"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Nature_" + String(key).replace("|", "_").replace(".", "_")
		mmi.multimesh = mm
		if g["mat"] != null:
			mmi.material_override = g["mat"]
		mmi.visibility_range_end = g["dist"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if g["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.add_to_group("nature_decor")
		parent.add_child(mmi)


func _scatter_models(name: String, count: float, center: Vector3, size: Vector2, lane_half: float, smin: float, smax: float, dist: float = PLANT_VISIBLE_DISTANCE, shadow: bool = false) -> void:
	var list := variants(name)
	for i in int(count):
		var v: Dictionary = list[rng.randi() % list.size()]
		var p := _random_point(center, size, lane_half)
		var s := rng.randf_range(smin, smax)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)).scaled(Vector3.ONE * s), p) * (v["xform"] as Transform3D)
		_add("%s_%d" % [name, list.find(v)], v["mesh"], null, xf, Color.WHITE, dist, shadow)


func _random_point(center: Vector3, size: Vector2, lane_half: float) -> Vector3:
	var hx := size.x * 0.5
	var x := rng.randf_range(-hx, hx)
	if lane_half > 0.0 and absf(x) < lane_half:
		x = signf(x if x != 0.0 else 1.0) * rng.randf_range(lane_half, maxf(hx, lane_half + 0.1))
	return Vector3(center.x + x, center.y, center.z + rng.randf_range(-size.y * 0.5, size.y * 0.5))


func _add(kind: String, mesh: Mesh, mat: Material, xf: Transform3D, color: Color, dist: float, shadow: bool) -> void:
	var key := "%d|%s" % [_area, kind]
	if not _groups.has(key):
		_groups[key] = {"mesh": mesh, "mat": mat, "t": [], "c": [], "dist": dist, "shadow": shadow}
	_groups[key]["t"].append(xf)
	_groups[key]["c"].append(color)
	var base_kind := kind.get_slice("_", 0)
	stats[base_kind] = stats.get(base_kind, 0) + 1


static var _grass_mat: ShaderMaterial
static var _rubble_mat: ShaderMaterial


static func _grass_material() -> ShaderMaterial:
	if _grass_mat == null:
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = FOLIAGE_SHADER
		_grass_mat.set_shader_parameter("leaf_tex", ShapeKit.grass_texture())
	return _grass_mat


static func leaf_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FOLIAGE_SHADER
	mat.set_shader_parameter("leaf_tex", ShapeKit.leaf_texture())
	mat.set_shader_parameter("wind_strength", 0.03)
	return mat


static func _rubble_material() -> ShaderMaterial:
	if _rubble_mat == null:
		_rubble_mat = WorldMaterials.make("rubble")
	return _rubble_mat
