/// Equivale a PrismStream del contrato Prism+.
class WatchStream {
  const WatchStream({
    required this.url,
    this.quality,
    this.label,
    this.headers,
    this.mimeType,
  });

  final String url;
  final String? quality;
  final String? label;
  final Map<String, String>? headers;
  final String? mimeType;

  String get displayLabel => label ?? quality ?? url;

  factory WatchStream.fromMap(Map<String, dynamic> map) => WatchStream(
    url: (map['url'] as String?) ?? '',
    quality: map['quality'] as String?,
    label: map['label'] as String?,
    headers: _parseHeaders(map['headers']),
    mimeType: map['mimeType'] as String?,
  );

  static Map<String, String>? _parseHeaders(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    return {
      for (final e in raw.entries) e.key.toString(): e.value?.toString() ?? '',
    };
  }
}

/// Equivale a PrismSubtitle del contrato Prism+.
class WatchSubtitle {
  const WatchSubtitle({required this.label, required this.url, this.lang});

  final String label;
  final String url;
  final String? lang;

  factory WatchSubtitle.fromMap(Map<String, dynamic> map) => WatchSubtitle(
    label: (map['label'] as String?) ?? '',
    url: (map['url'] as String?) ?? '',
    lang: map['lang'] as String?,
  );
}

/// Equivale a PrismWatch del contrato Prism+.
class WatchData {
  const WatchData({
    required this.streams,
    this.subtitles = const [],
    this.headers,
    this.reason,
  });

  final List<WatchStream> streams;
  final List<WatchSubtitle> subtitles;

  /// Headers globales aplicados a todos los streams.
  final Map<String, String>? headers;

  /// Razón por la que streams está vacío (premium_required, region_blocked, etc.).
  final String? reason;

  bool get hasMultipleQualities => streams.length > 1;

  factory WatchData.fromMap(Map<String, dynamic> map) {
    final globalHeaders = WatchStream._parseHeaders(map['headers']);
    final rawStreams = map['streams'] as List? ?? [];
    final rawSubs = map['subtitles'] as List? ?? [];
    return WatchData(
      streams: rawStreams.whereType<Map>().map((s) {
        final sm = s.cast<String, dynamic>();
        final merged = <String, String>{
          ...?globalHeaders,
          ...?(sm['headers'] as Map?)?.cast<String, String>(),
        };
        return WatchStream.fromMap({
          ...sm,
          if (merged.isNotEmpty) 'headers': merged,
        });
      }).toList(),
      subtitles: rawSubs
          .whereType<Map>()
          .map((s) => WatchSubtitle.fromMap(s.cast<String, dynamic>()))
          .toList(),
      headers: globalHeaders,
      reason: map['reason'] as String?,
    );
  }
}
