# Godot 4.7.2 / GDScript
# res://scripts/main.gd
#
# 「1つの部屋・敵1体・ボス1体」の試作ステージを、コードから組み立てる。
# キャラクターは Quaternius のモデル（P-16）。壁・床は箱。
# エディタでシーンを手作業で作らなくても F5 で遊べる。
# 慣れてきたら、Player/Enemy を .tscn に分けて見た目のモデルを差し替えていけばOK。
#
# 物理レイヤー（ビット番号）
#   1: 地形   2: プレイヤー本体   3: 敵本体
#   4: プレイヤーの被弾判定(Hurtbox)   5: 敵の被弾判定(Hurtbox)
extends Node3D

const TOON := preload("res://shaders/toon.gdshader")
# キャラクター（P-16）：服（Modular Character Outfits の Ranger）＋ 顔は素体モデルから借りる
const PLAYER_MODEL := "res://models/outfits/Male_Ranger.gltf"
const PLAYER_HEAD := "res://models/characters/Superhero_Male_FullBody.gltf"
# 剣（Quaternius の Medieval Weapons。CC0）と長さ（m）
const PLAYER_SWORD := "res://models/weapons/Sword.fbx"
const PLAYER_SWORD_LENGTH := 1.0
const ENEMY_SWORD_LENGTH := 0.9
# _build_enemy の params のうち、敵のスクリプトではなく見た目の組み立てに使うもの
const VISUAL_PARAMS := ["model_path", "sword_path", "head_path", "outfit_texture",
	"sword_length", "sword_model_length", "left_sword_path"]
