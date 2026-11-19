# Godot 4.7.2 / GDScript
# res://scripts/world/city_builder.gd
#
# 広い街（W-13 ②配置）。今の一本道（world_builder.gd）のまわりに、約280m×275m の白砂市を足す
#  ・道（幅10m）と区画（30m四方）の格子。区画には高さの違うビルを1〜3つ。崩れて低い廃墟や、空き地（公園）もある
#  ・一本道のまわり（CORRIDOR）は空けておく。一本道との間には幅8mほどの通りができる
#  ・目印：見晴らしの塔（42m。休める出っぱりが7mごと）、街の北を横切る川（泳ぐか、橋を渡る）
#  ・地面は厚い板（上の面が y 0）。川の所だけ空けて、川の底と水を置く
#  ・街の外は見えない壁（高さ60m）
#  ・乱数はシード固定（SEED）
#  ・崩れたビル（11/19）：上の階が半分か角だけ残ったビル（崩れた縁に鉄筋・垂れた床・下に瓦礫の山）、段々に崩れたビル
#  ・③ 見た目（11/19）：ビルの4つの面に、窓・窓枠・ベランダ・壁の穴・ツタ（ruin_kit.gd）。
#    街じゅうに草・植物・瓦礫を少なめに、空き地には多めに＋木（nature_kit.gd）。通りに車・看板・街灯
#  ・軽くするため、街のビルの見た目は材質ごとに1つの形にまとめて描く（何十個も別々に描くと重い）。
#    ビルごとの色の違いは、頂点の色で持たせる。当たり判定はビルごとの箱のまま
class_name CityBuilder
extends RefCounted

const SEED := 20261119
const CITY_MIN := Vector2(-140, -140)     # 街の端（x, z）
const CITY_MAX := Vector2(140, 135)
const BLOCK := 30.0                       # 区画の大きさ（m）
const STREET := 10.0                      # 道の幅（m）
const CORRIDOR := Rect2(-22, -64, 44, 124)  # 一本道のエリア（x -22〜22、z -64〜60）。ここには区画を作らない
const GROUND_THICKNESS := 3.5             # 地面の板の厚さ（川の岸の壁を兼ねる）
const PARK_RATE := 0.15                   # 空き地（公園）にする区画の割合
const RUIN_RATE := 0.25                   # 崩れて低い廃墟にするビルの割合
const BUILDING_HEIGHT := Vector2(6.0, 22.0)
const RUIN_HEIGHT := Vector2(1.5, 5.0)

# 川（街の北を東西に横切る）：z の範囲、水面、底
const RIVER_Z := Vector2(95.0, 103.0)
const RIVER_SURFACE_Y := -0.8
const RIVER_BOTTOM_Y := -3.0
const BRIDGES_X := [-100.0, 0.0, 60.0]   # 橋のある所（x）
const BRIDGE_WIDTH := 6.0

# 見晴らしの塔
const TOWER_POS := Vector3(80, 0, 40)
const TOWER_SIZE := Vector3(12, 42, 12)
const TOWER_LEDGE_STEP := 7.0             # 休める出っぱりの間隔（m）

# 地面の板：[x の範囲, z の範囲]（一本道のエリアと川は空ける）
const GROUNDS := [
	[Vector2(-140, -17), Vector2(-140, 95)],
	[Vector2(17, 140), Vector2(-140, 95)],
	[Vector2(-17, 17), Vector2(55, 95)],
	[Vector2(-17, 17), Vector2(-140, -60)],
	[Vector2(-140, 140), Vector2(103, 135)],
	# 一本道のエリアの中で、床がなかった所（建物の裏）
	[Vector2(-17, -7), Vector2(38, 55)], [Vector2(7, 17), Vector2(38, 55)], [Vector2(-7, 7), Vector2(52, 55)],
	[Vector2(-17, -5), Vector2(10, 38)], [Vector2(5, 17), Vector2(10, 38)],
	[Vector2(-17, -11), Vector2(-12, 10)], [Vector2(11, 17), Vector2(-12, 10)],
	[Vector2(-17, -2), Vector2(-30, -12)], [Vector2(2, 17), Vector2(-30, -12)],
	[Vector2(-17, -14), Vector2(-60, -30)], [Vector2(14, 17), Vector2(-60, -30)], [Vector2(-14, 14), Vector2(-60, -58)],
]

