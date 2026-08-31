import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../auth/repositories/session_repository.dart';

/// dadflix: Denizevi brain (:8892) baglantisi icin kullanici-scoped tercihler.
/// SeerrPreferences deseninin birebir kopyasi — upstream user_preferences.dart'a
/// bilinçli olarak dokunulmuyor (rebase guvenligi).
class DadflixPreferences {
  final PreferenceStore _store;
  final SessionRepository _session;

  DadflixPreferences(this._store, this._session);

  String _userKey(String key) {
    final uid = _session.activeUserId ?? '';
    return 'dadflix_${key}_$uid';
  }

  /// Denizevi brain temel adresi (denizevi-ai).
  String get baseUrl =>
      _store.getString(_userKey('base_url')) ?? 'http://192.168.1.105:8892';
  Future<void> setBaseUrl(String value) =>
      _store.setString(_userKey('base_url'), value.trim());

  /// Derleme zamani enjeksiyonu: --dart-define=DADFLIX_KEY=... ile gelir.
  /// Boylece aile cihazlarinda kurulumdan sonra elle anahtar girmek gerekmez;
  /// ayar ekranindan girilen deger her zaman oncelikli. Anahtar repo'ya girmez.
  static const String _builtInKey = String.fromEnvironment('DADFLIX_KEY');

  /// X-API-Key (DENIZEVI_API_KEY). Bos ise dadflix ozellikleri gizlenir.
  String get apiKey {
    final stored = _store.getString(_userKey('api_key')) ?? '';
    return stored.isNotEmpty ? stored : _builtInKey;
  }
  Future<void> setApiKey(String value) =>
      _store.setString(_userKey('api_key'), value.trim());

  bool get isConfigured => apiKey.isNotEmpty && baseUrl.isNotEmpty;

  /// Uygulanan ana-ekran yerlesim surumu (bir-kerelik duzen tasima bayragi).
  int get layoutVersion => _store.getInt(_userKey('layout_version')) ?? 0;
  Future<void> setLayoutVersion(int value) =>
      _store.setInt(_userKey('layout_version'), value);

  /// Uygulanan tek-seferlik varsayilan seti surumu.
  int get defaultsVersion => _store.getInt(_userKey('defaults_version')) ?? 0;
  Future<void> setDefaultsVersion(int value) =>
      _store.setInt(_userKey('defaults_version'), value);

  /// Concierge servisi adresi (verdict yazma yolu).
  String get conciergeUrl =>
      _store.getString(_userKey('concierge_url')) ??
      'http://192.168.1.105:8086';

  /// Concierge (:8086) yazma anahtari — verdict overlay POST'lari icin.
  static const String _builtInConciergeKey =
      String.fromEnvironment('DADFLIX_CONCIERGE_KEY');
  String get conciergeKey {
    final stored = _store.getString(_userKey('concierge_key')) ?? '';
    return stored.isNotEmpty ? stored : _builtInConciergeKey;
  }
}
