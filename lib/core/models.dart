/// ライブラリの中身（端末のキャッシュ library.json に保存。正本は NAS のファイルと .nfo）
library;

enum TitleKind { movie, series, home }

class VideoFile {
  final String path; // NAS のパス（共有フォルダから。例 /video/映画/君の名は。 (2016)/君の名は。 (2016).mkv）
  final int size;
  final String label; // バージョン名・part など（無印は ''）
  const VideoFile(this.path, this.size, [this.label = '']);

  String get name => path.substring(path.lastIndexOf('/') + 1);

  Map<String, dynamic> toJson() => {'p': path, 's': size, if (label.isNotEmpty) 'l': label};
  factory VideoFile.fromJson(Map<String, dynamic> j) => VideoFile(j['p'] as String, j['s'] as int? ?? 0, j['l'] as String? ?? '');
}

class Episode {
  final VideoFile file;
  final int season; // 特別編は 0
  final int? number;
  final int? numberEnd;
  final DateTime? airDate;
  final String title;
  final List<String> tags;
  const Episode(this.file, this.season, this.number, this.numberEnd, this.airDate, this.title, this.tags);

  /// 「S01E03」「S01E03-E04」「2019-04-07」
  String get code {
    String two(int n) => n.toString().padLeft(2, '0');
    if (number != null) {
      return 'S${two(season)}E${two(number!)}${numberEnd == null ? '' : '-E${two(numberEnd!)}'}';
    }
    final d = airDate;
    if (d != null) return '${d.year}-${two(d.month)}-${two(d.day)}';
    return '';
  }

  Map<String, dynamic> toJson() => {
        'f': file.toJson(),
        's': season,
        if (number != null) 'n': number,
        if (numberEnd != null) 'ne': numberEnd,
        if (airDate != null) 'd': airDate!.toIso8601String().substring(0, 10),
        if (title.isNotEmpty) 't': title,
        if (tags.isNotEmpty) 'g': tags,
      };

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        VideoFile.fromJson(j['f'] as Map<String, dynamic>),
        j['s'] as int? ?? 1,
        j['n'] as int?,
        j['ne'] as int?,
        j['d'] == null ? null : DateTime.tryParse(j['d'] as String),
        j['t'] as String? ?? '',
        [for (final t in (j['g'] as List? ?? const [])) '$t'],
      );
}

/// 作品の情報（.nfo から。無ければ空）
class Info {
  final String title, originalTitle, plot, tagline;
  final int? year;
  final List<String> genres, cast, directors;
  final String collection; // NFO の <set>（シリーズの劇場版などのまとまり）
  final Map<int, String> namedSeasons; // tvshow.nfo の <namedseason number="2">遊郭編</namedseason>
  final String tmdbId;
  const Info({
    this.title = '',
    this.originalTitle = '',
    this.plot = '',
    this.tagline = '',
    this.year,
    this.genres = const [],
    this.cast = const [],
    this.directors = const [],
    this.collection = '',
    this.namedSeasons = const {},
    this.tmdbId = '',
  });
  static const empty = Info();

  Map<String, dynamic> toJson() => {
        if (title.isNotEmpty) 'title': title,
        if (originalTitle.isNotEmpty) 'orig': originalTitle,
        if (plot.isNotEmpty) 'plot': plot,
        if (tagline.isNotEmpty) 'tag': tagline,
        if (year != null) 'year': year,
        if (genres.isNotEmpty) 'genres': genres,
        if (cast.isNotEmpty) 'cast': cast,
        if (directors.isNotEmpty) 'dir': directors,
        if (collection.isNotEmpty) 'set': collection,
        if (namedSeasons.isNotEmpty) 'seasons': {for (final e in namedSeasons.entries) '${e.key}': e.value},
        if (tmdbId.isNotEmpty) 'tmdb': tmdbId,
      };

  factory Info.fromJson(Map<String, dynamic>? j) {
    if (j == null) return empty;
    List<String> l(String k) => [for (final v in (j[k] as List? ?? const [])) '$v'];
    return Info(
      title: j['title'] as String? ?? '',
      originalTitle: j['orig'] as String? ?? '',
      plot: j['plot'] as String? ?? '',
      tagline: j['tag'] as String? ?? '',
      year: j['year'] as int?,
      genres: l('genres'),
      cast: l('cast'),
      directors: l('dir'),
      collection: j['set'] as String? ?? '',
      namedSeasons: {
        for (final e in ((j['seasons'] as Map?) ?? const {}).entries)
          if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): '${e.value}',
      },
      tmdbId: j['tmdb'] as String? ?? '',
    );
  }
}