var rng := RandomNumberGenerator.new()
var stats := {"building": 0, "ruin": 0, "park": 0}
var _merged := {}   # 材質の種類（"concrete" ／ "plaster"）→ SurfaceTool（ビルの形をまとめる）
var _kit: RuinKit
var _nature: NatureKit
var _parks: Array[Rect2] = []
var _roofs: Array[Vector3] = []       # 崩れていないビルの屋上の真ん中（強化アイテムを置く）
var side_spots: Array = []            # 寄り道の敵：[場所, 種類]（main.gd が作る。W-15 ④-3）
var _ground_upgrades: Array[Vector3] = []  # 道に置いた強化アイテム（寄り道の敵が守る）
var _used_spots: Array[Vector3] = []  # もう物を置いた場所（記録の断片・アイテムが重ならないように）

const STREET_DENSITY := 0.6        # 街の通りの草・瓦礫の量（一本道のエリアを1として）
const STREET_MODEL_DENSITY := 0.12 # 街の通りの植物モデル（シダ・イラクサなど。重い）の量（上の量に、さらに掛ける）
const PARK_DENSITY := 1.0          # 空き地の草・植物の量
const DECOR_TILE := 40.0           # 草・植物を散らすマスの大きさ（m）
const TREES_PER_PARK := Vector2i(2, 4)
const CITY_CARS := 26              # 通りに置く車の数
const CITY_SIGNS := 10
const CITY_LAMPS := 24
const FACES := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
# 記録の断片（W-15。④-1）：[種類, 文章]。置く場所は、塔の下・橋のたもと・空き地・交差点の順に決める
# アイテム（W-15 ④-2）
const HEAL_ITEMS := 8            # 回復薬（道・空き地に置く）
# 強化アイテム：1つ目は見晴らしの塔の屋上、次の ROOF_UPGRADES 個は低めのビルの屋上、残りは道
const UPGRADE_ITEMS := ["attack", "hp", "stamina", "attack", "hp", "stamina", "hp", "stamina", "attack"]
const ROOF_UPGRADES := 5
# 寄り道の敵（W-15 ④-3）：道の強化アイテムを守る組・見晴らしの塔の下・空き地。[種類, 種類] の組
const GUARD_GROUPS := [["zako", "heavy"], ["swift", "zako"], ["heavy", "caster"]]
const TOWER_GROUP := ["heavy", "caster"]
const PARK_GROUPS := [["zako", "caster"], ["swift", "swift"]]
const SIDE_OFFSETS := [Vector3(2.5, 0.1, 0), Vector3(-2.0, 0.1, 2.0)]  # 組の中の2体の位置（真ん中から）
# 眺めのいい場所（W-15 ④-4）：[場所の名前, 一文]。場所は 見晴らしの塔の屋上・西の橋・いちばん高いビルの屋上
const VISTAS := [
	["見晴らし塔の屋上", "街は、どこまでも緑に沈んでいる。ホールの屋根だけが、白く見える。"],
	["白砂川の西の橋", "水だけが、まだ街の外へ流れていく。"],
	["名もないビルの屋上", "ここから見ると、苗人は、ただ散歩をしているように見える。"],
]
const FRAGMENTS := [
	["post", "見晴らし塔　展望台まで階段二百十段。エレベーターは点検中です。"],
	["post", "この橋より先、通行止め。外へ出る許可のない方は、引き返してください。"],
	["note", "渡れば帰れると思った。橋の向こうも、同じ色をしていた。"],
	["note", "おかあさんは　ねている。おこさないで　って　いわれた。"],
	["note", "三日目。苗人の数が合わない。数えるたびに、一体増えている。"],
	["post", "緑眠の方の受け入れは終了しました。ご家族は自宅で看てください。"],
	["note", "外套の綿が足りない。この街の綿毛は、少し甘い匂いがする。"],
	["post", "市からのお知らせ：眠っている人を、外へ運ばないでください。"],
	["note", "ここに植えた桜は、今年も咲いた。咲いたのは、桜だけではなかった。"],
	["note", "刈り手は眠らない。眠れないだけだ。いつか私も、何かを待つのだろうか。"],
]
const CORRIDOR_INNER := Rect2(-17, -60, 34, 115)  # 一本道のエリアの中（ここには街の草を置かない。自分の草がある）
# 崩れたビル（11/19）
const COLLAPSE_HALF_RATE := 0.4    # 上の階が半分（または角だけ）崩れ落ちたビルの割合
const COLLAPSE_STEP_RATE := 0.2    # 段々に崩れたビルの割合（残りはそのまま）
const HEAP_CHUNKS := 26            # 崩れた側の下にできる瓦礫の山の塊の数


