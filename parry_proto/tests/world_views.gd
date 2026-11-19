# Godot 4.7.2 / GDScript
# res://tests/world_views.gd
# 景色の確認用（テストではない）。エリアのいくつかの場所を、順にカメラで映す。遊ぶときは不要。
# 実行（画面あり）: godot --path . -- --world-views
#  録画するとき: godot --path . --write-movie 出力先/f.png --fixed-fps 60 -- --world-views
#  1か所を VIEW_FRAMES フレームずつ映して、最後まで行ったら終わる
#  場所ごとに、FPS（1秒に描けた回数）と描画の回数（ドローコール）を出力する
#  ※ 録画（--write-movie）のときは FPS が正しく出ない。画面ありで普通に動かしたときの値を見る
#  -- --world-views --uncapped にすると、60fps の上限を外して「どれだけ余裕があるか」を測れる
extends Node

const VIEW_FRAMES := 120
const MEASURE_FROM := 60   # 映し始めてから、このフレームより後の FPS を測る（読み込み直後は遅いため）
const VIEWS := [
	[Vector3(0, 2.2, 44), Vector3(0, 2, 30)],      # 落ち高架から花梨通り
	[Vector3(-2, 3, 24), Vector3(2, 1, 10)],        # 水路の上から広場の方へ
	[Vector3(-6, 3, 8), Vector3(4, 2, -8)],         # 止まり時計の広場
	[Vector3(0, 2, -14), Vector3(0, 1.5, -24)],     # 書店街の抜け道
	[Vector3(0, 4, -32), Vector3(0, 2, -50)],       # 旧市民ホール
	[Vector3(12, 14, 50), Vector3(0, 0, 15)],       # 上から
	[Vector3(-1.5, 2.0, 37.5), Vector3(2.2, 2.0, 43)],  # スタートの看板（プレイヤーが近くにいるので文章が出ている）
	[Vector3(-60, 95, 170), Vector3(10, 0, 10)],    # 広い街の全体（上空から。W-13）
	[Vector3(-30, 3, -1), Vector3(0, 2, -1)],       # 広場の西の出口から、広場を見る
	[Vector3(62, 2.2, 15), Vector3(58, 3, -40)],    # 広い街の通り（地面の高さ。W-13 ③）
	[Vector3(0.6, 1.7, 30.0), Vector3(3.4, 0.7, 34.0)],  # 放置された車（近くから。W-14）
]

var _main: Node
var _cam: Camera3D
var _frame := 0
var _fps_sum := 0.0
var _fps_n := 0
var _fps_min := 9999.0
var _draws := 0


func _ready() -> void:
	_main = get_parent()
	for e in _main.enemies:
		e.aggro_range = 0.0
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_main.add_child(_cam)
	_cam.make_current()
	_main._hud_layer.visible = false
	# -- --world-views --from=8：8番目の景色から映す（録画を短くしたいとき）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="):
			_frame = (int(a.get_slice("=", 1)) - 1) * VIEW_FRAMES
	# 余裕を測るため、この確認のときだけ 60fps の上限と垂直同期を外す（遊ぶときは 60fps のまま）
	# -- --world-views --low ／ --high：画質を決めて測る（保存はしない。ふだんはポーズメニューで選んだ画質）
	var args := OS.get_cmdline_user_args()
	if "--low" in args or "--high" in args:
		GraphicsSettings.current = GraphicsSettings.LOW if "--low" in args else GraphicsSettings.HIGH
		GraphicsSettings.apply(_main._environment, get_viewport(), _main._sun, Palette.FOG_DENSITY)
	# -- --off=ssil,ssao,vol,glow,msaa,shadow：高画質の効果を1つずつ切って、どれが重いか調べる（調べるとき用）
	for a in args:
		if a.begins_with("--off="):
			var env: Environment = _main._environment
			for f in a.get_slice("=", 1).split(","):
				match f:
					"ssil": env.ssil_enabled = false
					"ssao": env.ssao_enabled = false
					"vol": env.volumetric_fog_enabled = false
					"glow": env.glow_enabled = false
					"msaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
					"shadow": _main._sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	if "--uncapped" in OS.get_cmdline_user_args():
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _process(delta: float) -> void:
	var _delta := delta
	_frame += 1
	var i := _frame / VIEW_FRAMES
	var f := _frame % VIEW_FRAMES
	if f > MEASURE_FROM:
		var fps := 1.0 / maxf(_delta, 0.0001)
		_fps_sum += fps
		_fps_n += 1
		_fps_min = minf(_fps_min, fps)
		_draws = maxi(_draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	if f == 0 and i > 0:
		print("景色%d：FPS 平均 %.0f／最低 %.0f、ドローコール %d" % [i, _fps_sum / maxf(_fps_n, 1), _fps_min, _draws])
		_fps_sum = 0.0
		_fps_n = 0
		_fps_min = 9999.0
		_draws = 0
	if i >= VIEWS.size():
		_main.quit_game()
		set_process(false)
		return
	_cam.look_at_from_position(VIEWS[i][0], VIEWS[i][1])
