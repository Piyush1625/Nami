import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

class ArtworkWidget extends StatelessWidget {
  const ArtworkWidget({
    super.key,
    required this.trackId,
    this.size = 48,
    this.borderRadius = 10,
  });

  final int trackId;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: QueryArtworkWidget(
          id: trackId,
          type: ArtworkType.AUDIO,
          artworkWidth: size,
          artworkHeight: size,
          artworkFit: BoxFit.cover,
          keepOldArtwork: true,
          nullArtworkWidget: Container(
            width: size,
            height: size,
            color: scheme.surfaceContainerHigh,
            child: Icon(
              Icons.music_note_rounded,
              color: scheme.primary,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
