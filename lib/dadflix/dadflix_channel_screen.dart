import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:playback_core/playback_core.dart';
import 'package:server_core/server_core.dart';

import '../data/models/aggregated_item.dart';
import '../ui/navigation/destinations.dart';
import '../ui/navigation/playback_launcher.dart';
import '../ui/widgets/navigation_layout.dart';
import 'dadflix_channel.dart';

/// dadflix: Kanal ekrani — "aç ve otur".
///
/// Kanali actiginda program COKTAN BASLAMIS olur: sunucudaki akistan "su an
/// ne oynuyor + kacinci saniye" bilgisi alinip oynatma o noktadan baslatilir
/// (gercek TV hissi). Altta gunun akisi rehber gibi listelenir.
class DadflixChannelScreen extends StatefulWidget {
  const DadflixChannelScreen({super.key});

  @override
  State<DadflixChannelScreen> createState() => _DadflixChannelScreenState();
}

class _DadflixChannelScreenState extends State<DadflixChannelScreen> {
  ChannelNow? _now;
  List<ChannelEntry> _grid = const [];
  bool _loading = true;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // Yayin akiyor: dakikada bir "su an ne var" tazelenir.
    _tick = Timer.periodic(const Duration(seconds: 45), (_) => _refreshNow());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final ch = GetIt.instance<DadflixChannel>();
    final now = await ch.now();
    final grid = await ch.schedule();
    if (!mounted) return;
    setState(() {
      _now = now;
      _grid = grid;
      _loading = false;
      _error = now == null && grid.isEmpty
          ? 'Kanal yayını alınamadı (sunucu kapalı olabilir).'
          : null;
    });
  }

  Future<void> _refreshNow() async {
    final now = await GetIt.instance<DadflixChannel>().now();
    if (!mounted || now == null) return;
    setState(() => _now = now);
  }

  /// Yayina katil: su anki programi, yayindaki saniyesinden baslat.
  Future<void> _tuneIn() async {
    final now = _now;
    if (now == null) return;
    final client = GetIt.instance<MediaServerClient>();
    final manager = GetIt.instance<PlaybackManager>();
    try {
      final raw = await client.userLibraryApi.getItem(now.itemId);
      final item = AggregatedItem(
        id: now.itemId,
        // Uygulama genelinde sunucu kimligi baseUrl'dir (home_view_model.dart:74).
        serverId: client.baseUrl,
        rawData: Map<String, dynamic>.from(raw),
      );
      if (!mounted) return;
      await launchPlayerWhilePreparing(
        context,
        manager: manager,
        destination: Destinations.videoPlayer,
        startPlayback: (session) => runPlaybackStart(session, () async {
          await manager.playItems(
            [item],
            startPosition: Duration(seconds: now.offsetSeconds),
          );
          return true;
        }),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Yayına katılamadı: $e')));
    }
  }

  String _hhmm(DateTime? d) => d == null
      ? '--:--'
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _now;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Text(_error!));
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(48, 8, 48, 24),
        children: [
          if (now != null) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('CANLI',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Text(now.daypart, style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(now.displayTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(
              '${now.remainingSeconds ~/ 60} dk kaldı'
              '${now.nextTitle != null ? '  ·  Sırada: ${now.nextTitle}' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              autofocus: true,
              onPressed: _tuneIn,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Yayına katıl'),
            ),
            const SizedBox(height: 28),
            Text('Bugünün akışı', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
          for (final e in _grid)
            ListTile(
              dense: true,
              leading: Text(_hhmm(e.startsAt), style: theme.textTheme.bodyMedium),
              title: Text(e.displayTitle),
              subtitle: Text(e.daypart),
              trailing: now != null && e.itemId == now.itemId
                  ? const Icon(Icons.circle, color: Colors.red, size: 12)
                  : null,
            ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NavigationLayout(
        activeRoute: Destinations.dadflixChannel,
        showBackButton: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 20, 48, 0),
              child: Text('Dadflix Kanalı', style: theme.textTheme.headlineSmall),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
