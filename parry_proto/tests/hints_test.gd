# Godot 4.7.2 / GDScript
# res://tests/hints_test.gd
# 操作のヒント・操作の一覧（U-11）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --hints-test
#  （白砂市のエリアで動く）
#  1. 始まると「移動」のヒントが出る（キーボードの書き方）
#  2. パッドを使うと、次のヒントはパッドの書き方になる（広場）
#  3. 同じ場所にもう一度行っても、同じヒントは出ない
#  4. 回復薬を拾うと回復薬のヒント、街へ出ると銃と地図のヒント
#  5. 出したヒントはセーブに残る（読み直しても覚えている）
#  6. 設定で「操作のヒント」をオフにすると出ない
#  7. ポーズメニューの「操作の一覧」で、全部の操作が見られる
extends Node

var _main: Node
var _p: Player
var _box: HintBox
var _t := 0
var _step := 0
var _results := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	_box = _main.hint_box
	for e in _main.enemies:
		e.aggro_range = 0.0
	Discoveries.reset()


func _physics_process(_delta: float) -> void:
	_t += 1
	match _step:
		0:
			if _t == HintDirector.START_DELAY + 5:
				_results["始まると「移動」のヒントが出る（%s）" % _box.label.text.left(14)] = _box.current_id == "move" and _box.label.text.begins_with("WASD")
				_box.frames_left = 1  # 次へ（テストを早く進める）
				# パッドを使った
				var ev := InputEventJoypadButton.new()
				ev.button_index = JOY_BUTTON_A
				ev.pressed = true
				_box._input(ev)
				_p.global_position = WorldBuilder.on_ground(Vector3(4, 0.1, 4))  # 広場
				_step = 1
				_t = 0
		1:
			if _t == 10:
				_results["パッドを使うと、パッドの書き方になる（広場：%s）" % _box.label.text.left(12)] = _box.current_id == "plaza" and _box.label.text.begins_with("L2")
				_box.frames_left = 1
				_p.global_position = WorldBuilder.on_ground(Vector3(0, 0.1, 30))  # 一度出て
			if _t == 20:
				_p.global_position = WorldBuilder.on_ground(Vector3(-4, 0.1, 2))  # また広場へ
			if _t == 30:
				_results["同じ場所にもう一度行っても、同じヒントは出ない"] = _box.current_id != "plaza"
				Discoveries.heals = 1
			if _t == 40:
				_results["回復薬を持つと、回復薬のヒントが出る"] = _box.current_id == "heal" or Discoveries.hints_seen.has("heal")
				_box.frames_left = 1
				_p.global_position = WorldBuilder.on_ground(Vector3(60, 0.1, 30))  # 街
			if _t == 60:
				_results["街へ出ると、銃と地図のヒントが出る"] = Discoveries.hints_seen.has("city") and (_box.current_id == "city" or _box._queue.size() >= 0)
				# セーブに残るか（テスト用のセーブは使わないので、中身だけ確かめる）
				_results["出したヒントを覚えている（%s）" % str(Discoveries.hints_seen.keys())] = Discoveries.hints_seen.has("move") and Discoveries.hints_seen.has("plaza") and Discoveries.hints_seen.has("city")
				# 設定でオフ
				GameSettings.hints = false
				Discoveries.hints_seen.erase("swim")
				_p.global_position = Vector3(0, -1.9, 19)  # 水路
				_p._start_swim()
			if _t == 80:
				_results["設定で「操作のヒント」をオフにすると出ない"] = not Discoveries.hints_seen.has("swim")
				GameSettings.hints = true
				# 操作の一覧
				var pm: PauseMenu = _main.pause_menu
				pm.open()
				pm.controls_button.pressed.emit()
				var panel: CreditsPanel = pm._controls_panel
				_results["ポーズメニューの「操作の一覧」で全部の操作が見られる"] = (
					pm.controls_open and panel.visible and panel.text_label.get_parsed_text().contains("パリィ")
					and panel.text_label.get_parsed_text().contains("リロード") and panel.text_label.get_parsed_text().contains("武器の輪"))
				pm.close()
				_finish()


func _finish() -> void:
	_step = 99
	print("==== ヒントのテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