func _init() -> void:
	rng.seed = SEED


func build(root: Node3D, kit: RuinKit, nature: NatureKit) -> void:
	_kit = kit
	_nature = nature
	_build_ground(root)
	_build_river(root)
	_build_blocks(root)
	_build_tower(root)
	_build_walls(root)
	_build_merged(root)
	_build_greenery()
	_build_street_props(root)
	_build_fragments(root)
	_build_pickups(root)
	_build_side_spots()
	_build_vistas(root)


func _build_ground(root: Node3D) -> void:
	for g in GROUNDS:
		var xr: Vector2 = g[0]
		var zr: Vector2 = g[1]
		var size := Vector3(xr.y - xr.x, GROUND_THICKNESS, zr.y - zr.x)
		var pos := Vector3((xr.x + xr.y) * 0.5, -GROUND_THICKNESS * 0.5, (zr.x + zr.y) * 0.5)
		WorldBuilder._add_box(root, pos, size, WorldMaterials.make("street"), true)


func _build_river(root: Node3D) -> void:
	var width := CITY_MAX.x - CITY_MIN.x
	var depth := RIVER_Z.y - RIVER_Z.x
	var cz := (RIVER_Z.x + RIVER_Z.y) * 0.5
	# 川の底
	WorldBuilder._add_box(root, Vector3(0, RIVER_BOTTOM_Y - 0.25, cz), Vector3(width, 0.5, depth), WorldMaterials.make("street"), true)
	# 水
	var water := Water.new()
	water.name = "River"
	var h := RIVER_SURFACE_Y - RIVER_BOTTOM_Y
	water.size = Vector3(width, h, depth)
	water.position = Vector3(0, RIVER_BOTTOM_Y + h * 0.5, cz)
	root.add_child(water)
	# 橋（地面と同じ高さの板）
	for bx in BRIDGES_X:
		var size := Vector3(BRIDGE_WIDTH, 0.6, depth + 1.0)
		var body := WorldBuilder._add_box(root, Vector3(bx, -0.3, cz), size, WorldMaterials.make("concrete"), true)
		(body.get_child(1) as MeshInstance3D).mesh = ShapeKit.beveled_box(size, 0.1)


func _build_blocks(root: Node3D) -> void:
	var step := BLOCK + STREET
	var x := CITY_MIN.x + STREET * 0.5
	while x + BLOCK <= CITY_MAX.x:
		var z := CITY_MIN.y + STREET * 0.5
		while z + BLOCK <= CITY_MAX.y:
			var cell := Rect2(x, z, BLOCK, BLOCK)
			if not cell.intersects(CORRIDOR) and not _overlaps_river(cell) and not cell.has_point(Vector2(TOWER_POS.x, TOWER_POS.z)):
				_build_block(root, cell)
			z += step
		x += step


func _overlaps_river(cell: Rect2) -> bool:
	return cell.position.y < RIVER_Z.y and cell.end.y > RIVER_Z.x


