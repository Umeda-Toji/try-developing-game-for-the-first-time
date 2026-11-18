# Godot 4.7.2 / GDScript
# res://tests/enemy_types_test.gd
# 新しい敵（E-12 重装兵・E-13 双剣士）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --enemy-types-test
#  ・数値が表（REQUIREMENTS.md 5.3）どおり／武器を持っている（双剣士は両手）
#  ・難易度「むずかしい」の倍率が掛かる
#  ・重装兵：攻撃2回のうち2回目がパリィできない（赤く光る）
#  ・双剣士：1回の攻撃が3連撃
#  プレイヤーは動かさない（HPを大きくして倒れないようにする）。ザコとボスは動かさない
extends Node

const HEAVY_ATTACKS := 2       # 重装兵の攻撃をこの回数見る
const TIMEOUT_FRAMES := 900

var _main: Node
var _player: Player
var _heavy: Enemy
var _swift: Enemy
var _frame := 0
var _step := 0
var _results := {}
var _heavy_unparryable: Array[bool] = []   # 重装兵の攻撃ごとの「パリィ不可」
var _swift_hits := 0                       # 双剣士の1回目の攻撃で、判定が出た回数
var _swift_done := false


func _ready() -> void:
	_main = get_parent()
	_player = _main.player
	_heavy = _main.heavy
	_swift = _main.swift
	_main.enemies[0].aggro_range = 0.0
	_main.boss.aggro_range = 0.0
	_swift.aggro_range = 0.0  # 先に重装兵だけを試す
	_main.caster.aggro_range = 0.0  # 魔法使いは ranged_test.gd で試す
	_player.hp = 100000


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _step:
		0:
			_check_numbers()
			# 重装兵をプレイヤーの目の前へ
			_heavy.global_position = _player.global_position + Vector3(0, 0, -2.0)
			_step = 1
		1:
			if _heavy.state == Enemy.State.ATTACK and _heavy.state_frame == 0 and _heavy.hitstop_frames == 0:
				if _heavy_unparryable.size() < _heavy._attack_count:
					_heavy_unparryable.append(_heavy._current_unparryable)
			if _heavy_unparryable.size() >= HEAVY_ATTACKS or _frame > TIMEOUT_FRAMES:
				_results["重装兵：2回目の攻撃がパリィ不可 %s" % str(_heavy_unparryable)] = _heavy_unparryable == [false, true]
				# 次は双剣士。重装兵は止める
				_heavy.aggro_range = 0.0
				_heavy.global_position = Vector3(-8, 0.1, -8)
				_heavy._set_state(Enemy.State.IDLE)
				_swift.aggro_range = 10.0
				_swift.global_position = _player.global_position + Vector3(0, 0, -1.6)
				_step = 2
		2:
			if _swift._attack_count == 1 and _swift.state == Enemy.State.ATTACK and _swift.state_frame == 0 and _swift.hitstop_frames == 0:
				_swift_hits += 1
			if _swift._attack_count >= 1 and _swift.state == Enemy.State.RECOVER:
				_swift_done = true
			if _swift_done or _frame > TIMEOUT_FRAMES * 2:
				_results["双剣士：1回の攻撃が3連撃（%d回）" % _swift_hits] = _swift_hits == 3
				_finish()


func _check_numbers() -> void:
	var h := _heavy
	var s := _swift
	_results["重装兵の数値（HP120・体幹100・予兆50・ダメージ25・2回に1回パリィ不可）"] = (
		h.max_hp == 120 and h.max_posture == 100.0 and h.telegraph_frames == 50 and h.damage == 25 and h.unparryable_every == 2)
	_results["双剣士の数値（HP50・体幹40・予兆24・3連撃・間隔14・ダメージ8）"] = (
		s.max_hp == 50 and s.max_posture == 40.0 and s.telegraph_frames == 24 and s.combo_hits == 3
		and s.combo_gap_frames == 14 and s.damage == 8)
	_results["重装兵はハンマーを持つ"] = h.model.find_child("Sword", true, false) != null
	_results["双剣士は両手に短剣を持つ"] = s.model.find_child("Sword", true, false) != null and s.model.find_child("Sword_L", true, false) != null
	_results["重装兵は双剣士より大きい"] = h.model.scale.x > s.model.scale.x
	# 難易度「むずかしい」：予兆×0.85・間隔×0.85・ダメージ×1.5（四捨五入）
	Difficulty.current = Difficulty.HARD
	h.apply_difficulty()
	s.apply_difficulty()
	_results["むずかしい：重装兵 予兆43・ダメージ38"] = h.telegraph_frames == 43 and h.damage == 38
	_results["むずかしい：双剣士 予兆20・間隔12・ダメージ12"] = s.telegraph_frames == 20 and s.combo_gap_frames == 12 and s.damage == 12
	Difficulty.current = Difficulty.NORMAL
	h.apply_difficulty()
	s.apply_difficulty()


func _finish() -> void:
	print("==== 敵の種類テスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
