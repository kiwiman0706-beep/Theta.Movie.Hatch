import 'dart:async';
import 'dart:convert';

import 'models.dart';
import 'naming.dart';
import 'nfo.dart';
import 'source.dart';

typedef Lister = Future<List<Entry>> Function(String dir);
typedef Reader = Future<List<int>?> Function(String path);

/// NAS の動画フォルダを読んで作品の一覧を作る。
/// 規則どおり（docs/naming-convention.md）なら正確に、整理前のフォルダでもできるだけ作品にまとめる：
/// - 最上位のフォルダ＝棚（映画・アニメ…）
/// - 動画の入ったフォルダ＝作品。Season フォルダや話数のある動画が並べばシリーズ、そうでなければ映画
/// - 動画が無くフォルダだけのもの＝まとまり（国内／海外 など）として 3 段まで中を見る
class Scanner {
  final Lister list;
  final Reader read;
  final int concurrency;
  final bool readNfo;
  void Function(String dir, int titles)? onProgress;
  bool Function()? cancelled;

  Scanner(this.list, this.read, {this.concurrency = 3, this.readNfo = true, this.onProgress, this.cancelled});

  final _out = <Title>[];
  int _running = 0;
  final _waiters = <Completer<void>>[];

  Future<T> _limit<T>(Future<T> Function() f) async {
    while (_running >= concurrency) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _running++;
    try {
      return await f();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }

  Future<List<Entry>> _ls(String dir) => _limit(() => list(dir));

  /// 読めなかったフォルダ（つながらない・権限が無い）。全体は止めずに続ける
  final errors = <String>[];

  /// ここまでに見つけた作品（スキャン中の途中経過）
  List<Title> get found => List.of(_out);

  /// roots：共有フォルダ（例 /video、/8Tube）。prefix を入れると、その直下で名前が prefix で始まる
  /// フォルダだけを棚として読む（Theta Book Hatch の「⑧」と同じ）。棚の名前は prefix を外したもの
  Future<List<Title>> scan(List<String> roots, {String prefix = ''}) async {
    _out.clear();
    errors.clear();
    final pre = prefix.trim().toLowerCase();
    for (final root in roots) {
      if (cancelled?.call() ?? false) break;
      final List<Entry> top;
      try {
        top = await _ls(root);
      } catch (e) {
        if (roots.length == 1) rethrow; // 共有フォルダそのものが読めないなら、接続か設定の問題
        errors.add('$root: $e');
        continue;
      }
      final dirs = top.where((e) => e.isDir && !isHiddenName(e.name));
      if (pre.isEmpty) {
        for (final f in top.where((e) => !e.isDir && isVideo(e.name))) {
          _out.add(_looseTitle(f, '', ShelfKind.auto));
        }
        await Future.wait([for (final s in dirs) _group(s.path, s.name, shelfKindOf(s.name), 0)]);
      } else {
        final shelves = dirs.where((e) => e.name.toLowerCase().startsWith(pre));
        await Future.wait([
          for (final s in shelves)
            () {
              final name = shelfName(s.name, prefix);
              return _group(s.path, name, shelfKindOf(name), 0);
            }(),
        ]);
      }
    }
    _out.sort((a, b) => naturalCompare(a.displayName, b.displayName));
    return List.of(_out);
  }

  /// 「⑧アニメ」→「アニメ」
  static String shelfName(String folder, String prefix) {
    final p = prefix.trim();
    var s = p.isNotEmpty && folder.toLowerCase().startsWith(p.toLowerCase()) ? folder.substring(p.length) : folder;
    s = s.replaceFirst(RegExp(r'^[\s_\-・.]+'), '');
    return s.isEmpty ? folder : s;
  }

  Future<void> _group(String dir, String shelf, ShelfKind hint, int depth) async {
    try {
      await _groupBody(dir, shelf, hint, depth);
    } catch (e) {
      errors.add('$dir: $e');
    }
  }

  Future<void> _groupBody(String dir, String shelf, ShelfKind hint, int depth) async {
    if (cancelled?.call() ?? false) return;
    final children = await _ls(dir);
    final videos = children.where((e) => !e.isDir && isVideo(e.name)).toList();
    final dirs = children.where((e) => e.isDir && !isHiddenName(e.name) && !isExtrasFolder(e.name)).toList();
    onProgress?.call(dir, _out.length);

    if (hint == ShelfKind.home) {
      for (final v in videos) {
        _out.add(_looseTitle(v, shelf, hint));
      }
      if (depth < 4) await Future.wait([for (final d in dirs) _group(d.path, shelf, hint, depth + 1)]);
      return;
    }

    // 棚の直下の動画ファイル：1 本で 1 作品
    for (final v in videos) {
      _out.add(_looseTitle(v, shelf, hint));
    }
    await Future.wait([for (final d in dirs) _folder(d, shelf, hint, depth)]);
  }

  /// フォルダ 1 つを作品として読む。作品でなければ、まとまりとして中を見る
  Future<void> _folder(Entry dir, String shelf, ShelfKind hint, int depth) async {
    try {
      await _folderBody(dir, shelf, hint, depth);
    } catch (e) {
      errors.add('${dir.path}: $e');
    }
  }

  Future<void> _folderBody(Entry dir, String shelf, ShelfKind hint, int depth) async {
    if (cancelled?.call() ?? false) return;
    final ch = await _ls(dir.path);
    final videos = ch.where((e) => !e.isDir && isVideo(e.name)).toList()..sort((a, b) => naturalCompare(a.name, b.name));
    final subdirs = ch.where((e) => e.isDir && !isHiddenName(e.name)).toList();
    final seasonDirs = [for (final d in subdirs) if (parseSeasonFolder(d.name) != null) d];
    final extrasDirs = [for (final d in subdirs) if (isExtrasFolder(d.name)) d];
    final otherDirs = [for (final d in subdirs) if (parseSeasonFolder(d.name) == null && !isExtrasFolder(d.name)) d];

    final numbered = videos.where((v) => parseEpisodeFile(v.name).hasNumber).length;
    final isSeries = seasonDirs.isNotEmpty ||
        (videos.length >= 2 && numbered >= 2) ||
        videos.length >= 3 ||
        (hint == ShelfKind.series && numbered >= 1);

    if (!isSeries && videos.isEmpty) {
      // まとまり（例：ドラマ/国内/…）
      if (depth < 3) await Future.wait([for (final d in otherDirs) _folder(d, shelf, hint, depth + 1)]);
      return;
    }

    final name = parseTitleName(dir.name);
    String? pick(List<String> names) {
      for (final n in names) {
        for (final e in ch) {
          if (!e.isDir && e.name.toLowerCase() == n) return e.path;
        }
      }
      return null;
    }

    final poster = pick(['poster.jpg', 'poster.png', 'folder.jpg', 'cover.jpg', 'poster.webp']);
    final fanart = pick(['fanart.jpg', 'backdrop.jpg', 'fanart.png', 'background.jpg']);

    final extras = <VideoFile>[];
    for (final d in extrasDirs) {
      for (final e in await _ls(d.path)) {
        if (!e.isDir && isVideo(e.name)) extras.add(VideoFile(e.path, e.size, stemOf(e.name)));
      }
    }
    var added = 0;
    for (final v in videos) {
      if (v.mtime > added) added = v.mtime;
    }

    if (isSeries) {
      final eps = <Episode>[];
      void addEp(Entry v, int defaultSeason) {
        final p = parseEpisodeFile(v.name);
        final title = p.subtitle.isNotEmpty ? p.subtitle : '';
        eps.add(Episode(VideoFile(v.path, v.size), p.season ?? defaultSeason, p.episode, p.episodeEnd, p.airDate, title,
            p.tags));
        if (v.mtime > added) added = v.mtime;
      }

      for (final v in videos) {
        addEp(v, 1);
      }
      // シーズンのタイトル：season.nfo ＞ tvshow.nfo の namedseason ＞ フォルダ名の後ろ（「Season 02 遊郭編」）
      final seasonTitles = <int, String>{};
      for (final s in seasonDirs) {
        final n = parseSeasonFolder(s.name)!;
        final listing = await _ls(s.path);
        final inner = listing.where((e) => !e.isDir && isVideo(e.name)).toList()
          ..sort((a, b) => naturalCompare(a.name, b.name));
        for (final v in inner) {
          addEp(v, n);
        }
        final folderTitle = seasonFolderTitle(s.name);
        if (folderTitle.isNotEmpty) seasonTitles[n] = folderTitle;
        final sn = listing.where((e) => !e.isDir && e.name.toLowerCase() == 'season.nfo').firstOrNull;
        if (sn != null) {
          final t = parseSeasonNfoTitle(await _text(sn.path));
          if (t.isNotEmpty) seasonTitles[n] = t;
        }
      }
      // 番号の無い話は、並び順で番号を振らずに名前順のまま
      eps.sort((a, b) {
        var c = a.season.compareTo(b.season);
        if (c != 0) return c;
        if (a.number != null && b.number != null) {
          c = a.number!.compareTo(b.number!);
          if (c != 0) return c;
        }
        if (a.airDate != null && b.airDate != null) {
          c = a.airDate!.compareTo(b.airDate!);
          if (c != 0) return c;
        }
        return naturalCompare(a.file.name, b.file.name);
      });
      final info = await _nfo(pick(['tvshow.nfo']));
      for (final e in info.namedSeasons.entries) {
        seasonTitles.putIfAbsent(e.key, () => e.value);
      }
      // 別の並び順：シリーズのフォルダの .m3u8（放送順.m3u8・時系列順.m3u8 など）。ファイルは複製しない
      final orders = <String, List<String>>{};
      final known = {for (final e in eps) e.file.path};
      for (final pl in ch.where((e) => !e.isDir && (extOf(e.name) == 'm3u8' || extOf(e.name) == 'm3u'))) {
        final paths = <String>[];
        for (final (ref, _) in parsePlaylist(await _text(pl.path))) {
          final abs = _resolve(dir.path, ref);
          if (known.contains(abs)) paths.add(abs);
        }
        if (paths.isNotEmpty) orders[stemOf(pl.name)] = paths;
      }
      _out.add(Title(
        id: dir.path,
        shelf: shelf,
        kind: TitleKind.series,
        name: name.title,
        year: name.year,
        poster: poster,
        fanart: fanart,
        info: info,
        episodes: eps,
        extras: extras,
        added: added,
        seasonTitles: seasonTitles,
        orders: orders,
      ));
      return;
    }

    // 映画：本編（バージョン・part）
    final files = <VideoFile>[];
    for (final v in videos) {
      final m = parseMovieFile(v.name);
      files.add(VideoFile(v.path, v.size, m.part != null ? 'part${m.part}' : m.version));
    }
    final stem = videos.isEmpty ? '' : stemOf(videos.first.name).toLowerCase();
    final nfoPath = pick(['$stem.nfo', 'movie.nfo']) ??
        ch.where((e) => !e.isDir && extOf(e.name) == 'nfo').map((e) => e.path).firstOrNull;
    _out.add(Title(
      id: dir.path,
      shelf: shelf,
      kind: TitleKind.movie,
      name: name.title,
      year: name.year,
      poster: poster,
      fanart: fanart,
      info: await _nfo(nfoPath),
      files: files,
      extras: extras,
      added: added,
    ));
    // 作品フォルダの中にさらに作品のフォルダがある（コレクション）なら、それも見る
    if (depth < 3) await Future.wait([for (final d in otherDirs) _folder(d, shelf, hint, depth + 1)]);
  }

  Title _looseTitle(Entry f, String shelf, ShelfKind hint) {
    final n = parseTitleName(stemOf(f.name));
    return Title(
      id: f.path,
      shelf: shelf,
      kind: hint == ShelfKind.home ? TitleKind.home : TitleKind.movie,
      name: n.title,
      year: n.year,
      files: [VideoFile(f.path, f.size)],
      added: f.mtime,
    );
  }

  /// 小さな文字のファイル（season.nfo・.m3u8）。読めなければ ''
  Future<String> _text(String path) async {
    try {
      final b = await _limit(() => read(path));
      return b == null ? '' : utf8.decode(b, allowMalformed: true).replaceFirst('\uFEFF', '');
    } catch (_) {
      return '';
    }
  }

  /// プレイリストの中のパス（相対・絶対、./ ../ 付き）を NAS の絶対パスにする
  static String _resolve(String base, String ref) {
    var r = ref.trim();
    if (r.startsWith('file://')) r = Uri.decodeFull(r.substring(7));
    final parts = r.startsWith('/') ? <String>[] : base.split('/').where((s) => s.isNotEmpty).toList();
    for (final seg in r.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return '/${parts.join('/')}';
  }

  Future<Info> _nfo(String? path) async {
    if (!readNfo || path == null) return Info.empty;
    try {
      final b = await _limit(() => read(path));
      if (b == null) return Info.empty;
      return parseNfo(utf8.decode(b, allowMalformed: true));
    } catch (_) {
      return Info.empty;
    }
  }
}
