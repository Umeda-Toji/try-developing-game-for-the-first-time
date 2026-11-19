# Godot 4.7.2 / GDScript
# res://scripts/ui/city_map.gd
#
# 地図（C。11/19）：ポーズメニューの「地図」で開く、白砂市を上から見た図
#  ・建物（当たり判定の箱）を、高いほど濃い色で描く。水（川・水路）は青
#  ・自分の位置と向き（白い三角）、場所の名前を出す
#  ・アイテム・記録の断片の場所は出さない（探す楽しみを残す）。見た眺めのいい場所だけ印を付ける
#  ・建物の形は、最初に開いたときに一度だけ集める（world_root の下の StaticBody3D）
#  ・地図の上が奥（−Z、ホールの方）、右が +X
class_name CityMap
extends Control

signal back_pressed

const MAP_RATIO := 0.86            # 画面の高さに対する地図の大きさ
const MIN_HEIGHT := 1.0            # これより低い箱（地面・床）は描かない（m）
const MIN_WIDTH := 2.5             # これより小さい箱（車・小物）は描かない（m）
const COLOR_BG := Color(0.05, 0.06, 0.06, 0.92)
const COLOR_GROUND := Color(0.78, 0.76, 0.68)
const COLOR_BUILDING_LOW := Color(0.55, 0.53, 0.48)
const COLOR_BUILDING_HIGH := Color(0.25, 0.25, 0.24)
const COLOR_WATER := Color(0.35, 0.55, 0.65)
const COLOR_PLAYER := Color(1, 1, 1)
const COLOR_VISTA := Color(0.95, 0.85, 0.4)
const COLOR_TEXT := Color(0.1, 0.1, 0.1)
# 場所の名前：[名前, 世界の位置（x, z）]
const PLACES := [
	["落ち高架", Vector2(0, 44)],
	["花梨通り", Vector2(0, 26)],
	["止まり時計の広場", Vector2(0, -3)],
	["書店街の抜け道", Vector2(0, -20)],
	["旧市民ホール", Vector2(0, -46)],
	["見晴らし塔", Vector2(80, 40)],
	["白砂川", Vector2(-60, 99)],
]

var world_root: Node3D
var player: Player
var is_open := false
var _boxes: Array = []             # [XZ の4つの角（PackedVector2Array）, 高さ]
var _waters: Array[Rect2] = []
var _collected := false
var _back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_back = Button.new()
	_back.text = "戻る（Esc ／ ○）"
	_back.custom_minimum_size = Vector2(220, 44)
	_back.add_theme_font_size_override("font_size", 18)
	_back.anchor_left = 1.0
	_back.anchor_right = 1.0
	_back.anchor_top = 1.0
	_back.anchor_bottom = 1.0
	_back.offset_left = -240
	_back.offset_right = -20
	_back.offset_top = -64
	_back.offset_bottom = -20
	_back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(_back)


func open() -> void:
	if not _collected:
		_collect()
	is_open = true
	visible = true
	_back.grab_focus()
	queue_redraw()


func close() -> void:
	is_open = false
	visible = false


# 世界の位置 → 地図の上の位置（ピクセル）
func world_to_map(p: Vector2) -> Vector2:
	var r := map_rect()
	var t := (p - CityBuilder.CITY_MIN) / (CityBuilder.CITY_MAX - CityBuilder.CITY_MIN)
	return r.position + t * r.size


# 地図を描く四角（画面の真ん中。街の縦横の比を保つ）
func map_rect() -> Rect2:
	var world_size := CityBuilder.CITY_MAX - CityBuilder.CITY_MIN
	var h := size.y * MAP_RATIO
	var w := h * world_size.x / world_size.y
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))


func box_count() -> int:
	return _boxes.size()


# 建物（箱の当たり判定）と水を集める
func _collect() -> void:
	_collected = true
	if world_root == null:
		return
	for body in world_root.find_children("*", "StaticBody3D", true, false):
		if body.is_in_group("invisible_wall"):
			continue
		for shape_node in body.get_children():
			if not shape_node is CollisionShape3D or not (shape_node as CollisionShape3D).shape is BoxShape3D:
				continue
			var cs := shape_node as CollisionShape3D
			var s: Vector3 = (cs.shape as BoxShape3D).size
			var xf := cs.global_transform
			var top := xf.origin.y + s.y * 0.5
			if s.y < MIN_HEIGHT or top < MIN_HEIGHT or maxf(s.x, s.z) < MIN_WIDTH:
				continue
			var pts := PackedVector2Array()
			for c in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
				var w: Vector3 = xf * ((c as Vector3) * s * 0.5)
				pts.append(Vector2(w.x, w.z))
			_boxes.append([pts, top])
	_boxes.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])  # 低い物から描く（高い物が上に重なる）
	for wn in get_tree().get_nodes_in_group("water"):
		var water := wn as Node3D
		var ws: Vector3 = water.get("size")
		_waters.append(Rect2(water.global_position.x - ws.x * 0.5, water.global_position.z - ws.z * 0.5, ws.x, ws.z))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	var r := map_rect()
	draw_rect(r, COLOR_GROUND)
	for wr in _waters:
		var a := world_to_map(wr.position)
		var b := world_to_map(wr.end)
		draw_rect(Rect2(a, b - a), COLOR_WATER)
	for bx in _boxes:
		var pts := PackedVector2Array()
		for p in bx[0]:
			pts.append(world_to_map(p))
		var k := clampf(float(bx[1]) / 25.0, 0.0, 1.0)
		draw_colored_polygon(pts, COLOR_BUILDING_LOW.lerp(COLOR_BUILDING_HIGH, k))
	draw_rect(r, Color(0.9, 0.88, 0.8), false, 2.0)
	var font := get_theme_default_font()
	for pl in PLACES:
		var mp := world_to_map(pl[1])
		var text: String = pl[0]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string_outline(font, mp + Vector2(-tw * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(1, 1, 1, 0.85))
		draw_string(font, mp + Vector2(-tw * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_TEXT)
	# 見た眺めのいい場所に、黄色い印
	for v in get_tree().get_nodes_in_group("vistas"):
		if Discoveries.vistas.has(v.vista_id):
			draw_circle(world_to_map(Vector2(v.global_position.x, v.global_position.z)), 6.0, COLOR_VISTA)
	# 自分：位置と向き（白い三角）
	if player != null:
		var pp := world_to_map(Vector2(player.global_position.x, player.global_position.z))
		var f3 := -player.global_transform.basis.z
		var f := Vector2(f3.x, f3.z).normalized() if Vector2(f3.x, f3.z).length() > 0.01 else Vector2.UP
		var side := Vector2(-f.y, f.x)
		var tri := PackedVector2Array([pp + f * 12.0, pp - f * 7.0 + side * 7.0, pp - f * 7.0 - side * 7.0])
		draw_colored_polygon(tri, COLOR_PLAYER)
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color.BLACK, 2.0)
	draw_string_outline(font, Vector2(r.position.x, r.position.y - 10), "白砂市（上が奥）", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color.BLACK)
	draw_string(font, Vector2(r.position.x, r.position.y - 10), "白砂市（上が奥）", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.93, 0.86))
