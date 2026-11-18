import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class Mark {
  final int pos; // 秒
  final int dur; // 秒（分からなければ 0）
  final int at; // 最後に見た時刻（ミリ秒）
  final bool done;
  const Mark(this.pos, this.dur, this.at, this.done);

  double get ratio => dur <= 0 ? 0 : (pos / dur).clamp(0, 1).toDouble();

  Map<String, dynamic> toJson() => {'p': pos, 'd': dur, 'a': at, if (done) 'x': true};
  factory Mark.fromJson(Map<String, dynamic> j) =>
      Mark(j['p'] as int? ?? 0, j['d'] as int? ?? 0, j['a'] as int? ?? 0, j['x'] == true);
}

/// 再生位置と見終わったか（ファイルのパスごと）。
/// いまは端末の中（progress.json）。次の版で Theta Vault の Movie/_state/<端末>.json と同期する（progress/movie.md）
class Progress extends ChangeNotifier {
  Map<String, Mark> marks = {};
  File? _file;

  Future<void> load() async {
    try {
      _file = File('${(await getApplicationSupportDirectory()).path}/progress.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        marks = {for (final e in j.entries) e.key: Mark.fromJson(e.value as Map<String, dynamic>)};
      }
    } catch (e) {
      debugPrint('progress: $e');
    }
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode({for (final e in marks.entries) e.key: e.value.toJson()}));
    } catch (_) {}
  }

  Mark? of(String path) => marks[path];

  /// 途中なら続きの位置（秒）。見終わった・初めてなら 0
  int resumeAt(String path) {
    final m = marks[path];
    if (m == null || m.done) return 0;
    return m.pos > 10 ? m.pos : 0;
  }

  Future<void> update(String path, int pos, int dur, {required int doneMarginSec}) async {
    final done = dur > 0 && dur - pos < doneMarginSec && pos > dur * 0.5;
    final now = DateTime.now().millisecondsSinceEpoch;
    final was = marks[path]?.done ?? false;
    // 見終わった作品を最初の数秒だけ開いたときは「見終わった」のまま
    marks[path] = done ? Mark(0, dur, now, true) : (was && pos < 30 ? Mark(0, dur, now, true) : Mark(pos, dur, now, false));
    notifyListeners();
    await _save();
  }

  Future<void> setDone(String path, bool done) async {
    final m = marks[path];
    marks[path] = Mark(0, m?.dur ?? 0, DateTime.now().millisecondsSinceEpoch, done);
    notifyListeners();
    await _save();
  }

  bool isDone(String path) => marks[path]?.done ?? false;

  /// 続きから見る：途中の物と、シリーズの次の話。新しい順
  List<(Title, VideoFile, Mark?)> continueWatching(List<Title> titles) {
    final out = <(Title, VideoFile, Mark?, int)>[];
    for (final t in titles) {
      if (t.kind == TitleKind.series) {
        // 最後に触った話
        Episode? last;
        Mark? lm;
        final eps = episodesOf(t);
        for (final e in eps) {
          final m = marks[e.file.path];
          if (m != null && (lm == null || m.at > lm.at)) {
            last = e;
            lm = m;
          }
        }
        if (last == null) continue;
        if (!lm!.done && lm.pos > 10) {
          out.add((t, last.file, lm, lm.at));
        } else if (lm.done) {
          final i = eps.indexOf(last);
          final next = eps.skip(i + 1).where((e) => !isDone(e.file.path) && e.season != 0).firstOrNull;
          if (next != null) out.add((t, next.file, marks[next.file.path], lm.at));
        }
      } else {
        for (final f in t.files) {
          final m = marks[f.path];
          if (m != null && !m.done && m.pos > 10) out.add((t, f, m, m.at));
        }
      }
    }
    out.sort((a, b) => b.$4.compareTo(a.$4));
    return [for (final o in out.take(20)) (o.$1, o.$2, o.$3)];
  }

  /// シリーズで次に見る話（見ていない最初の話。全部見たら最初）
  Episode? nextEpisode(Title t) {
    final cw = continueWatching([t]);
    final eps = episodesOf(t);
    if (cw.isNotEmpty) return eps.where((e) => e.file.path == cw.first.$2.path).firstOrNull;
    return eps.where((e) => !isDone(e.file.path) && e.season != 0).firstOrNull ?? eps.firstOrNull;
  }
}