const ZAKO_MODEL := "res://models/animations/UAL1_Standard.glb"  # アニメ素材の中のマネキン
# 敵の種類（ザコ・重装兵・双剣士・魔法使い）：[表示名, 当たり判定の大きさ, 設定]。広場と、街の寄り道の敵（W-15 ④-3）で使う
const ENEMY_KINDS := {
	"zako": ["ザコ敵", Vector3(0.9, 1.6, 0.9), {
		"feint_every": 3,  # 3回に1回フェイント攻撃（E-10）
		"model_path": ZAKO_MODEL,  # マネキンを body_color（赤）で塗る（P-16）
		"sword_path": "res://models/weapons/Sword_2.fbx",
		"flower_model": "Petal_5", "flower_size": 0.45,  # 頭の花（F-01）：5枚の広い花びら
	}],
	"heavy": ["重装兵", Vector3(1.1, 1.95, 1.1), {
		"aggro_range": 10.0, "max_hp": 120, "max_posture": 100.0, "move_speed": 2.0, "attack_range": 2.6,
		"telegraph_frames": 50, "glint_frames": 10, "recover_frames": 45, "damage": 25,
		"unparryable_every": 2, "body_color": Color(0.45, 0.47, 0.52),
		"model_path": ZAKO_MODEL, "sword_path": "res://models/weapons/Hammer_Double.fbx",
		"sword_length": 1.1, "sword_model_length": 4.97,
		"flower_model": "Petal_3", "flower_size": 0.6,  # 頭の花：6枚のとがった花びら
	}],
	"swift": ["双剣士", Vector3(0.8, 1.45, 0.8), {
		"aggro_range": 10.0, "max_hp": 50, "max_posture": 40.0, "move_speed": 4.5, "attack_range": 1.9,
		"telegraph_frames": 24, "glint_frames": 10, "combo_hits": 3, "combo_gap_frames": 14,
		"recover_frames": 25, "damage": 8, "body_color": Color(0.25, 0.65, 0.35),
		"model_path": ZAKO_MODEL, "sword_path": "res://models/weapons/Dagger.fbx",
		"left_sword_path": "res://models/weapons/Dagger.fbx", "sword_length": 0.5, "sword_model_length": 2.61,
		"attack_anims": [
			{"clip": "ual2/Sword_Regular_A", "from": 0.05, "key": 0.21, "to": 0.43},
			{"clip": "ual2/Sword_Regular_B", "from": 0.05, "key": 0.22, "to": 0.53},
		],
		"flower_model": "Petal_1", "flower_size": 0.35,  # 頭の花：少ない細い花びら
	}],
	"caster": ["魔法使い", Vector3(0.9, 1.7, 0.9), {
		"ranged": true, "aggro_range": 12.0, "max_hp": 40, "max_posture": 40.0, "move_speed": 2.5,
		"keep_distance_min": 5.0, "keep_distance_max": 8.0, "projectile_speed": 8.0,
		"telegraph_frames": 40, "glint_frames": 10, "recover_frames": 30, "attack_cooldown_frames": 70,
		"damage": 12, "body_color": Color(0.3, 0.4, 0.95), "model_path": ZAKO_MODEL,
		"attack_anims": [{"clip": "ual1/Spell_Simple_Shoot", "windup_clip": "ual1/Spell_Simple_Enter",
			"from": 0.0, "key": 0.08, "to": 0.5}],
		"flower_model": "Petal_2", "flower_size": 0.45,  # 頭の花：細い星の形
	}],
}
const BOSS_MODEL := "res://models/outfits/Female_Ranger.gltf"
const BOSS_HEAD := "res://models/characters/Superhero_Female_FullBody.gltf"
const BOSS_OUTFIT_TEXTURE := "res://models/outfits/T_Ranger_3_BaseColor.png"  # 服の色違い（プレイヤーと見分ける）
# 自動テスト（--autotest などを付けて起動したときだけ動く）
const TEST_SCRIPTS := {
	"--autotest": "res://tests/autotest.gd",        # 通しの自動プレイ
	"--retry-test": "res://tests/retry_test.gd",    # 敗北→リトライ（U-03）
	"--charge-test": "res://tests/charge_test.gd",  # 強攻撃の溜め（P-15）
	"--soft-lock-test": "res://tests/soft_lock_test.gd",  # ソフトロック（P-17）
	"--feint-test": "res://tests/feint_test.gd",  # ザコのフェイント攻撃（E-10）
	"--phase2-test": "res://tests/phase2_test.gd",  # ボス第2形態（E-11）
	"--pause-test": "res://tests/pause_test.gd",  # ポーズメニュー（U-04）
	"--model-test": "res://tests/model_test.gd",  # プレイヤーのモデルとアニメ（P-16）
	"--enemy-model-test": "res://tests/enemy_model_test.gd",  # 敵のモデルとアニメ（P-16）
	"--title-test": "res://tests/title_test.gd",  # タイトル画面（U-06）
	"--difficulty-test": "res://tests/difficulty_test.gd",  # 難易度（U-07）
	"--enemy-types-test": "res://tests/enemy_types_test.gd",  # 重装兵・双剣士（E-12・E-13）
	"--ranged-test": "res://tests/ranged_test.gd",  # 魔法使い・弾の跳ね返し（E-14）
	"--movement-test": "res://tests/movement_test.gd",  # ジャンプ・滑空・走る・スタミナ（M-01〜M-04）
	"--enemy-bars-test": "res://tests/enemy_bars_test.gd",  # 敵の頭の上の体力バー（U-08）
	"--world-test": "res://tests/world_test.gd",  # 白砂市のエリア・壁のぼり・泳ぎ（W-01〜、M-05・M-06）
	"--world-views": "res://tests/world_views.gd",
	"--items-test": "res://tests/items_test.gd",  # 回復・強化アイテム（W-15 ④-2）
	"--side-enemies-test": "res://tests/side_enemies_test.gd",  # 街の寄り道の敵（W-15 ④-3）
	"--vista-test": "res://tests/vista_test.gd",  # 眺めのいい場所（W-15 ④-4）
	"--save-test": "res://tests/save_test.gd",  # セーブ（S-01）
	"--map-test": "res://tests/map_test.gd",  # 地図（C）
	"--settings-test": "res://tests/settings_test.gd",  # 設定（O-01）
	"--lockon-test": "res://tests/lockon_test.gd",  # ロックオンの切り替え（L-01）
	"--flower-test": "res://tests/flower_test.gd",  # 敵の頭の花（F-01）
	"--sound-test": "res://tests/sound_test.gd",  # 探索の曲・環境音・花の音（A-01〜A-03）
	"--weapon-test": "res://tests/weapon_test.gd",  # 武器の持ち替え・武器の輪（G-01・G-02）
	"--gun-test": "res://tests/gun_test.gd",  # 撃つ・構え・反動・リロード（G-03）
	"--terrain-test": "res://tests/terrain_test.gd",  # 起伏のある地面（T-01・T-02。6a の試し）
	"--hints-test": "res://tests/hints_test.gd",  # 操作のヒント・操作の一覧（U-11）  # 景色の確認用（テストではない。エリアを順に映す）
}
const TITLE_TEST_FLAG := "--title-test"  # テストのうち、これだけはタイトル画面を出す
const WORLD_TEST_FLAGS := ["--world-test", "--world-views", "--items-test", "--side-enemies-test", "--vista-test", "--save-test", "--map-test", "--sound-test", "--hints-test"]  # これらは白砂市のエリアで動かす（ほかのテストは20m四方の部屋）
const SKIP_TITLE_KEY := "skip_title"     # リトライのとき true にしておく（読み直した後はタイトルを出さない）
# タイトル画面の後ろに映す景色（部屋全体を斜め上から。手前にプレイヤー、奥にザコとボス）
const TITLE_CAMERA_POS := Vector3(-5.0, 3.2, 9.5)
const TITLE_CAMERA_LOOK_AT := Vector3(1.0, 1.4, -3.0)
const TITLE_CAMERA_FOV := 60.0
const RESULT_DELAY_FRAMES := 60  # 勝ち負けが決まってから結果画面を出すまで（倒れる様子を見せる）

