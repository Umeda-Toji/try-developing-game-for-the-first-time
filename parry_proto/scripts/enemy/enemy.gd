# Godot 4.7.2 / GDScript
# res://scripts/enemy/enemy.gd
#
# 敵（ボスも同じスクリプトで、@export の数値を変えて作る）
#
#  ・攻撃は「予兆(TELEGRAPH) → 判定(ATTACK) → 硬直(RECOVER)」
#    予兆の最後 glint_frames は強く光る＝パリィの合図
#  ・パリィ不可の攻撃は赤く光る（回避で対処）
#  ・フェイント攻撃（E-10）：溜めが長く、途中で一度ニセの白い光を出す（攻撃は来ない）。
#    本物の攻撃は、溜めの最後の2回目の光のとき
#  ・第2形態（E-11）：HP が phase2_hp_ratio を切ると、少し止まって光り（その間は無敵）、
#    速く・連撃が多く・フェイントを使うようになる。体幹はリセット
#  ・体幹(posture)が溜まるとブレイク＝大ダメージのチャンス
#  ・ジャスト回避のスロー中は GameFeel.enemy_time_scale で敵だけ遅くなる
#  ・飛び道具の敵（E-14、ranged = true）：プレイヤーと keep_distance_min〜max の距離を保ち、
#    攻撃の瞬間に剣を振る代わりに魔法の弾（scripts/combat/projectile.gd）を撃つ。壁の向こうにいるときは撃たない
#  ・攻撃の合図（光る間）は、体の白い（赤い）光に加えて、まわりを照らす赤い光を出す（11/18。気づきやすく）
class_name Enemy
extends CharacterBody3D

signal stats_changed(enemy: Enemy)
signal event_logged(text: String)

enum State { IDLE, CHASE, TELEGRAPH, ATTACK, RECOVER, STAGGER, BROKEN, HITSTUN, DEAD, PHASE_CHANGE }

@export var display_name := "敵"
@export var aggro_range := 15.0           # この距離まで近づくと動き出す
@export var side_id := -1                 # 街の寄り道の敵（W-15 ④-3）の番号。-1 は広場・ボスの敵
const SIDE_LEASH_MULT := 2.5              # 寄り道の敵は、気づく距離のこの倍より離れると追うのをやめる
@export var max_hp := 80
@export var max_posture := 60.0
@export var move_speed := 3.0
@export var attack_range := 2.2
@export var telegraph_frames := 36        # 予兆の長さ
@export var glint_frames := 10            # 予兆の最後の「光る」長さ
@export var active_frames := 6            # 攻撃判定が出ている長さ
@export var recover_frames := 30          # 攻撃後の隙
@export var attack_cooldown_frames := 50
@export var damage := 15
@export var combo_hits := 1               # ボスは3などにすると連撃
@export var combo_gap_frames := 16        # 連撃の2発目以降の予兆（短い）
@export var unparryable_every := 0        # 0=なし / 3なら3回に1回パリィ不可
@export var feint_every := 0              # 0=なし / 3なら3回に1回フェイント攻撃（E-10）
@export var feint_telegraph_frames := 66  # フェイント攻撃の溜めの長さ
@export var feint_glint_start := 26       # 溜め始めからこのフレームで、ニセの光（長さは glint_frames）
@export var feint_offset := 0             # フェイントにする攻撃をずらす（パリィ不可の攻撃と重ならないように）

# ---- 第2形態（E-11）。phase2_hp_ratio が 0 なら第2形態なし ----
@export var phase2_hp_ratio := 0.0             # HP がこの割合以下になったら第2形態（ボスは 0.5）
@export var phase2_transition_frames := 60     # 切り替わりの演出の長さ（この間は無敵・攻撃しない）
@export var phase2_speed_mult := 1.4           # 移動の速さの倍率
@export var phase2_telegraph_frames := 30      # 予兆の長さ
@export var phase2_combo_gap_frames := 14      # 連撃の2発目以降の予兆
@export var phase2_combo_hits := 4             # 連撃数
@export var phase2_feint_every := 3            # フェイントの頻度
@export var phase2_feint_offset := 1           # フェイントをずらす（パリィ不可の3回目・6回目…と重ならない）
@export var phase2_body_color := Color(0.85, 0.2, 0.45)
@export var parry_posture_damage := 30.0  # パリィされたときの体幹ダメージ
@export var posture_recover_delay := 90   # 殴られなければこの後から体幹回復
@export var posture_recover_per_frame := 0.15
@export var stagger_frames := 50
@export var broken_frames := 150
@export var body_color := Color(0.85, 0.35, 0.3)
var bar_revealed := false                 # 攻撃を当てる（パリィする）までは、頭の上の体力バーを出さない
@export var bar_height := 2.0             # 頭の上の体力バー（U-08）を出す高さ（m）。main.gd が大きさから決める

