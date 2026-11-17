# 検証の記録

## 確かめたこと（クラウドのスレッド、実機なし）

- `flutter analyze`：指摘なし
- `flutter test`：名前の読み取り（規則どおり・整理前）、NFO、作品へのまとめ方（映画・パート・特典・シリーズ・特別編・放送日の番組・まとまりの中・ホームビデオ・隠しフォルダ）、キャッシュの往復
- DSM の真似（`test/fake_dsm.py`）との結合：2 段階認証（コード違い → 正しいコード → デバイストークンで次から省ける）、File Station の一覧、NFO の読み取り、再生用 URL の Range（206）
- `flutter build apk --release --target-platform android-arm,android-arm64`（デバッグ鍵）：`app.thetahatch.movie`・0.1.0、60.9MB（ARM だけ）

## 未確認（実機で確かめる）

- [ ] 本物の DSM 7 の File Station で、再生用 URL（`SYNO.FileStation.Download`・`mode=open`）が Range に応えて、シーク・続きからが効く
- [ ] Tailscale 経由で 10 分以上止まらずに再生できる（Video Station の裏技で止まっていた症状）
- [ ] mkv（HEVC 10bit）・.ts（ARIB 字幕・二か国語）・DTS が端末で再生でき、音声・字幕を切り替えられる
- [ ] WebDAV Server での一覧・再生（2 段階認証のアカウントで通るか）
- [ ] Theta Home Hatch から NAS の設定（URL・ユーザー・パスワード・デバイストークン）を受け取れる。借りたトークンで確認コードが省けるか
- [ ] スキンが Home の `ui.skin` に追従する
- [ ] 「更新する」が Home の更新画面を開く
- [ ] 数千本のライブラリでの読み込みの時間
