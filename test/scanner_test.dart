import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:theta_movie/core/models.dart';
import 'package:theta_movie/core/nfo.dart';
import 'package:theta_movie/core/scanner.dart';
import 'package:theta_movie/core/source.dart';

/// パスの一覧から NAS の木を真似る
class FakeTree {
  final Map<String, String> files; // パス → 中身（動画は ''）
  FakeTree(this.files);

  Future<List<Entry>> list(String dir) async {
    final pre = dir.endsWith('/') ? dir : '$dir/';
    final seen = <String, Entry>{};
    for (final p in files.keys) {
      if (!p.startsWith(pre)) continue;
      final rest = p.substring(pre.length);
      final i = rest.indexOf('/');
      if (i < 0) {
        seen[rest] = Entry(p, false, files[p]!.length, 1000);
      } else {
        final name = rest.substring(0, i);
        seen[name] ??= Entry('$pre$name', true, 0, 0);
      }
    }
    return seen.values.toList();
  }

  Future<List<int>?> read(String path) async => files.containsKey(path) ? utf8.encode(files[path]!) : null;
}

void main() {
  const movieNfo = '''<?xml version="1.0" encoding="UTF-8"?>
<movie>
  <title>君の名は。</title>
  <originaltitle>Your Name.</originaltitle>
  <year>2016</year>
  <plot>あらすじ</plot>
  <genre>アニメ</genre>
  <director>新海誠</director>
  <actor><name>神木隆之介</name></actor>
  <set><name>新海誠作品</name></set>
  <uniqueid type="tmdb">372058</uniqueid>
</movie>''';

  final tree = FakeTree({
    '/video/アニメ映画/君の名は。 (2016)/君の名は。 (2016).mkv': '',
    '/video/アニメ映画/君の名は。 (2016)/君の名は。 (2016).nfo': movieNfo,
    '/video/アニメ映画/君の名は。 (2016)/poster.jpg': 'x',
    '/video/アニメ映画/君の名は。 (2016)/extras/メイキング.mkv': '',
    '/video/映画/七人の侍 (1954)/七人の侍 (1954) - part1.mkv': '',
    '/video/映画/七人の侍 (1954)/七人の侍 (1954) - part2.mkv': '',
    '/video/映画/ばらの1本.mp4': '',
    '/video/アニメ/〇〇 (2019)/tvshow.nfo': '<tvshow><title>〇〇</title><plot>話</plot></tvshow>',
    '/video/アニメ/〇〇 (2019)/Season 01/〇〇 S01E02「二」.mkv': '',
    '/video/アニメ/〇〇 (2019)/Season 01/〇〇 S01E01「一」.mkv': '',
    '/video/アニメ/〇〇 (2019)/Season 02/〇〇 S02E01.mkv': '',
    '/video/アニメ/〇〇 (2019)/Season 00/〇〇 S00E01 OVA.mkv': '',
    // 整理前：まとまりの中に、話数だけのファイルが並ぶ
    '/video/ドラマ/国内/ドラマ名/ドラマ名 第1話.ts': '',
    '/video/ドラマ/国内/ドラマ名/ドラマ名 第2話.ts': '',
    '/video/テレビ/番組 (2005)/Season 2019/番組 2019-04-07「内容」 [テレ朝].ts': '',
    '/video/ホームビデオ/2024/2024-08-12 海水浴.mp4': '',
    '/video/@eaDir/x/y.mkv': '',
    '/video/#recycle/z.mkv': '',
  });

  late List<Title> titles;
  setUpAll(() async {
    titles = await Scanner(tree.list, tree.read).scan('/video');
  });

  Title by(String name) => titles.firstWhere((t) => t.name == name);

  test('隠しフォルダは読まない', () {
    expect(titles.any((t) => t.id.contains('@eaDir') || t.id.contains('#recycle')), isFalse);
  });

  test('映画：NFO・ポスター・特典', () {
    final t = by('君の名は。');
    expect(t.kind, TitleKind.movie);
    expect(t.shelf, 'アニメ映画');
    expect(t.year, 2016);
    expect(t.poster, endsWith('poster.jpg'));
    expect(t.info.originalTitle, 'Your Name.');
    expect(t.info.collection, '新海誠作品');
    expect(t.info.tmdbId, '372058');
    expect(t.info.cast, ['神木隆之介']);
    expect(t.extras.single.label, 'メイキング');
    expect(t.files.length, 1);
  });

  test('映画：パートに分かれたもの', () {
    final t = by('七人の侍');
    expect(t.kind, TitleKind.movie);
    expect([for (final f in t.files) f.label], ['part1', 'part2']);
  });

  test('棚の直下のファイルは 1 本で 1 作品', () {
    expect(by('ばらの1本').kind, TitleKind.movie);
  });

  test('シリーズ：シーズンと特別編、話の並び', () {
    final t = by('〇〇');
    expect(t.kind, TitleKind.series);
    expect(t.info.plot, '話');
    expect(t.seasons, [1, 2, 0]);
    expect([for (final e in t.episodesOf(1)) e.code], ['S01E01', 'S01E02']);
    expect(t.episodesOf(1).first.title, '一');
  });

  test('整理前のシリーズ（まとまりの中）', () {
    final t = by('ドラマ名');
    expect(t.kind, TitleKind.series);
    expect(t.shelf, 'ドラマ');
    expect([for (final e in t.episodes) e.number], [1, 2]);
  });

  test('放送日の番組', () {
    final t = by('番組');
    expect(t.kind, TitleKind.series);
    expect(t.episodes.single.season, 2019);
    expect(t.episodes.single.code, '2019-04-07');
  });

  test('ホームビデオは 1 本ずつ', () {
    final t = titles.firstWhere((t) => t.kind == TitleKind.home);
    expect(t.shelf, 'ホームビデオ');
  });

  test('キャッシュの往復（JSON）', () {
    for (final t in titles) {
      final back = Title.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), t.toJson());
    }
  });

  test('壊れた NFO は空', () {
    expect(parseNfo('<movie><title>').title, '');
    expect(parseNfo('https://www.themoviedb.org/movie/1\n<movie><title>A</title></movie>').title, 'A');
  });
}
