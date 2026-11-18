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
          skipNext();
        case 'previous':
          skipPrevious();
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
    // 字幕を選び直したら、画像の字幕（DVD・BD）かどうかで描き方を切り替える
    _subs.add(p.stream.track.listen((t) => _applySubtitleRendering(t.subtitle)));
    // 新しい動画を開いたら、チャプターを読み直す
    _subs.add(p.stream.duration.listen((d) {
      if (d > Duration.zero) _loadChapters();
    }));
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
    final eps = episodesOf(t); // 選んだ並び順（放送順・時系列順など）で次へ
    final i = eps.indexWhere((e) => e.file.path == f.path);
    return i < 0 || i + 1 >= eps.length ? null : eps[i + 1];
  }

  Episode? get previousEpisode {
    final t = title, f = file;
    if (t == null || f == null) return null;
    final eps = episodesOf(t);
    final i = eps.indexWhere((e) => e.file.path == f.path);
    return i <= 0 ? null : eps[i - 1];
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
      chapters = const [];
      secondarySubtitle = 'no';
      try {
        await _native?.setProperty('secondary-sid', 'no');
      } catch (_) {}
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

  // ---------------------------------------------------------------- チャプター（HandBrake の MP4・mkv など）

  /// 今の動画のチャプター（題名と始まる時刻）。無ければ空
  List<(String, Duration)> chapters = const [];

  NativePlayer? get _native => _player?.platform is NativePlayer ? _player!.platform as NativePlayer : null;

  Future<void> _loadChapters() async {
    final n = _native;
    final out = <(String, Duration)>[];
    if (n != null) {
      try {
        final count = int.tryParse(await n.getProperty('chapter-list/count')) ?? 0;
        for (var i = 0; i < count; i++) {
          final title = await n.getProperty('chapter-list/$i/title');
          final time = double.tryParse(await n.getProperty('chapter-list/$i/time')) ?? 0;
          out.add((title.isEmpty ? 'チャプター ${i + 1}' : title, Duration(milliseconds: (time * 1000).round())));
        }
      } catch (_) {}
    }
    chapters = out;
    notifyListeners();
  }

  /// 今いるチャプターの番号（無ければ -1）
  int chapterAt(Duration pos) {
    var i = -1;
    for (var k = 0; k < chapters.length; k++) {
      if (chapters[k].$2 <= pos + const Duration(milliseconds: 500)) i = k;
    }
    return i;
  }

  Future<void> seekChapter(int i) async {
    if (i < 0 || i >= chapters.length) return;
    await player.seek(chapters[i].$2);
  }

  /// 次のチャプターへ。無ければ false（呼んだ側で次の話・早送りにする）
  bool nextChapter() {
    if (!hasMedia || chapters.isEmpty) return false;
    final i = chapterAt(player.state.position);
    if (i + 1 >= chapters.length) return false;
    seekChapter(i + 1);
    return true;
  }

  /// 前のチャプターへ（始まって 3 秒を過ぎていたら、今のチャプターの頭へ）。無ければ false
  bool previousChapter() {
    if (!hasMedia || chapters.isEmpty) return false;
    final pos = player.state.position;
    final i = chapterAt(pos);
    if (i < 0) return false;
    if (pos - chapters[i].$2 > const Duration(seconds: 3)) {
      seekChapter(i);
    } else if (i > 0) {
      seekChapter(i - 1);
    } else {
      player.seek(Duration.zero);
    }
    return true;
  }

  // ---------------------------------------------------------------- 字幕

  /// 2 つ目の字幕（同時に表示。文字の字幕だけ）。'no' で消す
  String secondarySubtitle = 'no';

  Future<void> setSecondarySubtitle(String id) async {
    final n = _native;
    if (n == null) return;
    await n.setProperty('secondary-sid', id);
    secondarySubtitle = id;
    notifyListeners();
  }

  /// 画像の字幕（DVD の VobSub・BD の PGS・DVB）は、アプリでは文字として描けないので mpv に描かせる。
  /// 文字の字幕は今までどおりアプリで描く（日本語の書体が確実なため）
  Future<void> _applySubtitleRendering(SubtitleTrack t) async {
    final n = _native;
    if (n == null) return;
    const bitmap = {'hdmv_pgs_subtitle', 'pgssub', 'dvd_subtitle', 'dvdsub', 'dvb_subtitle', 'dvbsub', 'xsub', 'vobsub'};
    final image = t.image == true || bitmap.contains((t.codec ?? '').toLowerCase());
    try {
      await n.setProperty('sub-visibility', image ? 'yes' : 'no');
    } catch (_) {}
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

  /// ▶▶（ホイール・車・Bluetooth・通知）：シリーズは次の話、映画はチャプターがあれば次のチャプター、無ければ 30 秒先へ
  Future<void> skipNext() async {
    if (!hasMedia) return;
    if (nextEpisode != null) return next();
    if (nextChapter()) return;
    await seekBy(const Duration(seconds: 30));
  }

  /// ◀◀：チャプターがあれば前のチャプター（今のチャプターの頭）、無ければ前の話（始まって 5 秒を過ぎていたら頭へ）
  Future<void> skipPrevious() async {
    if (!hasMedia) return;
    if (previousChapter()) return;
    await previous();
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
