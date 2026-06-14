class WatchStream {
  const WatchStream({required this.url, this.quality, this.headers});

  final String url;
  final String? quality;
  final Map<String, String>? headers;

  factory WatchStream.fromMap(Map<String, dynamic> map) => WatchStream(
    url: (map['url'] as String?) ?? '',
    quality: map['quality'] as String?,
    headers: (map['headers'] as Map?)?.cast<String, String>(),
  );
}

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

class WatchData {
  const WatchData({required this.streams, this.subtitles = const []});

  final List<WatchStream> streams;
  final List<WatchSubtitle> subtitles;

  bool get hasMultipleQualities => streams.length > 1;

  factory WatchData.fromMap(Map<String, dynamic> map) {
    final rawStreams = map['streams'] as List? ?? [];
    final rawSubs = map['subtitles'] as List? ?? [];
    return WatchData(
      streams: rawStreams
          .whereType<Map>()
          .map((s) => WatchStream.fromMap(s.cast<String, dynamic>()))
          .toList(),
      subtitles: rawSubs
          .whereType<Map>()
          .map((s) => WatchSubtitle.fromMap(s.cast<String, dynamic>()))
          .toList(),
    );
  }
}
