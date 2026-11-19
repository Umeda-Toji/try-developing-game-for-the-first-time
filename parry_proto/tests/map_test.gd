# Godot 4.7.2 / GDScript
# res://tests/map_test.gd
# 地図（C）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --map-test
#  （白砂市のエリアで動く）
#  1. ポーズメニューに「地図」がある。押すと地図が開き、メニューは隠れる
#  2. 建物がたくさん描かれている（街のビル・一本道のビル）。水（川・水路）もある
#  3. 自分の位置が正しく地図の上に来る（街の角は地図の角、スタートは下の方）
#  4. Esc で地図を閉じると、メニューに戻る（「地図」が選ばれている）
extends Node

var _main: Node
var _p: Player
var _t := 0
var _results := {}
var _done := false
var MAP_HOLD := 0  # 録画で地図を見るときは、--map-hold で長く開いておく


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # ポーズ中も確かめる
	_main = get_parent()
	_p = _main.player
	if "--map-hold" in OS.get_cmdline_user_args():
		MAP_HOLD = 30


func _physics_process(_delta: float) -> void:
	_t += 1
	if _done:
		return
	var pm: PauseMenu = _main.pause_menu
	var map: CityMap = pm.city_map
	if _t == 20:
		pm.open()
		_results["ポーズメニューに「地図」がある"] = pm.map_button.visible
		pm.map_button.pressed.emit()
	if _t == 22:
		_results["押すと地図が開き、メニューは隠れる"] = pm.map_open and map.visible and not pm._menu_box.visible
		_results["建物が %d・水が %d 描かれている" % [map.box_count(), map._waters.size()]] = map.box_count() > 80 and map._waters.size() >= 2
		var r := map.map_rect()
		var c0 := map.world_to_map(CityBuilder.CITY_MIN)
		var c1 := map.world_to_map(CityBuilder.CITY_MAX)
		var start := map.world_to_map(Vector2(_p.global_position.x, _p.global_position.z))
		_results["街の角が地図の角になり、スタート（%s）は真ん中より下" % str(start.round())] = (
			c0.distance_to(r.position) < 0.5 and c1.distance_to(r.end) < 0.5 and r.has_point(start) and start.y > r.get_center().y)
	if _t == 22 + MAP_HOLD:
		Input.action_press("pause")
	if _t == 23 + MAP_HOLD:
		Input.action_release("pause")
	if _t == 25 + MAP_HOLD:
		_results["Esc で地図を閉じると、メニューに戻る"] = not pm.map_open and not map.visible and pm._menu_box.visible and pm.is_open and pm.map_button.has_focus()
		pm.close()
		_done = true
		print("==== 地図のテスト結果 ====")
		for k in _results.keys():
			print("%s: %s" % [k, str(_results[k])])
		_main.quit_game()