# ---- 飛び道具の敵（E-14）----
@export var ranged := false
@export var projectile_speed := 8.0       # 弾の速さ（m/秒）
@export var keep_distance_min := 5.0      # これより近づかれたら下がる（m）
@export var keep_distance_max := 8.0      # これより離れたら近づく（m）。この間にいれば撃つ
const PROJECTILE_HEIGHT := 1.3            # 弾を撃つ高さ（m）
const PROJECTILE_AIM_HEIGHT := 1.1        # プレイヤーのこの高さをねらう（m）

# ---- 見た目（P-16）。アニメは見た目だけで、判定のタイミングは上の数値（フレーム）で決まる ----
@export var recolor_model := true   # true：モデルを body_color で塗る（マネキン用）。false：素材の色のまま（ボス）
@export var attack_anims: Array = []  # 攻撃のアニメ。連撃では順番に使う。空なら DEFAULT_ATTACK_ANIM
const DEFAULT_ATTACK_ANIM := {"clip": "ual1/Sword_Attack", "from": 0.0, "key": 0.38, "to": 1.0}
const SWING_FOLLOW_SEC := 0.15      # 攻撃判定が出ている間に進めるアニメの長さ（振り切り）
const COMBO_WINDUP_SEC := 0.2       # 連撃の2発目以降は、振りかぶりをこれだけに縮める
const ANIM_IDLE := "ual1/Idle"
const ANIM_MOVE := "ual1/Jog_Fwd"
const ANIM_MOVE_REF_SPEED := 4.0    # 走りアニメがちょうど合う移動の速さ（m/秒）
const ANIM_HITSTUN := "ual1/Hit_Chest"
const ANIM_STAGGER := "ual2/Hit_Knockback"
const ANIM_BROKEN := "ual1/Crouch_Idle"  # 体幹ブレイク中：しゃがみこむ
const ANIM_PHASE_CHANGE := "ual1/Spell_Simple_Shoot"
const ANIM_DEATH := "ual1/Death01"
const HITSTUN_FRAMES := 12
# 状態の色（モデルの上に重ねる）
const TINT_GLINT := Color(1, 1, 0.85)          # パリィの合図（フェイントのニセの光も同じ）
const TINT_UNPARRYABLE := Color(1, 0.15, 0.1)  # パリィ不可の合図
const TINT_CHARGE := Color(1, 0.5, 0.1)        # 溜め中のゆっくりした点滅
const TINT_STAGGER := Color(1, 1, 0.3)
const TINT_BROKEN := Color(1, 0.8, 0.2)
const GLINT_STRENGTH := 1.6
const WARN_LIGHT_COLOR := Color(1.0, 0.12, 0.08)  # 攻撃の合図の赤い光
const WARN_LIGHT_ENERGY := 6.0
const WARN_LIGHT_RANGE := 6.0                      # 照らす範囲（m）

var state: State = State.IDLE
var state_frame := 0
var hp := 0
var posture := 0.0
var hitstop_frames := 0

var _target: Node3D = null
var _cooldown := 0
var _since_hit := 0
var _time_acc := 0.0
var _desired := Vector3.ZERO
var _combo_index := 0
var _attack_count := 0
var _current_unparryable := false
var _current_feint := false
var _phase2 := false
var _hit_flash := 0
var _dead_frames := 0          # 倒れてからのフレーム（倒れたあとは _tick が動かないので別に数える）
var _swing_anim: Dictionary = DEFAULT_ATTACK_ANIM  # 今振っている攻撃のアニメ
var _base := {}                # 難易度を掛ける前の値（apply_difficulty で使う）

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var model: CharacterModel = $Model
var warn_light: OmniLight3D   # 攻撃の合図の赤い光（まわりを照らす）


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	if recolor_model:
		model.set_body_color(body_color)
	warn_light = OmniLight3D.new()
	warn_light.name = "WarnLight"
	warn_light.light_color = WARN_LIGHT_COLOR
	warn_light.omni_range = WARN_LIGHT_RANGE
	warn_light.light_energy = 0.0
	warn_light.shadow_enabled = false  # 影は付けない（軽くする）
	warn_light.position = Vector3.UP * bar_height * 0.6
	add_child(warn_light)
	hitbox.hit_landed.connect(_on_hitbox_hit)
	stats_changed.emit(self)
	apply_difficulty()
	_update_visual()  # 最初のポーズを決めておく（タイトル画面でゲームが止まっていても T字のポーズにならないように）


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 25.0 * delta
	if state == State.DEAD:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_dead_frames += 1
		_update_visual()
		return
	if _target == null:
		_target = get_tree().get_first_node_in_group("player") as Node3D

	if hitstop_frames > 0:  # ヒットストップは実時間で数える（スローの影響を受けない）
		hitstop_frames -= 1
		_update_visual()
		return

	# 敵の「論理フレーム」を時間倍率ぶんだけ進める
	var ts := GameFeel.enemy_time_scale
	_time_acc += ts
	while _time_acc >= 1.0:
		_time_acc -= 1.0
		_tick()
	velocity.x = _desired.x * ts
	velocity.z = _desired.z * ts
	move_and_slide()
	_update_visual()


