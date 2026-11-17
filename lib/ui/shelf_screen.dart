import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../core/naming.dart';
import 'hud/hud_theme.dart';
import 'widgets.dart';

enum _Sort { name, year, added }

/// 棚（映画・アニメ…）の全作品
class ShelfScreen extends StatefulWidget {
  final String shelf;
  const ShelfScreen({super.key, required this.shelf});

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  _Sort _sort = _Sort.name;
  bool _unwatched = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = HudScope.of(context);
    var list = s.library.onShelf(widget.shelf);
    if (_unwatched) {
      list = list.where((t) => !t.allFiles.every((f) => s.progress.isDone(f.path))).toList();
    }
    list.sort(switch (_sort) {
      _Sort.name => (a, b) => naturalCompare(a.displayName, b.displayName),
      _Sort.year => (a, b) => (b.displayYear ?? 0).compareTo(a.displayYear ?? 0),
      _Sort.added => (a, b) => b.added.compareTo(a.added),
    });
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.fg,
        title: Text('${widget.shelf.isEmpty ? 'そのほか' : widget.shelf}（${list.length}）'),
        actions: [
          IconButton(
            tooltip: '見ていない作品だけ',
            icon: Icon(_unwatched ? Icons.visibility_off : Icons.visibility, color: _unwatched ? p.accent : p.fg),
            onPressed: () => setState(() => _unwatched = !_unwatched),
          ),
          PopupMenuButton<_Sort>(
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.name, child: Text('名前順')),
              PopupMenuItem(value: _Sort.year, child: Text('新しい年から')),
              PopupMenuItem(value: _Sort.added, child: Text('追加した順')),
            ],
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140, childAspectRatio: 0.52, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: list.length,
        itemBuilder: (_, i) => PosterTile(title: list[i]),
      ),
    );
  }
}
