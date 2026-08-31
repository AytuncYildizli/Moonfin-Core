import 'package:dio/dio.dart';

import 'dadflix_preferences.dart';

/// dadflix: "Dadflix Kanalı" — evin kendi TV kanali.
///
/// Sunucu (denizevi, :8899) gunluk bir YAYIN AKISI kurar; istemci "su an ne
/// oynuyor + kacinci saniyedeyiz" diye sorar ve normal Jellyfin yolundan
/// (DirectPlay) o noktadan baslatir. Yani sunucuda surekli transcode YOK:
/// kalite tam, Mac Mini'ye yuk binmiyor. Program bitince istemci tekrar sorar
/// ve akis kesintisiz devam eder — gercek bir kanal gibi.
class DadflixChannel {
  final DadflixPreferences _prefs;
  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
    ),
  );

  DadflixChannel(this._prefs);

  String get _base {
    // Kanal motoru beyinle ayni makinede, ayri portta.
    final uri = Uri.tryParse(_prefs.baseUrl);
    if (uri == null || uri.host.isEmpty) return 'http://192.168.1.105:8899';
    return 'http://${uri.host}:8899';
  }

  /// Su an yayinda olan program. Kanal bos/kapaliysa null.
  Future<ChannelNow?> now() async {
    if (!_prefs.isConfigured) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_base/api/channel/now',
        options: Options(headers: {'X-API-Key': _prefs.apiKey}),
      );
      final d = res.data;
      if (res.statusCode != 200 || d == null) return null;
      final on = d['onNow'];
      if (on is! Map<String, dynamic>) return null;
      final nx = d['next'];
      return ChannelNow(
        itemId: on['itemId'] as String,
        title: (on['title'] as String?) ?? '',
        seriesName: on['seriesName'] as String?,
        daypart: (on['daypart'] as String?) ?? '',
        offsetSeconds: (d['offsetSeconds'] as num?)?.toInt() ?? 0,
        remainingSeconds: (d['remainingSeconds'] as num?)?.toInt() ?? 0,
        nextTitle: nx is Map<String, dynamic> ? nx['title'] as String? : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// Gunun tam akisi (rehber ekrani icin).
  Future<List<ChannelEntry>> schedule() async {
    if (!_prefs.isConfigured) return const [];
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_base/api/channel/schedule',
        options: Options(headers: {'X-API-Key': _prefs.apiKey}),
      );
      final items = res.data?['items'];
      if (res.statusCode != 200 || items is! List) return const [];
      return [
        for (final e in items)
          if (e is Map<String, dynamic>)
            ChannelEntry(
              itemId: e['itemId'] as String? ?? '',
              title: (e['title'] as String?) ?? '',
              seriesName: e['seriesName'] as String?,
              daypart: (e['daypart'] as String?) ?? '',
              startsAt: DateTime.tryParse(e['startsAt'] as String? ?? ''),
              endsAt: DateTime.tryParse(e['endsAt'] as String? ?? ''),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

class ChannelNow {
  final String itemId;
  final String title;
  final String? seriesName;
  final String daypart;
  final int offsetSeconds;
  final int remainingSeconds;
  final String? nextTitle;

  const ChannelNow({
    required this.itemId,
    required this.title,
    this.seriesName,
    required this.daypart,
    required this.offsetSeconds,
    required this.remainingSeconds,
    this.nextTitle,
  });

  String get displayTitle =>
      seriesName != null && seriesName!.isNotEmpty ? '$seriesName · $title' : title;
}

class ChannelEntry {
  final String itemId;
  final String title;
  final String? seriesName;
  final String daypart;
  final DateTime? startsAt;
  final DateTime? endsAt;

  const ChannelEntry({
    required this.itemId,
    required this.title,
    this.seriesName,
    required this.daypart,
    this.startsAt,
    this.endsAt,
  });

  String get displayTitle =>
      seriesName != null && seriesName!.isNotEmpty ? '$seriesName · $title' : title;
}
