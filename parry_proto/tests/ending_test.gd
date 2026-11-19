# Godot 4.7.2 / GDScript
# res://tests/ending_test.gd
# エンディング（U-12）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --ending-test
#  （白砂市のエリアで動く。エンディングの後にシーンを作り直すので、2回に分けて確かめる）
#  1回目：母株を倒す → 「勝利！」ではなくエンディング → 文章が1行ずつ → 早送り → とばしてスタッフロール
#         （素材のクレジットと見つけた数）→ 倒したことを覚える → 終わるとシーンを作り直す
#  2回目：母株はいない・ホールの扉は開いている・ホールの中から始まる・ポーズできる
extends Node

const META_KEY := "ending_test_results"

var _main: Node
var _end: EndingScreen
var _t := 0
var _step := 0
var _results := {}
var _second := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	_main = get_parent()
	_end = _main.ending_screen
	_second = Engine.has_meta(META_KEY)
	if _second:
		_results = Engine.get_meta(META_KEY)
		Engine.remove_meta(META_KEY)
		_step = 10
	else:
		Discoveries.reset()
		for e in _main.enemies:
			e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_t += 1
	match _step:
		0:
			if _t == 5:
				_main.player.global_position = WorldBuilder.on_ground(Vector3(0, 0.1, -40))
				_main.boss.hp = 0
				_main.boss._die()
			if _t == 5 + Main_RESULT_DELAY() + 3:
				_results["母株を倒すと、エンディングが始まる（勝利の画面は出ない）"] = _end.is_open() and not _main.result_screen.visible and get_tree().paused
				_results["倒したことを覚え、ホールの中を保存する場所にする（%s）" % str(Discoveries.saved_position)] = (
					Discoveries.boss_defeated and Discoveries.saved_position.z < -31.0 and Discoveries.saved_position.z > -57.0)
				_step = 1
				_t = 0
		1:
			# 黒くなってから、最初の行
			if _t == EndingScreen.FADE_IN_FRAMES + EndingScreen.LINE_FADE_FRAMES + 5:
				var first := _end._line_labels[0] if not _end._line_labels.is_empty() else null
				_results["黒い画面に、文章が1行ずつ出る（%d行目まで）" % _end.lines_shown] = (
					_end.phase == EndingScreen.Phase.TEXT and first != null and first.text == "母株は焼けた。"
					and first.modulate.a > 0.9 and _end.lines_shown == 1)
				_results["文章は案A（外套を返す）"] = "".join(PackedStringArray(EndingScreen.BLOCKS[2])).contains("返す相手は、もういない")
				_mark = _end.elapsed_steps
			if _t == EndingScreen.FADE_IN_FRAMES + EndingScreen.LINE_FADE_FRAMES + 35:
				var normal := _end.elapsed_steps - _mark
				Input.action_press("jump")
				_mark = _end.elapsed_steps
				_normal = normal
			if _t == EndingScreen.FADE_IN_FRAMES + EndingScreen.LINE_FADE_FRAMES + 65:
				var fast := _end.elapsed_steps - _mark
				Input.action_release("jump")
				_results["押し続けると早送り（30フレームで %d → %d 進む）" % [_normal, fast]] = _normal == 30 and fast == 30 * EndingScreen.SPEED_UP
				_end.skip()
				_step = 2
				_t = 0
		2:
			if _t == 1:
				var txt := _end.roll_label.text
				_results["とばすとスタッフロール：素材のクレジットと見つけた数"] = (
					_end.phase == EndingScreen.Phase.ROLL and _end._roll_clip.visible
					and txt.contains("Quaternius") and txt.contains("Kenney") and txt.contains("見つけたもの") and txt.contains("記録の断片"))
				_roll_y = _end.roll_label.position.y
			if _t == 61:
				_results["スタッフロールは下から上へ流れる（%.0f → %.0f）" % [_roll_y, _end.roll_label.position.y]] = _end.roll_label.position.y < _roll_y - 50.0
				Engine.set_meta(META_KEY, _results)
				_end.skip()  # 終わり → シーンを作り直す（このテストも、もう一度始まる）
				_step = 3
		10:
			if _t == 10:
				var p: Player = _main.player
				_results["倒した後の街：母株はいない"] = _main.boss == null and _main.post_game and not _main.enemies.any(func(e): return e.display_name == "ボス")
				_results["ホールの扉は開いている"] = _main.boss_door.is_open
				_results["ホールの中から始まる（%s）" % str(p.global_position)] = p.global_position.z < -31.0 and p.global_position.z > -57.0 and absf(p.global_position.x) < 13.0
				_results["エンディングは出ていない・ポーズできる"] = not _end.is_open() and not get_tree().paused and _main.can_pause()
			if _t == 70:
				_results["倒した後は、勝ち負けが決まらない（母株がいなくても止まらない）"] = not _main._result_decided
				Discoveries.reset()
				_finish()


var _mark := 0
var _normal := 0
var _roll_y := 0.0


func Main_RESULT_DELAY() -> int:
	return _main.RESULT_DELAY_FRAMES


func _finish() -> void:
	_step = 99
	print("==== エンディングのテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
