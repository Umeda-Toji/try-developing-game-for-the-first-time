# Godot 4.7.2 / GDScript
# res://scripts/player/player.gd
#
# プレイヤー：状態遷移（ステートマシン）＋フレーム管理＋先行入力
#
#  ・すべてのタイミングは「物理フレーム数」（60tick/秒）で数える
#  ・state_frame は状態に入った最初のtickが 0
#  ・攻撃は「発生(startup) → 持続(active) → 硬直(recovery)」の3段階
#    cancel フレーム以降は次の攻撃・回避で硬直をキャンセルできる
#  ・パリィ専用のボタンは無い（NieR:Automata／NTE 風）。
#    コンボの1段目（移動中や回避の後に出した攻撃）の出始め parry_window_frames（難易度で変わる）の間に
#    敵の攻撃が当たるとパリィ成功。失敗しても普通の攻撃が出るだけ。
#    コンボの2段目以降は対象外（連打しているだけで常にパリィになるのを防ぐ）
#  ・入力は INPUT_BUFFER_FRAMES だけ覚えておく（先行入力）
#  ・強攻撃の溜め（P-15）：H1 の発生前に CHARGE_START_FRAMES まで□を押し続けていたら溜め（CHARGE）に入る。
#    離すと、溜めた長さに応じて強くなった H1 の続きが出る。すぐ離せば普通の H1。
#    パリィの受付は□を押した瞬間から（溜め中は受付なし）。溜め中は回避でキャンセルできる
#  ・ソフトロック（P-17）：ロックオンしていないとき、攻撃の瞬間に近くの敵の方を向く
#  ・移動（M-01〜M-04。操作は NieR:Automata にならう）：
#      ジャンプ（×／Space）は2回まで。2回跳んだ後に、もう一度ジャンプを押して押し続けると滑空（綿の外套）
#      回避（R2／Shift）の後に、回避ボタンを押し続けると走る
#      スタミナ：回避で減り、走る・滑空の間は少しずつ減る。使わずにいると回復する。0 だと回避・走る・滑空ができない
#      （ジャンプはスタミナを使わない。11/18 変更）
#  ・壁のぼり（M-05）：空中（ジャンプ中・落下中・泳いでいるとき）に壁へ向かって進むと壁につかまる。
#    前後で上下、左右で横に動く。上まで行くと登りきる。ジャンプで壁を蹴って離れる、回避で手を離す。スタミナを使う
#    （group "no_climb" の面＝見えない壁・ホールの壁などは登れない）
#  ・泳ぎ（M-06）：深い水（group "water"）に入ると泳ぐ。進むとスタミナを使い、切れると溺れて、最後に立っていた所へ戻る（ダメージ）
#    泳いでいる間は攻撃・回避できない。岸の壁へ向かって進むと、壁につかまって上がれる
#  ・落下：kill_y より下に落ちたら、最後に立っていた所へ戻る（ダメージ）
class_name Player
extends CharacterBody3D

signal hp_changed(current: int, max_value: int)
signal event_logged(text: String)

enum State { MOVE, ATTACK, DODGE, HITSTUN, DEAD, CHARGE, CLIMB, SWIM }

const MOVE_SPEED := 6.0
const DODGE_SPEED := 13.0
const GRAVITY := 25.0
const MAX_HP := 100

# ---- ここから下はすべて「フレーム数（1/60秒）」----
const INPUT_BUFFER_FRAMES := 8     # 先行入力を覚えておく長さ（約0.13秒）
const DODGE_TOTAL_FRAMES := 22     # 回避の全体
const DODGE_INVULN_FRAMES := 14    # 回避の無敵
const PERFECT_DODGE_FRAMES := 12   # 回避開始からこの間に敵の攻撃が来たらジャスト回避（「ふつう」の値。難易度で変わる → perfect_dodge_frames）
const DODGE_CANCEL_FRAME := 14     # 回避の後半は攻撃でキャンセル可
const PARRY_WINDOW_FRAMES := 9     # 攻撃の出始めのパリィ受付（約0.15秒）（「ふつう」の値。難易度で変わる → parry_window_frames）
const HITSTUN_FRAMES := 18
const COUNTER_WINDOW_FRAMES := 45  # パリィ成功後、反撃が強くなる時間
const WITCH_TIME_FRAMES := 120     # ジャスト回避後のスロー時間
const WITCH_TIME_SCALE := 0.25
const CHARGE_START_FRAMES := 12    # □をこれだけ押し続けたら溜めに入る（H1 の発生 14 より小さくすること）
const CHARGE_MAX_FRAMES := 60      # 溜めに入ってから最大まで溜まるまで（約1秒）
const CHARGE_MAX_MULTIPLIER := 2.0 # 最大まで溜めたときのダメージ・体幹ダメージの倍率

# ソフトロック（P-17）：ロックオンしていなくても、攻撃の瞬間に近くの敵を向く
const SOFT_LOCK_RANGE := 5.0             # この距離（m）以内の敵だけ
const PARRY_SPARK_HEIGHT := 1.2          # パリィの火花を出す高さ（m）
const SOFT_LOCK_HALF_ANGLE_DEG := 90.0   # 基準の方向から左右この角度以内の敵だけ（後ろの敵には振り向かない）

