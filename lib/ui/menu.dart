import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'hud/hud_theme.dart';
import 'widgets.dart';

/// Theta Music Hatch の画面の仕組み（screens.dart）をそのまま持ってきたもの。
/// 一覧を 1 画面ずつ重ね、ホイールで選ぶ。Thetaスキン（HUD）の見た目だけ

/// 画面スタックの操作（Shell が実装）
abstract class Nav {
  BuildContext get context;
  void push(IPodScreen s);
  void pop();

  /// ホイールのフォーカスを再生中のパネルへ
  void showNowPlaying();

  /// 一覧の下の方に短いお知らせを出す
  void toast(String message);
}

late Nav nav;

/// 一覧の 1 画面
abstract class IPodScreen extends ChangeNotifier {
  String get title;
  final Key key = UniqueKey();

  /// ホイールがこの画面を操作しているか（再生中のパネルにフォーカスがあるときは false）
  bool active = true;
  void onScroll(int delta) {}
  void onSelect() {}

  /// 中央ボタンの長押し（見た／まだ など）
  void onLongSelect() {}
  Widget build(BuildContext context);
  void attach() {}
  void detach() {}

  /// 選んでいる行のポスター（何も再生していないとき、パネルに出す）
  String? get poster => null;
}

class MenuItem {
  final String label;
  final String? detail;
  final bool chevron;
  final VoidCallback? onSelect;
  final VoidCallback? onLong; // 中央ボタン長押し・行の長押し
  final bool starred; // 印（見終わった など）
  final String? filePath; // 動画の行：再生中なら印を出す
  final String? poster; // サムネイル（NAS のパス）
  final bool thumb; // サムネイルの枠を出す
  final double progress; // 途中まで見た割合（0 なら出さない）
  const MenuItem(this.label,
      {this.detail,
      this.chevron = false,
      this.onSelect,
      this.onLong,
      this.starred = false,
      this.filePath,
      this.poster,
      this.thumb = false,
      this.progress = 0});
}

/// 今再生しているファイル（行に印を付けるため。Shell が入れる）
String? Function() playingPath = () => null;

/// リスト形式の画面
class MenuScreen extends IPodScreen {
  @override
  final String title;
  final List<MenuItem> Function() builder;
  final List<Listenable> deps;
  final bool letterIndex; // 速く回したとき頭文字を出す

  List<MenuItem> items = [];
  int selected = 0;
  final ScrollController scroll = ScrollController();
  double _viewport = 0;
  double _rowH = 46;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  int _streak = 0;
  String? letter;
  Timer? _letterTimer;

  MenuScreen(this.title, this.builder, {this.deps = const [], this.letterIndex = false}) {
    items = builder();
  }

  @override
  String? get poster => items.isEmpty ? null : items[selected].poster;

  /// 中身を作り直す（探す文字を変えたときなど）
  void refresh() => _rebuild();

  void _rebuild() {
    items = builder();
    if (selected >= items.length) selected = items.isEmpty ? 0 : items.length - 1;
    notifyListeners();
  }

  @override
  void attach() {
    for (final d in deps) {
      d.addListener(_rebuild);
    }
    _rebuild();
  }

  @override
  void detach() {
    for (final d in deps) {
      d.removeListener(_rebuild);
    }
  }

