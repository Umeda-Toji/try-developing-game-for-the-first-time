# Godot 4.7.2 / GDScript
# res://scripts/world/shape_kit.gd
#
# 角ばらない形を、コードで作る（W-11）
#  ・beveled_box：角を斜めに削った箱（建物・高架・柱。光が角に当たって、本物の建物らしく見える）
#  ・rock_chunk：ごつごつした塊（瓦礫。球をノイズでへこませて、下を平らにする。三角形は約100枚で軽い）
#  ・grass_texture／leaf_texture：草の葉・ツタの葉を描いた画像（透明な所は描かない）
#  ・card_mesh：十字に組んだ板（草のかたまりに使う）
#  ・作った形は同じ引数なら使い回す（キャッシュ）
class_name ShapeKit
extends RefCounted

static var _cache := {}


# 角を bevel（m）だけ斜めに削った箱
static func beveled_box(size: Vector3, bevel: float) -> ArrayMesh:
	var key := "box|%s|%.3f" % [str(size), bevel]
	if _cache.has(key):
		return _cache[key]
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.45)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 6つの面（少し内側に縮めた四角）
	for axis in 3:
		for s in [-1.0, 1.0]:
			var pts: Array[Vector3] = []
			for c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var p := Vector3.ZERO
				p[axis] = h[axis] * s
				var a1 := (axis + 1) % 3
				var a2 := (axis + 2) % 3
				p[a1] = (h[a1] - b) * c[0]
				p[a2] = (h[a2] - b) * c[1]
				pts.append(p)
			_add_poly(st, pts)
	# 12本の辺（斜めの細い面）
	for axis in 3:
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var pts: Array[Vector3] = []
				for t in [-1.0, 1.0]:
					var p := Vector3.ZERO
					p[axis] = (h[axis] - b) * t
					p[a1] = h[a1] * s1
					p[a2] = (h[a2] - b) * s2
					pts.append(p)
				for t in [1.0, -1.0]:
					var p := Vector3.ZERO
					p[axis] = (h[axis] - b) * t
					p[a1] = (h[a1] - b) * s1
					p[a2] = h[a2] * s2
					pts.append(p)
				_add_poly(st, pts)
	# 8つの角（小さな三角）
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var pts: Array[Vector3] = [
					Vector3(h.x * sx, (h.y - b) * sy, (h.z - b) * sz),
					Vector3((h.x - b) * sx, h.y * sy, (h.z - b) * sz),
					Vector3((h.x - b) * sx, (h.y - b) * sy, h.z * sz),
				]
				_add_poly(st, pts)
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# 外向きになるように向きをそろえて、多角形を三角形に分けて足す（法線は面ごと）
static func _add_poly(st: SurfaceTool, pts: Array[Vector3]) -> void:
	var center := Vector3.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	var n := (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if n.dot(center) < 0.0:
		pts.reverse()
		n = -n
	for i in range(1, pts.size() - 1):
		# Godot は時計回りが表なので、0, i+1, i の順に足す
		for p in [pts[0], pts[i + 1], pts[i]]:
			st.set_normal(n)
			st.add_vertex(p)


# ごつごつした塊（瓦礫）。variant ごとに形が変わる。大きさはおよそ 1m
static func rock_chunk(variant: int) -> ArrayMesh:
	var key := "rock|%d" % variant
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + variant
	var sphere := SphereMesh.new()
	sphere.radial_segments = 10
	sphere.rings = 6
	sphere.radius = 0.5
	sphere.height = 1.0
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var stretch := Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.45, 0.8), rng.randf_range(0.7, 1.2))
	var offsets := {}  # 同じ位置の頂点は同じだけ動かす（すき間ができないように）
	for i in verts.size():
		var v := verts[i]
		var k := Vector3i(roundi(v.x * 1000), roundi(v.y * 1000), roundi(v.z * 1000))
		if not offsets.has(k):
			offsets[k] = rng.randf_range(0.72, 1.12)
		v *= offsets[k]
		v *= stretch
		v.y = maxf(v.y, -0.12)  # 下は平らにする（地面に置ける）
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.deindex()
	st.generate_normals()  # 面ごとの法線（ごつごつに見える）
	var mesh := st.commit()
	_cache[key] = mesh
	return mesh


# 十字に組んだ2枚の板（幅1・高さ1、下の真ん中が原点）。草のかたまりに使う
static func card_mesh() -> ArrayMesh:
	if _cache.has("card"):
		return _cache["card"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ang in [0.0, PI * 0.5]:
		var d := Vector3(cos(ang), 0.0, sin(ang)) * 0.5
		var quad := [[-d, Vector2(0, 1)], [d, Vector2(1, 1)], [d + Vector3.UP, Vector2(1, 0)], [-d + Vector3.UP, Vector2(0, 0)]]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)  # 上向きの法線：草が裏から見ても暗くならない
			st.set_uv(quad[idx][1])
			st.add_vertex(quad[idx][0])
	var mesh := st.commit()
	_cache["card"] = mesh
	return mesh


