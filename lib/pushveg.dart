import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as HunterVegasMath;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as HunterVegasTimezoneData;
import 'package:timezone/timezone.dart' as HunterVegasTimezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'main.dart' show MafiaHarbor, CaptainHarbor, BillHarbor;

// ============================================================================
// HunterVegas инфраструктура
// ============================================================================

class HunterVegasLogger {
  const HunterVegasLogger();

  void HunterVegasLogInfo(Object hunterVegasMessage) =>
      debugPrint('[DressRetroLogger] $hunterVegasMessage');

  void HunterVegasLogWarn(Object hunterVegasMessage) =>
      debugPrint('[DressRetroLogger/WARN] $hunterVegasMessage');

  void HunterVegasLogError(Object hunterVegasMessage) =>
      debugPrint('[DressRetroLogger/ERR] $hunterVegasMessage');
}

class HunterVegasVault {
  static final HunterVegasVault SharedInstance =
  HunterVegasVault._InternalConstructor();

  HunterVegasVault._InternalConstructor();

  factory HunterVegasVault() => SharedInstance;

  final HunterVegasLogger HunterVegasLoggerInstance =
  const HunterVegasLogger();
}

// ============================================================================
// Константы — строки в кавычках не меняем
// ============================================================================

const String HunterVegasLoadedOnceKey = 'wheel_loaded_once';
const String HunterVegasStatEndpoint =
    'https://n1test-fish-mrb49.ondigitalocean.app/stat';
const String HunterVegasCachedFcmKey = 'wheel_cached_fcm';

// ============================================================================
// Утилиты: HunterVegasKit
// ============================================================================

class HunterVegasKit {
  static bool HunterVegasLooksLikeBareMail(Uri hunterVegasUri) {
    final String hunterVegasScheme = hunterVegasUri.scheme;
    if (hunterVegasScheme.isNotEmpty) return false;

    final String hunterVegasRaw = hunterVegasUri.toString();
    return hunterVegasRaw.contains('@') && !hunterVegasRaw.contains(' ');
  }