# ---- 移動（M-01〜M-04）。速さは m/秒、スタミナの量は「1フレームあたり」か「1回あたり」----
const JUMP_VELOCITY := 8.5           # 1回目のジャンプ（約1.4m 跳べる）
const AIR_JUMP_VELOCITY := 7.5       # 2回目のジャンプ（空中）
const MAX_JUMPS := 2
const SPRINT_SPEED := 9.5            # 走る速さ（歩きは MOVE_SPEED 6.0）
const GLIDE_SPEED := 7.0             # 滑空中の前へ進む速さ
const GLIDE_FALL_SPEED := 1.8        # 滑空中の落ちる速さ（これより速くは落ちない）
const STAMINA_MAX := 100.0
# アイテム（W-15 ④-2）
const HEAL_AMOUNT := 40              # 回復薬1つで戻るHP
const UPGRADE_HP := 10               # 「最大HP+10」1つで増える最大HP
const UPGRADE_STAMINA := 10.0        # 「最大スタミナ+10」1つで増える最大スタミナ
const UPGRADE_ATTACK := 0.05         # 「攻撃力+5%」1つで増える攻撃の倍率
const STAMINA_COST_DODGE := 20.0     # 回避1回
const STAMINA_DRAIN_SPRINT := 0.35   # 走っている間、1フレームごと（約3.5秒で 0）
const STAMINA_DRAIN_GLIDE := 0.3     # 滑空している間、1フレームごと（約5.5秒で 0）
const STAMINA_REGEN := 0.8           # 回復、1フレームごと（約2秒で満タン）
const STAMINA_REGEN_DELAY_FRAMES := 40  # 最後に使ってから、これだけたつと回復が始まる

# ---- 壁のぼり（M-05）・泳ぎ（M-06）・落下 ----
const CLIMB_SPEED := 2.5             # 壁を動く速さ（m/秒）
const CLIMB_REACH := 0.8             # 体の中心から、この距離までの壁につかまれる（m）
const CLIMB_CHEST_HEIGHT := 1.3      # 壁を調べる高さ（胸・足元）
const CLIMB_FOOT_HEIGHT := 0.25
const CLIMB_MANTLE_UP := 8.5         # 上に着いたときに登りきる勢い（上へ）
const CLIMB_MANTLE_FORWARD := 4.0    # 〃（前へ）
const CLIMB_JUMP_AWAY := 5.0         # ジャンプで壁を蹴る勢い
const STAMINA_DRAIN_CLIMB := 0.4     # 壁を動いている間、1フレームごと
const STAMINA_DRAIN_CLIMB_IDLE := 0.1  # 壁につかまって止まっている間
const SWIM_SPEED := 3.0
const SWIM_DEPTH := 0.9              # 足元が水面からこれより深いと泳ぐ（m）
const SWIM_FLOAT_DEPTH := 1.2        # 泳いでいる間、足元を水面からこれだけ下に保つ（m）
const STAMINA_DRAIN_SWIM := 0.25     # 泳いで進んでいる間、1フレームごと
const STAMINA_DRAIN_SWIM_IDLE := 0.05  # 浮いているだけの間
const DROWN_DAMAGE := 20             # 溺れたときのダメージ
const FALL_DAMAGE := 10              # 落下して戻されたときのダメージ

# 溜めの見た目
const COLOR_CHARGE := Color(1.0, 0.55, 0.15)
const COLOR_CHARGE_FULL := Color(1.0, 0.95, 0.3)
const CHARGE_GLOW_ENERGY := 0.8

# 攻撃データ。数字をいじるだけで手触りを調整できるよう、表にしておく
const ATTACKS := {
	"L1": {"startup": 5, "active": 4, "recovery": 14, "cancel": 9,
		"next_light": "L2", "next_heavy": "H1",
		"damage": 8, "posture": 6, "hitstop": 3, "shake": 0.04, "lunge": 3.0},
	"L2": {"startup": 5, "active": 4, "recovery": 14, "cancel": 9,
		"next_light": "L3", "next_heavy": "H1",
		"damage": 8, "posture": 6, "hitstop": 3, "shake": 0.04, "lunge": 3.0},
	"L3": {"startup": 8, "active": 5, "recovery": 22, "cancel": 16,
		"next_light": "", "next_heavy": "H1",
		"damage": 14, "posture": 10, "hitstop": 5, "shake": 0.08, "lunge": 4.5},
	"H1": {"startup": 14, "active": 6, "recovery": 24, "cancel": 22,
		"next_light": "L1", "next_heavy": "",
		"damage": 22, "posture": 25, "hitstop": 7, "shake": 0.15, "lunge": 2.0},
}