var player: Player
var enemies: Array[Enemy] = []
var boss: Enemy
var heavy: Enemy   # 重装兵（E-12）
var swift: Enemy   # 双剣士（E-13）
var caster: Enemy  # 魔法使い（E-14）
var side_enemies: Array[Enemy] = []  # 街の寄り道の敵（W-15 ④-3）
var _side_check_left := 0
const SIDE_AGGRO_RANGE := 12.0      # 寄り道の敵が気づく距離（m）
const SIDE_SLEEP_DISTANCE := 50.0   # これより遠い寄り道の敵は止めておく（m）
const SIDE_CHECK_FRAMES := 20       # 止める・動かすを確かめる間隔（フレーム）
var battle_hud: BattleHud  # HPバー・体幹バー（U-02）
var enemy_bars: EnemyBars  # 敵の頭の上の体力バー（U-08）
var result_screen: ResultScreen  # 勝利／敗北の画面（U-03）
var pause_menu: PauseMenu  # ポーズメニュー（U-04）
var slow_effect: SlowEffect  # スロー中の画面演出（F-04）
var hit_sparks: HitSparks  # ヒット・パリィ・ブレイクの火花（F-06）
var sfx: Sfx  # 効果音（F-05）
var bgm: Bgm  # BGM（F-07）
var ambience: Ambience  # 環境音（A-02。エリアのときだけ）
var weapon_wheel: WeaponWheel  # 武器の輪（G-02）
var hint_box: HintBox  # 操作のヒント（U-11。エリアのときだけ）
var title_screen: TitleScreen  # タイトル画面（U-06）
var _hud_layer: CanvasLayer
var use_world := true      # true：白砂市のエリア（W-01〜）／false：20m四方の部屋（自動テスト用）
var boss_door: BossDoor    # 旧市民ホールの扉（エリアのときだけ）
var _side_spots: Array = []
var vista_director: VistaDirector  # 眺めのいい場所でカメラを動かす（W-15 ④-4。エリアのときだけ）  # 寄り道の敵を置く場所と種類（CityBuilder.side_spots）
var world_decor := {}      # 自動で作った飾りの数（種類 → 数。テスト・報告用）
var _environment: Environment
var _sun: DirectionalLight3D
var _result_decided := false
var _result_victory := false
var _result_wait := 0
var _quitting := false
# 音を止めてから本当に終了するまで待つ「実際の時間」（ミリ秒）。
# 判定ではなくオーディオの片付けを待つだけなので、フレームではなく実時間で待つ
# （--fixed-fps のテストではフレームが実時間より速く進むため、フレームで数えると足りない）
const QUIT_WAIT_MSEC := 100
var _hud: Label
var _log_lines: Array[String] = []


func _ready() -> void:
	get_tree().auto_accept_quit = false  # ×ボタンで閉じるときは _notification() で quit_game() を呼ぶ
	_setup_input_map()
	# 自動テスト（--world-test 以外）は、今までの20m四方の部屋で動かす（敵の位置が変わってテストが壊れないように）
	var args := OS.get_cmdline_user_args()
	var test_flag := TEST_SCRIPTS.keys().any(func(f): return f in args)
	use_world = not test_flag or WORLD_TEST_FLAGS.any(func(f): return f in args)
	_build_world()
	hit_sparks = HitSparks.new()
	hit_sparks.name = "HitSparks"
	add_child(hit_sparks)
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	player = _build_player(_spawn("player", Vector3(0, 0.1, 6)))
	player.wheel_requested.connect(_open_weapon_wheel)
	if use_world:
		player.kill_y = WorldBuilder.KILL_Y
		apply_saved_position()
	enemies.append(_build_enemy_kind("zako", _spawn("zako", Vector3(-3, 0.1, -2))))
	# 重装兵（E-12）：大きくて遅い。予兆が長く一撃が重い。体幹が多く、2回に1回パリィできない攻撃（赤く光る）
	heavy = _build_enemy_kind("heavy", _spawn("heavy", Vector3(-6, 0.1, -6)))
	enemies.append(heavy)
	# すばやい敵（E-13）：小さくて速い。予兆の短い3連撃。HPが少ない。短剣を両手に持つ
	swift = _build_enemy_kind("swift", _spawn("swift", Vector3(6, 0.1, -1)))
	enemies.append(swift)
	# 魔法使い（E-14）：離れた所から魔法の弾を撃つ。攻撃の出始め（パリィ受付）で弾を跳ね返せる
	caster = _build_enemy_kind("caster", _spawn("caster", Vector3(-1, 0.1, -9)))
	enemies.append(caster)
	boss = _build_enemy("ボス", _spawn("boss", Vector3(4, 0.1, -8)), Vector3(1.6, 2.8, 1.6), {
		"aggro_range": 8.0, "max_hp": 300, "max_posture": 120.0, "move_speed": 2.4, "attack_range": 3.2,
		"telegraph_frames": 40, "glint_frames": 10, "combo_hits": 3, "combo_gap_frames": 18,
		"unparryable_every": 3, "damage": 20, "recover_frames": 45,
		"body_color": Color(0.55, 0.25, 0.7),
		# 第2形態（E-11）：HP50%以下で、速く・4連撃・フェイントあり
		"phase2_hp_ratio": 0.5, "phase2_speed_mult": 1.4, "phase2_telegraph_frames": 30,
		"phase2_combo_gap_frames": 14, "phase2_combo_hits": 4,
		"phase2_feint_every": 3, "phase2_feint_offset": 1,
		"phase2_body_color": Color(0.85, 0.2, 0.45),
		# 見た目（P-16）：女性の素体モデル。素材の色のまま、連撃は2種類の斬りを交互に
		"model_path": BOSS_MODEL, "head_path": BOSS_HEAD, "outfit_texture": BOSS_OUTFIT_TEXTURE,
		"recolor_model": false,
		"sword_path": "res://models/weapons/Claymore.fbx",
		"flower_model": "Petal_5", "flower_size": 0.9, "flower_layers": 2,  # 頭の花：2枚重ね。第2形態で肩・背中にも咲く  # 赤い大剣（ボスは1.6倍に拡大しているので、剣も大きくなる）
		"attack_anims": [
			{"clip": "ual2/Sword_Regular_A", "from": 0.05, "key": 0.21, "to": 0.43},
			{"clip": "ual2/Sword_Regular_B", "from": 0.05, "key": 0.22, "to": 0.53},
		],
	})
	enemies.append(boss)
	if use_world:
		build_side_enemies(_side_spots)
	if boss_door != null:
		boss_door.guards = [heavy, swift, caster]  # 広場の苗人を全部倒すと、ホールの扉が開く
	bgm = Bgm.new()
	bgm.name = "Bgm"
	bgm.boss = boss  # 第2形態になったらボスの曲へ
	bgm.enemies = enemies  # 敵に気づかれたら戦闘の曲へ（A-01）
	add_child(bgm)
	bgm.start()
	# 環境音（A-02）：白砂市のエリアのときだけ
	if use_world:
		ambience = Ambience.new()
		ambience.name = "Ambience"
		ambience.player = player
		add_child(ambience)
		ambience.start()
	_build_camera()
	_build_hud()
	if vista_director != null:
		vista_director.hud_layer = _hud_layer
	_build_slow_effect()
	_build_result_screen()
	_build_pause_menu()
	_build_title_screen()

	# テスト用：コマンドラインの -- の後ろに書いた名前のテストを1つ動かす
	for flag in TEST_SCRIPTS.keys():
		if flag in OS.get_cmdline_user_args():
			var t: Node = load(TEST_SCRIPTS[flag]).new()
			t.name = "Test"
			add_child(t)
			break


