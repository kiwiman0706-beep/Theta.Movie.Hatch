import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'settings.dart';
import 'source.dart';

/// DSM の File Station で NAS の動画を読む（Theta Music Hatch の DsAudioClient と同じログイン手順）。
/// SYNO.API.Info で API の場所 → SYNO.API.Auth でログイン。2 段階認証（Secure SignIn の確認コード）は
/// 初回だけコードを入れ、以後はデバイストークン（did）で通す（THETA_SHARED_SETTINGS.md §4.1 nas.deviceToken）。
class DsmSource implements MediaSource {
  final AppSettings settings;
  final http.Client _c;
  Map<String, dynamic>? _apis;
  String? _sid;
  String? _otp;
  Future<void>? _logging;

  DsmSource(this.settings, [http.Client? client]) : _c = client ?? http.Client();

  /// 「100.1.2.3」のように方式を省いたときは DSM の既定（http, 5000）を補う
  static String normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      final slash = u.indexOf('/');
      final host = slash < 0 ? u : u.substring(0, slash);
      final rest = slash < 0 ? '' : u.substring(slash);
      u = 'http://$host${host.contains(':') ? '' : ':5000'}$rest';
    }
    return u;
  }

  String get base => normalize(settings.dsUrl);

  /// 次のログインで 1 回だけ使う確認コード
  void setOtp(String? code) {
    _otp = (code == null || code.trim().isEmpty) ? null : code.trim();
    if (_otp != null) _sid = null;
  }

  void reset() {
    _sid = null;
    _apis = null;
  }

  /// つながらない・途中で切れた（Tailscale の揺れ、DSM が接続を閉じた）ときは、少し待って 3 回までやり直す
  Future<Map<String, dynamic>> _postJson(String url, Map<String, String> form, {Duration? timeout, int tries = 3}) async {
    http.Response? res;
    for (var i = 0;; i++) {
      try {
        res = await _c.post(Uri.parse(url), body: form).timeout(timeout ?? const Duration(seconds: 20));
        if (res.statusCode >= 500 && i + 1 < tries) {
          await Future<void>.delayed(Duration(milliseconds: 800 * (i + 1) * (i + 1)));
          continue;
        }
        break;
      } catch (e) {
        if (i + 1 >= tries) {
          if (e is TimeoutException) throw SourceException('NAS が応答しません（Tailscale はつながっていますか？）');
          throw SourceException('NAS につながりません: $e');
        }
        await Future<void>.delayed(Duration(milliseconds: 800 * (i + 1) * (i + 1)));
      }
    }
    if (res.statusCode != 200) throw SourceException('DSM HTTP ${res.statusCode}');
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw SourceException('DSM の応答ではありません');
    }
  }

  Map<String, dynamic> _api(String name) {
    final a = _apis?[name];
    if (a is! Map<String, dynamic>) throw SourceException('$name が使えません');
    return a;
  }

  int _ver(String name, int want) {
    final a = _api(name);
    final max = a['maxVersion'] as int? ?? want;
    final min = a['minVersion'] as int? ?? 1;
    return want.clamp(min, max);
  }

  String _url(String name) => '$base/webapi/${_api(name)['path'] ?? 'entry.cgi'}';

  @override
  Future<void> check() => ensureLogin();

  Future<void> ensureLogin() {
    if (_sid != null) return Future.value();
    return _logging ??= _login().whenComplete(() => _logging = null);
  }

  Future<void> _login() async {
    if (base.isEmpty) throw SourceException('NAS の URL が未設定です');
    const q = {'api': 'SYNO.API.Info', 'version': '1', 'method': 'query', 'query': 'all'};
    Map<String, dynamic> info;
    try {
      info = await _postJson('$base/webapi/query.cgi', q, timeout: const Duration(seconds: 8), tries: 2);
    } on SourceException {
      info = await _postJson('$base/webapi/entry.cgi', q, timeout: const Duration(seconds: 8), tries: 2);
    }
    _apis = info['data'] as Map<String, dynamic>?;
    if (_apis == null || !_apis!.containsKey('SYNO.API.Auth')) throw SourceException('DSM の応答ではありません');
    if (settings.password.isEmpty) throw SourceException('パスワードが未設定です');
    final did = settings.did;
    final twoStep = _otp != null || did.isNotEmpty;
    final p = <String, String>{
      'api': 'SYNO.API.Auth',
      'version': '${_ver('SYNO.API.Auth', twoStep ? 6 : 3)}',
      'method': 'login',
      'account': settings.user,
      'passwd': settings.password,
      'session': 'FileStation',
      'format': 'sid',
    };
    if (_otp != null) {
      p['otp_code'] = _otp!;
      p['enable_device_token'] = 'yes';
      p['device_name'] = 'ThetaMovieHatch';
    } else if (did.isNotEmpty) {
      p['device_id'] = did;
      p['device_name'] = 'ThetaMovieHatch';
    }
    _otp = null;
    // ログインはやり直さない（失敗が続くと NAS が一時的に拒否するため）
    final r = await _postJson(_url('SYNO.API.Auth'), p, tries: 1);
    if (r['success'] != true) {
      final code = (r['error'] as Map?)?['code'] as int? ?? 0;
      if (code == 403 || code == 406) {
        settings.did = '';
        await settings.save();
        throw OtpRequired('2 段階認証の確認コードを入れてください（1 回入れれば、この端末は次から要りません）');
      }
      if (code == 404) throw OtpRequired('確認コードが違います');
      throw SourceException(switch (code) {
        400 => 'アカウントかパスワードが違います',
        401 => 'アカウントが無効です',
        402 => 'File Station を使う権限がありません',
        407 => 'ログインの失敗が続いたため、NAS が一時的に拒否しています',
        _ => 'ログインエラー $code',
      });
    }
    final data = r['data'] as Map<String, dynamic>;
    _sid = data['sid'] as String;
    final newDid = (data['did'] ?? data['device_id'] ?? '') as String;
    if (newDid.isNotEmpty && newDid != settings.did) {
      settings.did = newDid;
      await settings.save();
    }
  }

  /// API を呼ぶ。セッション切れ（105〜107・119）なら 1 回だけログインし直す
  Future<Map<String, dynamic>> call(String api, String method, Map<String, String> params, {int version = 2}) async {
    for (var attempt = 0;; attempt++) {
      await ensureLogin();
      final p = {...params, 'api': api, 'version': '${_ver(api, version)}', 'method': method, '_sid': _sid!};
      final r = await _postJson(_url(api), p, timeout: const Duration(seconds: 60));
      if (r['success'] == true) return (r['data'] as Map<String, dynamic>?) ?? {};
      final code = (r['error'] as Map?)?['code'] as int? ?? 0;
      if (attempt == 0 && (code == 105 || code == 106 || code == 107 || code == 119)) {
        _sid = null;
        continue;
      }
      if (code == 408) throw SourceException('見つかりません: ${params['folder_path'] ?? params['path'] ?? ''}');
      throw SourceException('DSM エラー $code ($api.$method)');
    }
  }

  @override
  Future<List<Entry>> list(String dir) async {
    const page = 1000;
    final out = <Entry>[];
    for (var offset = 0;; offset += page) {
      final d = await call('SYNO.FileStation.List', 'list', {
        'folder_path': dir,
        'offset': '$offset',
        'limit': '$page',
        'additional': jsonEncode(['size', 'time']),
      });
      final files = (d['files'] as List?) ?? const [];
      for (final f in files.cast<Map<String, dynamic>>()) {
        final add = (f['additional'] as Map<String, dynamic>?) ?? const {};
        final time = (add['time'] as Map<String, dynamic>?) ?? const {};
        out.add(Entry(
          f['path'] as String,
          f['isdir'] == true,
          (add['size'] as num?)?.toInt() ?? 0,
          ((time['mtime'] as num?)?.toInt() ?? 0) * 1000,
        ));
      }
      final total = d['total'] as int? ?? out.length;
      if (files.isEmpty || out.length >= total) break;
    }
    return out;
  }

  Uri _downloadUri(String path) => Uri.parse(_url('SYNO.FileStation.Download')).replace(queryParameters: {
        'api': 'SYNO.FileStation.Download',
        'version': '${_ver('SYNO.FileStation.Download', 2)}',
        'method': 'download',
        'path': path,
        'mode': 'open',
        '_sid': _sid!,
      });

  @override
  Future<Uint8List?> read(String path) async {
    await ensureLogin();
    final res = await _c.get(_downloadUri(path)).timeout(const Duration(seconds: 30));
    final type = res.headers['content-type'] ?? '';
    if (type.startsWith('application/json')) return null; // エラー（408 そのファイルは無い など）
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw SourceException('ダウンロード HTTP ${res.statusCode}: $path');
    return res.bodyBytes;
  }

  /// 再生用の URL（セッション ID を含む。Range に対応：未確認、TESTING.md）
  @override
  Future<StreamUrl> stream(String path) async {
    await ensureLogin();
    return StreamUrl(_downloadUri(path).toString());
  }

  @override
  void close() {}
}
