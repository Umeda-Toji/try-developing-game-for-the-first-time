# Godot 4.7.2 / GDScript
# res://tests/retry_test.gd
# 敗北画面とリトライの確認（U-03）。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --retry-test
#  1回目のシーン：プレイヤーをわざと倒す → 敗北画面とゲーム停止を確認 → リトライを押す
#  2回目のシーン（読み直し後）：最初の状態に戻っているかを確認して終了
# シーンを読み直すとこのノードも消えるので、途中経過は Engine のメタ情報に残しておく
extends Node

const STAGE_KEY := "retry_test_stage"
const RESULTS_KEY := "retry_test_results"
const TIMEOUT_FRAMES := 300
const WAIT_BEFORE_RETRY := 30  # 結果画面が出てからリトライを押すまで（人が押すのと同じくらい待つ）

var _main: Node
var _frame := 0
var _pressed := false
var _shown_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 一時停止中も動かす
	_main = get_parent()


func _physics_process(_delta: float) -> void:
	_frame += 1
	var stage: int = Engine.get_meta(STAGE_KEY, 0)
	if stage == 0:
		_stage_defeat()
	else:
		_stage_after_retry()


func _stage_defeat() -> void:
	var player: Player = _main.player
	var rs: ResultScreen = _main.result_screen
	if _frame == 5:
		# 大ダメージを1回受けて倒れる
		player.receive_attack({"damage": 9999, "hitstop": 0, "shake": 0.0}, _main.boss)
	if _pressed:
		Input.action_release("retry")
		return
	if rs.visible:
		_shown_frames += 1
		if _shown_frames < WAIT_BEFORE_RETRY:
			return
		var results := {
			"敗北画面": not rs.is_victory,
			"敗北で一時停止": get_tree().paused,
		}
		Engine.set_meta(RESULTS_KEY, results)
		Engine.set_meta(STAGE_KEY, 1)
		Input.action_press("retry")  # R ／ × と同じ
		_pressed = true
	elif _frame > TIMEOUT_FRAMES:
		_finish({"敗北画面": false})


func _stage_after_retry() -> void:
	if _frame < 3:
		return
	var results: Dictionary = Engine.get_meta(RESULTS_KEY, {})
	var player: Player = _main.player
	results["リトライ後HP満タン"] = player.hp == Player.MAX_HP
	results["リトライ後に停止解除"] = not get_tree().paused
	results["リトライ後に結果画面なし"] = not _main.result_screen.visible
	results["リトライ後のボスHP満タン"] = _main.boss.hp == _main.boss.max_hp
	_finish(results)


func _finish(results: Dictionary) -> void:
	Input.action_release("retry")
	print("==== リトライテスト結果 ====")
	for k in results.keys():
		print("%s: %s" % [k, str(results[k])])
	_main.quit_game()  # 音を止めてから終了する
