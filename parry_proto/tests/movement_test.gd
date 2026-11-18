# Godot 4.7.2 / GDScript
# res://tests/movement_test.gd
# 移動（M-01〜M-04：ジャンプ・2段ジャンプ・滑空・走る・スタミナ）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --movement-test
#  敵は片付ける・動かさない。プレイヤーにボタンを押させて、高さ・速さ・スタミナを確かめる
extends Node

const TIMEOUT := 300

var _main: Node
var _p: Player
var _frame := 0
var _step := 0
var _t := 0
var _results := {}
var _release: Array[String] = []
var _ground_y := 0.0
var _max_y := 0.0
var _first_height := 0.0
var _stamina_before := 0.0
var _glide_min_vy := 0.0
var _glide_frames := 0
var _second_pressed := false


func _ready() -> void:
	process_physics_priority = -100  # プレイヤーより先に入力を入れる
	_main = get_parent()
	_p = _main.player
	_main.remove_extra_enemies()
	for e in _main.enemies:
		e.aggro_range = 0.0
	_p.global_position = Vector3(0, 0.1, 8)


func _physics_process(_delta: float) -> void:
	_frame += 1
	_t += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()
	match _step:
		0:  # 地面に立つのを待つ
			if _t > 20 and _p.is_on_floor():
				_ground_y = _p.global_position.y
				_stamina_before = _p.stamina
				_max_y = _ground_y
				_press("jump")
				_next()
		1:  # 1回目のジャンプの高さ
			_max_y = maxf(_max_y, _p.global_position.y)
			if _t == 2:
				_results["ジャンプではスタミナが減らない（%.0f → %.0f）" % [_stamina_before, _p.stamina]] = _p.stamina >= _stamina_before
			if _t > 5 and _p.is_on_floor():
				_first_height = _max_y - _ground_y
				_results["ジャンプの高さ %.2fm（1.2〜1.7m）" % _first_height] = _first_height > 1.2 and _first_height < 1.7
				_results["着地すると跳んだ回数が0に戻る"] = _p.jumps_used == 0
				_max_y = _ground_y
				_press("jump")
				_next()
		2:  # 2段ジャンプ：1回目の頂上（上へ進む速さが0近く）で2回目
			_max_y = maxf(_max_y, _p.global_position.y)
			if _p.jumps_used == 1 and _p.velocity.y < 0.5 and _t > 3 and not _second_pressed:
				_press("jump")
				_second_pressed = true
			if _p.jumps_used == 2 and _p.velocity.y < 0.0:
				_results["2段ジャンプは1回目より高い（%.2fm）" % (_max_y - _ground_y)] = _max_y - _ground_y > _first_height + 0.8
				# 3回目：押し続けると滑空
				Input.action_press("jump")
				Input.action_press("move_forward")
				_next()
			elif _t > TIMEOUT:
				_fail("2段ジャンプ")
		3:  # 滑空
			if _p.gliding:
				_glide_frames += 1
				_glide_min_vy = minf(_glide_min_vy, _p.velocity.y)
			if _glide_frames == 30 and Input.is_action_pressed("jump"):
				var hs := Vector2(_p.velocity.x, _p.velocity.z).length()
				_results["滑空すると前へ進む（%.1f m/秒）" % hs] = absf(hs - Player.GLIDE_SPEED) < 0.5
				Input.action_release("jump")  # 離すと普通に落ちる
			if _glide_frames >= 30 and not Input.is_action_pressed("jump"):
				if not _p.gliding:
					_results["滑空中はゆっくり落ちる（最も速くて %.1f m/秒）" % -_glide_min_vy] = _glide_min_vy >= -Player.GLIDE_FALL_SPEED - 0.01
					_results["ジャンプを離すと滑空をやめる"] = true
					Input.action_release("move_forward")
					_next()
			elif _t > TIMEOUT:
				Input.action_release("jump")
				Input.action_release("move_forward")
				_fail("滑空")
		4:  # 着地を待って、スタミナを満タンにしてから走る
			if _p.is_on_floor() and _t > 5:
				_p.stamina = Player.STAMINA_MAX
				_p.global_position = Vector3(0, 0.1, 8)
				_p.rotation.y = 0.0
				Input.action_press("move_forward")
				Input.action_press("dodge")  # 回避して、押し続ける
				_next()
		5:  # 走る
			if _t == 2:
				_results["回避でスタミナが20減る（%.0f）" % _p.stamina] = _p.stamina <= Player.STAMINA_MAX - Player.STAMINA_COST_DODGE
			if _t == Player.DODGE_TOTAL_FRAMES + 10:
				var hs := Vector2(_p.velocity.x, _p.velocity.z).length()
				_results["回避ボタンを押し続けると走る（%.1f m/秒）" % hs] = _p.sprinting and absf(hs - Player.SPRINT_SPEED) < 0.5
				_stamina_before = _p.stamina
			if _t == Player.DODGE_TOTAL_FRAMES + 20:
				_results["走っている間はスタミナが減る"] = _p.stamina < _stamina_before
				_p.stamina = 2.0  # もうすぐ切れる
			if _t == Player.DODGE_TOTAL_FRAMES + 30:
				var hs := Vector2(_p.velocity.x, _p.velocity.z).length()
				_results["スタミナが切れると走れない（%.1f m/秒）" % hs] = not _p.sprinting and absf(hs - Player.MOVE_SPEED) < 0.5
				Input.action_release("dodge")
				Input.action_release("move_forward")
		6:
			pass
	if _step == 5 and _t == Player.DODGE_TOTAL_FRAMES + 32:
		# スタミナ 0：回避もジャンプもできない
		_p.stamina = 0.0
		_press("dodge")
		_next()
	elif _step == 6:
		if _t == 2:
			_p.stamina = 0.0
			_results["スタミナ0では回避できない"] = _p.state != Player.State.DODGE
			_press("jump")
		elif _t == 4:
			_results["スタミナ0でもジャンプはできる"] = _p.jumps_used == 1
		elif _t == 4 + Player.STAMINA_REGEN_DELAY_FRAMES + 10:
			_results["しばらく使わないとスタミナが回復する（%.1f）" % _p.stamina] = _p.stamina > 0.0
			_finish()


func _next() -> void:
	_step += 1
	_t = 0


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)


func _fail(what: String) -> void:
	_results[what + "（時間切れ）"] = false
	_finish()


func _finish() -> void:
	_step = 99
	print("==== 移動テスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
