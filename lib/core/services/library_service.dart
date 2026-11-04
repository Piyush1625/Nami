import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/track.dart';

enum TrackSort { title, artist, album, dateAdded, duration }

class TrackGroup {
  const TrackGroup({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.tracks,
  });

  final String key;
  final String title;
  final String subtitle;
  final List<Track> tracks;

  Track get cover => tracks.first;

  Duration get totalDuration => tracks.fold(
        Duration.zero,
        (sum, t) => sum + t.duration,
      );
}

class SearchResults {
  const SearchResults({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
  });

  final List<Track> tracks;
  final List<TrackGroup> albums;
  final List<TrackGroup> artists;

  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}

class LibraryService extends ChangeNotifier {
  final OnAudioQuery _query = OnAudioQuery();

  static final RegExp _artistSplitPattern = RegExp(
    r'\s*(?:;|,|\bfeat\.?|\bft\.?|\s/\s)\s*',
    caseSensitive: false,
  );

  static List<String> splitArtists(String rawArtist) {
    final parts = rawArtist
        .split(_artistSplitPattern)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? [rawArtist] : parts;
  }

  bool scanning = false;
  bool permissionDenied = false;
  String? error;

  List<Track> _tracks = const [];
  Map<int, Track> _byId = const {};
  List<TrackGroup> _albums = const [];
  List<TrackGroup> _artists = const [];
  List<TrackGroup> _genres = const [];
  List<TrackGroup> _folders = const [];

  List<Track> get tracks => _tracks;
  List<TrackGroup> get albums => _albums;
  List<TrackGroup> get artists => _artists;
  List<TrackGroup> get genres => _genres;
  List<TrackGroup> get folders => _folders;

  Track? trackById(int id) => _byId[id];

  List<Track> tracksForIds(Iterable<int> ids) {
    final result = <Track>[];
    for (final id in ids) {
      final track = _byId[id];
      if (track != null) result.add(track);
    }
    return result;
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'library_cache.json'));
  }

  Future<void> loadCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString()) as List;
      final list = decoded
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _setTracks(list);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveCache(List<Track> list) async {
    try {
      final file = await _cacheFile();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(list.map((t) => t.toJson()).toList()),
        flush: true,
      );
      await tmp.rename(file.path);
    } catch (_) {}
  }

  Future<bool> _ensurePermission() async {
    if (!Platform.isAndroid) return true;
    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;
    final storage = await Permission.storage.request();
    if (storage.isGranted) return true;
    return await _query.permissionsStatus() || await _query.permissionsRequest();
  }

  Future<void> scan({int minSeconds = 10, List<String> excludedFolders = const []}) async {
    if (scanning) return;
    scanning = true;
    error = null;
    notifyListeners();

    try {
      final granted = await _ensurePermission();
      if (!granted) {
        permissionDenied = true;
        scanning = false;
        notifyListeners();
        return;
      }
      permissionDenied = false;

      final songs = await _query.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      final minMs = minSeconds * 1000;
      final filtered = <Track>[];
      for (final s in songs) {
        if ((s.duration ?? 0) < minMs) continue;
        if (s.data.isEmpty) continue;
        final track = Track.fromSong(s);
        if (excludedFolders.any((f) => track.folder.startsWith(f))) continue;
        filtered.add(track);
      }

      _setTracks(filtered);
      await _saveCache(filtered);
    } catch (e) {
      error = e.toString();
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  void _setTracks(List<Track> list) {
    final sorted = List<Track>.of(list)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _tracks = List.unmodifiable(sorted);
    _byId = {for (final t in _tracks) t.id: t};

    _albums = _groupBy(
      _tracks,
      keyOf: (t) => '${t.album.toLowerCase()}__${t.albumId}',
      titleOf: (t) => t.album,
      subtitleOf: (group) => group.first.artist,
      sortGroupTracks: (a, b) {
        final cmp = a.trackNumber.compareTo(b.trackNumber);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      },
    );

    final artistBuckets = <String, List<Track>>{};
    final artistTitles = <String, String>{};
    for (final t in _tracks) {
      for (final name in splitArtists(t.artist)) {
        final k = name.toLowerCase();
        (artistBuckets[k] ??= <Track>[]).add(t);
        artistTitles.putIfAbsent(k, () => name);
      }
    }
    final artistGroups = <TrackGroup>[];
    artistBuckets.forEach((k, items) {
      artistGroups.add(TrackGroup(
        key: k,
        title: artistTitles[k]!,
        subtitle: '${items.length} songs',
        tracks: List.unmodifiable(items),
      ));
    });
    artistGroups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _artists = List.unmodifiable(artistGroups);

    _genres = _groupBy(
      _tracks,
      keyOf: (t) => t.genre.toLowerCase(),
      titleOf: (t) => t.genre,
      subtitleOf: (group) => '${group.length} songs',
    );

    _folders = _groupBy(
      _tracks,
      keyOf: (t) => t.folder,
      titleOf: (t) => t.folderName,
      subtitleOf: (group) => group.first.folder,
    );
  }

  List<TrackGroup> _groupBy(
    List<Track> source, {
    required String Function(Track) keyOf,
    required String Function(Track) titleOf,
    required String Function(List<Track>) subtitleOf,
    int Function(Track, Track)? sortGroupTracks,
  }) {
    final buckets = <String, List<Track>>{};
    final titles = <String, String>{};
    for (final t in source) {
      final k = keyOf(t);
      (buckets[k] ??= <Track>[]).add(t);
      titles.putIfAbsent(k, () => titleOf(t));
    }
    final groups = <TrackGroup>[];
    buckets.forEach((k, items) {
      if (sortGroupTracks != null) items.sort(sortGroupTracks);
      groups.add(TrackGroup(
        key: k,
        title: titles[k]!,
        subtitle: subtitleOf(items),
        tracks: List.unmodifiable(items),
      ));
    });
    groups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return List.unmodifiable(groups);
  }

  List<Track> sortedTracks(TrackSort sort, {bool descending = false}) {
    final copy = List<Track>.of(_tracks);
    int compare(Track a, Track b) {
      switch (sort) {
        case TrackSort.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case TrackSort.artist:
          return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        case TrackSort.album:
          return a.album.toLowerCase().compareTo(b.album.toLowerCase());
        case TrackSort.dateAdded:
          return b.dateAddedSec.compareTo(a.dateAddedSec);
        case TrackSort.duration:
          return b.durationMs.compareTo(a.durationMs);
      }
    }

    copy.sort(descending ? (a, b) => compare(b, a) : compare);
    return copy;
  }

  SearchResults search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const SearchResults();
    return SearchResults(
      tracks: _tracks
          .where((t) =>
              t.title.toLowerCase().contains(q) ||
              t.artist.toLowerCase().contains(q) ||
              t.album.toLowerCase().contains(q))
          .toList(),
      albums: _albums
          .where((g) =>
              g.title.toLowerCase().contains(q) ||
              g.subtitle.toLowerCase().contains(q))
          .toList(),
      artists: _artists
          .where((g) => g.title.toLowerCase().contains(q))
          .toList(),
    );
  }
}
