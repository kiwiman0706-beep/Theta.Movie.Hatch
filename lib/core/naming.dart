/// ファイル名・フォルダ名の読み取り（docs/naming-convention.md）。
/// 規則どおりの名前を正しく読み、整理前の名前もできるだけ読む。純粋な関数だけ（テストは test/naming_test.dart）。
library;

const videoExts = {
  'mkv', 'mp4', 'm4v', 'avi', 'mov', 'wmv', 'ts', 'm2ts', 'mts', 'webm', 'mpg', 'mpeg', 'flv', 'vob', 'ogv', '3gp',
};

const subtitleExts = {'srt', 'ass', 'ssa', 'vtt', 'sub', 'sup'};

String extOf(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
}

String stemOf(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? name : name.substring(0, i);
}

bool isVideo(String name) => videoExts.contains(extOf(name)) && !name.startsWith('.');

/// 隠し・システムのフォルダ（Synology の @eaDir、#recycle など）
bool isHiddenName(String name) =>
    name.startsWith('.') || name.startsWith('@') || name.startsWith('#') || name == 'lost+found' || name.startsWith('_');

/// 特典映像のフォルダ（Jellyfin・Plex・Kodi と同じ名前）
const extrasFolders = {
  'extras', 'behind the scenes', 'deleted scenes', 'featurettes', 'interviews', 'scenes', 'shorts', 'trailers', 'other',
  '特典', '特典映像',
};

bool isExtrasFolder(String name) => extrasFolders.contains(name.toLowerCase());

/// 「タイトル (年) [tmdbid-123]」
class TitleName {
  final String title;
  final int? year;
  final String? tmdbId;
  const TitleName(this.title, this.year, this.tmdbId);
  @override
  String toString() => year == null ? title : '$title ($year)';
}

final _idTag = RegExp(r'\s*[\[{](?:tmdbid|tmdb)[-=](\d+)[\]}]', caseSensitive: false);
final _yearTail = RegExp(r'\s*[\(（]((?:19|20)\d{2})[\)）]\s*$');
final _bracketTail = RegExp(r'\s*\[[^\[\]]*\]\s*$');

TitleName parseTitleName(String name) {
  var s = name.trim();
  String? tmdb;
  final id = _idTag.firstMatch(s);
  if (id != null) {
    tmdb = id.group(1);
    s = s.replaceFirst(_idTag, '');
  }
  // 末尾の補足 [..] は外す
  while (_bracketTail.hasMatch(s)) {
    s = s.replaceFirst(_bracketTail, '');
  }
  int? year;
  final y = _yearTail.firstMatch(s);
  if (y != null) {
    year = int.parse(y.group(1)!);
    s = s.substring(0, y.start);
  }
  s = s.trim();
  return TitleName(s.isEmpty ? name.trim() : s, year, tmdb);
}

/// 映画のファイル名「タイトル (年) - 4K.mkv」→ バージョン名「4K」。part1 などは part に
class MovieFileName {
  final String version; // '' なら無印
  final int? part;
  const MovieFileName(this.version, this.part);
}

final _partRe = RegExp(r'^(?:part|pt|cd|disc|disk|dvd)\s*(\d+)$', caseSensitive: false);

MovieFileName parseMovieFile(String fileName) {
  final stem = stemOf(fileName);
  final i = stem.lastIndexOf(' - ');
  if (i < 0) return const MovieFileName('', null);
  final tail = stem.substring(i + 3).trim();
  final p = _partRe.firstMatch(tail);
  if (p != null) return MovieFileName('', int.parse(p.group(1)!));
  return MovieFileName(tail, null);
}

/// 「Season 01」「Season 2019」「Specials」「シーズン1」「第2期」→ シーズン番号（特別編は 0）。
/// 整理前の「Season 02 遊郭編」「Season 2 - 遊郭編」「第2期 遊郭編」も読む（後ろはシーズンのタイトル）
int? parseSeasonFolder(String name) => _season(name)?.$1;

/// フォルダ名に付いたシーズンのタイトル（無ければ ''）
String seasonFolderTitle(String name) => _season(name)?.$2 ?? '';

