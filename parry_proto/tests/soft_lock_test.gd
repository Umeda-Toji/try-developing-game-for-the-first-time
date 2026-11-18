# Godot 4.7.2 / GDScript
# res://tests/soft_lock_test.gd
# ソフトロック（P-17）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --soft-lock-test
#  敵を動かないようにしてから、敵を置く場所を変えて、ロックオンなしで弱攻撃を出し、向きを確かめる
#  （スティックは倒さない＝基準は正面）
extends Node

const CASE_FRAMES := 60         # 1つのケースの長さ（攻撃が終わるまで待つ）
const CHECK_FRAME := 3          # 攻撃ボタンを押してから向きを確かめるまで
const ANGLE_TOLERANCE_DEG := 5.0
const FAR := Vector3(0, 0.1, 9) # 使わない敵を置いておく場所（遠く）

var _main: Node
var _player: Player
var _zako: Enemy
var _boss: Enemy
var _frame := 0
var _case := 0
var _results := {}

# ケース：[名前, ザコの位置（プレイヤーから見て）, ボスの位置, 向くはずの相手（"zako"/"boss"/"" = 向きを変えない）]
# プレイヤーの正面は -Z。右は +X
var _cases := [
	["右前60°・3mのザコを向く", _polar(60, 3.0), FAR, "zako"],
	["真後ろのザコには振り向かない", _polar(180, 3.0), FAR, ""],
	["8m先（範囲外）のザコには振り向かない", _polar(20, 8.0), FAR, ""],
	["正面に近い方（ボス）を選ぶ", _polar(40, 3.0), _polar(-10, 4.0), "boss"],
]


func _ready() -> void:
	process_physics_priority = -100  # プレイヤーより先に入力を入れる
	_main = get_parent()
	_player = _main.player
	_zako = _main.enemies[0]
	_boss = _main.boss
	_main.remove_extra_enemies()  # ザコとボスだけで試す
	# 敵が動いたり攻撃したりしないようにする
	for e in _main.enemies:
		e.aggro_range = 0.0
		e.move_speed = 0.0
		e.attack_range = 0.0


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _case >= _cases.size():
		print("==== ソフトロックテスト結果 ====")
		for k in _results.keys():
			print("%s: %s" % [k, str(_results[k])])
		_main.quit_game()  # 音を止めてから終了する
		return

	var t := _frame - _case * CASE_FRAMES
	var c: Array = _cases[_case]
	if t == 1:
		# 配置：プレイヤーは原点で正面（-Z）向き
		_player.global_position = Vector3(0, 0.1, 0)
		_player.rotation.y = 0.0
		_zako.global_position = Vector3(0, 0.1, 0) + c[1]
		_boss.global_position = Vector3(0, 0.1, 0) + c[2]
	elif t == 3:
		Input.action_press("attack_light")
	elif t == 4:
		Input.action_release("attack_light")
	elif t == 3 + CHECK_FRAME:
		_results[c[0]] = _check_facing(c[3], c[1], c[2])
	elif t == CASE_FRAMES:
		_case += 1


func _check_facing(expect: String, zako_pos: Vector3, boss_pos: Vector3) -> bool:
	var fwd := -_player.global_transform.basis.z
	fwd.y = 0.0
	var want := Vector3(0, 0, -1)  # 向きを変えないなら、正面のまま
	if expect == "zako":
		want = zako_pos
	elif expect == "boss":
		want = boss_pos
	want.y = 0.0
	return rad_to_deg(fwd.normalized().angle_to(want.normalized())) < ANGLE_TOLERANCE_DEG


# 正面（-Z）から右回りに deg 度、距離 dist の位置
static func _polar(deg: float, dist: float) -> Vector3:
	var r := deg_to_rad(deg)
	return Vector3(sin(r), 0.0, -cos(r)) * dist