  static Uri HunterVegasToMailto(Uri hunterVegasUri) {
    final String hunterVegasFull = hunterVegasUri.toString();
    final List<String> hunterVegasBits = hunterVegasFull.split('?');
    final String hunterVegasWho = hunterVegasBits.first;

    final Map<String, String> hunterVegasQuery = hunterVegasBits.length > 1
        ? Uri.splitQueryString(hunterVegasBits[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: hunterVegasWho,
      queryParameters:
      hunterVegasQuery.isEmpty ? null : hunterVegasQuery,
    );
  }

  static Uri HunterVegasGmailize(Uri hunterVegasMailUri) {
    final Map<String, String> hunterVegasQp =
        hunterVegasMailUri.queryParameters;

    final Map<String, String> hunterVegasParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (hunterVegasMailUri.path.isNotEmpty)
        'to': hunterVegasMailUri.path,
      if ((hunterVegasQp['subject'] ?? '').isNotEmpty)
        'su': hunterVegasQp['subject']!,
      if ((hunterVegasQp['body'] ?? '').isNotEmpty)
        'body': hunterVegasQp['body']!,
      if ((hunterVegasQp['cc'] ?? '').isNotEmpty)
        'cc': hunterVegasQp['cc']!,
      if ((hunterVegasQp['bcc'] ?? '').isNotEmpty)
        'bcc': hunterVegasQp['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', hunterVegasParams);
  }

  static String HunterVegasDigitsOnly(String hunterVegasSource) =>
      hunterVegasSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия ссылок: HunterVegasLinker
// ============================================================================

class HunterVegasLinker {
  static Future<bool> HunterVegasOpen(Uri hunterVegasUri) async {
    try {
      if (await launchUrl(
        hunterVegasUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        hunterVegasUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (hunterVegasError) {
      debugPrint(
          'DressRetroLinker error: $hunterVegasError; url=$hunterVegasUri');

      try {
        return await launchUrl(
          hunterVegasUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler
// ============================================================================

@pragma('vm:entry-point')
Future<void> HunterVegasFcmBackgroundHandler(
    RemoteMessage hunterVegasMessage,
    ) async {
  debugPrint("Spin ID: ${hunterVegasMessage.messageId}");
  debugPrint("Spin Data: ${hunterVegasMessage.data}");
}

// ============================================================================
// HunterVegasDeviceProfile
// ============================================================================

class HunterVegasDeviceProfile {
  String? HunterVegasDeviceId;
  String? HunterVegasSessionId = 'wheel-one-off';
  String? HunterVegasPlatformKind;
  String? HunterVegasOsBuild;
  String? HunterVegasAppVersion;
  String? HunterVegasLocaleCode;
  String? HunterVegasTimezoneName;
  bool HunterVegasPushEnabled = true;

  Future<void> HunterVegasInitialize() async {
    final DeviceInfoPlugin hunterVegasInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo hunterVegasAndroidInfo =
      await hunterVegasInfoPlugin.androidInfo;

      HunterVegasDeviceId = hunterVegasAndroidInfo.id;
      HunterVegasPlatformKind = 'android';
      HunterVegasOsBuild = hunterVegasAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo hunterVegasIosInfo =
      await hunterVegasInfoPlugin.iosInfo;

      HunterVegasDeviceId = hunterVegasIosInfo.identifierForVendor;
      HunterVegasPlatformKind = 'ios';
      HunterVegasOsBuild = hunterVegasIosInfo.systemVersion;
    }

    final PackageInfo hunterVegasPackageInfo =
    await PackageInfo.fromPlatform();

    HunterVegasAppVersion = hunterVegasPackageInfo.version;
    HunterVegasLocaleCode = Platform.localeName.split('_').first;
    HunterVegasTimezoneName = HunterVegasTimezone.local.name;
    HunterVegasSessionId =
    'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> HunterVegasAsMap({String? hunterVegasFcmToken}) =>
      <String, dynamic>{
        'fcm_token': hunterVegasFcmToken ?? 'missing_token',
        'device_id': HunterVegasDeviceId ?? 'missing_id',
        'app_name': 'vegasstrike',
        'instance_id': HunterVegasSessionId ?? 'missing_session',
        'platform': HunterVegasPlatformKind ?? 'missing_system',
        'os_version': HunterVegasOsBuild ?? 'missing_build',
        'app_version': HunterVegasAppVersion ?? 'missing_app',
        'language': HunterVegasLocaleCode ?? 'en',
        'timezone': HunterVegasTimezoneName ?? 'UTC',
        'push_enabled': HunterVegasPushEnabled,
        "fthcashier": "true"
      };
}

// ============================================================================
// AppsFlyer шпион: HunterVegasSpy
// ============================================================================

class HunterVegasSpy {
  AppsFlyerOptions? HunterVegasOptions;
  AppsflyerSdk? HunterVegasSdk;

  String HunterVegasAppsFlyerUid = '';
  String HunterVegasAppsFlyerData = '';

  void HunterVegasStart({VoidCallback? hunterVegasOnUpdate}) {
    final AppsFlyerOptions hunterVegasOpts = AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    HunterVegasOptions = hunterVegasOpts;
    HunterVegasSdk = AppsflyerSdk(hunterVegasOpts);

    HunterVegasSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    HunterVegasSdk?.startSDK(
      onSuccess: () =>
          HunterVegasVault().HunterVegasLoggerInstance.HunterVegasLogInfo(
            'WheelSpy started',
          ),
      onError: (hunterVegasCode, hunterVegasMsg) => HunterVegasVault()
          .HunterVegasLoggerInstance
          .HunterVegasLogError('WheelSpy error $hunterVegasCode: $hunterVegasMsg'),
    );

    HunterVegasSdk?.onInstallConversionData((hunterVegasValue) {
      HunterVegasAppsFlyerData = hunterVegasValue.toString();
      hunterVegasOnUpdate?.call();
    });

    HunterVegasSdk?.getAppsFlyerUID().then((hunterVegasValue) {
      HunterVegasAppsFlyerUid = hunterVegasValue.toString();
      hunterVegasOnUpdate?.call();
    });
  }
}

// ============================================================================
// Мост для FCM токена: HunterVegasFcmBridge
// ============================================================================

class HunterVegasFcmBridge {
  final HunterVegasLogger HunterVegasLog = const HunterVegasLogger();

  String? HunterVegasToken;

  final List<void Function(String)> HunterVegasWaiters =
  <void Function(String)>[];

  String? get HunterVegasCurrentToken => HunterVegasToken;

  HunterVegasFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall hunterVegasCall) async {
      if (hunterVegasCall.method == 'setToken') {
        final String hunterVegasTokenString =
        hunterVegasCall.arguments as String;

        if (hunterVegasTokenString.isNotEmpty) {
          HunterVegasSetToken(hunterVegasTokenString);
        }
      }
    });

    HunterVegasRestoreToken();
  }

  Future<void> HunterVegasRestoreToken() async {
    try {
      final SharedPreferences hunterVegasPrefs =
      await SharedPreferences.getInstance();

      final String? hunterVegasCached =
      hunterVegasPrefs.getString(HunterVegasCachedFcmKey);

      if (hunterVegasCached != null && hunterVegasCached.isNotEmpty) {
        HunterVegasSetToken(hunterVegasCached, hunterVegasNotify: false);
      }
    } catch (_) {}
  }

  Future<void> HunterVegasPersistToken(String hunterVegasNewToken) async {
    try {
      final SharedPreferences hunterVegasPrefs =
      await SharedPreferences.getInstance();

      await hunterVegasPrefs.setString(
        HunterVegasCachedFcmKey,
        hunterVegasNewToken,
      );
    } catch (_) {}
  }

  void HunterVegasSetToken(
      String hunterVegasNewToken, {
        bool hunterVegasNotify = true,
      }) {
    HunterVegasToken = hunterVegasNewToken;
    HunterVegasPersistToken(hunterVegasNewToken);

    if (hunterVegasNotify) {
      for (final void Function(String) hunterVegasCallback
      in List<void Function(String)>.from(HunterVegasWaiters)) {
        try {
          hunterVegasCallback(hunterVegasNewToken);
        } catch (hunterVegasErr) {
          HunterVegasLog.HunterVegasLogWarn('fcm waiter error: $hunterVegasErr');
        }
      }

      HunterVegasWaiters.clear();
    }
  }

  Future<void> HunterVegasWaitForToken(
      Function(String hunterVegasTokenValue) hunterVegasOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((HunterVegasToken ?? '').isNotEmpty) {
        hunterVegasOnToken(HunterVegasToken!);
        return;
      }

      HunterVegasWaiters.add(hunterVegasOnToken);
    } catch (hunterVegasErr) {
      HunterVegasLog.HunterVegasLogError(
        'wheelWaitToken error: $hunterVegasErr',
      );
    }
  }
}

// ============================================================================
// HunterVegasLoader
// ============================================================================

class HunterVegasLoader extends StatefulWidget {
  const HunterVegasLoader({Key? key}) : super(key: key);

  @override
  State<HunterVegasLoader> createState() => _HunterVegasLoaderState();
}

class _HunterVegasLoaderState extends State<HunterVegasLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController HunterVegasController;

  static const Color HunterVegasBackgroundColor = Color(0xFF05071B);

  @override
  void initState() {
    super.initState();

    HunterVegasController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    HunterVegasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: HunterVegasBackgroundColor,
      child: AnimatedBuilder(
        animation: HunterVegasController,
        builder: (BuildContext context, Widget? child) {
          final double hunterVegasPhase =
              HunterVegasController.value * 2 * HunterVegasMath.pi;

          return CustomPaint(
            painter: HunterVegasLoaderPainter(
              hunterVegasPhase: hunterVegasPhase,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class HunterVegasLoaderPainter extends CustomPainter {
  final double hunterVegasPhase;

  HunterVegasLoaderPainter({
    required this.hunterVegasPhase,
  });

  @override
  void paint(Canvas hunterVegasCanvas, Size hunterVegasSize) {
    final double hunterVegasWidth = hunterVegasSize.width;
    final double hunterVegasHeight = hunterVegasSize.height;

    final Paint hunterVegasBackgroundPaint = Paint()
      ..color = const Color(0xFF05071B)
      ..style = PaintingStyle.fill;

    hunterVegasCanvas.drawRect(
      Offset.zero & hunterVegasSize,
      hunterVegasBackgroundPaint,
    );

    final double hunterVegasPulse =
        (HunterVegasMath.sin(hunterVegasPhase) + 1) / 2;

    final Paint hunterVegasCirclePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.red.withOpacity(0.14 + 0.16 * hunterVegasPulse),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(hunterVegasWidth * 0.5, hunterVegasHeight * 0.45),
          radius:
          hunterVegasHeight * (0.4 + 0.15 * hunterVegasPulse),
        ),
      );

    hunterVegasCanvas.drawCircle(
      Offset(hunterVegasWidth * 0.5, hunterVegasHeight * 0.45),
      hunterVegasHeight * (0.4 + 0.15 * hunterVegasPulse),
      hunterVegasCirclePaint,
    );

    final Paint hunterVegasOuterPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.redAccent.withOpacity(
            0.10 + 0.10 * (1 - hunterVegasPulse),
          ),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(hunterVegasWidth * 0.5, hunterVegasHeight * 0.45),
          radius: hunterVegasHeight *
              (0.55 + 0.10 * (1 - hunterVegasPulse)),
        ),
      );

    hunterVegasCanvas.drawCircle(
      Offset(hunterVegasWidth * 0.5, hunterVegasHeight * 0.45),
      hunterVegasHeight * (0.55 + 0.10 * (1 - hunterVegasPulse)),
      hunterVegasOuterPaint,
    );

    final double hunterVegasBaseSize = hunterVegasWidth * 0.35;

    final double hunterVegasFontSize =
        hunterVegasBaseSize + hunterVegasPulse * (hunterVegasBaseSize * 0.15);

    final String hunterVegasLetter = 'N';
    final String hunterVegasWord = 'CUP';

    final TextPainter hunterVegasLetterPainter = TextPainter(
      text: TextSpan(
        text: hunterVegasLetter,
        style: TextStyle(
          fontSize: hunterVegasFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.red.shade600,
          letterSpacing: 4,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.8),
              blurRadius: 22 + 18 * hunterVegasPulse,
              offset: const Offset(0, 0),
            ),
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: hunterVegasWidth);

    final double hunterVegasLetterX =
        (hunterVegasWidth - hunterVegasLetterPainter.width) / 2;

    final double hunterVegasLetterY =
        (hunterVegasHeight - hunterVegasLetterPainter.height) / 2;

    final Offset hunterVegasLetterOffset = Offset(
      hunterVegasLetterX,
      hunterVegasLetterY,
    );

    final Rect hunterVegasLetterRect = Rect.fromCenter(
      center: Offset(hunterVegasWidth / 2, hunterVegasHeight / 2),
      width: hunterVegasLetterPainter.width * 1.4,
      height: hunterVegasLetterPainter.height * 1.6,
    );

    final Paint hunterVegasGlowPaint = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        28 + 24 * hunterVegasPulse,
      )
      ..color = Colors.red.withOpacity(0.7 + 0.2 * hunterVegasPulse);

    hunterVegasCanvas.saveLayer(hunterVegasLetterRect, hunterVegasGlowPaint);
    hunterVegasLetterPainter.paint(
        hunterVegasCanvas, hunterVegasLetterOffset);
    hunterVegasCanvas.restore();

    hunterVegasLetterPainter.paint(
        hunterVegasCanvas, hunterVegasLetterOffset);

    final double hunterVegasCupFontSize = hunterVegasWidth * 0.11;

    final TextPainter hunterVegasCupPainter = TextPainter(
      text: TextSpan(
        text: hunterVegasWord,
        style: TextStyle(
          fontSize: hunterVegasCupFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.red.shade100.withOpacity(0.95),
          letterSpacing: 5,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.7),
              blurRadius: 12 + 10 * hunterVegasPulse,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: hunterVegasWidth);

    final double hunterVegasCupX =
        (hunterVegasWidth - hunterVegasCupPainter.width) / 2;

    final double hunterVegasCupY = hunterVegasLetterY +
        hunterVegasLetterPainter.height +
        hunterVegasHeight * 0.03;

    final Offset hunterVegasCupOffset = Offset(
      hunterVegasCupX,
      hunterVegasCupY,
    );

    hunterVegasCupPainter.paint(hunterVegasCanvas, hunterVegasCupOffset);
  }

  @override
  bool shouldRepaint(
      covariant HunterVegasLoaderPainter hunterVegasOldDelegate) =>
      hunterVegasOldDelegate.hunterVegasPhase != hunterVegasPhase;
}

// ============================================================================
// Статистика
// ============================================================================

Future<String> HunterVegasFinalUrl(
    String hunterVegasStartUrl, {
      int hunterVegasMaxHops = 10,
    }) async {
  final HttpClient hunterVegasClient = HttpClient();

  try {
    Uri hunterVegasCurrentUri = Uri.parse(hunterVegasStartUrl);

    for (int hunterVegasI = 0;
    hunterVegasI < hunterVegasMaxHops;
    hunterVegasI++) {
      final HttpClientRequest hunterVegasRequest =
      await hunterVegasClient.getUrl(hunterVegasCurrentUri);

      hunterVegasRequest.followRedirects = false;

      final HttpClientResponse hunterVegasResponse =
      await hunterVegasRequest.close();

      if (hunterVegasResponse.isRedirect) {
        final String? hunterVegasLoc =
        hunterVegasResponse.headers.value(HttpHeaders.locationHeader);

        if (hunterVegasLoc == null || hunterVegasLoc.isEmpty) break;

        final Uri hunterVegasNextUri = Uri.parse(hunterVegasLoc);

        hunterVegasCurrentUri = hunterVegasNextUri.hasScheme
            ? hunterVegasNextUri
            : hunterVegasCurrentUri.resolveUri(hunterVegasNextUri);

        continue;
      }

      return hunterVegasCurrentUri.toString();
    }

    return hunterVegasCurrentUri.toString();
  } catch (hunterVegasError) {
    debugPrint('wheelFinalUrl error: $hunterVegasError');
    return hunterVegasStartUrl;
  } finally {
    hunterVegasClient.close(force: true);
  }
}

Future<void> HunterVegasPostStat({
  required String hunterVegasEvent,
  required int hunterVegasTimeStart,
  required String hunterVegasUrl,
  required int hunterVegasTimeFinish,
  required String hunterVegasAppSid,
  int? hunterVegasFirstPageTs,
}) async {
  try {
    final String hunterVegasResolvedUrl =
    await HunterVegasFinalUrl(hunterVegasUrl);

    final Map<String, dynamic> hunterVegasPayload = <String, dynamic>{
      'event': hunterVegasEvent,
      'timestart': hunterVegasTimeStart,
      'timefinsh': hunterVegasTimeFinish,
      'url': hunterVegasResolvedUrl,
      'appleID': '6755681349',
      'open_count': '$hunterVegasAppSid/$hunterVegasTimeStart',
    };

    debugPrint('wheelStat $hunterVegasPayload');

    final http.Response hunterVegasResp = await http.post(
      Uri.parse('$HunterVegasStatEndpoint/$hunterVegasAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(hunterVegasPayload),
    );

    debugPrint(
      'wheelStat resp=${hunterVegasResp.statusCode} body=${hunterVegasResp.body}',
    );
  } catch (hunterVegasError) {
    debugPrint('wheelPostStat error: $hunterVegasError');
  }
}

// ============================================================================
// WebView-экран: HunterVegasTableView
// ============================================================================

class HunterVegasTableView extends StatefulWidget
    with WidgetsBindingObserver {
  String HunterVegasStartingUrl;

  HunterVegasTableView(this.HunterVegasStartingUrl, {super.key});

  @override
  State<HunterVegasTableView> createState() =>
      _HunterVegasTableViewState(HunterVegasStartingUrl);
}

class _HunterVegasTableViewState extends State<HunterVegasTableView>
    with WidgetsBindingObserver {
  _HunterVegasTableViewState(this.HunterVegasCurrentUrl);

  final HunterVegasVault HunterVegasVaultInstance = HunterVegasVault();

  late InAppWebViewController HunterVegasWebViewController;

  String? HunterVegasPushToken;

  final HunterVegasDeviceProfile HunterVegasDeviceProfileInstance =
  HunterVegasDeviceProfile();

  final HunterVegasSpy HunterVegasSpyInstance = HunterVegasSpy();

  bool HunterVegasOverlayBusy = false;

  String HunterVegasCurrentUrl;

  DateTime? HunterVegasLastPausedAt;

  bool HunterVegasLoadedOnceSent = false;

  // Email extraction
  String? HunterVegasCapturedEmail;
  Timer? HunterVegasEmailPollTimer;

  static const String HunterVegasInterceptScript = r"""
(function() {
  if (window.__retroKingHookInstalled) return;
  window.__retroKingHookInstalled = true;

  function tryExtract(url, bodyText) {
    try {
      if (url && url.indexOf('/player') !== -1) {
        var data = JSON.parse(bodyText);
        if (data && data.email) {
          window.__capturedEmail = data.email;
          window.flutter_inappwebview.callHandler('onPlayerData', data.email);
        }
      }
    } catch (e) {}
  }

  // Патчим fetch
  var origFetch = window.fetch;
  window.fetch = function() {
    var url = arguments[0];
    return origFetch.apply(this, arguments).then(function(response) {
      try {
        response.clone().text().then(function(text) {
          tryExtract(typeof url === 'string' ? url : url.url, text);
        });
      } catch (e) {}
      return response;
    });
  };

  // Патчим XMLHttpRequest
  var origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    this.__url = url;
    return origOpen.apply(this, arguments);
  };

  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    this.addEventListener('load', function() {
      try { tryExtract(this.__url, this.responseText); } catch (e) {}
    });
    return origSend.apply(this, arguments);
  };
})();
""";

  int? HunterVegasFirstPageTimestamp;

  int HunterVegasStartLoadTimestamp = 0;

  final Set<String> HunterVegasExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  final Set<String> HunterVegasExternalSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(
        HunterVegasFcmBackgroundHandler);

    HunterVegasFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    HunterVegasInitPushAndGetToken();
    HunterVegasDeviceProfileInstance.HunterVegasInitialize();
    HunterVegasWireForegroundPushHandlers();
    HunterVegasBindPlatformNotificationTap();

    HunterVegasSpyInstance.HunterVegasStart(
      hunterVegasOnUpdate: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    HunterVegasEmailPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState hunterVegasState) {
    if (hunterVegasState == AppLifecycleState.paused) {
      HunterVegasLastPausedAt = DateTime.now();
    }

    if (hunterVegasState == AppLifecycleState.resumed) {
      if (Platform.isIOS && HunterVegasLastPausedAt != null) {
        final DateTime hunterVegasNow = DateTime.now();

        final Duration hunterVegasDrift =
        hunterVegasNow.difference(HunterVegasLastPausedAt!);

        if (hunterVegasDrift > const Duration(minutes: 25)) {
          HunterVegasForceReloadToLobby();
        }
      }

      HunterVegasLastPausedAt = null;
    }
  }

  void HunterVegasForceReloadToLobby() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback(
          (Duration hunterVegasDuration) {
        if (!mounted) return;
      },
    );
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------

  void HunterVegasWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage hunterVegasMsg) {
      if (hunterVegasMsg.data['uri'] != null) {
        HunterVegasNavigateTo(hunterVegasMsg.data['uri'].toString());
      } else {
        HunterVegasReturnToCurrentUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen(
          (RemoteMessage hunterVegasMsg) {
        if (hunterVegasMsg.data['uri'] != null) {
          HunterVegasNavigateTo(hunterVegasMsg.data['uri'].toString());
        } else {
          HunterVegasReturnToCurrentUrl();
        }
      },
    );
  }

  void HunterVegasNavigateTo(String hunterVegasNewUrl) async {
    await HunterVegasWebViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(hunterVegasNewUrl)),
    );
  }

  void HunterVegasReturnToCurrentUrl() async {
    Future<void>.delayed(const Duration(seconds: 3), () {
      HunterVegasWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(HunterVegasCurrentUrl)),
      );
    });
  }

  Future<void> HunterVegasInitPushAndGetToken() async {
    final FirebaseMessaging hunterVegasFm = FirebaseMessaging.instance;

    await hunterVegasFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    HunterVegasPushToken = await hunterVegasFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала
  // --------------------------------------------------------------------------

  void HunterVegasBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall hunterVegasCall) async {
      if (hunterVegasCall.method == "onNotificationTap") {
        final Map<String, dynamic> hunterVegasPayload =
        Map<String, dynamic>.from(hunterVegasCall.arguments);

        debugPrint("URI from platform tap: ${hunterVegasPayload['uri']}");

        final String? hunterVegasUriString =
        hunterVegasPayload["uri"]?.toString();

        if (hunterVegasUriString != null &&
            !hunterVegasUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext hunterVegasContext) =>
                  HunterVegasTableView(hunterVegasUriString),
            ),
                (Route<dynamic> hunterVegasRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    HunterVegasBindPlatformNotificationTap();

    final bool hunterVegasIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: hunterVegasIsDark
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri(HunterVegasCurrentUrl),
              ),
              onWebViewCreated:
                  (InAppWebViewController hunterVegasController) {
                HunterVegasWebViewController = hunterVegasController;

                HunterVegasWebViewController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (List<dynamic> hunterVegasArgs) {
                    HunterVegasVaultInstance.HunterVegasLoggerInstance
                        .HunterVegasLogInfo("JS Args: $hunterVegasArgs");

                    try {
                      return hunterVegasArgs.reduce(
                            (dynamic hunterVegasV, dynamic hunterVegasE) =>
                        hunterVegasV + hunterVegasE,
                      );
                    } catch (_) {
                      return hunterVegasArgs.toString();
                    }
                  },
                );

                // Handler для email из /player
                HunterVegasWebViewController.addJavaScriptHandler(
                  handlerName: 'onPlayerData',
                  callback: (List<dynamic> hunterVegasArgs) {
                    final String? hunterVegasEmail = hunterVegasArgs.isNotEmpty
                        ? hunterVegasArgs[0]?.toString()
                        : null;
                    if (hunterVegasEmail != null &&
                        hunterVegasEmail.isNotEmpty) {
                      HunterVegasCapturedEmail = hunterVegasEmail;
                      HunterVegasEmailPollTimer?.cancel();
                      debugPrint('==============================');
                      debugPrint(
                          '>>> PLAYER EMAIL CAPTURED: $hunterVegasEmail');
                      debugPrint('==============================');
                    }
                  },
                );
              },
              onLoadStart: (
                  InAppWebViewController hunterVegasController,
                  Uri? hunterVegasUri,
                  ) async {
                HunterVegasStartLoadTimestamp =
                    DateTime.now().millisecondsSinceEpoch;

                if (hunterVegasUri != null) {
                  if (HunterVegasKit.HunterVegasLooksLikeBareMail(
                    hunterVegasUri,
                  )) {
                    try {
                      await hunterVegasController.stopLoading();
                    } catch (_) {}

                    final Uri hunterVegasMailto =
                    HunterVegasKit.HunterVegasToMailto(hunterVegasUri);

                    await HunterVegasLinker.HunterVegasOpen(
                      HunterVegasKit.HunterVegasGmailize(hunterVegasMailto),
                    );

                    return;
                  }

                  final String hunterVegasScheme =
                  hunterVegasUri.scheme.toLowerCase();

                  if (hunterVegasScheme != 'http' &&
                      hunterVegasScheme != 'https') {
                    try {
                      await hunterVegasController.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop: (
                  InAppWebViewController hunterVegasController,
                  Uri? hunterVegasUri,
                  ) async {
                await hunterVegasController.evaluateJavascript(
                  source: "console.log('Hello from Roulette JS!');",
                );

                // Внедряем перехватчик fetch/XHR для email
                await hunterVegasController.evaluateJavascript(
                  source: HunterVegasInterceptScript,
                );

                // Запускаем поллинг раз в минуту как запасной вариант
                HunterVegasStartEmailPolling(hunterVegasController);

                setState(() {
                  HunterVegasCurrentUrl =
                      hunterVegasUri?.toString() ?? HunterVegasCurrentUrl;
                });

                Future<void>.delayed(const Duration(seconds: 20), () {
                  HunterVegasSendLoadedOnce();
                });
              },
              shouldOverrideUrlLoading: (
                  InAppWebViewController hunterVegasController,
                  NavigationAction hunterVegasNav,
                  ) async {
                final Uri? hunterVegasUri = hunterVegasNav.request.url;

                if (hunterVegasUri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                if (HunterVegasKit.HunterVegasLooksLikeBareMail(
                  hunterVegasUri,
                )) {
                  final Uri hunterVegasMailto =
                  HunterVegasKit.HunterVegasToMailto(hunterVegasUri);

                  await HunterVegasLinker.HunterVegasOpen(
                    HunterVegasKit.HunterVegasGmailize(hunterVegasMailto),
                  );

                  return NavigationActionPolicy.CANCEL;
                }

                final String hunterVegasScheme =
                hunterVegasUri.scheme.toLowerCase();

                if (hunterVegasScheme == 'mailto') {
                  await HunterVegasLinker.HunterVegasOpen(
                    HunterVegasKit.HunterVegasGmailize(hunterVegasUri),
                  );

                  return NavigationActionPolicy.CANCEL;
                }

                if (hunterVegasScheme == 'tel') {
                  await launchUrl(
                    hunterVegasUri,
                    mode: LaunchMode.externalApplication,
                  );

                  return NavigationActionPolicy.CANCEL;
                }

                final String hunterVegasHost =
                hunterVegasUri.host.toLowerCase();

                final bool hunterVegasIsSocial =
                    hunterVegasHost.endsWith('facebook.com') ||
                        hunterVegasHost.endsWith('instagram.com') ||
                        hunterVegasHost.endsWith('twitter.com') ||
                        hunterVegasHost.endsWith('x.com');

                if (hunterVegasIsSocial) {
                  await HunterVegasLinker.HunterVegasOpen(hunterVegasUri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (HunterVegasIsExternalDestination(hunterVegasUri)) {
                  final Uri hunterVegasMapped =
                  HunterVegasMapExternalToHttp(hunterVegasUri);

                  await HunterVegasLinker.HunterVegasOpen(hunterVegasMapped);

                  return NavigationActionPolicy.CANCEL;
                }

                if (hunterVegasScheme != 'http' &&
                    hunterVegasScheme != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow: (
                  InAppWebViewController hunterVegasController,
                  CreateWindowAction hunterVegasReq,
                  ) async {
                final Uri? hunterVegasUrl = hunterVegasReq.request.url;

                if (hunterVegasUrl == null) return false;

                if (HunterVegasKit.HunterVegasLooksLikeBareMail(
                  hunterVegasUrl,
                )) {
                  final Uri hunterVegasMail =
                  HunterVegasKit.HunterVegasToMailto(hunterVegasUrl);

                  await HunterVegasLinker.HunterVegasOpen(
                    HunterVegasKit.HunterVegasGmailize(hunterVegasMail),
                  );

                  return false;
                }

                final String hunterVegasScheme =
                hunterVegasUrl.scheme.toLowerCase();

                if (hunterVegasScheme == 'mailto') {
                  await HunterVegasLinker.HunterVegasOpen(
                    HunterVegasKit.HunterVegasGmailize(hunterVegasUrl),
                  );

                  return false;
                }

                if (hunterVegasScheme == 'tel') {
                  await launchUrl(
                    hunterVegasUrl,
                    mode: LaunchMode.externalApplication,
                  );

                  return false;
                }

                final String hunterVegasHost =
                hunterVegasUrl.host.toLowerCase();

                final bool hunterVegasIsSocial =
                    hunterVegasHost.endsWith('facebook.com') ||
                        hunterVegasHost.endsWith('instagram.com') ||
                        hunterVegasHost.endsWith('twitter.com') ||
                        hunterVegasHost.endsWith('x.com');

                if (hunterVegasIsSocial) {
                  await HunterVegasLinker.HunterVegasOpen(hunterVegasUrl);
                  return false;
                }

                if (HunterVegasIsExternalDestination(hunterVegasUrl)) {
                  final Uri hunterVegasMapped =
                  HunterVegasMapExternalToHttp(hunterVegasUrl);

                  await HunterVegasLinker.HunterVegasOpen(hunterVegasMapped);

                  return false;
                }

                if (hunterVegasScheme == 'http' ||
                    hunterVegasScheme == 'https') {
                  hunterVegasController.loadUrl(
                    urlRequest: URLRequest(
                      url: WebUri(hunterVegasUrl.toString()),
                    ),
                  );
                }

                return false;
              },
            ),
            if (HunterVegasOverlayBusy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black87,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // Внешние направления
  // ========================================================================

  bool HunterVegasIsExternalDestination(Uri hunterVegasUri) {
    final String hunterVegasScheme = hunterVegasUri.scheme.toLowerCase();

    if (HunterVegasExternalSchemes.contains(hunterVegasScheme)) {
      return true;
    }

    if (hunterVegasScheme == 'http' || hunterVegasScheme == 'https') {
      final String hunterVegasHost = hunterVegasUri.host.toLowerCase();

      if (HunterVegasExternalHosts.contains(hunterVegasHost)) {
        return true;
      }

      if (hunterVegasHost.endsWith('t.me')) return true;
      if (hunterVegasHost.endsWith('wa.me')) return true;
      if (hunterVegasHost.endsWith('m.me')) return true;
      if (hunterVegasHost.endsWith('signal.me')) return true;
      if (hunterVegasHost.endsWith('facebook.com')) return true;
      if (hunterVegasHost.endsWith('instagram.com')) return true;
      if (hunterVegasHost.endsWith('twitter.com')) return true;
      if (hunterVegasHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri HunterVegasMapExternalToHttp(Uri hunterVegasUri) {
    final String hunterVegasScheme = hunterVegasUri.scheme.toLowerCase();

    if (hunterVegasScheme == 'tg' || hunterVegasScheme == 'telegram') {
      final Map<String, String> hunterVegasQp =
          hunterVegasUri.queryParameters;

      final String? hunterVegasDomain = hunterVegasQp['domain'];

      if (hunterVegasDomain != null && hunterVegasDomain.isNotEmpty) {
        return Uri.https('t.me', '/$hunterVegasDomain', <String, String>{
          if (hunterVegasQp['start'] != null)
            'start': hunterVegasQp['start']!,
        });
      }

      final String hunterVegasPath =
      hunterVegasUri.path.isNotEmpty ? hunterVegasUri.path : '';

      return Uri.https(
        't.me',
        '/$hunterVegasPath',
        hunterVegasUri.queryParameters.isEmpty
            ? null
            : hunterVegasUri.queryParameters,
      );
    }

    if (hunterVegasScheme == 'whatsapp') {
      final Map<String, String> hunterVegasQp =
          hunterVegasUri.queryParameters;

      final String? hunterVegasPhone = hunterVegasQp['phone'];
      final String? hunterVegasText = hunterVegasQp['text'];

      if (hunterVegasPhone != null && hunterVegasPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${HunterVegasKit.HunterVegasDigitsOnly(hunterVegasPhone)}',
          <String, String>{
            if (hunterVegasText != null && hunterVegasText.isNotEmpty)
              'text': hunterVegasText,
          },
        );
      }

      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (hunterVegasText != null && hunterVegasText.isNotEmpty)
            'text': hunterVegasText,
        },
      );
    }

    if (hunterVegasScheme == 'bnl') {
      final String hunterVegasNewPath =
      hunterVegasUri.path.isNotEmpty ? hunterVegasUri.path : '';

      return Uri.https(
        'bnl.com',
        '/$hunterVegasNewPath',
        hunterVegasUri.queryParameters.isEmpty
            ? null
            : hunterVegasUri.queryParameters,
      );
    }

    return hunterVegasUri;
  }

  void HunterVegasStartEmailPolling(
      InAppWebViewController hunterVegasController) {
    if (HunterVegasCapturedEmail != null) return; // уже есть — не надо

    HunterVegasEmailPollTimer?.cancel();
    HunterVegasEmailPollTimer = Timer.periodic(
      const Duration(minutes: 1),
          (Timer hunterVegasTimer) async {
        if (HunterVegasCapturedEmail != null) {
          hunterVegasTimer.cancel();
          return;
        }

        try {
          final dynamic hunterVegasResult =
          await hunterVegasController.evaluateJavascript(
            source: 'window.__capturedEmail || null',
          );

          if (hunterVegasResult != null &&
              hunterVegasResult.toString() != 'null' &&
              hunterVegasResult.toString().isNotEmpty) {
            HunterVegasCapturedEmail = hunterVegasResult.toString();
            hunterVegasTimer.cancel();
            debugPrint('==============================');
            debugPrint(
                '>>> PLAYER EMAIL CAPTURED (poll): $HunterVegasCapturedEmail');
            debugPrint('==============================');
          } else {
            HunterVegasVaultInstance.HunterVegasLoggerInstance
                .HunterVegasLogInfo(
                'Email poll: not found yet, retry in 1 min');
          }
        } catch (_) {}
      },
    );
  }

  Future<void> HunterVegasSendLoadedOnce() async {
    if (HunterVegasLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final int hunterVegasNow = DateTime.now().millisecondsSinceEpoch;

    await HunterVegasPostStat(
      hunterVegasEvent: 'Loaded',
      hunterVegasTimeStart: HunterVegasStartLoadTimestamp,
      hunterVegasTimeFinish: hunterVegasNow,
      hunterVegasUrl: HunterVegasCurrentUrl,
      hunterVegasAppSid: HunterVegasSpyInstance.HunterVegasAppsFlyerUid,
      hunterVegasFirstPageTs: HunterVegasFirstPageTimestamp,
    );

    HunterVegasLoadedOnceSent = true;
  }
}