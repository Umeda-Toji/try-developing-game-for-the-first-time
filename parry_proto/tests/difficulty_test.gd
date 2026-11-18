# Godot 4.7.2 / GDScript
# res://tests/difficulty_test.gd
# 難易度（U-07）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --difficulty-test
#  やさしい／ふつう／むずかしい を順に当てはめて、数値が表どおりか確かめる
#   ・「ふつう」は今までの数値（REQUIREMENTS.md 5章）のまま
#   ・何度当てはめても同じ結果になる（倍率が二重に掛からない）
#   ・パリィの受付が実際に長く／短くなる
extends Node

# 難易度ごとの、期待する値
#  player: [パリィ受付, ジャスト回避]
#  zako:   [予兆, フェイントの溜め, ニセの光, ダメージ]
#  boss:   [予兆, 連撃の間隔, 第2形態の予兆, 第2形態の間隔, ダメージ]
const EXPECTED := {
	Difficulty.EASY: {"player": [12, 14], "zako": [47, 86, 34, 8], "boss": [52, 23, 39, 18, 10]},
	Difficulty.NORMAL: {"player": [9, 12], "zako": [36, 66, 26, 15], "boss": [40, 18, 30, 14, 20]},
	Difficulty.HARD: {"player": [7, 9], "zako": [31, 56, 22, 23], "boss": [34, 15, 26, 12, 30]},
}

var _main: Node
var _frame := 0
var _results := {}


func _ready() -> void:
	_main = get_parent()
	for e in _main.enemies:  # 敵は動かさない
		e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame != 3:
		return
	var p: Player = _main.player
	var zako: Enemy = _main.enemies[0]
	var boss: Enemy = _main.boss
	_results["「ふつう」の受付は5章の値と同じ"] = Difficulty.SETTINGS[Difficulty.NORMAL]["parry_window_frames"] == Player.PARRY_WINDOW_FRAMES and Difficulty.SETTINGS[Difficulty.NORMAL]["perfect_dodge_frames"] == Player.PERFECT_DODGE_FRAMES
	for id in Difficulty.ORDER:
		Difficulty.current = id
		for _i in 2:  # 2回当てはめても同じになるか
			p.apply_difficulty()
			zako.apply_difficulty()
			boss.apply_difficulty()
		var got := {
			"player": [p.parry_window_frames, p.perfect_dodge_frames],
			"zako": [zako.telegraph_frames, zako.feint_telegraph_frames, zako.feint_glint_start, zako.damage],
			"boss": [boss.telegraph_frames, boss.combo_gap_frames, boss.phase2_telegraph_frames, boss.phase2_combo_gap_frames, boss.damage],
		}
		for who in ["player", "zako", "boss"]:
			_results["%s：%s %s" % [Difficulty.label(id), who, str(got[who])]] = got[who] == EXPECTED[id][who]
		# パリィの受付が実際にその長さになっているか（受付の最後のフレームは受付中、次のフレームは受付外）
		p._start_attack("L1", true)
		p.state_frame = p.parry_window_frames
		var in_window := p._is_parry_window()
		p.state_frame = p.parry_window_frames + 1
		var after_window := p._is_parry_window()
		_results["%s：パリィ受付は %dフレーム目まで" % [Difficulty.label(id), p.parry_window_frames]] = in_window and not after_window
		# フェイントのニセの光は、本物の光より前に終わる
		_results["%s：フェイントのニセの光は本物より前" % Difficulty.label(id)] = zako.feint_glint_start + zako.glint_frames < zako.feint_telegraph_frames - zako.glint_frames
	Difficulty.current = Difficulty.NORMAL
	print("==== 難易度テスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