# 見た目のアニメーション（P-16）。判定には使わない（判定は上の ATTACKS のフレーム数だけで決まる）
#  clip：使うアニメ、from／to：使う範囲（秒）
#  key：剣を一番速く振っている瞬間（秒）。攻撃の当たり始め（startup のフレーム）にこのポーズが来るように合わせる
#  （key の値は、右手の速さが一番大きくなる時刻を調べて決めた）
const ATTACK_ANIMS := {
	"L1": {"clip": "ual2/Sword_Regular_A", "from": 0.05, "key": 0.21, "to": 0.43},
	"L2": {"clip": "ual2/Sword_Regular_B", "from": 0.05, "key": 0.22, "to": 0.53},
	"L3": {"clip": "ual2/Sword_Regular_C", "from": 0.35, "key": 0.62, "to": 1.00},
	"H1": {"clip": "ual1/Sword_Attack", "from": 0.00, "key": 0.38, "to": 1.00},
}
const ANIM_IDLE := "ual1/Sword_Idle"
const ANIM_RUN := "ual1/Jog_Fwd"         # 素材では Jog_Fwd_Loop。Godot が読み込むときに "_Loop" を外す
const ANIM_SPRINT := "ual1/Sprint"        # 走る（M-03）
const ANIM_AIR := "ual1/Jump"             # 空中（ジャンプ中・落ちている間）
const ANIM_GLIDE := "ual2/NinjaJump_Idle"  # 滑空（外套で風に乗る）
const ANIM_CLIMB := "ual2/ClimbUp_1m"     # 壁のぼり（M-05）
const ANIM_SWIM := "ual1/Swim_Fwd"        # 泳ぐ（M-06）
const ANIM_SWIM_IDLE := "ual1/Swim_Idle"
const ANIM_RUN_SPEED := 1.3             # 走りアニメの再生の速さ（足が滑って見えないように）
const ANIM_DODGE := {"clip": "ual1/Roll", "from": 0.0, "to": 0.95}
const ANIM_HITSTUN := {"clip": "ual1/Hit_Chest", "from": 0.0, "to": 0.33}
const ANIM_DEATH := "ual1/Death01"      # 1tick に 1/60 秒ずつ進めて、最後のポーズで止める
# 状態の色（モデルの上に重ねる色と強さ）
const TINT_PARRY := Color(0.2, 1.0, 1.0)     # パリィ受付中：水色
const TINT_DODGE := Color(0.9, 0.9, 1.0)     # 回避の無敵中：白
const TINT_HITSTUN := Color(1.0, 0.3, 0.3)   # 被弾：赤
const TINT_COUNTER := Color(1.0, 1.0, 1.0)   # パリィ成功後の反撃チャンス：白く光る
const TINT_STRENGTH := 0.8

var state: State = State.MOVE
# 難易度（U-07）で変わる受付の長さ。apply_difficulty() で決まる
var parry_window_frames := PARRY_WINDOW_FRAMES
var perfect_dodge_frames := PERFECT_DODGE_FRAMES
var state_frame := 0
var hp := MAX_HP
var max_hp := MAX_HP           # 強化アイテムで増える（apply_upgrades）
var max_stamina := STAMINA_MAX
var attack_mult := 1.0
var hitstop_frames := 0
var lock_target: Node3D = null

var _attack_id := ""
var _attack_can_parry := false  # 今の攻撃の出始めでパリィできるか（コンボ1段目だけ true）
var _buffered_action := ""
var _buffer_age := 999
var _dodge_dir := Vector3.ZERO
var _perfect_dodge_done := false
var _counter_frames := 0
var _knockback := Vector3.ZERO
var _charge_mult := 1.0       # 今の攻撃にかかる溜めの倍率（溜めていなければ 1.0）
var _charge_done := false     # この攻撃ではもう溜めた（溜め終わった後にまた溜めに入らないため）
# 移動（M-01〜M-04）
var stamina := STAMINA_MAX
var jumps_used := 0            # 地面を離れてから跳んだ回数（着地で 0 に戻る）
var gliding := false
var sprinting := false
var _stamina_idle_frames := 0  # スタミナを使わずにいるフレーム数
var _stamina_used := false     # このフレームでスタミナを使ったか
var kill_y := -INF             # これより下に落ちたら戻す（main.gd が世界に合わせて決める）
var safe_position := Vector3.ZERO  # 最後に立っていた所（溺れた・落ちたときに戻る）
var _wall_normal := Vector3.BACK   # つかまっている壁の向き（壁から外向き）

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var model: CharacterModel = $Model


func _ready() -> void:
	add_to_group("player")
	safe_position = global_position
	hitbox.hit_landed.connect(_on_hitbox_hit)
	apply_upgrades()
	hp = max_hp
	stamina = max_stamina
	hp_changed.emit(hp, max_hp)
	apply_difficulty()
	_update_visual()  # 最初のポーズを決めておく（タイトル画面でゲームが止まっていても T字のポーズにならないように）


# 難易度（U-07）に合わせて、パリィ・ジャスト回避の受付を決める。何度呼んでも同じ結果になる
func apply_difficulty() -> void:
	parry_window_frames = Difficulty.value("parry_window_frames")
	perfect_dodge_frames = Difficulty.value("perfect_dodge_frames")


# =========================================================
# メインループ（1tick = 1フレーム）
# =========================================================
func _physics_process(delta: float) -> void:
	_buffer_inputs()
	if Input.is_action_just_pressed("lock_on"):
		_toggle_lock_on()
	if lock_target != null and (not is_instance_valid(lock_target) or lock_target.call("is_dead")):
		lock_target = null

	# ヒットストップ中は自分の時間を止める（入力だけは受け付けておく）
	if hitstop_frames > 0:
		hitstop_frames -= 1
		return

	_buffer_age += 1
	if _counter_frames > 0:
		_counter_frames -= 1
	state_frame += 1

	match state:
		State.MOVE:
			_state_move()
		State.ATTACK:
			_state_attack()
		State.DODGE:
			_state_dodge()
		State.HITSTUN:
			_state_hitstun()
		State.CHARGE:
			_state_charge()
		State.CLIMB:
			_state_climb()
		State.SWIM:
			_state_swim()
		State.DEAD:
			velocity.x = 0.0
			velocity.z = 0.0

	if not is_on_floor() and state != State.CLIMB and state != State.SWIM:
		velocity.y -= GRAVITY * delta
		if gliding:
			velocity.y = maxf(velocity.y, -GLIDE_FALL_SPEED)  # 外套で風に乗り、ゆっくり落ちる
	move_and_slide()
	if is_on_floor():
		jumps_used = 0
		gliding = false
		if state == State.MOVE and _water_surface() == -INF:
			safe_position = global_position
	if global_position.y < kill_y and state != State.DEAD:
		_respawn(FALL_DAMAGE, "落ちた")
	_update_stamina()
	_update_visual()


