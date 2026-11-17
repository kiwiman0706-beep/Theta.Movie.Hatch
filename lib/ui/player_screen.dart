import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app.dart';
import '../core/models.dart';

/// 再生（mpv。mkv・HEVC・DTS・ARIB 字幕・二か国語の .ts も端末でそのまま再生する＝NAS で変換しない）
class PlayerScreen extends StatefulWidget {
  final Title title;
  final VideoFile file;
  final bool fromStart;
  const PlayerScreen({super.key, required this.title, required this.file, this.fromStart = false});

  static Future<void> open(BuildContext context, Title t, VideoFile f, {bool fromStart = false}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerScreen(title: t, file: f, fromStart: fromStart),
      ));

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = Player(configuration: const PlayerConfiguration(title: 'Theta Movie Hatch'));
  late final VideoController _video = VideoController(_player);
  final _subs = <StreamSubscription<dynamic>>[];
  late VideoFile _file = widget.file;
  String? _error;
  bool _ended = false;
  int _lastSaved = 0;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  Episode? get _episode => widget.title.episodes.where((e) => e.file.path == _file.path).firstOrNull;

  Episode? get _next {
    final eps = widget.title.episodes;
    final i = eps.indexWhere((e) => e.file.path == _file.path);
    return i < 0 || i + 1 >= eps.length ? null : eps[i + 1];
  }

  @override
  void initState() {
    super.initState();
    if (_mobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
    _subs.add(_player.stream.position.listen((pos) {
      final sec = pos.inSeconds;
      if ((sec - _lastSaved).abs() >= 10) _save();
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) {
        _save(ended: true);
        if (mounted) setState(() => _ended = true);
      }
    }));
    _subs.add(_player.stream.error.listen((e) {
      if (mounted) setState(() => _error = e);
    }));
    _open(_file, fromStart: widget.fromStart);
  }

  Future<void> _open(VideoFile f, {bool fromStart = false}) async {
    final s = AppScope.of(context);
    setState(() {
      _file = f;
      _ended = false;
      _error = null;
    });
    try {
      final u = await s.library.source.stream(f.path);
      final resume = fromStart ? 0 : s.progress.resumeAt(f.path);
      _lastSaved = resume;
      await _player.open(Media(u.url, httpHeaders: u.headers, start: Duration(seconds: resume)));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save({bool ended = false}) async {
    final st = _player.state;
    final dur = st.duration.inSeconds;
    final pos = ended ? dur : st.position.inSeconds;
    if (dur <= 0 && pos <= 0) return;
    _lastSaved = pos;
    final s = AppScope.of(context);
    await s.progress.update(_file.path, pos, dur, doneMarginSec: s.settings.doneMarginSec);
  }

  @override
  void dispose() {
    _save();
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    if (_mobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const []);
    }
    super.dispose();
  }

  String get _label {
    final e = _episode;
    if (e == null) return widget.title.displayName + (_file.label.isEmpty ? '' : ' - ${_file.label}');
    return '${widget.title.displayName}  ${e.code} ${e.title}'.trim();
  }

  Future<void> _pickTrack({required bool audio}) async {
    final tracks = _player.state.tracks;
    final list = audio ? tracks.audio : tracks.subtitle;
    final cur = audio ? _player.state.track.audio : _player.state.track.subtitle;
    String name(dynamic t) {
      final id = t.id as String;
      if (id == 'auto') return '自動';
      if (id == 'no') return audio ? '音声なし' : '字幕なし';
      final parts = [t.title, t.language].where((x) => x != null && '$x'.isNotEmpty).join(' / ');
      return parts.isEmpty ? '#$id' : '#$id $parts';
    }

    final picked = await showModalBottomSheet<dynamic>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(audio ? '音声（二か国語など）' : '字幕')),
          for (final t in list)
            ListTile(
              leading: Icon(t.id == cur.id ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(name(t)),
              onTap: () => Navigator.of(ctx).pop(t),
            ),
        ]),
      ),
    );
    if (picked == null) return;
    if (audio) {
      await _player.setAudioTrack(picked as AudioTrack);
    } else {
      await _player.setSubtitleTrack(picked as SubtitleTrack);
    }
  }

  List<Widget> get _top => [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(_label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        IconButton(
          tooltip: '音声',
          icon: const Icon(Icons.audiotrack, color: Colors.white),
          onPressed: () => _pickTrack(audio: true),
        ),
        IconButton(
          tooltip: '字幕',
          icon: const Icon(Icons.subtitles, color: Colors.white),
          onPressed: () => _pickTrack(audio: false),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final next = _next;
    final video = Video(
      controller: _video,
      controls: _mobile ? MaterialVideoControls : MaterialDesktopVideoControls,
    );
    final mobileTheme = kDefaultMaterialVideoControlsThemeData.copyWith(
      topButtonBar: _top,
      seekBarThumbColor: Theme.of(context).colorScheme.primary,
      seekBarPositionColor: Theme.of(context).colorScheme.primary,
    );
    final desktopTheme = kDefaultMaterialDesktopVideoControlsThemeData.copyWith(topButtonBar: _top);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: MaterialVideoControlsTheme(
            normal: mobileTheme,
            fullscreen: mobileTheme,
            child: MaterialDesktopVideoControlsTheme(normal: desktopTheme, fullscreen: desktopTheme, child: video),
          ),
        ),
        if (_error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 72,
            child: Material(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('再生できません：$_error', style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        if (_ended && next != null)
          Positioned(
            right: 24,
            bottom: 96,
            child: FilledButton.icon(
              icon: const Icon(Icons.skip_next),
              label: Text('次の話 ${next.code} ${next.title}'.trim()),
              onPressed: () => _open(next.file),
            ),
          ),
        if (_ended && next == null)
          Positioned(
            right: 24,
            bottom: 96,
            child: FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('見終わりました'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
      ]),
    );
  }
}

