import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/track.dart';
import 'player_service.dart';

class AccentService extends ChangeNotifier {
  AccentService(this._player) {
    _sub = _player.onTrackChanged.listen(_update);
  }

  final PlayerService _player;
  final OnAudioQuery _query = OnAudioQuery();
  late final StreamSubscription<Track> _sub;
  int? _forTrackId;
  bool _disposed = false;

  Color? color;

  Future<void> refreshForCurrent() async {
    final track = _player.currentTrack;
    if (track != null) await _update(track);
  }

  Future<void> _update(Track track) async {
    if (_forTrackId == track.id) return;
    _forTrackId = track.id;

    Color? next;
    try {
      final bytes = await _query.queryArtwork(
        track.id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 96,
        quality: 70,
      );
      if (bytes != null && bytes.isNotEmpty) {
        next = await dominantColor(bytes);
      }
    } catch (e) {
      debugPrint('AccentService: could not read artwork: $e');
    }

    if (_disposed || _forTrackId != track.id) return;
    if (next != color) {
      color = next;
      notifyListeners();
    }
  }

  static Future<Color?> dominantColor(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 32,
      targetHeight: 32,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;

    const buckets = 36;
    final weight = List<double>.filled(buckets, 0);
    final sumR = List<double>.filled(buckets, 0);
    final sumG = List<double>.filled(buckets, 0);
    final sumB = List<double>.filled(buckets, 0);

    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final r = data.getUint8(i);
      final g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      final a = data.getUint8(i + 3);
      if (a < 128) continue;

      final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
      if (hsv.value < 0.2 || hsv.saturation < 0.25) continue;

      final w = hsv.saturation * hsv.value;
      final bucket = (hsv.hue / 360 * buckets).floor().clamp(0, buckets - 1).toInt();
      weight[bucket] += w;
      sumR[bucket] += r * w;
      sumG[bucket] += g * w;
      sumB[bucket] += b * w;
    }

    var best = 0;
    for (var i = 1; i < buckets; i++) {
      if (weight[i] > weight[best]) best = i;
    }
    if (weight[best] <= 0) return null;

    final w = weight[best];
    return Color.fromARGB(
      255,
      (sumR[best] / w).round().clamp(0, 255),
      (sumG[best] / w).round().clamp(0, 255),
      (sumB[best] / w).round().clamp(0, 255),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    super.dispose();
  }
}
