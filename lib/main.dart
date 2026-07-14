import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as appsflyer_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
    MethodChannel,
    SystemChrome,
    SystemUiOverlayStyle,
    MethodCall,
    VoidCallback;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;
import 'package:vegasroyalstakes/pushveg.dart';

import 'gameveg.dart';
import 'loadeveg.dart';

// ============================================================================
// Константы
// ============================================================================

const String hunterVegasRetroLoadedOnceKey = 'loaded_once';
const String hunterVegasRetroStatEndpoint = 'https://apistor.revieramerge.best/stat';
const String hunterVegasRetroCachedFcmKey = 'cached_fcm';
const String hunterVegasRetroCachedDeepKey = 'cached_deep_push_uri';

const Set<String> kBankSchemes = {
  'td',
  'rbc',
  'cibc',
  'scotiabank',
  'bmo',
  'bmodigitalbanking',
  'desjardins',
  'tangerine',
  'nationalbank',
  'simplii',
  'dominotoronto',
};

const Set<String> kBankDomains = {
  'td.com',
  'tdcanadatrust.com',
  'easyweb.td.com',
  'rbc.com',
  'royalbank.com',
  'online.royalbank.com',
  'cibc.com',
  'cibc.ca',
  'online.cibc.com',
  'scotiabank.com',
  'scotiaonline.scotiabank.com',
  'bmo.com',
  'bmo.ca',
  'bmodigitalbanking.com',
  'desjardins.com',
  'tangerine.ca',
  'nbc.ca',
  'nationalbank.ca',
  'simplii.com',
  'simplii.ca',
  'dominotoronto.com',
  'dominobank.com',
};

// ============================================================================
// OneLink / AppsFlyer домены — НЕ открывать во внешнем браузере
// ============================================================================

const Set<String> kOneLinkDomains = {
  'onelink.me',
  'app.appsflyer.com',
  'appsflyer.com',
  'af-link.com',
};

/// Проверяет, является ли URL ссылкой OneLink / AppsFlyer
bool HunterVegasIsOneLinkUrl(Uri uri) {
  final String host = uri.host.toLowerCase();
  if (host.isEmpty) return false;

  for (final String domain in kOneLinkDomains) {
    final String d = domain.toLowerCase();
    if (host == d || host.endsWith('.$d')) {
      return true;
    }
  }
  return false;
}

// ============================================================================
// Лёгкие сервисы
// ============================================================================

class HunterVegasLoggerService {
  static final HunterVegasLoggerService SharedInstance =
  HunterVegasLoggerService._InternalConstructor();

  HunterVegasLoggerService._InternalConstructor();

  factory HunterVegasLoggerService() => SharedInstance;

  final Connectivity HunterVegasConnectivity = Connectivity();

  void HunterVegasLogInfo(Object message) => print('[I] $message');
  void HunterVegasLogWarn(Object message) => print('[W] $message');
  void HunterVegasLogError(Object message) => print('[E] $message');
}

class HunterVegasNetworkService {
  final HunterVegasLoggerService HunterVegasLogger = HunterVegasLoggerService();

  Future<void> HunterVegasPostJson(
      String url,
      Map<String, dynamic> data,
      ) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (error) {
      HunterVegasLogger.HunterVegasLogError('postJson error: $error');
    }
  }
}

// ============================================================================
// Утилита: одновременное сохранение JSON в localStorage и SharedPreferences
// ============================================================================

Future<void> HunterVegasSaveJsonToLocalStorageAndPrefs({
  required InAppWebViewController? controller,
  required String key,
  required Map<String, dynamic> data,
}) async {
  final String jsonString = jsonEncode(data);

  if (controller != null) {
    try {
      await controller.evaluateJavascript(
        source: "localStorage.setItem('$key', JSON.stringify($jsonString));",
      );
    } catch (e, st) {
      HunterVegasLoggerService().HunterVegasLogError(
          'NcupSaveJsonToLocalStorageAndPrefs localStorage error: $e\n$st');
    }
  }

  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonString);
  } catch (e, st) {
    HunterVegasLoggerService().HunterVegasLogError(
        'NcupSaveJsonToLocalStorageAndPrefs prefs error: $e\n$st');
  }
}

// ============================================================================
// Профиль устройства
// ============================================================================

class HunterVegasDeviceProfile {
  String? HunterVegasDeviceId;
  String? HunterVegasSessionId = '';
  String? HunterVegasPlatformName;
  String? HunterVegasOsVersion;
  String? HunterVegasAppVersion;
  String? HunterVegasLanguageCode;
  String? HunterVegasTimezoneName;
  bool HunterVegasPushEnabled = false;

  bool HunterVegasSafeAreaEnabled = false;
  String? HunterVegasSafeAreaColor;

  bool safecasher = false;

  String? HunterVegasBaseUserAgent;

  Map<String, dynamic>? HunterVegasLastPushData;

  Map<String, dynamic>? HunterVegasSavels;

  Future<void> HunterVegasInitialize() async {
    final DeviceInfoPlugin hunterVegasDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo hunterVegasAndroidInfo =
      await hunterVegasDeviceInfoPlugin.androidInfo;
      HunterVegasDeviceId = hunterVegasAndroidInfo.id;
      HunterVegasPlatformName = 'android';
      HunterVegasOsVersion = hunterVegasAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo hunterVegasIosInfo =
      await hunterVegasDeviceInfoPlugin.iosInfo;
      HunterVegasDeviceId = hunterVegasIosInfo.identifierForVendor;
      HunterVegasPlatformName = 'ios';
      HunterVegasOsVersion = hunterVegasIosInfo.systemVersion;
    }

    final PackageInfo hunterVegasPackageInfo =
    await PackageInfo.fromPlatform();
    HunterVegasAppVersion = hunterVegasPackageInfo.version;
    HunterVegasLanguageCode = Platform.localeName.split('_').first;
    HunterVegasTimezoneName = tz_zone.local.name;
    HunterVegasSessionId = 'test-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> HunterVegasToMap({String? fcmToken}) =>
      <String, dynamic>{
        'fcm_token': fcmToken ?? 'missing_token',
        'device_id': HunterVegasDeviceId ?? 'missing_id',
        'app_name': 'vegasstrike',
        'instance_id': HunterVegasSessionId ?? 'missing_session',
        'platform': HunterVegasPlatformName ?? 'missing_system',
        'os_version': HunterVegasOsVersion ?? 'missing_build',
        'app_version': '1.4.1' ?? 'missing_app',
        'language': HunterVegasLanguageCode ?? 'en',
        'timezone': HunterVegasTimezoneName ?? 'UTC',
        'push_enabled': HunterVegasPushEnabled,
        'safe_area_native': HunterVegasSafeAreaEnabled,
        'useragent': HunterVegasBaseUserAgent ?? 'unknown_useragent',
        'savels': HunterVegasSavels ?? <String, dynamic>{},
        'fpscashier': safecasher,
      };
}

// ============================================================================
// AppsFlyer Spy
// ============================================================================

class HunterVegasAnalyticsSpyService {
  appsflyer_core.AppsFlyerOptions? HunterVegasAppsFlyerOptions;
  appsflyer_core.AppsflyerSdk? HunterVegasAppsFlyerSdk;

  String HunterVegasAppsFlyerUid = '';
  String HunterVegasAppsFlyerData = '';

  Map<String, dynamic>? HunterVegasAppsFlyerOneLinkData;

  void HunterVegasStartTracking({VoidCallback? onUpdate}) {
    final appsflyer_core.AppsFlyerOptions hunterVegasConfig =
    appsflyer_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6790771087',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    HunterVegasAppsFlyerOptions = hunterVegasConfig;
    HunterVegasAppsFlyerSdk = appsflyer_core.AppsflyerSdk(hunterVegasConfig);

    HunterVegasAppsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    HunterVegasAppsFlyerSdk?.startSDK(
      onSuccess: () =>
          HunterVegasLoggerService().HunterVegasLogInfo('RetroCarAnalyticsSpy started'),
      onError: (int code, String msg) => HunterVegasLoggerService()
          .HunterVegasLogError('RetroCarAnalyticsSpy error $code: $msg'),
    );

    HunterVegasAppsFlyerSdk?.onInstallConversionData((dynamic value) {
      HunterVegasAppsFlyerData = value.toString();
      onUpdate?.call();
    });

    HunterVegasAppsFlyerSdk?.getAppsFlyerUID().then((dynamic value) {
      HunterVegasAppsFlyerUid = value.toString();
      onUpdate?.call();
    });
  }

  void HunterVegasSetOneLinkData(Map<String, dynamic> data) {
    HunterVegasAppsFlyerOneLinkData = data;
    HunterVegasLoggerService()
        .HunterVegasLogInfo('NcupAnalyticsSpyService: OneLink data updated: $data');
  }
}

// ============================================================================
// FCM фон
// ============================================================================

@pragma('vm:entry-point')
Future<void> HunterVegasFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  HunterVegasLoggerService().HunterVegasLogInfo('bg-fcm: ${message.messageId}');
  HunterVegasLoggerService().HunterVegasLogInfo('bg-data: ${message.data}');

  final dynamic hunterVegasLink = message.data['uri'];
  if (hunterVegasLink != null) {
    try {
      final SharedPreferences hunterVegasPrefs =
      await SharedPreferences.getInstance();
      await hunterVegasPrefs.setString(
        hunterVegasRetroCachedDeepKey,
        hunterVegasLink.toString(),
      );
    } catch (e) {
      HunterVegasLoggerService()
          .HunterVegasLogError('bg-fcm save deep failed: $e');
    }
  }
}

// ============================================================================
// FCM Bridge — токен
// ============================================================================

class HunterVegasFcmBridge {
  final HunterVegasLoggerService HunterVegasLogger = HunterVegasLoggerService();

  static const MethodChannel _tokenChannel =
  MethodChannel('com.example.fcm/token');

  String? HunterVegasToken;
  final List<void Function(String)> HunterVegasTokenWaiters =
  <void Function(String)>[];

  String? get HunterVegasFcmToken => HunterVegasToken;

  Timer? _requestTimer;
  int _requestAttempts = 0;
  final int _maxAttempts = 10;

  HunterVegasFcmBridge() {
    _tokenChannel.setMethodCallHandler((MethodCall HunterVegasCall) async {
      if (HunterVegasCall.method == 'setToken') {
        final String HunterVegasTokenString =
        HunterVegasCall.arguments as String;
        HunterVegasLogger.HunterVegasLogInfo(
            'NcupFcmBridge: got token from native channel = $HunterVegasTokenString');
        if (HunterVegasTokenString.isNotEmpty) {
          HunterVegasSetToken(HunterVegasTokenString);
        }
      }
    });

    HunterVegasRestoreToken();
    _requestNativeToken();
    _startRequestTimer();
  }

  Future<void> _requestNativeToken() async {
    try {
      HunterVegasLogger.HunterVegasLogInfo(
          'NcupFcmBridge: request native getToken()');
      final String? token =
      await _tokenChannel.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        HunterVegasLogger.HunterVegasLogInfo(
            'NcupFcmBridge: native getToken() returns $token');
        HunterVegasSetToken(token);
      } else {
        HunterVegasLogger.HunterVegasLogWarn(
            'NcupFcmBridge: native getToken() returned empty');
      }
    } catch (e) {
      HunterVegasLogger.HunterVegasLogWarn(
          'NcupFcmBridge: getToken invoke error: $e');
    }
  }

  void _startRequestTimer() {
    _requestTimer?.cancel();
    _requestAttempts = 0;

    _requestTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) async {
      if ((HunterVegasToken ?? '').isNotEmpty) {
        HunterVegasLogger.HunterVegasLogInfo(
            'NcupFcmBridge: token already set, stop request timer');
        t.cancel();
        return;
      }

      if (_requestAttempts >= _maxAttempts) {
        HunterVegasLogger.HunterVegasLogWarn(
            'NcupFcmBridge: max getToken attempts reached, stop timer');
        t.cancel();
        return;
      }

      _requestAttempts++;
      HunterVegasLogger.HunterVegasLogInfo(
          'NcupFcmBridge: retry getToken() attempt #$_requestAttempts');
      await _requestNativeToken();
    });
  }

  Future<void> HunterVegasRestoreToken() async {
    try {
      final SharedPreferences hunterVegasPrefs =
      await SharedPreferences.getInstance();
      final String? hunterVegasCachedToken =
      hunterVegasPrefs.getString(hunterVegasRetroCachedFcmKey);
      if (hunterVegasCachedToken != null && hunterVegasCachedToken.isNotEmpty) {
        HunterVegasLogger.HunterVegasLogInfo(
            'NcupFcmBridge: restored cached token = $hunterVegasCachedToken');
        HunterVegasSetToken(hunterVegasCachedToken, notify: false);
      }
    } catch (e) {
      HunterVegasLogger.HunterVegasLogError('NcupRestoreToken error: $e');
    }
  }

  Future<void> HunterVegasPersistToken(String newToken) async {
    try {
      final SharedPreferences hunterVegasPrefs =
      await SharedPreferences.getInstance();
      await hunterVegasPrefs.setString(hunterVegasRetroCachedFcmKey, newToken);
    } catch (e) {
      HunterVegasLogger.HunterVegasLogError('NcupPersistToken error: $e');
    }
  }

  void HunterVegasSetToken(
      String newToken, {
        bool notify = true,
      }) {
    HunterVegasToken = newToken;
    HunterVegasPersistToken(newToken);

    if (notify) {
      for (final void Function(String) hunterVegasCallback
      in List<void Function(String)>.from(HunterVegasTokenWaiters)) {
        try {
          hunterVegasCallback(newToken);
        } catch (error) {
          HunterVegasLogger.HunterVegasLogWarn('fcm waiter error: $error');
        }
      }
      HunterVegasTokenWaiters.clear();
    }
  }

  Future<void> HunterVegasWaitForToken(
      Function(String token) hunterVegasOnToken,
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

      HunterVegasTokenWaiters.add(hunterVegasOnToken);
    } catch (error) {
      HunterVegasLogger.HunterVegasLogError('NcupWaitForToken error: $error');
    }
  }

  void dispose() {
    _requestTimer?.cancel();
  }
}

