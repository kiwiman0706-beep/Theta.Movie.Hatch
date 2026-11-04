# Jellyfin セットアップ（DS1825+）

Movie Hatch のサーバー側。ライブラリ・メタデータ・配信・視聴履歴を Jellyfin に任せる。

- CPU: AMD Ryzen V1500B（内蔵GPUなし）→ ハードウェア変換なし。
  **ダイレクト再生（変換しない）前提**で運用する。Movie Hatch も mpv/VLC 内蔵でダイレクト再生を基本にする。
- 手順は `docker-compose.yml` のコメント参照。初回は `http://<NASのIP>:8096` で初期設定。
- 外から: Tailscale パッケージを入れ `http://<NAS名>:8096`（MagicDNS）。
