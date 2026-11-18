# Godot 4.7.2 / GDScript
# res://tests/enemy_bars_test.gd
# 敵の頭の上の体力バー（U-08）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --enemy-bars-test
#  ・敵ごとにバーができる／攻撃（パリィ）するまでは見えない・攻撃すると見える
#  ・ダメージを受けるとHPバーが減る、体幹バーが増える
#  ・遠い敵・カメラの後ろの敵のバーは隠れる
#  ・倒した敵のバーは消える
extends Node

var _main: Node
var _bars: EnemyBars
var _frame := 0
var _results := {}


func _ready() -> void:
	process_physics_priority = 100
	_main = get_parent()
	_bars = _main.enemy_bars
	for e in _main.enemies:
		e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_frame += 1
	var zako: Enemy = _main.enemies[0]
	match _frame:
		5:
			var all_have := true
			for e in _main.enemies:
				all_have = all_have and not _bars.bar_of(e).is_empty()
			_results["敵ごとに体力バーができる（%d体）" % _main.enemies.size()] = all_have
			_results["攻撃するまでバーは見えない"] = not (_bars.bar_of(zako)["box"] as Control).visible
			zako.receive_attack({"damage": 30, "posture": 20, "hitstop": 0}, _main.player)
			_main.boss.on_parried(_main.player)  # パリィでも出る
			# 遠い敵・後ろの敵のテスト用に、攻撃を当てたことにしておく
			_main.heavy.bar_revealed = true
			_main.swift.bar_revealed = true
		8:
			_results["攻撃すると近い敵（ザコ）のバーが見える"] = (_bars.bar_of(zako)["box"] as Control).visible
			_results["パリィした敵（ボス）にもバーが出る"] = _main.boss.bar_revealed
			var b := _bars.bar_of(zako)
			_results["ダメージでHPバーが減る（%d / %d）" % [int(b["hp"].value), int(b["hp"].max_value)]] = b["hp"].value == zako.hp and zako.hp == zako.max_hp - 30
			_results["体幹バーが増える（%d）" % int(b["posture"].value)] = b["posture"].value > 0.0
			# 遠くへ（カメラの前、表示する距離より先。部屋の外でもよい）
			var cam := get_viewport().get_camera_3d()
			_main.heavy.global_position = cam.global_position - cam.global_transform.basis.z * (EnemyBars.SHOW_DISTANCE + 6.0)
			# カメラの後ろへ
			_main.swift.global_position = cam.global_position + cam.global_transform.basis.z * 3.0 - Vector3.UP * 1.0
		11:
			_results["遠い敵のバーは隠れる"] = not (_bars.bar_of(_main.heavy)["box"] as Control).visible
			_results["カメラの後ろの敵のバーは隠れる"] = not (_bars.bar_of(_main.swift)["box"] as Control).visible
			zako.receive_attack({"damage": 9999, "posture": 0, "hitstop": 0}, _main.player)
		14:
			_results["倒した敵のバーは消える"] = _bars.bar_of(zako).is_empty()
			print("==== 敵の体力バーテスト結果 ====")
			for k in _results.keys():
				print("%s: %s" % [k, str(_results[k])])
			_main.quit_game()