func _set_state(new_state: State) -> void:
	state = new_state
	state_frame = -1  # 次のtickの先頭で +1 されて 0 になる


# =========================================================
# 各状態
# =========================================================
func _state_move() -> void:
	var dir := _get_move_input()
	if _in_deep_water():
		_start_swim()
		return
	if not is_on_floor() and _try_start_climb(dir):
		return
	_update_jump_and_glide()
	# 走る：回避の後に回避ボタンを押し続けている間（動いていて、スタミナがある間）
	if sprinting and (not Input.is_action_pressed("dodge") or dir.length() < 0.1 or stamina <= 0.0 or not is_on_floor()):
		sprinting = false
	var speed := MOVE_SPEED
	if gliding:
		speed = GLIDE_SPEED
		if dir.length() < 0.1:
			dir = -global_transform.basis.z  # 入力がなくても前へ進む
		_use_stamina(STAMINA_DRAIN_GLIDE)
	elif sprinting:
		speed = SPRINT_SPEED
		_use_stamina(STAMINA_DRAIN_SPRINT)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if lock_target != null and not gliding and not sprinting:
		_face_toward(lock_target.global_position, 0.25)
	elif dir.length() > 0.1:
		_face_dir(dir, 0.25)

	if Input.is_action_just_pressed("use_item"):
		use_heal()
	match _take_buffered(["attack_light", "attack_heavy", "dodge"]):
		"attack_light":
			_start_attack("L1", true)
		"attack_heavy":
			_start_attack("H1", true)
		"dodge":
			_start_dodge(dir)


func _state_attack() -> void:
	var atk: Dictionary = ATTACKS[_attack_id]
	var startup: int = atk["startup"]
	var active: int = atk["active"]
	var total: int = startup + active + int(atk["recovery"])

	# 踏み込み：発生前だけ前へ進む
	var fwd := -global_transform.basis.z
	if state_frame < startup:
		velocity.x = fwd.x * float(atk["lunge"])
		velocity.z = fwd.z * float(atk["lunge"])
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1.0)
		velocity.z = move_toward(velocity.z, 0.0, 1.0)

	# 強攻撃の溜め：発生前に□を押し続けていたら溜めに入る
	var holding_heavy := Input.is_action_pressed("attack_heavy")
	if _attack_id == "H1" and not _charge_done and state_frame == CHARGE_START_FRAMES and holding_heavy:
		_start_charge()
		return

	# 判定の出し入れはフレームで決める
	if state_frame == startup:
		hitbox.activate(_make_payload(atk))
	elif state_frame == startup + active:
		hitbox.deactivate()

	# キャンセル受付
	if state_frame >= int(atk["cancel"]):
		var allowed: Array[String] = ["dodge"]
		if atk["next_light"] != "":
			allowed.append("attack_light")
		if atk["next_heavy"] != "":
			allowed.append("attack_heavy")
		match _take_buffered(allowed):
			"attack_light":
				_start_attack(atk["next_light"], false)
				return
			"attack_heavy":
				_start_attack(atk["next_heavy"], false)
				return
			"dodge":
				hitbox.deactivate()
				_start_dodge(_get_move_input())
				return

	if state_frame >= total:
		_set_state(State.MOVE)


func _state_dodge() -> void:
	var t := float(state_frame) / float(DODGE_TOTAL_FRAMES)
	var speed := lerpf(DODGE_SPEED, 1.5, t)
	velocity.x = _dodge_dir.x * speed
	velocity.z = _dodge_dir.z * speed

	if state_frame >= DODGE_CANCEL_FRAME:
		match _take_buffered(["attack_light", "attack_heavy"]):
			"attack_light":
				_start_attack("L1", true)
				return
			"attack_heavy":
				_start_attack("H1", true)
				return
	if state_frame >= DODGE_TOTAL_FRAMES:
		_set_state(State.MOVE)
		# 回避ボタンを押し続けていたら、そのまま走る（M-03）
		if Input.is_action_pressed("dodge") and stamina > 0.0 and is_on_floor():
			sprinting = true


func _state_charge() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if lock_target != null:
		_face_toward(lock_target.global_position, 0.25)
	# 回避で溜めをやめられる
	if _take_buffered(["dodge"]) == "dodge":
		_start_dodge(_get_move_input())
		return
	# □を離したら、溜めた長さに応じた倍率で H1 の続き（発生の残り）から出す
	if not Input.is_action_pressed("attack_heavy"):
		_release_charge()


func _state_hitstun() -> void:
	velocity.x = _knockback.x
	velocity.z = _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, 0.8)
	if state_frame >= HITSTUN_FRAMES:
		_set_state(State.MOVE)


