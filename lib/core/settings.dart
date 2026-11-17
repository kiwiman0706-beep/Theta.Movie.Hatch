import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 動画の読み先。dsm: DSM の File Station（2 段階認証に対応・既定） / webdav: WebDAV Server
enum SourceKind { dsm, webdav }

class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;

  /// パスワード・デバイストークンは端末内で暗号化して持つ（Android Keystore）。テストでは null
  static FlutterSecureStorage? secure = const FlutterSecureStorage();
  static const _secretKeys = ['password', 'did'];

  SourceKind source = SourceKind.dsm;
  String dsUrl = ''; // 例: http://nas.tailXXXX.ts.net:5000（ハブの nas.url）
  String davUrl = ''; // 例: http://nas.tailXXXX.ts.net:5005
  String user = '';
  String password = '';
  String did = ''; // 2 段階認証のデバイストークン（次から確認コードを省く）

  /// 動画の共有フォルダ（THETA_LIBRARY_SPEC.md §1。既定 /video）
  String videoRoot = '/video';

  /// シリーズのスキン（ui.skin）。followSeriesSkin のとき Home の値に追従
  String skin = 'system';
  bool followSeriesSkin = true;

  /// 続きから：残りがこれ未満なら「見終わった」
  int doneMarginSec = 120;

  bool get configured => (source == SourceKind.dsm ? dsUrl : davUrl).trim().isNotEmpty && user.isNotEmpty;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    source = SourceKind.values.firstWhere((s) => s.name == _p.getString('source'), orElse: () => SourceKind.dsm);
    dsUrl = _p.getString('dsUrl') ?? '';
    davUrl = _p.getString('davUrl') ?? '';
    user = _p.getString('user') ?? '';
    videoRoot = _p.getString('videoRoot') ?? '/video';
    skin = _p.getString('skin') ?? 'system';
    followSeriesSkin = _p.getBool('followSeriesSkin') ?? true;
    doneMarginSec = _p.getInt('doneMarginSec') ?? 120;
    final s = secure;
    if (s != null) {
      try {
        password = await s.read(key: 'password') ?? '';
        did = await s.read(key: 'did') ?? '';
      } catch (_) {}
    } else {
      password = _p.getString('password') ?? '';
      did = _p.getString('did') ?? '';
    }
  }

  Future<void> save() async {
    await _p.setString('source', source.name);
    await _p.setString('dsUrl', dsUrl);
    await _p.setString('davUrl', davUrl);
    await _p.setString('user', user);
    await _p.setString('videoRoot', videoRoot);
    await _p.setString('skin', skin);
    await _p.setBool('followSeriesSkin', followSeriesSkin);
    await _p.setInt('doneMarginSec', doneMarginSec);
    final values = {'password': password, 'did': did};
    final s = secure;
    for (final k in _secretKeys) {
      if (s != null) {
        try {
          await s.write(key: k, value: values[k]);
        } catch (_) {}
      } else {
        await _p.setString(k, values[k]!);
      }
    }
    notifyListeners();
  }
}
