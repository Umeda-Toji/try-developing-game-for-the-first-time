# Godot 4.7.2 / GDScript
# res://scripts/world/world_builder.gd
#
# 白砂市のエリア（W-01〜W-07。docs/WORLD.md）を箱で組み立てる
#  ステップB：配置（当たり判定のある箱）　ステップC：廃墟の見た目（ruin_kit.gd）　ステップD：色（palette.gd）
#
#  一本道（前＝ -Z 方向。全体で約110m）
#   1. 落ち高架（z 52〜38）     スタート。崩れた高架の下。後ろの橋台を登ると高架の上に出られ、端から滑空で降りられる
#   2. 花梨通り（z 38〜10）     両側にビル。途中に水路（z 22〜16）があり、泳いで渡って壁を登る（または高架から滑空で越える）
#   3. 止まり時計の広場（z 10〜-12）  22m四方。重装兵・双剣士・魔法使い。時計塔は登れる
#   4. 書店街の抜け道（z -12〜-30）  幅4mの屋根付きの路地。倒れた本棚（高さ3.2m）を登って越える
#   5. 旧市民ホール（z -30〜-58）   28m四方。広場の敵を全部倒すと入口の扉（根）が開く。ボス
#
#  ・当たり判定はすべてレイヤー1（地形）。カメラの SpringArm3D も当たって、建物にめり込まない
#  ・当たり判定は、歩く場所と大きな建物だけ。飾り（窓・瓦礫・植物）には付けない
#  ・登れない面（見えない壁・ホールの壁）は group "no_climb" に入れる
#  ・エリアの外には見えない壁（高さ40m）を置いて、出られないようにする
#  ・数値はすべてこのファイルの表（定数）にまとめる
class_name WorldBuilder
extends RefCounted

# 出てくる場所（プレイヤー・敵）
const SPAWNS := {
	"player": Vector3(0, 0.1, 41),
	"zako": Vector3(0, 0.1, 25),       # 花梨通り（水路の手前）
	"heavy": Vector3(-6, 0.1, -6),     # 広場
	"swift": Vector3(6, 0.1, 2),       # 広場
	"caster": Vector3(0, 0.1, -9),     # 広場の奥
	"boss": Vector3(0, 0.1, -46),      # ホールの中央
}
# タイトル画面の景色（スタートの上から、花梨通りを見下ろす）
const TITLE_CAMERA_POS := Vector3(5, 8, 50)
const TITLE_CAMERA_LOOK_AT := Vector3(0, 2, 24)

const KILL_Y := -15.0               # これより下に落ちたら、最後に立っていた場所に戻す
const WALL_HEIGHT_INVISIBLE := 40.0
const OUTER_GROUND_Y := -4.0        # エリアの外の地面（見た目だけ）の高さ
const OUTER_GROUND_SIZE := 400.0
const BEVEL := 0.12                 # 建物・高架の角を削る幅（m）

const F_PX := Vector3(1, 0, 0)      # 窓を付ける面の向き（外向き）
const F_NX := Vector3(-1, 0, 0)
const F_PZ := Vector3(0, 0, 1)
const F_NZ := Vector3(0, 0, -1)
const F_NONE := Vector3.ZERO