# =========================================================
# 行動の開始
# =========================================================
# can_parry：コンボ1段目なら true（出始めがパリィ受付になる）
func _start_attack(id: String, can_parry: bool) -> void:
	_attack_id = id
	_attack_can_parry = can_parry
	_charge_mult = 1.0
	_charge_done = false
	_set_state(State.ATTACK)
	if lock_target != null:
		_face_toward(lock_target.global_position, 1.0)
	else:
		# ソフトロック（P-17）：近くの敵を自動で向く。基準はスティックの方向（倒していなければ正面）
		var d := _get_move_input()
		var ref := d if d.length() > 0.1 else -global_transform.basis.z
		var soft := find_soft_lock_target(ref)
		if soft != null:
			_face_toward(soft.global_position, 1.0)
		elif d.length() > 0.1:
			_face_dir(d, 1.0)
	_log("攻撃 " + id)


func _start_charge() -> void:
	_charge_done = true
	_set_state(State.CHARGE)
	_log("溜め開始")


func _release_charge() -> void:
	_charge_mult = charge_multiplier()
	_attack_can_parry = false
	state = State.ATTACK
	state_frame = CHARGE_START_FRAMES  # 次のtickで +1 され、溜めに入った直後のフレームから再開する
	_log("溜め攻撃 x%.2f" % _charge_mult)


# 今の溜め具合での倍率（溜め中でなければ 1.0）
func charge_multiplier() -> float:
	if state != State.CHARGE:
		return 1.0
	var ratio := clampf(float(state_frame) / float(CHARGE_MAX_FRAMES), 0.0, 1.0)
	return lerpf(1.0, CHARGE_MAX_MULTIPLIER, ratio)


func _start_dodge(dir: Vector3) -> void:
	if stamina <= 0.0:
		return  # スタミナが無いと回避できない
	_use_stamina(STAMINA_COST_DODGE)
	sprinting = false
	gliding = false
	if dir.length() < 0.1:
		dir = global_transform.basis.z  # 入力なしなら後ろへ（バックステップ）
	_dodge_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_perfect_dodge_done = false
	_set_state(State.DODGE)
	_log("回避")


# =========================================================
# 被弾の判定（敵の Hitbox から呼ばれる）
# =========================================================
func receive_attack(attack: Dictionary, attacker: Node) -> int:
	if state == State.DEAD:
		return Combat.HitResult.IGNORED

	# パリィ：コンボ1段目の攻撃の出始め（受付フレーム内） かつ パリィ可能な攻撃
	var unparryable: bool = attack.get("unparryable", false)
	if _is_parry_window() and not unparryable:
		_on_parry_success(attacker)
		return Combat.HitResult.PARRIED

	# 回避：序盤ならジャスト回避、無敵中なら回避成功
	if state == State.DODGE:
		if state_frame <= perfect_dodge_frames and not _perfect_dodge_done:
			_on_perfect_dodge()
			return Combat.HitResult.PERFECT_DODGED
		if state_frame <= DODGE_INVULN_FRAMES:
			return Combat.HitResult.DODGED

	_take_damage(attack, attacker)
	return Combat.HitResult.HIT


# 敵の攻撃判定が出た瞬間に、敵から「近くにいるよ」と通知される。
# 回避で判定の外へ逃げ切った場合でもジャスト回避を成立させるため。
func on_enemy_attack_active(_enemy: Node) -> void:
	if state == State.DODGE and state_frame <= perfect_dodge_frames and not _perfect_dodge_done:
		_on_perfect_dodge()


func _on_parry_success(attacker: Node) -> void:
	_log("★パリィ成功！")
	hitstop_frames = 6
	_counter_frames = COUNTER_WINDOW_FRAMES
	GameFeel.shake(0.12, 8)
	if attacker is Node3D:  # 火花はプレイヤーと敵の間、胸くらいの高さに出す
		var mid := global_position.lerp((attacker as Node3D).global_position, 0.5)
		GameFeel.spark(mid + Vector3.UP * PARRY_SPARK_HEIGHT, GameFeel.SPARK_PARRY)
	hitbox.deactivate()
	_set_state(State.MOVE)  # 攻撃を打ち切って、即座に反撃できる
	if attacker.has_method("on_parried"):
		attacker.on_parried(self)


func _on_perfect_dodge() -> void:
	_perfect_dodge_done = true
	_counter_frames = WITCH_TIME_FRAMES
	_log("★ジャスト回避！スロー発動")
	GameFeel.start_witch_time(WITCH_TIME_SCALE, WITCH_TIME_FRAMES)


func _take_damage(attack: Dictionary, attacker: Node) -> void:
	hp = max(hp - int(attack["damage"]), 0)
	hp_changed.emit(hp, max_hp)
	hitbox.deactivate()
	hitstop_frames = int(attack.get("hitstop", 4))
	GameFeel.shake(float(attack.get("shake", 0.1)), 8)
	_log("被弾 -%d" % int(attack["damage"]))
	if hp <= 0:
		_set_state(State.DEAD)
		_log("やられた…")
		return
	var away := global_position - (attacker as Node3D).global_position
	away.y = 0.0
	_knockback = away.normalized() * 6.0
	_set_state(State.HITSTUN)


