# Godot 4.7.2 / GDScript
# res://tests/enemy_model_test.gd
# 敵の3Dモデルとアニメーション（P-16）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --enemy-model-test
#  プレイヤーは動かさず、ザコに攻撃させて次を確かめる
#   ・使うアニメが全部ある／ザコはマネキンを赤く塗る、ボスは素材の色のまま・大きさが当たり判定と同じ
#   ・攻撃判定が出る瞬間に、ちょうど「振り下ろしの瞬間」のポーズになる（見た目と判定がずれない）
#   ・パリィの合図（光る）中は強く色が付く
#   ・倒れるとやられのアニメになる
extends Node

var _main: Node
var _zako: Enemy
var _boss: Enemy
var _frame := 0
var _results := {}
var _swing_checked := false
var _swing_ok := false
var _glint_seen := false
var _glint_ok := true
var _dead_start := -1
var _red_ok := true
var _red_off_ok := true


func _ready() -> void:
	process_physics_priority = 100  # 敵の後に動いて、そのtickのポーズを確かめる
	_main = get_parent()
	_zako = _main.enemies[0]
	_boss = _main.boss
	_main.remove_extra_enemies()  # ザコとボスだけで試す
	_boss.aggro_range = 0.0
	_main.player.hp = 100000  # テスト中にプレイヤーが倒れないように
	_zako.global_position = _main.player.global_position + Vector3(0, 0, -2.0)  # すぐ攻撃してくるように近くへ


func _physics_process(_delta: float) -> void:
	_frame += 1
	_watch_zako()
	match _frame:
		2:
			var clips: Array[String] = [Enemy.ANIM_IDLE, Enemy.ANIM_MOVE, Enemy.ANIM_HITSTUN, Enemy.ANIM_STAGGER,
				Enemy.ANIM_BROKEN, Enemy.ANIM_PHASE_CHANGE, Enemy.ANIM_DEATH, Enemy.DEFAULT_ATTACK_ANIM["clip"]]
			for a in _boss.attack_anims:
				clips.append(a["clip"])
			var missing: Array[String] = []
			for c in clips:
				if not _zako.model.has_clip(c):
					missing.append(c)
			_results["アニメが全部ある（足りない：%s）" % str(missing)] = missing.is_empty()
			_results["ザコはモデルを塗り替える／ボスは素材の色のまま"] = _zako.recolor_model and not _boss.recolor_model
			_results["ボスはザコより大きい"] = _boss.model.scale.x > _zako.model.scale.x * 1.5
			_results["敵に剣が付いている"] = _zako.model.find_child("Sword", true, false) != null and _boss.model.find_child("Sword", true, false) != null
		240:
			_results["攻撃判定が出る瞬間に振り下ろしのポーズ"] = _swing_checked and _swing_ok
			_results["パリィの合図の間は強く光る"] = _glint_seen and _glint_ok
			_results["合図の間はまわりを赤く照らし、それ以外は消える"] = _glint_seen and _red_ok and _red_off_ok
			_zako.receive_attack({"damage": 9999, "posture": 0, "hitstop": 0}, self)
			_dead_start = _frame
		300:
			var expect := float(_frame - _dead_start) * CharacterModel.TICK_SEC
			_results["倒れるとやられのアニメ（1tickずつ進む）"] = _zako.model.current_clip == Enemy.ANIM_DEATH and absf(_zako.model.current_time - expect) <= CharacterModel.TICK_SEC * 1.01
			print("==== 敵モデルテスト結果 ====")
			for k in _results.keys():
				print("%s: %s" % [k, str(_results[k])])
			_main.quit_game()


func _watch_zako() -> void:
	if _zako.state == Enemy.State.ATTACK and _zako.state_frame == 0 and _zako.hitstop_frames == 0 and not _swing_checked:
		_swing_checked = true
		var a := _zako._swing_anim
		_swing_ok = _zako.model.current_clip == a["clip"] and is_equal_approx(_zako.model.current_time, a["key"])
	if _zako.is_glinting():
		_glint_seen = true
		_glint_ok = _glint_ok and is_equal_approx(_zako.model.tint_strength(), Enemy.GLINT_STRENGTH)
		_red_ok = _red_ok and _zako.warn_light.light_energy > 0.0  # 合図の間は赤い光
	elif _zako.state != Enemy.State.TELEGRAPH:
		_red_off_ok = _red_off_ok and _zako.warn_light.light_energy == 0.0