# 1つの区画：空き地か、1〜3つのビル（崩れた低い廃墟もある）
func _build_block(root: Node3D, cell: Rect2) -> void:
	if rng.randf() < PARK_RATE:
		stats["park"] += 1
		_parks.append(cell)
		return
	var count := rng.randi_range(1, 3)
	var along_x := rng.randf() < 0.5
	var length := cell.size.x if along_x else cell.size.y
	var cursor := 0.0
	for i in count:
		var remain := length - cursor
		if remain < 6.0:
			break
		var w := remain
		if i < count - 1 and remain > 14.0:
			w = rng.randf_range(8.0, minf(remain - 6.0, 18.0))
		var d := rng.randf_range(10.0, BLOCK)
		var ruin := rng.randf() < RUIN_RATE
		var h := rng.randf_range(RUIN_HEIGHT.x, RUIN_HEIGHT.y) if ruin else rng.randf_range(BUILDING_HEIGHT.x, BUILDING_HEIGHT.y)
		var size := Vector3(w, h, d) if along_x else Vector3(d, h, w)
		var off := cursor + w * 0.5
		var px := cell.position.x + (off if along_x else size.x * 0.5 + rng.randf_range(0.0, BLOCK - size.x))
		var pz := cell.position.y + (size.z * 0.5 + rng.randf_range(0.0, BLOCK - size.z) if along_x else off)
		_add_city_building(root, Vector3(px, h * 0.5, pz), size, ruin)
		stats["ruin" if ruin else "building"] += 1
		cursor += w + rng.randf_range(0.0, 3.0)


# 街のビル：そのまま／上の階が半分（角だけ）崩れ落ちた／段々に崩れた、のどれか（11/19）
func _add_city_building(root: Node3D, pos: Vector3, size: Vector3, ruin: bool) -> void:
	if ruin:
		_add_building(root, pos, size, false)
		return
	var r := rng.randf()
	var along_x := size.x >= size.z
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	var length := size.x if along_x else size.z
	if r < COLLAPSE_HALF_RATE:
		# 下の階はそのまま。上の階は片側（keep の割合）だけ残る
		var h1 := size.y * rng.randf_range(0.35, 0.65)
		var keep := rng.randf_range(0.4, 0.65)
		_add_building(root, Vector3(pos.x, h1 * 0.5, pos.z), Vector3(size.x, h1, size.z))
		var up_size := Vector3(size.x * keep, size.y - h1, size.z) if along_x else Vector3(size.x, size.y - h1, size.z * keep)
		var up_pos := Vector3(pos.x, h1 + up_size.y * 0.5, pos.z) + axis * side * length * (1.0 - keep) * 0.5
		if rng.randf() < 0.5:  # 角だけ残る（もう一方の向きも縮める）
			var other := Vector3.BACK if along_x else Vector3.RIGHT
			var k2 := rng.randf_range(0.5, 0.75)
			if along_x:
				up_size.z *= k2
			else:
				up_size.x *= k2
			up_pos += other * (1.0 if rng.randf() < 0.5 else -1.0) * (size.z if along_x else size.x) * (1.0 - k2) * 0.5
		_add_building(root, up_pos, up_size, true, false)
		# 崩れた縁：むき出しの鉄筋、垂れ下がった床の板、下の瓦礫の山
		var edge := up_pos - axis * side * (length * keep * 0.5) + Vector3.DOWN * (up_size.y * 0.5)
		var out := -axis * side
		for i in rng.randi_range(5, 9):
			var t := rng.randf_range(-0.45, 0.45) * (size.z if along_x else size.x)
			_kit._add_rebar(edge + (Vector3.BACK if along_x else Vector3.RIGHT) * t + Vector3.UP * rng.randf_range(0.0, up_size.y * 0.6), out, rng.randf_range(0.5, 1.4))
		var slab_basis := Basis(Vector3.BACK if along_x else Vector3.RIGHT, rng.randf_range(0.4, 0.9) * (-side if along_x else side))
		_kit._add("block", Transform3D(slab_basis * RuinKit._fbasis(rng.randf_range(2.0, 4.0), 0.25, 2.2, not along_x), edge + out * 1.0), Color.WHITE.darkened(0.25))
		var heap_center := pos + out * (length * 0.5 + 2.5)
		_rubble_heap(heap_center, 3.5)
		_rubble_heap(Vector3(edge.x, h1, edge.z) + out * (length * (1.0 - keep) * 0.4), 2.0)  # 下の階の屋上にも
		stats["collapsed"] = stats.get("collapsed", 0) + 1
	elif r < COLLAPSE_HALF_RATE + COLLAPSE_STEP_RATE:
		# 段々に崩れた：長い向きに3つに分けて、高さを順に下げる
		var heights := [size.y, size.y * rng.randf_range(0.55, 0.75), size.y * rng.randf_range(0.2, 0.4)]
		if side < 0.0:
			heights.reverse()
		for i in 3:
			var seg_len := length / 3.0
			var h: float = heights[i]
			var seg_size := Vector3(seg_len, h, size.z) if along_x else Vector3(size.x, h, seg_len)
			var seg_pos := Vector3(pos.x, h * 0.5, pos.z) + axis * (-length * 0.5 + seg_len * (i + 0.5))
			_add_building(root, seg_pos, seg_size, true, i == 0)
		_rubble_heap(pos + axis * side * (length * 0.5 + 2.0), 3.0)
		stats["collapsed"] = stats.get("collapsed", 0) + 1
	else:
		_add_building(root, pos, size)
		_roofs.append(Vector3(pos.x, size.y, pos.z))