# 難易度（U-07）：予兆の長さ・連撃の間隔・ダメージに倍率を掛ける（ボス第2形態の値にも）
#  ・フェイントの溜めとニセの光のタイミングも、予兆と同じ倍率で伸び縮みさせる
#  ・光る長さ（glint_frames）は変えない。予兆は光る長さより必ず長くする
#  ・最初に呼ばれたときの値を覚えておき、いつもそこから計算する（何度呼んでも同じ結果）
#  ・戦い始める前に呼ぶ（第2形態になった後に呼ぶと、第1形態の値に戻ってしまう）
func apply_difficulty() -> void:
	if _base.is_empty():
		_base = {
			"telegraph_frames": telegraph_frames, "combo_gap_frames": combo_gap_frames,
			"feint_telegraph_frames": feint_telegraph_frames, "feint_glint_start": feint_glint_start,
			"phase2_telegraph_frames": phase2_telegraph_frames, "phase2_combo_gap_frames": phase2_combo_gap_frames,
			"damage": damage,
		}
	var min_tele := glint_frames + 1
	telegraph_frames = Difficulty.scale_frames(_base["telegraph_frames"], "telegraph_mult", min_tele)
	feint_telegraph_frames = Difficulty.scale_frames(_base["feint_telegraph_frames"], "telegraph_mult", min_tele)
	feint_glint_start = Difficulty.scale_frames(_base["feint_glint_start"], "telegraph_mult")
	phase2_telegraph_frames = Difficulty.scale_frames(_base["phase2_telegraph_frames"], "telegraph_mult", min_tele)
	combo_gap_frames = Difficulty.scale_frames(_base["combo_gap_frames"], "combo_gap_mult", min_tele)
	phase2_combo_gap_frames = Difficulty.scale_frames(_base["phase2_combo_gap_frames"], "combo_gap_mult", min_tele)
	damage = maxi(roundi(float(_base["damage"]) * float(Difficulty.value("damage_mult"))), 1)


func _set_state(new_state: State) -> void:
	state = new_state
	state_frame = -1


