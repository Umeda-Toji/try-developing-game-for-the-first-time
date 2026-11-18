# ParryProto（Godot 4.7.2 用・試作）

（キャラクターは Quaternius の CC0 モデル、部屋は箱）で「1部屋・ザコ1体・ボス1体」と戦える、パリィ／ジャスト回避／コンボ／体幹ブレイクの試作です。

## 開き方
1. Godot 4.7.2（標準版。.NET版でなくてOK）をダウンロード
2. Project Manager →「インポート」→ このフォルダの `project.godot` を選ぶ
3. F5 で実行

## 操作
| 操作 | キーボード/マウス | パッド（PlayStation表記） |
|---|---|---|
| 移動 | WASD | 左スティック |
| カメラ | マウス（矢印キー） | 右スティック |
| 通常攻撃（3段） | 左クリック / J | △ |
| 強攻撃（長押しで溜め） | 右クリック / K | □ |
| 回避（押し続けると走る） | Shift | R2 |
| ジャンプ（2回まで。2回跳んだ後に押し続けると滑空） | Space | × |
| パリィ | 攻撃キーの出始め | 攻撃ボタン（△ / □）の出始め |
| ロックオン | Tab / ホイールクリック | L2 |
| リトライ（勝敗の画面で） | R / 画面のボタン | × |
| ポーズ（再開／リトライ／終了） | Esc | OPTIONS |

- パリィ専用のボタンはありません。敵の攻撃に合わせて**攻撃すると、その出始め（9フレーム）がパリィ**になります。失敗しても普通に攻撃が出ます。コンボの2段目以降ではパリィになりません
- ロックオンしていなくても、攻撃すると近く（5m以内）の敵を自動で向きます（後ろの敵には振り向きません）
- 強攻撃は**押し続けると溜め**（オレンジ→最大で黄色）。離すと最大2倍の威力。溜め中は回避でやめられます
- ボスはHPが半分を切ると**第2形態**になります（速くなり、4連撃・フェイントも使う）
- ザコはときどき**フェイント攻撃**をします。溜めが長く、途中で一度ニセの白い光を出します。本物は2回目の光です
- 敵が **白く強く光ったら攻撃でパリィ**、**赤く光ったら回避**（パリィ不可）。攻撃の合図の間は、敵のまわりが赤く照らされます
- ボタンの割り当ては `scripts/main.gd` の `_setup_input_map()` で変えられます
- パリィ成功・ジャスト回避の直後は反撃が2倍（自キャラが少し光る）
- **スタミナ**（HPバーの下の黄色いバー）：回避で減り、走る・滑空の間も減ります（ジャンプでは減りません）。使わずにいると回復します。0 だと回避・走る・滑空ができません
- **壁のぼり**：空中で壁へ向かって進むとつかまります（前後で上下、左右で横）。上まで行くと登りきります。ジャンプで壁を蹴る、回避で手を離す。スタミナを使います
- **泳ぎ**：深い水に入ると泳ぎます。スタミナが切れると溺れて、最後に立っていた所へ戻ります（ダメージ）
- エリアのあちこちに看板・端末があり、近づくと短い文章が浮かびます
- エリアは「落ち高架 → 花梨通り → 止まり時計の広場 → 書店街の抜け道 → 旧市民ホール」の一本道。広場の敵を全部倒すとホールの扉が開きます（世界観は `docs/WORLD.md`）
- 攻撃を当てた（パリィした）敵の頭の上に、HPバー（赤）と体幹バー（オレンジ）が出ます
- 体幹ゲージが満タン → ブレイク（黄色）→ ダメージ1.5倍