func _process(_delta: float) -> void:
	# 調整用の文字（U-01）：ふだんは隠す。F3 ／ パッドの SHARE で出し入れ（U-10。設定にも保存）
	if Input.is_action_just_pressed("debug_hud"):
		GameSettings.set_flag("debug_hud", not GameSettings.debug_hud)
	_hud.visible = GameSettings.debug_hud
	if _hud.visible:
		_update_hud()


# ゲームを終える。鳴っている音を止めて、オーディオが片付くのを少し待ってから終了する
# （すぐ終了すると、鳴っていた音が「使用中のまま残った」という警告が出るため）
func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	get_tree().paused = true  # 待っている間にゲームが進んで、新しい音が鳴らないように止める
	sfx.stop_all()
	bgm.stop_all()
	if ambience != null:
		ambience.stop_all()
	var test := get_node_or_null("Test")  # 自動テストも止める（結果を2回出さないように）
	if test != null:
		test.set_physics_process(false)
	var until := Time.get_ticks_msec() + QUIT_WAIT_MSEC
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	get_tree().quit()


# ウィンドウの×ボタンで閉じるときも quit_game() を通す
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


# =========================================================
# 勝ち負けの判定（U-03）。フレームで数える
# =========================================================
func _physics_process(_delta: float) -> void:
	if not side_enemies.is_empty():
		_update_side_enemy_sleep()
	if not _result_decided:
		# 同じフレームに両方起きたら、ボス撃破（勝利）を優先する
		if boss.is_dead():
			_decide_result(true)
		elif player.is_dead():
			_decide_result(false)
		return
	if _result_wait > 0:
		_result_wait -= 1
		if _result_wait == 0:
			result_screen.show_result(_result_victory)
			get_tree().paused = true  # ゲームを止める（結果画面だけは動く）


func _decide_result(victory: bool) -> void:
	_result_decided = true
	_result_victory = victory
	_result_wait = RESULT_DELAY_FRAMES
	bgm.fade_out()
	_on_log("==== %s ====" % ("勝利" if victory else "敗北"))


func _build_slow_effect() -> void:
	slow_effect = SlowEffect.new()
	slow_effect.name = "SlowEffect"
	slow_effect.environment = _environment
	add_child(slow_effect)


# タイトル画面（U-06）：起動したときだけ出す。リトライの後と、自動テスト（タイトルのテスト以外）では出さない
func _build_title_screen() -> void:
	title_screen = TitleScreen.new()
	title_screen.name = "TitleScreen"
	title_screen.start_requested.connect(_start_with_difficulty)
	title_screen.continue_requested.connect(_continue_game)
	title_screen.graphics_toggled.connect(toggle_graphics)
	title_screen.quit_requested.connect(quit_game)
	# タイトル画面の間は、調整用の文字やバーを隠し、景色用のカメラに切り替える
	# （タイトル中はゲームが止まり _process が動かないので、表示が変わったときに切り替える）
	var game_cam := get_viewport().get_camera_3d()
	var title_cam := Camera3D.new()
	title_cam.name = "TitleCamera"
	title_cam.fov = TITLE_CAMERA_FOV
	add_child(title_cam)
	if use_world:
		title_cam.look_at_from_position(WorldBuilder.TITLE_CAMERA_POS, WorldBuilder.TITLE_CAMERA_LOOK_AT)
	else:
		title_cam.look_at_from_position(TITLE_CAMERA_POS, TITLE_CAMERA_LOOK_AT)
	title_screen.visibility_changed.connect(func() -> void:
		_hud_layer.visible = not title_screen.visible
		if title_screen.visible:
			title_cam.make_current()
		elif game_cam != null:
			game_cam.make_current())
	add_child(title_screen)
	var skip: bool = Engine.get_meta(SKIP_TITLE_KEY, false)
	Engine.set_meta(SKIP_TITLE_KEY, false)
	var args := OS.get_cmdline_user_args()
	var other_test := TEST_SCRIPTS.keys().any(func(f): return f != TITLE_TEST_FLAG and f in args)
	if not skip and not other_test:
		title_screen.open()


