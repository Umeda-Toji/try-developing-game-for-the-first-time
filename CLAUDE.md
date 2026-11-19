# CLAUDE.md（このプロジェクトでの約束）

- このプロジェクトは **Godot 4.7.2-stable / GDScript** の三人称パリィアクションの試作です。
- 仕様と進み具合は **`REQUIREMENTS.md`** にあります。作業の前に必ず読んでください。
- タイミングの判定は、すべて物理フレーム（60tick）で数えます。秒数や `delta` で判定しないでください。
- `REQUIREMENTS.md` 5章の数値を変える前に、理由を説明して確認を取ってください。
- 変更したら、自動テストを実行して結果を報告してください。
  `C:\Users\umeji\Desktop\Godot_v4.7.2-stable_win64.exe --path . --headless --fixed-fps 60 -- --autotest`
  最後の `--autotest` を `--retry-test`（敗北・リトライ）、`--charge-test`（強攻撃の溜め）、`--soft-lock-test`（ソフトロック）、`--feint-test`（フェイント攻撃）、`--phase2-test`（ボス第2形態）、`--pause-test`（ポーズメニュー）、`--model-test`（プレイヤーのモデル）、`--enemy-model-test`（敵のモデル）、`--title-test`（タイトル画面）、`--difficulty-test`（難易度）、`--enemy-types-test`（重装兵・双剣士）、`--ranged-test`（魔法使い）、`--movement-test`（ジャンプ・滑空・走る・スタミナ）、`--enemy-bars-test`（敵の体力バー）、`--world-test`（白砂市のエリア・壁のぼり・泳ぎ）、`--items-test`（回復・強化アイテム）、`--side-enemies-test`（街の寄り道の敵）、`--vista-test`（眺めのいい場所）、`--save-test`（セーブ）、`--map-test`（地図）、`--settings-test`（設定）、`--lockon-test`（ロックオンの切り替え）、`--flower-test`（敵の頭の花）、`--sound-test`（探索の曲・環境音・花の音）、`--weapon-test`（武器の持ち替え・武器の輪）、`--gun-test`（撃つ・構え・反動・リロード）、`--terrain-test`（起伏のある地面）、`--hints-test`（操作のヒント・操作の一覧）に変えたものも実行する。
  （`parry_proto` フォルダで実行する。初回やクラス名エラーが出たときは、先に `--path . --headless --import` を1回実行する）
- コメントは日本語で書いてください。わからないこと・未決定のことは質問してください。
- 作業が終わったら、`REQUIREMENTS.md` の「状態」欄を更新してください。
