# Godot 4.7.2 / GDScript
# res://tests/settings_test.gd
# 設定（O-01）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --settings-test
#  （遊んでいる人の user://settings.cfg は使わず、user://settings_test.cfg を使って、最後に消す）
#  1. 最初の値：音量は全部100%、感度は ふつう1.0・構え0.6、反転はオフ、狙いの補助はオン
#  2. ポーズメニューの「設定」で開き、Esc で戻る
#  3. 全体の音量を50%にすると、Master の音量が下がる。BGM・効果音は、それぞれの音のバスを通る。0% で消える
#  4. マウスの感度を2.0倍にすると、同じ動きでカメラが2倍回る。左右・上下の反転で向きが逆になる
#  5. 保存して、読み直すと元に戻る。画質の設定（[graphics]）は消えない
#  6. タイトル画面にも「設定」がある
extends Node

var _main: Node
var _t := 0
var _results := {}
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_main = get_parent()
	_delete_file()


func _physics_process(_delta: float) -> void:
	_t += 1
	# 録画で画面を見るときは --settings-hold：先に設定の画面を開いて、しばらく見せる
	var hold := "--settings-hold" in OS.get_cmdline_user_args()
	if hold and _t == 10:
		_main.pause_menu.open()
		_main.pause_menu.open_settings()
	if _done or _t != (40 if hold else 20):
		return
	var gs := GameSettings
	_results["保存は テスト用のファイル（%s）" % gs.save_path] = gs.save_path == GameSettings.TEST_SAVE_PATH
	_results["最初の値（音量100%・感度1.0／構え0.6・反転オフ・狙いの補助オン）"] = (
		gs.volumes.values().all(func(v): return is_equal_approx(v, 1.0))
		and is_equal_approx(gs.sens["mouse"], 1.0) and is_equal_approx(gs.sens["pad"], 1.0)
		and is_equal_approx(gs.sens["mouse_aim"], 0.6) and is_equal_approx(gs.sens["pad_aim"], 0.6)
		and not gs.invert_x and not gs.invert_y and gs.aim_assist and gs.tracers)

	# ポーズメニューから開く
	var pm: PauseMenu = _main.pause_menu
	pm.open()
	pm.settings_button.pressed.emit()
	var panel: SettingsPanel = pm.settings_panel
	_results["ポーズメニューの「設定」で開く"] = pm.settings_open and panel.visible and not pm._menu_box.visible

	# 音量
	var bgm_ok: bool = (_main.bgm.get_node("Bgm_battle") as AudioStreamPlayer).bus == "BGM"
	var sfx_ok := true
	for c in _main.sfx.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).bus != "SFX":
			sfx_ok = false
	_results["BGM・効果音は、それぞれの音のバスを通る"] = bgm_ok and sfx_ok and AudioServer.get_bus_index("Ambient") != -1
	(panel.sliders["volume_master"] as HSlider).value = 0.5
	var db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	_results["全体の音量 50%% で Master が %.1f dB" % db] = absf(db - linear_to_db(0.5)) < 0.1 and is_equal_approx(gs.volumes["master"], 0.5)
	(panel.sliders["volume_bgm"] as HSlider).value = 0.0
	_results["BGM の音量 0% で BGM が消える"] = AudioServer.is_bus_mute(AudioServer.get_bus_index("BGM"))

	# 感度・反転
	var rig: Node3D = _main.get_node("CameraRig")
	var y0: float = rig.yaw
	rig.apply_look(Vector2(10, 0) * 0.003, true)
	var d1: float = rig.yaw - y0
	(panel.sliders["sens_mouse"] as HSlider).value = 2.0
	y0 = rig.yaw
	rig.apply_look(Vector2(10, 0) * 0.003, true)
	var d2: float = rig.yaw - y0
	_results["マウスの感度2.0倍で、カメラが2倍回る（%.3f → %.3f）" % [d1, d2]] = absf(d2 - d1 * 2.0) < 0.0001
	(panel.checks["invert_x"] as CheckButton).button_pressed = true
	y0 = rig.yaw
	rig.apply_look(Vector2(10, 0) * 0.003, true)
	var d3: float = rig.yaw - y0
	(panel.checks["invert_y"] as CheckButton).button_pressed = true
	var p0: float = rig.pitch
	rig.apply_look(Vector2(0, 10) * 0.003, true)
	var dp: float = rig.pitch - p0
	_results["左右・上下の反転で向きが逆になる（%.3f、縦 %.3f）" % [d3, dp]] = absf(d3 + d2) < 0.0001 and dp > 0.0

	# 保存・読み直し（画質の [graphics] は残る）
	var cfg := ConfigFile.new()
	cfg.load(gs.save_path)
	cfg.set_value("graphics", "quality", "low")
	cfg.save(gs.save_path)
	(panel.checks["aim_assist"] as CheckButton).button_pressed = false
	gs.reset_to_defaults()
	gs.load_settings()
	var cfg2 := ConfigFile.new()
	cfg2.load(gs.save_path)
	_results["保存して読み直すと元に戻り、画質の設定も残る"] = (
		is_equal_approx(gs.volumes["master"], 0.5) and is_equal_approx(gs.volumes["bgm"], 0.0) and is_equal_approx(gs.sens["mouse"], 2.0)
		and gs.invert_x and gs.invert_y and not gs.aim_assist and cfg2.get_value("graphics", "quality", "") == "low")

	# Esc で戻る
	pm.close_settings()
	_results["戻ると、ポーズメニューに戻る（「設定」が選ばれている）"] = not pm.settings_open and pm._menu_box.visible and pm.settings_button.has_focus()
	pm.close()

	# タイトル画面
	var title: TitleScreen = _main.title_screen
	title.open()
	title.settings_button.pressed.emit()
	_results["タイトル画面にも「設定」がある"] = title.settings_open and title.settings_panel.visible
	title.close()

	gs.reset_to_defaults()
	gs.apply_audio()
	_delete_file()
	_done = true
	print("==== 設定のテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()


func _delete_file() -> void:
	if FileAccess.file_exists(GameSettings.TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.TEST_SAVE_PATH))
