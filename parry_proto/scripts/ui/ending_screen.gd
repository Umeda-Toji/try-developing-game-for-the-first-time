# Godot 4.7.2 / GDScript
# res://scripts/ui/ending_screen.gd
#
# エンディング（U-12。11/20 決定）：白砂市のエリアで母株（ボス）を倒したあとに出す
#  1. 画面がゆっくり黒くなる
#  2. 黒の上に、文章（案A「外套を返す」）を1行ずつ出す。ひとまとまり出したら消して、次へ
#  3. スタッフロール：使った素材のクレジット → 最後に「見つけたもの」の数。下から上へ流す
#  4. 終わったら finished を出す（main.gd が、母株のいない街のホールから続きを始める）
#  ・攻撃／ジャンプ／決定を押し続けると早送り（SPEED_UP 倍）。Esc／OPTIONS／○ で今の部分をとばす
#  ・ゲームを止めて出す（process_mode = ALWAYS）。すべてフレームで数える
class_name EndingScreen
extends CanvasLayer

signal finished

const LAYER_ORDER := 12              # 結果画面・ポーズより手前
const FADE_IN_FRAMES := 120          # 黒くなるまで
const LINE_FADE_FRAMES := 40         # 1行が浮かぶまで
const LINE_GAP_FRAMES := 100         # 次の行を出すまで
const BLOCK_HOLD_FRAMES := 150       # ひとまとまり出し終えてから消すまで
const BLOCK_FADE_FRAMES := 50        # ひとまとまりが消えるまで
const ROLL_WAIT_FRAMES := 60         # 文章が終わってから、スタッフロールを流すまで
const ROLL_SPEED := 1.0              # スタッフロールの流れる速さ（1フレームに何ピクセル）
const END_HOLD_FRAMES := 180         # 流れ終わって、最後の数を見せておく長さ
const END_FADE_FRAMES := 60          # 最後に暗くして終える
const SPEED_UP := 4                  # 押し続けたときの早送り
const TEXT_FONT_SIZE := 26
const ROLL_FONT_SIZE := 19
const TEXT_COLOR := Color(0.92, 0.9, 0.84)

# 文章（案A「外套を返す」）。ひとまとまりごとに分ける
const BLOCKS := [
	["母株は焼けた。", "根がほどけ、街の苗人は、立ったまま枯れていった。"],
	["ホールの奥に、燃え残った外套があった。", "三年前に戻らなかった刈り手のものだ。"],
	["帰ったら返す、と手帳には書いてあった。", "返す相手は、もういない。"],
	["白砂市の春は、静かに終わった。"],
]

enum Phase { HIDDEN, FADE_IN, TEXT, ROLL_WAIT, ROLL, END_HOLD, END_FADE, DONE }

var phase := Phase.HIDDEN
var block_index := 0                 # 今出しているまとまり
var lines_shown := 0                 # そのまとまりで出した行の数
var _t := 0                          # 今の部分の中のフレーム
var elapsed_steps := 0               # 進んだフレームの合計（早送りでは1フレームに SPEED_UP 進む。テスト用）
var _block_fading := false
var _black: ColorRect
var _text_box: VBoxContainer
var _line_labels: Array[Label] = []
var _roll_clip: Control
var roll_label: Label                # スタッフロールの文（テストで中身を確かめる）
var _hint: Label
var _shade: ColorRect                # 最後に暗くする


func _ready() -> void:
	layer = LAYER_ORDER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func is_open() -> bool:
	return phase != Phase.HIDDEN and phase != Phase.DONE


# 始める。見つけたものの数は、このときの数を使う
func open() -> void:
	roll_label.text = _roll_text()
	visible = true
	phase = Phase.FADE_IN
	_t = 0
	block_index = 0
	lines_shown = 0
	_black.modulate.a = 0.0
	_shade.modulate.a = 0.0
	_roll_clip.visible = false
	_clear_lines()


func _physics_process(_delta: float) -> void:
	if not is_open():
		return
	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("ui_cancel"):
		skip()
		return
	var steps := SPEED_UP if _fast_held() else 1
	for i in steps:
		_step()
		if not is_open():
			return


func _fast_held() -> bool:
	return Input.is_action_pressed("attack_light") or Input.is_action_pressed("jump") or Input.is_action_pressed("ui_accept")


# 今の部分をとばす（文章 → スタッフロール → 終わり）
func skip() -> void:
	match phase:
		Phase.FADE_IN, Phase.TEXT, Phase.ROLL_WAIT:
			_black.modulate.a = 1.0
			_clear_lines()
			_start_roll()
		_:
			_finish()


