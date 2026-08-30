import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:server_core/server_core.dart';

import '../ui/navigation/destinations.dart';
import '../ui/widgets/navigation_layout.dart';

/// dadflix: mac-odakli spor sayfasi.
///
/// Veri kaynagi Jellyfin'in kendi rehberi: EPG hattimiz (update_jellyfin_epg
/// + Sportarr enjeksiyonu) spor programlarini kanal-eslesmis ve IsSports
/// bayrakli uretir; burada yalnizca `/LiveTv/Programs?IsSports=true`
/// sorgulanir — ek sunucu servisi yok. Ayni mac birden cok kanalda
/// (4K/FHD varyantlari) yayinlanir; ada+saate gore gruplanir, tiklamada
/// tek kanal dogrudan acilir, coklu kanalda secim sorulur.
class DadflixSportsScreen extends StatefulWidget {
  const DadflixSportsScreen({super.key});

  @override
  State<DadflixSportsScreen> createState() => _DadflixSportsScreenState();
}

class _SportsMatch {
  final String name;
  final DateTime? start;
  final DateTime? end;
  final List<({String channelId, String channelName})> channels;

  _SportsMatch({
    required this.name,
    required this.start,
    required this.end,
    required this.channels,
  });

  bool get isLive {
    final now = DateTime.now();
    return start != null &&
        end != null &&
        now.isAfter(start!) &&
        now.isBefore(end!);
  }
}

class _DadflixSportsScreenState extends State<DadflixSportsScreen> {
  List<_SportsMatch>? _matches;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = GetIt.instance<MediaServerClient>();
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final now = DateTime.now().toUtc();
      final res = await dio.get<Map<String, dynamic>>(
        '${client.baseUrl}/LiveTv/Programs',
        queryParameters: {
          'IsSports': true,
          'UserId': client.userId,
          'MinEndDate': now.toIso8601String(),
          'MaxStartDate':
              now.add(const Duration(hours: 36)).toIso8601String(),
          'SortBy': 'StartDate',
          // Saglayici EPG'si spor kanallarina kanal-adi DOLGU programlari basar
          // (4 saatlik bloklar); Jellyfin bunlari kanal grubundan IsSports sayar
          // ve 36 saatlik pencerede ~1500 kayit olusur. 400 limitinde liste ilk
          // ~9 saatte doluyor, aksam maclari DISARIDA kaliyordu (2026-08-30:
          // 6 gercek mac 730-851. siralardaydi). Dolgular sunucuda temizlenemez
          // (kategori tasimiyorlar), bu yuzden pencerenin tamamini cekiyoruz;
          // ayiklama zaten istemcide yapiliyor.
          'Limit': 2500,
          'EnableImages': false,
          'EnableUserData': false,
        },
        options: Options(
          headers: {
            'Authorization':
                'MediaBrowser Token="${client.accessToken}"',
          },
        ),
      );
      final items = (res.data?['Items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          // Mac gibi gorunenler: Sportarr'in ⚽ isaretlileri + gercek EPG'deki
          // "Takim A - Takim B" / "A vs B" kaliplari. Dolgu programlar
          // (Tanitim, kanal jenerikleri) bu kaliba uymaz ve elenir.
          .where((p) {
            final n = (p['Name'] as String? ?? '');
            // Kanal-adi dolgusu (program adi == kanal adi) mac degildir.
            if (n == (p['ChannelName'] as String? ?? '')) return false;
            return n.contains('⚽') ||
                n.contains(' vs ') ||
                RegExp(r'\S\s-\s\S').hasMatch(n);
          })
          .toList();
      final grouped = <String, _SportsMatch>{};
      for (final p in items) {
        final name = (p['Name'] as String? ?? '').trim();
        final startRaw = p['StartDate'] as String?;
        final key = '$name|$startRaw';
        final start = startRaw == null
            ? null
            : DateTime.tryParse(startRaw)?.toLocal();
        final end = (p['EndDate'] as String?) == null
            ? null
            : DateTime.tryParse(p['EndDate'] as String)?.toLocal();
        final channel = (
          channelId: p['ChannelId'] as String? ?? '',
          channelName: p['ChannelName'] as String? ?? 'Kanal',
        );
        final existing = grouped[key];
        if (existing == null) {
          grouped[key] = _SportsMatch(
            name: name,
            start: start,
            end: end,
            channels: [channel],
          );
        } else if (channel.channelId.isNotEmpty) {
          existing.channels.add(channel);
        }
      }
      if (!mounted) return;
      setState(() => _matches = grouped.values.toList());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Maçlar yüklenemedi: $e');
    }
  }

  Future<void> _open(_SportsMatch match) async {
    final channels =
        match.channels.where((c) => c.channelId.isNotEmpty).toList();
    if (channels.isEmpty) return;
    String channelId = channels.first.channelId;
    if (channels.length > 1) {
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Kanal seç'),
          children: [
            for (final c in channels)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(c.channelId),
                child: Text(c.channelName),
              ),
          ],
        ),
      );
      if (picked == null) return;
      channelId = picked;
    }
    if (!mounted) return;
    await context.push(Destinations.liveTvChannel(channelId));
  }

  String _timeLabel(_SportsMatch m) {
    final s = m.start;
    if (s == null) return '';
    final today = DateTime.now();
    final sameDay = s.day == today.day && s.month == today.month;
    final hh = s.hour.toString().padLeft(2, '0');
    final mm = s.minute.toString().padLeft(2, '0');
    return sameDay ? '$hh:$mm' : 'Yarın $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (_error != null) {
      body = Center(child: Text(_error!));
    } else if (_matches == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_matches!.isEmpty) {
      body = const Center(
        child: Text('Önümüzdeki 36 saatte planlı maç görünmüyor.'),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
        itemCount: _matches!.length,
        itemBuilder: (context, i) {
          final m = _matches![i];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              autofocus: i == 0,
              leading: m.isLive
                  ? const Icon(Icons.circle, color: Colors.red, size: 14)
                  : const Icon(Icons.schedule, size: 18),
              title: Text(m.name),
              subtitle: Text(
                '${_timeLabel(m)} · ${m.channels.length} kanal'
                '${m.isLive ? ' · CANLI' : ''}',
              ),
              trailing: const Icon(Icons.play_arrow_rounded),
              onTap: () => _open(m),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NavigationLayout(
        activeRoute: Destinations.dadflixSports,
        showBackButton: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 24, 48, 0),
              child: Text('Spor', style: theme.textTheme.headlineMedium),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
