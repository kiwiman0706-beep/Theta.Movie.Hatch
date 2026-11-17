import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../app.dart';
import 'hud/hud_theme.dart';

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
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NasImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  void _load() {
    final path = widget.path;
    if (path == _loaded) return;
    _loaded = path;
    if (path == null) {
      _bytes = null;
      return;
    }
    _bytes = services.posters.cached(path);
    if (_bytes == null) {
      services.posters.get(path).then((b) {
        if (mounted && widget.path == path) setState(() => _bytes = b);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HudScope.of(context);
    final b = widget.path == null ? null : _bytes;
    if (b != null) {
      return Image.memory(b,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback(p));
    }
    return _fallback(p);
  }

  Widget _fallback(Palette p) => Container(
        color: p.raised,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: widget.fallback.isEmpty
            ? Icon(Icons.movie_outlined, color: p.faint, size: 18)
            : Text(
                widget.fallback,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 13, fontFamily: p.display),
              ),
      );
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

/// 確認コード（Secure SignIn）の入力
Future<String?> askOtp(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('2 段階認証'),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '確認コード（6 桁）'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('やめる')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('ログイン')),
      ],
    ),
  );
}

/// 文字の入力（探す）
Future<String?> askText(BuildContext context, String title, {String hint = ''}) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('やめる')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('探す')),
      ],
    ),
  );
}