# 箱の表：[中心, 大きさ, 種類, 登れるか, 窓を付ける面]
#  種類：GROUND 地面／BUILDING 建物／OVERPASS 高架／OBSTACLE 倒れた本棚
const BOXES := [
	# ---- 1. 落ち高架 ----
	[Vector3(0, -0.5, 45), Vector3(14, 1, 14), "GROUND", true, F_NONE],
	[Vector3(0, 2.5, 48), Vector3(6, 5, 8), "OVERPASS", true, F_NONE],          # 橋台（登ると高架の上へ）
	[Vector3(0, 4.5, 37), Vector3(6, 1, 14), "OVERPASS", true, F_NONE],         # 高架の床（z 44〜30。端は崩れている）
	[Vector3(-2.5, 2, 40), Vector3(1, 4, 1), "OVERPASS", true, F_NONE],         # 柱
	[Vector3(2.5, 2, 40), Vector3(1, 4, 1), "OVERPASS", true, F_NONE],
	[Vector3(-2.5, 2, 34), Vector3(1, 4, 1), "OVERPASS", true, F_NONE],
	[Vector3(2.5, 2, 34), Vector3(1, 4, 1), "OVERPASS", true, F_NONE],
	[Vector3(-9.5, 5, 40.5), Vector3(5, 10, 5), "BUILDING", true, F_PX],         # 左右のビル（真ん中は街への出口。W-13）
	[Vector3(-9.5, 5, 49.5), Vector3(5, 10, 5), "BUILDING", true, F_PX],
	[Vector3(9.5, 5, 40.5), Vector3(5, 10, 5), "BUILDING", true, F_NX],
	[Vector3(9.5, 5, 49.5), Vector3(5, 10, 5), "BUILDING", true, F_NX],
	[Vector3(0, 5, 53), Vector3(24, 10, 2), "BUILDING", false, F_NZ],           # 後ろの壁
	# ---- 2. 花梨通り（床は厚くして、水路の壁を兼ねる）----
	[Vector3(0, -1.75, 30), Vector3(10, 3.5, 16), "GROUND", true, F_NONE],      # z 38〜22
	[Vector3(0, -1.75, 13), Vector3(10, 3.5, 6), "GROUND", true, F_NONE],       # z 16〜10
	[Vector3(0, -3.25, 19), Vector3(10, 0.5, 6), "GROUND", true, F_NONE],       # 水路の底（y -3）
	[Vector3(-8.5, 4.25, 34), Vector3(7, 15.5, 8), "BUILDING", true, F_PX],     # 左のビル（y -3.5 から）
	[Vector3(-8.5, 2.75, 26), Vector3(7, 12.5, 8), "BUILDING", true, F_PX],
	[Vector3(-8.5, 5.25, 16), Vector3(7, 17.5, 12), "BUILDING", true, F_PX],
	[Vector3(8.5, 3.25, 34), Vector3(7, 13.5, 8), "BUILDING", true, F_NX],      # 右のビル
	[Vector3(8.5, 5.25, 26), Vector3(7, 17.5, 8), "BUILDING", true, F_NX],
	[Vector3(8.5, 3.75, 16), Vector3(7, 14.5, 12), "BUILDING", true, F_NX],
	# ---- 3. 止まり時計の広場 ----
	[Vector3(0, -0.5, -1), Vector3(22, 1, 22), "GROUND", true, F_NONE],
	[Vector3(-13.5, 5, -7.5), Vector3(5, 10, 9), "BUILDING", true, F_PX],       # 左右のビル（真ん中は街への出口。W-13）
	[Vector3(-13.5, 5, 5.5), Vector3(5, 10, 9), "BUILDING", true, F_PX],
	[Vector3(13.5, 5, -7.5), Vector3(5, 10, 9), "BUILDING", true, F_NX],
	[Vector3(13.5, 5, 5.5), Vector3(5, 10, 9), "BUILDING", true, F_NX],
	[Vector3(-9, 5, -13), Vector3(14, 10, 2), "BUILDING", false, F_PZ],         # 奥の壁（真ん中が抜け道の入口）
	[Vector3(9, 5, -13), Vector3(14, 10, 2), "BUILDING", false, F_PZ],
	[Vector3(8, 6, -9), Vector3(3, 12, 3), "BUILDING", true, F_PZ],             # 時計塔
	[Vector3(0, 0.3, -1), Vector3(5, 0.6, 5), "OBSTACLE", true, F_NONE],        # 噴水の縁
	# ---- 4. 書店街の抜け道 ----
	[Vector3(0, -0.5, -21), Vector3(4, 1, 18), "GROUND", true, F_NONE],
	[Vector3(-3, 3, -21), Vector3(2, 6, 18), "BUILDING", false, F_PX],          # 左右の壁
	[Vector3(3, 3, -21), Vector3(2, 6, 18), "BUILDING", false, F_NX],
	[Vector3(0, 6.5, -21), Vector3(8, 1, 10), "BUILDING", false, F_NONE],       # 屋根（z -26〜-16）
	[Vector3(0, 1.6, -21.5), Vector3(4, 3.2, 1), "OBSTACLE", true, F_NONE],     # 倒れた本棚（登って越える）
	# ---- 5. 旧市民ホール ----
	[Vector3(0, -0.5, -44), Vector3(28, 1, 28), "GROUND", true, F_NONE],
	[Vector3(-8, 6, -29.5), Vector3(12, 12, 1), "BUILDING", false, F_NZ],       # 入口の壁（真ん中が扉）
	[Vector3(8, 6, -29.5), Vector3(12, 12, 1), "BUILDING", false, F_NZ],
	[Vector3(0, 8, -29.5), Vector3(4, 8, 1), "BUILDING", false, F_NONE],        # 扉の上
	[Vector3(0, 6, -58.5), Vector3(30, 12, 1), "BUILDING", false, F_PZ],        # 奥・左右の壁
	[Vector3(-14.5, 6, -44), Vector3(1, 12, 30), "BUILDING", false, F_PX],
	[Vector3(14.5, 6, -44), Vector3(1, 12, 30), "BUILDING", false, F_NX],
]