# 1枚の板（幅1・高さ1、上の真ん中が原点）。ツタの葉に使う
static func leaf_card_mesh() -> ArrayMesh:
	if _cache.has("leaf_card"):
		return _cache["leaf_card"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := [[Vector3(-0.5, -1, 0), Vector2(0, 1)], [Vector3(0.5, -1, 0), Vector2(1, 1)], [Vector3(0.5, 0, 0), Vector2(1, 0)], [Vector3(-0.5, 0, 0), Vector2(0, 0)]]
	for idx in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.BACK)
		st.set_uv(quad[idx][1])
		st.add_vertex(quad[idx][0])
	var mesh := st.commit()
	_cache["leaf_card"] = mesh
	return mesh


# 草の葉を描いた画像（下から上へ細くなる葉を何本も。透明な所は描かない）
static func grass_texture() -> ImageTexture:
	if _cache.has("grass_tex"):
		return _cache["grass_tex"]
	var size := 256
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.4, 0.2, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 46:
		var x0 := rng.randf_range(10, size - 10)
		var h := rng.randf_range(size * 0.45, size * 0.98)
		var lean := rng.randf_range(-0.35, 0.35)
		var w0 := rng.randf_range(2.5, 5.5)
		var base := Color(0.32, 0.45, 0.2).lerp(Color(0.55, 0.58, 0.3), rng.randf()).darkened(rng.randf_range(0.0, 0.25))
		var steps := int(h)
		for s in steps:
			var t := float(s) / h
			var y := size - 1 - s
			var x := x0 + lean * s + sin(t * 3.0 + i) * 3.0 * t
			var w := w0 * (1.0 - t) + 0.5
			var col := base.lightened(t * 0.25)  # 先ほど明るい
			for dx in range(int(x - w), int(x + w) + 1):
				if dx >= 0 and dx < size and y >= 0:
					img.set_pixel(dx, y, col)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["grass_tex"] = tex
	return tex


