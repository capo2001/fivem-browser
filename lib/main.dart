import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

const Color kBg = Color(0xFF070A0F);
const Color kSurface = Color(0xFF10141C);
const double kRadius = 5;

Color get kAccent => AppState.I.accentColor;

const String kFavoriteCheckTask = 'favoriteCheckTask';

// ---------------------------------------------------------------------------
// Themes
// ---------------------------------------------------------------------------

class AppThemeOption {
  final String key;
  final String labelDe;
  final String labelEn;
  final Color accent;
  const AppThemeOption(this.key, this.labelDe, this.labelEn, this.accent);
}

const List<AppThemeOption> kThemeOptions = [
  AppThemeOption('silver', 'Silber', 'Silver', Color(0xFFD4D8DF)),
  AppThemeOption('blue', 'Blau', 'Blue', Color(0xFF4C8DFF)),
  AppThemeOption('gold', 'Gold', 'Gold', Color(0xFFE0B45A)),
];

AppThemeOption themeByKey(String key) =>
    kThemeOptions.firstWhere((t) => t.key == key, orElse: () => kThemeOptions.first);

// ---------------------------------------------------------------------------
// Localization (lightweight - no codegen, just a lookup table)
// ---------------------------------------------------------------------------

const Map<String, Map<String, String>> _strings = {
  'appName': {'de': 'Fserver', 'en': 'Fserver'},
  'serverList': {'de': 'Serverliste', 'en': 'Server list'},
  'favorites': {'de': 'Favoriten', 'en': 'Favorites'},
  'favoritesSubtitle': {'de': 'Deine gespeicherten Server', 'en': 'Your saved servers'},
  'serverListSubtitle': {'de': 'Alle Server durchsuchen', 'en': 'Browse all servers'},
  'settings': {'de': 'Einstellungen', 'en': 'Settings'},
  'search': {'de': 'Server suchen', 'en': 'Search servers'},
  'retry': {'de': 'Erneut versuchen', 'en': 'Retry'},
  'noServersFound': {'de': 'Keine Server gefunden.', 'en': 'No servers found.'},
  'noFavoritesYet': {'de': 'Noch keine Favoriten. Tippe auf den Stern in einem Serverprofil.', 'en': 'No favorites yet. Tap the star on a server profile.'},
  'loading': {'de': 'Lade komplette Serverliste…\ndas kann bis zu 30 Sekunden dauern', 'en': 'Loading full server list…\nthis can take up to 30 seconds'},
  'hideEmpty': {'de': 'Leere ausblenden', 'en': 'Hide empty'},
  'hideFull': {'de': 'Volle ausblenden', 'en': 'Hide full'},
  'country': {'de': 'Land', 'en': 'Country'},
  'tagsHint': {'de': 'Tags (1x einschließen, 2x ausschließen)', 'en': 'Tags (tap once to include, twice to exclude)'},
  'join': {'de': 'Beitreten', 'en': 'Join'},
  'copied': {'de': 'Kopiert', 'en': 'Copied'},
  'overview': {'de': 'Übersicht', 'en': 'Overview'},
  'scripts': {'de': 'Scripts', 'en': 'Scripts'},
  'filterScripts': {'de': 'Script filtern', 'en': 'Filter scripts'},
  'noScriptsFound': {'de': 'Keine Scripts gefunden.', 'en': 'No scripts found.'},
  'gametype': {'de': 'Gametype', 'en': 'Gametype'},
  'map': {'de': 'Map', 'en': 'Map'},
  'players': {'de': 'Spieler', 'en': 'Players'},
  'boost': {'de': 'Boost', 'en': 'Boost'},
  'onesync': {'de': 'OneSync', 'en': 'OneSync'},
  'active': {'de': 'Aktiv', 'en': 'Active'},
  'inactive': {'de': 'Inaktiv', 'en': 'Inactive'},
  'build': {'de': 'Build', 'en': 'Build'},
  'language': {'de': 'Sprache', 'en': 'Language'},
  'tags': {'de': 'Tags', 'en': 'Tags'},
  'onboardingWelcome': {'de': 'Willkommen', 'en': 'Welcome'},
  'onboardingLanguage': {'de': 'Wähle deine Sprache', 'en': 'Choose your language'},
  'onboardingTheme': {'de': 'Wähle dein Farbschema', 'en': 'Choose your color scheme'},
  'continueLabel': {'de': 'Weiter', 'en': 'Continue'},
  'getStarted': {'de': 'Los geht\'s', 'en': 'Get started'},
  'appLanguage': {'de': 'App-Sprache', 'en': 'App language'},
  'colorScheme': {'de': 'Farbschema', 'en': 'Color scheme'},
  'notifications': {'de': 'Benachrichtigungen', 'en': 'Notifications'},
  'notificationsDesc': {'de': 'Benachrichtigung senden, wenn ein favorisierter Server genug Spieler hat', 'en': 'Notify me when a favorite server has enough players'},
  'notificationThreshold': {'de': 'Ab wie vielen Spielern benachrichtigen', 'en': 'Notify from this many players'},
  'back': {'de': 'Zurück', 'en': 'Back'},
};

String tr(String key) {
  final lang = AppState.I.language;
  return _strings[key]?[lang] ?? _strings[key]?['de'] ?? key;
}

