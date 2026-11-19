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


func _ready() -> void:
	GameFeel.shake_requested.connect(_on_shake)
	if target != null:
		spring.add_excluded_object(target.get_rid())
		global_position = target.global_position + Vector3(0, 1.4, 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		apply_look(mm.relative * mouse_sensitivity, true)
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
		apply_look(look * stick_speed * delta, false)

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


func _on_shake(strength: float, frames: int) -> void:
	if strength >= _shake_strength * float(_shake_frames) / float(max(_shake_total, 1)):
		_shake_strength = strength
		_shake_frames = frames
		_shake_total = max(frames, 1)
