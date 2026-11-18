# Godot 4.7.2 / GDScript
# res://tests/pause_test.gd
# ポーズメニュー（U-04）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --pause-test
#  1回目のシーン：
#    ポーズで開く → ゲームが止まる → もう一度ポーズで閉じる → 「再開」ボタンで閉じる → 「リトライ」ボタン
#  2回目のシーン（リトライ後）：最初の状態に戻ったか → 「終了」ボタンでゲームが終わる
# シーンを読み直すとこのノードも消えるので、途中経過は Engine のメタ情報に残しておく
extends Node

const STAGE_KEY := "pause_test_stage"
const RESULTS_KEY := "pause_test_results"

var _main: Node
var _menu: PauseMenu
var _player: Player
var _frame := 0
var _release: Array[String] = []
var _results := {}
var _pos_before := Vector3.ZERO


func _ready() -> void:
	process_physics_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS  # ポーズ中も動かす
	_main = get_parent()
	_menu = _main.pause_menu
	_player = _main.player
	for e in _main.enemies:  # 敵は動かさない
		e.aggro_range = 0.0
	_results = Engine.get_meta(RESULTS_KEY, {})


func _physics_process(_delta: float) -> void:
	_frame += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()
	if Engine.get_meta(STAGE_KEY, 0) == 0:
		_stage_first()
	else:
		_stage_after_retry()


func _stage_first() -> void:
	match _frame:
		10:
			_press("pause")
		13:
			_results["ポーズで開く"] = _menu.is_open and _menu.visible
			_results["ポーズ中はゲームが止まる"] = get_tree().paused
			_results["最初は「再開」が選ばれている"] = _menu.resume_button.has_focus()
			_pos_before = _player.global_position
			Input.action_press("move_forward")
		40:
			Input.action_release("move_forward")
			_results["ポーズ中はプレイヤーが動かない"] = _player.global_position.is_equal_approx(_pos_before)
			_press("pause")
		43:
			_results["もう一度ポーズで閉じる"] = not _menu.is_open and not get_tree().paused
			_press("pause")
		46:
			_menu.resume_button.pressed.emit()
		48:
			_results["「再開」ボタンで閉じる"] = not _menu.is_open and not get_tree().paused
			_press("pause")
		51:
			_main._result_decided = true  # 勝ち負けが決まった後は、ポーズできないか
			_menu.resume_button.pressed.emit()
		53:
			_press("pause")
		56:
			_results["勝敗が決まった後はポーズしない"] = not _menu.is_open
			_main._result_decided = false
			_press("pause")
		57:
			# U-09：画質ボタンで「高画質」⇔「軽い」が切り替わる（2回押して元に戻す）
			var before: bool = _main._environment.ssao_enabled
			var label_before: String = _menu.graphics_button.text
			_menu.graphics_button.pressed.emit()
			var switched: bool = _main._environment.ssao_enabled != before and _menu.graphics_button.text != label_before
			_menu.graphics_button.pressed.emit()
			_results["画質ボタンで切り替わる（%s ⇔ もう一方）" % label_before] = switched and _main._environment.ssao_enabled == before
		58:
			_menu.credits_button.pressed.emit()  # U-05：クレジットを開く
		60:
			var t := _menu.credits_text.text
			_results["クレジットが開く"] = _menu.credits_open and _menu.credits_text.visible
			var has_mit := t.contains("Godot Engine contributors") and t.contains("Permission is hereby granted")
			_results["クレジットに Godot のライセンス文がある"] = has_mit
			_results["クレジットに中で使っているソフトの表示がある"] = t.contains("FreeType")
			_press("ui_cancel")
		63:
			_results["Esc／○でクレジットからメニューに戻る"] = not _menu.credits_open and _menu.is_open
		65:
			Engine.set_meta(RESULTS_KEY, _results)
			Engine.set_meta(STAGE_KEY, 1)
			_menu.retry_button.pressed.emit()  # シーンが読み直される


func _stage_after_retry() -> void:
	match _frame:
		3:
			_results["「リトライ」で読み直し後、停止していない"] = not get_tree().paused
			_results["「リトライ」で読み直し後、メニューは閉じている"] = not _main.pause_menu.is_open
			_press("pause")
		6:
			print("==== ポーズテスト結果 ====")
			for k in _results.keys():
				print("%s: %s" % [k, str(_results[k])])
			print("（このあと「終了」ボタンでゲームが終われば合格）")
			_menu.quit_button.pressed.emit()


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)