# =========================================================
# 自分の攻撃が当たったとき
# =========================================================
func _on_hitbox_hit(target_hurtbox: Hurtbox) -> void:
	var target := target_hurtbox.entity
	if not target.has_method("receive_attack"):
		return
	var payload := hitbox.attack
	var result: int = target.receive_attack(payload, self)
	if result == Combat.HitResult.HIT:
		hitstop_frames = int(payload["hitstop"])  # 当てた側も止める＝重さが出る
		GameFeel.shake(float(payload["shake"]), 6)
		GameFeel.spark(hitbox.contact_point(target_hurtbox), GameFeel.SPARK_HIT)


func _make_payload(atk: Dictionary) -> Dictionary:
	var p := atk.duplicate()
	if _charge_mult > 1.0:  # 溜め攻撃は強化（反撃の強化とも重なる）
		p["damage"] = int(round(float(p["damage"]) * _charge_mult))
		p["posture"] = int(round(float(p["posture"]) * _charge_mult))
	if _counter_frames > 0:  # パリィ／ジャスト回避後の反撃は強化
		p["damage"] = int(p["damage"]) * 2
		p["posture"] = int(p["posture"]) * 2
		p["hitstop"] = int(p["hitstop"]) + 3
	if attack_mult != 1.0:  # 強化アイテム（攻撃力+5%）
		p["damage"] = int(round(float(p["damage"]) * attack_mult))
	return p


# =========================================================
# 入力・向き・ロックオン
# =========================================================
# =========================================================
# 壁のぼり（M-05）
# =========================================================
# dir の方向に登れる壁があれば、つかまる
func _try_start_climb(dir: Vector3) -> bool:
	if dir.length() < 0.1 or stamina <= 0.0:
		return false
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var hit := _wall_ray(CLIMB_CHEST_HEIGHT, flat)
	if hit.is_empty():
		return false
	var n: Vector3 = hit["normal"]
	if flat.dot(-n) < 0.6:
		return false  # 壁に向かっていない（かすっただけ）
	_wall_normal = Vector3(n.x, 0.0, n.z).normalized()
	rotation.y = atan2(_wall_normal.x, _wall_normal.z)  # 壁の方を向く（前＝ -Z ＝ 壁の内側）
	gliding = false
	sprinting = false
	velocity = Vector3.ZERO
	_set_state(State.CLIMB)
	_log("壁につかまった")
	return true


func _state_climb() -> void:
	var up := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var side := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var right := Vector3.UP.cross(_wall_normal).normalized()
	velocity = Vector3.UP * up * CLIMB_SPEED + right * side * CLIMB_SPEED - _wall_normal * 0.5
	var moving := absf(up) > 0.1 or absf(side) > 0.1
	_use_stamina(STAMINA_DRAIN_CLIMB if moving else STAMINA_DRAIN_CLIMB_IDLE)

	if Input.is_action_just_pressed("jump"):  # 壁を蹴って離れる
		velocity = _wall_normal * CLIMB_JUMP_AWAY + Vector3.UP * 5.0
		jumps_used = 1
		_set_state(State.MOVE)
		return
	if Input.is_action_just_pressed("dodge") or stamina <= 0.0:  # 手を離す（スタミナ切れでも落ちる）
		velocity = _wall_normal * 1.0
		_set_state(State.MOVE)
		return
	if is_on_floor() and up < 0.0:  # 下まで降りた
		_set_state(State.MOVE)
		return

	var chest := _wall_ray(CLIMB_CHEST_HEIGHT, -_wall_normal)
	if not chest.is_empty():
		var n: Vector3 = chest["normal"]
		_wall_normal = Vector3(n.x, 0.0, n.z).normalized()
		return
	# 胸の高さに壁が無い：足元にはまだ壁がある＝上に着いた → 登りきる
	var foot := _wall_ray(CLIMB_FOOT_HEIGHT, -_wall_normal)
	if not foot.is_empty() and up > 0.0:
		velocity = Vector3.UP * CLIMB_MANTLE_UP - _wall_normal * CLIMB_MANTLE_FORWARD
		jumps_used = MAX_JUMPS  # 登りきった直後は跳べない（落ちたら滑空はできる）
		_set_state(State.MOVE)
		_log("登りきった")
		return
	_set_state(State.MOVE)  # 壁が途切れた（横にはみ出した）


# 登れる壁を探す（見つからなければ空の辞書）。登れない面（no_climb）・床や天井は無視する
func _wall_ray(height: float, dir: Vector3) -> Dictionary:
	var from := global_position + Vector3.UP * height
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * CLIMB_REACH, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var c: Object = hit["collider"]
	if c is Node and (c as Node).is_in_group("no_climb"):
		return {}
	if absf((hit["normal"] as Vector3).y) > 0.3:
		return {}
	return hit


# =========================================================
# 泳ぎ（M-06）・落下
# =========================================================
# 今いる場所の水面の高さ（水の中でなければ -INF）
func _water_surface() -> float:
	for w in get_tree().get_nodes_in_group("water"):
		var water := w as Water
		if water != null and water.contains(global_position):
			return water.surface_y
	return -INF


func _in_deep_water() -> bool:
	var s := _water_surface()
	return s != -INF and global_position.y < s - SWIM_DEPTH


func _start_swim() -> void:
	gliding = false
	sprinting = false
	hitbox.deactivate()
	_set_state(State.SWIM)
	_log("泳ぐ")


