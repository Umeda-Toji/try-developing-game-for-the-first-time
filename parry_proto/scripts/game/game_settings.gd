# Godot 4.7.2 / GDScript
# res://scripts/game/game_settings.gd
#
# 設定（O-01。11/19。オートロード "GameSettings"）
#  ・音量を種類ごとに：全体・BGM・効果音・環境音（0〜100%。100% が今までの大きさ）。音のバス Master／BGM／SFX／Ambient に当てる
#  ・感度：マウス・パッド × ふつう・構え（倍率 0.2〜3.0。ふつう 1.0＝今まで、構え 0.6）。構えの感度は銃（ステップ5）で効く
#  ・カメラの反転：上下・左右（最初はオフ）
#  ・狙いの補助：パッドで構えたとき、照準が敵に少し吸い付く（最初はオン。銃（ステップ5）で効く）
#  ・保存先は画質と同じ user://settings.cfg の [options]（ゲームのセーブとは別。「はじめから」でも消えない）
#  ・自動テスト（起動に -- の付いた引数があるとき）は、読まない・書かない。--settings-test だけはテスト用の別のファイルを使う
extends Node

signal changed   # 設定が変わった

const SAVE_PATH := "user://settings.cfg"
const TEST_SAVE_PATH := "user://settings_test.cfg"
const TEST_FLAG := "--settings-test"
const SECTION := "options"

const VOLUME_KEYS := ["master", "bgm", "sfx", "ambient"]
const VOLUME_LABELS := {"master": "全体", "bgm": "BGM", "sfx": "効果音", "ambient": "環境音"}
const BUS_NAMES := {"master": "Master", "bgm": "BGM", "sfx": "SFX", "ambient": "Ambient"}
const VOLUME_STEP := 0.05
const VOLUME_DEFAULT := 1.0

const SENS_KEYS := ["mouse", "pad", "mouse_aim", "pad_aim"]
const SENS_LABELS := {"mouse": "マウス（ふつう）", "pad": "パッド（ふつう）", "mouse_aim": "マウス（構え）", "pad_aim": "パッド（構え）"}
const SENS_MIN := 0.2
const SENS_MAX := 3.0
const SENS_STEP := 0.1
const SENS_DEFAULTS := {"mouse": 1.0, "pad": 1.0, "mouse_aim": 0.6, "pad_aim": 0.6}

# 狙いの補助（パッドで構えたとき。銃で使う）
const AIM_ASSIST_ANGLE_DEG := 4.0   # 照準からこの角度の中の敵に吸い付く
const AIM_ASSIST_RANGE := 30.0      # この距離（m）までの敵
const AIM_ASSIST_PULL := 0.15       # 1フレームで、残りの角度のこの割合だけ寄る

var volumes := {}
var sens := {}
var invert_x := false
var invert_y := false
var aim_assist := true
var tracers := true          # 弾道の表示（撃った弾の光の線と火花。G-07）
var debug_hud := false       # 調整用の文字（FPS・敵の状態・ログ）を出すか（U-10。最初は隠す）
var hints := true            # 操作のヒント（U-11。最初は出す）
var save_enabled := true
var save_path := SAVE_PATH


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if TEST_FLAG in args:
		save_path = TEST_SAVE_PATH
	else:
		for a in args:
			if a.begins_with("--"):
				save_enabled = false  # 自動テストは、遊んでいる人の設定を使わない
	reset_to_defaults()
	_ensure_buses()
	load_settings()
	apply_audio()


func reset_to_defaults() -> void:
	for k in VOLUME_KEYS:
		volumes[k] = VOLUME_DEFAULT
	sens = SENS_DEFAULTS.duplicate()
	invert_x = false
	invert_y = false
	aim_assist = true
	tracers = true
	debug_hud = false
	hints = true


# 音のバス（BGM・SFX・Ambient）を作る。どれも Master に流れる
func _ensure_buses() -> void:
	for k in ["bgm", "sfx", "ambient"]:
		var name: String = BUS_NAMES[k]
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")


func apply_audio() -> void:
	for k in VOLUME_KEYS:
		var idx := AudioServer.get_bus_index(BUS_NAMES[k])
		if idx == -1:
			continue
		var v: float = volumes[k]
		AudioServer.set_bus_mute(idx, v <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


func set_volume(key: String, v: float) -> void:
	volumes[key] = clampf(snappedf(v, VOLUME_STEP), 0.0, 1.0)
	apply_audio()
	save_settings()
	changed.emit()


func set_sens(key: String, v: float) -> void:
	sens[key] = clampf(snappedf(v, SENS_STEP), SENS_MIN, SENS_MAX)
	save_settings()
	changed.emit()


func set_flag(key: String, on: bool) -> void:
	match key:
		"invert_x":
			invert_x = on
		"invert_y":
			invert_y = on
		"aim_assist":
			aim_assist = on
		"tracers":
			tracers = on
		"debug_hud":
			debug_hud = on
		"hints":
			hints = on
	save_settings()
	changed.emit()


# カメラの回し方の倍率（感度×反転）。aiming は構えているとき（銃）
func look_scale(is_mouse: bool, aiming: bool = false) -> Vector2:
	var key := ("mouse" if is_mouse else "pad") + ("_aim" if aiming else "")
	var s: float = sens[key]
	return Vector2(s * (-1.0 if invert_x else 1.0), s * (-1.0 if invert_y else 1.0))


func save_settings() -> bool:
	if not save_enabled:
		return false
	var cfg := ConfigFile.new()
	cfg.load(save_path)  # 画質（[graphics]）などは残す
	for k in VOLUME_KEYS:
		cfg.set_value(SECTION, "volume_" + k, volumes[k])
	for k in SENS_KEYS:
		cfg.set_value(SECTION, "sens_" + k, sens[k])
	cfg.set_value(SECTION, "invert_x", invert_x)
	cfg.set_value(SECTION, "invert_y", invert_y)
	cfg.set_value(SECTION, "aim_assist", aim_assist)
	cfg.set_value(SECTION, "tracers", tracers)
	cfg.set_value(SECTION, "debug_hud", debug_hud)
	cfg.set_value(SECTION, "hints", hints)
	return cfg.save(save_path) == OK


func load_settings() -> bool:
	if not save_enabled:
		return false
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return false
	for k in VOLUME_KEYS:
		volumes[k] = clampf(float(cfg.get_value(SECTION, "volume_" + k, VOLUME_DEFAULT)), 0.0, 1.0)
	for k in SENS_KEYS:
		sens[k] = clampf(float(cfg.get_value(SECTION, "sens_" + k, SENS_DEFAULTS[k])), SENS_MIN, SENS_MAX)
	invert_x = bool(cfg.get_value(SECTION, "invert_x", false))
	invert_y = bool(cfg.get_value(SECTION, "invert_y", false))
	aim_assist = bool(cfg.get_value(SECTION, "aim_assist", true))
	tracers = bool(cfg.get_value(SECTION, "tracers", true))
	debug_hud = bool(cfg.get_value(SECTION, "debug_hud", false))
	hints = bool(cfg.get_value(SECTION, "hints", true))
	return true
