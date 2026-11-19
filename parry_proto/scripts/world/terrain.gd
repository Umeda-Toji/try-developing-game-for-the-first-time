# Godot 4.7.2 / GDScript
# res://scripts/world/terrain.gd
#
# 起伏のある地面（T-01。NEXT_FEATURES 1.5・ステップ6。11/19 決定）
#  ・Godot に最初からある「高さの地図」の当たり判定（HeightMapShape3D）と、同じ高さで作った見た目の形
#  ・area を TILE m 四方のマスに分け、マスごとに1つの形と1つの当たり判定。高さは STEP（1m）ごと
#  ・高さは FastNoiseLite（シード固定）。丘は最大 HILL_MAX（+4m）、くぼ地は最大 HOLLOW_MAX（−2m）
#    波の長さを長めにして、坂はたいてい25°まで、急な所でも MAX_SLOPE_DEG（35°）まで
#  ・flat_zones：その中は高さ0（今の高架・水路・本棚・川と橋など）。まわり blend m で、なめらかに起伏へ戻す
#  ・scale_zones：その中は起伏を小さくする（広場 ±1m、ホール ±0.8m など）
#  ・高さは height_at(x, z) でいつでも同じ値が出る（物を置くとき・テストで使う）
class_name Terrain
extends Node3D

const SEED := 20261120
const TILE := 64                 # マスの大きさ（m）
const STEP := 1.0                # 高さの点の間隔（m）。HeightMapShape3D の点の間隔と同じ
const HILL_MAX := 4.0            # 丘の高さの最大（m）
const HOLLOW_MAX := 2.0          # くぼ地の深さの最大（m）
const MAX_SLOPE_DEG := 35.0      # 坂の角度の上限（テストで確かめる）
const NOISE_FREQ := 0.012        # 波の細かさ（小さいほどなだらか）
const NOISE_RANGE := 0.75        # ノイズの値をこの幅で割って、−1〜1 にそろえる

var area := Rect2(-64, -64, 128, 128)   # 起伏を作る範囲（x, z）
var flat_zones: Array = []      # [Rect2, blend(m)]
var scale_zones: Array = []     # [Rect2, 起伏の倍率, blend(m)]
var material: Material
var tiles := 0
var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = NOISE_FREQ
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_noise.fractal_gain = 0.4


# その場所の地面の高さ（m）
func height_at(x: float, z: float) -> float:
	var n := clampf(_noise.get_noise_2d(x, z) / NOISE_RANGE, -1.0, 1.0)
	var h := n * HILL_MAX if n > 0.0 else n * HOLLOW_MAX
	return h * mask_at(x, z)


# 起伏の強さ（0〜1）。平らにする所と、小さくする所の掛け算
func mask_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var m := 1.0
	for f in flat_zones:
		m = minf(m, _zone_factor(p, f[0], float(f[1])))
	for s in scale_zones:
		var t := 1.0 - _zone_factor(p, s[0], float(s[2]))   # 中で 1、外で 0
		m *= lerpf(1.0, float(s[1]), t)
	return m


# 長方形の中で 0、外へ blend m 離れると 1。なめらかにつなぐ
static func _zone_factor(p: Vector2, r: Rect2, blend: float) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	var d := Vector2(dx, dz).length()
	if blend <= 0.0:
		return 0.0 if d <= 0.0 else 1.0
	return smoothstep(0.0, 1.0, d / blend)


# 形と当たり判定を作る
func build(parent: Node3D) -> void:
	parent.add_child(self)
	var x := area.position.x
	while x < area.end.x:
		var z := area.position.y
		while z < area.end.y:
			_build_tile(x, z)
			z += TILE
		x += TILE


func _build_tile(x0: float, z0: float) -> void:
	var n := int(TILE / STEP) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = height_at(x0 + i * STEP, z0 + j * STEP)
	# 見た目
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			var hx0 := heights[j * n + maxi(i - 1, 0)]
			var hx1 := heights[j * n + mini(i + 1, n - 1)]
			var hz0 := heights[maxi(j - 1, 0) * n + i]
			var hz1 := heights[mini(j + 1, n - 1) * n + i]
			st.set_normal(Vector3(hx0 - hx1, 2.0 * STEP, hz0 - hz1).normalized())
			st.set_uv(Vector2(x0 + i * STEP, z0 + j * STEP) * 0.25)
			st.add_vertex(Vector3(x0 + i * STEP, heights[j * n + i], z0 + j * STEP))
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainTile_%d_%d" % [int(x0), int(z0)]
	mi.mesh = st.commit()
	if material != null:
		mi.material_override = material
	add_child(mi)
	# 当たり判定（HeightMapShape3D は形の真ん中が原点、点の間隔は1m）
	var body := StaticBody3D.new()
	body.name = "TerrainBody_%d_%d" % [int(x0), int(z0)]
	body.collision_layer = 0
	body.set_collision_layer_value(1, true)
	body.add_to_group("terrain")
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = Vector3(x0 + TILE * 0.5, 0.0, z0 + TILE * 0.5)
	add_child(body)
	tiles += 1


# 範囲の中の、いちばん急な坂（度）。点ごとに隣との差で調べる（テスト用）
func max_slope_deg(sample_step: float = 1.0) -> float:
	var best := 0.0
	var x := area.position.x
	while x < area.end.x - sample_step:
		var z := area.position.y
		while z < area.end.y - sample_step:
			var h := height_at(x, z)
			var gx := (height_at(x + sample_step, z) - h) / sample_step
			var gz := (height_at(x, z + sample_step) - h) / sample_step
			best = maxf(best, rad_to_deg(atan(Vector2(gx, gz).length())))
			z += sample_step
		x += sample_step
	return best