# 1論理フレームぶんの処理
func _tick() -> void:
	state_frame += 1
	_since_hit += 1
	if _cooldown > 0:
		_cooldown -= 1
	if _hit_flash > 0:
		_hit_flash -= 1
	if _since_hit > posture_recover_delay and state != State.BROKEN:
		posture = maxf(posture - posture_recover_per_frame, 0.0)

	var dist := 999.0
	if _target != null:
		dist = global_position.distance_to(_target.global_position)

	match state:
		State.IDLE:
			_desired = Vector3.ZERO
			if dist < aggro_range:
				_set_state(State.CHASE)
		State.CHASE:
			_face_target(0.15)
			if side_id >= 0 and dist > aggro_range * SIDE_LEASH_MULT:  # 寄り道の敵は、離れたらあきらめる
				_desired = Vector3.ZERO
				_set_state(State.IDLE)
			elif ranged:
				_chase_ranged(dist)
			elif dist > attack_range:
				_desired = _dir_to_target() * move_speed
			else:
				_desired = Vector3.ZERO
				if _cooldown == 0:
					_begin_combo()
		State.TELEGRAPH:
			_desired = Vector3.ZERO
			# 予兆の前半だけプレイヤーを追って向きを変える（後半は向き固定＝読める）
			# ニセの光の間も、本物と同じように向きを止める
			if state_frame < _telegraph_length() - glint_frames and not is_fake_glint():
				_face_target(0.2)
			if state_frame >= _telegraph_length():
				_set_state(State.ATTACK)
		State.ATTACK:
			_desired = Vector3.ZERO if ranged else -global_transform.basis.z * 4.0
			if state_frame == 0 and ranged:
				_shoot()
			elif state_frame == 0:
				hitbox.activate({
					"damage": damage, "hitstop": 5, "shake": 0.12,
					"unparryable": _current_unparryable,
				})
				if _target != null and dist < attack_range + 1.5 and _target.has_method("on_enemy_attack_active"):
					_target.on_enemy_attack_active(self)
			if state_frame >= active_frames:
				hitbox.deactivate()
				_combo_index += 1
				if _combo_index < combo_hits:
					_set_state(State.TELEGRAPH)  # 連撃の次の一発へ
				else:
					_set_state(State.RECOVER)
		State.RECOVER:
			_desired = Vector3.ZERO
			if state_frame >= recover_frames:
				_cooldown = attack_cooldown_frames
				_set_state(State.CHASE)
		State.STAGGER:
			_desired = Vector3.ZERO
			if state_frame >= stagger_frames:
				_cooldown = attack_cooldown_frames
				_set_state(State.CHASE)
		State.HITSTUN:
			_desired = Vector3.ZERO
			if state_frame >= HITSTUN_FRAMES:
				_set_state(State.CHASE)
		State.PHASE_CHANGE:
			_desired = Vector3.ZERO
			if state_frame >= phase2_transition_frames:
				_set_state(State.CHASE)
		State.BROKEN:
			_desired = Vector3.ZERO
			if state_frame >= broken_frames:
				posture = 0.0
				_cooldown = attack_cooldown_frames
				stats_changed.emit(self)
				_set_state(State.CHASE)


# 飛び道具の敵の動き：近すぎたら下がり、遠すぎたら近づき、ちょうどよければ撃つ
func _chase_ranged(dist: float) -> void:
	if dist < keep_distance_min:
		_desired = -_dir_to_target() * move_speed
	elif dist > keep_distance_max:
		_desired = _dir_to_target() * move_speed
	elif not has_line_of_sight():
		# 壁の向こうにいるときは撃たない。見える所まで近づく
		_desired = _dir_to_target() * move_speed
	else:
		_desired = Vector3.ZERO
		if _cooldown == 0:
			_begin_combo()


# プレイヤーとの間に壁（地形）がないか（胸の高さどうしで調べる）
func has_line_of_sight() -> bool:
	if _target == null:
		return false
	var from := global_position + Vector3.UP * PROJECTILE_HEIGHT
	var to := _target.global_position + Vector3.UP * PROJECTILE_AIM_HEIGHT
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _shoot() -> void:
	if _target == null:
		return
	var p := Projectile.new()
	p.name = "Projectile"
	p.speed = projectile_speed
	p.shooter = self
	p.attack = {"damage": damage, "hitstop": 5, "shake": 0.1, "unparryable": _current_unparryable}
	get_parent().add_child(p)
	var from := global_position + Vector3.UP * PROJECTILE_HEIGHT - global_transform.basis.z * 0.6
	var to := _target.global_position + Vector3.UP * PROJECTILE_AIM_HEIGHT
	p.global_position = from
	p.direction = (to - from).normalized()
	_log("%s が魔法を撃った" % display_name)


func _begin_combo() -> void:
	_combo_index = 0
	_attack_count += 1
	_current_unparryable = unparryable_every > 0 and _attack_count % unparryable_every == 0
	_current_feint = feint_every > 0 and (_attack_count + feint_offset) % feint_every == 0
	if _current_feint:
		_log("%s フェイント攻撃の構え" % display_name)
	_set_state(State.TELEGRAPH)


func _telegraph_length() -> int:
	if _combo_index > 0:
		return combo_gap_frames
	return feint_telegraph_frames if _current_feint else telegraph_frames


# 今、ニセの光（フェイント）を出しているところか
func is_fake_glint() -> bool:
	if state != State.TELEGRAPH or not _current_feint or _combo_index != 0:
		return false
	return state_frame >= feint_glint_start and state_frame < feint_glint_start + glint_frames


# 今、白（または赤）く光っているか（本物の合図・ニセの合図のどちらでも）
func is_glinting() -> bool:
	if state != State.TELEGRAPH:
		return false
	return is_fake_glint() or _telegraph_length() - state_frame <= glint_frames


