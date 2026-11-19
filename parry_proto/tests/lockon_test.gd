# Godot 4.7.2 / GDScript
# res://tests/lockon_test.gd
# ロックオンの切り替え（L-01）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --lockon-test
#  （20m四方の部屋。敵は動かさない）
#  1. 押すと、いちばん近い敵にロックオン
#  2. ロックオン中に短く押すと、次に近い敵に切り替わる（近い順。いちばん遠い敵の次は、いちばん近い敵）
#  3. 押し続けて、押してから44フレームではまだロックオン、45フレームで解除。離しても切り替わらない
#  4. 敵が1体しかいないときに押しても、何も変わらない
#  （テストから押したボタンは、プレイヤーには1フレーム遅れて届くので、押す・離す・確かめるの間を2フレーム空ける）
extends Node

const TAP := 6   # 短く押す1回の長さ：0で押す、2で離す、4で確かめる

var _main: Node
var _p: Player
var _t := 0
var _results := {}
var _order: Array[Node3D] = []
var _seen: Array[Node3D] = []
var _hold_prev_frames := -1
var _hold_prev_locked := false
var _hold_checked := false
var _single: Node3D


func _ready() -> void:
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	for e in _main.enemies:
		e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_t += 1
	if _t == 10:
		_order = _p.lock_candidates()
		_tap_step(0)
	elif _t > 10 and _t < 10 + TAP:
		_tap_step(_t - 10)
		if _t - 10 == 4:
			_results["押すと、いちばん近い敵にロックオン（%s）" % _name(_p.lock_target)] = _p.lock_target == _order[0]
			_seen = [_p.lock_target]
	# 短く押すのを、敵の数だけくり返す
	elif _t >= 20 and _t < 20 + _order.size() * TAP:
		var k := (_t - 20) % TAP
		_tap_step(k)
		if k == 4:
			_seen.append(_p.lock_target)
	elif _t == 20 + _order.size() * TAP:
		var names := _seen.map(func(e): return _name(e))
		var expect: Array[Node3D] = _order.duplicate()
		expect.append(_order[0])
		_results["短く押すと、近い順に切り替わり、最後はいちばん近い敵に戻る（%s）" % ", ".join(names)] = _seen == expect
		Input.action_press("lock_on")  # 押し続ける
		_t = 200
	elif _t > 200 and _t < 300:
		# 押し続けている間：押した数のフレームが 44 → 45 になったときに解除されるか
		var f: int = _p._lock_hold_frames
		var locked := _p.lock_target != null
		if not _hold_checked and _hold_prev_locked and not locked:
			_results["押してから %d フレームではロックオン、%d フレームで解除" % [_hold_prev_frames, f]] = (
				_hold_prev_frames == Player.LOCK_RELEASE_HOLD_FRAMES - 1 and f == Player.LOCK_RELEASE_HOLD_FRAMES)
			_hold_checked = true
		_hold_prev_frames = f
		_hold_prev_locked = locked
		if _t == 270:
			Input.action_release("lock_on")
		if _t == 274:
			if not _hold_checked:
				_results["押し続けると解除（解除されなかった）"] = false
			_results["解除した後に離しても、切り替わらない"] = _p.lock_target == null
			# 敵を1体だけにする（ほかの敵は片付けて、ボスは遠くへ）
			_main.remove_extra_enemies()
			_main.boss.global_position = Vector3(0, 0.1, -200)
			_t = 299  # 次のフレームが 300（押す）
	elif _t >= 300 and _t < 300 + TAP:
		_tap_step(_t - 300)
		if _t - 300 == 4:
			_single = _p.lock_target
	elif _t >= 310 and _t < 310 + TAP:
		_tap_step(_t - 310)
		if _t - 310 == 4:
			_results["敵が1体のときに押しても、何も変わらない（%s）" % _name(_p.lock_target)] = _single != null and _p.lock_target == _single
			print("==== ロックオンのテスト結果 ====")
			for k in _results.keys():
				print("%s: %s" % [k, str(_results[k])])
			_main.quit_game()


func _tap_step(k: int) -> void:
	if k == 0:
		Input.action_press("lock_on")
	elif k == 2:
		Input.action_release("lock_on")


func _name(e: Node3D) -> String:
	return "なし" if e == null else str(e.get("display_name"))