func _state_swim() -> void:
	var s := _water_surface()
	if s == -INF:
		_set_state(State.MOVE)
		return
	var dir := _get_move_input()
	if _try_start_climb(dir):  # 岸の壁につかまって上がる
		return
	velocity.x = dir.x * SWIM_SPEED
	velocity.z = dir.z * SWIM_SPEED
	velocity.y = ((s - SWIM_FLOAT_DEPTH) - global_position.y) * 6.0  # 水面に浮かぶ
	if dir.length() > 0.1:
		_face_dir(dir, 0.2)
		_use_stamina(STAMINA_DRAIN_SWIM)
	else:
		_use_stamina(STAMINA_DRAIN_SWIM_IDLE)
	if stamina <= 0.0:
		_respawn(DROWN_DAMAGE, "溺れた")
		return
	if is_on_floor() and global_position.y > s - SWIM_DEPTH:  # 浅い所に上がった
		_set_state(State.MOVE)


# 最後に立っていた所へ戻す（溺れた・落ちたとき）
func _respawn(damage: int, why: String) -> void:
	_log(why)
	global_position = safe_position
	reset_physics_interpolation()  # 瞬間移動なので、前の位置からなめらかにつながないようにする
	velocity = Vector3.ZERO
	gliding = false
	sprinting = false
	stamina = max_stamina
	hp = max(hp - damage, 0)
	hp_changed.emit(hp, max_hp)
	if hp <= 0:
		_set_state(State.DEAD)
		_log("やられた…")
	else:
		_set_state(State.MOVE)


# ジャンプ（2回まで）と滑空（M-01・M-02）。MOVE の状態のときだけ呼ぶ
func _update_jump_and_glide() -> void:
	if Input.is_action_just_pressed("jump"):
		if not is_on_floor() and jumps_used == 0:
			jumps_used = 1  # 足場から落ちている途中は、1回目のジャンプを使ったことにする
		if jumps_used < MAX_JUMPS:  # ジャンプはスタミナを使わない
			velocity.y = JUMP_VELOCITY if jumps_used == 0 else AIR_JUMP_VELOCITY
			jumps_used += 1
			gliding = false
			_log("ジャンプ %d" % jumps_used)
		elif not is_on_floor() and jumps_used >= MAX_JUMPS and stamina > 0.0:
			gliding = true  # 2回跳んだ後にもう一度押すと、外套を開く
			_log("滑空")
	# 滑空はジャンプを押している間だけ。離すか、スタミナが切れたら閉じる
	if gliding and (not Input.is_action_pressed("jump") or stamina <= 0.0):
		gliding = false


# 強化アイテムの数から、最大HP・最大スタミナ・攻撃の倍率を決める（W-15 ④-2）
# picked：今拾ったアイテムの種類。最大HPが増えたら今のHPも足す。最大スタミナが増えたら満タンにする
func apply_upgrades(picked: String = "") -> void:
	max_hp = MAX_HP + Discoveries.hp_ups * UPGRADE_HP
	max_stamina = STAMINA_MAX + Discoveries.stamina_ups * UPGRADE_STAMINA
	attack_mult = 1.0 + Discoveries.attack_ups * UPGRADE_ATTACK
	if picked == "hp":
		hp = mini(hp + UPGRADE_HP, max_hp)
		_log("最大HP %d" % max_hp)
	elif picked == "stamina":
		stamina = max_stamina
		_log("最大スタミナ %d" % int(max_stamina))
	hp_changed.emit(hp, max_hp)


# 回復薬を使う（Q ／ 十字キー上）。歩いている・立っているときだけ。HPが満タンなら使わない
func use_heal() -> bool:
	if Discoveries.heals <= 0 or hp >= max_hp or hp <= 0:
		return false
	Discoveries.heals -= 1
	hp = mini(hp + HEAL_AMOUNT, max_hp)
	hp_changed.emit(hp, max_hp)
	_log("回復薬 +%d（残り %d）" % [HEAL_AMOUNT, Discoveries.heals])
	return true


func _use_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_stamina_used = true


# スタミナの回復：しばらく使わずにいると回復する
func _update_stamina() -> void:
	if _stamina_used:
		_stamina_idle_frames = 0
	else:
		_stamina_idle_frames += 1
	_stamina_used = false
	if _stamina_idle_frames >= STAMINA_REGEN_DELAY_FRAMES:
		stamina = minf(stamina + STAMINA_REGEN, max_stamina)


func _buffer_inputs() -> void:
	for action in ["attack_light", "attack_heavy", "dodge"]:
		if Input.is_action_just_pressed(action):
			_buffered_action = action
			_buffer_age = 0


func _take_buffered(allowed: Array) -> String:
	if _buffered_action == "" or _buffer_age > INPUT_BUFFER_FRAMES:
		return ""
	if not allowed.has(_buffered_action):
		return ""
	var a := _buffered_action
	_buffered_action = ""
	return a


func _get_move_input() -> Vector3:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(v.x, 0.0, v.y)
	var b := cam.global_transform.basis
	var forward := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var right := Vector3(b.x.x, 0.0, b.x.z).normalized()
	return right * v.x - forward * v.y


func _face_dir(dir: Vector3, weight: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)  # モデルは -Z が正面
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)


func _face_toward(pos: Vector3, weight: float) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length() > 0.01:
		_face_dir(d, weight)


