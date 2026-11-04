class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({this.synced = const [], this.plain = ''});

  final List<LyricLine> synced;
  final String plain;

  bool get isSynced => synced.isNotEmpty;
  bool get isEmpty => synced.isEmpty && plain.trim().isEmpty;

  int indexAt(Duration position) {
    var lo = 0;
    var hi = synced.length - 1;
    var result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (synced[mid].time <= position) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  static Lyrics parseLrc(String source) {
    final stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final lines = <LyricLine>[];

    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final matches = stamp.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.substring(matches.last.end).trim();
      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final fraction = m.group(3);
        var millis = 0;
        if (fraction != null) {
          millis = int.parse(fraction.padRight(3, '0').substring(0, 3));
        }
        lines.add(LyricLine(
          Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
          text,
        ));
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    if (lines.isEmpty) {
      return Lyrics(plain: source.trim());
    }
    return Lyrics(synced: lines);
  }
}
