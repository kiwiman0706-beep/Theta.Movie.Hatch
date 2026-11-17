# Theta Movie Hatch

Synology の Video Station の代わりになる、NAS（DS1825+）の動画プレーヤー。Theta Hatch シリーズの 1 つ。

- **NAS で変換しない**：mpv（`media_kit`）を内蔵し、mkv・HEVC・DTS・ARIB 字幕・二か国語の .ts も端末でそのまま再生する（DS1825+ は内蔵 GPU が無く、変換が弱いため）
- **NAS を直接読む**：DSM の File Station（2 段階認証に対応・既定）か WebDAV。外からは Tailscale
- **ファイルが正本**：作品の並べ方と名前は [`docs/naming-convention.md`](docs/naming-convention.md)（Jellyfin・Plex・Kodi でもそのまま読める形）。情報は `.nfo` とポスター（`poster.jpg`）から
- Jellyfin は無くても動く。入れておけば公式アプリ・LG のテレビ（webOS）で同じライブラリを見られる（[`server/jellyfin/`](server/jellyfin/README.md)）

## できること（0.1.0）

- 棚（映画・アニメ映画・ドラマ・アニメ・テレビ・ライブ・ホームビデオ）ごとのポスターの一覧、最近追加、検索（題名・出演者・監督）
- 作品の画面：あらすじ・出演・シーズンと話・バージョン・特典映像・関連（同じ出演者・同じコレクション）
- 再生：続きから、次の話、音声（二か国語）と字幕の切り替え、ダブルタップで早送り・戻し
- 整理前のフォルダもできるだけ読む（`第5話`・`#12`・`S02E10`・放送日の名前、まとまりのフォルダ）
- シリーズの共通設定：スキン（`ui.skin`）、NAS の接続先・パスワード・2 段階認証のトークンを Theta Home Hatch から受け取る。更新は Home に頼む

次の版から：オフラインのキャッシュ → Theta Vault（視聴の記録・作品のノート）→ Video Station からの移行・整理ツール → Android TV → Windows・Mac（`progress/movie.md`）

## 使い方

1. 設定で「File Station」を選び、DSM の URL（例 `http://nas.tailXXXX.ts.net:5000`）・ユーザー名・パスワード・動画のフォルダ（既定 `/video`）を入れる。Theta Home Hatch があれば「Home Hatch の設定を使う」
2. 「接続を確かめる」。2 段階認証なら確認コードを 1 回入れる（次からは要らない）
3. ホームに戻ると NAS を読む。動画を足したら ⟳（または下に引っ張る）

## 作り

```
lib/core/   naming.dart（名前の読み取り）・scanner.dart（作品にまとめる）・nfo.dart
            dsm.dart（File Station）・webdav.dart・library.dart・progress.dart（続きから）
            series.dart（ハブとのやり取り。Android 側は Series.kt）
lib/ui/     home・shelf・title・player・settings、hud/（シリーズのスキン）
server/     Jellyfin（NAS に並べて入れる場合）
tools/      （次の版）Video Station からの移行・整理ツール
```

- スキンの色は `lib/ui/hud/skins.g.dart`（生成。`python tool/gen_skins.py <Theta.Hatch.Series>/design/skins/skins.json`）
- テスト：`flutter analyze`・`flutter test`（`test/fake_dsm.py` で DSM を真似た結合テストを含む。python3 が要る）
- Release：版（`pubspec.yaml`）を上げて既定ブランチに push すると `release.yml` が `v<版>` の Release を作る。署名はシリーズ共通の鍵（Secret 4 つ）。本文は `docs/releases/v<版>.md`
- APK は ARM だけ（`flutter build apk --release --target-platform android-arm,android-arm64`）
- 手元で署名するときは `android/key.properties`（Git 管理外）。無ければデバッグ鍵（ハブからは入らない）

## シリーズ

共通の仕様・スキン・鍵は [Theta.Hatch.Series](https://github.com/kiwiman0706-beep/Theta.Hatch.Series)。移行の方針と進み具合は `progress/movie.md`。
