import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../data/models/aggregated_item.dart';
import '../data/models/home_row.dart';
import '../preference/home_section_config.dart';
import '../preference/user_preferences.dart';
import '../ui/navigation/home_refresh_bus.dart';
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
      await _applyDadflixDefaults();
      // Yerlesimi uygula (senkron dibe atmis olabilir).
      await enforceLayout();
      print('dadflix: feed satirlari eklendi=$added toplam=${configs.length}');
    } catch (e) {
      print('dadflix: ensureHomeSections hata: $e');
    }
  }

  // --- Yerlesim koruyucusu -------------------------------------------------
  //
  // Moonbase senkronu (plugin_sync_service.dart:1423) her acilista bolum
  // listesini sunucunun `homeRowOrder`'indan yeniden kurar ve TANIMADIGI
  // dinamik satirlari -- yani bizimkileri -- TUM built-in tiplerin ARKASINA
  // ekler. Sonuc: Spark/kesif lane'leri 60+ satir asagida gomulu kalir ve
  // pratikte gorunmez. Sunucuya kendi duzenimizi yazmak webOS TV'lerin
  // paylastigi profili de degistirecegi icin tercih edilmedi; bunun yerine
  // tercih degisimlerini dinleyip yerlesimi geri aliyoruz.

  static const _freshRowSection = '${_sectionPrefix}personalized-fresh';

  /// Kisisel Spark satiri "Devam Edenler"in hemen ardina gelir: ilk kaydirmada
  /// gorunur. (nextUp ayri bir bolum olsa da mergeContinueWatchingNextUp ile
  /// ayni satirda ciziliyor.)
  static const _freshSlot = 1;

  /// Ilk birkac kesif lane'i Live TV'den sonra, kutuphane satirlarindan ONCE:
  /// kullanici lane'leri aramak zorunda kalmasin.
  static const _topDiscoverySlot = 2;
  static const _topDiscoveryCount = 3;

  /// Ayni anda acik tutulan kesif lane sayisi (konsey hedefi 6-10 gorunur satir).
  static const _visibleDiscoveryCount = 6;

  /// Geri kalan kesif lane'leri kutuphane satirlarinin (latestMedia her
  /// kutuphane icin ayri satira aciliyor) arkasinda toplanir.
  static const _restDiscoverySlot = 5;

  /// Kisisel satir bu konumdan daha asagidaysa yerlesim bozulmus sayilir.
  /// (Kullanicinin kucuk elle duzenlemeleri bu toleransta korunur.)
  static const _freshTolerance = 2;

  bool _watching = false;
  bool _enforcing = false;

  /// Tercihler her degistiginde (ozellikle Moonbase senkronundan sonra)
  /// yerlesimi denetler. Tekrar tekrar yazmaz: yalnizca gomulme tespit
  /// edilirse mudahale eder.
  void startLayoutGuard() {
    if (_watching || !_prefs.isConfigured) return;
    _watching = true;
    GetIt.instance<UserPreferences>().addListener(_onPreferencesChanged);
  }

  Timer? _guardDebounce;

  void _onPreferencesChanged() {
    if (_enforcing) return;
    // Senkron tek turda birden cok tercih yazar; her tick'te liste yeniden
    // kurmak 10-foot arayuzde jank ve odak kaymasi yapar (konsey uyarisi).
    _guardDebounce?.cancel();
    _guardDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(enforceLayout());
    });
  }

  /// Dadflix satirlarini gorunur konuma tasir. Zaten yerindeyse hicbir sey
  /// yazmaz (senkron ile sonsuz dongu olusmaz).
  Future<void> enforceLayout() async {
    if (_enforcing || !_prefs.isConfigured) return;
    _enforcing = true;
    try {
      final prefs = GetIt.instance<UserPreferences>();
      final configs = List<HomeSectionConfig>.from(prefs.homeSectionsConfig)
        ..sort((a, b) => a.order.compareTo(b.order));
      final ours = configs
          .where((c) => isDadflixSection(c.pluginSection))
          .toList();
      if (ours.isEmpty) return;

      // Kisisel satir yeterince yukaridaysa dokunma (elle duzenlemeye saygi).
      final enabled = configs.where((c) => c.enabled).toList();
      final freshIdx = enabled.indexWhere(
        (c) => c.pluginSection == _freshRowSection,
      );
      // Fresh yerindeyse VE acik kesif sayisi hedefteyse dokunma.
      final openDiscovery = ours
          .where((c) => c.enabled && c.pluginSection != _freshRowSection)
          .length;
      if (freshIdx >= 0 &&
          freshIdx <= _freshTolerance &&
          openDiscovery == _visibleDiscoveryCount) {
        return;
      }

      final others = configs
          .where((c) => !isDadflixSection(c.pluginSection))
          .toList();
      final enabledOthers = others.where((c) => c.enabled).toList();
      final disabledOthers = others.where((c) => !c.enabled).toList();
      final fresh = ours.where((c) => c.pluginSection == _freshRowSection);
      final discovery = ours
          .where((c) => c.pluginSection != _freshRowSection)
          .toList();

      // Konsey (Grok/GLM 2026-08-31): 23 lane 10-foot arayuzde fazla; odak
      // yolu uzuyor. Ilk _visibleDiscoveryCount kadari acik kalir, kalani
      // KAPATILIR (silinmez: kullanici Ayarlar > Home Sections'tan acabilir,
      // ileride Spark sirayi dondurdukce farkli lane'ler one gelir).
      for (var i = 0; i < discovery.length; i++) {
        final shouldEnable = i < _visibleDiscoveryCount;
        if (discovery[i].enabled != shouldEnable) {
          discovery[i] = discovery[i].copyWith(enabled: shouldEnable);
        }
      }
      final visibleDiscovery =
          discovery.where((c) => c.enabled).toList();
      final hiddenDiscovery =
          discovery.where((c) => !c.enabled).toList();
      final topDiscovery = visibleDiscovery.take(_topDiscoveryCount).toList();
      final restDiscovery = visibleDiscovery.skip(_topDiscoveryCount).toList();

      final rebuilt = <HomeSectionConfig>[];
      for (var i = 0; i < enabledOthers.length; i++) {
        if (i == _freshSlot) rebuilt.addAll(fresh);
        if (i == _topDiscoverySlot) rebuilt.addAll(topDiscovery);
        if (i == _restDiscoverySlot) rebuilt.addAll(restDiscovery);
        rebuilt.add(enabledOthers[i]);
      }
      // Acik built-in sayisi slot'lardan azsa kalanlari sona ekle.
      for (final c in [...fresh, ...topDiscovery, ...restDiscovery]) {
        if (!rebuilt.contains(c)) rebuilt.add(c);
      }
      rebuilt.addAll(hiddenDiscovery);
      rebuilt.addAll(disabledOthers);

      for (var i = 0; i < rebuilt.length; i++) {
        rebuilt[i] = rebuilt[i].copyWith(order: i);
      }
      await prefs.setHomeSectionsConfig(rebuilt);
      homeRefreshBus.requestNowOrAfterNavigation();
      print('dadflix: yerlesim duzeltildi (Spark $freshIdx -> $_freshSlot)');
    } catch (e) {
      print('dadflix: yerlesim hatasi: $e');
    } finally {
      _enforcing = false;
    }
  }

  /// Tek seferlik Dadflix varsayilanlari. Kullanici sonradan degistirirse
  /// tekrar ezilmez (surum bayragi). Yeni stick'lerde ayni davranis icin
  /// kurulumdan sonra kendiliginden uygulanir.
  Future<void> _applyDadflixDefaults() async {
    if (_prefs.defaultsVersion >= 1) return;
    try {
      final prefs = GetIt.instance<UserPreferences>();
      // Outro'da "Skip Outro" butonu yerine dogrudan "Sirada" karti cikar
      // (kullanici istegi 2026-08-31): jenerikte tek is siradaki bolume
      // gecmek; ayri bir atlama butonu gereksiz.
      await prefs.set(UserPreferences.replaceSkipOutroWithNextUp, true);
      await _prefs.setDefaultsVersion(1);
      print('dadflix: varsayilanlar uygulandi (outro -> Sirada)');
    } catch (e) {
      print('dadflix: varsayilan hatasi: $e');
    }
  }
}
