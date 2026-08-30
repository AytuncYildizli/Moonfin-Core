import 'package:dio/dio.dart';

import 'dadflix_preferences.dart';

/// dadflix: denizevi-ai (:8892) ince HTTP istemcisi.
/// Sozlesme webOS moonfin'deki services/debridPlay.js ile ayni:
///  POST /api/discover/play  -> 200 {granted,url,mimeType?,subtitleUrl?}
///                              202 {status:'preparing',torrentId}
///                              404 kaynak yok (Seerr istegine dusulur)
///  GET  /api/discover/status?torrentId=X -> {ready,progress,url?,subtitleUrl?}
class DadflixApi {
  final DadflixPreferences _prefs;
  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
      validateStatus: (_) => true,
    ),
  );

  DadflixApi(this._prefs);

  Options get _auth => Options(headers: {'X-API-Key': _prefs.apiKey});

  /// Debrid aninda-oynatma. Kaynak yoksa/lokal hata varsa null doner
  /// (cagiran Seerr istek akisina duser).
  Future<DebridPlayResult?> playDebrid({
    required int tmdbId,
    String? imdbId,
    required String mediaType, // 'movie' | 'tv'
    required String title,
    int? year,
    int? season,
    int? episode,
  }) async {
    if (!_prefs.isConfigured) return null;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '${_prefs.baseUrl}/api/discover/play',
        data: {
          'tmdbId': tmdbId,
          if (imdbId != null && imdbId.isNotEmpty) 'imdbId': imdbId,
          'mediaType': mediaType,
          'title': title,
          if (year != null) 'year': year,
          if (season != null) 'season': season,
          if (episode != null) 'episode': episode,
        },
        options: _auth,
      );
      final data = res.data;
      if (res.statusCode == 200 && data != null && data['granted'] == true) {
        final url = data['url'] as String?;
        if (url == null || url.isEmpty) return null;
        return DebridPlayResult(
          granted: true,
          url: url,
          mimeType: data['mimeType'] as String?,
          subtitleUrl: data['subtitleUrl'] as String?,
        );
      }
      if (res.statusCode == 202 && data != null) {
        return DebridPlayResult(
          granted: false,
          status: (data['status'] as String?) ?? 'preparing',
          torrentId: data['torrentId'] is int
              ? data['torrentId'] as int
              : int.tryParse('${data['torrentId']}'),
        );
      }
      return null; // 404 / 5xx -> Seerr istegine dus
    } catch (_) {
      return null; // ag hatasi/timeout -> Seerr istegine dus
    }
  }

  /// Hazirlanan (202) indirmenin durumunu yoklar; hata halinde null.
  Future<DebridStatus?> pollStatus(int torrentId) async {
    if (!_prefs.isConfigured) return null;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${_prefs.baseUrl}/api/discover/status',
        queryParameters: {'torrentId': torrentId},
        options: _auth,
      );
      final data = res.data;
      if (res.statusCode == 200 && data != null) {
        return DebridStatus(
          ready: data['ready'] == true,
          progress: (data['progress'] as num?)?.toDouble() ?? 0,
          url: data['url'] as String?,
          subtitleUrl: data['subtitleUrl'] as String?,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

class DebridPlayResult {
  final bool granted;
  final String? url;
  final String? mimeType;
  final String? subtitleUrl;
  final String? status;
  final int? torrentId;

  const DebridPlayResult({
    required this.granted,
    this.url,
    this.mimeType,
    this.subtitleUrl,
    this.status,
    this.torrentId,
  });
}

class DebridStatus {
  final bool ready;
  final double progress;
  final String? url;
  final String? subtitleUrl;

  const DebridStatus({
    required this.ready,
    required this.progress,
    this.url,
    this.subtitleUrl,
  });
}
