import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' hide Title;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app.dart';
import '../core/clicker.dart';
import 'click_wheel.dart';
import 'hud/hud_theme.dart';
import 'hud/hud_widgets.dart';
import 'ipod_theme.dart';
import 'menu.dart';
import 'menus.dart';
import 'settings_screen.dart';
import 'widgets.dart';

/// 本体（Theta Music Hatch の Theta スキンの配置をそのまま）。
/// 縦向き：上にタブ付きの一覧、下に動画のパネルとクリックホイール。
/// 横向き（タブレット・PC）：左に一覧、右にパネルとホイール。スマホを横にしたら全画面。
/// 再生は画面と別に動いているので、再生中も一覧を自由に見て回れる
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

/// 再生中のパネルのホイールの役目：seek＝ふだん（回すと早送り・戻し）、volume＝音量（中央で切り替え）
enum NowMode { seek, volume }

class _ShellState extends State<Shell> implements Nav {
  final List<IPodScreen> _stack = [];
  bool _forward = true;
  Timer? _seekTimer;
  late List<ThetaTab> _tabs = thetaTabs();

  @override
  void initState() {
    super.initState();
    nav = this;
    playingPath = () => services.playback.file?.path;
    _modes = modeMenu(_selectTab);
    _pushInternal(_modes);
    if (!services.settings.configured) {
      _selectTab(_tabs.length - 1, animate: false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSettingsIfNeeded());
    } else {
      _selectTab(services.progress.continueWatching(services.library.titles).isNotEmpty ? 0 : 1, animate: false);
      if (services.library.titles.isEmpty) services.library.scan();
    }
    services.settings.addListener(_onChange);
    services.playback.addListener(_onPlayback);
    services.library.addListener(_onLibrary);
    Clicker.prepare();
  }