# タイトルで難易度を選んだ（U-07）：プレイヤーと敵に難易度を当てはめてから始める
# （リトライのときは前の難易度のまま。Difficulty.current は読み直しても残る）
func _start_with_difficulty(difficulty: String) -> void:
	Difficulty.current = difficulty
	player.apply_difficulty()
	for e in enemies:
		e.apply_difficulty()
	_on_log("難易度：" + Difficulty.label())
	title_screen.close()


func _build_pause_menu() -> void:
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.can_open = can_pause
	pause_menu.resume_requested.connect(pause_menu.close)
	pause_menu.retry_requested.connect(_retry)
	pause_menu.quit_requested.connect(quit_game)
	pause_menu.graphics_toggled.connect(toggle_graphics)
	pause_menu.save_requested.connect(_save_from_menu)
	pause_menu.save_available = use_world  # セーブ・地図は街（エリア）のときだけ
	pause_menu.city_map.world_root = get_node_or_null("World")
	pause_menu.city_map.player = player
	add_child(pause_menu)


# テスト用：ザコとボスだけで試すテストのために、それ以外の敵（重装兵・双剣士・魔法使い）を片付ける
func remove_extra_enemies() -> void:
	for e in [heavy, swift, caster]:
		if e != null and is_instance_valid(e):
			enemies.erase(e)
			e.remove_from_group("enemies")
			e.queue_free()


# 画質を切り替える（U-09。ポーズメニューの「画質」ボタン）
func toggle_graphics() -> void:
	GraphicsSettings.toggle()
	GraphicsSettings.apply(_environment, get_viewport(), _sun, Palette.FOG_DENSITY)


# ポーズしてよいか：勝ち負けが決まった後や、終了の途中はポーズしない
# 武器の輪を開く（G-02）。開いている間は、プレイヤーは動かない
func _open_weapon_wheel(hold_mode: bool) -> void:
	if weapon_wheel == null or weapon_wheel.is_open or player.is_dead():
		return
	weapon_wheel.open(player.weapons.current, hold_mode)


func can_pause() -> bool:
	if weapon_wheel != null and weapon_wheel.is_open:
		return false
	return not _result_decided and not _quitting and not title_screen.is_open and not (vista_director != null and vista_director.active)


func _build_result_screen() -> void:
	result_screen = ResultScreen.new()
	result_screen.name = "ResultScreen"
	result_screen.retry_requested.connect(_retry)
	add_child(result_screen)


# 最後に保存した場所から始める（セーブ S-01。つづきから・リトライ）
func apply_saved_position() -> void:
	if not Discoveries.has_position:
		return
	# 起伏（T-01）を入れる前のセーブで、地面の中になっていたら、地面の上に置き直す
	var sp := Discoveries.saved_position
	sp.y = maxf(sp.y, WorldBuilder.ground_y(sp.x, sp.z) + 0.1)
	Discoveries.saved_position = sp
	player.global_position = Discoveries.saved_position
	player.safe_position = Discoveries.saved_position
	player.reset_physics_interpolation()


# タイトルの「つづきから」：セーブを読み込んで、シーンを作り直す（拾った物・倒した敵を消した街になる）
func _continue_game() -> void:
	if Discoveries.load_game():
		_retry()


# ポーズメニューの「セーブ」
func _save_from_menu() -> void:
	pause_menu.show_saved(Discoveries.save_game())


func _retry() -> void:
	Engine.set_meta(SKIP_TITLE_KEY, true)  # 読み直した後はタイトルを出さず、すぐ戦う
	sfx.stop_all()
	bgm.stop_all()
	if ambience != null:
		ambience.stop_all()
	get_tree().paused = false
	GameFeel.reset()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()  # シーンを最初から作り直す