# ソフトロックの相手を探す：SOFT_LOCK_RANGE 以内 かつ 基準の方向から左右 SOFT_LOCK_HALF_ANGLE_DEG 以内で、
# 基準の方向にいちばん近い（角度が小さい）敵。いなければ null
func find_soft_lock_target(ref_dir: Vector3) -> Node3D:
	var ref := Vector3(ref_dir.x, 0.0, ref_dir.z).normalized()
	if ref.length() < 0.01:
		return null
	var best: Node3D = null
	var best_angle := deg_to_rad(SOFT_LOCK_HALF_ANGLE_DEG)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node3D) or e.call("is_dead"):
			continue
		var to := (e as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() > SOFT_LOCK_RANGE or to.length() < 0.01:
			continue
		var angle := ref.angle_to(to.normalized())
		if angle <= best_angle:
			best_angle = angle
			best = e
	return best


func _toggle_lock_on() -> void:
	if lock_target != null:
		lock_target = null
		_log("ロックオン解除")
		return
	var best: Node3D = null
	var best_d := 25.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D and not e.call("is_dead"):
			var d := global_position.distance_to((e as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = e
	lock_target = best
	if best != null:
		_log("ロックオン: " + str(best.get("display_name")))


func _is_parry_window() -> bool:
	return state == State.ATTACK and _attack_can_parry and state_frame <= parry_window_frames


func is_dead() -> bool:
	return state == State.DEAD


func state_name() -> String:
	return State.keys()[state]


func _log(text: String) -> void:
	event_logged.emit(text)


# 状態が目で見えると調整がすごく楽になる
#  ・ポーズ：状態と state_frame からアニメーションの位置を決める（見た目だけ）
#  ・色：モデルの上に状態の色を重ねる。何も無いときは重ねない（元の見た目）
func _update_visual() -> void:
	_update_pose()
	var c := Color.WHITE
	var strength := 0.0
	match state:
		State.ATTACK:
			if _is_parry_window():
				c = TINT_PARRY
				strength = TINT_STRENGTH
		State.DODGE:
			if state_frame <= DODGE_INVULN_FRAMES:
				c = TINT_DODGE
				strength = TINT_STRENGTH * 0.6
		State.HITSTUN:
			c = TINT_HITSTUN
			strength = TINT_STRENGTH
		State.CHARGE:
			# 溜めるほどオレンジに近づき、最大まで溜まると黄色く光る
			var ratio := clampf(float(state_frame) / float(CHARGE_MAX_FRAMES), 0.0, 1.0)
			c = COLOR_CHARGE.darkened(0.6).lerp(COLOR_CHARGE, ratio)  # 暗いオレンジ → 明るいオレンジ
			strength = CHARGE_GLOW_ENERGY + 0.4 * ratio
			if ratio >= 1.0:
				c = COLOR_CHARGE_FULL
	if strength == 0.0 and _counter_frames > 0 and state != State.DEAD:
		c = TINT_COUNTER
		strength = 0.6
	model.set_tint(c, strength)


func _update_pose() -> void:
	# 回避中だけ、モデルを回避の方向へ向ける（後ろへの回避でも前転に見えるように）
	model.rotation.y = 0.0
	match state:
		State.MOVE:
			var spd := Vector2(velocity.x, velocity.z).length()
			if gliding:
				model.pose_loop(ANIM_GLIDE)
			elif not is_on_floor():
				model.pose_loop(ANIM_AIR)
			elif sprinting:
				model.pose_loop(ANIM_SPRINT, spd / SPRINT_SPEED)
			elif spd > 0.5:
				model.pose_loop(ANIM_RUN, ANIM_RUN_SPEED * spd / MOVE_SPEED)
			else:
				model.pose_loop(ANIM_IDLE)
		State.ATTACK, State.CHARGE:
			var atk: Dictionary = ATTACKS[_attack_id]
			var a: Dictionary = ATTACK_ANIMS[_attack_id]
			var startup: int = atk["startup"]
			var total: int = startup + int(atk["active"]) + int(atk["recovery"])
			# 溜め中は、溜めに入ったフレームのポーズ（振りかぶり）で止める
			var f := CHARGE_START_FRAMES if state == State.CHARGE else state_frame
			model.pose_frames(a["clip"], f, total, a["from"], a["to"], startup, a["key"])
		State.DODGE:
			if _dodge_dir.length() > 0.1:
				var fwd := -global_transform.basis.z
				# Y軸まわりの角度は atan2(-x, -z)（-Z が 0 度）。体の向きとの差だけモデルを回す
				model.rotation.y = atan2(-_dodge_dir.x, -_dodge_dir.z) - atan2(-fwd.x, -fwd.z)
			model.pose_frames(ANIM_DODGE["clip"], state_frame, DODGE_TOTAL_FRAMES, ANIM_DODGE["from"], ANIM_DODGE["to"])
		State.CLIMB:
			var cspd := velocity.length()
			model.pose_loop(ANIM_CLIMB, clampf(cspd / CLIMB_SPEED, 0.0, 1.0))
		State.SWIM:
			if Vector2(velocity.x, velocity.z).length() > 0.5:
				model.pose_loop(ANIM_SWIM)
			else:
				model.pose_loop(ANIM_SWIM_IDLE)
		State.HITSTUN:
			model.pose_frames(ANIM_HITSTUN["clip"], state_frame, HITSTUN_FRAMES, ANIM_HITSTUN["from"], ANIM_HITSTUN["to"])
		State.DEAD:
			var end_time := model.clip_length(ANIM_DEATH)
			model.pose_at(ANIM_DEATH, minf(float(state_frame) * CharacterModel.TICK_SEC, end_time))
