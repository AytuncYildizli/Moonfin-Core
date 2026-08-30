import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../data/models/aggregated_item.dart';
import '../data/models/home_row.dart';
import '../preference/home_section_config.dart';
import '../preference/user_preferences.dart';
import 'dadflix_preferences.dart';

/// dadflix: denizevi-ai ev feed'ini (:8892 /api/feed/home) ana ekran
/// satirlarina baglar.
///
/// Satir konfigurasyonu `pluginSource: custom` + `pluginSection:
/// 'dadflix_feed:<feedRowId>'` bicimindedir; boylece Moonbase senkronu ve
/// ayar ekrani satiri upstream'in kendi custom satirlari gibi korur
/// (yeni enum degeri EKLENMEZ — bilinmeyen pluginSource ilk senkronda
/// silinir). Item'lar TMDB tabanlidir ve `serverId: 'seerr'` senteliyle
/// uretilir: tiklama Seerr detayina gider, orada da debrid "Simdi izle"
/// butonu devrededir.
class DadflixFeedService {
  static const _sectionPrefix = 'dadflix_feed:';

  final DadflixPreferences _prefs;
  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (_) => true,
    ),
  );

  Map<String, dynamic>? _cachedFeed;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<Map<String, dynamic>?>? _inFlight;

  DadflixFeedService(this._prefs);

  static bool isDadflixSection(String? section) =>
      section != null && section.startsWith(_sectionPrefix);

  Future<Map<String, dynamic>?> _feed({bool forceRefresh = false}) async {
    if (!_prefs.isConfigured) return null;
    final fresh =
        DateTime.now().difference(_cachedAt) < const Duration(minutes: 15);
    if (!forceRefresh && _cachedFeed != null && fresh) return _cachedFeed;
    final pending = _inFlight;
    if (pending != null) return pending;
    final future = _fetchFeed();
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
    }
  }

  Future<Map<String, dynamic>?> _fetchFeed() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${_prefs.baseUrl}/api/feed/home',
        options: Options(headers: {'X-API-Key': _prefs.apiKey}),
      );
      if (res.statusCode == 200 && res.data != null) {
        _cachedFeed = res.data;
        _cachedAt = DateTime.now();
        return _cachedFeed;
      }
    } catch (_) {}
    return _cachedFeed; // bayat cache bos ekrandan iyidir
  }

  Map<String, dynamic>? _rowJson(Map<String, dynamic> feed, String rowId) {
    final freshRow = feed['freshRow'];
    if (freshRow is Map<String, dynamic> && freshRow['id'] == rowId) {
      return freshRow;
    }
    final rows = feed['rows'];
    if (rows is List) {
      for (final r in rows) {
        if (r is Map<String, dynamic> && r['id'] == rowId) return r;
      }
    }
    return null;
  }

  /// row_data_source'un custom dalindan cagrilir.
  Future<HomeRow> loadRow({
    required String rowId,
    required String title,
    required String section,
    bool forceRefresh = false,
  }) async {
    final feedRowId = section.substring(_sectionPrefix.length);
    final feed = await _feed(forceRefresh: forceRefresh);
    final row = feed == null ? null : _rowJson(feed, feedRowId);
    if (row == null) {
      return HomeRow(id: rowId, title: title, rowType: HomeRowType.pluginDynamic);
    }
    final items = <AggregatedItem>[];
    for (final raw in (row['items'] as List? ?? const [])) {
      if (raw is! Map<String, dynamic>) continue;
      final providerIds = raw['ProviderIds'];
      final tmdb = providerIds is Map ? providerIds['Tmdb']?.toString() : null;
      if (tmdb == null || tmdb.isEmpty) continue;
      final isTv = (raw['mediaType'] ?? '') == 'tv' || raw['Type'] == 'Series';
      items.add(
        AggregatedItem(
          id: tmdb,
          serverId: 'seerr',
          rawData: {
            'Name': raw['Name'] ?? '',
            'Type': isTv ? 'Series' : 'Movie',
            'Overview': raw['overview'] ?? '',
            'PosterPath': raw['posterPath'] ?? '',
            'BackdropPath': raw['backdropPath'] ?? raw['posterPath'] ?? '',
            'ProductionYear': raw['ProductionYear'],
            'SeerrMediaType': isTv ? 'tv' : 'movie',
            'ProviderIds': {'Tmdb': tmdb},
          },
        ),
      );
    }
    return HomeRow(
      id: rowId,
      // Basligi feed'ten al: kisisel satirin adi dinamik
      // ("X Izledigin Icin"); config'teki metin fallback kalir.
      title: (row['title'] as String?)?.trim().isNotEmpty == true
          ? row['title'] as String
          : title,
      rowType: HomeRowType.pluginDynamic,
      items: items,
    );
  }

  /// Uygulama acilisinda bir kez: feed'deki TUM satirlari Home Sections'a
  /// (yoksa) ekler. Kisisel satir one, kesif satirlari mevcutlarin arkasina.
  /// Anahtar yapilandirilmamissa hicbir sey yapmaz.
  Future<void> ensureHomeSections() async {
    if (!_prefs.isConfigured) {
      print('dadflix: feed yapilandirilmamis (anahtar yok)');
      return;
    }
    try {
      final feed = await _feed();
      if (feed == null) {
        print('dadflix: feed alinamadi, satirlar eklenmedi');
        return;
      }
      final prefs = GetIt.instance<UserPreferences>();
      final configs = List<HomeSectionConfig>.from(prefs.homeSectionsConfig);
      final existing = configs
          .map((c) => c.pluginSection)
          .whereType<String>()
          .toSet();
      var added = 0;
      var tailOrder = configs.length + 8;
      void add(String rowId, String label, int order) {
        final section = '$_sectionPrefix$rowId';
        if (existing.contains(section)) return;
        configs.add(
          HomeSectionConfig.pluginDynamic(
            serverId: 'custom',
            pluginSection: section,
            pluginDisplayText: label,
            pluginSource: HomeSectionPluginSource.custom,
            enabled: true,
            order: order,
          ),
        );
        added++;
      }

      final freshRow = feed['freshRow'];
      if (freshRow is Map<String, dynamic> && freshRow['id'] is String) {
        add(
          freshRow['id'] as String,
          (freshRow['title'] as String?) ?? 'Spark: Senin İçin',
          2, // Devam Edenler + Sirada'dan hemen sonra
        );
      }
      final rows = feed['rows'];
      if (rows is List) {
        for (final r in rows) {
          if (r is! Map<String, dynamic>) continue;
          final id = r['id'];
          if (id is! String || id.isEmpty) continue;
          add(id, (r['title'] as String?) ?? id, tailOrder++);
        }
      }
      if (added > 0) {
        await prefs.setHomeSectionsConfig(configs);
      }
      print('dadflix: feed satirlari eklendi=$added toplam=${configs.length}');
    } catch (e) {
      print('dadflix: ensureHomeSections hata: $e');
    }
  }
}