// ---------------------------------------------------------------------------
// App state & persistence
// ---------------------------------------------------------------------------

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  String language = 'de';
  String themeKey = 'silver';
  bool notificationsEnabled = false;
  int notificationThreshold = 10;
  Set<String> favorites = {};
  bool onboardingDone = false;

  Color get accentColor => themeByKey(themeKey).accent;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    language = prefs.getString('language') ?? 'de';
    themeKey = prefs.getString('themeKey') ?? 'silver';
    notificationsEnabled = prefs.getBool('notificationsEnabled') ?? false;
    notificationThreshold = prefs.getInt('notificationThreshold') ?? 10;
    favorites = (prefs.getStringList('favorites') ?? const []).toSet();
    onboardingDone = prefs.getBool('onboardingDone') ?? false;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', language);
    await prefs.setString('themeKey', themeKey);
    await prefs.setBool('notificationsEnabled', notificationsEnabled);
    await prefs.setInt('notificationThreshold', notificationThreshold);
    await prefs.setStringList('favorites', favorites.toList());
    await prefs.setBool('onboardingDone', onboardingDone);
  }

  Future<void> setLanguage(String lang) async {
    language = lang;
    notifyListeners();
    await _persist();
  }

  Future<void> setThemeKey(String key) async {
    themeKey = key;
    notifyListeners();
    await _persist();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setNotificationThreshold(int value) async {
    notificationThreshold = value;
    notifyListeners();
    await _persist();
  }

  Future<void> completeOnboarding() async {
    onboardingDone = true;
    notifyListeners();
    await _persist();
  }

  bool isFavorite(String code) => favorites.contains(code);

  Future<void> toggleFavorite(String code) async {
    if (!favorites.add(code)) favorites.remove(code);
    notifyListeners();
    await _persist();
  }
}

// ---------------------------------------------------------------------------
// Background favorite-player-count check + local notifications
// ---------------------------------------------------------------------------

Future<void> _showFavoriteNotification(FlutterLocalNotificationsPlugin plugin, int id, String hostname, int clients) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'favorite_server_channel',
      'Favoriten-Benachrichtigungen',
      channelDescription: 'Benachrichtigungen für favorisierte Server',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
  await plugin.show(id, hostname, 'hat gerade $clients Spieler', details);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('notificationsEnabled') ?? false;
      final favorites = prefs.getStringList('favorites') ?? const [];
      if (!enabled || favorites.isEmpty) return true;
      final threshold = prefs.getInt('notificationThreshold') ?? 10;

      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(const InitializationSettings(android: androidInit));

      final servers = await ApiService.fetchTopServers();
      final byCode = {for (final s in servers) s.code: s};
      var notificationId = 5000;
      for (final code in favorites) {
        final server = byCode[code];
        if (server == null) continue;
        if (server.clients >= threshold) {
          await _showFavoriteNotification(plugin, notificationId++, server.hostname, server.clients);
        }
      }
    } catch (_) {
      // Best-effort background task - failures shouldn't crash anything.
    }
    return true;
  });
}

Future<void> _initNotifications() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.I.load();
  await _initNotifications();
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      kFavoriteCheckTask,
      kFavoriteCheckTask,
      frequency: const Duration(minutes: 15),
    );
  } catch (_) {
    // Background scheduling is best-effort; the app still works without it.
  }
  runApp(const FivemBrowserApp());
}