# 瓦礫の山：ごつごつした塊を、真ん中ほど高く積む（見た目だけ）
func _rubble_heap(center: Vector3, radius: float) -> void:
	for i in HEAP_CHUNKS:
		var ang := rng.randf_range(0.0, TAU)
		var d := sqrt(rng.randf()) * radius
		var mound := (1.0 - d / radius) * radius * 0.45
		var s := rng.randf_range(0.5, 1.6)
		var p := center + Vector3(cos(ang) * d, mound * rng.randf_range(0.3, 1.0), sin(ang) * d)
		var b := Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))).scaled(Vector3(s, s * 0.7, s))
		_kit._add("chunk", Transform3D(b, p), Color.WHITE.darkened(rng.randf_range(0.05, 0.35)))


func _add_building(root: Node3D, pos: Vector3, size: Vector3, windows: bool = true, roof: bool = true) -> void:
	var tint := WorldBuilder._tint("BUILDING", rng)
	# 飾り（③）：窓などは、ランダムな2つの面に付ける（廃墟は崩れた屋上だけ）
	if windows:
		# 4つの面すべてに付ける（屋上の塊は1回だけ）
		for i in FACES.size():
			_kit.decorate_building(pos, size, FACES[i], maxf(pos.y - size.y * 0.5, 0.0), tint, i == 0 and roof)
	elif roof:
		_kit.decorate_building(pos, size, Vector3.ZERO, 0.0, tint)
	var kind := "plaster" if rng.randf() < 0.5 else "concrete"
	# 当たり判定だけの箱
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 0
	body.set_collision_layer_value(1, true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_to_group("city_building")
	root.add_child(body)
	# 見た目：角を削った箱を、材質ごとのまとめた形に足す（色はビルごとの頂点の色）
	if not _merged.has(kind):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_merged[kind] = st
	var st2: SurfaceTool = _merged[kind]
	var arrays := ShapeKit.beveled_box(size, WorldBuilder.BEVEL).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		st2.set_color(tint)
		st2.set_normal(normals[i])
		st2.add_vertex(verts[i] + pos)


# 草・植物・瓦礫：街を DECOR_TILE ごとのマスに分けて、少なめに散らす（一本道と川はよける）。空き地は多めに＋木
func _build_greenery() -> void:
	var x := CITY_MIN.x
	while x < CITY_MAX.x:
		var z := CITY_MIN.y
		while z < CITY_MAX.y:
			var tile := Rect2(x, z, DECOR_TILE, DECOR_TILE)
			# 一本道のエリア（の中）と川は、マスごとではなく、1本ずつよける（マスごと飛ばすと、草のない所ができる）
			if not CORRIDOR_INNER.encloses(tile):
				_nature.scatter_area(Vector3(x + DECOR_TILE * 0.5, 0, z + DECOR_TILE * 0.5), Vector2(DECOR_TILE, DECOR_TILE), 0.0, STREET_DENSITY,
					[CORRIDOR_INNER, Rect2(CITY_MIN.x, RIVER_Z.x - 0.5, CITY_MAX.x - CITY_MIN.x, RIVER_Z.y - RIVER_Z.x + 1.0)], STREET_MODEL_DENSITY)
			z += DECOR_TILE
		x += DECOR_TILE
	for p in _parks:
		var c := p.get_center()
		_nature.scatter_area(Vector3(c.x, 0, c.y), p.size, 0.0, PARK_DENSITY)
		for i in rng.randi_range(TREES_PER_PARK.x, TREES_PER_PARK.y):
			_nature.add_tree(Vector3(c.x + rng.randf_range(-11, 11), 0, c.y + rng.randf_range(-11, 11)), rng.randf_range(5.0, 9.0))


# 通りの車・看板・街灯：道の真ん中の線の近くに置く（一本道・川・塔はよける）
func _build_street_props(root: Node3D) -> void:
	var lines: Array[float] = []
	var v := CITY_MIN.x + STREET * 0.5 + BLOCK + STREET * 0.5
	while v < CITY_MAX.x:
		lines.append(v)
		v += BLOCK + STREET
	var placed := 0
	var tries := 0
	while placed < CITY_CARS + CITY_SIGNS + CITY_LAMPS and tries < 2000:
		tries += 1
		var along_z := rng.randf() < 0.5
		var line: float = lines[rng.randi() % lines.size()]
		var t := rng.randf_range(CITY_MIN.y + 5.0, CITY_MAX.y - 5.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := Vector3(line + side * 3.0, 0, t) if along_z else Vector3(t, 0, line + side * 3.0)
		var p2 := Vector2(pos.x, pos.z)
		if CORRIDOR.grow(4.0).has_point(p2) or (pos.z > RIVER_Z.x - 3.0 and pos.z < RIVER_Z.y + 3.0) or p2.distance_to(Vector2(TOWER_POS.x, TOWER_POS.z)) < 12.0:
			continue
		var yaw := (0.0 if along_z else PI * 0.5) + rng.randf_range(-0.3, 0.3)
		if placed < CITY_CARS:
			WorldBuilder.add_car(root, _kit, pos, yaw + (PI if rng.randf() < 0.5 else 0.0), rng.randf() < 0.1)
		elif placed < CITY_CARS + CITY_SIGNS:
			_kit.add_sign(pos + Vector3(side * 1.5, 0, 0) if along_z else pos + Vector3(0, 0, side * 1.5), rng.randf_range(-PI, PI), rng.randf_range(-1.0, 1.0))
		else:
			var edge := pos + (Vector3(side * 1.8, 0, 0) if along_z else Vector3(0, 0, side * 1.8))
			_nature.add_street_lamp(edge, yaw + (PI * 0.5 * side), rng.randf_range(-0.3, 0.3) if rng.randf() < 0.3 else 0.0)
		placed += 1
	stats["street_props"] = placed


# 記録の断片（W-15）：建物のない所（道・空き地）に置く。読むと Discoveries に覚える
func _build_fragments(root: Node3D) -> void:
	var spots: Array[Vector3] = [
		Vector3(60, 0, 34),                           # 見晴らしの塔の下（西の通り）
		Vector3(-100, 0, RIVER_Z.x - 6.0),           # 西の橋の南のたもと
		Vector3(60, 0, RIVER_Z.y + 6.0),             # 東の橋の北のたもと
	]
	for p in _parks:                                  # 空き地の真ん中
		spots.append(Vector3(p.get_center().x, 0, p.get_center().y))
	# 足りない分は交差点（道と道が交わる所）。一本道・川・塔からは離す
	var lines: Array[float] = []
	var v := CITY_MIN.x + STREET * 0.5 + BLOCK + STREET * 0.5
	while v < CITY_MAX.x:
		lines.append(v)
		v += BLOCK + STREET
	for x in lines:
		for z in lines:
			var p2 := Vector2(x, z)
			if CORRIDOR.grow(4.0).has_point(p2) or (z > RIVER_Z.x - 4.0 and z < RIVER_Z.y + 4.0):
				continue
			spots.append(Vector3(x + 2.0, 0, z + 2.0))
	# 空き地・交差点は、街じゅうに散らばるように、シード固定で混ぜる（最初の3つはそのまま）
	var rest := spots.slice(3)
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector3 = rest[i]
		rest[i] = rest[j]
		rest[j] = tmp
	var ordered: Array[Vector3] = spots.slice(0, 3)
	ordered.append_array(rest)
	spots = ordered
	for i in FRAGMENTS.size():
		var sign := SignPost.new()
		sign.name = "LoreFragment%d" % i
		sign.fragment_id = i
		sign.kind = FRAGMENTS[i][0]
		sign.text = FRAGMENTS[i][1]
		sign.position = spots[i]
		_used_spots.append(spots[i])
		sign.rotation.y = rng.randf_range(-PI, PI)
		root.add_child(sign)
	Discoveries.fragment_total = FRAGMENTS.size()
	stats["fragments"] = FRAGMENTS.size()


# アイテム（W-15 ④-2）：回復薬は道・空き地、強化は塔の屋上・ビルの屋上・道
func _build_pickups(root: Node3D) -> void:
	var ground := _open_spots()
	var roofs := _roofs.duplicate()
	roofs.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)  # 低いビルから（登りやすい）
	roofs = roofs.slice(0, ROOF_UPGRADES * 2)
	var id := 0
	for i in UPGRADE_ITEMS.size():
		var pos: Vector3
		if i == 0:
			pos = TOWER_POS + Vector3.UP * TOWER_SIZE.y
		elif i <= ROOF_UPGRADES and not roofs.is_empty():
			pos = roofs.pop_at(rng.randi() % roofs.size())
		else:
			pos = ground.pop_back()
			_ground_upgrades.append(pos)
		_add_pickup(root, UPGRADE_ITEMS[i], id, pos)
		id += 1
	for i in HEAL_ITEMS:
		_add_pickup(root, "heal", id, ground.pop_back())
		id += 1
	stats["pickups"] = id


func _add_pickup(root: Node3D, kind: String, id: int, pos: Vector3) -> void:
	var item := Pickup.new()
	item.name = "Pickup%d_%s" % [id, kind]
	item.kind = kind
	item.item_id = id
	item.position = pos
	root.add_child(item)
	_used_spots.append(pos)


# 寄り道の敵の場所と種類を決める（敵そのものは main.gd が作る）
func _build_side_spots() -> void:
	for i in mini(_ground_upgrades.size(), GUARD_GROUPS.size()):
		_add_side_group(_ground_upgrades[i], GUARD_GROUPS[i])
	_add_side_group(Vector3(60, 0, 46), TOWER_GROUP)  # 塔の西の通り（記録の断片の少し北）
	for i in mini(_parks.size(), PARK_GROUPS.size()):
		var c := _parks[_parks.size() - 1 - i].get_center()
		_add_side_group(Vector3(c.x, 0, c.y), PARK_GROUPS[i])
	stats["side_enemies"] = side_spots.size()


func _add_side_group(center: Vector3, kinds: Array) -> void:
	for j in kinds.size():
		side_spots.append([center + SIDE_OFFSETS[j], kinds[j]])


# 眺めのいい場所：場所と、カメラの動き（cam_from → cam_to）・見る所（look_from → look_to）
func _build_vistas(root: Node3D) -> void:
	var top := TOWER_POS + Vector3.UP * TOWER_SIZE.y
	var river_z := (RIVER_Z.x + RIVER_Z.y) * 0.5
	var bridge := Vector3(BRIDGES_X[0], 0.0, river_z)
	var high := _roofs[0]
	for r in _roofs:
		if r.y > high.y:
			high = r
	var defs := [
		[top, top + Vector3(5, 8, 8), top + Vector3(-5, 10, -5), Vector3(30, 0, 60), Vector3(0, 10, -50)],  # 屋上の崩れた塊より上から
		[bridge, bridge + Vector3(3, 3, -4), bridge + Vector3(5, 6, 3), Vector3(-30, 0, river_z), Vector3(60, 4, river_z)],
		[high, high + Vector3(-3, 4, 3), high + Vector3(3, 6, -3), TOWER_POS + Vector3.UP * 25.0, Vector3(0, 3, 0)],
	]
	for i in VISTAS.size():
		var v := Vista.new()
		v.name = "Vista%d" % i
		v.vista_id = i
		v.place_name = VISTAS[i][0]
		v.line = VISTAS[i][1]
		v.position = defs[i][0]
		v.cam_from = defs[i][1]
		v.cam_to = defs[i][2]
		v.look_from = defs[i][3]
		v.look_to = defs[i][4]
		root.add_child(v)
		_used_spots.append(defs[i][0])
	Discoveries.vista_total = VISTAS.size()
	stats["vistas"] = VISTAS.size()


# 物を置ける地面の場所（交差点の角と空き地の端）。もう使った所から6m以上離す。シード固定で混ぜて返す
func _open_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var lines: Array[float] = []
	var v := CITY_MIN.x + STREET * 0.5 + BLOCK + STREET * 0.5
	while v < CITY_MAX.x:
		lines.append(v)
		v += BLOCK + STREET
	var cands: Array[Vector3] = []
	for x in lines:
		for z in lines:
			cands.append(Vector3(x - 2.5, 0, z - 2.5))
	for pk in _parks:
		cands.append(Vector3(pk.position.x + 4.0, 0, pk.position.y + 4.0))
		cands.append(Vector3(pk.end.x - 4.0, 0, pk.end.y - 4.0))
	for c in cands:
		var p2 := Vector2(c.x, c.z)
		if CORRIDOR.grow(4.0).has_point(p2) or (c.z > RIVER_Z.x - 4.0 and c.z < RIVER_Z.y + 4.0):
			continue
		if p2.distance_to(Vector2(TOWER_POS.x, TOWER_POS.z)) < 12.0:
			continue
		var near_used := false
		for u in _used_spots:
			if Vector2(u.x, u.z).distance_to(p2) < 6.0:
				near_used = true
		if near_used:
			continue
		out.append(c)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector3 = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


# まとめた形を、材質ごとに1つずつ置く
func _build_merged(root: Node3D) -> void:
	for kind in _merged.keys():
		var mi := MeshInstance3D.new()
		mi.name = "CityBuildings_" + kind
		mi.mesh = (_merged[kind] as SurfaceTool).commit()
		mi.material_override = WorldMaterials.make(kind)
		root.add_child(mi)


# 見晴らしの塔：細長いビル。7mごとに、休める出っぱりを付ける（高さごとに向きを変えて、ぐるっと回りながら登る）
func _build_tower(root: Node3D) -> void:
	_add_building(root, TOWER_POS + Vector3.UP * TOWER_SIZE.y * 0.5, TOWER_SIZE)
	var dirs := [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]
	var y := TOWER_LEDGE_STEP
	var i := 0
	var last: StaticBody3D = null
	while y < TOWER_SIZE.y - 1.0:
		var dir: Vector3 = dirs[i % 4]
		var ledge_size := Vector3(1.6, 0.4, TOWER_SIZE.z * 0.6) if absf(dir.x) > 0.5 else Vector3(TOWER_SIZE.x * 0.6, 0.4, 1.6)
		var pos := TOWER_POS + Vector3.UP * y + dir * (TOWER_SIZE.x * 0.5 + 0.8)
		last = WorldBuilder._add_box(root, pos, ledge_size, WorldMaterials.make("concrete"), true)
		(last.get_child(1) as MeshInstance3D).mesh = ShapeKit.beveled_box(ledge_size, 0.08)
		y += TOWER_LEDGE_STEP
		i += 1
	if last != null:
		last.add_to_group("tower_top_ledge")


# 街の外の見えない壁（高さ60m）
func _build_walls(root: Node3D) -> void:
	var h := 60.0
	var cx := (CITY_MIN.x + CITY_MAX.x) * 0.5
	var cz := (CITY_MIN.y + CITY_MAX.y) * 0.5
	var w := CITY_MAX.x - CITY_MIN.x
	var d := CITY_MAX.y - CITY_MIN.y
	WorldBuilder._add_invisible_wall(root, Vector3(CITY_MIN.x - 0.5, h * 0.5, cz), Vector3(1, h, d + 2))
	WorldBuilder._add_invisible_wall(root, Vector3(CITY_MAX.x + 0.5, h * 0.5, cz), Vector3(1, h, d + 2))
	WorldBuilder._add_invisible_wall(root, Vector3(cx, h * 0.5, CITY_MIN.y - 0.5), Vector3(w + 2, h, 1))
	WorldBuilder._add_invisible_wall(root, Vector3(cx, h * 0.5, CITY_MAX.y + 0.5), Vector3(w + 2, h, 1))
