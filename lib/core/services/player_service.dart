import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/lyrics.dart';
import '../models/track.dart';
import 'library_service.dart';
import 'lyrics_service.dart';
import 'user_data_service.dart';

class QueueEntry {
  QueueEntry(this.track) : uid = '${track.id}_${_counter++}';
  static int _counter = 0;

  final String uid;
  final Track track;
}

class PlayerService extends ChangeNotifier {
  PlayerService({
    required this.library,
    required this.userData,
    required this.lyricsService,
  }) {
    _init();
  }

  final LibraryService library;
  final UserDataService userData;
  final LyricsService lyricsService;

  late final AudioPlayer _player;
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer _loudness = AndroidLoudnessEnhancer();

  final StreamController<Track> _trackChangedController =
      StreamController<Track>.broadcast();
  final StreamController<Track> _trackPlayedController =
      StreamController<Track>.broadcast();

  Stream<Track> get onTrackChanged => _trackChangedController.stream;
  Stream<Track> get onTrackPlayed => _trackPlayedController.stream;

  final List<QueueEntry> _entries = [];
  int _currentIndex = 0;
  Lyrics _currentLyrics = const Lyrics();
  bool _pauseAtTrackEnd = false;
  Timer? _sleepTimer;
  DateTime? _sleepUntil;

  Future<void> _queueLock = Future<void>.value();

  int? _listeningTrackId;
  int _accumulatedListenMs = 0;
  int _lastPositionMs = 0;
  bool _countedCurrentPlay = false;

