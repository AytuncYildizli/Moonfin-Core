import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'dadflix_api.dart';
import 'dadflix_preferences.dart';

/// dadflix: Denizevi brain baglanti ayarlari (base URL + X-API-Key).
/// settings_side_panel.dart'tan pushSettingsScreen ile acilir; upstream'in
/// `part` mekanizmasina bilerek girmiyoruz (public ekran yeterli).
class DadflixSettingsScreen extends StatefulWidget {
  const DadflixSettingsScreen({super.key});

  @override
  State<DadflixSettingsScreen> createState() => _DadflixSettingsScreenState();
}

class _DadflixSettingsScreenState extends State<DadflixSettingsScreen> {
  late final DadflixPreferences _prefs = GetIt.instance<DadflixPreferences>();
  late final TextEditingController _urlCtrl =
      TextEditingController(text: _prefs.baseUrl);
  late final TextEditingController _keyCtrl =
      TextEditingController(text: _prefs.apiKey);
  String? _testResult;
  bool _testing = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    await _prefs.setBaseUrl(_urlCtrl.text);
    await _prefs.setApiKey(_keyCtrl.text);
    setState(() {
      _testing = true;
      _testResult = null;
    });
    // Ucuz bir dogrulama: status endpoint'i gecerli anahtarla cevap doner.
    final api = GetIt.instance<DadflixApi>();
    final ok = await api.pollStatus(0) != null;
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = ok ? 'Bağlantı OK ✓' : 'Bağlantı kurulamadı (adres/anahtar?)';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dadflix Brain')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Denizevi brain bağlantısı: debrid anında oynatma ve akıllı '
            'özellikler bu sunucuyu kullanır.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Sunucu adresi',
              hintText: 'http://192.168.1.105:8892',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Erişim anahtarı',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _testing ? null : _saveAndTest,
            child: Text(_testing ? 'Deneniyor…' : 'Kaydet ve sına'),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Text(_testResult!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
