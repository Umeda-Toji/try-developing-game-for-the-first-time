# Godot 4.7.2 / GDScript
# res://tests/title_test.gd
# タイトル画面（U-06）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --title-test
#  1回目のシーン：
#    起動するとタイトルが出る → ゲームは止まっている・HUDは隠れる・ポーズは開かない
#    → クレジットを開いて Esc／○で戻る → 「はじめる」で難易度の画面 → Esc／○で戻る
#    → もう一度「はじめる」→「やさしい」で始まる（難易度が当てはまる） → リトライ
#  2回目のシーン（リトライ後）：タイトルは出ない・難易度は「やさしい」のまま → 最後に「終了」ボタンでゲームが終わる
# シーンを読み直すとこのノードも消えるので、途中経過は Engine のメタ情報に残しておく
extends Node

const STAGE_KEY := "title_test_stage"
const RESULTS_KEY := "title_test_results"

var _main: Node
var _title: TitleScreen
var _frame := 0
var _release: Array[String] = []
var _results := {}


func _ready() -> void:
	process_physics_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS  # タイトル中（一時停止中）も動かす
	_main = get_parent()
	_title = _main.title_screen
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
		3:
			_results["起動するとタイトルが出る"] = _title.is_open and _title.visible
			_results["タイトル中はゲームが止まる"] = get_tree().paused
			_results["最初は「はじめる」が選ばれている"] = _title.start_button.has_focus()
			_results["タイトル中は HUD を隠す"] = not _main._hud_layer.visible
			_press("pause")
		6:
			_results["タイトル中はポーズメニューが開かない"] = not _main.pause_menu.is_open
			_title.credits_button.pressed.emit()
		8:
			var t := _title.credits_panel.text_label.text
			_results["タイトルからクレジットが開く"] = _title.credits_open and t.contains("Godot Engine contributors")
			_press("ui_cancel")
		11:
			_results["Esc／○でクレジットから戻る"] = not _title.credits_open and _title.is_open
			_title.start_button.pressed.emit()
		13:
			_results["「はじめる」で難易度の画面が出る"] = _title.difficulty_open and _title.is_open
			_results["難易度は最初「ふつう」が選ばれている"] = _title.difficulty_buttons[Difficulty.NORMAL].has_focus()
			_results["難易度を選ぶまでゲームは止まったまま"] = get_tree().paused
			_press("ui_cancel")
		16:
			_results["Esc／○で難易度の画面から戻る"] = not _title.difficulty_open and _title.is_open
			_title.start_button.pressed.emit()
		18:
			_title.difficulty_buttons[Difficulty.EASY].pressed.emit()  # 「やさしい」で始める
		20:
			_results["難易度を選ぶとタイトルが閉じる"] = not _title.is_open and not _title.visible
			_results["難易度を選ぶとゲームが動き出す"] = not get_tree().paused
			_results["「やさしい」が当てはまる（パリィ受付12・ザコの予兆47・ボスのダメージ10）"] = (
				Difficulty.current == Difficulty.EASY and _main.player.parry_window_frames == 12
				and _main.enemies[0].telegraph_frames == 47 and _main.boss.damage == 10)
		22:
			_results["ゲーム中は HUD が見える"] = _main._hud_layer.visible
			Engine.set_meta(RESULTS_KEY, _results)
			Engine.set_meta(STAGE_KEY, 1)
			_main._retry()  # シーンが読み直される


func _stage_after_retry() -> void:
	match _frame:
		3:
			_results["リトライの後はタイトルを出さない"] = not _main.title_screen.is_open and not get_tree().paused
			_results["リトライの後も「やさしい」のまま"] = Difficulty.current == Difficulty.EASY and _main.player.parry_window_frames == 12 and _main.enemies[0].telegraph_frames == 47
			_main.title_screen.open()  # 「終了」ボタンを試すために開く
		5:
			print("==== タイトルテスト結果 ====")
			for k in _results.keys():
				print("%s: %s" % [k, str(_results[k])])
			print("（このあと「終了」ボタンでゲームが終われば合格）")
			_main.title_screen.quit_button.pressed.emit()


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)
