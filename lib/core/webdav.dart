import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'settings.dart';
import 'source.dart';

/// Synology の WebDAV Server で読む（Theta Music Hatch の WebDavClient を元に）。
/// WebDAV のルートに共有フォルダが並ぶので、パスは File Station と同じ（/video/…）。
class WebDavSource implements MediaSource {
  final AppSettings settings;
  final http.Client _c;
  WebDavSource(this.settings, [http.Client? client]) : _c = client ?? http.Client();

  Uri get base => Uri.parse(settings.davUrl.trim().replaceAll(RegExp(r'/+$'), ''));

  Map<String, String> get authHeaders => settings.user.isEmpty
      ? const {}
      : {'Authorization': 'Basic ${base64Encode(utf8.encode('${settings.user}:${settings.password}'))}'};

  Uri uriFor(String path) => base.replace(pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        ...path.split('/').where((s) => s.isNotEmpty),
      ]);

  static const _propfind = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getcontentlength/><d:getlastmodified/>'
      '</d:prop></d:propfind>';

  @override
  Future<void> check() async {
    if (settings.davUrl.trim().isEmpty) throw SourceException('WebDAV の URL が未設定です');
    await list('/');
  }

  @override
  Future<List<Entry>> list(String dir) async {
    final u = uriFor(dir);
    final req = http.Request('PROPFIND', u.replace(path: u.path.endsWith('/') ? u.path : '${u.path}/'))
      ..headers.addAll(authHeaders)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = _propfind;
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _c.send(req).timeout(const Duration(seconds: 30)));
    } on TimeoutException {
      throw SourceException('NAS が応答しません（Tailscale はつながっていますか？）');
    } catch (e) {
      throw SourceException('NAS につながりません: $e');
    }
    if (res.statusCode == 401) throw SourceException('ユーザー名かパスワードが違います（401）');
    if (res.statusCode == 404) throw SourceException('見つかりません: $dir');
    if (res.statusCode != 207 && res.statusCode != 200) throw SourceException('PROPFIND 失敗 (${res.statusCode})');
    final doc = XmlDocument.parse(utf8.decode(res.bodyBytes, allowMalformed: true));
    final prefix = _norm(base.path);
    final self = _norm(dir);
    final out = <Entry>[];
    for (final r in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'response')) {
      XmlElement? first(String local) =>
          r.descendants.whereType<XmlElement>().where((e) => e.name.local == local).firstOrNull;
      var href = first('href')?.innerText.trim() ?? '';
      if (href.isEmpty) continue;
      if (href.startsWith('http')) href = Uri.parse(href).path;
      var path = _norm(Uri.decodeFull(href));
      if (prefix != '/' && path.startsWith(prefix)) path = _norm(path.substring(prefix.length));
      if (path == self) continue;
      final isDir = first('resourcetype')?.descendants.whereType<XmlElement>().any((e) => e.name.local == 'collection') ??
          false;
      var mtime = 0;
      try {
        final m = first('getlastmodified')?.innerText.trim();
        if (m != null && m.isNotEmpty) mtime = HttpDate.parse(m).millisecondsSinceEpoch;
      } catch (_) {}
      out.add(Entry(path, isDir, int.tryParse(first('getcontentlength')?.innerText.trim() ?? '') ?? 0, mtime));
    }
    return out;
  }

  static String _norm(String p) {
    var s = p.replaceAll(RegExp(r'/+'), '/');
    if (s.length > 1 && s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (!s.startsWith('/')) s = '/$s';
    return s;
  }

  @override
  Future<Uint8List?> read(String path) async {
    final res = await _c.get(uriFor(path), headers: authHeaders).timeout(const Duration(seconds: 30));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw SourceException('GET 失敗 (${res.statusCode}): $path');
    return res.bodyBytes;
  }

  @override
  Future<StreamUrl> stream(String path) async => StreamUrl(uriFor(path).toString(), authHeaders);

  @override
  void close() {}
}
