# Godot 4.7.2 / GDScript
# res://scripts/game/difficulty.gd
#
# 難易度（U-07）
#  ・「ふつう」は今までの数値そのまま（REQUIREMENTS.md 5章の値）
#  ・「やさしい」「むずかしい」は、下の表の値・倍率で変える（11/18 決定）
#      パリィの受付・ジャスト回避の受付（フレーム数）
#      敵の予兆の長さ・連撃の間隔（倍率。ボス第2形態の値にも掛ける。光る長さは変えない）
#      敵のダメージ（倍率）
#  ・プレイヤーの HP、敵の HP・体幹は変えない
#  ・current は static なので、リトライでシーンを読み直しても同じ難易度のまま
class_name Difficulty
extends RefCounted

const EASY := "easy"
const NORMAL := "normal"
const HARD := "hard"
const ORDER: Array[String] = [EASY, NORMAL, HARD]

const SETTINGS := {
	EASY: {
		"label": "やさしい", "note": "パリィの受付が長く、敵の攻撃がゆっくりで痛くない。はじめての人に",
		"parry_window_frames": 12, "perfect_dodge_frames": 14,
		"telegraph_mult": 1.3, "combo_gap_mult": 1.3, "damage_mult": 0.5,
	},
	NORMAL: {
		"label": "ふつう", "note": "標準の難しさ。迷ったらこれ",
		"parry_window_frames": 9, "perfect_dodge_frames": 12,
		"telegraph_mult": 1.0, "combo_gap_mult": 1.0, "damage_mult": 1.0,
	},
	HARD: {
		"label": "むずかしい", "note": "パリィの受付が短く、敵の攻撃が速くて痛い。慣れた人に",
		"parry_window_frames": 7, "perfect_dodge_frames": 9,
		"telegraph_mult": 0.85, "combo_gap_mult": 0.85, "damage_mult": 1.5,
	},
}

static var current := NORMAL


static func value(key: String) -> Variant:
	return SETTINGS[current][key]


static func label(id: String = "") -> String:
	return SETTINGS[current if id == "" else id]["label"]


# 倍率を掛けたフレーム数（四捨五入。最低でも min_frames）
static func scale_frames(base: int, mult_key: String, min_frames: int = 1) -> int:
	return maxi(roundi(float(base) * float(value(mult_key))), min_frames)
