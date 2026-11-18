# Godot 4.7.2 / GDScript
# res://scripts/ui/slow_effect.gd
#
# スロー中の画面演出（F-04）
#  ・ジャスト回避のスロー（GameFeel.is_witch_time()）の間、画面の色を薄くして（彩度を下げて）、青っぽくする
#  ・内蔵GPUでも軽いように、重いポストエフェクトは使わない（N-02）
#      - 彩度：Environment の adjustment（色調補正）を使う
#      - 青み：画面全体に半透明の ColorRect を1枚かぶせるだけ
#  ・切り替えはパッと変えず、SLOW_FADE_FRAMES かけてじわっと変える（物理フレームで数える）
class_name SlowEffect
extends CanvasLayer

# ---- 見た目の数値（ここを変えれば見た目が変わる）----
const SLOW_FADE_FRAMES := 8                      # 演出が出きる／消えきるまで
const SLOW_SATURATION := 0.35                    # スロー中の彩度（1.0 = 普通、0.0 = 白黒）
const SLOW_BRIGHTNESS := 0.95                    # スロー中の明るさ（1.0 = 普通）
const SLOW_CONTRAST := 1.1                       # スロー中のコントラスト（1.0 = 普通）
const SLOW_TINT := Color(0.35, 0.55, 1.0, 0.14)  # 画面にかぶせる色（a = 濃さ）
const LAYER_ORDER := 0                           # HUD（1）や結果画面（10）より奥に描く

var environment: Environment  # main.gd が渡す
var strength := 0.0           # 0.0 = 演出なし ～ 1.0 = 演出が最大（テストからも見る）

var _tint: ColorRect


var _base := Vector3.ONE  # ふだんの 彩度・明るさ・コントラスト


func _ready() -> void:
	layer = LAYER_ORDER
	_tint = ColorRect.new()
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = SLOW_TINT
	add_child(_tint)
	if environment != null:
		environment.adjustment_enabled = true
		# ふだんの色調（世界の色づくり W-07 で決めた値）を覚えておき、スロー中はそこから変える
		_base = Vector3(environment.adjustment_saturation, environment.adjustment_brightness, environment.adjustment_contrast)
	_apply()


func _physics_process(_delta: float) -> void:
	var target := 1.0 if GameFeel.is_witch_time() else 0.0
	var step := 1.0 / float(SLOW_FADE_FRAMES)
	strength = move_toward(strength, target, step)
	_apply()


func _apply() -> void:
	_tint.visible = strength > 0.0
	_tint.color.a = SLOW_TINT.a * strength
	if environment != null:
		environment.adjustment_saturation = lerpf(_base.x, _base.x * SLOW_SATURATION, strength)
		environment.adjustment_brightness = lerpf(_base.y, _base.y * SLOW_BRIGHTNESS, strength)
		environment.adjustment_contrast = lerpf(_base.z, _base.z * SLOW_CONTRAST, strength)
