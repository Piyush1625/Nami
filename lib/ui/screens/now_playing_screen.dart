import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../core/services/player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/user_data_service.dart';
import '../widgets/artwork_widget.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showLyrics = false;

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final userData = context.watch<UserDataService>();
    final settings = context.watch<SettingsService>();
    final track = player.currentTrack;
    final scheme = Theme.of(context).colorScheme;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing')),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_showLyrics ? 'Lyrics' : 'Now Playing'),
        actions: [
          IconButton(
            tooltip: 'Lyrics',
            icon: Icon(_showLyrics ? Icons.album_outlined : Icons.lyrics_outlined),
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
          ),
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => _openQueueSheet(context, player),
          ),
          IconButton(
            tooltip: 'Equalizer & Audio',
            icon: const Icon(Icons.equalizer_rounded),
            onPressed: () => _openAudioSheet(context, player),
          ),
          IconButton(
            tooltip: 'Sleep Timer',
            icon: const Icon(Icons.bedtime_outlined),
            onPressed: () => _openSleepSheet(context, player),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: settings.amoledBlack
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.primary.withValues(alpha: 0.22),
                    Colors.black,
                    Colors.black,
                  ],
                )
              : null,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              children: [
                Expanded(
                  child: _showLyrics
                      ? _LyricsView(player: player)
                      : Center(
                          child: Hero(
                            tag: 'art_${track.id}',
                            child: ArtworkWidget(
                              trackId: track.id,
                              size: 290,
                              borderRadius: 24,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${track.artist} • ${track.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        userData.isFavorite(track.id)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: userData.isFavorite(track.id) ? scheme.primary : null,
                      ),
                      onPressed: () => userData.toggleFavorite(track.id),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (context, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final total = track.duration.inMilliseconds > 0
                        ? track.duration
                        : const Duration(seconds: 1);
                    final sliderVal = pos.inMilliseconds
                        .clamp(0, total.inMilliseconds)
                        .toDouble();
                    return Column(
                      children: [
                        Slider(
                          value: sliderVal,
                          max: total.inMilliseconds.toDouble(),
                          onChanged: (v) =>
                              player.seek(Duration(milliseconds: v.round())),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(pos)),
                            if (settings.bitPerfectUsbDac)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: scheme.primary.withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  'USB DAC BIT-PERFECT',
                                  style: TextStyle(
                                      fontSize: 10, color: scheme.primary),
                                ),
                              ),
                            Text(_fmt(track.duration)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.shuffle_rounded,
                        color: player.shuffleEnabled ? scheme.primary : null,
                      ),
                      onPressed: player.toggleShuffle,
                    ),
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: player.previous,
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(18),
                      ),
                      onPressed: player.togglePlayPause,
                      child: Icon(
                        player.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                      ),
                    ),
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: player.next,
                    ),
                    IconButton(
                      icon: Icon(
                        player.loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        color: player.loopMode != LoopMode.off
                            ? scheme.primary
                            : null,
                      ),
                      onPressed: player.cycleLoopMode,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openQueueSheet(BuildContext context, PlayerService player) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Consumer<PlayerService>(
        builder: (context, p, _) {
          final entries = p.queueEntries;
          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: entries.length,
            // ignore: deprecated_member_use
            onReorder: p.reorderQueue,
            itemBuilder: (context, i) {
              final e = entries[i];
              final isCurrent = i == p.currentIndex;
              return ListTile(
                key: ValueKey(e.uid),
                selected: isCurrent,
                leading: ArtworkWidget(trackId: e.track.id, size: 40),
                title: Text(e.track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(e.track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => p.removeQueueAt(i),
                ),
                onTap: () => p.skipToQueueIndex(i),
              );
            },
          );
        },
      ),
    );
  }

  void _openAudioSheet(BuildContext context, PlayerService player) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Playback Speed (${player.speed.toStringAsFixed(2)}x)',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: player.speed,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              label: '${player.speed.toStringAsFixed(2)}x',
              onChanged: player.setSpeed,
            ),
            const SizedBox(height: 8),
            Text('Loudness Boost', style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 8,
              children: [
                for (final db in [0.0, 3.0, 6.0, 10.0])
                  ActionChip(
                    label: Text(db == 0 ? 'Off' : '+${db.toInt()} dB'),
                    onPressed: () => player.setLoudnessGain(db),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Lyric Timestamp Offset', style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('-0.5s'),
                  onPressed: () => player.shiftCurrentLyrics(-500),
                ),
                ActionChip(
                  label: const Text('+0.5s'),
                  onPressed: () => player.shiftCurrentLyrics(500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openSleepSheet(BuildContext context, PlayerService player) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ActionChip(
              label: const Text('Off'),
              onPressed: () {
                player.setSleepTimer(null);
                Navigator.pop(context);
              },
            ),
            for (final min in [15, 30, 45, 60])
              ActionChip(
                label: Text('$min min'),
                onPressed: () {
                  player.setSleepTimer(Duration(minutes: min));
                  Navigator.pop(context);
                },
              ),
            ActionChip(
              label: const Text('End of current track'),
              onPressed: () {
                player.setSleepTimer(null, finishCurrentTrack: true);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsView extends StatelessWidget {
  const _LyricsView({required this.player});
  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final lyrics = player.currentLyrics;
    final scheme = Theme.of(context).colorScheme;
    if (lyrics.isEmpty) {
      return const Center(
        child: Text('No synced .lrc or embedded lyrics found for this track.'),
      );
    }
    if (!lyrics.isSynced) {
      return SingleChildScrollView(
        child: Text(lyrics.plain, textAlign: TextAlign.center),
      );
    }
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final activeIdx = lyrics.indexAt(pos);
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: ListView.builder(
              itemCount: lyrics.synced.length,
              itemBuilder: (context, i) {
                final line = lyrics.synced[i];
                final active = i == activeIdx;
                return ListTile(
                  onTap: () => player.seek(line.time),
                  title: Text(
                    line.text.isEmpty ? '♪' : line.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: active ? 20 : 15,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