class FivemBrowserApp extends StatelessWidget {
  const FivemBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final base = ThemeData.dark(useMaterial3: true);
        return MaterialApp(
          title: 'Fserver',
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            scaffoldBackgroundColor: kBg,
            colorScheme: base.colorScheme.copyWith(
              brightness: Brightness.dark,
              primary: kAccent,
              secondary: kAccent,
              surface: kSurface,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              foregroundColor: Colors.white,
            ),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            textTheme: base.textTheme.apply(
              bodyColor: Colors.white.withValues(alpha: 0.92),
              displayColor: Colors.white,
              fontSizeFactor: 0.93,
            ),
            dividerColor: Colors.white.withValues(alpha: 0.08),
            useMaterial3: true,
          ),
          home: AppState.I.onboardingDone ? const MainMenuPage() : const OnboardingPage(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

String stripColorCodes(String input) {
  return input.replaceAll(RegExp(r'\^[0-9]'), '');
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  return false;
}

List<String> _asStringList(dynamic v) {
  if (v is List) {
    return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

List<PlayerInfo> _asPlayerList(dynamic v) {
  if (v is List) {
    return v
        .whereType<Map>()
        .map((m) => PlayerInfo.fromMap(m.cast<String, dynamic>()))
        .toList();
  }
  return const [];
}

class PlayerInfo {
  final int id;
  final String name;
  final int ping;

  const PlayerInfo({required this.id, required this.name, required this.ping});

  factory PlayerInfo.fromMap(Map<String, dynamic> m) {
    return PlayerInfo(
      id: _asInt(m['id']),
      name: stripColorCodes((m['name'] ?? '?').toString()),
      ping: _asInt(m['ping']),
    );
  }
}

// vars keys already surfaced through a dedicated field elsewhere in the
// UI, or internal FXServer convars not interesting to show to a player.
const Set<String> _knownVarsKeys = {
  'sv_projectname',
  'sv_projectdesc',
  'locale',
  'tags',
  'banner_detail',
  'banner_connecting',
  'onesync_enabled',
  'sv_enforcegamebuild',
  'sv_maxclients',
  'sv_scripthookallowed',
  'sv_appearallowlisted',
  'premium',
  'sv_enhancedhostsupport',
  'activitypubfeed',
  'sv_licensekeytoken',
  'sv_lan',
};

class ServerVars {
  final String? projectName;
  final String? projectDesc;
  final String? locale;
  final List<String> tags;
  final String? bannerDetail;
  final bool onesyncEnabled;
  final String? enforceGameBuild;
  // Server-operator-defined custom vars (e.g. "Website", "Discord",
  // "Fahrzeuge") that aren't part of the fixed field set above.
  final Map<String, String> extra;

  const ServerVars({
    this.projectName,
    this.projectDesc,
    this.locale,
    this.tags = const [],
    this.bannerDetail,
    this.onesyncEnabled = false,
    this.enforceGameBuild,
    this.extra = const {},
  });

  factory ServerVars.fromMap(Map<String, dynamic> m) {
    final rawTags = (m['tags'] ?? '').toString();
    final tags = rawTags
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    String? nullIfEmpty(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final projectName = nullIfEmpty(m['sv_projectName']);
    final projectDesc = nullIfEmpty(m['sv_projectDesc']);

    final extra = <String, String>{};
    for (final key in m.keys) {
      if (_knownVarsKeys.contains(key.toLowerCase())) continue;
      final value = nullIfEmpty(m[key]);
      if (value == null) continue;
      extra[key.replaceAll(':', '').trim()] = stripColorCodes(value);
    }

    return ServerVars(
      projectName: projectName != null ? stripColorCodes(projectName) : null,
      projectDesc: projectDesc != null ? stripColorCodes(projectDesc) : null,
      locale: nullIfEmpty(m['locale']),
      tags: tags,
      bannerDetail: nullIfEmpty(m['banner_detail']),
      onesyncEnabled: _asBool(m['onesync_enabled']),
      enforceGameBuild: nullIfEmpty(m['sv_enforceGameBuild']),
      extra: extra,
    );
  }
}

class GameServer {
  final String endPoint;
  final String code;
  final String hostnameRaw;
  final String hostname;
  final int clients;
  final int svMaxclients;
  final String gametype;
  final String mapname;
  final String iconVersion;
  final int upvotePower;
  final List<String> resources;
  final List<PlayerInfo> players;
  final ServerVars vars;

  const GameServer({
    required this.endPoint,
    required this.code,
    required this.hostnameRaw,
    required this.hostname,
    required this.clients,
    required this.svMaxclients,
    required this.gametype,
    required this.mapname,
    required this.iconVersion,
    required this.upvotePower,
    required this.resources,
    required this.players,
    required this.vars,
  });

  factory GameServer.fromEntry(Map<String, dynamic> entry) {
    final endPoint = (entry['EndPoint'] ?? '').toString();
    final data = (entry['Data'] is Map)
        ? (entry['Data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final varsMap =
        (data['vars'] is Map) ? (data['vars'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final rawHostname = (data['hostname'] ?? endPoint).toString();

    return GameServer(
      endPoint: endPoint,
      code: _extractCode(endPoint),
      hostnameRaw: rawHostname,
      hostname: stripColorCodes(rawHostname),
      clients: _asInt(data['clients']),
      svMaxclients: _asInt(data['svMaxclients']),
      gametype: stripColorCodes((data['gametype'] ?? '').toString()),
      mapname: stripColorCodes((data['mapname'] ?? '').toString()),
      iconVersion: (data['iconVersion'] ?? '0').toString(),
      upvotePower: _asInt(data['upvotePower']),
      resources: _asStringList(data['resources']),
      players: _asPlayerList(data['players']),
      vars: ServerVars.fromMap(varsMap),
    );
  }

  static String _extractCode(String endPoint) {
    final match =
        RegExp(r'^([a-zA-Z0-9]+)\.users\.cfx\.re(?::\d+)?$').firstMatch(endPoint);
    if (match != null) return match.group(1)!;
    return endPoint;
  }

  // `vars.locale` is free text set by each server operator (not a
  // validated ISO code), so raw values are wildly inconsistent ("DE",
  // "GER", "D", "USA", "EUA", ...). Only a handful of countries are
  // curated into flags; everything else shows no country badge.
  static const Map<String, Set<String>> _countryAliasGroups = {
    'DE': {'DE', 'GER', 'GERMANY', 'DEUTSCHLAND', 'D', 'DA'},
    'IT': {'IT', 'ITA', 'ITALY', 'ITALIA'},
    'US': {'US', 'USA', 'EUA', 'AMERICA', 'UNITEDSTATES'},
  };

  String? get countryGroup {
    final locale = vars.locale;
    if (locale == null || locale.isEmpty) return null;
    final normalized = locale.toUpperCase().trim();
    final parts =
        normalized.split(RegExp(r'[-_\s]+')).where((p) => p.isNotEmpty);
    final candidates = <String>{normalized, ...parts};
    for (final entry in _countryAliasGroups.entries) {
      if (candidates.any(entry.value.contains)) return entry.key;
    }
    return null;
  }

  Set<String> get tagsLower => vars.tags.map((t) => t.toLowerCase()).toSet();

  String get iconUrl =>
      'https://frontend.cfx-services.net/api/servers/icon/$code/$iconVersion.png';

  String get joinUrl => 'cfx.re/join/$code';
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

// Minimal protobuf wire-format reader: enough to walk an unknown message's
// fields (varint / length-delimited / 32-bit / 64-bit) without needing a
// full .proto-generated schema or an extra dependency.
class _ProtoReader {
  final Uint8List bytes;
  int _offset = 0;

  _ProtoReader(this.bytes);

  int _readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final b = bytes[_offset++];
      result |= (b & 0x7F) << shift;
      if (b & 0x80 == 0) break;
      shift += 7;
    }
    return result;
  }

  Uint8List _readBytes(int length) {
    final chunk = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return chunk;
  }

  /// Field number -> list of raw values (int for varint/fixed, Uint8List
  /// for length-delimited), in encounter order, since fields may repeat.
  Map<int, List<Object>> readFields() {
    final fields = <int, List<Object>>{};
    while (_offset < bytes.length) {
      final tag = _readVarint();
      final fieldNumber = tag >> 3;
      final wireType = tag & 0x7;
      Object value;
      switch (wireType) {
        case 0:
          value = _readVarint();
          break;
        case 1:
          value = _readBytes(8);
          break;
        case 2:
          final len = _readVarint();
          value = _readBytes(len);
          break;
        case 5:
          value = _readBytes(4);
          break;
        default:
          return fields;
      }
      fields.putIfAbsent(fieldNumber, () => []).add(value);
    }
    return fields;
  }
}

class ApiService {
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
    'Origin': 'https://servers.fivem.net',
    'Referer': 'https://servers.fivem.net/',
  };

  // The site doesn't have a server-side "top N by country" route: it
  // downloads the full server dump via a redirect-based stream endpoint
  // and filters/sorts it client-side, so we do the same.
  static const List<String> _topUrls = [
    'https://frontend.cfx-services.net/api/servers/streamRedir/',
    'https://servers-frontend.fivem.net/api/servers/streamRedir/',
  ];

  static const List<String> _singleUrls = [
    'https://frontend.cfx-services.net/api/servers/single/',
    'https://servers-frontend.fivem.net/api/servers/single/',
  ];

  static Future<List<GameServer>> fetchTopServers() async {
    final attemptErrors = <String>[];
    for (final url in _topUrls) {
      try {
        final res = await _getWithDohFallback(
          Uri.parse(url),
          timeout: const Duration(seconds: 60),
        );
        if (res.statusCode == 200) {
          final bytes = Uint8List.fromList(_gunzipIfNeeded(res.bodyBytes));
          final servers = await compute(_parseList, bytes);
          if (servers.isNotEmpty) return servers;
          attemptErrors.add('$url: leere Antwort');
        } else {
          attemptErrors.add('$url: HTTP ${res.statusCode}');
        }
      } catch (e) {
        attemptErrors.add('$url: $e');
      }
    }
    throw ApiException(
        'Serverliste konnte nicht geladen werden.\n${attemptErrors.join('\n')}');
  }

  // The stream feed is NOT JSON: it's a sequence of length-prefixed
  // protobuf messages (confirmed against the open-source "cfx-api"
  // reference implementation). Each record is:
  //   [4-byte little-endian uint32 length][that many bytes: a `Server`
  //   protobuf message with field 1 = EndPoint (string), field 2 = Data
  //   (nested message)].
  // Runs in a background isolate via compute() since the full dump can be
  // several megabytes and tens of thousands of entries.
  static List<GameServer> _parseList(Uint8List bytes) {
    final result = <GameServer>[];
    var offset = 0;
    while (offset + 4 <= bytes.length) {
      final len = bytes[offset] |
          (bytes[offset + 1] << 8) |
          (bytes[offset + 2] << 16) |
          (bytes[offset + 3] << 24);
      offset += 4;
      if (len < 0 || offset + len > bytes.length) break;
      final record = Uint8List.sublistView(bytes, offset, offset + len);
      offset += len;
      try {
        final entry = _decodeServerEntry(record);
        if (entry != null) {
          result.add(GameServer.fromEntry(entry));
        }
      } catch (_) {
        // skip malformed entries
      }
    }
    return result;
  }

  static Map<String, dynamic>? _decodeServerEntry(Uint8List bytes) {
    final fields = _ProtoReader(bytes).readFields();
    final endpointRaw = fields[1]?.first;
    final dataRaw = fields[2]?.first;
    if (endpointRaw is! Uint8List || dataRaw is! Uint8List) return null;
    return {
      'EndPoint': utf8.decode(endpointRaw, allowMalformed: true),
      'Data': _decodeServerData(dataRaw),
    };
  }

  static Map<String, dynamic> _decodeServerData(Uint8List bytes) {
    final fields = _ProtoReader(bytes).readFields();

    String? stringField(int number) {
      final v = fields[number]?.first;
      return v is Uint8List ? utf8.decode(v, allowMalformed: true) : null;
    }

    int intField(int number) {
      final v = fields[number]?.first;
      return v is int ? v : 0;
    }

    List<String> repeatedString(int number) {
      return (fields[number] ?? const [])
          .whereType<Uint8List>()
          .map((b) => utf8.decode(b, allowMalformed: true))
          .toList();
    }

    final vars = <String, dynamic>{};
    for (final entryBytes in fields[12] ?? const []) {
      if (entryBytes is! Uint8List) continue;
      final entryFields = _ProtoReader(entryBytes).readFields();
      final keyRaw = entryFields[1]?.first;
      final valueRaw = entryFields[2]?.first;
      if (keyRaw is Uint8List && valueRaw is Uint8List) {
        vars[utf8.decode(keyRaw, allowMalformed: true)] =
            utf8.decode(valueRaw, allowMalformed: true);
      }
    }

    final players = <Map<String, dynamic>>[];
    for (final playerBytes in fields[10] ?? const []) {
      if (playerBytes is! Uint8List) continue;
      final p = _ProtoReader(playerBytes).readFields();
      final nameRaw = p[1]?.first;
      players.add({
        'name': nameRaw is Uint8List ? utf8.decode(nameRaw, allowMalformed: true) : '',
        'ping': (p[4]?.first is int) ? p[4]!.first as int : 0,
        'id': (p[5]?.first is int) ? p[5]!.first as int : 0,
      });
    }

    return {
      'svMaxclients': intField(1),
      'clients': intField(2),
      'hostname': stringField(4) ?? '',
      'gametype': stringField(5) ?? '',
      'mapname': stringField(6) ?? '',
      'resources': repeatedString(8),
      'iconVersion': intField(11),
      'vars': vars,
      'upvotePower': intField(17),
      'players': players,
    };
  }

  static Future<GameServer> fetchServerDetail(String code) async {
    final attemptErrors = <String>[];
    for (final base in _singleUrls) {
      final url = '$base$code';
      try {
        final res = await _getWithDohFallback(
          Uri.parse(url),
          timeout: const Duration(seconds: 20),
        );
        if (res.statusCode != 200) {
          attemptErrors.add('$url: HTTP ${res.statusCode}');
          continue;
        }
        final decoded = jsonDecode(_bodyText(res));
        // fromEntry expects the *whole* {EndPoint, Data} wrapper (it does
        // its own entry['Data'] lookup) - passing decoded['Data'] here
        // directly was the long-standing bug that left every field empty.
        if (decoded is Map &&
            (decoded['Data'] is Map || decoded['EndPoint'] != null)) {
          return GameServer.fromEntry(decoded.cast<String, dynamic>());
        }
        attemptErrors.add('$url: unerwartetes Antwortformat');
      } catch (e) {
        attemptErrors.add('$url: $e');
      }
    }
    throw ApiException(
        'Serverdetails konnten nicht geladen werden.\n${attemptErrors.join('\n')}');
  }

  // The stream endpoint's response isn't always transparently
  // gzip-decompressed depending on the connection path taken, so decode
  // defensively: unzip if the bytes still look gzip-compressed, then
  // decode as UTF-8, falling back to Latin-1 so a stray invalid byte
  // somewhere in a server's user-supplied fields can't crash parsing.
  static String _bodyText(http.Response res) {
    final bytes = _gunzipIfNeeded(res.bodyBytes);
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static List<int> _gunzipIfNeeded(List<int> bytes) {
    if (bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      try {
        return gzip.decode(bytes);
      } catch (_) {
        return bytes;
      }
    }
    return bytes;
  }

  static final Map<String, InternetAddress> _dohIpCache = {};

  // Some networks filter the plain system DNS resolver (e.g. carrier
  // "youth protection" filters or a local ad-blocking VPN) while leaving
  // browsers unaffected because they use encrypted DNS-over-HTTPS. If the
  // normal request fails with a DNS lookup error, fall back to resolving
  // the host via Cloudflare's DoH endpoint and connecting to that IP
  // directly, mirroring what the browser does under the hood.
  static Future<http.Response> _getWithDohFallback(
    Uri uri, {
    required Duration timeout,
  }) async {
    try {
      return await http.get(uri, headers: _headers).timeout(timeout);
    } catch (e) {
      if (!_looksLikeDnsFailure(e)) rethrow;
      return _getViaDoh(uri, timeout: timeout);
    }
  }

  static bool _looksLikeDnsFailure(Object e) {
    final msg = e.toString();
    return msg.contains('Failed host lookup') ||
        msg.contains('No address associated with hostname');
  }

  // Two independent public DoH resolvers, tried in order, in case a
  // network specifically blocks one well-known resolver IP.
  static const List<String> _dohProviders = [
    'https://1.1.1.1/dns-query',
    'https://8.8.8.8/resolve',
  ];

  static Future<InternetAddress> _resolveViaDoh(String host) async {
    final cached = _dohIpCache[host];
    if (cached != null) return cached;
    final errors = <String>[];
    for (final base in _dohProviders) {
      try {
        final res = await http.get(
          Uri.parse('$base?name=$host&type=A'),
          headers: const {'Accept': 'application/dns-json'},
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) {
          errors.add('$base: HTTP ${res.statusCode}');
          continue;
        }
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['Answer'] is List) {
          for (final answer in decoded['Answer'] as List) {
            if (answer is Map &&
                answer['type'] == 1 &&
                answer['data'] is String) {
              final ip = InternetAddress.tryParse(answer['data'] as String);
              if (ip != null) {
                _dohIpCache[host] = ip;
                return ip;
              }
            }
          }
        }
        errors.add('$base: keine A-Record-Antwort');
      } catch (e) {
        errors.add('$base: $e');
      }
    }
    throw ApiException(
        'DoH-Auflösung fehlgeschlagen für $host (${errors.join(' | ')})');
  }

  static Future<http.Response> _getViaDoh(
    Uri uri, {
    required Duration timeout,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.connectionFactory = (url, proxyHost, proxyPort) async {
      final ip = await _resolveViaDoh(url.host);
      final socket = await Socket.connect(ip, url.port, timeout: timeout);
      return ConnectionTask.fromSocket(
        Future.value(socket),
        () => socket.destroy(),
      );
    };
    try {
      final request = await client.getUrl(uri);
      _headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return http.Response.bytes(bytes, response.statusCode);
    } finally {
      client.close(force: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Shared glass widgets
// ---------------------------------------------------------------------------

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double opacity;
  final double borderOpacity;
  final BorderRadius borderRadius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.blur = 22,
    this.opacity = 0.05,
    this.borderOpacity = 0.10,
    this.borderRadius = const BorderRadius.all(Radius.circular(kRadius)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: borderOpacity),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: opacity + 0.03),
                Colors.white.withValues(alpha: opacity * 0.3),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final bool active;
  final VoidCallback? onTap;
  final Color? tintColor;

  const Pill({
    super.key,
    required this.text,
    this.active = false,
    this.onTap,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = tintColor ?? kAccent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kRadius),
          color: active ? color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            height: 1,
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.75),
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Server list page
// ---------------------------------------------------------------------------

enum TagState { neutral, include, exclude }

class ServerListPage extends StatefulWidget {
  const ServerListPage({super.key});

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  List<GameServer> _servers = [];
  List<String> _topTags = [];
  bool _loading = true;
  String? _error;

  bool _filtersOpen = false;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _hideEmpty = false;
  bool _hideFull = false;
  String? _selectedCountry;
  final Map<String, TagState> _tagStates = {};

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servers = await ApiService.fetchTopServers();
      servers.sort((a, b) => b.upvotePower.compareTo(a.upvotePower));
      setState(() {
        _servers = servers;
        _topTags = _computeTopTags(servers);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // Curated, fixed set rather than derived from data - `vars.locale` is
  // free text and produces dozens of near-duplicate junk values.
  static const List<String> _availableCountries = ['DE', 'IT', 'US'];

  // Computed once when the list loads (not on every rebuild - with 30k+
  // servers this was the main source of the filter panel's lag), and
  // capped to the most common tags so the chip list stays small.
  static List<String> _computeTopTags(List<GameServer> servers) {
    final counts = <String, int>{};
    for (final s in servers) {
      for (final tag in s.tagsLower) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return sorted.take(24).toList();
  }

  List<GameServer> get _filtered {
    final query = _searchCtrl.text.trim().toLowerCase();
    final activeTagFilters =
        _tagStates.entries.where((e) => e.value != TagState.neutral).toList();

    return _servers.where((s) {
      if (query.isNotEmpty && !s.hostname.toLowerCase().contains(query)) {
        return false;
      }
      if (_hideEmpty && s.clients == 0) return false;
      if (_hideFull && s.svMaxclients > 0 && s.clients >= s.svMaxclients) {
        return false;
      }
      if (_selectedCountry != null && s.countryGroup != _selectedCountry) {
        return false;
      }
      for (final entry in activeTagFilters) {
        final has = s.tagsLower.contains(entry.key);
        if (entry.value == TagState.include && !has) return false;
        if (entry.value == TagState.exclude && has) return false;
      }
      return true;
    }).toList();
  }

  void _cycleTag(String tag) {
    setState(() {
      final current = _tagStates[tag] ?? TagState.neutral;
      switch (current) {
        case TagState.neutral:
          _tagStates[tag] = TagState.include;
          break;
        case TagState.include:
          _tagStates[tag] = TagState.exclude;
          break;
        case TagState.exclude:
          _tagStates[tag] = TagState.neutral;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(filtered.length),
            if (_filtersOpen) _buildFilterPanel(),
            Expanded(child: _buildBody(filtered)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
              Text(
                tr('serverList'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const Spacer(),
              _iconButton(
                icon: _filtersOpen ? Icons.tune : Icons.tune_outlined,
                active: _filtersOpen,
                onTap: () => setState(() => _filtersOpen = !_filtersOpen),
              ),
              const SizedBox(width: 8),
              _iconButton(
                icon: Icons.refresh,
                onTap: _loading ? null : _load,
              ),
            ],
          ),
          const SizedBox(height: 10),
          GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.search, size: 18, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: tr('search'),
                    ),
                  ),
                ),
                if (_searchCtrl.text.isNotEmpty)
                  InkWell(
                    onTap: () => _searchCtrl.clear(),
                    child: Icon(Icons.close, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton({required IconData icon, VoidCallback? onTap, bool active = false}) {
    return GlassPanel(
      padding: const EdgeInsets.all(8),
      opacity: active ? 0.14 : 0.05,
      child: InkWell(
        onTap: onTap,
        child: Icon(icon, size: 18, color: active ? kAccent : Colors.white.withValues(alpha: 0.8)),
      ),
    );
  }

  Widget _buildFilterPanel() {
    final countries = _availableCountries;
    final tags = _topTags;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Pill(
                    text: tr('hideEmpty'),
                    active: _hideEmpty,
                    onTap: () => setState(() => _hideEmpty = !_hideEmpty),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Pill(
                    text: tr('hideFull'),
                    active: _hideFull,
                    onTap: () => setState(() => _hideFull = !_hideFull),
                  ),
                ),
              ],
            ),
            if (countries.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionLabel(tr('country')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: countries.map((c) {
                  final active = _selectedCountry == c;
                  return Pill(
                    text: c,
                    active: active,
                    onTap: () => setState(() {
                      _selectedCountry = active ? null : c;
                    }),
                  );
                }).toList(),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              _sectionLabel(tr('tagsHint')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tags.map((t) {
                  final state = _tagStates[t] ?? TagState.neutral;
                  return Pill(
                    text: t,
                    active: state != TagState.neutral,
                    tintColor: state == TagState.exclude ? Colors.redAccent : kAccent,
                    onTap: () => _cycleTag(t),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildBody(List<GameServer> filtered) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: kAccent, strokeWidth: 2.4),
            const SizedBox(height: 14),
            Text(
              'Lade komplette Serverliste…\ndas kann bis zu 30 Sekunden dauern',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.45)),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: Colors.white.withValues(alpha: 0.35), size: 36),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
              const SizedBox(height: 14),
              GlassPanel(
                opacity: 0.10,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: InkWell(
                  onTap: _load,
                  child: Text(tr('retry'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          tr('noServersFound'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kAccent,
      backgroundColor: kSurface,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 20),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => ServerTile(server: filtered[index]),
      ),
    );
  }
}

class ServerTile extends StatelessWidget {
  final GameServer server;

  const ServerTile({super.key, required this.server});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ServerDetailPage(server: server)),
        );
      },
      child: GlassPanel(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ServerIcon(server: server, size: 52),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.hostname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  if (server.vars.tags.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: server.vars.tags.take(3).map((t) {
                        return Text(
                          t,
                          style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.4)),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (server.countryGroup != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public, size: 11, color: Colors.white.withValues(alpha: 0.35)),
                      const SizedBox(width: 3),
                      Text(
                        server.countryGroup!,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.45), letterSpacing: 0.4),
                      ),
                    ],
                  ),
                const SizedBox(height: 4),
                Text(
                  '${server.clients}/${server.svMaxclients}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                _BoostBadge(power: server.upvotePower),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BoostBadge extends StatelessWidget {
  final int power;
  const _BoostBadge({required this.power});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        color: kAccent.withValues(alpha: 0.08),
        border: Border.all(color: kAccent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.keyboard_arrow_up, size: 15, color: kAccent),
          Text(
            '$power',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kAccent),
          ),
        ],
      ),
    );
  }
}

class _ServerIcon extends StatelessWidget {
  final GameServer server;
  final double size;
  const _ServerIcon({required this.server, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadius),
      child: Image.network(
        server.iconUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _fallback(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _fallback();
        },
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        color: Colors.white.withValues(alpha: 0.05),
      ),
      child: Icon(Icons.dns_outlined, size: size * 0.5, color: Colors.white.withValues(alpha: 0.3)),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail page
// ---------------------------------------------------------------------------

class ServerDetailPage extends StatefulWidget {
  final GameServer server;
  const ServerDetailPage({super.key, required this.server});

  @override
  State<ServerDetailPage> createState() => _ServerDetailPageState();
}

class _ServerDetailPageState extends State<ServerDetailPage> with SingleTickerProviderStateMixin {
  // The bulk list feed omits resources and most custom vars (623
  // resources per server would balloon the ~20MB dump massively), so
  // those are fetched separately here. Never lets a bad/partial response
  // regress good data - it can only add resources/extra vars, never
  // remove the reliable list-derived fields.
  late final GameServer _server = widget.server;
  late final TabController _tabController;
  final TextEditingController _scriptCtrl = TextEditingController();
  List<String>? _fetchedResources;
  Map<String, String>? _fetchedExtraVars;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scriptCtrl.addListener(() => setState(() {}));
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      final detail = await ApiService.fetchServerDetail(_server.code);
      if (!mounted) return;
      setState(() {
        if (detail.resources.isNotEmpty) _fetchedResources = detail.resources;
        if (detail.vars.extra.isNotEmpty) _fetchedExtraVars = detail.vars.extra;
      });
    } catch (_) {
      // Best-effort only - the page already shows the list-derived data.
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scriptCtrl.dispose();
    super.dispose();
  }

  void _copyJoin() {
    Clipboard.setData(ClipboardData(text: _server.joinUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        content: Text('${tr('copied')}: ${_server.joinUrl}', style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _server;
    return Scaffold(
      backgroundColor: kBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              expandedHeight: 200,
              backgroundColor: kBg,
              leading: const BackButton(),
              actions: [
                IconButton(
                  onPressed: () async {
                    await AppState.I.toggleFavorite(s.code);
                    if (mounted) setState(() {});
                  },
                  icon: Icon(
                    AppState.I.isFavorite(s.code) ? Icons.star : Icons.star_border,
                    color: AppState.I.isFavorite(s.code) ? const Color(0xFFE0B45A) : Colors.white,
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _Banner(server: s),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ServerIcon(server: s, size: 44),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.hostname,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                              if (s.vars.projectName != null && s.vars.projectName != s.hostname) ...[
                                const SizedBox(height: 2),
                                Text(
                                  s.vars.projectName!,
                                  style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(kRadius),
                            onTap: _copyJoin,
                            child: GlassPanel(
                              opacity: 0.14,
                              borderOpacity: 0.4,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.content_copy, size: 15, color: kAccent),
                                    const SizedBox(width: 6),
                                    Text(tr('join'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kAccent)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassPanel(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${s.clients}/${s.svMaxclients}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  indicatorColor: kAccent,
                  indicatorWeight: 2,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.4),
                  labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: tr('overview')),
                    Tab(text: tr('scripts')),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _OverviewTab(
              server: s,
              extraVars: {...s.vars.extra, ...?_fetchedExtraVars},
            ),
            _ScriptsTab(
              resources: _fetchedResources ?? s.resources,
              controller: _scriptCtrl,
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final GameServer server;
  const _Banner({required this.server});

  @override
  Widget build(BuildContext context) {
    final banner = server.vars.bannerDetail;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (banner != null)
          Image.network(
            banner,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Container(color: kSurface),
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kSurface, kBg],
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kBg.withValues(alpha: 0.10), kBg.withValues(alpha: 0.85)],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: kBg.withValues(alpha: 0.85),
          child: tabBar,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => oldDelegate.tabBar != tabBar;
}

class _OverviewTab extends StatelessWidget {
  final GameServer server;
  final Map<String, String> extraVars;
  const _OverviewTab({required this.server, required this.extraVars});

  @override
  Widget build(BuildContext context) {
    final s = server;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (s.vars.projectDesc != null) ...[
          GlassPanel(
            child: Text(
              s.vars.projectDesc!,
              style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75), height: 1.4),
            ),
          ),
          const SizedBox(height: 10),
        ],
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statRow(tr('gametype'), s.gametype.isEmpty ? '—' : s.gametype),
              _divider(),
              _statRow(tr('map'), s.mapname.isEmpty ? '—' : s.mapname),
              _divider(),
              _statRow(tr('players'), '${s.clients} / ${s.svMaxclients}'),
              _divider(),
              _statRow(tr('boost'), '${s.upvotePower}'),
              _divider(),
              _statRow(tr('onesync'), s.vars.onesyncEnabled ? tr('active') : tr('inactive')),
              if (s.vars.enforceGameBuild != null) ...[
                _divider(),
                _statRow(tr('build'), s.vars.enforceGameBuild!),
              ],
              if (s.vars.locale != null) ...[
                _divider(),
                _statRow(tr('language'), s.vars.locale!),
              ],
            ],
          ),
        ),
        if (s.vars.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('tags').toUpperCase(), style: TextStyle(fontSize: 10.5, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.4))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: s.vars.tags.map((t) => Pill(text: t)).toList(),
                ),
              ],
            ),
          ),
        ],
        if (extraVars.isNotEmpty) ...[
          const SizedBox(height: 10),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in extraVars.entries) ...[
                  if (entry.key != extraVars.entries.first.key) _divider(),
                  _infoRow(entry.key, entry.value),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
          ),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // Custom operator-set fields (e.g. "Website", "Discord") can be
  // arbitrarily long, so label and value stack instead of sharing a row.
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.45))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.white.withValues(alpha: 0.06));
}

class _ScriptsTab extends StatelessWidget {
  final List<String> resources;
  final TextEditingController controller;
  const _ScriptsTab({required this.resources, required this.controller});

  @override
  Widget build(BuildContext context) {
    final query = controller.text.trim().toLowerCase();
    final filtered = resources
        .where((r) => query.isEmpty || r.toLowerCase().contains(query))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.search, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: tr('filterScripts'),
                    ),
                  ),
                ),
                Text('${filtered.length}/${resources.length}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4))),
              ],
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(tr('noScriptsFound'), style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    return GlassPanel(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          Icon(Icons.extension_outlined, size: 15, color: Colors.white.withValues(alpha: 0.4)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(filtered[index], style: const TextStyle(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding
// ---------------------------------------------------------------------------

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;

  void _selectLanguage(String lang) {
    AppState.I.setLanguage(lang);
    setState(() {});
  }

  void _selectTheme(String key) {
    AppState.I.setThemeKey(key);
    setState(() {});
  }

  void _onContinue() {
    if (_step == 0) {
      setState(() => _step = 1);
    } else {
      AppState.I.completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(Icons.dns, size: 46, color: kAccent),
              const SizedBox(height: 18),
              Text(
                tr('onboardingWelcome'),
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _step == 0 ? tr('onboardingLanguage') : tr('onboardingTheme'),
                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 28),
              if (_step == 0) _buildLanguageStep() else _buildThemeStep(),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: InkWell(
                  borderRadius: BorderRadius.circular(kRadius),
                  onTap: _onContinue,
                  child: GlassPanel(
                    opacity: 0.14,
                    borderOpacity: 0.4,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        _step == 0 ? tr('continueLabel') : tr('getStarted'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kAccent),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageStep() {
    return Column(
      children: [
        _optionTile('Deutsch', AppState.I.language == 'de', () => _selectLanguage('de')),
        const SizedBox(height: 10),
        _optionTile('English', AppState.I.language == 'en', () => _selectLanguage('en')),
      ],
    );
  }

  Widget _buildThemeStep() {
    return Column(
      children: kThemeOptions.map((t) {
        final label = AppState.I.language == 'de' ? t.labelDe : t.labelEn;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _optionTile(
            label,
            AppState.I.themeKey == t.key,
            () => _selectTheme(t.key),
            swatch: t.accent,
          ),
        );
      }).toList(),
    );
  }

  Widget _optionTile(String label, bool active, VoidCallback onTap, {Color? swatch}) {
    return InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: GlassPanel(
        opacity: active ? 0.14 : 0.05,
        borderOpacity: active ? 0.5 : 0.10,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            if (swatch != null) ...[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(color: swatch, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
            if (active) Icon(Icons.check_circle, size: 18, color: kAccent),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main menu
// ---------------------------------------------------------------------------

class MainMenuPage extends StatelessWidget {
  const MainMenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: kBg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('appName'),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 24),
                  _MenuCard(
                    icon: Icons.dns,
                    title: tr('serverList'),
                    subtitle: tr('serverListSubtitle'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ServerListPage()),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MenuCard(
                    icon: Icons.star,
                    title: tr('favorites'),
                    subtitle: tr('favoritesSubtitle'),
                    badge: AppState.I.favorites.isEmpty ? null : '${AppState.I.favorites.length}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FavoritesPage()),
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kRadius),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      ),
                      child: GlassPanel(
                        padding: const EdgeInsets.all(12),
                        child: Icon(Icons.settings_outlined, size: 22, color: Colors.white.withValues(alpha: 0.85)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: GlassPanel(
        blur: 24,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kRadius),
                color: kAccent.withValues(alpha: 0.12),
                border: Border.all(color: kAccent.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, size: 26, color: kAccent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
                ],
              ),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadius),
                  color: kAccent.withValues(alpha: 0.14),
                ),
                child: Text(badge!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kAccent)),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  bool _loading = true;
  String? _error;
  List<GameServer> _favoriteServers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servers = await ApiService.fetchTopServers();
      final favorites = AppState.I.favorites;
      final matched = servers.where((s) => favorites.contains(s.code)).toList();
      matched.sort((a, b) => b.upvotePower.compareTo(a.upvotePower));
      if (!mounted) return;
      setState(() {
        _favoriteServers = matched;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => Navigator.of(context).pop(),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.arrow_back, size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr('favorites'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (AppState.I.favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            tr('noFavoritesYet'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
          ),
        ),
      );
    }
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2.4));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: Colors.white.withValues(alpha: 0.35), size: 32),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
              const SizedBox(height: 14),
              InkWell(
                onTap: _load,
                child: GlassPanel(
                  opacity: 0.10,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Text(tr('retry'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_favoriteServers.isEmpty) {
      return Center(
        child: Text(tr('noFavoritesYet'), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kAccent,
      backgroundColor: kSurface,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 20),
        itemCount: _favoriteServers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => ServerTile(server: _favoriteServers[index]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: () => Navigator.of(context).pop(),
                    child: GlassPanel(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(Icons.arrow_back, size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    tr('settings'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _sectionLabel(tr('appLanguage')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Row(
                      children: [
                        Expanded(
                          child: Pill(
                            text: 'Deutsch',
                            active: AppState.I.language == 'de',
                            onTap: () {
                              AppState.I.setLanguage('de');
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Pill(
                            text: 'English',
                            active: AppState.I.language == 'en',
                            onTap: () {
                              AppState.I.setLanguage('en');
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('colorScheme')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Column(
                      children: kThemeOptions.map((t) {
                        final label = AppState.I.language == 'de' ? t.labelDe : t.labelEn;
                        final active = AppState.I.themeKey == t.key;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: InkWell(
                            onTap: () {
                              AppState.I.setThemeKey(t.key);
                              setState(() {});
                            },
                            child: Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
                                if (active) Icon(Icons.check_circle, size: 17, color: kAccent),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(tr('notifications')),
                  const SizedBox(height: 8),
                  GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(tr('notificationsDesc'), style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75))),
                            ),
                            Switch(
                              value: AppState.I.notificationsEnabled,
                              activeColor: kAccent,
                              onChanged: (v) {
                                AppState.I.setNotificationsEnabled(v);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        if (AppState.I.notificationsEnabled) ...[
                          Divider(height: 20, color: Colors.white.withValues(alpha: 0.06)),
                          Text(tr('notificationThreshold'), style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.5))),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _stepperButton(Icons.remove, () {
                                final v = (AppState.I.notificationThreshold - 5).clamp(1, 9999);
                                AppState.I.setNotificationThreshold(v);
                                setState(() {});
                              }),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    '${AppState.I.notificationThreshold}',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              _stepperButton(Icons.add, () {
                                final v = (AppState.I.notificationThreshold + 5).clamp(1, 9999);
                                AppState.I.setNotificationThreshold(v);
                                setState(() {});
                              }),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(kRadius),
      onTap: onTap,
      child: GlassPanel(
        opacity: 0.08,
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 18, color: kAccent),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10.5,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.4),
      ),
    );
  }
}
