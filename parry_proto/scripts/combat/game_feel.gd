# Godot 4.7.2 / GDScript
# res://scripts/combat/game_feel.gd
# オートロード名: GameFeel
# 手ごたえ演出（カメラ揺れ・ジャスト回避のスロー・火花）をまとめる。
#
# スローは Engine.time_scale を使わず「敵だけ遅くする」方式。
#   - プレイヤーは通常速度のまま反撃できる（いわゆる"ウィッチタイム"）
#   - フレーム数で数えている判定がズレない
extends Node

signal shake_requested(strength: float, frames: int)
signal witch_time_changed(active: bool)
signal spark_requested(pos: Vector3, kind: String)

# 火花の種類（F-06）。見た目は scripts/combat/hit_sparks.gd の表で決める
const SPARK_HIT := "hit"       # 攻撃が当たった
const SPARK_PARRY := "parry"   # パリィ成功
const SPARK_BREAK := "break"   # 体幹ブレイク

var enemy_time_scale := 1.0
var _slow_frames_left := 0


func shake(strength: float, frames: int) -> void:
	shake_requested.emit(strength, frames)


# 火花を出す（実際に出すのは main.gd が作る HitSparks）
func spark(pos: Vector3, kind: String) -> void:
	spark_requested.emit(pos, kind)


func start_witch_time(scale: float, frames: int) -> void:
	enemy_time_scale = scale
	_slow_frames_left = frames
	witch_time_changed.emit(true)


# リトライ時に呼ぶ。オートロードはシーンを読み直しても残るので、スローを確実に止める
func reset() -> void:
	enemy_time_scale = 1.0
	_slow_frames_left = 0


func is_witch_time() -> bool:
	return _slow_frames_left > 0


func _physics_process(_delta: float) -> void:
	if _slow_frames_left > 0:
		_slow_frames_left -= 1
		if _slow_frames_left == 0:
			enemy_time_scale = 1.0
			witch_time_changed.emit(false)
