import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/track.dart';

class SavedQueue {
  const SavedQueue({
    required this.trackIds,
    required this.index,
    required this.positionMs,
  });

  final List<int> trackIds;
  final int index;
  final int positionMs;
}

class UserDataService extends ChangeNotifier {
  UserDataService(this._prefs) {
    _load();
  }

  static const _kFavorites = 'nami.favorites';
  static const _kPlaylists = 'nami.playlists';
  static const _kPlayCounts = 'nami.playCounts';
  static const _kHistory = 'nami.history';
  static const _kQueue = 'nami.queue';
  static const maxHistory = 3000;

  final SharedPreferences _prefs;

  final Set<int> _favorites = <int>{};
  final List<Playlist> _playlists = <Playlist>[];
  final Map<int, int> _playCounts = <int, int>{};
  final List<HistoryEntry> _history = <HistoryEntry>[];

  Set<int> get favorites => Set.unmodifiable(_favorites);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<HistoryEntry> get history => List.unmodifiable(_history);
  Map<int, int> get playCounts => Map.unmodifiable(_playCounts);

  void _load() {
    try {
      final fav = _prefs.getString(_kFavorites);
      if (fav != null) {
        _favorites.addAll((jsonDecode(fav) as List).map((e) => e as int));
      }

      final pl = _prefs.getString(_kPlaylists);
      if (pl != null) {
        _playlists.addAll((jsonDecode(pl) as List).map(
            (e) => Playlist.fromJson(Map<String, dynamic>.from(e as Map))));
      }

      final counts = _prefs.getString(_kPlayCounts);
      if (counts != null) {
        (jsonDecode(counts) as Map).forEach((key, value) {
          _playCounts[int.parse(key as String)] = value as int;
        });
      }

      final hist = _prefs.getString(_kHistory);
      if (hist != null) {
        _history.addAll((jsonDecode(hist) as List).map(
            (e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map))));
      }
    } catch (e) {
      debugPrint('UserDataService load error: $e');
    }
  }

  bool isFavorite(int trackId) => _favorites.contains(trackId);

  Future<void> toggleFavorite(int trackId) async {
    if (!_favorites.remove(trackId)) {
      _favorites.add(trackId);
    }
    notifyListeners();
    await _prefs.setString(_kFavorites, jsonEncode(_favorites.toList()));
  }

  Future<Playlist> createPlaylist(String name, {List<int>? initialTracks}) async {
    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Untitled Playlist' : name.trim(),
      trackIds: initialTracks != null ? List<int>.of(initialTracks) : <int>[],
    );
    _playlists.add(playlist);
    notifyListeners();
    await _savePlaylists();
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    await _savePlaylists();
  }

  Future<void> addTrackToPlaylist(String playlistId, int trackId) async {
    final pl = _playlists.where((p) => p.id == playlistId).firstOrNull;
    if (pl == null) return;
    if (!pl.trackIds.contains(trackId)) {
      pl.trackIds.add(trackId);
      notifyListeners();
      await _savePlaylists();
    }
  }

  Future<void> _savePlaylists() async {
    await _prefs.setString(
      _kPlaylists,
      jsonEncode(_playlists.map((p) => p.toJson()).toList()),
    );
  }

  int playCountOf(int trackId) => _playCounts[trackId] ?? 0;

  Future<void> recordPlay(int trackId) async {
    _playCounts[trackId] = (_playCounts[trackId] ?? 0) + 1;
    _history.insert(
      0,
      HistoryEntry(trackId: trackId, playedAt: DateTime.now()),
    );
    if (_history.length > maxHistory) {
      _history.removeRange(maxHistory, _history.length);
    }
    notifyListeners();
    await _prefs.setString(
      _kPlayCounts,
      jsonEncode(_playCounts.map((k, v) => MapEntry(k.toString(), v))),
    );
    await _prefs.setString(
      _kHistory,
      jsonEncode(_history.map((e) => e.toJson()).toList()),
    );
  }

  SavedQueue? loadSavedQueue() {
    try {
      final raw = _prefs.getString(_kQueue);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SavedQueue(
        trackIds: (j['ids'] as List).map((e) => e as int).toList(),
        index: (j['idx'] as int?) ?? 0,
        positionMs: (j['pos'] as int?) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveQueue({
    required List<int> trackIds,
    required int index,
    required int positionMs,
  }) async {
    await _prefs.setString(
      _kQueue,
      jsonEncode({'ids': trackIds, 'idx': index, 'pos': positionMs}),
    );
  }

  String exportBackupJson() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'favorites': _favorites.toList(),
      'playlists': _playlists.map((p) => p.toJson()).toList(),
      'playCounts': _playCounts.map((k, v) => MapEntry(k.toString(), v)),
      'history': _history.map((h) => h.toJson()).toList(),
    });
  }
}
