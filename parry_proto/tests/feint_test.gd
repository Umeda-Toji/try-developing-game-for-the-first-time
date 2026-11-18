# Godot 4.7.2 / GDScript
# res://tests/feint_test.gd
# ザコのフェイント攻撃（E-10）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --feint-test
#  1. フェイント：溜めが66フレームで、途中（26フレーム目）にニセの光が出る
#  2. ニセの光で攻撃ボタンを押す → パリィにならず、本物の攻撃が当たる
#  3. フェイント：本物の光（2回目）で押す → パリィ成功
#  4. 普通の攻撃：溜めは36フレームで、ニセの光は出ない
extends Node

const TIMEOUT_FRAMES := 2000

var _main: Node
var _player: Player
var _zako: Enemy
var _frame := 0
var _step := 0
var _results := {}
var _release: Array[String] = []
var _parry_count := 0

# 1回の攻撃の観察用
var _in_telegraph := false
var _telegraph_len := 0
var _fake_glint_first := -1
var _pressed := false
var _hp_before := 0
var _parry_before := 0


func _ready() -> void:
	process_physics_priority = -100  # プレイヤーより先に入力を入れる
	_main = get_parent()
	_player = _main.player
	_zako = _main.enemies[0]
	_main.boss.aggro_range = 0.0  # ボスは動かさない
	_main.remove_extra_enemies()  # ザコだけで試す
	_player.event_logged.connect(_on_player_log)
	_player.global_position = Vector3(0, 0.1, 0)
	_zako.global_position = Vector3(0, 0.1, -4)
	_set_next_feint(true)


func _physics_process(_delta: float) -> void:
	_frame += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()
	if _frame > TIMEOUT_FRAMES:
		_results["タイムアウトせずに終わる"] = false
		_finish()
		return

	_observe_telegraph()
	match _step:
		0:  # フェイント：ニセの光で押す
			if _zako.is_fake_glint() and not _pressed:
				_hp_before = _player.hp
				_parry_before = _parry_count
				_press("attack_light")
				_pressed = true
			if _pressed and _zako.state == Enemy.State.RECOVER:
				_results["フェイントの溜めが66フレーム（%d）" % _telegraph_len] = _telegraph_len == 66
				_results["ニセの光が26フレーム目に出る（%d）" % _fake_glint_first] = _fake_glint_first == 26
				_results["ニセの光で押すとパリィにならない"] = _parry_count == _parry_before
				_results["そのあと本物の攻撃が当たる"] = _player.hp == _hp_before - _zako.damage
				_next_attack(true)
		1:  # フェイント：本物の光で押す
			if _in_telegraph and _zako.frames_until_active() == 3 and not _pressed:
				_parry_before = _parry_count
				_press("attack_light")
				_pressed = true
			if _pressed and (_zako.state == Enemy.State.STAGGER or _zako.state == Enemy.State.RECOVER):
				_results["本物の光で押すとパリィ成功"] = _parry_count == _parry_before + 1
				_next_attack(false)
		2:  # 普通の攻撃（何も押さずに見るだけ）
			if _zako.state == Enemy.State.ATTACK and _telegraph_len > 0:
				_results["普通の攻撃の溜めは36フレーム（%d）" % _telegraph_len] = _telegraph_len == 36
				_results["普通の攻撃はニセの光なし"] = _fake_glint_first == -1
				_finish()


# 予兆（TELEGRAPH）の長さと、ニセの光が最初に出たフレームを記録する
func _observe_telegraph() -> void:
	var now := _zako.state == Enemy.State.TELEGRAPH
	if now and not _in_telegraph:
		_telegraph_len = _zako.frames_until_active() + _zako.state_frame
	if now and _zako.is_fake_glint() and _fake_glint_first == -1:
		_fake_glint_first = _zako.state_frame
	_in_telegraph = now


# 次の攻撃をフェイントにする／しない（ザコは feint_every = 3）
func _set_next_feint(feint: bool) -> void:
	_zako._attack_count = 2 if feint else 0


func _next_attack(feint: bool) -> void:
	_step += 1
	_set_next_feint(feint)
	_pressed = false
	_telegraph_len = 0
	_fake_glint_first = -1


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)


func _on_player_log(text: String) -> void:
	if text.contains("パリィ成功"):
		_parry_count += 1


func _finish() -> void:
	print("==== フェイントテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()  # 音を止めてから終了する
