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

  /// 動画の共有フォルダ（THETA_LIBRARY_SPEC.md §1。既定 /video）。複数はカンマか改行で区切る
  String videoRoot = '/video';

  /// 読むフォルダの目印（接頭辞）。共有フォルダの直下で、名前がこれで始まるフォルダだけを読む。
  /// Theta Book Hatch と同じ（既定 ⑧）。空なら共有フォルダの全部
  String folderPrefix = '⑧';

  List<String> get videoRoots => videoRootsOf(videoRoot);

  List<String> videoRootsOf(String text) => [
        for (final r in text.split(RegExp(r'[,、\n]')))
          if (r.trim().isNotEmpty) normRoot(r),
      ];

  static String normRoot(String r) {
    var s = r.trim();
    if (s.isEmpty) return '/video';
    if (!s.startsWith('/')) s = '/$s';
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// シリーズのスキン（ui.skin）。followSeriesSkin のとき Home の値に追従
  String skin = 'system';
  bool followSeriesSkin = true;

  /// 続きから：残りがこれ未満なら「見終わった」
  int doneMarginSec = 120;

  /// ホイール（Theta Music Hatch と同じ）：カリカリ音・振動・案内
  bool clicker = true;
  bool haptics = true;
  bool wheelGuide = true;

  /// 画面の並べ方（Theta Music Hatch 1.7.0 と同じ）：auto（幅 600 以上で幅 ≥ 高さ×0.75 なら横並び）・wide・tall
  String thetaLayout = 'auto';

  /// 左のタブに文字も出す（幅 40 → 116）
  bool tabLabels = false;

  /// 音の出し方（Android の mpv の ao）：audiotrack（既定）・opensles
  String audioOutput = 'audiotrack';

  bool get configured => (source == SourceKind.dsm ? dsUrl : davUrl).trim().isNotEmpty && user.isNotEmpty;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    source = SourceKind.values.firstWhere((s) => s.name == _p.getString('source'), orElse: () => SourceKind.dsm);
    dsUrl = _p.getString('dsUrl') ?? '';
    davUrl = _p.getString('davUrl') ?? '';
    user = _p.getString('user') ?? '';
    videoRoot = _p.getString('videoRoot') ?? '/video';
    folderPrefix = _p.getString('folderPrefix') ?? '⑧';
    skin = _p.getString('skin') ?? 'system';
    followSeriesSkin = _p.getBool('followSeriesSkin') ?? true;
    doneMarginSec = _p.getInt('doneMarginSec') ?? 120;
    clicker = _p.getBool('clicker') ?? true;
    haptics = _p.getBool('haptics') ?? true;
    wheelGuide = _p.getBool('wheelGuide') ?? true;
    thetaLayout = _p.getString('thetaLayout') ?? 'auto';
    tabLabels = _p.getBool('tabLabels') ?? false;
    audioOutput = _p.getString('audioOutput') ?? 'audiotrack';
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
    await _p.setString('folderPrefix', folderPrefix);
    await _p.setString('skin', skin);
    await _p.setBool('followSeriesSkin', followSeriesSkin);
    await _p.setInt('doneMarginSec', doneMarginSec);
    await _p.setBool('clicker', clicker);
    await _p.setBool('haptics', haptics);
    await _p.setBool('wheelGuide', wheelGuide);
    await _p.setString('thetaLayout', thetaLayout);
    await _p.setBool('tabLabels', tabLabels);
    await _p.setString('audioOutput', audioOutput);
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
