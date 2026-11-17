import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final services = await Services.create();
  runApp(MovieApp(services: services));
}
