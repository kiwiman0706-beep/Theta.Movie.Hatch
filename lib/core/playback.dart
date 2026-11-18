import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'library.dart';
import 'models.dart';
import 'progress.dart';
import 'settings.dart';

/// 再生（mpv）。画面とは別に持つので、一覧を見て回っている間も止まらない。
/// NAS で変換せず、mkv・HEVC・DTS・ARIB 字幕・二か国語の .ts も端末でそのまま再生する
class Playback extends ChangeNotifier {
  final AppSettings settings;
  final Library library;
  final Progress progress;

  Playback(this.settings, this.library, this.progress);

  /// mpv は初めて再生するときに作る（起動を軽く。テストでも画面を描けるように）
  Player? _player;
  Player get player => _player ??= _create();
  late final VideoController video = VideoController(player);
  final _subs = <StreamSubscription<dynamic>>[];

  Player _create() {
    final p = Player(configuration: const PlayerConfiguration(title: 'Theta Movie Hatch'));
    _subs.add(p.stream.playing.listen((_) => notifyListeners()));
    _subs.add(p.stream.completed.listen((done) {
      if (done) _ended();
    }));
    _subs.add(p.stream.error.listen((e) {
      error = e;
      notifyListeners();
    }));
    _subs.add(p.stream.position.listen((pos) {
      if ((pos.inSeconds - _lastSaved).abs() >= 10) save();
    }));
    _subs.add(p.stream.volume.listen((_) => notifyListeners()));
    return p;
  }

  Title? title;
  VideoFile? file;
  String? error;
  int _lastSaved = 0;

  bool get hasMedia => file != null;
  bool get playing => _player?.state.playing ?? false;
  double get volume => (_player?.state.volume ?? 100) / 100;

  Episode? get episode => title?.episodes.where((e) => e.file.path == file?.path).firstOrNull;

  Episode? get nextEpisode {
    final t = title, f = file;
    if (t == null || f == null) return null;
    final i = t.episodes.indexWhere((e) => e.file.path == f.path);
    return i < 0 || i + 1 >= t.episodes.length ? null : t.episodes[i + 1];
  }

  Episode? get previousEpisode {
    final t = title, f = file;
    if (t == null || f == null) return null;
    final i = t.episodes.indexWhere((e) => e.file.path == f.path);
    return i <= 0 ? null : t.episodes[i - 1];
  }

  /// 「作品名  S01E03 サブタイトル」
  String get label {
    final t = title, f = file;
    if (t == null || f == null) return '';
    final e = episode;
    if (e == null) return t.displayName + (f.label.isEmpty ? '' : ' - ${f.label}');
    return '${e.code} ${e.title}'.trim();
  }

  Future<void> play(Title t, VideoFile f, {bool fromStart = false}) async {
    if (file != null) await save();
    title = t;
    file = f;
    error = null;
    notifyListeners();
    try {
      final u = await library.source.stream(f.path);
      final resume = fromStart ? 0 : progress.resumeAt(f.path);
      _lastSaved = resume;
      await player.open(Media(u.url, httpHeaders: u.headers, start: Duration(seconds: resume)));
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (hasMedia) await player.playOrPause();
  }

  Future<void> seekBy(Duration d) async {
    if (!hasMedia) return;
    final st = player.state;
    var to = st.position + d;
    if (to < Duration.zero) to = Duration.zero;
    if (st.duration > Duration.zero && to > st.duration) to = st.duration - const Duration(seconds: 1);
    await player.seek(to);
  }

  Future<void> changeVolume(double delta) async {
    if (hasMedia) await player.setVolume(((volume + delta).clamp(0.0, 1.0)) * 100);
  }

  Future<void> next() async {
    final n = nextEpisode;
    if (n != null) await play(title!, n.file);
  }

  /// 前の話。始まって 5 秒を過ぎていたら、その話の頭へ（iPod と同じ）
  Future<void> previous() async {
    if (!hasMedia) return;
    if (player.state.position.inSeconds > 5) return player.seek(Duration.zero);
    final p = previousEpisode;
    if (p != null) await play(title!, p.file, fromStart: true);
  }

  Future<void> stop() async {
    await save();
    await _player?.stop();
    title = null;
    file = null;
    notifyListeners();
  }

  Future<void> save({bool ended = false}) async {
    final f = file;
    if (f == null) return;
    final st = player.state;
    final dur = st.duration.inSeconds;
    final pos = ended ? dur : st.position.inSeconds;
    if (dur <= 0 && pos <= 0) return;
    _lastSaved = pos;
    await progress.update(f.path, pos, dur, doneMarginSec: settings.doneMarginSec);
  }

  /// 見終わったら記録して、シリーズなら次の話へ
  Future<void> _ended() async {
    await save(ended: true);
    final n = nextEpisode;
    if (n != null && n.season != 0) {
      await play(title!, n.file, fromStart: true);
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }
}
