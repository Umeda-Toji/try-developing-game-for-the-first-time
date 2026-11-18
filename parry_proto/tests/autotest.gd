# Godot 4.7.2 / GDScript
# res://tests/autotest.gd
# 動作確認用の自動プレイ（遊ぶときは不要）。
# 実行: godot --path . --headless -- --autotest
# パリィ → 反撃コンボ → ジャスト回避 → 被弾 → ボスへ、の順に試してログを出す。
extends Node

var _phase := 0
var _release: Array[String] = []
var _frame := 0
var _phase_start := 0
var _main: Node
var _zako: Enemy
var _boss: Enemy
var _player: Player
var _results := {}


func _ready() -> void:
	process_physics_priority = -100  # プレイヤーより先に入力を入れる
	process_mode = Node.PROCESS_MODE_ALWAYS  # 結果画面でゲームが一時停止しても、テストは動かす
	_main = get_parent()
	_player = _main.player
	_zako = _main.enemies[0]
	_boss = _main.boss
	_main.remove_extra_enemies()  # ザコとボスだけで試す


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)


func _physics_process(_delta: float) -> void:
	_frame += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()

	var since := _frame - _phase_start
	match _phase:
		0:  # ロックオン
			if since == 10:
				_press("lock_on")
				_next()
		1:  # ザコの攻撃にパリィ（攻撃判定の3フレーム前に攻撃ボタンを押す）
			if _zako.frames_until_active() == 3:
				_press("attack_light")  # 攻撃の出始めでパリィ
				_next()
		2:  # パリィ後に弱攻撃コンボ
			if since in [8, 20, 32]:
				_press("attack_light")
			if since == 70:
				_results["パリィ後の敵体幹"] = _zako.posture
				# U-02：ロックオン中の敵のバーが出ていて、値が合っているか（HUDは前のフレームの値なので±1まで許す）
				var hud: BattleHud = _main.battle_hud
				var hp_ok := absf(hud.enemy_hp_bar.value - _zako.hp) <= 1.0
				var max_ok := hud.enemy_hp_bar.max_value == _zako.max_hp
				_results["敵バー表示（ロックオン中）"] = hud.enemy_panel.visible and hp_ok and max_ok
				_next()
		3:  # ジャスト回避（2フレーム前）
			if _zako.frames_until_active() == 2:
				_press("dodge")
				_next()
		4:
			if since == 5:
				_results["ジャスト回避→スロー"] = GameFeel.is_witch_time()
			# F-04：スロー中は画面演出が最大になり、スローが終わると消えるか
			if since == 30:
				_results["スロー演出が出る"] = is_equal_approx(_main.slow_effect.strength, 1.0)
			if since in [20, 32, 44]:
				_press("attack_light")
			if since == 139:
				# F-06：ここまでに出した火花は、出し終わって消えているか（寿命は1秒未満）
				_results["火花が消える"] = _main.hit_sparks.active_count() == 0
			if since == 140:
				_results["スロー演出が消える"] = not GameFeel.is_witch_time() and _main.slow_effect.strength == 0.0
				_next()
		5:  # わざと被弾
			if since == 1:
				_results["被弾前HP"] = _player.hp
			if _zako.is_dead():
				_results["被弾テスト"] = "ザコが先に倒れたのでスキップ"
				_next()
			elif _zako.state == Enemy.State.RECOVER:
				_results["被弾後HP"] = _player.hp
				_next()
		6:  # 強攻撃でザコを倒しきる（パリィ→強攻撃を繰り返す）
			if _zako.frames_until_active() == 3:
				_press("attack_light")  # 攻撃の出始めでパリィ
			if _zako.state == Enemy.State.STAGGER or _zako.state == Enemy.State.BROKEN:
				if since % 12 == 0:
					_press("attack_heavy")
			if _zako.is_dead() or since > 1500:
				_results["ザコ撃破"] = _zako.is_dead()
				_results["ザコ撃破までのフレーム"] = since
				_next()
		7:  # ボスへロックオン、パリィ不可（赤）は回避、それ以外はパリィ
			if since == 5 and _player.lock_target == null:
				_press("lock_on")
			var f := _boss.frames_until_active()
			if f == 3 and not _boss._current_unparryable:
				_press("attack_light")  # 攻撃の出始めでパリィ
			elif f == 2 and _boss._current_unparryable:
				_press("dodge")
			if _boss.state == Enemy.State.STAGGER or _boss.state == Enemy.State.BROKEN or GameFeel.is_witch_time():
				if since % 12 == 0:
					_press("attack_light")
			else:
				# ボスへ近づく
				var d := _boss.global_position - _player.global_position
				if d.length() > 3.0 and _player.state == Player.State.MOVE:
					Input.action_press("move_forward")
				else:
					Input.action_release("move_forward")
			if _boss.is_dead() or _player.is_dead() or since > 3000:
				Input.action_release("move_forward")
				_results["ボス撃破"] = _boss.is_dead()
				_results["ボスが第2形態になった"] = _boss.is_phase2()
				_results["ボス残りHP"] = _boss.hp
				_results["プレイヤー残りHP"] = _player.hp
				var hud: BattleHud = _main.battle_hud
				_results["HPバーの値が合う"] = int(hud.player_hp_bar.value) == _player.hp
				_next()
		8:
			# U-02：倒した敵のバーは隠れているか（1フレーム待ってHUDを更新させてから見る）
			if since < 2:
				return
			if since == 2:
				_results["敵バー非表示（撃破後）"] = not _main.battle_hud.enemy_panel.visible
			# U-03：ボスを倒したら、少し待って勝利画面が出て、ゲームが止まるか
			var rs: ResultScreen = _main.result_screen
			if not rs.visible and since < 200:
				return
			_results["勝利画面"] = rs.visible and rs.is_victory
			# F-06：ヒット・パリィ・ブレイクの火花が、それぞれ1回以上出たか
			var counts: Dictionary = _main.hit_sparks.spawn_counts
			_results["火花：ヒット %d回" % counts["hit"]] = counts["hit"] > 0
			_results["火花：パリィ %d回" % counts["parry"]] = counts["parry"] > 0
			_results["火花：ブレイク %d回" % counts["break"]] = counts["break"] > 0
			# F-05：4種類の音のファイルが読み込めていて、それぞれ1回以上鳴ったか
			var sfx: Sfx = _main.sfx
			for kind in ["hit", "parry", "perfect_dodge", "break"]:
				var n: int = sfx.play_counts[kind]
				_results["効果音：%s %d回" % [kind, n]] = sfx.is_loaded(kind) and n > 0
			_results["一時停止"] = get_tree().paused
			print("==== 結果 ====")
			for k in _results.keys():
				print("%s: %s" % [k, str(_results[k])])
			_main.quit_game()  # 音を止めてから終了する


func _next() -> void:
	_phase += 1
	_phase_start = _frame
