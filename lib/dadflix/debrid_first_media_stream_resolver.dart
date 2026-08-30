import 'package:playback_core/playback_core.dart';

import '../data/models/aggregated_item.dart';

/// dadflix: `serverId == 'debrid'` olan sentetik item'lari, rawData'ya
/// onceden gomulmus debrid URL'inden oynatir; diger her seyi sarilan
/// resolver'a aynen devreder.
///
/// Desen `LocalFirstMediaStreamResolver` ile birebir ayni: her oynatma
/// girisi `PlaybackManager._playCurrentItem -> resolver.resolve(item)`
/// uzerinden aktigi icin burada sarmalamak tum giris noktalarini kapsar.
/// API cagrisi burada YAPILMAZ — buton `POST /api/discover/play`'i cagirir
/// ve sonucu `DadflixStreamUrl` / `DadflixSubtitleUrl` olarak item'a gomer;
/// boylece resolver deterministik ve ag-bagimsiz kalir.
class DebridFirstMediaStreamResolver extends MediaStreamResolver {
  final MediaStreamResolver _inner;

  DebridFirstMediaStreamResolver({required MediaStreamResolver inner})
      : _inner = inner;

  static String? _containerOf(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    final ext = path.substring(dot + 1).toLowerCase();
    if (ext.length > 4) return null;
    return ext;
  }

  @override
  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  }) async {
    if (mediaItem is AggregatedItem && mediaItem.serverId == 'debrid') {
      final url = mediaItem.rawData['DadflixStreamUrl'] as String?;
      if (url == null || url.isEmpty) {
        throw StateError('Debrid stream URL missing from item');
      }
      final subUrl = mediaItem.rawData['DadflixSubtitleUrl'] as String?;
      final subs = <ExternalSubtitle>[
        if (subUrl != null && subUrl.isNotEmpty)
          ExternalSubtitle(
            deliveryUrl: subUrl,
            title: 'Türkçe',
            language: 'tur',
            codec: 'vtt',
            isDefault: true,
            streamIndex: 1,
          ),
      ];
      return StreamResolutionResult(
        streamUrl: url,
        mediaSourceId: mediaItem.id,
        playMethod: StreamPlayMethod.directPlay,
        container: _containerOf(url),
        externalSubtitles: subs,
        mediaStreams: [
          for (final s in subs)
            {
              'Type': 'Subtitle',
              'Index': s.streamIndex,
              'IsExternal': true,
              'Codec': s.codec,
              'Language': s.language,
              'DisplayTitle': 'Türkçe',
              'IsDefault': true,
            },
        ],
        // "local" degil ama dort tuketicisi de debrid icin dogru davranisi
        // veriyor: rapor hatalari yutulur, sunucu transcode fallback kapanir.
        isLocalMedia: true,
      );
    }
    return _inner.resolve(
      mediaItem,
      deviceProfile: deviceProfile,
      maxStreamingBitrate: maxStreamingBitrate,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      startTimeTicks: startTimeTicks,
      mediaSourceId: mediaSourceId,
      enableDirectPlay: enableDirectPlay,
      enableDirectStream: enableDirectStream,
      enableTranscoding: enableTranscoding,
    );
  }
}
