# Video Station のデータの書き出しを、ローカルの Claude Code に頼む文

自分の PC（Windows か Mac）で動く Claude Code に貼る。NAS（DS1825+）に SSH でつなげるようにしておく
（DSM の「コントロールパネル → 端末と SNMP → SSH サービスを有効にする」）。

---

Synology の Video Station のデータベースを、移行のために書き出したいです。手伝ってください。
**読むだけ**で、NAS の設定・Video Station・動画ファイルには何も変更を加えないでください。

## 背景

- NAS：Synology DS1825+（DS416play の HDD をそのまま差し替えた。Video Station は裏技のスクリプトで動かしている）
- Video Station のデータは、DSM の PostgreSQL のデータベース `video_metadata` にある（はず）
- 書き出したものは、Theta Movie Hatch（GitHub `kiwiman0706-beep/Theta.Movie.Hatch`）の移行ツールが読む

## やってほしいこと

1. SSH で NAS に入る手順を教えてください（ユーザー名・IP は私が入れます。パスワードは私が打ちます）
2. NAS の上で、次を順に実行してください（`sudo` のパスワードは私が入れます）
   - データベースの一覧：`sudo -u postgres psql -l`（`video_metadata` があるか）
   - 表の一覧：`sudo -u postgres psql -d video_metadata -c '\dt+'`
   - 各表の件数：`movie`・`tvshow`・`tvshow_episode`・`video_file`・`watch_status`・`collection` などの `select count(*)`（実際にある表で）
   - 構造だけ：`sudo -u postgres pg_dump -s video_metadata > ~/video_metadata.schema.sql`
   - 全部（復元用）：`sudo -u postgres pg_dump -Fc video_metadata > ~/video_metadata.dump`
   - 全部（読める形）：`sudo -u postgres pg_dump -Fp video_metadata > ~/video_metadata.sql`
3. 3 つのファイルを PC にコピーしてください（`scp`。置き場所は `ドキュメント\VideoStation\`）。大きさも教えてください
4. 表の一覧・件数・`video_metadata.schema.sql` の中身（構造だけ）を、まとめて見せてください。私がそれを Theta Movie Hatch のスレッドに貼ります

## 守ってほしいこと

- データベースに書き込む SQL（`insert`・`update`・`delete`・`drop` など）は実行しない
- Video Station のパッケージ・裏技のスクリプトには触らない
- パスワードを画面やファイルに残さない
- `pg_dump` が見つからない・権限で失敗したら、無理をせずエラーをそのまま見せてください
