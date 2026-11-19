# Godot 4.7.2 / GDScript
# res://tests/phase2_test.gd
# ボス第2形態（E-11）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --phase2-test
#  1. HP が50%を切るまでは第1形態のまま
#  2. 50%を切ると第2形態：切り替わり中（無敵）になり、体幹がリセット、数値が変わる
#  3. 切り替わりが終わると動き出す
#  4. 第2形態では、パリィ不可（3・6・9回目）とフェイントが同じ攻撃に重ならない
extends Node

var _main: Node
var _boss: Enemy
var _frame := 0
var _change_start := -1
var _results := {}


func _ready() -> void:
	process_physics_priority = -100
	_main = get_parent()
	_boss = _main.boss
	# プレイヤーとザコは遠くに置き、ボスは追いかけてこないようにする
	_main.enemies[0].aggro_range = 0.0
	_boss.aggro_range = 0.0
	_main.remove_extra_enemies()  # ボスだけで試す


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == 5:
		_boss.posture = 50.0
		_hit(140)  # 300 → 160（まだ50%より上）
		_results["HP160では第1形態のまま"] = not _boss.is_phase2()
		# BGM（F-07）：最初は通常の曲。どちらの曲もループする設定になっているか
		var bgm: Bgm = _main.bgm
		# 最初は探索の曲（A-01）。ボスが近くにいて気づかれていれば、もう戦闘の曲になっている
		_results["BGM：最初は探索の曲か戦闘の曲（%s）" % bgm.current] = (bgm.current == "explore" or bgm.current == "battle") and bgm.is_playing(bgm.current)
		var battle_stream := bgm.get_node("Bgm_battle").stream as AudioStreamOggVorbis
		var boss_stream := bgm.get_node("Bgm_boss").stream as AudioStreamWAV
		_results["BGM：2曲ともループする"] = battle_stream.loop and boss_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
	elif _frame == 10:
		_hit(20)  # 160 → 140（50%を切る）
		_results["HP50%を切ると第2形態"] = _boss.is_phase2()
		_results["切り替わりの演出に入る"] = _boss.state == Enemy.State.PHASE_CHANGE
		_results["体幹がリセットされる"] = _boss.posture == 0.0
		_results["溜めが30・連撃4になる"] = _boss.telegraph_frames == 30 and _boss.combo_hits == 4
		var hp_before := _boss.hp
		var r := _boss.receive_attack(_payload(50), _main.player)
		_results["切り替わり中は無敵"] = r == Combat.HitResult.IGNORED and _boss.hp == hp_before
		_change_start = _frame
	elif _change_start > 0 and _boss.state != Enemy.State.PHASE_CHANGE:
		var took := _frame - _change_start
		_results["切り替わりが終わると動き出す（%dフレーム）" % took] = took >= _boss.phase2_transition_frames
		_results["BGM：第2形態でボスの曲に切り替わる"] = _main.bgm.current == "boss" and _main.bgm.is_playing("boss")
		_check_pattern()
		_finish()
	elif _frame > 600:
		_results["切り替わりが終わる"] = false
		_finish()


# 第2形態の攻撃1〜9回目の「パリィ不可」と「フェイント」を調べる
func _check_pattern() -> void:
	var feints: Array[int] = []
	var overlap := false
	for n in range(1, 10):
		_boss._attack_count = n - 1
		_boss._begin_combo()
		if _boss._current_feint:
			feints.append(n)
		if _boss._current_feint and _boss._current_unparryable:
			overlap = true
	_results["フェイントは %s 回目" % str(feints)] = feints == [2, 5, 8]
	_results["パリィ不可とフェイントが重ならない"] = not overlap


func _hit(damage: int) -> void:
	_boss.receive_attack(_payload(damage), _main.player)


func _payload(damage: int) -> Dictionary:
	return {"damage": damage, "posture": 0, "hitstop": 0, "shake": 0.0}


func _finish() -> void:
	print("==== 第2形態テスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()  # 音を止めてから終了する
