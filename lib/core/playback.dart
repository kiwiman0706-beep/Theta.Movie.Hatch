import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'library.dart';
import 'media_session.dart';
import 'models.dart';
import 'progress.dart';
import 'settings.dart';

/// 再生（mpv）。画面とは別に持つので、一覧を見て回っている間も止まらない。
/// NAS で変換せず、mkv・HEVC・DTS・ARIB 字幕・二か国語の .ts も端末でそのまま再生する
class Playback extends ChangeNotifier {
  final AppSettings settings;
  final Library library;
  final Progress progress;

  Playback(this.settings, this.library, this.progress) {
    // 車・Bluetooth・イヤホンのボタン
    MediaSessionBridge.listen((b, pos) {
      if (!hasMedia) return;
      switch (b) {
        case 'play':
          player.play();
        case 'pause':
          player.pause();
        case 'next':
          nextEpisode != null ? next() : seekBy(const Duration(seconds: 30));
        case 'previous':
          previous();
        case 'forward':
          seekBy(const Duration(seconds: 30));
        case 'rewind':
          seekBy(const Duration(seconds: -10));
        case 'seek':
          if (pos != null) player.seek(Duration(milliseconds: pos));
      }
    });
  }

  /// mpv は初めて再生するときに作る（起動を軽く。テストでも画面を描けるように）
  Player? _player;
  Player get player => _player ??= _create();
  late final VideoController video = VideoController(player);
  final _subs = <StreamSubscription<dynamic>>[];

  /// mpv の警告・エラー（設定の「再生のログ」で見られる。音が出ないときなどの手がかり）
  final log = <String>[];

  Player _create() {
    final p = Player(
        configuration: const PlayerConfiguration(title: 'Theta Movie Hatch', logLevel: MPVLogLevel.warn));
    _subs.add(p.stream.log.listen((l) {
      log.add('[${l.level}] ${l.prefix}: ${l.text.trim()}');
      if (log.length > 300) log.removeAt(0);
    }));
    // 再生・一時停止を Android に知らせる（オーディオフォーカスとメディアセッション）
    _subs.add(p.stream.playing.listen((playing) {
      MediaSessionBridge.state(playing: playing, position: p.state.position);
      notifyListeners();
    }));
    _subs.add(p.stream.duration.listen((d) {
      if (d > Duration.zero) MediaSessionBridge.meta(title?.displayName ?? '', label, d);
    }));
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
      await applyAudioOutput();
      await player.open(Media(u.url, httpHeaders: u.headers, start: Duration(seconds: resume)));
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  /// 音の出し方（Android）。media_kit の既定は OpenSL ES だが、端末によって音が出ないことがあるので、
  /// 既定は AudioTrack（mpv-android と同じ）。設定で OpenSL ES にも変えられる
  String? _appliedAo;
  Future<void> applyAudioOutput() async {
    if (!Platform.isAndroid) return;
    // 選んだ方式を先に、だめならもう片方（同梱の mpv にあるのは audiotrack と opensles だけ）
    final ao = settings.audioOutput == 'opensles' ? 'opensles,audiotrack' : 'audiotrack,opensles';
    if (ao == _appliedAo) return;
    final pl = player.platform;
    if (pl is NativePlayer) {
      await pl.setProperty('ao', ao);
      // 再生中に変えたときは、音の出口を開き直す
      if (_appliedAo != null && hasMedia) await pl.command(['ao-reload']);
      _appliedAo = ao;
      log.add('[info] ao=$ao');
    }
  }

  /// 今の音声の様子（設定の「再生のログ」の先頭に出す）
  Future<String> audioInfo() async {
    final pl = _player;
    if (pl == null) return '再生していません';
    final st = pl.state;
    final a = st.audioParams;
    final t = st.track.audio;
    var ao = '';
    var cur = '';
    final n = pl.platform;
    if (n is NativePlayer) {
      try {
        ao = await n.getProperty('ao');
        cur = await n.getProperty('current-ao');
      } catch (_) {}
    }
    return [
      '音量 ${st.volume.round()}　ミュート ${st.volume == 0 ? 'はい' : 'いいえ'}',
      '音声トラック #${t.id} ${t.title ?? ''} ${t.language ?? ''}（全 ${st.tracks.audio.length - 2} 本）',
      '音声 ${a.format ?? '-'} ${a.sampleRate ?? '-'}Hz ${a.channels ?? '-'}',
      '出力 ao=$ao  使用中=$cur',
    ].join('\n');
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
    await MediaSessionBridge.stop();
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
