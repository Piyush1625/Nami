import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.path,
    required this.uri,
    required this.durationMs,
    required this.genre,
    required this.dateAddedSec,
    required this.size,
    this.trackNumber = 0,
  });

  static const unknownArtist = 'Unknown artist';
  static const unknownAlbum = 'Unknown album';
  static const unknownGenre = 'Unknown genre';

  final int id;
  final String title;
  final String artist;
  final String album;
  final int albumId;
  final String path;
  final String uri;
  final int durationMs;
  final String genre;
  final int dateAddedSec;
  final int size;
  final int trackNumber;

  Duration get duration => Duration(milliseconds: durationMs);
  String get folder => p.dirname(path);
  String get folderName => p.basename(folder);

  Uri get artUri =>
      Uri.parse('content://media/external/audio/albumart/$albumId');

  factory Track.fromSong(SongModel s) {
    String clean(String? value, String fallback) {
      final text = (value ?? '').trim();
      return (text.isEmpty || text == '<unknown>') ? fallback : text;
    }

    return Track(
      id: s.id,
      title: clean(s.title, s.displayNameWOExt),
      artist: clean(s.artist, unknownArtist),
      album: clean(s.album, unknownAlbum),
      albumId: s.albumId ?? 0,
      path: s.data,
      uri: s.uri ?? '',
      durationMs: s.duration ?? 0,
      genre: clean(s.genre, unknownGenre),
      dateAddedSec: s.dateAdded ?? 0,
      size: s.size,
      trackNumber: s.track ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'albumId': albumId,
        'path': path,
        'uri': uri,
        'durationMs': durationMs,
        'genre': genre,
        'dateAddedSec': dateAddedSec,
        'size': size,
        'trackNumber': trackNumber,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as int,
        title: j['title'] as String,
        artist: j['artist'] as String,
        album: j['album'] as String,
        albumId: j['albumId'] as int,
        path: j['path'] as String,
        uri: j['uri'] as String,
        durationMs: j['durationMs'] as int,
        genre: j['genre'] as String,
        dateAddedSec: j['dateAddedSec'] as int,
        size: j['size'] as int,
        trackNumber: (j['trackNumber'] as int?) ?? 0,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