  List<QueueEntry> get queueEntries => List.unmodifiable(_entries);
  List<Track> get queue => List.unmodifiable(_entries.map((e) => e.track));
  int get currentIndex => _currentIndex;
  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _entries.length)
          ? _entries[_currentIndex].track
          : null;
  Lyrics get currentLyrics => _currentLyrics;

  bool get isPlaying => _player.playing;
  bool get shuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;
  double get speed => _player.speed;
  DateTime? get sleepUntil => _sleepUntil;
  bool get pauseAtTrackEnd => _pauseAtTrackEnd;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  AndroidEqualizer get equalizer => _equalizer;
  AndroidLoudnessEnhancer get loudness => _loudness;

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final prev = _queueLock;
    final completer = Completer<void>();
    _queueLock = completer.future;
    return prev.then((_) => action()).whenComplete(completer.complete);
  }

  Future<void> _init() async {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: Platform.isAndroid ? [_equalizer, _loudness] : [],
      ),
    );

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.currentIndexStream.listen((idx) async {
      if (idx == null || idx < 0 || idx >= _entries.length) return;
      final changed = _currentIndex != idx;
      _currentIndex = idx;
      final track = _entries[idx].track;
      if (changed) {
        _resetListenTracker(track);
        if (_pauseAtTrackEnd) {
          _pauseAtTrackEnd = false;
          await _player.pause();
        }
        _trackChangedController.add(track);
      }
      _currentLyrics = await lyricsService.loadFor(track);
      unawaited(_persistQueue());
      notifyListeners();
    });

    _player.positionStream.listen((pos) {
      final track = currentTrack;
      if (track == null || !_player.playing) {
        _lastPositionMs = pos.inMilliseconds;
        return;
      }
      if (_listeningTrackId != track.id) {
        _resetListenTracker(track);
      }
      final delta = pos.inMilliseconds - _lastPositionMs;
      _lastPositionMs = pos.inMilliseconds;
      if (delta > 0 && delta < 2500) {
        _accumulatedListenMs += delta;
        final thresholdMs = (track.durationMs > 0 && track.durationMs < 30000)
            ? (track.durationMs ~/ 2)
            : 15000;
        if (!_countedCurrentPlay && _accumulatedListenMs >= thresholdMs) {
          _countedCurrentPlay = true;
          unawaited(userData.recordPlay(track.id));
          _trackPlayedController.add(track);
        }
      }
    });

    _player.playerStateStream.listen((_) => notifyListeners());
    _player.shuffleModeEnabledStream.listen((_) => notifyListeners());
    _player.loopModeStream.listen((_) => notifyListeners());
  }

  void _resetListenTracker(Track track) {
    _listeningTrackId = track.id;
    _accumulatedListenMs = 0;
    _lastPositionMs = 0;
    _countedCurrentPlay = false;
  }

  Future<void> shiftCurrentLyrics(int offsetMs) async {
    final track = currentTrack;
    if (track == null) return;
    _currentLyrics = await lyricsService.shiftLyrics(track, offsetMs);
    notifyListeners();
  }

  Future<void> restoreSavedQueue() async {
    final saved = userData.loadSavedQueue();
    if (saved == null || saved.trackIds.isEmpty) return;
    final restored = library.tracksForIds(saved.trackIds);
    if (restored.isEmpty) return;
    await playTracks(
      restored,
      startIndex: saved.index.clamp(0, restored.length - 1),
      autoPlay: false,
      initialPosition: Duration(milliseconds: saved.positionMs),
    );
  }

  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    bool autoPlay = true,
    Duration initialPosition = Duration.zero,
  }) =>
      _synchronized(() async {
        if (tracks.isEmpty) return;
        _entries
          ..clear()
          ..addAll(tracks.map(QueueEntry.new));
        _currentIndex = startIndex.clamp(0, _entries.length - 1);

        final children = _entries.map(_toAudioSource).toList();
        await _player.setAudioSources(
          children,
          initialIndex: _currentIndex,
          initialPosition: initialPosition,
        );

        final active = currentTrack;
        if (active != null) {
          _resetListenTracker(active);
          _trackChangedController.add(active);
          _currentLyrics = await lyricsService.loadFor(active);
        }

        notifyListeners();
        if (autoPlay) {
          unawaited(_player.play());
        }
        unawaited(_persistQueue());
      });

  Future<void> playNext(Track track) => _synchronized(() async {
        if (_entries.isEmpty) {
          await playTracks([track]);
          return;
        }
        final insertIdx = (_currentIndex + 1).clamp(0, _entries.length);
        final entry = QueueEntry(track);
        _entries.insert(insertIdx, entry);
        await _player.insertAudioSource(insertIdx, _toAudioSource(entry));
        notifyListeners();
        unawaited(_persistQueue());
      });

  Future<void> addToQueue(Track track) => _synchronized(() async {
        if (_entries.isEmpty) {
          await playTracks([track]);
          return;
        }
        final entry = QueueEntry(track);
        _entries.add(entry);
        await _player.addAudioSource(_toAudioSource(entry));
        notifyListeners();
        unawaited(_persistQueue());
      });

  Future<void> removeQueueAt(int index) => _synchronized(() async {
        if (index < 0 || index >= _entries.length) return;
        if (_entries.length == 1) {
          await _player.stop();
          _entries.clear();
          _currentIndex = 0;
          notifyListeners();
          return;
        }
        _entries.removeAt(index);
        if (index < _currentIndex) {
          _currentIndex--;
        } else if (index == _currentIndex && _currentIndex >= _entries.length) {
          _currentIndex = _entries.length - 1;
        }
        await _player.removeAudioSourceAt(index);
        notifyListeners();
        unawaited(_persistQueue());
      });

  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      _synchronized(() async {
        if (oldIndex < 0 || oldIndex >= _entries.length) return;
        if (newIndex > oldIndex) newIndex -= 1;
        newIndex = newIndex.clamp(0, _entries.length - 1);
        if (oldIndex == newIndex) return;

        final item = _entries.removeAt(oldIndex);
        _entries.insert(newIndex, item);

        if (_currentIndex == oldIndex) {
          _currentIndex = newIndex;
        } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
          _currentIndex--;
        } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
          _currentIndex++;
        }

        await _player.moveAudioSource(oldIndex, newIndex);
        notifyListeners();
        unawaited(_persistQueue());
      });

  AudioSource _toAudioSource(QueueEntry entry) {
    final t = entry.track;
    return AudioSource.file(
      t.path,
      tag: MediaItem(
        id: entry.uid,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.duration,
        artUri: t.artUri,
      ),
    );
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> next() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  Future<void> previous() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= _entries.length) return;
    await _player.seek(Duration.zero, index: index);
    if (!_player.playing) await _player.play();
  }

  Future<void> toggleShuffle() async {
    final next = !_player.shuffleModeEnabled;
    if (next) await _player.shuffle();
    await _player.setShuffleModeEnabled(next);
    notifyListeners();
  }

  Future<void> cycleLoopMode() async {
    final next = switch (_player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(next);
    notifyListeners();
  }

  Future<void> setSpeed(double value) async {
    await _player.setSpeed(value.clamp(0.5, 2.0));
    notifyListeners();
  }

  Future<void> setLoudnessGain(double targetGainDb) async {
    if (!Platform.isAndroid) return;
    await _loudness.setEnabled(targetGainDb > 0);
    await _loudness.setTargetGain(targetGainDb);
    notifyListeners();
  }

  void setSleepTimer(Duration? duration, {bool finishCurrentTrack = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepUntil = null;
    _pauseAtTrackEnd = finishCurrentTrack;

    if (duration != null && duration > Duration.zero) {
      _sleepUntil = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () {
        if (_pauseAtTrackEnd) return;
        _player.pause();
        _sleepUntil = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> _persistQueue() async {
    if (_entries.isEmpty) return;
    await userData.saveQueue(
      trackIds: _entries.map((e) => e.track.id).toList(),
      index: _currentIndex,
      positionMs: _player.position.inMilliseconds,
    );
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _trackChangedController.close();
    _trackPlayedController.close();
    _player.dispose();
    super.dispose();
  }
}