# 1フレームぶん進める
func _step() -> void:
	_t += 1
	elapsed_steps += 1
	match phase:
		Phase.FADE_IN:
			_black.modulate.a = clampf(float(_t) / FADE_IN_FRAMES, 0.0, 1.0)
			if _t >= FADE_IN_FRAMES:
				_begin_block()
		Phase.TEXT:
			_step_text()
		Phase.ROLL_WAIT:
			if _t >= ROLL_WAIT_FRAMES:
				_start_roll()
		Phase.ROLL:
			roll_label.position.y -= ROLL_SPEED
			if roll_label.position.y + roll_label.size.y <= _roll_clip.size.y * 0.5 + roll_label.get_line_height() * 4:
				phase = Phase.END_HOLD
				_t = 0
		Phase.END_HOLD:
			if _t >= END_HOLD_FRAMES:
				phase = Phase.END_FADE
				_t = 0
		Phase.END_FADE:
			_shade.modulate.a = clampf(float(_t) / END_FADE_FRAMES, 0.0, 1.0)
			if _t >= END_FADE_FRAMES:
				_finish()


func _step_text() -> void:
	var block: Array = BLOCKS[block_index]
	# 行が浮かぶ
	for i in _line_labels.size():
		var shown_at := i * LINE_GAP_FRAMES
		if not _block_fading:
			_line_labels[i].modulate.a = clampf(float(_t - shown_at) / LINE_FADE_FRAMES, 0.0, 1.0)
	lines_shown = mini(block.size(), _t / LINE_GAP_FRAMES + 1)
	var all_shown_at := (block.size() - 1) * LINE_GAP_FRAMES + LINE_FADE_FRAMES
	if not _block_fading and _t >= all_shown_at + BLOCK_HOLD_FRAMES:
		_block_fading = true
		_t = 0
		return
	if _block_fading:
		var a := 1.0 - clampf(float(_t) / BLOCK_FADE_FRAMES, 0.0, 1.0)
		for l in _line_labels:
			l.modulate.a = minf(l.modulate.a, a)
		if _t >= BLOCK_FADE_FRAMES:
			block_index += 1
			if block_index >= BLOCKS.size():
				_clear_lines()
				phase = Phase.ROLL_WAIT
				_t = 0
			else:
				_begin_block()


func _begin_block() -> void:
	phase = Phase.TEXT
	_t = 0
	_block_fading = false
	lines_shown = 0
	_clear_lines()
	for s in BLOCKS[block_index]:
		var l := Label.new()
		l.text = s
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
		l.add_theme_color_override("font_color", TEXT_COLOR)
		l.modulate.a = 0.0
		_text_box.add_child(l)
		_line_labels.append(l)


func _clear_lines() -> void:
	for l in _line_labels:
		l.queue_free()
	_line_labels.clear()


func _start_roll() -> void:
	phase = Phase.ROLL
	_t = 0
	_roll_clip.visible = true
	roll_label.size = Vector2(_roll_clip.size.x, roll_label.get_combined_minimum_size().y)
	roll_label.position = Vector2(0.0, _roll_clip.size.y)


func _finish() -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	_shade.modulate.a = 1.0
	finished.emit()


# スタッフロールの文：素材のクレジット → 見つけたもの（作った人の名前は出さない。11/20 決定）
func _roll_text() -> String:
	var s := Credits.CREDITS_HEAD.strip_edges()
	s += "\n\n■ Godot Engine\nMIT ライセンス（ライセンス文は、ポーズメニューの「クレジット」で読めます）"
	s += "\n\n\n\n■ 見つけたもの\n" + Discoveries.summary_text()
	s += "\n\n\n\nあそんでくれて、ありがとう。"
	return s


func _build() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_black)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_text_box = VBoxContainer.new()
	_text_box.add_theme_constant_override("separation", 16)
	center.add_child(_text_box)

	_roll_clip = Control.new()
	_roll_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roll_clip.clip_contents = true
	_roll_clip.visible = false
	add_child(_roll_clip)
	roll_label = Label.new()
	roll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roll_label.add_theme_font_size_override("font_size", ROLL_FONT_SIZE)
	roll_label.add_theme_color_override("font_color", TEXT_COLOR)
	roll_label.anchor_right = 1.0
	_roll_clip.add_child(roll_label)

	_hint = Label.new()
	_hint.text = "押し続けて早送り（攻撃・ジャンプ）　Esc ／ OPTIONS でとばす"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.58))
	# 右上に出す（下に出すと、流れてくるスタッフロールと重なるため）
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.offset_right = -24
	_hint.offset_top = 16
	add_child(_hint)

	_shade = ColorRect.new()
	_shade.color = Color.BLACK
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