// ============================================================================
// Splash / Hall
// ============================================================================

class HunterVegasHall extends StatefulWidget {
  const HunterVegasHall({Key? key}) : super(key: key);

  @override
  State<HunterVegasHall> createState() => _HunterVegasHallState();
}

class _HunterVegasHallState extends State<HunterVegasHall> {
  final HunterVegasFcmBridge HunterVegasFcmBridgeInstance =
  HunterVegasFcmBridge();
  bool HunterVegasNavigatedOnce = false;
  Timer? HunterVegasFallbackTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    HunterVegasFcmBridgeInstance.HunterVegasWaitForToken((String hunterVegasToken) {
      HunterVegasGoToHarbor(hunterVegasToken);
    });

    HunterVegasFallbackTimer = Timer(
      const Duration(seconds: 8),
          () => HunterVegasGoToHarbor(''),
    );
  }

  void HunterVegasGoToHarbor(String hunterVegasSignal) {
    if (HunterVegasNavigatedOnce) return;
    HunterVegasNavigatedOnce = true;
    HunterVegasFallbackTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) =>
            HunterVegasHarbor(HunterVegasSignal: hunterVegasSignal),
      ),
    );
  }

  @override
  void dispose() {
    HunterVegasFallbackTimer?.cancel();
    HunterVegasFcmBridgeInstance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: AppLoader(),
        ),
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class HunterVegasBosunViewModel {
  final HunterVegasDeviceProfile HunterVegasDeviceProfileInstance;
  final HunterVegasAnalyticsSpyService HunterVegasAnalyticsSpyInstance;

  HunterVegasBosunViewModel({
    required this.HunterVegasDeviceProfileInstance,
    required this.HunterVegasAnalyticsSpyInstance,
  });

  Map<String, dynamic> HunterVegasDeviceMap(String? fcmToken) =>
      HunterVegasDeviceProfileInstance.HunterVegasToMap(fcmToken: fcmToken);

  Map<String, dynamic> HunterVegasAppsFlyerPayload(
      String? token, {
        String? deepLink,
      }) {
    final Map<String, dynamic> onelinkData =
        HunterVegasAnalyticsSpyInstance.HunterVegasAppsFlyerOneLinkData ??
            <String, dynamic>{};

    return <String, dynamic>{
      'content': <String, dynamic>{
        'af_data': HunterVegasAnalyticsSpyInstance.HunterVegasAppsFlyerData,
        'af_id': HunterVegasAnalyticsSpyInstance.HunterVegasAppsFlyerUid,
        'fb_app_name': 'vegasstrike',
        'app_name': 'vegasstrike',
        'onelink': onelinkData,
        'bundle_identifier': 'com.vegasroyalstake.vegasroyalstakes',
        'app_version': '1.4.1',
        'apple_id': '6790771087',
        'fcm_token': token ?? 'no_token',
        'device_id':
        HunterVegasDeviceProfileInstance.HunterVegasDeviceId ?? 'no_device',
        'instance_id':
        HunterVegasDeviceProfileInstance.HunterVegasSessionId ??
            'no_instance',
        'platform':
        HunterVegasDeviceProfileInstance.HunterVegasPlatformName ?? 'no_type',
        'os_version':
        HunterVegasDeviceProfileInstance.HunterVegasOsVersion ?? 'no_os',
        'language':
        HunterVegasDeviceProfileInstance.HunterVegasLanguageCode ?? 'en',
        'timezone':
        HunterVegasDeviceProfileInstance.HunterVegasTimezoneName ?? 'UTC',
        'push_enabled': HunterVegasDeviceProfileInstance.HunterVegasPushEnabled,
        'useruid': HunterVegasAnalyticsSpyInstance.HunterVegasAppsFlyerUid,
        'safearea':
        HunterVegasDeviceProfileInstance.HunterVegasSafeAreaEnabled,
        'safearea_color':
        HunterVegasDeviceProfileInstance.HunterVegasSafeAreaColor ?? '',
        'useragent':
        HunterVegasDeviceProfileInstance.HunterVegasBaseUserAgent ??
            'unknown_useragent',
        'push': HunterVegasDeviceProfileInstance.HunterVegasLastPushData ??
            <String, dynamic>{},
        'deep': deepLink,
        'fpscashier': HunterVegasDeviceProfileInstance.safecasher,
      },
    };
  }
}

class HunterVegasCourierService {
  final HunterVegasBosunViewModel HunterVegasBosun;
  final InAppWebViewController? Function() HunterVegasGetWebViewController;

  HunterVegasCourierService({
    required this.HunterVegasBosun,
    required this.HunterVegasGetWebViewController,
  });

  Future<InAppWebViewController?> _waitForController({
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    final HunterVegasLoggerService logger = HunterVegasLoggerService();
    final DateTime start = DateTime.now();

    while (DateTime.now().difference(start) < timeout) {
      final InAppWebViewController? c = HunterVegasGetWebViewController();
      if (c != null) {
        return c;
      }
      await Future<void>.delayed(interval);
    }

    logger.HunterVegasLogWarn(
        '_waitForController: timeout, controller is still null');
    return null;
  }

  Future<void> HunterVegasPutDeviceToLocalStorage(String? token) async {
    final InAppWebViewController? hunterVegasController =
    await _waitForController();
    if (hunterVegasController == null) return;

    final Map<String, dynamic> hunterVegasMap =
    HunterVegasBosun.HunterVegasDeviceMap(token);
    HunterVegasLoggerService()
        .HunterVegasLogInfo("applocal (${jsonEncode(hunterVegasMap)});");

    await HunterVegasSaveJsonToLocalStorageAndPrefs(
      controller: hunterVegasController,
      key: 'app_data',
      data: hunterVegasMap,
    );
  }

  Future<void> HunterVegasSendRawToPage(
      String? token, {
        String? deepLink,
      }) async {
    final InAppWebViewController? hunterVegasController =
    await _waitForController();
    if (hunterVegasController == null) return;

    final Map<String, dynamic> hunterVegasPayload =
    HunterVegasBosun.HunterVegasAppsFlyerPayload(token,
        deepLink: deepLink);

    final String hunterVegasJsonString = jsonEncode(hunterVegasPayload);

    HunterVegasLoggerService()
        .HunterVegasLogInfo('SendRawData: $hunterVegasJsonString');

    final String jsSafeJson = jsonEncode(hunterVegasJsonString);
    final String jsCode = 'sendRawData($jsSafeJson);';

    try {
      await hunterVegasController.evaluateJavascript(source: jsCode);
    } catch (e, st) {
      HunterVegasLoggerService().HunterVegasLogError(
          'NcupSendRawToPage evaluateJavascript error: $e\n$st');
    }
  }
}

// ============================================================================
// Статистика
// ============================================================================

Future<String> HunterVegasResolveFinalUrl(
    String startUrl, {
      int maxHops = 10,
    }) async {
  final HttpClient hunterVegasHttpClient = HttpClient();

  try {
    Uri hunterVegasCurrentUri = Uri.parse(startUrl);

    for (int hunterVegasIndex = 0;
    hunterVegasIndex < maxHops;
    hunterVegasIndex++) {
      final HttpClientRequest hunterVegasRequest =
      await hunterVegasHttpClient.getUrl(hunterVegasCurrentUri);
      hunterVegasRequest.followRedirects = false;
      final HttpClientResponse hunterVegasResponse =
      await hunterVegasRequest.close();

      if (hunterVegasResponse.isRedirect) {
        final String? hunterVegasLocationHeader =
        hunterVegasResponse.headers.value(HttpHeaders.locationHeader);
        if (hunterVegasLocationHeader == null ||
            hunterVegasLocationHeader.isEmpty) {
          break;
        }

        final Uri hunterVegasNextUri = Uri.parse(hunterVegasLocationHeader);
        hunterVegasCurrentUri = hunterVegasNextUri.hasScheme
            ? hunterVegasNextUri
            : hunterVegasCurrentUri.resolveUri(hunterVegasNextUri);
        continue;
      }

      return hunterVegasCurrentUri.toString();
    }

    return hunterVegasCurrentUri.toString();
  } catch (error) {
    print('goldenLuxuryResolveFinalUrl error: $error');
    return startUrl;
  } finally {
    hunterVegasHttpClient.close(force: true);
  }
}

Future<void> HunterVegasPostStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final String hunterVegasResolvedUrl =
    await HunterVegasResolveFinalUrl(url);

    final Map<String, dynamic> hunterVegasPayload = <String, dynamic>{
      'event': event,
      'timestart': timeStart,
      'timefinsh': timeFinish,
      'url': hunterVegasResolvedUrl,
      'appleID': '6790771087',
      'open_count': '$appSid/$timeStart',
    };

    print('goldenLuxuryStat $hunterVegasPayload');

    final http.Response hunterVegasResponse = await http.post(
      Uri.parse('$hunterVegasRetroStatEndpoint/$appSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(hunterVegasPayload),
    );

    print(
        'goldenLuxuryStat resp=${hunterVegasResponse.statusCode} body=${hunterVegasResponse.body}');
  } catch (error) {
    print('goldenLuxuryPostStat error: $error');
  }
}

// ============================================================================
// Открытие неизвестных кастомных схем (otpauth и т.п.) во внешнем приложении
// ============================================================================

Future<bool> HunterVegasTryOpenUnknownSchemeExternally(Uri uri) async {
  try {
    final bool can = await canLaunchUrl(uri);
    if (!can) {
      print('NcupTryOpenUnknownSchemeExternally: no handler for $uri');
      return false;
    }
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    print('NcupTryOpenUnknownSchemeExternally: launched=$ok uri=$uri');
    return ok;
  } catch (e) {
    print('NcupTryOpenUnknownSchemeExternally error: $e; uri=$uri');
    return false;
  }
}

bool HunterVegasIsCancelledLoadError({String? description, dynamic type}) {
  final String desc = (description ?? '').toLowerCase();
  final String typeString = (type?.toString() ?? '').toLowerCase();
  return desc.contains('-999') ||
      desc.contains('cancelled') ||
      desc.contains('canceled') ||
      typeString.contains('cancelled') ||
      typeString.contains('canceled');
}

// ============================================================================
// Банковские утилиты
// ============================================================================

bool HunterVegasIsBankScheme(Uri uri) {
  final String scheme = uri.scheme.toLowerCase();
  return kBankSchemes.contains(scheme);
}

bool HunterVegasIsBankDomain(Uri uri) {
  final String host = uri.host.toLowerCase();
  if (host.isEmpty) return false;

  for (final String bank in kBankDomains) {
    final String bankHost = bank.toLowerCase();
    if (host == bankHost || host.endsWith('.$bankHost')) {
      return true;
    }
  }
  return false;
}

