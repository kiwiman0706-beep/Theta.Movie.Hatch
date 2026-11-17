import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' hide Title;

import '../app.dart';
import '../core/models.dart';
import '../core/progress.dart';
import 'hud/hud_theme.dart';
import 'title_screen.dart';

/// NAS の画像（ポスター・背景）。無ければ頭文字
class NasImage extends StatefulWidget {
  final String? path;
  final String fallback;
  final BoxFit fit;
  const NasImage(this.path, {super.key, this.fallback = '', this.fit = BoxFit.cover});

  @override
  State<NasImage> createState() => _NasImageState();
}

class _NasImageState extends State<NasImage> {
  Uint8List? _bytes;
  String? _loaded;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(NasImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  void _load() {
    final path = widget.path;
    if (path == null || path == _loaded) return;
    _loaded = path;
    final posters = AppScope.of(context).posters;
    _bytes = posters.cached(path);
    if (_bytes == null) {
      posters.get(path).then((b) {
        if (mounted && widget.path == path) setState(() => _bytes = b);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final b = widget.path == null ? null : _bytes;
    if (b != null) {
      return Image.memory(b, fit: widget.fit, gaplessPlayback: true, errorBuilder: (_, _, _) => _fallback(p));
    }
    return _fallback(p);
  }

  Widget _fallback(Palette p) => Container(
        color: p.raised,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          widget.fallback,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: p.muted, fontSize: 13, fontFamily: p.display),
        ),
      );
}

/// ポスター 1 枚（2:3）と題名。mark があれば下に進み具合の線
class PosterTile extends StatelessWidget {
  final Title title;
  final String? subtitle;
  final Mark? mark;
  final VoidCallback? onTap;
  final double width;
  const PosterTile({super.key, required this.title, this.subtitle, this.mark, this.onTap, this.width = 120});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final y = title.displayYear;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap ??
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleScreen(titleId: title.id))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: p.line, width: p.lineWidth),
                borderRadius: BorderRadius.circular(p.rounded ? p.radius * 0.6 : 0),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                NasImage(title.poster, fallback: title.displayName),
                if (mark != null && mark!.ratio > 0)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      value: mark!.ratio,
                      minHeight: 4,
                      color: p.accent,
                      backgroundColor: Colors.black45,
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(title.displayName,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.fg, fontSize: 12, height: 1.25)),
          Text(subtitle ?? (y == null ? '' : '$y'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.faint, fontSize: 11, fontFamily: p.mono)),
        ]),
      ),
    );
  }
}

/// 横 1 列の棚
class PosterRow extends StatelessWidget {
  final String code;
  final String label;
  final List<Widget> children;
  final VoidCallback? onMore;
  const PosterRow({super.key, required this.code, required this.label, required this.children, this.onMore});

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Row(children: [
          Text('[ $code ]', style: TextStyle(color: p.accent, fontSize: 11, letterSpacing: 2, fontFamily: p.mono)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: p.fg, fontSize: 15, fontWeight: FontWeight.w600))),
          if (onMore != null)
            TextButton(onPressed: onMore, child: Text('すべて ›', style: TextStyle(color: p.muted, fontSize: 12))),
        ]),
      ),
      SizedBox(
        height: 236,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => children[i],
        ),
      ),
    ]);
  }
}

String fmtDuration(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

String fmtSize(int bytes) {
  if (bytes <= 0) return '';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${u[i]}';
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