/// 作品の話を、利用者が選んだ並び順で返す（AppSettings の episodeOrder。Services が入れる）。
/// 続きから・次の話はこの順に進む
List<Episode> Function(Title) episodesOf = (t) => t.episodes;

class Title {
  final String id; // 作品のフォルダ（ファイル 1 つだけの作品はそのファイル）のパス
  final String shelf; // 最上位フォルダ（映画・アニメ…）
  final TitleKind kind;
  final String name;
  final int? year;
  final String? poster; // NAS のパス
  final String? fanart;
  final Info info;
  final List<VideoFile> files; // 映画：本編（バージョン・part）
  final List<Episode> episodes; // シリーズ：全話
  final List<VideoFile> extras;
  final int added; // 見つけた時刻（ミリ秒。NAS の更新時刻）

  /// シーズンのタイトル（season.nfo・tvshow.nfo の namedseason・フォルダ名の後ろ）
  final Map<int, String> seasonTitles;

  /// 別の並び順（シリーズのフォルダの .m3u8。名前 → ファイルのパスの並び）。例：放送順・時系列順
  final Map<String, List<String>> orders;

  const Title({
    required this.id,
    required this.shelf,
    required this.kind,
    required this.name,
    this.year,
    this.poster,
    this.fanart,
    this.info = Info.empty,
    this.files = const [],
    this.episodes = const [],
    this.extras = const [],
    this.added = 0,
    this.seasonTitles = const {},
    this.orders = const {},
  });

  String get displayName => info.title.isNotEmpty ? info.title : name;
  int? get displayYear => year ?? info.year;

  List<int> get seasons {
    final s = {for (final e in episodes) e.season}.toList()..sort();
    // 特別編（0）は最後に
    if (s.remove(0)) s.add(0);
    return s;
  }

  List<Episode> episodesOf(int season) => episodes.where((e) => e.season == season).toList();

  /// 並び順 [order]（orders の名前。null・知らない名前ならフォルダの順）の全話
  List<Episode> episodesInOrder(String? order) {
    final paths = order == null ? null : orders[order];
    if (paths == null) return episodes;
    final byPath = {for (final e in episodes) e.file.path: e};
    return [for (final p in paths) ?byPath[p]];
  }

  /// 再生できるファイルを全部（続きからの判定・オフライン用）
  List<VideoFile> get allFiles => [...files, for (final e in episodes) e.file];

  Map<String, dynamic> toJson() => {
        'id': id,
        'shelf': shelf,
        'kind': kind.name,
        'name': name,
        if (year != null) 'year': year,
        if (poster != null) 'poster': poster,
        if (fanart != null) 'fanart': fanart,
        'info': info.toJson(),
        if (files.isNotEmpty) 'files': [for (final f in files) f.toJson()],
        if (episodes.isNotEmpty) 'eps': [for (final e in episodes) e.toJson()],
        if (extras.isNotEmpty) 'extras': [for (final f in extras) f.toJson()],
        'added': added,
        if (seasonTitles.isNotEmpty) 'stitles': {for (final e in seasonTitles.entries) '${e.key}': e.value},
        if (orders.isNotEmpty) 'orders': orders,
      };

  factory Title.fromJson(Map<String, dynamic> j) => Title(
        id: j['id'] as String,
        shelf: j['shelf'] as String? ?? '',
        kind: TitleKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => TitleKind.movie),
        name: j['name'] as String? ?? '',
        year: j['year'] as int?,
        poster: j['poster'] as String?,
        fanart: j['fanart'] as String?,
        info: Info.fromJson(j['info'] as Map<String, dynamic>?),
        files: [for (final f in (j['files'] as List? ?? const [])) VideoFile.fromJson(f as Map<String, dynamic>)],
        episodes: [for (final e in (j['eps'] as List? ?? const [])) Episode.fromJson(e as Map<String, dynamic>)],
        extras: [for (final f in (j['extras'] as List? ?? const [])) VideoFile.fromJson(f as Map<String, dynamic>)],
        added: j['added'] as int? ?? 0,
        seasonTitles: {
          for (final e in ((j['stitles'] as Map?) ?? const {}).entries)
            if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): '${e.value}',
        },
        orders: {
          for (final e in ((j['orders'] as Map?) ?? const {}).entries)
            '${e.key}': [for (final p in (e.value as List)) '$p'],
        },
      );
}