# =========================================================
# 入力（Project Settings > Input Map でも同じことができる）
#
# ★ボタンの割り当てを変えるときは、この関数の中だけを書き換えればよい。
#   Godot のパッドのボタン名は Xbox 配置。PlayStation のボタンとの対応は：
#     JOY_BUTTON_Y = △   JOY_BUTTON_X = □   JOY_BUTTON_A = ×   JOY_BUTTON_B = ○
#     JOY_BUTTON_LEFT_SHOULDER = L1   JOY_BUTTON_RIGHT_SHOULDER = R1
#     L2 / R2 はボタンではなく「軸」：_axis(JOY_AXIS_TRIGGER_LEFT / RIGHT, 1.0)
#   パリィ専用のボタンは無い。攻撃ボタン（△／□）の出始めがパリィになる（player.gd）
# =========================================================
func _setup_input_map() -> void:
	_add_action("move_forward", [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])   # 左スティック
	_add_action("move_back", [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add_action("move_left", [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add_action("move_right", [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add_action("cam_left", [_key(KEY_LEFT), _axis(JOY_AXIS_RIGHT_X, -1.0)])   # 右スティック
	_add_action("cam_right", [_key(KEY_RIGHT), _axis(JOY_AXIS_RIGHT_X, 1.0)])
	_add_action("cam_up", [_key(KEY_UP), _axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_add_action("cam_down", [_key(KEY_DOWN), _axis(JOY_AXIS_RIGHT_Y, 1.0)])
	_add_action("attack_light", [_mouse(MOUSE_BUTTON_LEFT), _key(KEY_J), _joy(JOY_BUTTON_Y)])  # △
	_add_action("attack_heavy", [_mouse(MOUSE_BUTTON_RIGHT), _key(KEY_K), _joy(JOY_BUTTON_X)])  # □
	_add_action("dodge", [_key(KEY_SHIFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])  # R2（押し続けると走る）
	_add_action("jump", [_key(KEY_SPACE), _joy(JOY_BUTTON_A)])  # ×（2回まで。2回跳んだ後に押し続けると滑空）
	_add_action("lock_on", [_key(KEY_TAB), _mouse(MOUSE_BUTTON_MIDDLE), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])  # L2
	_add_action("retry", [_key(KEY_R), _joy(JOY_BUTTON_A)])  # 結果画面でのリトライ：R ／ ×
	_add_action("pause", [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)])  # ポーズ：Esc ／ OPTIONS
	_add_action("debug_hud", [_key(KEY_F3), _joy(JOY_BUTTON_BACK)])  # 調整用の文字を出し入れ：F3 ／ SHARE（U-10）
	_add_action("use_item", [_key(KEY_Q), _joy(JOY_BUTTON_DPAD_UP)])  # 回復薬を使う：Q ／ 十字キー上（W-15）
	# 武器（G-01・G-02）：F＝剣、1＝AR、2＝SMG、3＝SG。パッドは武器の輪（R3。銃のときは△長押しでも）
	_add_action("weapon_sword", [_key(KEY_F)])
	_add_action("weapon_ar", [_key(KEY_1)])
	_add_action("weapon_smg", [_key(KEY_2)])
	_add_action("weapon_sg", [_key(KEY_3)])
	_add_action("weapon_wheel", [_joy(JOY_BUTTON_RIGHT_STICK)])  # R3
	_add_action("wheel_hold", [_joy(JOY_BUTTON_Y)])  # △（銃のときの長押しだけに使う）
	# 銃（G-03）：撃つ＝左クリック／R1、構える＝右クリック／L1、リロード＝R／○（剣のときは何もしない）
	_add_action("fire", [_mouse(MOUSE_BUTTON_LEFT), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("aim", [_mouse(MOUSE_BUTTON_RIGHT), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_add_action("reload", [_key(KEY_R), _joy(JOY_BUTTON_B)])


func _add_action(action_name: String, events: Array) -> void:
	if InputMap.has_action(action_name):
		return  # リトライでシーンを読み直したときに、同じ割り当てを二重に足さない
	InputMap.add_action(action_name, 0.25)
	for ev in events:
		InputMap.action_add_event(action_name, ev)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e


# =========================================================
# ステージ
# =========================================================
func _build_world() -> void:
	# 空・光・霧（W-07）。色の数値は scripts/world/palette.gd
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	# 空：写真の空（Poly Haven の CC0 の HDRI。W-09）。空の光が、建物の日かげや映り込みにも使われる
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load(Palette.SKY_HDRI)
	sky_mat.energy_multiplier = Palette.SKY_ENERGY
	var sky := Sky.new()
	sky.sky_material = sky_mat
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = Palette.AMBIENT_ENERGY
	environment.ambient_light_sky_contribution = Palette.AMBIENT_SKY_CONTRIBUTION
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# 色調補正：少し鮮やかに、メリハリを付ける（スロー演出はここから色を変える）
	environment.adjustment_enabled = true
	environment.adjustment_saturation = Palette.SATURATION
	environment.adjustment_contrast = Palette.CONTRAST
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX  # 写真のような色の出方（明るい所が白く飛びにくい）
	environment.tonemap_exposure = Palette.EXPOSURE
	# 遠くが少しかすむ普通の霧（ボリュームフォグは使わない）
	environment.fog_enabled = true
	environment.fog_light_color = Palette.FOG
	environment.fog_density = Palette.FOG_DENSITY
	environment.fog_sky_affect = 0.25
	# 内蔵GPU向け：重い効果（SSAO/SSIL/SSR/SDFGI/ボリュームフォグ/グロー）は使わない
	env.environment = environment
	_environment = environment  # スロー演出（F-04）で色を変えるために覚えておく
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Palette.SUN_ROTATION_DEG
	sun.light_color = Palette.SUN
	sun.light_energy = Palette.SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # 分割なし＝最も軽い
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	_sun = sun
	# 画質（U-09）：高画質／軽い。ポーズメニューで切り替えられる
	GraphicsSettings.load_saved()
	GraphicsSettings.apply(environment, get_viewport(), sun, Palette.FOG_DENSITY)

	if use_world:
		var w := WorldBuilder.build(self)  # 白砂市のエリア（scripts/world/world_builder.gd）
		boss_door = w["door"]
		world_decor = w["decor"]
		_side_spots = w["side_enemies"]
		vista_director = VistaDirector.new()
		vista_director.name = "VistaDirector"
		add_child(vista_director)
		boss_door.opened.connect(func() -> void: _on_log("根がほどけ、ホールの扉が開いた"))
		return

	# 床（20m四方の部屋）と壁（自動テスト用）
	_add_static_box(Vector3(0, -0.5, 0), Vector3(20, 1, 20), Color(0.45, 0.47, 0.5))
	_add_static_box(Vector3(0, 1.5, -10), Vector3(20, 3, 0.5), Color(0.35, 0.37, 0.42))
	_add_static_box(Vector3(0, 1.5, 10), Vector3(20, 3, 0.5), Color(0.35, 0.37, 0.42))
	_add_static_box(Vector3(-10, 1.5, 0), Vector3(0.5, 3, 20), Color(0.35, 0.37, 0.42))
	_add_static_box(Vector3(10, 1.5, 0), Vector3(0.5, 3, 20), Color(0.35, 0.37, 0.42))


# 出てくる場所：エリアのときは WorldBuilder の表、部屋（テスト）のときは test_pos
func _spawn(key: String, test_pos: Vector3) -> Vector3:
	return WorldBuilder.on_ground(WorldBuilder.SPAWNS[key]) if use_world else test_pos  # 起伏（T-01）の上なら地面の高さに


func _add_static_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 0
	body.set_collision_layer_value(1, true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_child(_make_box_mesh(size, Vector3.ZERO, color, "Mesh"))
	add_child(body)


func _make_box_mesh(size: Vector3, offset: Vector3, color: Color, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = offset
	var mat := ShaderMaterial.new()
	mat.shader = TOON
	mat.set_shader_parameter("albedo", color)
	mi.material_override = mat
	return mi


func _make_area(node_name: String, script: Script, size: Vector3, offset: Vector3) -> Area3D:
	var area: Area3D = Area3D.new()
	area.set_script(script)
	area.name = node_name
	area.position = offset
	area.collision_layer = 0
	area.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	return area


# =========================================================
# プレイヤー・敵
# =========================================================
func _build_player(pos: Vector3) -> Player:
	var p := CharacterBody3D.new()
	p.set_script(load("res://scripts/player/player.gd"))
	p.name = "Player"
	p.position = pos
	p.collision_layer = 0
	p.collision_mask = 0
	p.set_collision_layer_value(2, true)
	p.set_collision_mask_value(1, true)
	p.set_collision_mask_value(3, true)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	p.add_child(col)

	# 見た目：Quaternius のキャラクター（P-16）。アニメーションは player.gd が毎tick指定する
	var model := CharacterModel.new()
	model.name = "Model"
	p.add_child(model)
	model.setup(PLAYER_MODEL, 0.0, PLAYER_HEAD)
	model.attach_sword(PLAYER_SWORD, PLAYER_SWORD_LENGTH)

	var hurt := _make_area("Hurtbox", load("res://scripts/combat/hurtbox.gd"), Vector3(0.8, 1.8, 0.8), Vector3(0, 0.9, 0))
	hurt.set_collision_layer_value(4, true)
	p.add_child(hurt)
	var hit := _make_area("Hitbox", load("res://scripts/combat/hitbox.gd"), Vector3(1.6, 1.2, 1.4), Vector3(0, 0.9, -1.1))
	hit.set_collision_mask_value(5, true)
	p.add_child(hit)

	add_child(p)
	var pl := p as Player
	pl.event_logged.connect(_on_log)
	return pl


func _build_enemy_kind(kind: String, pos: Vector3, extra: Dictionary = {}) -> Enemy:
	var k: Array = ENEMY_KINDS[kind]
	var params: Dictionary = (k[2] as Dictionary).duplicate()
	params.merge(extra, true)
	return _build_enemy(k[0], pos, k[1], params)


# 寄り道の敵（W-15 ④-3）：街に置く。一度倒した敵（Discoveries.killed）は作らない。作った数を返す
func build_side_enemies(spots: Array) -> int:
	var made := 0
	for i in spots.size():
		if Discoveries.killed.has(i):
			continue
		var sp: Array = spots[i]
		var e := _build_enemy_kind(sp[1], sp[0], {"side_id": i, "aggro_range": SIDE_AGGRO_RANGE})
		e.apply_difficulty()
		enemies.append(e)
		side_enemies.append(e)
		made += 1
	return made


# 遠くの寄り道の敵は止めておく（軽くするため）。SIDE_CHECK_FRAMES ごとに確かめる
func _update_side_enemy_sleep() -> void:
	_side_check_left -= 1
	if _side_check_left > 0:
		return
	_side_check_left = SIDE_CHECK_FRAMES
	for e in side_enemies:
		if not is_instance_valid(e):
			continue
		var far := e.global_position.distance_to(player.global_position) > SIDE_SLEEP_DISTANCE
		e.process_mode = Node.PROCESS_MODE_DISABLED if far else Node.PROCESS_MODE_INHERIT


func _build_enemy(display: String, pos: Vector3, size: Vector3, params: Dictionary) -> Enemy:
	var e := CharacterBody3D.new()
	e.set_script(load("res://scripts/enemy/enemy.gd"))
	e.name = display
	e.position = pos
	e.set("display_name", display)
	e.set("bar_height", size.y + 0.35)  # 頭の上の体力バー（U-08）の高さ
	for key in params.keys():
		if not key in VISUAL_PARAMS:
			e.set(key, params[key])
	e.collision_layer = 0
	e.collision_mask = 0
	e.set_collision_layer_value(3, true)
	e.set_collision_mask_value(1, true)
	e.set_collision_mask_value(2, true)
	e.set_collision_mask_value(3, true)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position = Vector3(0, size.y * 0.5, 0)
	e.add_child(col)

	# 見た目：モデルを当たり判定の箱と同じ高さにする（P-16）。アニメは enemy.gd が毎tick指定する
	var model := CharacterModel.new()
	model.name = "Model"
	e.add_child(model)
	model.setup(params["model_path"], size.y, params.get("head_path", ""))
	if params.has("outfit_texture"):
		model.replace_texture("T_Ranger_BaseColor", params["outfit_texture"])
	var model_len: float = params.get("sword_model_length", CharacterModel.SWORD_MODEL_LENGTH)
	if params.has("sword_path"):  # 魔法使いは武器を持たない
		model.attach_sword(params["sword_path"], params.get("sword_length", ENEMY_SWORD_LENGTH), model_len)
	if params.has("left_sword_path"):  # 双剣：左手にも持たせる
		model.attach_sword(params["left_sword_path"], params.get("sword_length", ENEMY_SWORD_LENGTH), model_len, "hand_l")

	var hurt := _make_area("Hurtbox", load("res://scripts/combat/hurtbox.gd"), size, Vector3(0, size.y * 0.5, 0))
	hurt.set_collision_layer_value(5, true)
	e.add_child(hurt)
	var reach: float = params.get("attack_range", 2.2)
	var hit := _make_area("Hitbox", load("res://scripts/combat/hitbox.gd"),
		Vector3(size.x + 1.0, 1.4, reach), Vector3(0, 1.0, -size.z * 0.5 - reach * 0.5 + 0.2))
	hit.set_collision_mask_value(4, true)
	e.add_child(hit)

	add_child(e)
	var en := e as Enemy
	en.event_logged.connect(_on_log)
	return en


func _build_camera() -> void:
	var rig := Node3D.new()
	rig.set_script(load("res://scripts/camera/camera_rig.gd"))
	rig.name = "CameraRig"
	rig.set("target", player)
	var spring := SpringArm3D.new()
	spring.name = "SpringArm3D"
	spring.spring_length = 4.5
	spring.collision_mask = 1  # 地形だけに当たってカメラが壁にめり込まない
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	spring.shape = sphere
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 70.0
	spring.add_child(cam)
	rig.add_child(spring)
	add_child(rig)
	cam.make_current()


# =========================================================
# 調整用HUD（数値が見えると調整が早い）
# =========================================================
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud_layer = layer
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud)

	# HPバー・体幹バー（中身は scripts/ui/battle_hud.gd）
	battle_hud = BattleHud.new()
	battle_hud.name = "BattleHud"
	battle_hud.player = player
	layer.add_child(battle_hud)
	# 敵の頭の上の体力バー（U-08）
	enemy_bars = EnemyBars.new()
	enemy_bars.name = "EnemyBars"
	layer.add_child(enemy_bars)
	# 武器の輪（G-02）
	weapon_wheel = WeaponWheel.new()
	weapon_wheel.name = "WeaponWheel"
	weapon_wheel.chosen.connect(func(id: String) -> void:
		if player.weapons.request(id):
			_on_log("持ち替え：" + str(Weapons.LABELS[id])))
	layer.add_child(weapon_wheel)
	# 操作のヒント（U-11）：エリアのときだけ
	if use_world:
		hint_box = HintBox.new()
		hint_box.name = "HintBox"
		layer.add_child(hint_box)
		var hd := HintDirector.new()
		hd.name = "HintDirector"
		hd.main = self
		hd.box = hint_box
		add_child(hd)
	# 見つけたときのお知らせ（W-15）
	var toast := DiscoveryToast.new()
	toast.name = "DiscoveryToast"
	layer.add_child(toast)
	add_child(layer)


func _update_hud() -> void:
	var s := "FPS %d   難易度 %s   %s\n" % [Engine.get_frames_per_second(), Difficulty.label(), "【スロー中】" if GameFeel.is_witch_time() else ""]
	s += "プレイヤー HP %d / %d   状態 %s\n" % [player.hp, player.max_hp, player.state_name()]
	for e in enemies:
		if e.side_id >= 0:
			continue  # 寄り道の敵は多いので、調整用の表示には出さない
		s += "%s HP %d / %d   体幹 %d / %d   状態 %s\n" % [
			e.display_name, e.hp, e.max_hp, int(e.posture), int(e.max_posture), e.state_name()]
	s += "\n[WASD/左スティック]移動 [マウス/右スティック]カメラ [左クリック/J/△]通常攻撃 [右クリック/K/□]強攻撃（長押しで溜め）\n"
	s += "[Space/×]ジャンプ（2回・押し続けて滑空） [Shift/R2]回避（押し続けて走る） [Tab/L2]ロックオン [Esc/OPTIONS]ポーズ\n"
	s += "白く光ったら攻撃でパリィ／赤く光ったら回避\n\n"
	s += "\n".join(_log_lines)
	_hud.text = s


func _on_log(text: String) -> void:
	_log_lines.append(text)
	if _log_lines.size() > 8:
		_log_lines.pop_front()
	if "--autotest" in OS.get_cmdline_user_args():
		print("[f%d] %s" % [Engine.get_physics_frames(), text])
