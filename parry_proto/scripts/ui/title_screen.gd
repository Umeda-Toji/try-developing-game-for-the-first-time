# Godot 4.7.2 / GDScript
# res://scripts/ui/title_screen.gd
#
# タイトル画面（U-06）
#  ・ゲームを起動したときに出る。開いている間はゲームを一時停止する（後ろに戦う場所がうっすら見える）
#  ・ボタン：はじめる／クレジット／終了。マウスでも、パッドの上下＋×でも選べる
#  ・「はじめる」→ 難易度（やさしい／ふつう／むずかしい）を選ぶ → 始まる（U-07）。最初は「ふつう」が選ばれている
#  ・クレジットはポーズメニューと同じ画面（CreditsPanel）。Esc／○で戻る
#  ・リトライしたときは出さない（main.gd が決める）
#  ・ゲームの名前は GAME_TITLE。まだ仮の名前（REQUIREMENTS.md 9章の未決定事項）
#  ・ノードはすべてコードで組み立てる
class_name TitleScreen
extends CanvasLayer

signal start_requested(difficulty: String)  # 選んだ難易度（Difficulty.EASY など）
signal quit_requested
signal continue_requested   # 「つづきから」（セーブ S-01）

# ---- 見た目の数値 ----
const GAME_TITLE := "ParryProto"            # 仮の名前。決まったらここを変える
const SUBTITLE := "― パリィアクション 試作版 ―"
const LAYER_ORDER := 30                      # ポーズメニュー（20）・結果画面（10）より手前
const TITLE_FONT_SIZE := 88
const SUBTITLE_FONT_SIZE := 22
const HINT_FONT_SIZE := 16
const BUTTON_SIZE := Vector2(260, 56)
const COLOR_BG := Color(0.03, 0.04, 0.08, 0.6)    # 後ろの画面を暗くする（戦う場所がうっすら見える）
const COLOR_TITLE := Color(0.85, 0.95, 1.0)
const COLOR_TITLE_OUTLINE := Color(0.1, 0.55, 0.75)  # パリィの水色に合わせる
const COLOR_SUBTITLE := Color(0.75, 0.8, 0.9)
const HINT_TEXT := "白く光ったら攻撃でパリィ ／ 赤く光ったら回避\n[マウス左/J/△]攻撃　[マウス右/K/□]強攻撃　[Shift/R2]回避　[Space/×]ジャンプ　[Tab/L2]ロックオン"

var is_open := false
var credits_open := false
var difficulty_open := false
var difficulty_buttons := {}   # 難易度 → ボタン
var start_button: Button
var continue_button: Button
var confirm_open := false     # 「はじめから」の確かめる画面が出ているか
var confirm_yes: Button
var confirm_no: Button
var _confirm: Control
var credits_button: Button
var quit_button: Button
var credits_panel: CreditsPanel

var _menu: Control
var _difficulty_menu: Control
var _difficulty_note: Label


func _ready() -> void:
	layer = LAYER_ORDER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _process(_delta: float) -> void:
	if not is_open:
		return
	var back := Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("ui_cancel")
	if confirm_open and back:
		close_confirm()
	elif credits_open and back:
		close_credits()
	elif difficulty_open and back:
		close_difficulty()


func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# セーブがあれば「つづきから」を出して、最初に選んでおく。「はじめる」は「はじめから」になる
	var saved := Discoveries.has_save()
	continue_button.visible = saved
	start_button.text = "はじめから" if saved else "はじめる"
	(continue_button if saved else start_button).grab_focus()  # パッドの×ですぐ始められるように


func close() -> void:
	if confirm_open:
		close_confirm()
	if credits_open:
		close_credits()
	if difficulty_open:
		close_difficulty()
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# 「はじめる」／「はじめから」：セーブがあるときは、消してよいか確かめる
func _on_start_pressed() -> void:
	if Discoveries.has_save():
		open_confirm()
	else:
		open_difficulty()


func open_confirm() -> void:
	confirm_open = true
	_menu.visible = false
	_confirm.visible = true
	confirm_no.grab_focus()  # まちがえて消さないように、「いいえ」を選んでおく


func close_confirm() -> void:
	confirm_open = false
	_confirm.visible = false
	_menu.visible = true
	start_button.grab_focus()


