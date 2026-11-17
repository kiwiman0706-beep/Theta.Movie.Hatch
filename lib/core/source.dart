import 'dart:typed_data';

/// NAS のフォルダの 1 項目
class Entry {
  final String path; // 共有フォルダからの絶対パス（/video/映画/…）。末尾の / なし
  final bool isDir;
  final int size;
  final int mtime; // ミリ秒（分からなければ 0）
  const Entry(this.path, this.isDir, this.size, this.mtime);
  String get name => path.substring(path.lastIndexOf('/') + 1);
}

class SourceException implements Exception {
  final String message;
  SourceException(this.message);
  @override
  String toString() => message;
}

/// 2 段階認証の確認コードが要る（または違う）
class OtpRequired extends SourceException {
  OtpRequired(super.message);
}

/// 再生に渡す URL と、付けるヘッダー
class StreamUrl {
  final String url;
  final Map<String, String> headers;
  const StreamUrl(this.url, [this.headers = const {}]);
}

/// 動画の読み先（DSM の File Station か WebDAV）。どちらも同じパス（/video/…）で扱う
abstract class MediaSource {
  /// フォルダ直下の一覧
  Future<List<Entry>> list(String dir);

  /// 小さなファイル（.nfo など）。無ければ null
  Future<Uint8List?> read(String path);

  /// 再生・ダウンロード用の URL（Range に対応した HTTP）
  Future<StreamUrl> stream(String path);

  /// 接続を確かめる（ログインまで）
  Future<void> check();

  void close() {}
}
