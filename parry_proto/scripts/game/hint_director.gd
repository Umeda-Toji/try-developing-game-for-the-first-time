# Godot 4.7.2 / GDScript
# res://scripts/game/hint_director.gd
#
# 操作のヒントを、その場所・その場面で1回だけ出す（U-11。11/20 決定）
#  ①スタート：移動・カメラ・ジャンプ　②高架の端：2段ジャンプと滑空　③水路：泳ぐ・壁のぼり
#  ④花梨通りの最初の敵：パリィ（白）・回避（赤）　⑤広場：ロックオン・強攻撃の溜め・ジャスト回避
#  ⑥初めて回復薬を拾ったとき　⑦街へ出たとき：銃・地図
#  ・出したヒントは Discoveries.hints_seen に覚えてセーブに残す（はじめからでまた出る）
#  ・設定の「操作のヒント」がオフなら出さない。白砂市のエリアのときだけ（main.gd が作る）
class_name HintDirector
extends Node

const START_DELAY := 30        # 始まってから最初のヒントを出すまで（フレーム）
const ENEMY_NEAR := 12.0       # 最初の敵がこれより近くで合図を出したら、パリィのヒント（m）
const OVERPASS_EDGE := Rect2(-3.0, 29.5, 6.0, 4.5)    # 高架の崩れた端のあたり（x, z）
const PLAZA := Rect2(-11.0, -12.0, 22.0, 22.0)
const ORDER := ["move", "glide", "swim", "parry", "plaza", "heal", "city"]
# [キーボード・マウスの文, パッドの文]
const TEXTS := {
	"move": ["WASD で移動、マウスでカメラ、Space でジャンプ", "左スティックで移動、右スティックでカメラ、× でジャンプ"],
	"glide": ["Space を2回でジャンプ。3回目を押し続けると、外套で滑空する", "× を2回でジャンプ。3回目を押し続けると、外套で滑空する"],
	"swim": ["水の中は泳げる（スタミナを使う）。壁に向かうと、つかまって登れる", "水の中は泳げる（スタミナを使う）。壁に向かうと、つかまって登れる"],
	"parry": ["花が白く咲いたら、左クリック（攻撃）でパリィ。赤く咲いたら Shift で回避", "花が白く咲いたら、△（攻撃）でパリィ。赤く咲いたら R2 で回避"],
	"plaza": ["Tab でロックオン（押すと次の敵、長押しで解除）。右クリック長押しで強攻撃を溜める\n攻撃が当たる直前に回避すると、ジャスト回避で敵が遅くなる",
		"L2 でロックオン（押すと次の敵、長押しで解除）。□長押しで強攻撃を溜める\n攻撃が当たる直前に回避すると、ジャスト回避で敵が遅くなる"],
	"heal": ["Q で回復薬を使う（HP+40。3つまで持てる）", "十字キー上で回復薬を使う（HP+40。3つまで持てる）"],
	"city": ["1・2・3 で銃、F で剣に持ち替え。左クリックで撃つ・右クリックで構える・R でリロード\n地図は Esc（ポーズ）から",
		"R3 で武器の輪。R1 で撃つ・L1 で構える・○ でリロード\n地図は OPTIONS（ポーズ）から"],
}

var main: Node
var box: HintBox
var _frames := 0


func _physics_process(_delta: float) -> void:
	if main == null or box == null or get_tree().paused or not GameSettings.hints:
		return
	var p: Player = main.player
	if p == null or p.is_dead():
		return
	_frames += 1
	var xz := Vector2(p.global_position.x, p.global_position.z)
	if _frames >= START_DELAY:
		_try("move")
	if OVERPASS_EDGE.has_point(xz) and p.global_position.y > 3.5:
		_try("glide")
	if p.state == Player.State.SWIM:
		_try("swim")
	var zako: Enemy = main.enemies[0] if not main.enemies.is_empty() else null
	if zako != null and is_instance_valid(zako) and zako.is_glinting() and zako.global_position.distance_to(p.global_position) < ENEMY_NEAR:
		_try("parry")
	if PLAZA.has_point(xz):
		_try("plaza")
	if Discoveries.heals > 0:
		_try("heal")
	if not CityBuilder.CORRIDOR.has_point(xz):
		_try("city")


func _try(id: String) -> void:
	if Discoveries.hints_seen.has(id):
		return
	Discoveries.hints_seen[id] = true
	var t: Array = TEXTS[id]
	box.show_hint(id, t[0], t[1])


# 操作の一覧（ポーズメニュー）：キーボード・マウスとパッドの両方
static func controls_text() -> String:
	var rows := [
		["移動", "WASD", "左スティック"], ["カメラ", "マウス（矢印キー）", "右スティック"],
		["攻撃（3段）・パリィ", "左クリック／J（出始めがパリィ）", "△"], ["強攻撃（長押しで溜め）", "右クリック／K", "□"],
		["回避（押し続けて走る）", "Shift", "R2"], ["ジャンプ（2回・3回目長押しで滑空）", "Space", "×"],
		["ロックオン（押すと次の敵・長押しで解除）", "Tab／ホイールクリック", "L2"], ["回復薬", "Q", "十字キー上"],
		["剣／AR／SMG／SG に持ち替え", "F／1／2／3", "武器の輪（R3。銃のときは△長押し）"],
		["撃つ／構える／リロード（銃のとき）", "左クリック／右クリック／R", "R1／L1／○"],
		["ポーズ（地図・設定・セーブ）", "Esc", "OPTIONS"], ["調整用の文字", "F3", "SHARE"],
	]
	var s := "[b]操作[/b]　　（キーボード・マウス ／ パッド）\n\n"
	for r in rows:
		s += "[b]%s[/b]\n　%s　／　%s\n" % [r[0], r[1], r[2]]
	s += "\n花が[b]白く[/b]咲いたら攻撃でパリィ、[b]赤く[/b]咲いたら回避。攻撃が当たる直前の回避はジャスト回避"
	return s
