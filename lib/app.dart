import 'package:material_ui/material_ui.dart';

import 'core/library.dart';
import 'core/playback.dart';
import 'core/posters.dart';
import 'core/progress.dart';
import 'core/series.dart';
import 'core/settings.dart';
import 'ui/hud/hud_theme.dart';
import 'ui/shell.dart';

/// アプリ全体で使うもの（Theta Music Hatch と同じく、どこからでも services で読む）
late Services services;

class Services {
  final AppSettings settings;
  final Library library;
  final Progress progress;
  late final Posters posters = Posters(() => library.source);
  late final Playback playback = Playback(settings, library, progress);
  Services(this.settings, this.library, this.progress);

  static Future<Services> create() async {
    final s = AppSettings();
    await s.load();
    final lib = Library(s);
    final pr = Progress();
    await Future.wait([lib.loadCache(), pr.load()]);
    return services = Services(s, lib, pr);
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

/// 古い呼び方（settings_screen など）
class AppScope {
  static Services of(BuildContext context) => services;
}

class MovieApp extends StatefulWidget {
  const MovieApp({super.key});

  @override
  State<MovieApp> createState() => _MovieAppState();
}

class _MovieAppState extends State<MovieApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    services.followHub();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Home でスキンを変えて戻ってきたとき
    if (state == AppLifecycleState.resumed) services.followHub();
    // 裏に回ったら再生位置を残す
    if (state == AppLifecycleState.paused) services.playback.save();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        final p = paletteFor(services.settings.skin, brightness);
        return HudScope(
          palette: p,
          child: MaterialApp(
            title: 'Theta Movie Hatch',
            debugShowCheckedModeBanner: false,
            theme: hudMaterialTheme(p),
            builder: (context, child) => HudScope(palette: p, child: child!),
            home: const Shell(),
          ),
        );
      },
    );
  }
}
