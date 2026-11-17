import 'package:material_ui/material_ui.dart';

import 'core/library.dart';
import 'core/posters.dart';
import 'core/progress.dart';
import 'core/series.dart';
import 'core/settings.dart';
import 'ui/home_screen.dart';
import 'ui/hud/hud_theme.dart';

/// アプリ全体で使うもの
class Services {
  final AppSettings settings;
  final Library library;
  final Progress progress;
  late final Posters posters = Posters(() => library.source);
  Services(this.settings, this.library, this.progress);

  static Future<Services> create() async {
    final s = AppSettings();
    await s.load();
    final lib = Library(s);
    final pr = Progress();
    await Future.wait([lib.loadCache(), pr.load()]);
    return Services(s, lib, pr);
  }

  /// シリーズのハブ（Home・KidsHome）からスキンを受け取る（承認なしで読める項目だけ）
  Future<void> followHub() async {
    if (!settings.followSeriesSkin) return;
    final info = await Series.info();
    final skin = info['ui.skin'] ?? '';
    if (skin.isNotEmpty && skin != settings.skin) {
      settings.skin = skin;
      await settings.save();
    }
  }
}

class AppScope extends InheritedWidget {
  final Services services;
  const AppScope({super.key, required this.services, required super.child});

  static Services of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}

class MovieApp extends StatefulWidget {
  final Services services;
  const MovieApp({super.key, required this.services});

  @override
  State<MovieApp> createState() => _MovieAppState();
}

class _MovieAppState extends State<MovieApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.services.followHub();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Home でスキンを変えて戻ってきたとき
    if (state == AppLifecycleState.resumed) widget.services.followHub();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return AppScope(
      services: s,
      child: ListenableBuilder(
        listenable: s.settings,
        builder: (context, _) {
          final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
          final p = paletteFor(s.settings.skin, brightness);
          return HudScope(
            palette: p,
            child: MaterialApp(
              title: 'Theta Movie Hatch',
              debugShowCheckedModeBanner: false,
              theme: hudMaterialTheme(p),
              home: const HomeScreen(),
            ),
          );
        },
      ),
    );
  }
}