# 「あと何論理フレームで攻撃判定が出るか」（テスト・デバッグ用）
func frames_until_active() -> int:
	if state != State.TELEGRAPH:
		return -1
	return _telegraph_length() - state_frame


# =========================================================
# プレイヤーからの攻撃・パリィ
# =========================================================
func receive_attack(attack: Dictionary, _attacker: Node) -> int:
	if state == State.DEAD or state == State.PHASE_CHANGE:  # 切り替わりの演出中は無敵
		return Combat.HitResult.IGNORED
	var dmg := int(attack["damage"])
	bar_revealed = true
	if state == State.BROKEN:
		dmg = int(dmg * 1.5)
	hp = max(hp - dmg, 0)
	_since_hit = 0
	_hit_flash = 4
	hitstop_frames = int(attack["hitstop"])
	if state != State.BROKEN:
		posture += float(attack["posture"])
	_log("%s に %d ダメージ" % [display_name, dmg])

	if hp <= 0:
		_die()
	elif _should_enter_phase2():
		_enter_phase2()
	elif posture >= max_posture and state != State.BROKEN:
		_break()
	elif state in [State.IDLE, State.CHASE, State.RECOVER, State.HITSTUN]:
		# 予兆中・攻撃中は怯まない（スーパーアーマー）→ パリィする意味が生まれる
		_set_state(State.HITSTUN)
	stats_changed.emit(self)
	return Combat.HitResult.HIT


func on_parried(_by: Node) -> void:
	bar_revealed = true
	hitbox.deactivate()
	posture += parry_posture_damage
	_since_hit = 0
	hitstop_frames = 6
	if posture >= max_posture:
		_break()
	else:
		_set_state(State.STAGGER)
		_log("%s がよろめいた" % display_name)
	stats_changed.emit(self)


func _should_enter_phase2() -> bool:
	return not _phase2 and phase2_hp_ratio > 0.0 and float(hp) <= float(max_hp) * phase2_hp_ratio


func _enter_phase2() -> void:
	_phase2 = true
	hitbox.deactivate()
	posture = 0.0
	move_speed *= phase2_speed_mult
	telegraph_frames = phase2_telegraph_frames
	combo_gap_frames = phase2_combo_gap_frames
	combo_hits = phase2_combo_hits
	feint_every = phase2_feint_every
	feint_offset = phase2_feint_offset
	body_color = phase2_body_color
	if recolor_model:
		model.set_body_color(body_color)
	_cooldown = 0
	_set_state(State.PHASE_CHANGE)
	GameFeel.shake(0.25, 20)
	GameFeel.spark(hurtbox.global_position, GameFeel.SPARK_BREAK)
	_log("◆%s 第2形態！" % display_name)


func is_phase2() -> bool:
	return _phase2


func _break() -> void:
	posture = max_posture
	hitbox.deactivate()
	_set_state(State.BROKEN)
	GameFeel.shake(0.2, 12)
	GameFeel.spark(hurtbox.global_position, GameFeel.SPARK_BREAK)
	_log("◆%s 体幹ブレイク！" % display_name)


func _die() -> void:
	hitbox.deactivate()
	_set_state(State.DEAD)
	_dead_frames = 0
	remove_from_group("enemies")
	_log("%s を倒した" % display_name)
	if side_id >= 0:
		Discoveries.kill_side_enemy(side_id)  # 一度倒した寄り道の敵は、リトライしても戻らない（自動で保存）


func _on_hitbox_hit(target_hurtbox: Hurtbox) -> void:
	var t := target_hurtbox.entity
	if not t.has_method("receive_attack"):
		return
	var result: int = t.receive_attack(hitbox.attack, self)
	if result == Combat.HitResult.HIT:
		hitstop_frames = 5
		GameFeel.spark(hitbox.contact_point(target_hurtbox), GameFeel.SPARK_HIT)


# =========================================================
# 補助
# =========================================================
func _dir_to_target() -> Vector3:
	var d := _target.global_position - global_position
	d.y = 0.0
	return d.normalized()


func _face_target(weight: float) -> void:
	if _target == null:
		return
	var d := _dir_to_target()
	if d.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), weight)


func is_dead() -> bool:
	return state == State.DEAD


func state_name() -> String:
	return State.keys()[state]


func _log(text: String) -> void:
	event_logged.emit(text)