(int, String)? _season(String name) {
  final raw = name.trim();
  final s = raw.toLowerCase();
  if (s == 'specials' || s == 'special' || s == 'sp' || s == '特別編' || s == 'ova') return (0, '');
  final m = RegExp(r'^(?:season|series|s|シーズン)\s*(\d{1,4})(?:\s*[-–—:：_・]?\s+|\s*[-–—:：_・]\s*)?(.*)$', caseSensitive: false)
          .firstMatch(raw) ??
      RegExp(r'^第\s*(\d{1,2})\s*(?:期|シーズン|シリーズ)\s*[-–—:：_・]?\s*(.*)$').firstMatch(raw);
  if (m == null) return null;
  final title = (m.group(2) ?? '').trim();
  // 「S2」の後ろにすぐ英字が続くもの（「Sample」など）はシーズンではない
  if (title.isNotEmpty && RegExp(r'^(?:season|series|s|シーズン)\s*\d+[a-z]', caseSensitive: false).hasMatch(raw)) {
    return null;
  }
  return (int.parse(m.group(1)!), title);
}

/// 話のファイル名から読み取ったもの
class EpisodeName {
  final int? season;
  final int? episode;
  final int? episodeEnd;
  final DateTime? airDate;
  final String subtitle; // 「サブタイトル」の中身
  final List<String> tags; // 末尾の [..] の中身（放送日・放送局・再・DVD1 など）
  const EpisodeName({this.season, this.episode, this.episodeEnd, this.airDate, this.subtitle = '', this.tags = const []});
  bool get hasNumber => episode != null || airDate != null;
}

final _sxe = RegExp(r'(?:^|[\s._\-])s(\d{1,4})[\s._]?e(\d{1,4})(?:\s*-?\s*e(\d{1,4}))?', caseSensitive: false);
final _date = RegExp(r'((?:19|20)\d{2})[-._年/]?(\d{1,2})[-._月/]?(\d{1,2})日?');
final _epJa = RegExp(r'第\s*(\d{1,4})\s*[話回]');
final _epHash = RegExp(r'[#＃]\s*(\d{1,4})');
final _epE = RegExp(r'(?:^|[\s._\-\[])(?:ep?|episode)\s*(\d{1,4})(?:$|[\s._\-\]])', caseSensitive: false);
final _subtitle = RegExp(r'「([^」]*)」');
final _bracket = RegExp(r'\[([^\[\]]*)\]');

EpisodeName parseEpisodeFile(String fileName) {
  final stem = stemOf(fileName);
  final tags = [for (final m in _bracket.allMatches(stem)) m.group(1)!.trim()].where((t) => t.isNotEmpty).toList();
  final sub = _subtitle.firstMatch(stem)?.group(1)?.trim() ?? '';
  // 放送日・番号は [..] と「..」の外から探す（[2019-04-21 TBS] を放送日と取り違えないよう、本体を先に見る）
  final body = stem.replaceAll(_bracket, ' ').replaceAll(_subtitle, ' ');
  final m = _sxe.firstMatch(body);
  if (m != null) {
    final end = m.group(3) == null ? null : int.parse(m.group(3)!);
    return EpisodeName(
        season: int.parse(m.group(1)!),
        episode: int.parse(m.group(2)!),
        episodeEnd: end,
        airDate: _dateIn(tags.join(' ')),
        subtitle: sub,
        tags: tags);
  }
  final ja = _epJa.firstMatch(body) ?? _epHash.firstMatch(body) ?? _epE.firstMatch(body);
  if (ja != null) {
    return EpisodeName(episode: int.parse(ja.group(1)!), airDate: _dateIn('$body ${tags.join(' ')}'), subtitle: sub, tags: tags);
  }
  final d = _dateIn(body) ?? _dateIn(tags.join(' '));
  if (d != null) return EpisodeName(airDate: d, subtitle: sub, tags: tags);
  return EpisodeName(subtitle: sub, tags: tags);
}

DateTime? _dateIn(String s) {
  for (final m in _date.allMatches(s)) {
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return DateTime(y, mo, d);
  }
  return null;
}

/// 棚（最上位フォルダ）の種類
enum ShelfKind { movie, series, home, auto }

ShelfKind shelfKindOf(String folder) => switch (folder) {
      '映画' || 'アニメ映画' || 'ライブ' || '特番' || 'Movies' || 'movies' => ShelfKind.movie,
      'ドラマ' || 'アニメ' || 'テレビ' || 'TV' || 'Shows' || 'shows' => ShelfKind.series,
      'ホームビデオ' || 'Home Videos' => ShelfKind.home,
      _ => ShelfKind.auto,
    };

/// 自然な並び（「第2話」<「第10話」）のための比較
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a).toList(), y = re.allMatches(b).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i], q = y[i];
    if (p.group(1) != null && q.group(1) != null) {
      final c = int.parse(p.group(1)!).compareTo(int.parse(q.group(1)!));
      if (c != 0) return c;
    } else {
      final c = p.group(0)!.compareTo(q.group(0)!);
      if (c != 0) return c;
    }
  }
  return x.length.compareTo(y.length);
}
