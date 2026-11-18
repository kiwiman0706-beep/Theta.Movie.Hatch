import 'package:flutter/services.dart';

/// Android のオーディオフォーカスとメディアセッション（MediaBridge.kt）。
/// 再生中であることを知らせるので、Android Auto・Bluetooth に音が流れ、機器のボタンで操作できる
class MediaSessionBridge {
  static const _ch = MethodChannel('theta_movie/media');

  /// 車・Bluetooth・イヤホンのボタン。b：play・pause・next・previous・forward・rewind・seek（pos はミリ秒）
  static void listen(void Function(String b, int? pos) onButton) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'button') {
        final a = Map<String, Object?>.from(call.arguments as Map);
        onButton('${a['b']}', (a['pos'] as num?)?.toInt());
      }
    });
  }

  static Future<void> meta(String title, String subtitle, Duration duration) => _call('meta', {
        'title': title,
        'subtitle': subtitle,
        'duration': duration.inMilliseconds,
      });

  static Future<void> state({required bool playing, required Duration position}) =>
      _call('state', {'playing': playing, 'pos': position.inMilliseconds});

  static Future<void> stop() => _call('stop', const {});

  static Future<void> _call(String m, Map<String, Object?> args) async {
    try {
      await _ch.invokeMethod<void>(m, args);
    } catch (_) {
      // Android 以外・テストでは何もしない
    }
  }
}