## ファイル
```
project.godot                  設定（60tick固定・内蔵GPU向けの軽量設定）
scenes/main.tscn               起動シーン（中身は main.gd が組み立てる）
scripts/main.gd                ステージ・入力・HUDの組み立て
scripts/player/player.gd       プレイヤーの状態遷移・フレーム管理・先行入力
scripts/enemy/enemy.gd         敵/ボス（@exportの数値違いでボスになる）
scripts/combat/hitbox.gd       攻撃判定（1攻撃1ヒット）
scripts/combat/hurtbox.gd      被弾判定
scripts/combat/combat.gd       判定結果の定数
scripts/combat/game_feel.gd    手ごたえ（カメラ揺れ・敵だけスロー・火花の合図）※オートロード
scripts/combat/hit_sparks.gd   ヒット・パリィ・ブレイクの火花
scripts/combat/projectile.gd   魔法使いの弾（パリィで跳ね返る）
scripts/camera/camera_rig.gd   三人称カメラ・ロックオン・揺れ
scripts/ui/battle_hud.gd       HPバー・スタミナバー・体幹バー（ロックオン中の敵）
scripts/ui/enemy_bars.gd       敵の頭の上の体力バー
scripts/world/world_builder.gd 白砂市のエリアの配置（箱の表・敵の出る場所）
scripts/world/palette.gd       世界の色・光・霧（ここを変えると全体の色が変わる）
scripts/world/ruin_kit.gd      廃墟の見た目（窓・ツタ・瓦礫・草・木）の自動生成（シード固定）
shaders/ruin_pbr.gdshader      壁・地面の表面（写真テクスチャを三方向から貼る・苔・雨の跡。リアルな陰影）
scripts/world/world_materials.gd  材質（どのテクスチャを使うか）
scripts/game/graphics_settings.gd 画質の切り替え（高画質／軽い）
textures/                      写真から作ったテクスチャと空（Poly Haven、CC0）
models/nature/                 植物・石・倒れた木・街灯の3Dモデル（Poly Haven、CC0）
scripts/world/nature_kit.gd    植物・石・瓦礫・木・街灯を置く（シード固定）
scripts/world/shape_kit.gd     角を削った箱・ごつごつした塊・草や葉の画像をコードで作る
shaders/foliage.gdshader       草・葉（透明な所を切り抜く・風でゆれる・光が透ける）
tests/world_views.gd           景色の確認ツール（--world-views。場所ごとの FPS も出す）
scripts/world/water.gd         水（泳ぐ）
scripts/world/boss_door.gd     ホールの扉（広場の敵を全部倒すと開く）
scripts/world/sign_post.gd     看板・端末（近づくと設定文の短い文章が浮かぶ）
docs/WORLD.md                  世界観・設定文（緑の眠り）
scripts/ui/result_screen.gd    勝利／敗北の画面とリトライ
scripts/ui/pause_menu.gd       ポーズメニュー（クレジット画面もここから開く）
scripts/ui/credits.gd          クレジットの文章（ライセンス表記）
scripts/ui/credits_panel.gd    クレジットの画面（ポーズメニューとタイトル画面で共通）
scripts/ui/title_screen.gd     タイトル画面（ゲームの名前は GAME_TITLE。今は仮の名前）と難易度の選択
scripts/game/difficulty.gd     難易度の数値（やさしい／ふつう／むずかしい）
scripts/ui/slow_effect.gd      スロー中の画面演出（色を薄く・青く）
shaders/toon.gdshader          軽いトゥーンシェーダー
shaders/tint_overlay.gdshader  モデルに状態の色（パリィ受付の水色など）を重ねる
scripts/visual/character_model.gd  3Dモデルとアニメーション（見た目だけ。判定はフレームで決まる）
models/                        Quaternius の CC0 モデル・アニメーション（LICENSE_Quaternius_CC0.txt）
scripts/combat/sfx.gd          効果音（ヒット・パリィ・ジャスト回避・ブレイク）
sounds/                        効果音（Kenney の CC0。どのファイルを使うかは sfx.gd の SOUNDS 表）
scripts/audio/bgm.gd           BGM（通常の曲 → ボス第2形態で切り替え。音量は VOLUME_DB）
music/                         BGM（OpenGameArt の CC0。ループの設定は .import ファイル）
tests/autotest.gd              自動プレイ（動作確認用）
tests/retry_test.gd            敗北→リトライの確認（--retry-test）
tests/charge_test.gd           強攻撃の溜めの確認（--charge-test）
tests/soft_lock_test.gd        ソフトロックの確認（--soft-lock-test）
tests/feint_test.gd            フェイント攻撃の確認（--feint-test）
tests/phase2_test.gd           ボス第2形態の確認（--phase2-test）
tests/pause_test.gd            ポーズメニューの確認（--pause-test）
tests/model_test.gd            プレイヤーのモデルとアニメの確認（--model-test）
tests/enemy_model_test.gd      敵のモデルとアニメの確認（--enemy-model-test）
tests/title_test.gd            タイトル画面の確認（--title-test）
tests/difficulty_test.gd       難易度の確認（--difficulty-test）
tests/enemy_types_test.gd      重装兵・双剣士の確認（--enemy-types-test）
tests/ranged_test.gd           魔法使い・弾の跳ね返しの確認（--ranged-test）
tests/movement_test.gd         ジャンプ・滑空・走る・スタミナの確認（--movement-test）
tests/enemy_bars_test.gd       敵の頭の上の体力バーの確認（--enemy-bars-test）
tests/world_test.gd            白砂市のエリア・壁のぼり・泳ぎの確認（--world-test。これだけエリアで動く）
```