Future<bool> HunterVegasOpenBank(Uri uri) async {
  try {
    if (HunterVegasIsBankScheme(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }

    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        HunterVegasIsBankDomain(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }
  } catch (e) {
    print('NcupOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// Главный WebView — Harbor
// ============================================================================

class HunterVegasHarbor extends StatefulWidget {
  final String? HunterVegasSignal;

  const HunterVegasHarbor({super.key, required this.HunterVegasSignal});

  @override
  State<HunterVegasHarbor> createState() => _HunterVegasHarborState();
}

class _HunterVegasHarborState extends State<HunterVegasHarbor>
    with WidgetsBindingObserver {
  InAppWebViewController? HunterVegasWebViewController;

  InAppWebViewController? HunterVegasPopupWebViewController;
  bool _isPopupVisible = false;
  String? _popupUrl;
  CreateWindowAction? _popupCreateAction;

  bool _popupCanGoBack = false;
  String? _popupCurrentUrl;

  bool _isOpeningExternalNewTab = false;
  final Set<String> _handledNewTabUrls = <String>{};

  Timer? _parentInstallTimer;
  Timer? _popupInstallTimer;

  final String HunterVegasHomeUrl =
      'https://appapi.vegasstrike.quest/';

  int HunterVegasWebViewKeyCounter = 0;
  DateTime? HunterVegasSleepAt;
  bool HunterVegasVeilVisible = false;
  double HunterVegasWarmProgress = 0.0;
  late Timer HunterVegasWarmTimer;
  final int HunterVegasWarmSeconds = 6;
  bool HunterVegasCoverVisible = true;

  bool HunterVegasLoadedOnceSent = false;
  int? HunterVegasFirstPageTimestamp;

  HunterVegasCourierService? HunterVegasCourier;
  HunterVegasBosunViewModel? HunterVegasBosunInstance;

  String HunterVegasCurrentUrl = '';
  int HunterVegasStartLoadTimestamp = 0;

  final HunterVegasDeviceProfile HunterVegasDeviceProfileInstance =
  HunterVegasDeviceProfile();
  final HunterVegasAnalyticsSpyService HunterVegasAnalyticsSpyInstance =
  HunterVegasAnalyticsSpyService();

  final Set<String> HunterVegasSpecialSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> HunterVegasExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
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

  String? HunterVegasDeepLinkFromPush;

  String? _baseUserAgent;
  String _currentUserAgent = "";
  String? _currentUrl;

  String? _serverUserAgent;

  bool _safeAreaEnabled = false;
  Color _safeAreaBackgroundColor = const Color(0xFF000000);

  bool _startupSendRawDone = false;

  String? _pendingLoadedJs;

  bool _loadedJsExecutedOnce = false;

  bool _isInGoogleAuth = false;

  List<String> _buttonWhitelist = <String>[];
  bool _showBackButton = false;

  bool _backButtonHiddenAfterTap = false;

  bool _isCurrentlyOnGoogle = false;

  static const MethodChannel _appsFlyerDeepLinkChannel =
  MethodChannel('appsflyer_deeplink_channel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HunterVegasFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;
    _currentUrl = HunterVegasHomeUrl;

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          HunterVegasCoverVisible = false;
        });
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        HunterVegasVeilVisible = true;
      });
    });

    _bindPushChannelFromAppDelegate();
    _bindAppsFlyerDeepLinkChannel();
    HunterVegasBootHarbor();
  }

  bool _isAboutBlankUrl(String? value) {
    final String u = (value ?? '').trim().toLowerCase();
    return u.isEmpty || u == 'about:blank' || u.startsWith('about:blank');
  }

  bool _isAboutBlankUri(Uri? uri) => _isAboutBlankUrl(uri?.toString());

  void _bindAppsFlyerDeepLinkChannel() {
    _appsFlyerDeepLinkChannel.setMethodCallHandler(
          (MethodCall call) async {
        if (call.method == 'onDeepLink') {
          try {
            final dynamic args = call.arguments;

            Map<String, dynamic> payload;

            print(" Data Deepl link ${args.toString()}");
            if (args is Map) {
              payload = Map<String, dynamic>.from(args as Map);
            } else if (args is String) {
              payload = jsonDecode(args) as Map<String, dynamic>;
            } else {
              payload = <String, dynamic>{'raw': args.toString()};
            }

            HunterVegasLoggerService()
                .HunterVegasLogInfo('AppsFlyer onDeepLink from iOS: $payload');

            final dynamic raw = payload['raw'];
            if (raw is Map) {
              final Map<String, dynamic> normalized =
              Map<String, dynamic>.from(raw as Map);

              print("One Link Data $normalized");
              HunterVegasAnalyticsSpyInstance
                  .HunterVegasSetOneLinkData(normalized);

              // === OneLink: извлекаем deep_link_value и навигируем внутри ===
              _handleOneLinkDeepNavigation(normalized);
            } else {
              HunterVegasAnalyticsSpyInstance
                  .HunterVegasSetOneLinkData(payload);
              _handleOneLinkDeepNavigation(payload);
            }
          } catch (e, st) {
            HunterVegasLoggerService()
                .HunterVegasLogError('Error in onDeepLink handler: $e\n$st');
          }
        }
      },
    );
  }

  /// Обработка OneLink deep link — навигация внутри WebView, а не во внешний браузер
  void _handleOneLinkDeepNavigation(Map<String, dynamic> data) {
    try {
      // Пытаемся извлечь URL для навигации из OneLink данных
      String? targetUrl;

      // deep_link_value — стандартное поле AppsFlyer OneLink
      if (data.containsKey('deep_link_value') &&
          data['deep_link_value'] != null) {
        final String dlv = data['deep_link_value'].toString().trim();
        if (dlv.startsWith('http://') || dlv.startsWith('https://')) {
          targetUrl = dlv;
        }
      }

      // af_dp — ещё одно стандартное поле
      if (targetUrl == null &&
          data.containsKey('af_dp') &&
          data['af_dp'] != null) {
        final String afDp = data['af_dp'].toString().trim();
        if (afDp.startsWith('http://') || afDp.startsWith('https://')) {
          targetUrl = afDp;
        }
      }

      // link — может быть финальным URL
      if (targetUrl == null &&
          data.containsKey('link') &&
          data['link'] != null) {
        final String link = data['link'].toString().trim();
        if (link.startsWith('http://') || link.startsWith('https://')) {
          targetUrl = link;
        }
      }

      // clickURL
      if (targetUrl == null &&
          data.containsKey('clickURL') &&
          data['clickURL'] != null) {
        final String clickUrl = data['clickURL'].toString().trim();
        if (clickUrl.startsWith('http://') || clickUrl.startsWith('https://')) {
          targetUrl = clickUrl;
        }
      }

      if (targetUrl != null && targetUrl.isNotEmpty) {
        HunterVegasLoggerService().HunterVegasLogInfo(
            'OneLink deep navigation: loading $targetUrl in WebView');
        HunterVegasDeepLinkFromPush = targetUrl;

        // Навигируем внутри WebView
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          HunterVegasNavigateToUri(targetUrl!);
        });
      } else {
        HunterVegasLoggerService().HunterVegasLogInfo(
            'OneLink deep navigation: no target URL found in data, '
                'sending data to page via sendRawData');
      }
    } catch (e, st) {
      HunterVegasLoggerService()
          .HunterVegasLogError('_handleOneLinkDeepNavigation error: $e\n$st');
    }
  }

  void _bindPushChannelFromAppDelegate() {
    const MethodChannel pushChannel = MethodChannel('com.example.fcm/push');

    pushChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'setPushData') {
        try {
          Map<String, dynamic> pushData;
          if (call.arguments is Map) {
            pushData = Map<String, dynamic>.from(call.arguments);
            print("Get Push Data $pushData");
          } else if (call.arguments is String) {
            pushData =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
          } else {
            pushData = <String, dynamic>{'raw': call.arguments.toString()};
          }

          HunterVegasLoggerService()
              .HunterVegasLogInfo('Got push data from AppDelegate: $pushData');

          HunterVegasDeviceProfileInstance.HunterVegasLastPushData = pushData;

          final dynamic uriRaw = pushData['uri'] ?? pushData['deep_link'];
          if (uriRaw != null && uriRaw.toString().isNotEmpty) {
            final String u = uriRaw.toString();
            HunterVegasDeepLinkFromPush = u;
            await HunterVegasSaveCachedDeep(u);
          }
        } catch (e, st) {
          HunterVegasLoggerService()
              .HunterVegasLogError('setPushData handler error: $e\n$st');
        }
      }
    });
  }

  bool _isGoogleUrl(Uri uri) {
    final String full = uri.toString().toLowerCase();
    return full.contains('google.com') ||
        full.contains('accounts.google.') ||
        full.contains('googleusercontent.com') ||
        full.contains('gstatic.com');
  }

  Future<void> _applyGoogleUserAgent() async {
    if (HunterVegasWebViewController == null) return;

    const String googleUa = 'random';

    if (_currentUserAgent == googleUa) {
      HunterVegasLoggerService()
          .HunterVegasLogInfo('[UA] Already set to "random" for Google, skip');
      return;
    }

    HunterVegasLoggerService()
        .HunterVegasLogInfo('[UA] Applying GOOGLE User-Agent: $googleUa');

    try {
      await HunterVegasWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: googleUa),
      );
      _currentUserAgent = googleUa;
      _isCurrentlyOnGoogle = true;
      print('[UA] GOOGLE WEBVIEW USER AGENT: $_currentUserAgent');
    } catch (e) {
      HunterVegasLoggerService()
          .HunterVegasLogError('Error setting Google User-Agent: $e');
    }
  }

  Future<void> _applyGoogleUserAgentForPopup() async {
    if (HunterVegasPopupWebViewController == null) return;

    const String googleUa = 'random';

    HunterVegasLoggerService().HunterVegasLogInfo(
        '[UA] Applying GOOGLE User-Agent to POPUP: $googleUa');

    try {
      await HunterVegasPopupWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: googleUa),
      );
      print('[UA] GOOGLE POPUP USER AGENT: $googleUa');
    } catch (e) {
      HunterVegasLoggerService()
          .HunterVegasLogError('Error setting Google User-Agent for popup: $e');
    }
  }

  Future<void> _updateUserAgentFromServerPayload(
      Map<dynamic, dynamic> root) async {
    String? fullua;
    String? uatail;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['fullua'] != null &&
          content['fullua'].toString().trim().isNotEmpty) {
        fullua = content['fullua'].toString().trim();
      }
      if (content['uatail'] != null &&
          content['uatail'].toString().trim().isNotEmpty) {
        uatail = content['uatail'].toString().trim();
      }
    }

    if (fullua == null &&
        root['fullua'] != null &&
        root['fullua'].toString().trim().isNotEmpty) {
      fullua = root['fullua'].toString().trim();
    }
    if (uatail == null &&
        root['uatail'] != null &&
        root['uatail'].toString().trim().isNotEmpty) {
      uatail = root['uatail'].toString().trim();
    }

    if (uatail == null) {
      final dynamic adata = root['adata'];
      if (adata is Map &&
          adata['uatail'] != null &&
          adata['uatail'].toString().trim().isNotEmpty) {
        uatail = adata['uatail'].toString().trim();
      }
    }

    await _applyUserAgent(fullua: fullua, uatail: uatail);
  }

  Future<void> _applyUserAgent({String? fullua, String? uatail}) async {
    if (HunterVegasWebViewController == null) return;

    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      try {
        final ua = await HunterVegasWebViewController!.evaluateJavascript(
          source: "navigator.userAgent",
        );
        if (ua is String && ua.trim().isNotEmpty) {
          _baseUserAgent = ua.trim();
          _currentUserAgent = _baseUserAgent!;
          HunterVegasDeviceProfileInstance.HunterVegasBaseUserAgent =
              _baseUserAgent;
          HunterVegasLoggerService()
              .HunterVegasLogInfo('Base User-Agent detected: $_baseUserAgent');
        }
      } catch (e) {
        HunterVegasLoggerService()
            .HunterVegasLogWarn('Failed to get base userAgent from JS: $e');
      }
    }

    if (_baseUserAgent == null || _baseUserAgent!.trim().isEmpty) {
      HunterVegasLoggerService().HunterVegasLogWarn(
          'Base User-Agent is still null/empty, skip UA update');
      return;
    }

    HunterVegasLoggerService().HunterVegasLogInfo(
        'Server UA payload: fullua="$fullua", uatail="$uatail", base="$_baseUserAgent"');

    String newUa;
    if (fullua != null && fullua.trim().isNotEmpty) {
      newUa = fullua.trim();
    } else if (uatail != null && uatail.trim().isNotEmpty) {
      newUa = "${_baseUserAgent!}/${uatail.trim()}";
    } else {
      newUa = "${_baseUserAgent!}";
    }

    _serverUserAgent = newUa;
    HunterVegasLoggerService()
        .HunterVegasLogInfo('Server UA calculated and stored: $_serverUserAgent');
  }

  Future<void> _applyNormalUserAgentIfNeeded() async {
    if (HunterVegasWebViewController == null) return;

    if (_isCurrentlyOnGoogle) {
      HunterVegasLoggerService().HunterVegasLogInfo(
          '[UA] Currently on Google page, keeping "random" UA');
      return;
    }

    final String targetUa = _serverUserAgent ?? _baseUserAgent ?? 'random';

    if (targetUa == _currentUserAgent) {
      HunterVegasLoggerService()
          .HunterVegasLogInfo('Normal UA unchanged, keeping: $_currentUserAgent');
      return;
    }

    HunterVegasLoggerService()
        .HunterVegasLogInfo('Applying NORMAL WebView User-Agent: $targetUa');

    try {
      await HunterVegasWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _currentUserAgent = targetUa;
      print('[UA] NORMAL WEBVIEW USER AGENT: $_currentUserAgent');
    } catch (e) {
      HunterVegasLoggerService().HunterVegasLogError(
          'Error while setting normal User-Agent "$targetUa": $e');
    }
  }

  Future<void> _switchUserAgentForUrl(Uri? uri) async {
    if (uri == null) return;

    if (_isGoogleUrl(uri)) {
      _isCurrentlyOnGoogle = true;
      await _applyGoogleUserAgent();
    } else {
      if (_isCurrentlyOnGoogle) {
        _isCurrentlyOnGoogle = false;
      }
      await _applyNormalUserAgentIfNeeded();
    }
  }

  Future<void> printJsUserAgent() async {
    if (HunterVegasWebViewController == null) return;

    try {
      final ua = await HunterVegasWebViewController!.evaluateJavascript(
        source: "navigator.userAgent",
      );

      if (ua is String) {
        print('[JS UA] navigator.userAgent = $ua');
      } else {
        print('[JS UA] navigator.userAgent (non-string) = $ua');
      }
    } catch (e, st) {
      print('Error reading navigator.userAgent: $e\n$st');
    }
  }

  Future<void> debugPrintCurrentUserAgent() async {
    HunterVegasLoggerService().HunterVegasLogInfo(
        '[STATE UA] _currentUserAgent = $_currentUserAgent');
    await printJsUserAgent();
  }

  Future<void> HunterVegasLoadLoadedFlag() async {
    final SharedPreferences hunterVegasPrefs =
    await SharedPreferences.getInstance();
    HunterVegasLoadedOnceSent =
        hunterVegasPrefs.getBool(hunterVegasRetroLoadedOnceKey) ?? false;
  }

  Future<void> HunterVegasSaveLoadedFlag() async {
    final SharedPreferences hunterVegasPrefs =
    await SharedPreferences.getInstance();
    await hunterVegasPrefs.setBool(hunterVegasRetroLoadedOnceKey, true);
    HunterVegasLoadedOnceSent = true;
  }

  Future<void> HunterVegasLoadCachedDeep() async {
    try {
      final SharedPreferences hunterVegasPrefs =
      await SharedPreferences.getInstance();
      final String? hunterVegasCached =
      hunterVegasPrefs.getString(hunterVegasRetroCachedDeepKey);
      if ((hunterVegasCached ?? '').isNotEmpty) {
        HunterVegasDeepLinkFromPush = hunterVegasCached;
      }
    } catch (_) {}
  }

  Future<void> HunterVegasSaveCachedDeep(String uri) async {
    try {
      final SharedPreferences hunterVegasPrefs =
      await SharedPreferences.getInstance();
      await hunterVegasPrefs.setString(hunterVegasRetroCachedDeepKey, uri);
    } catch (_) {}
  }

  Future<void> HunterVegasSendLoadedOnce({
    required String url,
    required int timestart,
  }) async {
    if (HunterVegasLoadedOnceSent) return;

    final int hunterVegasNow = DateTime.now().millisecondsSinceEpoch;

    await HunterVegasPostStat(
      event: 'Loaded',
      timeStart: timestart,
      timeFinish: hunterVegasNow,
      url: url,
      appSid: HunterVegasAnalyticsSpyInstance.HunterVegasAppsFlyerUid,
      firstPageLoadTs: HunterVegasFirstPageTimestamp,
    );

    await HunterVegasSaveLoadedFlag();
  }

  void HunterVegasBootHarbor() {
    HunterVegasStartWarmProgress();
    HunterVegasWireFcmHandlers();
    HunterVegasAnalyticsSpyInstance.HunterVegasStartTracking(
      onUpdate: () => setState(() {}),
    );
    HunterVegasBindNotificationTap();
    HunterVegasPrepareDeviceProfile();
  }

  void HunterVegasWireFcmHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage hunterVegasMessage) async {
      final dynamic hunterVegasLink = hunterVegasMessage.data['uri'];
      if (hunterVegasLink != null) {
        final String hunterVegasUri = hunterVegasLink.toString();
        HunterVegasDeepLinkFromPush = hunterVegasUri;
        await HunterVegasSaveCachedDeep(hunterVegasUri);
      } else {
        HunterVegasResetHomeAfterDelay();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage hunterVegasMessage) async {
      final dynamic hunterVegasLink = hunterVegasMessage.data['uri'];
      if (hunterVegasLink != null) {
        final String hunterVegasUri = hunterVegasLink.toString();
        HunterVegasDeepLinkFromPush = hunterVegasUri;
        await HunterVegasSaveCachedDeep(hunterVegasUri);

        HunterVegasNavigateToUri(hunterVegasUri);

        await HunterVegasPushDeviceInfo();
        await HunterVegasPushAppsFlyerData();
      } else {
        HunterVegasResetHomeAfterDelay();
      }
    });
  }

  void HunterVegasBindNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onNotificationTap') {
        final Map<String, dynamic> hunterVegasPayload =
        Map<String, dynamic>.from(call.arguments);
        final String? hunterVegasUriRaw = hunterVegasPayload['uri']?.toString();

        if (hunterVegasUriRaw != null &&
            hunterVegasUriRaw.isNotEmpty &&
            !hunterVegasUriRaw.contains('Нет URI')) {
          final String hunterVegasUri = hunterVegasUriRaw;
          HunterVegasDeepLinkFromPush = hunterVegasUri;
          await HunterVegasSaveCachedDeep(hunterVegasUri);

          if (!context.mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext context) =>
                  HunterVegasTableView(hunterVegasUri),
            ),
                (Route<dynamic> route) => false,
          );

          await HunterVegasPushDeviceInfo();
          await HunterVegasPushAppsFlyerData();
        }
      }
    });
  }

  Future<void> HunterVegasPrepareDeviceProfile() async {
    try {
      await HunterVegasDeviceProfileInstance.HunterVegasInitialize();

      final FirebaseMessaging hunterVegasMessaging = FirebaseMessaging.instance;
      final NotificationSettings hunterVegasSettings =
      await hunterVegasMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      HunterVegasDeviceProfileInstance.HunterVegasPushEnabled =
          hunterVegasSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
              hunterVegasSettings.authorizationStatus ==
                  AuthorizationStatus.provisional;

      await HunterVegasLoadLoadedFlag();
      await HunterVegasLoadCachedDeep();

      HunterVegasBosunInstance = HunterVegasBosunViewModel(
        HunterVegasDeviceProfileInstance: HunterVegasDeviceProfileInstance,
        HunterVegasAnalyticsSpyInstance: HunterVegasAnalyticsSpyInstance,
      );

      HunterVegasCourier = HunterVegasCourierService(
        HunterVegasBosun: HunterVegasBosunInstance!,
        HunterVegasGetWebViewController: () => HunterVegasWebViewController,
      );
    } catch (error) {
      HunterVegasLoggerService()
          .HunterVegasLogError('prepareDeviceProfile fail: $error');
    }
  }

  void HunterVegasNavigateToUri(String link) async {
    try {
      await HunterVegasWebViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(link)),
      );
    } catch (error) {
      HunterVegasLoggerService()
          .HunterVegasLogError('navigate error: $error');
    }
  }

  void HunterVegasResetHomeAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        HunterVegasWebViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(HunterVegasHomeUrl)),
        );
      } catch (_) {}
    });
  }

  String? _resolveTokenForShip() {
    if (widget.HunterVegasSignal != null &&
        widget.HunterVegasSignal!.isNotEmpty) {
      return widget.HunterVegasSignal;
    }
    return null;
  }

  Future<void> _sendAllDataToPageTwice() async {
    await HunterVegasPushDeviceInfo();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await HunterVegasPushDeviceInfo();
      await HunterVegasPushAppsFlyerData();
    });
  }

  Future<void> HunterVegasPushDeviceInfo() async {
    final String? hunterVegasToken = _resolveTokenForShip();

    try {
      await HunterVegasCourier?.HunterVegasPutDeviceToLocalStorage(
          hunterVegasToken);
    } catch (error) {
      HunterVegasLoggerService()
          .HunterVegasLogError('pushDeviceInfo error: $error');
    }
  }

  Future<void> HunterVegasPushAppsFlyerData() async {
    final String? hunterVegasToken = _resolveTokenForShip();

    try {
      await HunterVegasCourier?.HunterVegasSendRawToPage(
        hunterVegasToken,
        deepLink: HunterVegasDeepLinkFromPush,
      );
    } catch (error) {
      HunterVegasLoggerService()
          .HunterVegasLogError('pushAppsFlyerData error: $error');
    }
  }

  void HunterVegasStartWarmProgress() {
    int hunterVegasTick = 0;
    HunterVegasWarmProgress = 0.0;

    HunterVegasWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
          if (!mounted) return;

          setState(() {
            hunterVegasTick++;
            HunterVegasWarmProgress = hunterVegasTick / (HunterVegasWarmSeconds * 10);

            if (HunterVegasWarmProgress >= 1.0) {
              HunterVegasWarmProgress = 1.0;
              HunterVegasWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      HunterVegasSleepAt = DateTime.now();
    }

    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && HunterVegasSleepAt != null) {
        final DateTime hunterVegasNow = DateTime.now();
        final Duration hunterVegasDrift =
        hunterVegasNow.difference(HunterVegasSleepAt!);

        if (hunterVegasDrift > const Duration(minutes: 25)) {
          HunterVegasReboardHarbor();
        }
      }
      HunterVegasSleepAt = null;
    }
  }

  void HunterVegasReboardHarbor() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              HunterVegasHarbor(HunterVegasSignal: widget.HunterVegasSignal),
        ),
            (Route<dynamic> route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HunterVegasWarmTimer.cancel();

    _parentInstallTimer?.cancel();
    _popupInstallTimer?.cancel();

    HunterVegasWebViewController = null;
    HunterVegasPopupWebViewController = null;

    super.dispose();
  }

  bool HunterVegasIsBareEmail(Uri uri) {
    final String hunterVegasScheme = uri.scheme;
    if (hunterVegasScheme.isNotEmpty) return false;
    final String hunterVegasRaw = uri.toString();
    return hunterVegasRaw.contains('@') && !hunterVegasRaw.contains(' ');
  }

  Uri HunterVegasToMailto(Uri uri) {
    final String hunterVegasFull = uri.toString();
    final List<String> hunterVegasParts = hunterVegasFull.split('?');
    final String hunterVegasEmail = hunterVegasParts.first;
    final Map<String, String> hunterVegasQueryParams =
    hunterVegasParts.length > 1
        ? Uri.splitQueryString(hunterVegasParts[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: hunterVegasEmail,
      queryParameters:
      hunterVegasQueryParams.isEmpty ? null : hunterVegasQueryParams,
    );
  }

  Future<bool> HunterVegasOpenMailExternal(Uri mailto) async {
    try {
      final String scheme = mailto.scheme.toLowerCase();
      final String path = mailto.path.toLowerCase();

      HunterVegasLoggerService().HunterVegasLogInfo(
          'NcupOpenMailExternal: scheme=$scheme path=$path uri=$mailto');

      if (scheme != 'mailto') {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        HunterVegasLoggerService()
            .HunterVegasLogInfo('NcupOpenMailExternal: non-mailto result=$ok');
        return ok;
      }

      final bool can = await canLaunchUrl(mailto);
      HunterVegasLoggerService()
          .HunterVegasLogInfo('NcupOpenMailExternal: canLaunchUrl(mailto) = $can');

      if (can) {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        HunterVegasLoggerService().HunterVegasLogInfo(
            'NcupOpenMailExternal: externalApplication result=$ok');
        if (ok) return true;
      }

      HunterVegasLoggerService().HunterVegasLogWarn(
          'NcupOpenMailExternal: no native handler for mailto, fallback to Gmail Web');
      final Uri gmailUri = HunterVegasGmailizeMailto(mailto);
      final bool webOk = await HunterVegasOpenWeb(gmailUri);
      HunterVegasLoggerService().HunterVegasLogInfo(
          'NcupOpenMailExternal: Gmail Web fallback result=$webOk');
      return webOk;
    } catch (e, st) {
      HunterVegasLoggerService().HunterVegasLogError(
          'NcupOpenMailExternal error: $e\n$st; url=$mailto');
      return false;
    }
  }

  Future<bool> HunterVegasOpenMailWeb(Uri mailto) async {
    final Uri hunterVegasGmailUri = HunterVegasGmailizeMailto(mailto);
    return HunterVegasOpenWeb(hunterVegasGmailUri);
  }

  Uri HunterVegasGmailizeMailto(Uri mailUri) {
    final Map<String, String> hunterVegasQueryParams = mailUri.queryParameters;

    final Map<String, String> hunterVegasParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (mailUri.path.isNotEmpty) 'to': mailUri.path,
      if ((hunterVegasQueryParams['subject'] ?? '').isNotEmpty)
        'su': hunterVegasQueryParams['subject']!,
      if ((hunterVegasQueryParams['body'] ?? '').isNotEmpty)
        'body': hunterVegasQueryParams['body']!,
      if ((hunterVegasQueryParams['cc'] ?? '').isNotEmpty)
        'cc': hunterVegasQueryParams['cc']!,
      if ((hunterVegasQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': hunterVegasQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', hunterVegasParams);
  }

  bool HunterVegasIsPlatformLink(Uri uri) {
    final String hunterVegasScheme = uri.scheme.toLowerCase();
    if (HunterVegasSpecialSchemes.contains(hunterVegasScheme)) {
      return true;
    }

    if (hunterVegasScheme == 'http' || hunterVegasScheme == 'https') {
      final String hunterVegasHost = uri.host.toLowerCase();

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

  String HunterVegasDigitsOnly(String source) =>
      source.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri HunterVegasHttpizePlatformUri(Uri uri) {
    final String hunterVegasScheme = uri.scheme.toLowerCase();

    if (hunterVegasScheme == 'tg' || hunterVegasScheme == 'telegram') {
      final Map<String, String> hunterVegasQp = uri.queryParameters;
      final String? hunterVegasDomain = hunterVegasQp['domain'];

      if (hunterVegasDomain != null && hunterVegasDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$hunterVegasDomain',
          <String, String>{
            if (hunterVegasQp['start'] != null) 'start': hunterVegasQp['start']!,
          },
        );
      }

      final String hunterVegasPath = uri.path.isNotEmpty ? uri.path : '';

      return Uri.https(
        't.me',
        '/$hunterVegasPath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if ((hunterVegasScheme == 'http' || hunterVegasScheme == 'https') &&
        uri.host.toLowerCase().endsWith('t.me')) {
      return uri;
    }

    if (hunterVegasScheme == 'viber') {
      return uri;
    }

    if (hunterVegasScheme == 'whatsapp') {
      final Map<String, String> hunterVegasQp = uri.queryParameters;
      final String? hunterVegasPhone = hunterVegasQp['phone'];
      final String? hunterVegasText = hunterVegasQp['text'];

      if (hunterVegasPhone != null && hunterVegasPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${HunterVegasDigitsOnly(hunterVegasPhone)}',
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

    if ((hunterVegasScheme == 'http' || hunterVegasScheme == 'https') &&
        (uri.host.toLowerCase().endsWith('wa.me') ||
            uri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return uri;
    }

    if (hunterVegasScheme == 'skype') {
      return uri;
    }

    if (hunterVegasScheme == 'fb-messenger') {
      final String hunterVegasPath =
      uri.pathSegments.isNotEmpty ? uri.pathSegments.join('/') : '';
      final Map<String, String> hunterVegasQp = uri.queryParameters;

      final String hunterVegasId =
          hunterVegasQp['id'] ?? hunterVegasQp['user'] ?? hunterVegasPath;

      if (hunterVegasId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$hunterVegasId',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if (hunterVegasScheme == 'sgnl') {
      final Map<String, String> hunterVegasQp = uri.queryParameters;
      final String? hunterVegasPhone = hunterVegasQp['phone'];
      final String? hunterVegasUsername = hunterVegasQp['username'];

      if (hunterVegasPhone != null && hunterVegasPhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${HunterVegasDigitsOnly(hunterVegasPhone)}',
        );
      }

      if (hunterVegasUsername != null && hunterVegasUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$hunterVegasUsername',
        );
      }

      final String hunterVegasPath = uri.pathSegments.join('/');
      if (hunterVegasPath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$hunterVegasPath',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return uri;
    }

    if (hunterVegasScheme == 'tel') {
      return Uri.parse('tel:${HunterVegasDigitsOnly(uri.path)}');
    }

    if (hunterVegasScheme == 'mailto') {
      return uri;
    }

    if (hunterVegasScheme == 'bnl') {
      final String hunterVegasNewPath = uri.path.isNotEmpty ? uri.path : '';
      return Uri.https(
        'bnl.com',
        '/$hunterVegasNewPath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    return uri;
  }

  Future<bool> HunterVegasOpenWeb(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      try {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> HunterVegasOpenExternal(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      return false;
    }
  }

  void HunterVegasHandleServerSavedata(String savedata) {
    print('onServerResponse savedata: $savedata');
if(savedata=='false'){
  Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) =>
        GameWebView(),
      ),
  );
      }

  }

  Color _parseHexColor(String hex) {
    String value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) {
      value = 'FF$value';
    }
    final intColor = int.tryParse(value, radix: 16) ?? 0xFF000000;
    return Color(intColor);
  }

  Future<void> _updateAppDataInLocalStorageFromProfile() async {
    final InAppWebViewController? controller = HunterVegasWebViewController;
    if (controller == null) return;

    final String? token = _resolveTokenForShip();
    final Map<String, dynamic> map =
    HunterVegasDeviceProfileInstance.HunterVegasToMap(fcmToken: token);

    HunterVegasLoggerService()
        .HunterVegasLogInfo('updateAppDataFromProfile: ${jsonEncode(map)}');

    await HunterVegasSaveJsonToLocalStorageAndPrefs(
      controller: controller,
      key: 'app_data',
      data: map,
    );
  }

  void _updateExtraDataFromServerPayload(Map<dynamic, dynamic> root) {
    try {
      final dynamic adataRaw = root['adata'];
      if (adataRaw is Map) {
        final Map adata = adataRaw;

        final dynamic buttonswlRaw = adata['buttonswl'];
        if (buttonswlRaw is List) {
          final List<String> list = buttonswlRaw
              .where((e) => e != null)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          setState(() {
            _buttonWhitelist = list;
          });
          HunterVegasLoggerService()
              .HunterVegasLogInfo('buttonswl updated: $_buttonWhitelist');
          _updateBackButtonVisibility();
        }

        if (adata.containsKey('fpscashier')) {
          final dynamic fpsRaw = adata['fpscashier'];
          bool? fpsValue;

          if (fpsRaw is bool) {
            fpsValue = fpsRaw;
          } else if (fpsRaw is num) {
            fpsValue = fpsRaw != 0;
          } else if (fpsRaw is String) {
            final String v = fpsRaw.toLowerCase().trim();
            if (v == 'true' || v == '1' || v == 'yes') fpsValue = true;
            if (v == 'false' || v == '0' || v == 'no') fpsValue = false;
          }

          if (fpsValue != null) {
            final bool old = HunterVegasDeviceProfileInstance.safecasher;
            HunterVegasDeviceProfileInstance.safecasher = fpsValue;
            HunterVegasLoggerService().HunterVegasLogInfo(
                'fpscashier updated from server payload: $fpsValue');

            _updateAppDataInLocalStorageFromProfile();

            if (!old && fpsValue && HunterVegasWebViewController != null) {
              HunterVegasLoggerService().HunterVegasLogInfo(
                  'fpscashier switched to true, installing JS hooks now');
              _scheduleSafeInstall(HunterVegasWebViewController!,
                  label: 'parent');
            }
          }
        }

        final dynamic savelsRaw = adata['savels'];
        if (savelsRaw is Map) {
          HunterVegasDeviceProfileInstance.HunterVegasSavels =
          Map<String, dynamic>.from(savelsRaw);
          HunterVegasLoggerService().HunterVegasLogInfo(
              'savels stored in profile: ${HunterVegasDeviceProfileInstance.HunterVegasSavels}');
          _updateAppDataInLocalStorageFromProfile();
        }
      }
    } catch (e, st) {
      HunterVegasLoggerService().HunterVegasLogError(
          'Error in _updateExtraDataFromServerPayload: $e\n$st');
    }
  }

  void _updateSafeAreaFromServerPayload(Map<dynamic, dynamic> root) {
    HunterVegasLoggerService().HunterVegasLogInfo(
        'SAFEAREA RAW PAYLOAD: ${jsonEncode(root)}');

    bool? safearea;
    String? bgLightHex;
    String? bgDarkHex;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['safearea'] != null) {
        final dynamic raw = content['safearea'];
        if (raw is bool) {
          safearea = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') safearea = true;
          if (v == 'false' || v == '0' || v == 'no') safearea = false;
        } else if (raw is num) {
          safearea = raw != 0;
        }
      }

      if (content['safearea_color'] != null &&
          content['safearea_color'].toString().trim().isNotEmpty) {
        bgLightHex = content['safearea_color'].toString().trim();
        bgDarkHex = bgLightHex;
      }
    }

    final dynamic adata = root['adata'];
    if (adata is Map) {
      if (safearea == null && adata['safearea'] != null) {
        final dynamic raw = adata['safearea'];
        if (raw is bool) {
          safearea = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') safearea = true;
          if (v == 'false' || v == '0' || v == 'no') safearea = false;
        } else if (raw is num) {
          safearea = raw != 0;
        }
      }

      if (adata['bgsareaw'] != null &&
          adata['bgsareaw'].toString().trim().isNotEmpty) {
        bgLightHex = adata['bgsareaw'].toString().trim();
      }
      if (adata['bgsareab'] != null &&
          adata['bgsareab'].toString().trim().isNotEmpty) {
        bgDarkHex = adata['bgsareab'].toString().trim();
      }
    }

    if (safearea == null && root['safearea'] != null) {
      final dynamic raw = root['safearea'];
      if (raw is bool) {
        safearea = raw;
      } else if (raw is String) {
        final String v = raw.toLowerCase().trim();
        if (v == 'true' || v == '1' || v == 'yes') safearea = true;
        if (v == 'false' || v == '0' || v == 'no') safearea = false;
      } else if (raw is num) {
        safearea = raw != 0;
      }
    }

    HunterVegasLoggerService().HunterVegasLogInfo(
        'SAFEAREA PARSED: enabled=$safearea, light=$bgLightHex, dark=$bgDarkHex');

    if (safearea == null) {
      return;
    }

    final Brightness platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    String? chosenHex;
    if (platformBrightness == Brightness.light) {
      chosenHex = bgLightHex ?? bgDarkHex;
    } else {
      chosenHex = bgDarkHex ?? bgLightHex;
    }

    final bool enabled = safearea;
    Color background =
    enabled ? const Color(0xFF1A1A22) : const Color(0xFF000000);

    if (enabled && chosenHex != null && chosenHex.isNotEmpty) {
      background = _parseHexColor(chosenHex);
    }

    setState(() {
      _safeAreaEnabled = enabled;
      _safeAreaBackgroundColor = background;
      HunterVegasDeviceProfileInstance.HunterVegasSafeAreaEnabled = enabled;
      HunterVegasDeviceProfileInstance.HunterVegasSafeAreaColor =
      enabled ? (chosenHex ?? '#1A1A22') : '';
    });

    () async {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('safearea_enabled', enabled);
        await prefs.setString(
          'safearea_color',
          HunterVegasDeviceProfileInstance.HunterVegasSafeAreaColor ?? '',
        );
        HunterVegasLoggerService().HunterVegasLogInfo(
          'SafeArea saved to prefs: enabled=$enabled, color="${HunterVegasDeviceProfileInstance.HunterVegasSafeAreaColor}"',
        );
      } catch (e, st) {
        HunterVegasLoggerService().HunterVegasLogError(
            'Error saving SafeArea to prefs: $e\n$st');
      }
    }();

    HunterVegasLoggerService().HunterVegasLogInfo(
        'SAFEAREA STATE UPDATED: enabled=$_safeAreaEnabled, color=$_safeAreaBackgroundColor (brightness=$platformBrightness)');
  }

  bool _matchesButtonWhitelist(String url) {
    if (url.isEmpty) return false;
    if (_buttonWhitelist.isEmpty) return false;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }

    final String host = uri.host.toLowerCase();
    final String full = uri.toString();

    for (final String item in _buttonWhitelist) {
      final String trimmed = item.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        if (full.startsWith(trimmed)) return true;
      } else {
        final String domain = trimmed.toLowerCase();
        if (host == domain || host.endsWith('.$domain')) return true;
      }
    }

    return false;
  }

  Future<void> _updateBackButtonVisibility() async {
    final String current = _currentUrl ?? HunterVegasCurrentUrl;
    final bool shouldShow = _matchesButtonWhitelist(current);

    if (_backButtonHiddenAfterTap) {
      _backButtonHiddenAfterTap = false;
    }

    if (shouldShow != _showBackButton) {
      if (mounted) {
        setState(() {
          _showBackButton = shouldShow;
        });
      } else {
        _showBackButton = shouldShow;
      }
    }
  }

  Future<void> _handleBackButtonPressed() async {
    if (mounted) {
      setState(() {
        _backButtonHiddenAfterTap = true;
        _showBackButton = false;
      });
    } else {
      _backButtonHiddenAfterTap = true;
      _showBackButton = false;
    }

    if (_isPopupVisible) {
      await _handlePopupBackPressed();
      return;
    }

    if (HunterVegasWebViewController == null) return;
    try {
      if (await HunterVegasWebViewController!.canGoBack()) {
        await HunterVegasWebViewController!.goBack();
      } else {
        await HunterVegasWebViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(HunterVegasHomeUrl)),
        );
      }
    } catch (e, st) {
      HunterVegasLoggerService()
          .HunterVegasLogError('Error on back button pressed: $e\n$st');
    }
  }

  InAppWebViewSettings _mainWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isInspectable: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useOnDownloadStart: true,
      javaScriptCanOpenWindowsAutomatically: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      transparentBackground: true,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowsBackForwardNavigationGestures: true,
    );
  }

  InAppWebViewSettings _popupWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isInspectable: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useOnDownloadStart: true,
      javaScriptCanOpenWindowsAutomatically: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      transparentBackground: false,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowsBackForwardNavigationGestures: true,
    );
  }

  Future<void> _safeEvaluateJavascript(
      InAppWebViewController? controller, {
        required String source,
        String debugName = 'js',
      }) async {
    if (controller == null) return;
    if (!mounted) return;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      await controller.evaluateJavascript(source: source);
    } catch (e) {
      print('WERLOG: safeEvaluateJavascript error [$debugName]: $e');
    }
  }

  Future<void> _installJsErrorLogger(InAppWebViewController controller) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installJsErrorLogger',
      source: r'''
        (function() {
          if (window.__ncupJsLoggerInstalled) return;
          window.__ncupJsLoggerInstalled = true;

          function serializeError(err) {
            try {
              if (!err) return null;
              var plain = {};
              Object.getOwnPropertyNames(err).forEach(function(key) {
                plain[key] = err[key];
              });
              return plain;
            } catch (_) {
              return { message: String(err) };
            }
          }

          window.onerror = function(message, source, lineno, colno, error) {
            try {
              var payload = {
                type: 'onerror',
                message: String(message || ''),
                source: String(source || ''),
                lineno: lineno || 0,
                colno: colno || 0,
                error: serializeError(error)
              };
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupJSLogger', payload);
              }
            } catch (e) {
              console.log('NcupJSLogger onerror inner fail', e);
            }
          };

          window.addEventListener('unhandledrejection', function(event) {
            try {
              var reason = event.reason;
              var payload = {
                type: 'unhandledrejection',
                reason: serializeError(reason) || { message: String(reason || '') }
              };
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupJSLogger', payload);
              }
            } catch (e) {
              console.log('NcupJSLogger unhandledrejection inner fail', e);
            }
          });
        })();
      ''',
    );
  }

  Future<void> _installPostMessageBridge(
      InAppWebViewController controller, {
        required String label,
      }) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installPostMessageBridge-$label',
      source: '''
        (function() {
          if (window.__ncupPostMessageBridgeInstalled_$label) return;
          window.__ncupPostMessageBridgeInstalled_$label = true;

          window.addEventListener('message', function(event) {
            try {
              var dataRaw = event.data;
              var dataString;
              try {
                dataString = JSON.stringify(dataRaw);
              } catch (e) {
                dataString = String(dataRaw);
              }

              var hasBridge = !!(window.flutter_inappwebview && window.flutter_inappwebview.callHandler);

              var payload = {
                label: '$label',
                origin: String(event.origin || ''),
                data: dataString,
                href: String(window.location.href || '')
              };

              if (hasBridge) {
                window.flutter_inappwebview.callHandler('NcupPostMessage', payload);
              }

              try {
                var parsed = dataRaw;
                if (typeof parsed === 'string') {
                  parsed = JSON.parse(parsed);
                }
                if (parsed && parsed.type === 'newTab' && parsed.url) {
                  if (hasBridge) {
                    window.flutter_inappwebview.callHandler('NcupCheckoutAction', parsed);
                  }
                }
              } catch (parseErr) {}
            } catch (e) {}
          });
        })();
      ''',
    );
  }

  Future<void> _installCheckoutInterceptor(
      InAppWebViewController controller,
      ) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installCheckoutInterceptor',
      source: r'''
        (function() {
          if (window.__ncupCheckoutInterceptorInstalled) return;
          window.__ncupCheckoutInterceptorInstalled = true;

          function sendToFlutter(data) {
            try {
              if (!data || typeof data !== 'object') return;
              if (data.type === 'newTab' && data.url) {
                console.log('[NCUP checkout interceptor] newTab:', data.url);
                if (
                  window.flutter_inappwebview &&
                  window.flutter_inappwebview.callHandler
                ) {
                  window.flutter_inappwebview.callHandler(
                    'NcupCheckoutAction',
                    data
                  );
                }
              }
            } catch (e) {
              console.log('[NCUP checkout interceptor] send error', e);
            }
          }

          function tryParseMaybeJson(value) {
            try {
              if (!value) return null;
              if (typeof value === 'object') {
                return value;
              }
              if (typeof value === 'string') {
                return JSON.parse(value);
              }
              return null;
            } catch (e) {
              return null;
            }
          }

          function tryHandlePayload(payload) {
            try {
              var data = tryParseMaybeJson(payload);
              if (!data) return;

              if (Array.isArray(data)) {
                data.forEach(function(item) {
                  if (item && item.type === 'newTab' && item.url) {
                    sendToFlutter(item);
                  }
                });
                return;
              }

              if (data.type === 'newTab' && data.url) {
                sendToFlutter(data);
                return;
              }

              if (data.savedata) {
                var saved = tryParseMaybeJson(data.savedata);
                if (saved && saved.type === 'newTab' && saved.url) {
                  sendToFlutter(saved);
                  return;
                }
              }

              if (data.data) {
                var nested = tryParseMaybeJson(data.data);
                if (nested && nested.type === 'newTab' && nested.url) {
                  sendToFlutter(nested);
                  return;
                }
              }

              if (data.content) {
                var content = tryParseMaybeJson(data.content);
                if (content && content.type === 'newTab' && content.url) {
                  sendToFlutter(content);
                  return;
                }
              }
            } catch (e) {
              console.log('[NCUP checkout interceptor] handle error', e);
            }
          }

          var originalFetch = window.fetch;
          if (originalFetch) {
            window.fetch = function() {
              return originalFetch.apply(this, arguments).then(function(response) {
                try {
                  var cloned = response.clone();
                  cloned.text().then(function(text) {
                    tryHandlePayload(text);
                  }).catch(function() {});
                } catch (e) {}
                return response;
              });
            };
          }

          var OriginalXHR = window.XMLHttpRequest;
          if (OriginalXHR) {
            window.XMLHttpRequest = function() {
              var xhr = new OriginalXHR();
              var originalOpen = xhr.open;
              var originalSend = xhr.send;

              xhr.open = function() {
                return originalOpen.apply(xhr, arguments);
              };

              xhr.send = function() {
                xhr.addEventListener('load', function() {
                  try {
                    tryHandlePayload(xhr.responseText);
                  } catch (e) {}
                });
                return originalSend.apply(xhr, arguments);
              };

              return xhr;
            };
          }

          var originalOpen = window.open;
          window.open = function(url, target, features) {
            try {
              console.log('[NCUP window.open intercepted]', url, target, features);
            } catch (e) {}

            if (originalOpen) {
              return originalOpen.apply(window, arguments);
            }
            return null;
          };
        })();
      ''',
    );
  }

  Future<void> _installLocalStorageHook(
      InAppWebViewController controller) async {
    await _safeEvaluateJavascript(
      controller,
      debugName: 'installLocalStorageHook',
      source: r'''
        (function() {
          if (window.__ncupLocalStorageHookInstalled) return;
          window.__ncupLocalStorageHookInstalled = true;

          try {
            var originalSetItem = window.localStorage.setItem;
            window.localStorage.setItem = function(key, value) {
              try {
                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                  window.flutter_inappwebview.callHandler('NcupLocalStorageSetItem', {
                    key: String(key),
                    value: String(value)
                  });
                }
              } catch (e) {
                console.log('Ncup localStorage hook error', e);
              }
              return originalSetItem.apply(this, arguments);
            };
          } catch (e) {
            console.log('Ncup localStorage hook init error', e);
          }
        })();
      ''',
    );
  }

  Future<void> _safeInstallAll(
      InAppWebViewController? controller, {
        required String label,
      }) async {
    if (controller == null) return;
    if (!mounted) return;
    if (!HunterVegasDeviceProfileInstance.safecasher) {
      print('WERLOG: safeInstallAll skipped ($label) because fpscashier=false');
      return;
    }

    try {
      await _installJsErrorLogger(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installPostMessageBridge(controller, label: label);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installCheckoutInterceptor(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _installLocalStorageHook(controller);
    } catch (e) {
      print('WERLOG: safeInstallAll error label=$label error=$e');
    }
  }

  void _scheduleSafeInstall(
      InAppWebViewController controller, {
        required String label,
      }) {
    if (label == 'popup') {
      _popupInstallTimer?.cancel();
      _popupInstallTimer =
          Timer(const Duration(milliseconds: 450), () async {
            if (!mounted) return;
            await _safeInstallAll(controller, label: label);
          });
    } else {
      _parentInstallTimer?.cancel();
      _parentInstallTimer =
          Timer(const Duration(milliseconds: 250), () async {
            if (!mounted) return;
            await _safeInstallAll(controller, label: label);
          });
    }
  }

  Map<String, dynamic>? _tryDecodeMap(dynamic value) {
    try {
      if (value == null) return null;
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      if (value is String) {
        final String trimmed = value.trim();
        if (trimmed.isEmpty) return null;
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _openExternalForJsonNewTab(Uri uri) async {
    if (_isAboutBlankUri(uri)) return false;

    final String url = uri.toString();

    if (_handledNewTabUrls.contains(url)) {
      print('WERLOG: duplicate JSON newTab ignored url=$url');
      return true;
    }

    _handledNewTabUrls.add(url);

    if (_isOpeningExternalNewTab) {
      print('WERLOG: external newTab already opening, ignored url=$url');
      return false;
    }

    _isOpeningExternalNewTab = true;

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      print('WERLOG: JSON newTab external launched=$launched url=$url');
      return launched;
    } catch (e) {
      print('WERLOG: JSON newTab external error=$e url=$url');
      return false;
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _isOpeningExternalNewTab = false;
      });
    }
  }

  Future<bool> _handleCheckoutAction(dynamic rawPayload) async {
    try {
      Map<String, dynamic>? data = _tryDecodeMap(rawPayload);
      if (data == null) return false;

      if (data.containsKey('savedata')) {
        final Map<String, dynamic>? savedataMap =
        _tryDecodeMap(data['savedata']);
        if (savedataMap != null) {
          data = savedataMap;
        }
      }

      if (data.containsKey('data')) {
        final Map<String, dynamic>? dataMap = _tryDecodeMap(data['data']);
        if (dataMap != null &&
            dataMap['type']?.toString() == 'newTab' &&
            (dataMap['url']?.toString() ?? '').isNotEmpty) {
          data = dataMap;
        }
      }

      if (data.containsKey('content')) {
        final Map<String, dynamic>? contentMap =
        _tryDecodeMap(data['content']);
        if (contentMap != null &&
            contentMap['type']?.toString() == 'newTab' &&
            (contentMap['url']?.toString() ?? '').isNotEmpty) {
          data = contentMap;
        }
      }

      final String type = data['type']?.toString() ?? '';
      final String url = data['url']?.toString() ?? '';

      if (type == 'newTab' && url.isNotEmpty) {
        final Uri? uri = Uri.tryParse(url);
        if (uri == null || _isAboutBlankUri(uri)) {
          print('WERLOG: invalid JSON newTab uri=$url');
          return false;
        }

        // === OneLink: НЕ открываем во внешнем браузере ===
        if (HunterVegasIsOneLinkUrl(uri)) {
          HunterVegasLoggerService().HunterVegasLogInfo(
              'OneLink newTab detected, loading in WebView: $url');
          HunterVegasNavigateToUri(url);
          return true;
        }

        print('WERLOG: handle JSON newTab url=$url');
        await _openExternalForJsonNewTab(uri);
        return true;
      }

      return false;
    } catch (e) {
      print('WERLOG: handleCheckoutAction error: $e');
      return false;
    }
  }

  Future<bool> _onCreateWindowHandler(
      InAppWebViewController controller,
      CreateWindowAction request,
      ) async {
    final Uri? hunterVegasUri = request.request.url;
    final String urlString = hunterVegasUri?.toString() ?? '';

    print(
      'WERLOG: MAIN onCreateWindow '
          'windowId=${request.windowId} '
          'url=$urlString '
          'isDialog=${request.isDialog} '
          'hasGesture=${request.hasGesture}',
    );

    if (hunterVegasUri != null) {
      _currentUrl = hunterVegasUri.toString();
      await _updateBackButtonVisibility();

      // === OneLink: загружаем внутри WebView, не открываем внешний браузер ===
      if (HunterVegasIsOneLinkUrl(hunterVegasUri)) {
        HunterVegasLoggerService().HunterVegasLogInfo(
            'OneLink onCreateWindow: loading in main WebView: $hunterVegasUri');
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(hunterVegasUri.toString())),
        );
        return false;
      }

      if (_isGoogleUrl(hunterVegasUri)) {}

      if (HunterVegasIsBankScheme(hunterVegasUri) ||
          ((hunterVegasUri.scheme == 'http' ||
              hunterVegasUri.scheme == 'https') &&
              HunterVegasIsBankDomain(hunterVegasUri))) {
        await HunterVegasOpenBank(hunterVegasUri);
        return false;
      }

      if (HunterVegasIsBareEmail(hunterVegasUri)) {
        final Uri hunterVegasMailto = HunterVegasToMailto(hunterVegasUri);
        await HunterVegasOpenMailExternal(hunterVegasMailto);
        return false;
      }

      final String hunterVegasScheme = hunterVegasUri.scheme.toLowerCase();

      if (hunterVegasScheme == 'mailto') {
        await HunterVegasOpenMailExternal(hunterVegasUri);
        return false;
      }

      if (hunterVegasScheme == 'tel') {
        await launchUrl(hunterVegasUri,
            mode: LaunchMode.externalApplication);
        return false;
      }

      final String host = hunterVegasUri.host.toLowerCase();
      final bool hunterVegasIsSocial = host.endsWith('facebook.com') ||
          host.endsWith('instagram.com') ||
          host.endsWith('twitter.com') ||
          host.endsWith('x.com');

      if (hunterVegasIsSocial) {
        await HunterVegasOpenExternal(hunterVegasUri);
        return false;
      }

      if (HunterVegasIsPlatformLink(hunterVegasUri)) {
        final Uri hunterVegasWebUri =
        HunterVegasHttpizePlatformUri(hunterVegasUri);
        await HunterVegasOpenExternal(hunterVegasWebUri);
        return false;
      }
    }

    if (!mounted) return false;

    setState(() {
      _popupCreateAction = request;
      _popupUrl = urlString.isNotEmpty && !_isAboutBlankUrl(urlString)
          ? urlString
          : null;
      _popupCurrentUrl = _popupUrl;
      _isPopupVisible = true;
      _popupCanGoBack = false;
    });

    return true;
  }

  Future<bool> _onPopupCreateWindowHandler(
      InAppWebViewController controller,
      CreateWindowAction createWindowAction,
      ) async {
    final Uri? uri = createWindowAction.request.url;
    final String urlString = uri?.toString() ?? '';

    print(
      'WERLOG: POPUP onCreateWindow '
          'windowId=${createWindowAction.windowId} '
          'url=$urlString',
    );

    // === OneLink в popup: загружаем в popup WebView ===
    if (uri != null && HunterVegasIsOneLinkUrl(uri)) {
      HunterVegasLoggerService().HunterVegasLogInfo(
          'OneLink popup onCreateWindow: loading in popup WebView: $uri');
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
      return false;
    }

    if (!mounted) return false;

    if (createWindowAction.windowId != null) {
      setState(() {
        _popupCreateAction = createWindowAction;
        _popupUrl = urlString.isNotEmpty && !_isAboutBlankUrl(urlString)
            ? urlString
            : _popupUrl;
        _popupCurrentUrl = _popupUrl;
        _isPopupVisible = true;
      });
      return true;
    }

    if (urlString.isNotEmpty && !_isAboutBlankUrl(urlString)) {
      try {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(urlString)),
        );
      } catch (e) {
        print('WERLOG: popup inner window.open load error: $e url=$urlString');
      }
    }

    return false;
  }

  void _closePopup() {
    setState(() {
      _isPopupVisible = false;
      _popupUrl = null;
      _popupCurrentUrl = null;
      _popupCreateAction = null;
      _popupCanGoBack = false;
      HunterVegasPopupWebViewController = null;
    });
  }

  Future<void> _closePopupAndNotifyParent({
    String reason = 'closed_by_user',
  }) async {
    try {
      await HunterVegasWebViewController?.evaluateJavascript(
        source: '''
          try {
            window.dispatchEvent(new MessageEvent('message', {
              data: ${jsonEncode({
          'type': 'ncup_popup_closed',
          'reason': reason,
        })},
              origin: window.location.origin
            }));
          } catch(e) {
            console.log('ncup popup close notify failed', e);
          }
        ''',
      );
    } catch (e) {
      print('WERLOG: closePopup notify parent error: $e');
    }
    _closePopup();
  }

  Future<void> _refreshPopupCanGoBack() async {
    final InAppWebViewController? c = HunterVegasPopupWebViewController;
    if (c == null) {
      if (_popupCanGoBack && mounted) {
        setState(() {
          _popupCanGoBack = false;
        });
      }
      return;
    }
    try {
      final bool can = await c.canGoBack();
      if (!mounted) return;
      if (can != _popupCanGoBack) {
        setState(() {
          _popupCanGoBack = can;
        });
      }
    } catch (e) {
      print('WERLOG: _refreshPopupCanGoBack error: $e');
    }
  }

  Future<void> _handlePopupBackPressed() async {
    final InAppWebViewController? c = HunterVegasPopupWebViewController;
    if (c == null) {
      _closePopup();
      return;
    }
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          _refreshPopupCanGoBack();
        });
      } else {
        await _closePopupAndNotifyParent(reason: 'popup_back_no_history');
      }
    } catch (e) {
      print('WERLOG: _handlePopupBackPressed error: $e');
      _closePopup();
    }
  }

  bool _isCurrentPopupInWhitelist() {
    if (!_isPopupVisible) return false;
    final String popupUrlForCheck = _popupCurrentUrl ?? _popupUrl ?? '';
    return _matchesButtonWhitelist(popupUrlForCheck);
  }

  Widget _buildPopupWebView() {
    final bool popupInWhitelist = _isCurrentPopupInWhitelist();

    final bool showBackArrow = !popupInWhitelist && _popupCanGoBack;
    final bool showCloseButton = !popupInWhitelist && !_popupCanGoBack;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.96),
        child: Column(
          children: [
            if (!popupInWhitelist) ...[
              SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black,
                  child: Row(
                    children: [
                      if (showBackArrow)
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: _handlePopupBackPressed,
                        )
                      else if (showCloseButton)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            _closePopupAndNotifyParent(reason: 'close_button');
                          },
                        ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
            ],
            Expanded(
              child: InAppWebView(
                windowId: _popupCreateAction?.windowId,
                initialUrlRequest:
                (_popupCreateAction?.windowId == null) && _popupUrl != null
                    ? URLRequest(url: WebUri(_popupUrl!))
                    : null,
                initialSettings: _popupWebViewSettings(),
                onWebViewCreated:
                    (InAppWebViewController popupController) async {
                  HunterVegasPopupWebViewController = popupController;

                  print(
                    'WERLOG: popup created '
                        'windowId=${_popupCreateAction?.windowId} '
                        'initialUrl=${_popupUrl ?? _popupCreateAction?.request.url}',
                  );

                  final String popupInitUrl =
                      _popupUrl ??
                          _popupCreateAction?.request.url?.toString() ??
                          '';
                  if (popupInitUrl.isNotEmpty) {
                    final Uri? popupUri = Uri.tryParse(popupInitUrl);
                    if (popupUri != null && _isGoogleUrl(popupUri)) {
                      await _applyGoogleUserAgentForPopup();
                    }
                  }

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupLocalStorageSetItem',
                    callback: (List<dynamic> args) async {
                      try {
                        if (args.isEmpty) return null;
                        final dynamic raw = args.first;
                        if (raw is Map) {
                          final String key =
                              raw['key']?.toString() ?? '';
                          final String value =
                              raw['value']?.toString() ?? '';
                          if (key.isNotEmpty) {
                            final SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                            await prefs.setString(key, value);
                            HunterVegasLoggerService().HunterVegasLogInfo(
                                'NcupLocalStorageSetItem (popup): saved key="$key" len=${value.length}');
                          }
                        }
                      } catch (e, st) {
                        HunterVegasLoggerService().HunterVegasLogError(
                            'NcupLocalStorageSetItem popup handler error: $e\n$st');
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupCheckoutAction',
                    callback: (List<dynamic> args) async {
                      print('WERLOG: POPUP NcupCheckoutAction args=$args');
                      if (args.isNotEmpty) {
                        await _handleCheckoutAction(args.first);
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupPostMessage',
                    callback: (List<dynamic> args) async {
                      try {
                        if (args.isEmpty) return null;
                        final dynamic first = args.first;
                        final dynamic dataToHandle =
                        (first is Map && first['data'] != null)
                            ? first['data']
                            : first;
                        await _handleCheckoutAction(dataToHandle);
                      } catch (e) {
                        print('WERLOG: POPUP NcupPostMessage handler error: $e');
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupJSLogger',
                    callback: (List<dynamic> args) {
                      print('WERLOG: POPUP JS error payload: $args');
                      return null;
                    },
                  );
                },
                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                onLoadStart: (controller, uri) async {
                  print('WERLOG: popup onLoadStart url=$uri');
                  if (uri != null && !_isAboutBlankUri(uri)) {
                    if (_isGoogleUrl(uri)) {
                      await _applyGoogleUserAgentForPopup();
                    }

                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = uri.toString();
                        if (_backButtonHiddenAfterTap) {
                          _backButtonHiddenAfterTap = false;
                        }
                      });
                    }
                  }
                  _refreshPopupCanGoBack();
                },
                onLoadStop: (controller, uri) async {
                  print('WERLOG: popup onLoadStop url=$uri');
                  if (uri != null && !_isAboutBlankUri(uri)) {
                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = uri.toString();
                      });
                    }
                  }
                  if (!_isAboutBlankUri(uri)) {
                    _scheduleSafeInstall(controller, label: 'popup');
                  }
                  _refreshPopupCanGoBack();
                },
                onUpdateVisitedHistory: (controller, url, isReload) async {
                  if (url != null && !_isAboutBlankUri(url)) {
                    if (mounted) {
                      setState(() {
                        _popupCurrentUrl = url.toString();
                        if (_backButtonHiddenAfterTap) {
                          _backButtonHiddenAfterTap = false;
                        }
                      });
                    }
                  }
                  _refreshPopupCanGoBack();
                },
                onCreateWindow: _onPopupCreateWindowHandler,
                shouldOverrideUrlLoading: (
                    InAppWebViewController controller,
                    NavigationAction navigationAction,
                    ) async {
                  final Uri? uri = navigationAction.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (_isAboutBlankUri(uri)) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  // === OneLink: разрешаем навигацию внутри popup ===
                  if (HunterVegasIsOneLinkUrl(uri)) {
                    HunterVegasLoggerService().HunterVegasLogInfo(
                        'OneLink popup shouldOverride: ALLOW in popup: $uri');
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (_isGoogleUrl(uri)) {
                    await _applyGoogleUserAgentForPopup();
                    return NavigationActionPolicy.ALLOW;
                  }

                  final String scheme = uri.scheme.toLowerCase();

                  if (HunterVegasIsBareEmail(uri)) {
                    final Uri mailto = HunterVegasToMailto(uri);
                    await HunterVegasOpenMailExternal(mailto);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'mailto') {
                    await HunterVegasOpenMailExternal(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'tel') {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (HunterVegasIsBankScheme(uri) ||
                      ((scheme == 'http' || scheme == 'https') &&
                          HunterVegasIsBankDomain(uri))) {
                    await HunterVegasOpenBank(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme != 'http' && scheme != 'https') {
                    print(
                      'WERLOG: popup non-http/https scheme=$scheme url=$uri, trying external app',
                    );
                    await HunterVegasTryOpenUnknownSchemeExternally(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onCloseWindow: (controller) {
                  print('WERLOG: popup onCloseWindow');
                  _closePopup();
                },
                onLoadError: (controller, uri, code, message) async {
                  print(
                    'WERLOG: popup onLoadError url=$uri code=$code msg=$message',
                  );
                },
                onReceivedError: (controller, request, error) async {
                  print(
                    'WERLOG: popup onReceivedError '
                        'url=${request.url} '
                        'type=${error.type} '
                        'desc=${error.description}',
                  );
                },
                onReceivedHttpError:
                    (controller, request, errorResponse) async {
                  print(
                    'WERLOG: popup onReceivedHttpError '
                        'url=${request.url} '
                        'status=${errorResponse.statusCode} '
                        'reason=${errorResponse.reasonPhrase}',
                  );
                },
                onConsoleMessage: (controller, consoleMessage) {
                  print(
                    'WERLOG: popup console: '
                        '${consoleMessage.messageLevel} ${consoleMessage.message}',
                  );
                },
                onDownloadStartRequest: (controller, req) async {
                  print(
                      'WERLOG: popup download for url=${req.url}, opening external');
                  await HunterVegasOpenExternal(req.url);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    HunterVegasBindNotificationTap();

    final Color bgColor =
    _safeAreaEnabled ? _safeAreaBackgroundColor : Colors.black;

    final Widget webView = Stack(
      children: <Widget>[
        if (HunterVegasCoverVisible)
          const Center(child: AppLoader())
        else
          Container(
            color: bgColor,
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  key: ValueKey<int>(HunterVegasWebViewKeyCounter),
                  initialSettings: _mainWebViewSettings(),
                  initialUrlRequest: URLRequest(
                    url: WebUri(HunterVegasHomeUrl),
                  ),
                  onWebViewCreated:
                      (InAppWebViewController controller) async {
                    HunterVegasWebViewController = controller;
                    _currentUrl = HunterVegasHomeUrl;

                    HunterVegasBosunInstance ??= HunterVegasBosunViewModel(
                      HunterVegasDeviceProfileInstance:
                      HunterVegasDeviceProfileInstance,
                      HunterVegasAnalyticsSpyInstance:
                      HunterVegasAnalyticsSpyInstance,
                    );

                    HunterVegasCourier ??= HunterVegasCourierService(
                      HunterVegasBosun: HunterVegasBosunInstance!,
                      HunterVegasGetWebViewController: () =>
                      HunterVegasWebViewController,
                    );

                    try {
                      final ua = await controller.evaluateJavascript(
                        source: "navigator.userAgent",
                      );
                      if (ua is String && ua.trim().isNotEmpty) {
                        _baseUserAgent = ua.trim();
                        _currentUserAgent = _baseUserAgent!;
                        HunterVegasDeviceProfileInstance
                            .HunterVegasBaseUserAgent = _baseUserAgent;
                        HunterVegasLoggerService().HunterVegasLogInfo(
                            'Initial WebView User-Agent: $_baseUserAgent');
                        print(
                            '[UA] INITIAL WEBVIEW USER AGENT: $_baseUserAgent');
                      }
                    } catch (e) {
                      HunterVegasLoggerService().HunterVegasLogWarn(
                          'Failed to read navigator.userAgent on create: $e');
                    }

                    await _applyNormalUserAgentIfNeeded();

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupLocalStorageSetItem',
                      callback: (List<dynamic> args) async {
                        try {
                          if (args.isEmpty) return null;
                          final dynamic raw = args.first;
                          if (raw is Map) {
                            final String key =
                                raw['key']?.toString() ?? '';
                            final String value =
                                raw['value']?.toString() ?? '';
                            if (key.isNotEmpty) {
                              final SharedPreferences prefs =
                              await SharedPreferences.getInstance();
                              await prefs.setString(key, value);
                              HunterVegasLoggerService().HunterVegasLogInfo(
                                  'NcupLocalStorageSetItem (main): saved key="$key" len=${value.length}');
                            }
                          }
                        } catch (e, st) {
                          HunterVegasLoggerService().HunterVegasLogError(
                              'NcupLocalStorageSetItem main handler error: $e\n$st');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'onServerResponse',
                      callback: (List<dynamic> args) async {
                        if (args.isEmpty) return null;

                        print("Get Data server $args");

                        try {
                          dynamic first = args[0];

                          if (first is List && first.isNotEmpty) {
                            first = first.first;
                          }

                          final bool handled =
                          await _handleCheckoutAction(first);
                          if (handled) {}

                          if (first is Map) {
                            final Map<dynamic, dynamic> root = first;

                            if (root['savedata'] != null) {
                              HunterVegasHandleServerSavedata(
                                  root['savedata'].toString());
                              await _handleCheckoutAction(root['savedata']);
                            }

                            _updateExtraDataFromServerPayload(root);
                            _updateSafeAreaFromServerPayload(root);
                            await _updateUserAgentFromServerPayload(root);

                            await _applyNormalUserAgentIfNeeded();

                            try {
                              if (!_loadedJsExecutedOnce) {
                                final dynamic adataRaw = root['adata'];
                                if (adataRaw is Map) {
                                  final Map adata = adataRaw;
                                  final dynamic loadedJsRaw =
                                  adata['loadedjs'];
                                  if (loadedJsRaw != null) {
                                    final String loadedJs =
                                    loadedJsRaw.toString().trim();
                                    if (loadedJs.isNotEmpty) {
                                      _pendingLoadedJs = loadedJs;
                                      HunterVegasLoggerService()
                                          .HunterVegasLogInfo(
                                        'loadedjs received, will execute ONCE after 6 seconds',
                                      );

                                      Future<void>.delayed(
                                        const Duration(seconds: 6),
                                            () async {
                                          if (!mounted) return;
                                          if (_loadedJsExecutedOnce) {
                                            HunterVegasLoggerService()
                                                .HunterVegasLogInfo(
                                                'Skipping loadedjs: already executed once');
                                            return;
                                          }
                                          if (HunterVegasWebViewController ==
                                              null) {
                                            HunterVegasLoggerService()
                                                .HunterVegasLogWarn(
                                                'Skipping loadedjs execution: controller is null');
                                            return;
                                          }
                                          final String? jsToRun =
                                              _pendingLoadedJs;
                                          if (jsToRun == null ||
                                              jsToRun.isEmpty) {
                                            return;
                                          }
                                          HunterVegasLoggerService()
                                              .HunterVegasLogInfo(
                                              'Executing loadedjs from server payload (ONCE, delayed 6s)');
                                          try {
                                            await HunterVegasWebViewController
                                                ?.evaluateJavascript(
                                              source: jsToRun,
                                            );
                                            _loadedJsExecutedOnce = true;
                                          } catch (e, st) {
                                            HunterVegasLoggerService()
                                                .HunterVegasLogError(
                                                'Error executing delayed loadedjs: $e\n$st');
                                          }
                                        },
                                      );
                                    }
                                  }
                                }
                              } else {
                                HunterVegasLoggerService().HunterVegasLogInfo(
                                    'loadedjs ignored: already executed once earlier');
                              }
                            } catch (e, st) {
                              HunterVegasLoggerService().HunterVegasLogError(
                                  'Error scheduling loadedjs: $e\n$st');
                            }
                          }
                        } catch (e, st) {
                          print('onServerResponse error: $e\n$st');
                        }

                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupCheckoutAction',
                      callback: (List<dynamic> args) async {
                        try {
                          print('WERLOG: MAIN NcupCheckoutAction args=$args');
                          if (args.isNotEmpty) {
                            await _handleCheckoutAction(args.first);
                          }
                        } catch (e) {
                          print(
                              'WERLOG: MAIN NcupCheckoutAction error: $e');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupJSLogger',
                      callback: (List<dynamic> args) {
                        try {
                          final dynamic payload =
                          args.isNotEmpty ? args.first : null;
                          print('WERLOG: MAIN JS error payload: $payload');
                        } catch (e) {
                          print('WERLOG: NcupJSLogger handler error: $e');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupPostMessage',
                      callback: (List<dynamic> args) async {
                        try {
                          if (args.isEmpty) return null;
                          final dynamic first = args.first;
                          final dynamic dataToHandle =
                          (first is Map && first['data'] != null)
                              ? first['data']
                              : first;
                          await _handleCheckoutAction(dataToHandle);
                        } catch (e) {
                          print(
                              'WERLOG: MAIN NcupPostMessage handler error: $e');
                        }
                        return null;
                      },
                    );
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                  onLoadStart:
                      (InAppWebViewController controller, Uri? uri) async {
                    setState(() {
                      HunterVegasStartLoadTimestamp =
                          DateTime.now().millisecondsSinceEpoch;
                    });

                    final Uri? hunterVegasViewUri = uri;
                    if (hunterVegasViewUri != null) {
                      _currentUrl = hunterVegasViewUri.toString();

                      await _switchUserAgentForUrl(hunterVegasViewUri);

                      await _updateBackButtonVisibility();

                      if (HunterVegasIsBareEmail(hunterVegasViewUri)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        final Uri hunterVegasMailto =
                        HunterVegasToMailto(hunterVegasViewUri);
                        await HunterVegasOpenMailExternal(hunterVegasMailto);
                        return;
                      }

                      final String hunterVegasScheme =
                      hunterVegasViewUri.scheme.toLowerCase();

                      if (hunterVegasScheme == 'mailto') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await HunterVegasOpenMailExternal(hunterVegasViewUri);
                        return;
                      }

                      if (HunterVegasIsBankScheme(hunterVegasViewUri)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await HunterVegasOpenBank(hunterVegasViewUri);
                        return;
                      }

                      if (hunterVegasScheme != 'http' &&
                          hunterVegasScheme != 'https') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await HunterVegasTryOpenUnknownSchemeExternally(
                            hunterVegasViewUri);
                      }
                    }
                  },
                  onLoadError: (
                      InAppWebViewController controller,
                      Uri? uri,
                      int code,
                      String message,
                      ) async {
                    if (HunterVegasIsCancelledLoadError(description: message)) {
                      print(
                          'WERLOG: ignoring cancelled load (code=$code, url=$uri)');
                      return;
                    }

                    final int hunterVegasNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String hunterVegasEvent =
                        'InAppWebViewError(code=$code, message=$message)';

                    await HunterVegasPostStat(
                      event: hunterVegasEvent,
                      timeStart: hunterVegasNow,
                      timeFinish: hunterVegasNow,
                      url: uri?.toString() ?? '',
                      appSid:
                      HunterVegasAnalyticsSpyInstance.HunterVegasAppsFlyerUid,
                      firstPageLoadTs: HunterVegasFirstPageTimestamp,
                    );
                  },
                  onReceivedError: (
                      InAppWebViewController controller,
                      WebResourceRequest request,
                      WebResourceError error,
                      ) async {
                    final String hunterVegasDescription =
                    (error.description ?? '').toString();

                    if (HunterVegasIsCancelledLoadError(
                        description: hunterVegasDescription,
                        type: error.type)) {
                      print(
                          'WERLOG: ignoring cancelled load (type=${error.type}, url=${request.url})');
                      return;
                    }

                    final int hunterVegasNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String hunterVegasEvent =
                        'WebResourceError(code=$error, message=$hunterVegasDescription)';

                    await HunterVegasPostStat(
                      event: hunterVegasEvent,
                      timeStart: hunterVegasNow,
                      timeFinish: hunterVegasNow,
                      url: request.url?.toString() ?? '',
                      appSid:
                      HunterVegasAnalyticsSpyInstance.HunterVegasAppsFlyerUid,
                      firstPageLoadTs: HunterVegasFirstPageTimestamp,
                    );
                  },
                  onLoadStop:
                      (InAppWebViewController controller, Uri? uri) async {
                    setState(() {
                      HunterVegasCurrentUrl = uri.toString();
                      _currentUrl = HunterVegasCurrentUrl;
                    });

                    if (uri != null) {
                      await _switchUserAgentForUrl(uri);
                    }

                    if (!_isAboutBlankUri(uri)) {
                      _scheduleSafeInstall(controller, label: 'parent');
                    }

                    await debugPrintCurrentUserAgent();

                    await _sendAllDataToPageTwice();
                    await _updateBackButtonVisibility();

                    Future<void>.delayed(
                      const Duration(seconds: 20),
                          () {
                        HunterVegasSendLoadedOnce(
                          url: HunterVegasCurrentUrl.toString(),
                          timestart: HunterVegasStartLoadTimestamp,
                        );
                      },
                    );
                  },
                  onUpdateVisitedHistory:
                      (controller, url, isReload) async {
                    if (url != null && !_isAboutBlankUri(url)) {
                      _currentUrl = url.toString();
                      await _updateBackButtonVisibility();
                      await _switchUserAgentForUrl(url);
                    }
                  },
                  shouldOverrideUrlLoading:
                      (InAppWebViewController controller,
                      NavigationAction action) async {
                    final Uri? hunterVegasUri = action.request.url;
                    if (hunterVegasUri == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    _currentUrl = hunterVegasUri.toString();
                    await _updateBackButtonVisibility();

                    if (_isAboutBlankUri(hunterVegasUri)) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    // === OneLink: ВСЕГДА разрешаем навигацию внутри WebView ===
                    if (HunterVegasIsOneLinkUrl(hunterVegasUri)) {
                      HunterVegasLoggerService().HunterVegasLogInfo(
                          'OneLink shouldOverride: ALLOW in WebView: $hunterVegasUri');
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (_isGoogleUrl(hunterVegasUri)) {
                      _isCurrentlyOnGoogle = true;
                      await _applyGoogleUserAgent();
                      return NavigationActionPolicy.ALLOW;
                    } else {
                      if (_isCurrentlyOnGoogle) {
                        _isCurrentlyOnGoogle = false;
                      }
                      await _applyNormalUserAgentIfNeeded();
                    }

                    if (HunterVegasIsBareEmail(hunterVegasUri)) {
                      final Uri hunterVegasMailto =
                      HunterVegasToMailto(hunterVegasUri);
                      await HunterVegasOpenMailExternal(hunterVegasMailto);
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String hunterVegasScheme =
                    hunterVegasUri.scheme.toLowerCase();

                    if (hunterVegasScheme == 'mailto') {
                      await HunterVegasOpenMailExternal(hunterVegasUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (HunterVegasIsBankScheme(hunterVegasUri)) {
                      await HunterVegasOpenBank(hunterVegasUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if ((hunterVegasScheme == 'http' ||
                        hunterVegasScheme == 'https') &&
                        HunterVegasIsBankDomain(hunterVegasUri)) {
                      await HunterVegasOpenBank(hunterVegasUri);

                      if (_isAdobeRedirect(hunterVegasUri)) {
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AdobeRedirectScreen(uri: hunterVegasUri),
                            ),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (hunterVegasScheme == 'tel') {
                      await launchUrl(
                        hunterVegasUri,
                        mode: LaunchMode.externalApplication,
                      );
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String host = hunterVegasUri.host.toLowerCase();
                    final bool hunterVegasIsSocial =
                        host.endsWith('facebook.com') ||
                            host.endsWith('instagram.com') ||
                            host.endsWith('twitter.com') ||
                            host.endsWith('x.com');

                    if (hunterVegasIsSocial) {
                      await HunterVegasOpenExternal(hunterVegasUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (HunterVegasIsPlatformLink(hunterVegasUri)) {
                      final Uri hunterVegasWebUri =
                      HunterVegasHttpizePlatformUri(hunterVegasUri);
                      await HunterVegasOpenExternal(hunterVegasWebUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (hunterVegasScheme != 'http' &&
                        hunterVegasScheme != 'https') {
                      await HunterVegasTryOpenUnknownSchemeExternally(
                          hunterVegasUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: _onCreateWindowHandler,
                  onCloseWindow: (controller) {
                    print('WERLOG: MAIN onCloseWindow');
                  },
                  onDownloadStartRequest: (
                      InAppWebViewController controller,
                      DownloadStartRequest req,
                      ) async {
                    await HunterVegasOpenExternal(req.url);
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    print(
                      'WERLOG: MAIN console: '
                          '${consoleMessage.messageLevel} ${consoleMessage.message}',
                    );
                  },
                ),
                Visibility(
                  visible: !HunterVegasVeilVisible,
                  child: const Center(child: AppLoader()),
                ),
                if (_isPopupVisible &&
                    (_popupUrl != null || _popupCreateAction != null))
                  _buildPopupWebView(),
              ],
            ),
          ),
      ],
    );

    final bool popupInWhitelist = _isCurrentPopupInWhitelist();

    final bool whitelistMatch =
        (!_isPopupVisible && _showBackButton) || popupInWhitelist;

    final bool shouldShowTopBackBar =
        whitelistMatch && !_backButtonHiddenAfterTap;

    final Color topBarColor =
    _safeAreaEnabled ? _safeAreaBackgroundColor : Colors.black;

    final Widget topBackBar = shouldShowTopBackBar
        ? Container(
      color: topBarColor,
      padding: const EdgeInsets.only(left: 4, right: 4),
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleBackButtonPressed,
          ),
        ],
      ),
    )
        : const SizedBox.shrink();

    final Widget fullScreen = Column(
      children: [
        topBackBar,
        Expanded(child: webView),
      ],
    );

    final Widget body = _safeAreaEnabled
        ? SafeArea(
      child: fullScreen,
    )
        : fullScreen;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SizedBox.expand(
          child: ColoredBox(
            color: bgColor,
            child: body,
          ),
        ),
      ),
    );
  }

  bool _isAdobeRedirect(Uri uri) {
    final String host = uri.host.toLowerCase();
    return host == 'c00.adobe.com';
  }
}

// ---------------------- Экран для c00.adobe.com ----------------------

class AdobeRedirectScreen extends StatelessWidget {
  final Uri uri;

  const AdobeRedirectScreen({super.key, required this.uri});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111111),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Go to the App Store and download the app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              SizedBox(height: 24),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(HunterVegasFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HunterVegasHall(),
    ),
  );
}