# 見えない壁：[中心, 大きさ]（登れない。エリアの外に出ない・扉を飛び越えないため）
const INVISIBLE_WALLS := [
	# 街の外枠は city_builder.gd（W-13）
	[Vector3(-15, 26, -44), Vector3(1, 28, 30)],    # ホールの壁の上（扉を越えて入れないように）
	[Vector3(0, 26, -58.5), Vector3(30, 28, 1)],
	[Vector3(15, 26, -44), Vector3(1, 28, 30)],
	[Vector3(0, 26, -29.5), Vector3(30, 28, 1)],
]

# 水：[中心, 大きさ]（上の面が水面）
const WATERS := [
	[Vector3(0, -1.9, 19), Vector3(10, 2.2, 6)],    # 花梨通りの水路（水面 y -0.8、底 y -3）
]

const DOOR_POS := Vector3(0, 2, -29.5)
const DOOR_SIZE := Vector3(4, 4, 1)

# ---- 飾り（ステップC。当たり判定なし）----
# 地面の飾りを散らす範囲：[中心（y は地面の高さ）, 大きさ（x, z）, 道の真ん中の空ける幅]
const DECOR_AREAS := [
	[Vector3(0, 0, 45), Vector2(14, 14), 2.0],      # 落ち高架
	[Vector3(0, 5, 37), Vector2(5.5, 13), 0.0],     # 高架の上
	[Vector3(0, 0, 30), Vector2(10, 16), 2.0],      # 花梨通り
	[Vector3(0, 0, 13), Vector2(10, 6), 2.0],
	[Vector3(0, -3, 19), Vector2(10, 6), 0.0],      # 水路の底（水の中に見える）
	[Vector3(0, 0, -1), Vector2(22, 22), 4.0],      # 広場
	[Vector3(0, 0, -21), Vector2(4, 18), 1.0],      # 書店街の抜け道
	[Vector3(0, 0, -44), Vector2(28, 28), 6.0],     # 旧市民ホール
]
# 木：[根もと, 高さ]
const TREES := [
	[Vector3(-3.8, 0, 47), 5.0],
	[Vector3(3.6, 0, 27), 6.5],
	[Vector3(-3.5, 0, 12), 5.5],
	[Vector3(-8, 0, 6), 7.0],                        # 広場
	[Vector3(9, 0, 6), 6.0],
	[Vector3(-7.5, 0, -8.5), 5.0],
	[Vector3(0, 0, -1), 4.0],                        # 噴水の真ん中から生えた木
	[Vector3(-9, 0, -52), 9.0],                      # ホール（天井の抜けた所から光の方へ）
	[Vector3(10, 0, -36), 7.5],
]
# 看板・端末（W-08）：[置く場所, 向き（ラジアン）, 種類（post 看板／note 手帳）, 文章（docs/WORLD.md）]
const SIGN_POSTS := [
	[Vector3(2.2, 0, 43), PI, "post", "白く咲いたら、斬れ。赤く咲いたら、退け。　――先に来た刈り手より"],
	[Vector3(-4.6, 0, 39.5), PI * 0.5, "post", "白砂市　春のさくら市　三月二十日〜。雨天中止。"],
	[Vector3(4.2, 0, 23.5), -PI * 0.5, "post", "本日の歩行者数：0。昨日の歩行者数：0。記録を続けます。"],
	[Vector3(5.6, 0, -10.2), 0.0, "post", "この時計は、市民の寄付によって建てられました。午後二時十四分。"],
	[Vector3(1.3, 0, -15), -PI * 0.5, "post", "眠くなったら外へ出ないでください。家族の顔を、見ていてください。"],
	[Vector3(-1.1, 0, -25.5), 0.3, "note", "母株の場所はわかった。ホールだ。帰ったら、外套を返す。"],
	[Vector3(1.3, 0, -27.8), 0.0, "post", "根は、誰かを待つように扉を閉じている。"],
]
# 放置された車：[置く場所, 向き（ラジアン）, ひっくり返っているか]（道の端に寄せる）
const CARS := [
	[Vector3(-3.6, 0, 47.5), 0.15, false],      # 落ち高架の下
	[Vector3(3.4, 0, 34), -0.25, false],        # 花梨通り
	[Vector3(-3.5, 0, 27.5), 2.9, false],
	[Vector3(3.4, 0, 12.5), 0.1, true],         # ひっくり返った車
	[Vector3(-8.5, 0, 1.5), 1.4, false],        # 広場
	[Vector3(7.5, 0, -4.5), -1.2, false],
]
const CAR_COLLISION_SIZE := Vector3(1.8, 1.4, 4.3)
# 倒れた看板：[根もと, 向き, 傾き（ラジアン）]
const SIGNS := [
	[Vector3(4.2, 0, 41), -0.5, 0.35],
	[Vector3(-4.0, 0, 15), 1.2, -0.9],
	[Vector3(9.5, 0, 3), 2.2, 1.1],
	[Vector3(-12, 0, -50), 0.4, 0.2],
]
# 倒れた木：[根もと, 向き（ラジアン）, 大きさ]
const FALLEN_LOGS := [
	[Vector3(-3.6, 0, 33), 0.4, 1.3],
	[Vector3(8.5, 0, -4), 2.0, 1.6],
	[Vector3(-10, 0, -40), -0.6, 1.8],
]
# 街灯：[根もと, 向き, 傾き（倒れかけ）]
const STREET_LAMPS := [
	[Vector3(-4.3, 0, 36), PI * 0.5, 0.0],
	[Vector3(4.3, 0, 29), -PI * 0.5, 0.12],
	[Vector3(-4.3, 0, 12), PI * 0.5, -0.25],
	[Vector3(4.3, 0, 11), -PI * 0.5, 0.0],
	[Vector3(-10, 0, 8), 0.3, 0.0],
	[Vector3(10, 0, -10), 2.5, 0.35],
]
# ホールの柱：[根もと, 高さ, 折れているか]
const PILLARS := [
	[Vector3(-11, 0, -34), 11.0, false], [Vector3(-11, 0, -44), 11.0, true], [Vector3(-11, 0, -54), 11.0, false],
	[Vector3(11, 0, -34), 11.0, true], [Vector3(11, 0, -44), 11.0, false], [Vector3(11, 0, -54), 11.0, true],
]