# 「はい」：セーブを消して、難易度を選ぶ
func _confirm_new_game() -> void:
	Discoveries.delete_save()
	confirm_open = false
	_confirm.visible = false
	continue_button.visible = false
	start_button.text = "はじめる"
	open_difficulty()


# 難易度を選ぶ画面
func open_difficulty() -> void:
	difficulty_open = true
	_menu.visible = false
	_difficulty_menu.visible = true
	difficulty_buttons[Difficulty.current].grab_focus()  # 前に選んだ難易度（最初は「ふつう」）


func close_difficulty() -> void:
	difficulty_open = false
	_difficulty_menu.visible = false
	_menu.visible = true
	start_button.grab_focus()


func choose_difficulty(id: String) -> void:
	start_requested.emit(id)


func open_credits() -> void:
	credits_open = true
	_menu.visible = false
	credits_panel.open()


func close_credits() -> void:
	credits_open = false
	credits_panel.close()
	_menu.visible = true
	credits_button.grab_focus()


# =========================================================
# 組み立て
# =========================================================
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu = center

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = GAME_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.add_theme_color_override("font_outline_color", COLOR_TITLE_OUTLINE)
	title.add_theme_constant_override("outline_size", 12)
	box.add_child(title)

	var sub := Label.new()
	sub.text = SUBTITLE
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", SUBTITLE_FONT_SIZE)
	sub.add_theme_color_override("font_color", COLOR_SUBTITLE)
	box.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	box.add_child(gap)

	continue_button = _make_button("つづきから", func() -> void: continue_requested.emit())
	box.add_child(continue_button)
	start_button = _make_button("はじめる", _on_start_pressed)
	credits_button = _make_button("クレジット", open_credits)
	quit_button = _make_button("終了", func() -> void: quit_requested.emit())
	for b in [start_button, credits_button, quit_button]:
		box.add_child(b)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 20)
	box.add_child(gap2)

	var hint := Label.new()
	hint.text = HINT_TEXT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_color", COLOR_SUBTITLE)
	box.add_child(hint)

	_build_difficulty_menu()
	_build_confirm()

	credits_panel = CreditsPanel.new()
	credits_panel.back_pressed.connect(close_credits)
	add_child(credits_panel)


func _build_difficulty_menu() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	add_child(center)
	_difficulty_menu = center
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var head := Label.new()
	head.text = "難易度を選ぶ"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 40)
	head.add_theme_color_override("font_color", COLOR_TITLE)
	head.add_theme_color_override("font_outline_color", COLOR_TITLE_OUTLINE)
	head.add_theme_constant_override("outline_size", 8)
	box.add_child(head)

	for id in Difficulty.ORDER:
		var b := _make_button(Difficulty.label(id), choose_difficulty.bind(id))
		# 選んでいる難易度の説明を下に出す（マウスを乗せたときも）
		b.focus_entered.connect(func() -> void: _difficulty_note.text = Difficulty.SETTINGS[id]["note"])
		b.mouse_entered.connect(func() -> void: _difficulty_note.text = Difficulty.SETTINGS[id]["note"])
		box.add_child(b)
		difficulty_buttons[id] = b

	_difficulty_note = Label.new()
	_difficulty_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_note.custom_minimum_size = Vector2(560, 0)
	_difficulty_note.add_theme_font_size_override("font_size", HINT_FONT_SIZE + 2)
	_difficulty_note.add_theme_color_override("font_color", COLOR_SUBTITLE)
	box.add_child(_difficulty_note)

	var back := _make_button("戻る（Esc ／ ○）", close_difficulty)
	back.custom_minimum_size = Vector2(BUTTON_SIZE.x, 44)
	back.add_theme_font_size_override("font_size", 18)
	box.add_child(back)


# 「はじめから」の確かめる画面
func _build_confirm() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.visible = false
	add_child(center)
	_confirm = center
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var head := Label.new()
	head.text = "セーブを消して、はじめから遊びますか？\n（見つけたもの・強化は、すべてなくなります）"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", COLOR_TITLE)
	head.add_theme_color_override("font_outline_color", COLOR_TITLE_OUTLINE)
	head.add_theme_constant_override("outline_size", 8)
	box.add_child(head)
	confirm_yes = _make_button("はい（セーブを消す）", _confirm_new_game)
	confirm_no = _make_button("いいえ", close_confirm)
	box.add_child(confirm_yes)
	box.add_child(confirm_no)


func _make_button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_pressed)
	return b