# ツタの葉のかたまりを描いた画像（ハート形に近い葉をいくつも重ねる）
static func leaf_texture() -> ImageTexture:
	if _cache.has("leaf_tex"):
		return _cache["leaf_tex"]
	var size := 256
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.25, 0.35, 0.18, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	# 茎
	for y in size:
		var x := int(size * 0.5 + sin(y * 0.05) * 6.0)
		for dx in range(-1, 2):
			img.set_pixel(clampi(x + dx, 0, size - 1), y, Color(0.3, 0.27, 0.18, 1.0))
	for i in 22:
		var cx := rng.randf_range(size * 0.2, size * 0.8)
		var cy := rng.randf_range(size * 0.08, size * 0.95)
		var r := rng.randf_range(16, 30)
		var rot := rng.randf_range(-PI, PI)
		var col := Color(0.24, 0.36, 0.16).lerp(Color(0.38, 0.5, 0.22), rng.randf()).darkened(rng.randf_range(0.0, 0.3))
		for py in range(int(cy - r), int(cy + r)):
			for px in range(int(cx - r), int(cx + r)):
				if px < 0 or py < 0 or px >= size or py >= size:
					continue
				var d := Vector2(px - cx, py - cy).rotated(rot) / r
				# 葉の形：先のとがった楕円
				var inside := (d.x * d.x) / 0.45 + pow(d.y + 0.15 * absf(d.x) * 2.0, 2.0) < 1.0 - 0.35 * maxf(d.y, 0.0)
				if inside:
					var vein := 1.0 - 0.25 * exp(-absf(d.x) * 18.0)  # 真ん中の葉脈は少し暗い
					img.set_pixel(px, py, Color(col.r * vein, col.g * vein, col.b * vein, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["leaf_tex"] = tex
	return tex


# ---------------------------------------------------------
# 車（W-14）：車の長さ方向にいくつかの断面を並べて、つなげた形（ロフト）
#  ・下の車体：ボンネット・トランクは低く、真ん中は高い。断面は角を丸めた四角
#  ・上の客室：窓（暗い色）と屋根。前の窓・後ろの窓は斜め
#  ・頂点の色：塗装＝白（車ごとの色を掛ける）、窓＝ほぼ黒、バンパー・下まわり＝灰色
#  ・長さ 4.4m・幅 1.8m・高さ 約1.5m。前は +Z
# ---------------------------------------------------------
const CAR_PAINT := Color(1, 1, 1)
const CAR_GLASS := Color(0.07, 0.08, 0.09)
const CAR_TRIM := Color(0.35, 0.35, 0.35)


static func car_mesh() -> ArrayMesh:
	if _cache.has("car"):
		return _cache["car"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 下の車体：[z, 下の高さ, 上の高さ（ベルトライン）, 半分の幅]
	var body := [
		[-2.2, 0.32, 0.72, 0.84], [-2.05, 0.28, 0.9, 0.9], [-1.6, 0.28, 0.98, 0.9], [-0.8, 0.28, 1.0, 0.9],
		[0.6, 0.28, 1.0, 0.9], [1.3, 0.28, 0.95, 0.9], [1.9, 0.28, 0.86, 0.89], [2.2, 0.32, 0.7, 0.84],
	]
	_loft(st, body, CAR_PAINT, CAR_PAINT, 0.12)
	# 客室：[z, 下の高さ, 屋根の高さ, 半分の幅]。前後は窓が斜めに下がる
	var cabin := [
		[-1.45, 0.97, 0.99, 0.74], [-0.85, 0.99, 1.47, 0.7], [0.45, 0.99, 1.5, 0.7], [1.15, 0.97, 0.99, 0.74],
	]
	_loft(st, cabin, CAR_GLASS, CAR_PAINT, 0.06)
	# バンパー（前後の灰色の帯）と、ライト
	for zz in [-2.24, 2.24]:
		_box_into(st, Vector3(0, 0.45, zz), Vector3(1.75, 0.18, 0.12), CAR_TRIM)
	for lx in [-0.6, 0.6]:
		_box_into(st, Vector3(lx, 0.78, 2.21), Vector3(0.35, 0.12, 0.05), Color(0.85, 0.85, 0.8))
		_box_into(st, Vector3(lx, 0.8, -2.21), Vector3(0.32, 0.1, 0.05), Color(0.5, 0.12, 0.1))
	# タイヤの入るくぼみ（黒い影）
	for wz in [-1.35, 1.35]:
		for sx in [-1.0, 1.0]:
			_box_into(st, Vector3(sx * 0.86, 0.4, wz), Vector3(0.12, 0.42, 0.9), CAR_GLASS)
	st.generate_normals()
	var mesh := st.commit()
	_cache["car"] = mesh
	return mesh


# タイヤ（黒いゴム）とホイール（灰色）。軸は X（横）、直径 0.66m
static func wheel_mesh() -> ArrayMesh:
	if _cache.has("wheel"):
		return _cache["wheel"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 16
	for part in [[0.33, 0.24, Color(0.08, 0.08, 0.08)], [0.2, 0.26, Color(0.45, 0.45, 0.47)]]:
		var r: float = part[0]
		var w: float = part[1]
		var col: Color = part[2]
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			var p0 := Vector3(0, cos(a0) * r, sin(a0) * r)
			var p1 := Vector3(0, cos(a1) * r, sin(a1) * r)
			var hx := Vector3(w * 0.5, 0, 0)
			_tri(st, [p0 - hx, p1 - hx, p1 + hx], col, Vector3.ZERO)
			_tri(st, [p0 - hx, p1 + hx, p0 + hx], col, Vector3.ZERO)
			_tri(st, [hx, p1 + hx, p0 + hx], col, Vector3(-1, 0, 0))
			_tri(st, [-hx, p0 - hx, p1 - hx], col, Vector3(1, 0, 0))
	st.generate_normals()
	var mesh := st.commit()
	_cache["wheel"] = mesh
	return mesh


# 断面を順につなげる。断面は角を丸めた四角（8点）。下半分の色 side_col、上の面の色 top_col
static func _loft(st: SurfaceTool, stations: Array, side_col: Color, top_col: Color, round_r: float) -> void:
	var rings: Array = []
	for s in stations:
		var z: float = s[0]
		var y0: float = s[1]
		var y1: float = s[2]
		var hw: float = s[3]
		var r := minf(round_r, (y1 - y0) * 0.45)
		var pts := [
			Vector3(-hw, y0, z), Vector3(hw, y0, z),
			Vector3(hw, y1 - r, z), Vector3(hw - r, y1, z),
			Vector3(-hw + r, y1, z), Vector3(-hw, y1 - r, z),
		]
		rings.append(pts)
	var n: int = rings[0].size()
	for k in range(rings.size() - 1):
		var a: Array = rings[k]
		var b: Array = rings[k + 1]
		for i in n:
			var j := (i + 1) % n
			var col := top_col if (i == 2 or i == 3 or i == 4) else side_col
			_tri(st, [a[i], b[i], b[j]], col)
			_tri(st, [a[i], b[j], a[j]], col)
	# 前と後ろのふた
	for ring in [rings[0], rings[rings.size() - 1]]:
		var c := Vector3.ZERO
		for p in ring:
			c += p
		c /= n
		for i in n:
			_tri(st, [c, ring[i], ring[(i + 1) % n]], side_col)


static func _box_into(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	var arrays := beveled_box(size, minf(0.02, minf(size.x, minf(size.y, size.z)) * 0.3)).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for v in verts:  # 角を削った箱は、もう向きがそろっているので、そのまま足す
		st.set_color(col)
		st.add_vertex(v + center)


# 三角形を足す。外向き（中心から離れる向き）になるように、向きをそろえる
static func _tri(st: SurfaceTool, p: Array, col: Color, origin: Vector3 = Vector3(0, 0.75, 0)) -> void:
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var c: Vector3 = p[2]
	var n := (b - a).cross(c - a)
	var center := (a + b + c) / 3.0
	var outward: Vector3 = center - origin
	var order := [0, 2, 1] if n.dot(outward) > 0.0 else [0, 1, 2]
	for i in order:
		st.set_color(col)
		st.add_vertex(p[i])