# エリアを作って parent の子にする。扉などを返す
static func build(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "World"
	parent.add_child(root)
	var kit := RuinKit.new()  # 乱数はシード固定（RuinKit.SEED）
	for b in BOXES:
		var pos: Vector3 = b[0]
		var size: Vector3 = b[1]
		var kind: String = b[2]
		var tint := _tint(kind, kit.rng)
		var body := _add_box(root, pos, size, _material(kind, tint, pos, size, kit.rng), b[3])
		if kind == "BUILDING" or kind == "OVERPASS" or kind == "OBSTACLE":
			# 角を斜めに削った形にする（当たり判定は箱のまま）
			(body.get_child(1) as MeshInstance3D).mesh = ShapeKit.beveled_box(size, BEVEL)
		if kind == "BUILDING":
			var ground_y := -3.5 if pos.y - size.y * 0.5 < -3.0 else 0.0
			kit.decorate_building(pos, size, b[4], maxf(ground_y, 0.0), tint)
			# 裏側（広い街に面した側。W-13）にも窓を付ける。地面の下まで続くビルは除く（水路の壁）
			if b[4] != F_NONE and b[3] and pos.y - size.y * 0.5 > -1.0:
				kit.decorate_building(pos, size, -(b[4] as Vector3), 0.0, tint, false)
	for p in PILLARS:
		kit.add_pillar(p[0], p[1], p[2], Color.WHITE)
	# 放置された車（W-10）：見た目＋当たり判定（大きいので、ぶつかる・登れる）
	for c in CARS:
		add_car(root, kit, c[0], c[1], c[2])
	for sg in SIGNS:
		kit.add_sign(sg[0], sg[1], sg[2])
	# 広い街（W-13）：街・川・見晴らしの塔・外枠と、街の飾り・植物（飾りは下の kit・nature に足す）
	var nature := NatureKit.new()
	var city := CityBuilder.new()
	city.build(root, kit, nature)
	kit.build(root)
	# 植物・石・瓦礫・木・街灯（W-11。Poly Haven の CC0 モデルと、コードで作る草）
	for a in DECOR_AREAS:
		nature.scatter_area(a[0], a[1], a[2])
	for t in TREES:
		nature.add_tree(t[0], t[1])
	for l in FALLEN_LOGS:
		nature.add_fallen_log(l[0], l[1], l[2])
	for l in STREET_LAMPS:
		nature.add_street_lamp(l[0], l[1], l[2])
	nature.build(root)
	for w in INVISIBLE_WALLS:
		_add_invisible_wall(root, w[0], w[1])
	# エリアの外の地面（見た目だけ。遠くは霧でかすむ）。歩ける床より下に置き、当たり判定は付けない
	var outer := MeshInstance3D.new()
	outer.name = "OuterGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(OUTER_GROUND_SIZE, OUTER_GROUND_SIZE)
	outer.mesh = plane
	outer.position = Vector3(0, OUTER_GROUND_Y, -3)
	outer.material_override = WorldMaterials.make("street", Palette.OUTER_GROUND)
	root.add_child(outer)
	for w in WATERS:
		var water := Water.new()
		water.name = "Water"
		water.size = w[1]
		water.position = w[0]
		root.add_child(water)
	for sp in SIGN_POSTS:
		var sign := SignPost.new()
		sign.name = "SignPost"
		sign.position = sp[0]
		sign.rotation.y = sp[1]
		sign.kind = sp[2]
		sign.text = sp[3]
		root.add_child(sign)
	var door := BossDoor.new()
	door.name = "BossDoor"
	door.size = DOOR_SIZE
	door.position = DOOR_POS
	door.add_to_group("no_climb")
	root.add_child(door)
	var decor := kit.stats.duplicate()
	decor.merge(nature.stats)
	decor.merge(city.stats)
	return {"root": root, "door": door, "decor": decor, "side_enemies": city.side_spots}


# 色合い：写真のテクスチャに掛ける色。白に近いほどテクスチャの色そのまま
# 建物ごとに少しだけ明るさ・色みを変えて、同じ壁が並んで見えないようにする
static func _tint(kind: String, rng: RandomNumberGenerator) -> Color:
	match kind:
		"BUILDING":
			var warm := rng.randf_range(-0.04, 0.06)
			return Color(1.0 + warm, 1.0, 1.0 - warm).darkened(rng.randf_range(0.0, 0.18))
		_:
			return Color.WHITE


# 箱の種類と場所から、どのテクスチャを使うか決める（W-09）
static func _material(kind: String, tint: Color, pos: Vector3, size: Vector3, rng: RandomNumberGenerator) -> ShaderMaterial:
	var bottom := pos.y - size.y * 0.5
	match kind:
		"GROUND":
			if pos.z < -29.0:
				return WorldMaterials.make("hall_floor", tint)
			if size.x >= 20.0 and pos.z > -13.0 and pos.z < 11.0:
				return WorldMaterials.make("plaza", tint)
			return WorldMaterials.make("street", tint)
		"OBSTACLE":
			if pos.z < -12.0:
				return WorldMaterials.make("wood", tint)   # 倒れた本棚
			return WorldMaterials.make("rubble", tint)     # 噴水の縁
		"OVERPASS":
			return WorldMaterials.make("concrete", tint)
		_:
			var gy := maxf(bottom, 0.0) if bottom > -1.0 else -0.8  # 水路に面したビルは、水面の近くに苔
			return WorldMaterials.make("plaster" if rng.randf() < 0.5 else "concrete", tint, gy)


static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, climbable: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 0
	body.set_collision_layer_value(1, true)
	if not climbable:
		body.add_to_group("no_climb")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)
	return body


# 放置された車：見た目（kit）と当たり判定の箱
static func add_car(root: Node3D, kit: RuinKit, pos: Vector3, yaw: float, flipped: bool) -> void:
	kit.add_car(pos, yaw, flipped)
	var col := StaticBody3D.new()
	col.name = "Car"
	col.collision_layer = 0
	col.set_collision_layer_value(1, true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = CAR_COLLISION_SIZE
	shape.shape = box
	col.add_child(shape)
	col.transform = Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * CAR_COLLISION_SIZE.y * 0.5)
	root.add_child(col)


static func _add_invisible_wall(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "InvisibleWall"
	body.position = pos
	body.collision_layer = 0
	body.set_collision_layer_value(1, true)
	body.add_to_group("no_climb")
	body.add_to_group("invisible_wall")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
