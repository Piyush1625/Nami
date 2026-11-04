import 'package:flutter/material.dart';

import '../core/models/track.dart';
import 'extension_api.dart';

class MorningMixExtension extends NamiExtension {
  const MorningMixExtension();

  @override
  String get id => 'morning_mix';

  @override
  String get name => 'Morning Mix';

  @override
  String get description =>
      'Adds a Home card in the morning that plays the songs you usually '
      'listen to at that time of day.';

  static bool _isMorning(DateTime now) => now.hour >= 4 && now.hour < 12;

  List<Track> buildMix(ExtensionContext context, {int size = 40}) {
    final counts = <int, int>{};
    for (final entry in context.userData.history) {
      final hour = entry.playedAt.hour;
      if (hour >= 5 && hour < 12) {
        counts[entry.trackId] = (counts[entry.trackId] ?? 0) + 1;
      }
    }

    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ids = <int>[for (final e in ranked.take(size)) e.key];

    for (final favorite in context.userData.favorites) {
      if (ids.length >= size) break;
      if (!ids.contains(favorite)) ids.add(favorite);
    }

    final tracks = context.library.tracksForIds(ids);
    if (tracks.isEmpty) {
      final all = List<Track>.of(context.library.tracks)..shuffle();
      return all.take(30).toList();
    }
    return tracks..shuffle();
  }

  @override
  Widget? buildHomeCard(BuildContext context, ExtensionContext extension) {
    if (!_isMorning(DateTime.now())) return null;
    if (extension.library.tracks.isEmpty) return null;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ListTile(
        leading: const Icon(Icons.wb_sunny_outlined),
        title: const Text('Good morning'),
        subtitle: const Text('Start the day with your Morning Mix'),
        trailing: IconButton.filled(
          tooltip: 'Play Morning Mix',
          icon: const Icon(Icons.play_arrow),
          onPressed: () {
            final mix = buildMix(extension);
            extension.player.playTracks(mix);
          },
        ),
      ),
    );
  }
}