# 見た目：ポーズ（アニメ）と、モデルに重ねる状態の色
func _update_visual() -> void:
	_update_pose()
	var c := Color.WHITE
	var strength := 0.0
	match state:
		State.TELEGRAPH:
			if is_glinting():
				# パリィの合図：白く強く光る（パリィ不可は赤）。フェイントのニセの光も同じ見た目
				c = TINT_UNPARRYABLE if _current_unparryable else TINT_GLINT
				strength = GLINT_STRENGTH
			else:
				# 溜め中：ゆっくり点滅
				c = TINT_CHARGE
				strength = 0.25 + 0.25 * sin(float(state_frame) * 0.4)
		State.STAGGER:
			c = TINT_STAGGER
			strength = 0.5
		State.PHASE_CHANGE:
			# 切り替わり中：新しい色で、強く点滅する
			c = phase2_body_color
			strength = 0.8 + 0.8 * sin(float(state_frame) * 0.6)
		State.BROKEN:
			c = TINT_BROKEN
			strength = 0.9
	if _hit_flash > 0 and state != State.DEAD:
		c = Color.WHITE
		strength = 1.2
	# 素材の色のままのモデル（ボス）は、第2形態になったら新しい色をうっすら重ねる
	if strength == 0.0 and _phase2 and not recolor_model and state != State.DEAD:
		c = phase2_body_color
		strength = 0.35
	model.set_tint(c, strength)
	# 攻撃の合図の間は、まわりを赤く照らす（白い合図・赤い合図・ニセの合図のどれでも）
	if warn_light != null:
		warn_light.light_energy = WARN_LIGHT_ENERGY if is_glinting() and state != State.DEAD else 0.0


func _current_attack_anim() -> Dictionary:
	if attack_anims.is_empty():
		return DEFAULT_ATTACK_ANIM
	return attack_anims[_combo_index % attack_anims.size()]


# 状態と state_frame（敵の論理フレーム）からポーズを決める。スロー中は論理フレームが遅く進むので、動きも遅くなる
func _update_pose() -> void:
	var ts := GameFeel.enemy_time_scale
	match state:
		State.IDLE:
			model.pose_loop(ANIM_IDLE, ts)
		State.CHASE:
			if _desired.length() > 0.1:
				model.pose_loop(ANIM_MOVE, ts * _desired.length() / ANIM_MOVE_REF_SPEED)
			else:
				model.pose_loop(ANIM_IDLE, ts)
		State.TELEGRAPH:
			# 振りかぶって、予兆の終わり（＝攻撃判定が出る瞬間）にちょうど振り下ろしの瞬間（key）になる
			_swing_anim = _current_attack_anim()
			var key: float = _swing_anim["key"]
			var from: float = _swing_anim["from"]
			if _combo_index > 0:
				from = maxf(from, key - COMBO_WINDUP_SEC)
			if _swing_anim.has("windup_clip"):
				# 振りかぶりを別のアニメで見せる（魔法使い：手を上げる → 撃つ）
				var w: String = _swing_anim["windup_clip"]
				model.pose_frames(w, state_frame, _telegraph_length(), 0.0, model.clip_length(w))
			else:
				model.pose_frames(_swing_anim["clip"], state_frame, _telegraph_length(), from, key)
		State.ATTACK:
			var key: float = _swing_anim["key"]
			var follow := minf(key + SWING_FOLLOW_SEC, _swing_anim["to"])
			model.pose_frames(_swing_anim["clip"], state_frame, active_frames, key, follow)
		State.RECOVER:
			var key: float = _swing_anim["key"]
			var follow := minf(key + SWING_FOLLOW_SEC, _swing_anim["to"])
			model.pose_frames(_swing_anim["clip"], state_frame, recover_frames, follow, _swing_anim["to"])
		State.HITSTUN:
			model.pose_frames(ANIM_HITSTUN, state_frame, HITSTUN_FRAMES, 0.0, model.clip_length(ANIM_HITSTUN))
		State.STAGGER:
			model.pose_frames(ANIM_STAGGER, state_frame, stagger_frames, 0.0, model.clip_length(ANIM_STAGGER))
		State.BROKEN:
			model.pose_loop(ANIM_BROKEN, ts)
		State.PHASE_CHANGE:
			model.pose_frames(ANIM_PHASE_CHANGE, state_frame, phase2_transition_frames, 0.0, model.clip_length(ANIM_PHASE_CHANGE))
		State.DEAD:
			var end_time := model.clip_length(ANIM_DEATH)
			model.pose_at(ANIM_DEATH, minf(float(_dead_frames) * CharacterModel.TICK_SEC, end_time))
