import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theta_movie/core/dsm.dart';
import 'package:theta_movie/core/models.dart';
import 'package:theta_movie/core/scanner.dart';
import 'package:theta_movie/core/settings.dart';
import 'package:theta_movie/core/source.dart';

/// test/fake_dsm.py（DSM の真似）を立てて、ログイン（2 段階認証）・一覧・読み取り・再生用 URL を通しで試す。
/// python3 が無ければ飛ばす
void main() {
  late Directory dir;
  late Process server;
  const port = 5987;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('movie_dsm');
    final f = File('${dir.path}/アニメ/〇〇 (2019)/Season 01/〇〇 S01E01「一」.mkv');
    await f.create(recursive: true);
    await f.writeAsBytes(List.generate(1000, (i) => i % 256));
    await File('${dir.path}/アニメ/〇〇 (2019)/tvshow.nfo').writeAsString('<tvshow><title>〇〇</title></tvshow>');
    server = await Process.start('python3', ['test/fake_dsm.py', dir.path, '$port', '--otp']);
    await server.stdout.first; // 「fake DSM on …」
  });

  tearDownAll(() async {
    server.kill();
    await dir.delete(recursive: true);
  });

  Future<AppSettings> settings() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.secure = null;
    final s = AppSettings();
    await s.load();
    s
      ..dsUrl = '127.0.0.1:$port'
      ..user = 'u'
      ..password = 'p';
    return s;
  }

  test('2 段階認証：コード → デバイストークンで次から省ける', () async {
    final s = await settings();
    final src = DsmSource(s);
    await expectLater(src.check(), throwsA(isA<OtpRequired>()));
    src.setOtp('000000');
    await expectLater(src.check(), throwsA(isA<OtpRequired>()));
    src.setOtp('123456');
    await src.check();
    expect(s.did, 'did-abc');
    // 新しい接続でも、トークンで通る
    await DsmSource(s).check();
  });

  test('一覧・作品の読み取り・再生用 URL（Range）', () async {
    final s = await settings();
    s.did = 'did-abc';
    final src = DsmSource(s);
    final titles = await Scanner(src.list, src.read).scan(['/video']);
    final t = titles.single;
    expect(t.kind, TitleKind.series);
    expect(t.info.title, '〇〇');
    final ep = t.episodes.single;
    expect(ep.file.size, 1000);
    final u = await src.stream(ep.file.path);
    final res = await http.get(Uri.parse(u.url), headers: {...u.headers, 'Range': 'bytes=100-199'});
    expect(res.statusCode, 206);
    expect(res.bodyBytes.length, 100);
    expect(res.bodyBytes.first, 100);
  });
}
