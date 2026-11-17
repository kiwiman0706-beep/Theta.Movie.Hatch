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
    tmdbId: tmdb,
  );
}