  void _openSettingsIfNeeded() {
    if (!services.settings.configured) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    }
  }

  void _onChange() => setState(() {});

  String? _lastFile;
  void _onPlayback() {
    final f = services.playback.file?.path;
    if (f != null && f != _lastFile) {
      // 選んで再生を始めたら、ホイールは再生中のパネルへ（一覧はそのまま）
      _focusNow = true;
      _nowMode = NowMode.seek;
    }
    _lastFile = f;
    setState(() {});
  }

  void _onLibrary() {
    final tabs = thetaTabs();
    if (tabs.length != _tabs.length) {
      _tabs = tabs;
      if (_tab >= _tabs.length) _tab = -1;
    }
    setState(() {});
  }

  IPodScreen get _top => _stack.last;

  void _pushInternal(IPodScreen s) {
    if (_stack.isNotEmpty) {
      _stack.last.removeListener(_onChange);
      _stack.last.detach();
    }
    _stack.add(s);
    s.attach();
    s.addListener(_onChange);
  }

  @override
  void push(IPodScreen s) {
    setState(() {
      _forward = true;
      _focusNow = false;
      _pushInternal(s);
    });
  }

  @override
  void pop() {
    if (_stack.length <= 1) return;
    setState(() {
      _forward = false;
      final s = _stack.removeLast();
      if (_stack.length == 1) _tab = -1; // モードの一覧に戻った
      s.removeListener(_onChange);
      s.detach();
      Future<void>.delayed(const Duration(milliseconds: 400), s.dispose);
      _top.attach();
      _top.addListener(_onChange);
    });
  }

  @override
  void showNowPlaying() => _setFocusNow(true);

  /// 今のモード（左のタブ）。モードの一覧にいるときは -1
  int _tab = -1;
  late MenuScreen _modes;

  /// いちばん上（モードの一覧）で MENU を押して、左のタブを文字付きに広げている（Music Hatch 1.7.0）
  bool _railOpen = false;

  void _selectTab(int i, {bool animate = true}) {
    _focusNow = false;
    _railOpen = false;
    void go() {
      _forward = true;
      for (final s in _stack) {
        s.removeListener(_onChange);
        s.detach();
        if (s != _modes) Future<void>.delayed(const Duration(milliseconds: 400), s.dispose);
      }
      _stack
        ..clear()
        ..add(_modes);
      _modes.selected = i;
      _tab = i;
      _pushInternal(_tabs[i].root());
    }

    animate ? setState(go) : go();
  }

  // ---------------------------------------------------------------- フォーカス（Theta Music Hatch と同じ）
  // 一覧にフォーカス：回す＝選ぶ、中央＝決定、MENU＝戻る（いちばん上なら再生中へ）
  // 再生中にフォーカス：回す＝早送り・戻し（中央で音量に切り替え）、中央長押し＝全画面、MENU＝一覧へ

  bool _focusNow = false;
  NowMode _nowMode = NowMode.seek;
  Timer? _modeTimer;

  void _setFocusNow(bool on) {
    if (_focusNow == on && _nowMode == NowMode.seek) return;
    _modeTimer?.cancel();
    setState(() {
      _focusNow = on;
      _nowMode = NowMode.seek;
    });
  }

  void _setNowMode(NowMode m) {
    _modeTimer?.cancel();
    setState(() => _nowMode = m);
    if (m == NowMode.volume) {
      _modeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _nowMode = NowMode.seek);
      });
    }
  }

  bool get _nowFocused => _focusNow && services.playback.hasMedia;

  WheelGuide? get _guide {
    if (!services.settings.wheelGuide) return null;
    if (_nowFocused) {
      return WheelGuide(
        menu: '一覧へ',
        center: _nowMode == NowMode.volume ? 'SEEK' : 'VOLUME',
        centerHold: '長押し 全画面',
        ring: _nowMode == NowMode.volume ? '←  VOLUME  →' : '←  SEEK  →',
      );
    }
    final top = _top;
    final list = top is MenuScreen && top.items.isNotEmpty;
    return WheelGuide(
      menu: _stack.length > 1
          ? '上の階層へ'
          : !_railOpen && !services.settings.tabLabels
          ? 'タブを広げる'
          : services.playback.hasMedia
          ? '再生中へ'
          : (_railOpen ? 'タブをたたむ' : null),
      center: list ? 'SELECT' : null,
      centerHold: services.playback.hasMedia
          ? '長押し 全画面'
          : (list && top.items[top.selected].onLong != null ? '長押し 見た' : null),
      ring: list ? '←  SELECT  →' : null,
    );
  }

  String? _toast;
  Timer? _toastTimer;

  @override
  void toast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _click() {
    if (services.settings.haptics) HapticFeedback.selectionClick();
    if (services.settings.clicker) Clicker.click();
  }

  void _onTick(int dir) {
    _click();
    final pb = services.playback;
    if (_nowFocused) {
      if (_nowMode == NowMode.volume) {
        pb.changeVolume(dir * 0.04);
        _setNowMode(NowMode.volume);
      } else {
        pb.seekBy(Duration(seconds: 10 * dir));
      }
      return;
    }
    _top.onScroll(dir);
  }

  void _onButton(WheelButton b) {
    if (services.settings.haptics) HapticFeedback.lightImpact();
    if (services.settings.clicker) Clicker.click(volume: 0.8);
    final pb = services.playback;
    switch (b) {
      case WheelButton.menu:
        if (_nowFocused) {
          _setFocusNow(false);
        } else if (_stack.length > 1) {
          pop();
        } else if (!_railOpen && !services.settings.tabLabels) {
          setState(() => _railOpen = true); // いちばん上 → 左のタブを文字付きに広げる
        } else if (pb.hasMedia) {
          _railOpen = false;
          _setFocusNow(true); // もう一度 MENU → 再生中へ
        } else if (_railOpen) {
          setState(() => _railOpen = false);
        }
      case WheelButton.select:
        if (_nowFocused) {
          _setNowMode(_nowMode == NowMode.volume ? NowMode.seek : NowMode.volume);
        } else {
          _top.onSelect();
        }
      case WheelButton.playPause:
        if (pb.hasMedia) pb.toggle();
      case WheelButton.next:
        if (pb.nextEpisode != null) {
          pb.next();
        } else {
          pb.seekBy(const Duration(seconds: 30));
        }
      case WheelButton.previous:
        pb.previous();
    }
  }

  void _holdStart(WheelButton b) {
    final pb = services.playback;
    if (b == WheelButton.select || b == WheelButton.menu) {
      if (services.settings.haptics) HapticFeedback.heavyImpact();
      if (b == WheelButton.select) {
        if (pb.hasMedia) {
          _openFullscreen();
        } else {
          _top.onLongSelect();
        }
      }
      return;
    }
    // ◀◀・▶▶ の長押し：早送り・巻き戻し（だんだん速く）
    final d = b == WheelButton.next ? 1 : -1;
    _seekTimer?.cancel();
    var n = 0;
    _seekTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      n++;
      pb.seekBy(Duration(seconds: d * (n > 12 ? 30 : 10)));
    });
  }

  void _holdEnd(WheelButton b) => _seekTimer?.cancel();

  // ---------------------------------------------------------------- 全画面

  bool _fullscreen = false;

  Future<void> _openFullscreen() async {
    if (_fullscreen || !services.playback.hasMedia) return;
    _fullscreen = true;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const FullscreenPlayer(),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    _fullscreen = false;
    // 全画面の裏で向きが変わっていても、閉じたときの向きを「前の向き」にする
    // （縦で全画面 → 横に回して閉じたとき、縦→横と見なしてまた全画面にしないように）
    if (mounted) _orientation = MediaQuery.orientationOf(context);
  }

  bool get _phone => Platform.isAndroid || Platform.isIOS;

  /// 前に描いたときの向き（縦 → 横に変わった瞬間を見分ける）
  Orientation? _orientation;

  @override
  void dispose() {
    _seekTimer?.cancel();
    _toastTimer?.cancel();
    _modeTimer?.cancel();
    services.settings.removeListener(_onChange);
    services.playback.removeListener(_onPlayback);
    services.library.removeListener(_onLibrary);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final wheelColors = IPodColors(
      bodyTop: p.bg,
      bodyBottom: p.bg,
      wheel: p.raised,
      wheelEdge: p.line,
      wheelLabel: p.muted,
      center: p.panel,
      centerEdge: p.accent,
    );
    Widget wheel(double size) => ClickWheel(
      size: size,
      colors: wheelColors,
      onTick: _onTick,
      onButton: _onButton,
      onHoldStart: _holdStart,
      onHoldEnd: _holdEnd,
      guide: _guide,
    );
    final mq = MediaQuery.of(context);
    // 再生中にスマホを縦から横に変えた瞬間だけ全画面にする（縦に戻すと全画面の方が閉じる）。
    // 最初から横向きで再生を始めたとき・横向きのまま全画面を閉じたときは、勝手に全画面にしない
    // （全画面はダブルタップ・全画面ボタン・中央の長押しで）
    final o = mq.orientation;
    if (_phone &&
        _orientation == Orientation.portrait &&
        o == Orientation.landscape &&
        services.playback.hasMedia &&
        !_fullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openFullscreen());
    }
    _orientation = o;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: PopScope(
        canPop: _stack.length <= 1 && !_nowFocused,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_nowFocused) {
            _setFocusNow(false);
          } else {
            pop();
          }
        },
        child: Scaffold(
          backgroundColor: p.bg,
          body: CustomPaint(
            painter: BackdropPainter(p),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, c) {
                  final list = _list(p);
                  Widget nowPanel() => NowPanel(
                    focused: _nowFocused,
                    mode: _nowMode,
                    idlePoster: _top.poster,
                    onTap: () => _setFocusNow(true),
                    onDoubleTap: _openFullscreen,
                  );
                  // 横並びにするか（Music Hatch 1.7.0 と同じ）：Auto は幅 600 以上で、幅 ≥ 高さ × 0.75
                  // （Z Fold を広げた画面・タブレットの横）。縦に持ったスマホ・タブレットは縦並び。設定で Wide・Tall に固定できる
                  final layout = services.settings.thetaLayout;
                  final wide =
                      layout == 'wide' || (layout == 'auto' && c.maxWidth >= 600 && c.maxWidth >= c.maxHeight * 0.75);
                  if (wide) {
                    final right = min(c.maxWidth * 0.44, 560.0);
                    final w = min(right - 40, c.maxHeight * 0.42);
                    return Row(
                      children: [
                        Expanded(child: list),
                        SizedBox(
                          width: right,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
                            child: Column(children: [nowPanel(), const Spacer(), wheel(w), const SizedBox(height: 12)]),
                          ),
                        ),
                      ],
                    );
                  }
                  // 縦向き：上に一覧、下に動画とホイール
                  final w = min(c.maxWidth * 0.58, c.maxHeight * 0.26);
                  return Column(
                    children: [
                      Expanded(child: list),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                        // 動画のパネルは高さの 3 割まで（一覧を残す）
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: c.maxHeight * 0.3),
                          child: Center(child: nowPanel()),
                        ),
                      ),
                      Padding(padding: const EdgeInsets.only(bottom: 10), child: wheel(w)),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 左のタブと一覧（今の画面）
  Widget _list(Palette p) {
    final top = _top;
    top.active = !_nowFocused;
    final depth = _stack.length;
    final code = _tab < 0 || _tab >= _tabs.length ? 'MOVIE' : _tabs[_tab].label;
    final panel = Container(
      decoration: BoxDecoration(
        color: p.pop ? p.panel : null,
        border: Border.all(color: p.line, width: p.lineWidth),
        borderRadius: p.rounded ? BorderRadius.circular(p.radius) : null,
      ),
      clipBehavior: p.rounded ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 36,
                  child: depth > 1
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: '戻る（MENU）',
                          onPressed: pop,
                          icon: Icon(Icons.chevron_left, color: p.accent),
                        )
                      : Center(child: Container(width: 6, height: 6, color: p.accent)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        depth > 2 ? 'LIB.$code / ${depth - 2}' : 'LIB.$code',
                        style: TextStyle(color: p.faint, fontSize: 10, letterSpacing: 2, fontFamily: p.mono),
                      ),
                      Text(
                        top.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.fg,
                          fontSize: 20,
                          height: 1.2,
                          fontFamily: p.display,
                          fontWeight: p.pop ? FontWeight.bold : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (services.library.scanning)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stripes(color: p.line),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (cur, prev) => Stack(children: [...prev, ?cur]),
                transitionBuilder: (child, anim) {
                  final incoming = child.key == top.key;
                  final begin = incoming ? Offset(_forward ? 1 : -1, 0) : Offset(_forward ? -1 : 1, 0);
                  return SlideTransition(
                    position: Tween(begin: begin, end: Offset.zero).animate(anim),
                    child: child,
                  );
                },
                child: KeyedSubtree(
                  key: top.key,
                  child: ListenableBuilder(listenable: top, builder: (context, _) => top.build(context)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    // いちばん上の階層でタブを文字付きに広げたら、タブだけでモードを選ぶ（同じ一覧を 2 つ出さない。Music Hatch 1.7.1）
    final labels = services.settings.tabLabels || _railOpen;
    final full = _tab < 0 && labels;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (full)
              Expanded(
                child: Listener(
                  onPointerDown: (_) => _setFocusNow(false),
                  child: _withToast(
                    // ホイールで選んでいるモード（_modes.selected）を光らせる。SELECT・タップで開く
                    ThetaTabs(tabs: _tabs, active: _modes.selected, width: c.maxWidth, onSelect: _selectTab),
                    p,
                  ),
                ),
              )
            else ...[
              ThetaTabs(tabs: _tabs, active: _tab, width: labels ? 116 : 40, onSelect: _selectTab),
              Expanded(
                // 一覧を触ったら、ホイールのフォーカスも一覧へ
                child: Listener(
                  onPointerDown: (_) => _setFocusNow(false),
                  child: CustomPaint(
                    foregroundPainter: p.rounded ? null : CornersPainter(_nowFocused ? p.line : p.accent),
                    child: _withToast(panel, p),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _withToast(Widget lcd, Palette p) {
    return Stack(
      children: [
        Positioned.fill(child: lcd),
        if (_toast != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: p.raised,
                  border: Border.all(color: p.accent),
                  borderRadius: BorderRadius.circular(p.rounded ? 8 : 0),
                ),
                child: Text(
                  _toast!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.fg, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: p.mono),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 一覧の左に付く縦のタブ（Theta Music Hatch 1.7.1 の ThetaTabs と同じ考え方）。
/// 幅 40 は印だけ（高ければ縦書き）、90 以上で印と名前を横に並べる。いちばん上の階層で広げたときは
/// リストの場所いっぱい（モードの一覧の代わり）。棚が多くて低くなりすぎるときは、高さを保ってスクロール
class ThetaTabs extends StatelessWidget {
  final List<ThetaTab> tabs;
  final int active;
  final void Function(int) onSelect;
  final double width;
  const ThetaTabs({super.key, required this.tabs, required this.active, required this.onSelect, this.width = 40});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    double gap(int i) => i == 0 ? 0 : (tabs[i].group != tabs[i - 1].group ? 10 : 4);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: width,
      child: LayoutBuilder(
        builder: (context, c) {
          // 横書き（印＋名前）なら 1 行の高さで足りる。縦書きは字が収まる高さが要る
          final minH = c.maxWidth >= 90 ? (c.maxWidth >= 200 ? 52.0 : 44.0) : 72.0;
          final gaps = [for (var i = 0; i < tabs.length; i++) gap(i)].fold<double>(0, (a, b) => a + b);
          if ((c.maxHeight - gaps) / tabs.length >= minH) {
            return Column(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) SizedBox(height: gap(i)),
                  Expanded(child: _tab(p, i)),
                ],
              ],
            );
          }
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) SizedBox(height: gap(i)),
                // ホイールで選んでいるタブが見えるように
                SizedBox(
                  height: minH,
                  child: i == active ? _Visible(child: _tab(p, i)) : _tab(p, i),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 縦書きの字：英字は横に寝かせる。日本語（棚の名前）は縦に積む（4 字まで）
  Widget _vertical(Palette p, ThetaTab t, Color fg) {
    final ascii = RegExp(r'^[\x20-\x7E]+$').hasMatch(t.label);
    if (ascii) {
      return RotatedBox(
        quarterTurns: 3,
        child: Text(
          t.label,
          style: TextStyle(fontSize: 12, letterSpacing: 1.5, fontFamily: p.mono, color: fg),
        ),
      );
    }
    final chars = t.label.characters.take(4).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final ch in chars) Text(ch, style: TextStyle(fontSize: 13, height: 1.1, color: fg))],
    );
  }

  Widget _tab(Palette p, int i) {
    final t = tabs[i];
    final on = i == active;
    final g = p.group(t.group);
    final bg = on ? (p.pop ? g : p.accent) : (p.pop ? p.panel : p.bg);
    final fg = on ? (p.pop && t.group != 0 ? p.fg : p.onAccent) : p.fg;
    final shape = p.rounded ? const BorderRadius.horizontal(left: Radius.circular(8)) : null;
    return Semantics(
      button: true,
      selected: on,
      label: t.title,
      child: GestureDetector(
        onTap: () => onSelect(i),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: on && !p.pop ? p.accent : p.line, width: p.lineWidth),
            borderRadius: shape,
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(width: 3, height: 18, color: on ? fg : g),
              ),
              LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth >= 90) {
                    // 印と名前を横に（英字のタブは略号、棚は名前そのもの）
                    final big = c.maxWidth >= 200;
                    final ascii = RegExp(r'^[\x20-\x7E]+$').hasMatch(t.label);
                    return Padding(
                      padding: EdgeInsets.only(left: big ? 16 : 8, right: 8),
                      child: Row(
                        children: [
                          Icon(t.icon, size: big ? 22 : 18, color: fg),
                          SizedBox(width: big ? 12 : 6),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                big ? t.title : (ascii ? t.label : t.title),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: big ? 16 : 12,
                                  letterSpacing: ascii && !big ? 1.2 : 0.5,
                                  fontFamily: p.mono,
                                  color: fg,
                                ),
                              ),
                            ),
                          ),
                          if (big && t.count != null)
                            Text(
                              '${t.count}',
                              style: TextStyle(fontSize: 12, fontFamily: p.mono, color: on ? fg : p.faint),
                            ),
                        ],
                      ),
                    );
                  }
                  return Center(
                    child: c.maxWidth < 30 || c.maxHeight < 64
                        ? Icon(t.icon, size: 19, color: fg)
                        : FittedBox(fit: BoxFit.scaleDown, child: _vertical(p, t, fg)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 作られたら（選ぶ場所が変わったら）スクロールして見えるようにする
class _Visible extends StatefulWidget {
  final Widget child;
  const _Visible({required this.child});
  @override
  State<_Visible> createState() => _VisibleState();
}

class _VisibleState extends State<_Visible> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 下にはみ出していれば下端に、上にはみ出していれば上端に合わせる（見えていれば動かさない）
      Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _fmt(Duration d) => fmtDuration(d.inSeconds);

/// 再生中のパネル（Music Hatch のジャケットの場所に動画）。16:9。
/// 何も再生していないときは、一覧で選んでいる作品のポスター。押すとフォーカス、2 回押すと全画面
class NowPanel extends StatelessWidget {
  final bool focused;
  final NowMode mode;
  final String? idlePoster;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  const NowPanel({
    super.key,
    required this.focused,
    required this.mode,
    required this.idlePoster,
    required this.onTap,
    required this.onDoubleTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final pb = services.playback;
    final radius = p.rounded ? BorderRadius.circular(p.radius) : BorderRadius.zero;
    final label = TextStyle(color: p.muted, fontSize: 11, fontFamily: p.mono, letterSpacing: 1);

    final Widget body;
    if (!pb.hasMedia) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          if (idlePoster != null)
            NasImage(idlePoster, key: ValueKey(idlePoster), fit: BoxFit.contain)
          else
            ColoredBox(
              color: p.raised,
              child: Icon(Icons.movie_outlined, size: 48, color: p.faint),
            ),
          Positioned(
            left: 10,
            bottom: 8,
            child: Text(
              '[ NOW ] 一覧から選んで中央ボタンで再生',
              style: label.copyWith(shadows: [Shadow(color: p.bg, blurRadius: 4)]),
            ),
          ),
        ],
      );
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: Video(controller: pb.video, controls: NoVideoControls),
          ),
          // 上：作品名と話。下：進み具合（回すとシーク／音量）
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '[ NOW ]',
                    style: TextStyle(color: p.accent, fontSize: 11, letterSpacing: 2, fontFamily: p.mono),
                  ),
                  const SizedBox(width: 6),
                  Icon(pb.playing ? Icons.play_arrow : Icons.pause, size: 15, color: p.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${pb.title?.displayName ?? ''}  ${pb.episode == null ? '' : pb.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  // 全画面ボタン（横向きのまま再生を始めたときなど）
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onDoubleTap,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.fullscreen, size: 22, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: _Progress(mode: mode, focused: focused),
            ),
          ),
          if (pb.error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '再生できません：${pb.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: pb.hasMedia ? onDoubleTap : null,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: CustomPaint(
          foregroundPainter: p.rounded ? null : CornersPainter(focused ? p.accent : p.line),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: focused ? p.accent : p.line, width: focused ? 2 : p.lineWidth),
            ),
            padding: EdgeInsets.all(focused ? 0 : 1),
            child: ClipRRect(borderRadius: radius, child: body),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  final NowMode mode;
  final bool focused;
  const _Progress({required this.mode, required this.focused});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final pl = services.playback.player;
    final label = TextStyle(color: Colors.white70, fontSize: 11, fontFamily: p.mono, letterSpacing: 1);
    if (mode == NowMode.volume && focused) {
      return Row(
        children: [
          Icon(Icons.volume_down, size: 16, color: p.accent),
          const SizedBox(width: 6),
          Expanded(child: HudProgress(services.playback.volume)),
          const SizedBox(width: 6),
          Text('VOL ${(services.playback.volume * 100).round()}', style: label),
        ],
      );
    }
    return StreamBuilder<Duration>(
      stream: pl.stream.position,
      builder: (context, snap) {
        final pos = snap.data ?? pl.state.position;
        final dur = pl.state.duration;
        final v = dur.inMilliseconds == 0 ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
        final remain = dur - pos;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            HudProgress(v.clamp(0.0, 1.0)),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(_fmt(pos), style: label),
                const Spacer(),
                if (focused) Text('◀ SEEK ▶', style: label.copyWith(color: p.accent)),
                const Spacer(),
                Text('-${_fmt(remain.isNegative ? Duration.zero : remain)}', style: label),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 全画面（同じプレーヤーをそのまま大きく。閉じても再生は続く）
class FullscreenPlayer extends StatefulWidget {
  const FullscreenPlayer({super.key});
  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  bool get _mobile => Platform.isAndroid || Platform.isIOS;
  bool _wasLandscape = false;

  @override
  void initState() {
    super.initState();
    if (_mobile) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    services.playback.addListener(_onChange);
  }

  void _onChange() {
    if (!services.playback.hasMedia && mounted) Navigator.of(context).maybePop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    services.playback.removeListener(_onChange);
    if (_mobile) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _pickTrack({required bool audio}) async {
    final player = services.playback.player;
    final tracks = player.state.tracks;
    final list = audio ? tracks.audio : tracks.subtitle;
    final cur = audio ? player.state.track.audio.id : player.state.track.subtitle.id;
    String name(String id, String? title, String? lang) {
      if (id == 'auto') return '自動';
      if (id == 'no') return audio ? '音声なし' : '字幕なし';
      final parts = [title, lang].where((x) => x != null && x.isNotEmpty).join(' / ');
      return parts.isEmpty ? '#$id' : '#$id $parts';
    }

    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(audio ? '音声（二か国語など）' : '字幕')),
            for (final (i, t) in list.indexed)
              ListTile(
                leading: Icon(
                  (audio ? (t as AudioTrack).id : (t as SubtitleTrack).id) == cur
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(
                  audio
                      ? name((t as AudioTrack).id, t.title, t.language)
                      : name((t as SubtitleTrack).id, t.title, t.language),
                ),
                onTap: () => Navigator.of(ctx).pop(i),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    if (audio) {
      await player.setAudioTrack(tracks.audio[picked]);
    } else {
      await player.setSubtitleTrack(tracks.subtitle[picked]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pb = services.playback;
    // スマホを縦に戻したら閉じる（横にして開いたときだけ）
    final landscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (_mobile) {
      if (landscape) {
        _wasLandscape = true;
      } else if (_wasLandscape) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
    }
    final top = [
      IconButton(
        icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      Expanded(
        child: Text(
          '${pb.title?.displayName ?? ''}  ${pb.episode == null ? '' : pb.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
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
      if (pb.nextEpisode != null)
        IconButton(
          tooltip: '次の話',
          icon: const Icon(Icons.skip_next, color: Colors.white),
          onPressed: pb.next,
        ),
    ];
    final accent = Theme.of(context).colorScheme.primary;
    // 下の帯：付属の全画面ボタン（もう 1 枚全画面を重ねてしまい、抜けにくくなる）の代わりに「全画面を閉じる」
    Widget exit() => IconButton(
          tooltip: '全画面を閉じる',
          icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        );
    final mobileTheme = kDefaultMaterialVideoControlsThemeData.copyWith(
      topButtonBar: top,
      bottomButtonBar: [const MaterialPositionIndicator(), const Spacer(), exit()],
      seekBarThumbColor: accent,
      seekBarPositionColor: accent,
    );
    final desktopTheme = kDefaultMaterialDesktopVideoControlsThemeData.copyWith(
      topButtonBar: top,
      bottomButtonBar: [
        const MaterialDesktopPlayOrPauseButton(),
        const MaterialDesktopVolumeButton(),
        const MaterialDesktopPositionIndicator(),
        const Spacer(),
        exit(),
      ],
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: mobileTheme,
        fullscreen: mobileTheme,
        child: MaterialDesktopVideoControlsTheme(
          normal: desktopTheme,
          fullscreen: desktopTheme,
          child: Video(controller: pb.video, controls: _mobile ? MaterialVideoControls : MaterialDesktopVideoControls),
        ),
      ),
    );
  }
}
