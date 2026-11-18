import 'package:xml/xml.dart';

import 'models.dart';

/// Kodi 形式の .nfo（movie・tvshow・episodedetails）を読む。読めなければ Info.empty。
/// Jellyfin・Kodi が書く形と同じ（docs/naming-convention.md §6）。
Info parseNfo(String text) {
  final XmlDocument doc;
  try {
    // 先頭に URL だけ書いた NFO（Kodi の古い形）もあるので、< から読む
    final i = text.indexOf('<');
    if (i < 0) return Info.empty;
    doc = XmlDocument.parse(text.substring(i));
  } catch (_) {
    return Info.empty;
  }
  final root = doc.rootElement;
  String one(String name) => root.getElement(name)?.innerText.trim() ?? '';
  List<String> many(String name) =>
      [for (final e in root.findElements(name)) e.innerText.trim()].where((s) => s.isNotEmpty).toList();

  final cast = <String>[
    for (final a in root.findElements('actor'))
      if ((a.getElement('name')?.innerText.trim() ?? '').isNotEmpty) a.getElement('name')!.innerText.trim(),
  ];
  // <set><name>…</name></set> と <set>…</set> の両方
  final setEl = root.getElement('set');
  final set = setEl == null ? '' : (setEl.getElement('name')?.innerText ?? setEl.innerText).trim();

  var tmdb = '';
  for (final u in root.findElements('uniqueid')) {
    if (u.getAttribute('type') == 'tmdb') tmdb = u.innerText.trim();
  }
  if (tmdb.isEmpty) tmdb = one('tmdbid');

  int? year = int.tryParse(one('year'));
  if (year == null) {
    final d = one('premiered').isNotEmpty ? one('premiered') : one('aired');
    if (d.length >= 4) year = int.tryParse(d.substring(0, 4));
  }

  return Info(
    title: one('title'),
    originalTitle: one('originaltitle'),
    plot: one('plot').isNotEmpty ? one('plot') : one('outline'),
    tagline: one('tagline'),
    year: year,
    genres: many('genre'),
    cast: cast,
    directors: many('director'),
    collection: set,
    namedSeasons: {
      for (final e in root.findElements('namedseason'))
        if (int.tryParse(e.getAttribute('number') ?? '') != null && e.innerText.trim().isNotEmpty)
          int.parse(e.getAttribute('number')!): e.innerText.trim(),
    },
    tmdbId: tmdb,
  );
}

/// season.nfo（Season フォルダの中）のタイトル。読めなければ ''
String parseSeasonNfoTitle(String text) {
  try {
    final i = text.indexOf('<');
    if (i < 0) return '';
    return XmlDocument.parse(text.substring(i)).rootElement.getElement('title')?.innerText.trim() ?? '';
  } catch (_) {
    return '';
  }
}

/// プレイリスト（.m3u / .m3u8）：並び順の相対パス（または絶対パス）と、#EXTINF の題名
List<(String, String)> parsePlaylist(String text) {
  final out = <(String, String)>[];
  var title = '';
  for (var line in text.split(RegExp(r'\r?\n'))) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF')) {
      final c = line.indexOf(',');
      title = c < 0 ? '' : line.substring(c + 1).trim();
      continue;
    }
    if (line.startsWith('#')) continue;
    out.add((line.replaceAll('\\', '/'), title));
    title = '';
  }
  return out;
}
