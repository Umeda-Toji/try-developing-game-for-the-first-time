# Godot 4.7.2 / GDScript
# res://tests/charge_test.gd
# 強攻撃の溜め（P-15）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --charge-test
#  敵が近づいてこないようにしてから、次の4つを順に試す
#   1. □をすぐ離す → 溜めにならず、普通の H1（ダメージ 22）
#   2. □を最大まで押し続ける → 溜めになり、離すと 2倍（ダメージ 44）
#   3. □を半分くらい溜める → 1.5倍くらい（ダメージは倍率どおり）
#   4. 溜め中に回避 → 溜めをやめて回避になる
extends Node

const GAP := 90  # 1つの確認が終わってから次を始めるまで（前の攻撃が終わるのを待つ）

var _main: Node
var _player: Player
var _frame := 0
var _step := 0
var _step_start := 0
var _results := {}
var _saw_charge := false
var _max_damage := 0


func _ready() -> void:
	process_physics_priority = -100  # プレイヤーより先に入力を入れる
	_main = get_parent()
	_player = _main.player
	# 敵を動かさない（近づいてこない）
	for e in _main.enemies:
		e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_frame += 1
	var t := _frame - _step_start
	if _player.state == Player.State.CHARGE:
		_saw_charge = true
	if _player.hitbox.active:
		_max_damage = maxi(_max_damage, int(_player.hitbox.attack["damage"]))

	match _step:
		0:  # すぐ離す
			_hold_heavy(t, 1)
			if t == GAP:
				_results["タップ：溜めにならない"] = not _saw_charge
				_results["タップ：ダメージ22"] = _max_damage == 22
				_next()
		1:  # 最大まで溜める（溜めに入る12 ＋ 最大まで60 ＋ 余裕）
			_hold_heavy(t, Player.CHARGE_START_FRAMES + Player.CHARGE_MAX_FRAMES + 10)
			if t == Player.CHARGE_START_FRAMES + 5:
				_results["長押し：溜め状態になる"] = _player.state == Player.State.CHARGE
			if t == Player.CHARGE_START_FRAMES + Player.CHARGE_MAX_FRAMES + 10 + GAP:
				_results["最大溜め：ダメージ44（2倍）"] = _max_damage == 44
				_next()
		2:  # 半分だけ溜める
			_hold_heavy(t, Player.CHARGE_START_FRAMES + int(Player.CHARGE_MAX_FRAMES * 0.5) + 1)
			if t == Player.CHARGE_START_FRAMES + Player.CHARGE_MAX_FRAMES + GAP:
				# 倍率が1.5倍くらい（1.3〜1.7）で、ダメージがその倍率どおりか
				var mult: float = _player._charge_mult
				_results["半分溜め：倍率 %.2f（1.3〜1.7）" % mult] = mult > 1.3 and mult < 1.7
				_results["半分溜め：ダメージ %d が倍率どおり" % _max_damage] = _max_damage == int(round(22.0 * mult))
				_next()
		3:  # 溜め中に回避
			_hold_heavy(t, Player.CHARGE_START_FRAMES + 40)
			if t == Player.CHARGE_START_FRAMES + 20:
				Input.action_press("dodge")
			if t == Player.CHARGE_START_FRAMES + 21:
				Input.action_release("dodge")
			if t == Player.CHARGE_START_FRAMES + 24:
				_results["溜め中の回避：回避になる"] = _player.state == Player.State.DODGE
			if t == Player.CHARGE_START_FRAMES + 40 + GAP:
				_results["溜め中の回避：攻撃は出ない"] = _max_damage == 0
				_next()
		4:
			print("==== 溜めテスト結果 ====")
			for k in _results.keys():
				print("%s: %s" % [k, str(_results[k])])
			_main.quit_game()  # 音を止めてから終了する


# t=1 で□を押し、frames フレーム押し続けてから離す
func _hold_heavy(t: int, frames: int) -> void:
	if t == 1:
		Input.action_press("attack_heavy")
	elif t == 1 + frames:
		Input.action_release("attack_heavy")


func _next() -> void:
	_step += 1
	_step_start = _frame
	_saw_charge = false
	_max_damage = 0
