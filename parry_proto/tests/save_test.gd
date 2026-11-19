# Godot 4.7.2 / GDScript
# res://tests/save_test.gd
# セーブ（S-01）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --save-test
#  （白砂市のエリアで動く。遊んでいる人のセーブ user://save.cfg は使わず、user://save_test.cfg を使って、最後に消す）
#  1. セーブがないときは、タイトルに「つづきから」が出ない
#  2. アイテムを拾うと自動で保存される（回復薬の数・拾った物・場所）
#  3. 覚えている物を消してから読み込むと、元に戻る（難易度も）
#  4. ポーズメニューの「セーブ」で保存できる（ボタンに「セーブしました」）
#  5. セーブがあると、タイトルに「つづきから」が出て、最初に選ばれている
#  6. 「はじめから」→ 確かめる画面 →「はい」でセーブが消え、難易度の画面になる
#  7. 保存した場所から始められる
#  （B）ポーズメニューに、見つけたものの数が出る
extends Node

var _main: Node
var _p: Player
var _step := 0
var _t := 0
var _results := {}
var _item: Pickup
var _item_id := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # タイトル・ポーズでゲームが止まっている間も確かめる
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	for e in _main.enemies:
		e.aggro_range = 0.0
	Discoveries.delete_save()


func _physics_process(_delta: float) -> void:
	_t += 1
	match _step:
		0:
			if _t == 20:
				_results["保存は テスト用のファイル（%s）" % Discoveries.save_path] = Discoveries.save_path == Discoveries.TEST_SAVE_PATH
				var title: TitleScreen = _main.title_screen
				title.open()
				_results["セーブがないときは「つづきから」が出ない"] = not title.continue_button.visible and title.start_button.text == "はじめる"
				title.close()
				for it in get_tree().get_nodes_in_group("pickups"):
					if it.kind == "heal":
						_item = it
						break
				_item_id = _item.item_id
				_place(_item.global_position)
				_next()
		1:
			if _t == 20:
				_results["アイテムを拾うと自動で保存される"] = Discoveries.has_save()
				Difficulty.current = Difficulty.HARD
				Discoveries.save_game()
				var pos := Discoveries.saved_position
				Discoveries.reset()
				Difficulty.current = Difficulty.NORMAL
				var ok := Discoveries.load_game()
				_results["読み込むと元に戻る（回復薬 %d、拾った物 %s、難易度 %s、場所 %s）" % [Discoveries.heals, str(Discoveries.picked.keys()), Difficulty.current, str(Discoveries.saved_position)]] = (
					ok and Discoveries.heals == 1 and Discoveries.picked.has(_item_id) and Difficulty.current == Difficulty.HARD
					and Discoveries.has_position and Discoveries.saved_position.distance_to(pos) < 0.01)
				# ポーズメニューの「セーブ」
				Discoveries.heals = 2
				_main.pause_menu.open()
				_main.pause_menu.save_button.pressed.emit()
				_next()
		2:
			if _t == 2:
				var pm: PauseMenu = _main.pause_menu
				Discoveries.heals = 0
				Discoveries.load_game()
				_results["ポーズメニューの「セーブ」で保存できる（%s、回復薬 %d）" % [pm.save_button.text, Discoveries.heals]] = (
					pm.save_button.visible and pm.save_button.text == "セーブしました" and Discoveries.heals == 2)
				_results["ポーズメニューに見つけたものの数が出る（%s）" % pm.found_label.text.replace("\n", "／")] = (
					pm.found_label.visible and pm.found_label.text.contains("回復薬　1 / %d（いま 2 つ" % CityBuilder.HEAL_ITEMS)
					and pm.found_label.text.contains("記録の断片　0 / %d" % CityBuilder.FRAGMENTS.size())
					and pm.found_label.text.contains("寄り道の敵　0 / 12") and pm.found_label.text.contains("眺めのいい場所　0 / 3"))
				pm.close()
				var title: TitleScreen = _main.title_screen
				title.open()
				_results["セーブがあると「つづきから」が出て、選ばれている"] = (
					title.continue_button.visible and title.continue_button.has_focus() and title.start_button.text == "はじめから")
				title.start_button.pressed.emit()
				_results["「はじめから」で確かめる画面が出る（「いいえ」が選ばれている）"] = title.confirm_open and title.confirm_no.has_focus() and Discoveries.has_save()
				title.confirm_no.pressed.emit()
				_results["「いいえ」で戻り、セーブは残る"] = not title.confirm_open and Discoveries.has_save()
				title.start_button.pressed.emit()
				title.confirm_yes.pressed.emit()
				_results["「はい」でセーブが消えて、難易度の画面になる"] = not Discoveries.has_save() and title.difficulty_open and Discoveries.heals == 0
				title.close()
				# 保存した場所から始める
				Discoveries.saved_position = Vector3(60, 0.1, 46)
				Discoveries.has_position = true
				_main.apply_saved_position()
				_results["保存した場所から始められる（%s）" % str(_p.global_position)] = _p.global_position.distance_to(Vector3(60, 0.1, 46)) < 0.01
				_finish()


func _place(pos: Vector3) -> void:
	_p.global_position = pos + Vector3.UP * 0.1
	_p.velocity = Vector3.ZERO
	_p._set_state(Player.State.MOVE)


func _next() -> void:
	_step += 1
	_t = 0


func _finish() -> void:
	_step = 99
	Discoveries.delete_save()
	print("==== セーブのテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
