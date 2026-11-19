# Godot 4.7.2 / GDScript
# res://scripts/camera/camera_rig.gd
# 三人称カメラ：プレイヤー追従＋マウス/右スティック回転＋ロックオン＋揺れ
# 構成：CameraRig(Node3D) > SpringArm3D > Camera3D
class_name CameraRig
extends Node3D

@export var target: Player
@export var mouse_sensitivity := 0.003
@export var stick_speed := 2.5
@export var follow_lerp := 0.2

var yaw := 0.0
var pitch := -0.35

var _shake_strength := 0.0
var _shake_frames := 0
var _shake_total := 1

@onready var spring: SpringArm3D = $SpringArm3D
@onready var cam: Camera3D = $SpringArm3D/Camera3D


# 構え（G-03）：肩越しに寄ってズーム
const AIM_BLEND_FRAMES := 10
const AIM_LENGTH := 1.6
const AIM_FOV := 45.0
const AIM_SHOULDER := 0.55          # 右肩へのずらし（m）
var aim_blend := 0.0                # 0＝ふつう、1＝構え
var _normal_length := 4.5
var _normal_fov := 70.0
var _last_pad := false              # 最後にカメラを動かしたのがパッドか（狙いの補助はパッドだけ）


func _ready() -> void:
	add_to_group("camera_rig")
	GameFeel.shake_requested.connect(_on_shake)
	_normal_length = spring.spring_length if spring.spring_length > 0.0 else 4.5
	_normal_fov = cam.fov
	if target != null:
		spring.add_excluded_object(target.get_rid())
		global_position = target.global_position + Vector3(0, 1.4, 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_last_pad = false
		apply_look(mm.relative * mouse_sensitivity, true, _is_aiming())
	# Esc でマウスを解放する処理は、ポーズメニュー（U-04）に移した（Esc でポーズ＝マウスが出る）
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# カメラを回す。amount は（横, 縦）の回す量。設定（O-01）の感度と反転を掛ける
func apply_look(amount: Vector2, is_mouse: bool, aiming: bool = false) -> void:
	var wheel := get_tree().get_first_node_in_group("weapon_wheel") as WeaponWheel
	if wheel != null and wheel.is_open:
		return  # 武器の輪を開いている間は、右スティックは武器を選ぶのに使う
	var s := GameSettings.look_scale(is_mouse, aiming)
	yaw -= amount.x * s.x
	pitch = clampf(pitch - amount.y * s.y, -1.2, 0.4)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(target.global_position + Vector3(0, 1.4, 0), follow_lerp)

	var lt := target.lock_target
	if lt != null and is_instance_valid(lt):
		# ロックオン中：プレイヤー→敵の方向を見るように回す
		var d := lt.global_position - target.global_position
		d.y = 0.0
		if d.length() > 0.1:
			yaw = lerp_angle(yaw, atan2(-d.x, -d.z), 0.15)
		pitch = lerpf(pitch, -0.3, 0.1)
	else:
		var look := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
		if look.length() > 0.05:
			_last_pad = true
		apply_look(look * stick_speed * delta, false, _is_aiming())
		_aim_assist(look)

	# 構え：寄る・ズーム・右肩へ
	aim_blend = move_toward(aim_blend, 1.0 if _is_aiming() else 0.0, 1.0 / AIM_BLEND_FRAMES)
	spring.spring_length = lerpf(_normal_length, AIM_LENGTH, aim_blend)
	cam.fov = lerpf(_normal_fov, AIM_FOV, aim_blend)
	spring.position.x = AIM_SHOULDER * aim_blend
	rotation = Vector3(pitch, yaw, 0.0)

	# 揺れ：残りフレームに比例して弱まる
	if _shake_frames > 0:
		_shake_frames -= 1
		var s := _shake_strength * float(_shake_frames) / float(_shake_total)
		cam.h_offset = randf_range(-s, s)
		cam.v_offset = randf_range(-s, s)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


func _is_aiming() -> bool:
	return target != null and target.aiming


# 反動：上に跳ね、横に少し揺れる（G-03）
func add_recoil(up: float, side: float) -> void:
	pitch = clampf(pitch + up, -1.2, 0.4)
	yaw += randf_range(-side, side)


# 狙いの補助（パッドで構えているとき。設定でオン／オフ）：照準の近くの敵へ少しずつ寄る
func _aim_assist(stick: Vector2) -> void:
	if not _is_aiming() or not GameSettings.aim_assist or not _last_pad or stick.length() > 0.2:
		return
	var from := cam.global_position
	var fwd := -cam.global_basis.z
	var best: Node3D = null
	var best_angle := deg_to_rad(GameSettings.AIM_ASSIST_ANGLE_DEG)
	for e in get_tree().get_nodes_in_group("enemies"):
		var n := e as Node3D
		if n == null or e.call("is_dead"):
			continue
		var p := n.global_position + Vector3.UP * float(e.get("bar_height")) * 0.45
		if from.distance_to(p) > GameSettings.AIM_ASSIST_RANGE:
			continue
		var ang := fwd.angle_to((p - from).normalized())
		if ang < best_angle:
			best_angle = ang
			best = n
	if best == null:
		return
	var d := (best.global_position + Vector3.UP * float(best.get("bar_height")) * 0.45 - from).normalized()
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := asin(clampf(d.y, -1.0, 1.0))
	yaw = lerp_angle(yaw, want_yaw, GameSettings.AIM_ASSIST_PULL)
	pitch = lerpf(pitch, want_pitch, GameSettings.AIM_ASSIST_PULL)


func _on_shake(strength: float, frames: int) -> void:
	if strength >= _shake_strength * float(_shake_frames) / float(max(_shake_total, 1)):
		_shake_strength = strength
		_shake_frames = frames
		_shake_total = max(frames, 1)
