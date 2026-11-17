# Theta Movie Hatch

NAS（Synology DS1825+）の動画を、変換せずに端末で再生するプレーヤー（Flutter＋mpv）。Video Station の代わり。
詳しくは README.md、実機で確かめていないことは TESTING.md。

- アプリ ID `app.thetahatch.movie`。Release は既定ブランチへの push で `release.yml` が作る（版は `pubspec.yaml`、本文は `docs/releases/v<版>.md`）
- 作品の並べ方と名前の正本は `docs/naming-convention.md`（Theta.Hatch.Series の `spec/THETA_LIBRARY_SPEC.md` から参照されているので、場所を変えない）
- Flutter 3.50 からは `package:material_ui/material_ui.dart`（`flutter/material.dart` は非推奨）。`Title` が models.dart とぶつかるので `hide Title`
- スキンの色は `lib/ui/hud/skins.g.dart`（手で直さない。`python tool/gen_skins.py <Theta.Hatch.Series>/design/skins/skins.json`）
- テスト：`flutter analyze`・`flutter test`（`test/fake_dsm.py` で DSM を真似た結合テスト）

## Theta Hatch シリーズ共通（必ず参照）

このアプリは Theta Hatch シリーズの 1 つです。シリーズ共通の仕様・デザイン・鍵の決まりは
GitHub の kiwiman0706-beep/Theta.Hatch.Series にあり、このリポジトリの docs より優先します。

- 作業を始める前に、Theta.Hatch.Series を読める状態にする
  （クラウドのスレッドでは add_repo で kiwiman0706-beep/Theta.Hatch.Series を追加して clone する）
- 読むもの：
  - `spec/THETA_HATCH_SPEC.md`（共通仕様）、`spec/THETA_VAULT_SPEC.md`、`spec/THETA_SHARED_SETTINGS.md`、`spec/THETA_GOOGLE_SETUP.md`
  - `design/README.md`（スキン：system・dark・light・pop・alert・scifi。色は `design/skins/skins.json`）
  - `spec/THETA_HATCH_SPEC.md` §6.1（アプリ内自動更新は必須）、`docs/MIGRATION.md`・`catalog/apps.json`（このアプリの目標の ID・リポジトリ名）
  - `secrets/README.md`（署名鍵はシリーズ共通。Secret の名前は ANDROID_KEYSTORE_B64・ANDROID_KEYSTORE_PASSWORD・ANDROID_KEY_ALIAS・ANDROID_KEY_PASSWORD）
- 共通仕様の写しをこのリポジトリに増やさない（変えるときは Theta.Hatch.Series 側を直す）
- 鍵・パスワード・API キーをリポジトリに入れない
- 移行や大きな変更の方針と進み具合は、Theta.Hatch.Series の `progress/<id>.md` に書く（書き方は `progress/_TEMPLATE.md`。自分のアプリのファイルだけを触る）
- 作品の版や概要が変わったら、Theta.Hatch.Series の README の一覧も直す
