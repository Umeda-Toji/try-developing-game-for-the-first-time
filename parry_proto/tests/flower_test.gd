# Godot 4.7.2 / GDScript
# res://tests/flower_test.gd
# 敵の頭の花（F-01）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --flower-test
#  （20m四方の部屋）
#  1. どの敵にも花があり、最初はつぼみ
#  2. ザコの普通の攻撃：合図で白く開き、6フレームで開ききる。攻撃が終わると20フレームでつぼみに戻る。今の光（E-15）も出ている
#  3. ザコのフェイント：ニセの光では半分だけ白く開き、本物の光で開ききる
#  4. 重装兵のパリィできない攻撃：赤く開く
#  5. 倒れると満開（1.3）になり、白っぽくなる
#  6. ボスの第2形態：肩と背中の花（3つ）が咲く
extends Node

const TIMEOUT := 900

var _main: Node
var _p: Player
var _zako: Enemy
var _t := 0
var _step := 0
var _results := {}
var _f := {}   # 観察のメモ


func _ready() -> void:
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	_zako = _main.enemies[0]
	for e in _main.enemies:
		e.aggro_range = 0.0
	if "--flower-hold" in OS.get_cmdline_user_args():
		_f["hold"] = true


func _physics_process(_delta: float) -> void:
	_t += 1
	_p.hp = _p.max_hp  # 当たっても倒れないように
	if _f.get("hold", false) or "--flower-hold" in OS.get_cmdline_user_args():
		# 録画で見るとき：目印のフレームを出す（静止画を選ぶため）
		if _zako.is_glinting() and _zako.flower.open_amount >= 1.0:
			print("EVT glint ", Engine.get_frames_drawn())
		if _step == 4 and _t == int(_f.get("dead_t", 0)) + 30:
			print("EVT dead ", Engine.get_frames_drawn())
		if _step >= 5 and _t == int(_f.get("p2_t", 0)) + 90:
			print("EVT boss ", Engine.get_frames_drawn())
		_close_up()
	if _t > TIMEOUT and _step < 99:
		_results["時間内に終わる（step %d）" % _step] = false
		_finish()
		return
	match _step:
		0:
			if _t == 4 and "--flower-debug" in OS.get_cmdline_user_args():
				for e in _main.enemies:
					var sk := e.model.find_child("Skeleton3D", true, false) as Skeleton3D
					var hi := sk.find_bone("Head")
					var head: Vector3 = (sk.global_transform * sk.get_bone_global_pose(hi)).origin
					var rest: Vector3 = (sk.global_transform * sk.get_bone_global_rest(hi)).origin
					var fw: Vector3 = -e.global_basis.z
					var rt: Vector3 = Vector3.UP.cross(fw).normalized()
					var d: Vector3 = e.flower.global_position - head
					print("DBG %s pos=%s head=%s rest=%s d(fwd,up,right)=(%.2f,%.2f,%.2f) flowerY.fwd=%.2f skel_scale=%.2f model_rot=%s" % [e.display_name, str(e.global_position), str(head), str(rest), d.dot(fw), d.y, d.dot(rt), e.flower.global_basis.y.normalized().dot(fw), sk.global_basis.get_scale().x, str(e.model.rotation_degrees)])
			if _t == 5:
				var all_ok := true
				for e in _main.enemies:
					var fl: EnemyFlower = e.flower
					if fl == null or fl.open_amount != 0.0 or not fl._bud.visible:
						all_ok = false
				_results["どの敵にも花があり、最初はつぼみ（%d体）" % _main.enemies.size()] = all_ok
				_p.global_position = Vector3(-3, 0.1, 1.2)  # ザコの前
				_zako.aggro_range = 15.0
				_zako._attack_count = 0  # 次は普通の攻撃
				_step = 1
		1:  # 普通の攻撃
			var fl: EnemyFlower = _zako.flower
			if _zako.is_glinting() and not _f.has("g0"):
				_f["g0"] = _t
				_results["合図のときは、今の光（まわりの赤い光）も出る"] = true
			if _f.has("g0") and _t == int(_f["g0"]) + EnemyFlower.OPEN_FRAMES:
				_results["合図で白く開き、%d フレームで開ききる（%.2f）" % [EnemyFlower.OPEN_FRAMES, fl.open_amount]] = (
					is_equal_approx(fl.open_amount, 1.0) and fl.color == EnemyFlower.COLOR_WHITE)
				var light_on: bool = _zako.warn_light.light_energy > 0.0
				_results["合図のときは、今の光（まわりの赤い光）も出る"] = light_on
			if _f.has("g0") and not _f.has("a_end") and _zako.state != Enemy.State.ATTACK and _zako.state != Enemy.State.TELEGRAPH:
				_f["a_end"] = _t
			if _f.has("a_end") and not _f.has("closed") and fl.open_amount <= 0.0:
				_f["closed"] = _t - int(_f["a_end"])
				_results["攻撃が終わると %d フレームでつぼみに戻る" % int(_f["closed"])] = absi(int(_f["closed"]) - EnemyFlower.CLOSE_FRAMES) <= 1 and fl.color == EnemyFlower.COLOR_BUD
				_f.clear()
				_zako._attack_count = 2  # 次はフェイント
				_step = 2
		2:  # フェイント
			var fl: EnemyFlower = _zako.flower
			if _zako.is_fake_glint():
				_f["fake_max"] = maxf(float(_f.get("fake_max", 0.0)), fl.open_amount)
				_f["fake_white"] = fl.color == EnemyFlower.COLOR_WHITE
			if _f.has("fake_max") and _zako.is_glinting() and not _zako.is_fake_glint():
				_f["real_max"] = maxf(float(_f.get("real_max", 0.0)), fl.open_amount)
			if _f.has("real_max") and _zako.state == Enemy.State.ATTACK and not _f.has("done"):
				_f["done"] = true
				_results["フェイントのニセの光では半分だけ白く開く（%.2f）" % float(_f["fake_max"])] = (
					absf(float(_f["fake_max"]) - EnemyFlower.FEINT_OPEN) < 0.01 and bool(_f["fake_white"]))
				_results["本物の光で開ききる（%.2f）" % fl.open_amount] = is_equal_approx(fl.open_amount, 1.0)
				_zako.aggro_range = 0.0
				_f.clear()
				# 重装兵：次はパリィできない攻撃
				var heavy: Enemy = _main.heavy
				_p.global_position = heavy.global_position + Vector3(0, 0, 2.0)
				heavy.aggro_range = 15.0
				heavy._attack_count = 1
				_step = 3
		3:  # パリィできない攻撃
			var heavy: Enemy = _main.heavy
			if heavy.is_glinting() and heavy.flower.open_amount >= 1.0 and not _f.has("red"):
				_f["red"] = true
				_results["パリィできない攻撃では赤く開く"] = heavy._current_unparryable and heavy.flower.color == EnemyFlower.COLOR_RED
				heavy.aggro_range = 0.0
				_zako.receive_attack({"damage": 9999, "posture": 0, "hitstop": 0}, _p)
				_f["dead_t"] = _t
				_step = 4
		4:  # 倒れる
			if _t == int(_f["dead_t"]) + 40:
				var fl: EnemyFlower = _zako.flower
				_results["倒れると満開（%.2f）になり、白っぽくなる" % fl.open_amount] = is_equal_approx(fl.open_amount, EnemyFlower.DEATH_OPEN) and fl.color == EnemyFlower.COLOR_DEAD
				var boss: Enemy = _main.boss
				_results["ボスには肩と背中の花が %d つあり、最初は咲いていない" % boss.flower.extra_count()] = boss.flower.extra_count() == 3 and boss.flower.extra_amount() == 0.0
				boss.receive_attack({"damage": int(boss.max_hp * 0.6), "posture": 0, "hitstop": 0}, _p)
				_f["p2_t"] = _t
				_step = 5
		5:  # 第2形態
			var boss: Enemy = _main.boss
			if _t == int(_f["p2_t"]) + boss.phase2_transition_frames + 5:
				_results["第2形態で、肩と背中の花が咲く（%.2f）" % boss.flower.extra_amount()] = boss.is_phase2() and is_equal_approx(boss.flower.extra_amount(), 1.0)
				if _f.has("hold"):
					_step = 6
				else:
					_finish()
		6:
			if _t == int(_f["p2_t"]) + 200:
				_finish()


# 録画で見るとき：今見ている敵の顔の前にカメラを置く
var _cam: Camera3D
func _close_up() -> void:
	if _cam == null:
		_cam = Camera3D.new()
		add_child(_cam)
		_cam.make_current()
	var who: Enemy = _zako
	if _step == 3:
		who = _main.heavy
	elif _step >= 5 or (_step == 4 and _t > int(_f.get("dead_t", 0)) + 35):
		who = _main.boss
	var big: bool = who == _main.boss
	var fwd := -who.global_transform.basis.z
	if big:  # ボスはプレイヤーの方から見る（壁に入らないように）
		var to_p := _p.global_position - who.global_position
		to_p.y = 0.0
		fwd = to_p.normalized()
	var h := 2.6 if big else 1.5
	_cam.global_position = who.global_position + fwd * (3.2 if big else 2.0) + Vector3.UP * h + who.global_transform.basis.x * 0.6
	_cam.look_at(who.global_position + Vector3.UP * (h - 0.2))


func _finish() -> void:
	_step = 99
	print("==== 頭の花のテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