  @override
  void onScroll(int delta) {
    if (items.isEmpty) return;
    final now = DateTime.now();
    _streak = now.difference(_lastTick).inMilliseconds < 70 ? _streak + 1 : 0;
    _lastTick = now;
    var step = 1;
    if (items.length > 60) step = _streak > 24 ? 8 : (_streak > 10 ? 3 : 1);
    final next = (selected + delta * step).clamp(0, items.length - 1);
    if (next == selected) return;
    selected = next;
    _ensureVisible();
    if (letterIndex && _streak > 10) {
      final l = items[selected].label;
      letter = l.isEmpty ? '' : l.characters.first.toUpperCase();
      _letterTimer?.cancel();
      _letterTimer = Timer(const Duration(milliseconds: 700), () {
        letter = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void _ensureVisible() {
    if (!scroll.hasClients || _viewport <= 0) return;
    final top = selected * _rowH;
    final bottom = top + _rowH;
    final off = scroll.offset;
    if (top < off) {
      scroll.jumpTo(top);
    } else if (bottom > off + _viewport) {
      scroll.jumpTo(bottom - _viewport);
    }
  }

  @override
  void onSelect() {
    if (items.isEmpty) return;
    items[selected].onSelect?.call();
  }

  @override
  void onLongSelect() {
    if (items.isEmpty) return;
    items[selected].onLong?.call();
  }

  @override
  void dispose() {
    _letterTimer?.cancel();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final playing = playingPath();
    final list = LayoutBuilder(builder: (context, c) {
      _viewport = c.maxHeight;
      _rowH = items.any((it) => it.thumb) ? 64 : 46;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
      if (items.isEmpty) {
        return Center(child: Text('ありません', style: TextStyle(color: p.faint)));
      }
      return ListView.builder(
        controller: scroll,
        physics: const ClampingScrollPhysics(),
        itemExtent: _rowH,
        itemCount: items.length,
        itemBuilder: (context, i) => _hudRow(p, items[i], i == selected, i, playing),
      );
    });
    return Stack(children: [
      Positioned.fill(child: list),
      if (letter != null)
        Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
            child: Text(letter!, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
          ),
        ),
    ]);
  }

  void _tap(int i, VoidCallback? f) {
    selected = i;
    notifyListeners();
    f?.call();
  }

  /// Theta スキンの行：縞模様、選んでいる行はアクセント色、再生中に印
  Widget _hudRow(Palette p, MenuItem it, bool sel, int i, String? playing) {
    final lit = sel && active; // フォーカスが無いときは、選んでいる行を枠だけにする
    final fg = lit ? p.onAccent : p.fg;
    final now = it.filePath != null && it.filePath == playing;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(i, it.onSelect),
      onLongPress: it.onLong == null ? null : () => _tap(i, it.onLong),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: lit ? p.accent : (i.isOdd ? p.zebra : null),
          border: sel && !active ? Border.all(color: p.accent.withValues(alpha: 0.6)) : null,
          borderRadius: p.rounded && sel ? BorderRadius.circular(6) : null,
        ),
        child: Row(children: [
          if (it.thumb)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: (_rowH - 10) * 2 / 3,
                height: _rowH - 10,
                child: NasImage(it.poster, key: ValueKey(it.poster), fallback: ''),
              ),
            ),
          if (now)
            Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.graphic_eq, size: 18, color: lit ? fg : p.accent)),
          if (it.starred)
            Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.check, size: 16, color: lit ? fg : p.accent)),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: now && !lit ? p.accent : fg, fontSize: 15)),
              if (it.progress > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 8),
                  child: LinearProgressIndicator(
                    value: it.progress,
                    minHeight: 2,
                    color: lit ? fg : p.accent,
                    backgroundColor: lit ? fg.withValues(alpha: 0.3) : p.line,
                  ),
                ),
            ]),
          ),
          if (it.detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(it.detail!,
                  style: TextStyle(color: lit ? fg : p.faint, fontSize: 12, fontFamily: p.mono, letterSpacing: 0.5)),
            ),
          if (it.chevron) Icon(Icons.chevron_right, color: lit ? fg : p.faint, size: 20),
        ]),
      ),
    );
  }
}

/// 文だけの画面（あらすじ・読み込みの様子など）
class InfoScreen extends IPodScreen {
  @override
  final String title;
  final Listenable? source;
  final Widget Function(BuildContext) content;
  final VoidCallback? select;
  final String? image;
  InfoScreen(this.title, this.content, {this.source, this.select, this.image});

  final ScrollController _scroll = ScrollController();

  @override
  String? get poster => image;

  @override
  void attach() => source?.addListener(notifyListeners);
  @override
  void detach() => source?.removeListener(notifyListeners);
  @override
  void onSelect() => select?.call();

  /// 回すと文を送る
  @override
  void onScroll(int delta) {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo((_scroll.offset + delta * 40).clamp(0, _scroll.position.maxScrollExtent));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: TextStyle(color: HudScope.of(context).fg, fontSize: 14, height: 1.6),
          child: content(context),
        ),
      );
}