## 調整するならここ（すべてフレーム数 = 1/60秒）
- `player.gd` 上部の `PARRY_WINDOW_FRAMES`（パリィ受付）、`PERFECT_DODGE_FRAMES`（ジャスト回避）、`INPUT_BUFFER_FRAMES`（先行入力）
- `player.gd` の `ATTACKS` 表（発生・持続・硬直・キャンセル可能フレーム・ヒットストップ）
- `enemy.gd` の `@export`（予兆の長さ・光る長さ・連撃数）。ボスの値は `main.gd` の `_build_enemy("ボス", ...)`

## 自動テスト（任意）
```
godot --path . --headless --fixed-fps 60 -- --autotest
```

## 軽さの確認（FPS）
- 遊んでいるときは、画面の左上に FPS が出ます（60 以上なら目標どおり。上限は 240fps）
- 描画が速くても、攻撃や回避のタイミング（判定）は 1秒に60回の物理フレームで数えるので変わりません
- エリアの6か所を順に映して、場所ごとの FPS を出す確認ツールもあります（`parry_proto` フォルダで実行）：
  ```powershell
  C:\Users\umeji\Documents\Godot_v4.7.2-stable_win64_console.exe --path . -- --world-views
  ```
  - 最後に `--uncapped` を足すと、60fps の上限を外して「どれだけ余裕があるか」を測れます
  - さらに `--low`（軽い）か `--high`（高画質）を足すと、その画質で測ります（足さないときは、ポーズメニューで選んだ画質）
  - 11/18 のこのPC（Intel Arc）：6か所すべて 60fps。上限を外すと 高画質 78〜132fps／軽い 147〜417fps
- 重いときは、ポーズメニューの「画質」で「軽い」に切り替えてください
- 軽くするための工夫：草・瓦礫・窓などは種類ごとにまとめて描く（MultiMesh）、小物には当たり判定を付けない、遠くの小物は描かない、重い効果（SSAO・グローなど）は使わない

## .exe の書き出し（N-08）
- 設定は `export_presets.cfg`（Windows Desktop、64bit、ゲームのデータは .exe の中に入れる）
- エクスポートテンプレート（Godot 4.7.2 用）は `%APPDATA%\Godot\export_templates\4.7.2.stable` に入っている（Windows 用だけ）
- 書き出しコマンド（`parry_proto` フォルダで実行）：
  ```powershell
  C:\Users\umeji\Documents\Godot_v4.7.2-stable_win64_console.exe --path . --headless --export-release "Windows Desktop" ../build/ParryProto.exe
  ```
- エディタからなら「プロジェクト → エクスポート → Windows Desktop → プロジェクトのエクスポート」
- できた `build/ParryProto.exe` 1つだけを配れば遊べる（約130MB）

## ライセンス・クレジット
- このゲームは **Godot Engine**（MIT ライセンス）で作っています。
  Copyright (c) 2014-present Godot Engine contributors. / Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
- Godot のライセンス文の全文と、Godot が中で使っているソフトウェア（FreeType など）の表記は、
  **ゲーム内のポーズメニュー →「クレジット」** で見られます（`scripts/ui/credits.gd` が Godot から自動で取り出して表示）。
- プレイヤーの3Dモデルとアニメーションは **Quaternius**（https://quaternius.com）の Universal Base Characters ／ Universal Animation Library 1・2 です（プレイヤー・ボス＝Modular Character Outfits - Fantasy の Ranger の服＋素体の顔、ザコ＝アニメ素材のマネキン、剣・ハンマー・短剣＝LowPoly Medieval Weapons。CC0 1.0。表記は必須ではありませんが記載しています）。
- BGM は OpenGameArt の CC0 の曲です：「Battle Theme A」（作曲 Alex Smith／cynicmusic.com、pixelsphere.org。ループ版 Ferk）と「Epic Boss Battle」（Juhani Junkala）。
- 壁・地面のテクスチャ、空、植物・石・街灯の3Dモデルは **Poly Haven**（https://polyhaven.com）の CC0 素材です。
- 効果音は **Kenney**（https://kenney.nl）の Impact Sounds ／ RPG Audio です（CC0 1.0。表記は必須ではありませんが記載しています）。前の仮の音は `tools/placeholder_sounds/` に保管。
- 素材（音・モデルなど）を追加したら、`scripts/ui/credits.gd` の `CREDITS_HEAD` と、この README にクレジットを書き足してください。
