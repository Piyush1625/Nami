import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NamiApp());
}

class NamiApp extends StatelessWidget {
  const NamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nami',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070709),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF121217),
        ),
      ),
      home: const NamiHomeShell(),
    );
  }
}

class LyricLine {
  final Duration timestamp;
  final String text;
  LyricLine({required this.timestamp, required this.text});
}

class AudioTrack {
  String title;
  String artist;
  String album;
  String genre;
  String albumArtist;
  String composer;
  String comment;
  String trackNumber;
  String year;
  final String path;
  Uint8List? albumArt;
  String rawLyrics;
  List<LyricLine> parsedLyrics;
  bool isMetadataLoaded;
  bool isLyricsFetched;
  Duration duration;
  bool isFavorite;
  String addedDate;
  int fileSize;
  int bitrateKbps;
  int sampleRateHz;
  int bitDepth;

  AudioTrack({
    required this.title,
    required this.artist,
    required this.album,
    this.genre = "Hip-Hop/Rap",
    this.albumArtist = "",
    this.composer = "",
    this.comment = "",
    this.trackNumber = "1/10",
    this.year = "2025-08-22",
    required this.path,
    this.albumArt,
    this.rawLyrics = "",
    List<LyricLine>? parsedLyrics,
    this.isMetadataLoaded = false,
    this.isLyricsFetched = false,
    this.duration = const Duration(minutes: 3, seconds: 45),
    this.isFavorite = false,
    this.addedDate = "Sep 2026",
    this.fileSize = 0,
    this.bitrateKbps = 1790,
    this.sampleRateHz = 48000,
    this.bitDepth = 24,
  }) : parsedLyrics = parsedLyrics ?? [];
}

class CustomPlaylist {
  String name;
  List<AudioTrack> tracks;
  CustomPlaylist({required this.name, required this.tracks});
}

class MornyeExtension {
  final String name;
  final String version;
  final String author;
  final String format;
  bool isEnabled;
  MornyeExtension({required this.name, required this.version, required this.author, required this.format, this.isEnabled = true});
}

class MornyeCatalogItem {
  final String title;
  final String artist;
  final String album;
  final String subtitle;
  final String type;
  final String service;
  final String? previewUrl;
  final String? artworkUrl;
  final int durationSeconds;

  MornyeCatalogItem({required this.title, required this.artist, required this.album, required this.subtitle, required this.type, required this.service, this.previewUrl, this.artworkUrl, this.durationSeconds = 210});
}

class NamiHomeShell extends StatefulWidget {
  const NamiHomeShell({super.key});
  @override
  State<NamiHomeShell> createState() => _NamiHomeShellState();
}

class _NamiHomeShellState extends State<NamiHomeShell> {
  int _selectedIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer(handleInterruptions: true, androidApplyAudioAttributes: true, handleAudioSessionActivation: true);
  bool _hasPermission = false;
  bool _isScanning = false;
  List<AudioTrack> _songs = [];
  List<AudioTrack> _filteredSongs = [];
  final List<AudioTrack> _playNextQueue = [];
  List<CustomPlaylist> _customPlaylists = [];

  final ValueNotifier<AudioTrack?> _currentSongNotifier = ValueNotifier<AudioTrack?>(null);
  AudioTrack? get _currentSong => _currentSongNotifier.value;
  set _currentSong(AudioTrack? val) => _currentSongNotifier.value = val;

  bool _isPlaying = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  int _artistGridColumns = 4;
  String _artistSortOrder = "Artist";

  final TextEditingController _mornyeSearchController = TextEditingController();
  List<MornyeCatalogItem> _mornyeResults = [];
  bool _isMornyeSearching = false;
  String _selectedMornyeService = "Qobuz";
  String _mornyeActiveFilter = "All";
  String _mornyeRepoUrl = "https://raw.githubusercontent.com/mornyeapp/Mornye-Extension/main/registry.json";
  String _mornyeAudioQuality = "24-bit / 192kHz Hi-Res FLAC";
  bool _mornyeEmbedArt = true;
  bool _mornyeAutoLrc = true;
  String _mornyeDownloadFolder = "/storage/emulated/0/Music";
  final Set<String> _downloadingTitles = {};
  final List<String> _mornyeServices = ["Qobuz", "Tidal", "Apple Music", "Spotify Web", "Amazon Music", "YouTube Music"];

  bool _usbDacExclusive = true;
  bool _gaplessPlayback = true;
  bool _mediaNotificationEnabled = true;
  String _connectedDacName = "KEFINE";
  String _userName = "Piyush";
  String? _userPhotoPath;
  List<String> _deviceImages = [];

  final List<MornyeExtension> _extensions = [
    MornyeExtension(name: 'Qobuz Studio Master (.sflx)', version: '1.4.0', author: 'OpenAudio', format: '24-bit / 192kHz FLAC', isEnabled: true),
    MornyeExtension(name: 'Tidal Hi-Res MAX (.sflx)', version: '1.4.2', author: 'Mornye Core', format: '24-bit / 96kHz FLAC', isEnabled: true),
    MornyeExtension(name: 'Apple Music ALAC (.sflx)', version: '1.1.8', author: 'Mornye Core', format: '24-bit ALAC', isEnabled: true),
    MornyeExtension(name: 'LRCLIB Synced Lyrics (.sflx)', version: '2.1.0', author: 'LRCLIB', format: 'Timestamped .LRC', isEnabled: true),
  ];

  static const List<String> _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void initState() {
    super.initState();
    _initAudioSessionAndDac();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissionAndScanMusic());
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        if (_playNextQueue.isNotEmpty) _playSong(_playNextQueue.removeAt(0));
        else _playNextTrack();
      }
    });
  }

  Future<void> _initAudioSessionAndDac() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(contentType: AndroidAudioContentType.music, flags: AndroidAudioFlags.audibilityEnforced, usage: AndroidAudioUsage.media),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      await session.setActive(true);
      await _audioPlayer.setSpeed(1.0);
      await _audioPlayer.setPitch(1.0);
      await _audioPlayer.setSkipSilenceEnabled(false);
      final devices = await session.getDevices();
      for (var d in devices) { if (d.isOutput && d.name.isNotEmpty) _connectedDacName = d.name; }
    } catch (_) {}
  }

  Future<void> _toggleUsbDacMode(bool enabled) async {
    setState(() => _usbDacExclusive = enabled);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled ? 'USB DAC Bit-Perfect Mode Enabled' : 'Android Mixer 32-bit Float Active'), backgroundColor: Colors.deepPurple));
  }

  Future<void> _requestPermissionAndScanMusic() async {
    PermissionStatus status = await Permission.audio.request();
    await Permission.photos.request();
    if (!status.isGranted) status = await Permission.storage.request();
    if (!status.isGranted) status = await Permission.manageExternalStorage.request();
    if (status.isGranted || await Permission.storage.isGranted || await Permission.manageExternalStorage.isGranted) {
      setState(() { _hasPermission = true; _isScanning = true; });
      await _fastScanDeviceMusic();
      _scanUserPhotosInBackground();
    }
  }

  Future<void> _scanUserPhotosInBackground() async {
    List<String> imgs = [];
    final dirs = [Directory('/storage/emulated/0/Download'), Directory('/storage/emulated/0/Pictures'), Directory('/storage/emulated/0/DCIM/Camera')];
    for (var d in dirs) {
      try {
        if (await d.exists()) {
          await for (var entity in d.list(recursive: false, followLinks: false)) {
            if (entity is File) {
              final l = entity.path.toLowerCase();
              if (l.endsWith('.jpg') || l.endsWith('.jpeg') || l.endsWith('.png') || l.endsWith('.webp')) { imgs.add(entity.path); if (imgs.length >= 24) break; }
            }
          }
        }
      } catch (_) {}
      if (imgs.length >= 24) break;
    }
    if (mounted) setState(() => _deviceImages = imgs);
  }

  Future<void> _fastScanDeviceMusic() async {
    List<AudioTrack> foundTracks = [];
    try {
      List<Directory> searchDirs = [];
      if (await Directory('/storage/emulated/0/Music').exists()) searchDirs.add(Directory('/storage/emulated/0/Music'));
      if (await Directory('/storage/emulated/0/Download').exists()) searchDirs.add(Directory('/storage/emulated/0/Download'));
      final Set<String> seenPaths = {};
      for (var dir in searchDirs) {
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            String path = entity.path; String lower = path.toLowerCase(); String fileName = entity.uri.pathSegments.last;
            if (fileName.startsWith('.')) continue;
            if (lower.endsWith('.flac') || lower.endsWith('.mp3') || lower.endsWith('.m4a') || lower.endsWith('.wav')) {
              if (seenPaths.contains(path)) continue;
              seenPaths.add(path);
              String cleanName = _sanitizeMetadataText(fileName.substring(0, fileName.lastIndexOf('.')).replaceAll('_', ' '));
              String artist = 'Unknown Artist';
              if (cleanName.contains(' - ')) {
                final parts = cleanName.split(' - ');
                artist = _sanitizeMetadataText(parts[0]);
                cleanName = _sanitizeMetadataText(parts.sublist(1).join(' - '));
              }
              String formattedDate = "Sep 2026";
              try {
                final stat = await entity.stat();
                formattedDate = "${_monthNames[stat.modified.month - 1]} ${stat.modified.year}";
              } catch (_) {}
              foundTracks.add(AudioTrack(title: cleanName, artist: artist, album: cleanName, path: path, addedDate: formattedDate));
            }
          }
        }
      }
    } catch (_) {}
    foundTracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    setState(() { _songs = foundTracks; _filteredSongs = foundTracks; _isScanning = false; });
    _enrichMetadataInBackground();
  }

  Future<void> _enrichMetadataInBackground() async {
    for (int i = 0; i < _songs.length; i++) {
      if (!_songs[i].isMetadataLoaded) {
        await _extractAudioMetadata(_songs[i]);
        if (i % 3 == 0 && mounted) setState(() {});
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _extractAudioMetadata(AudioTrack track) async {
    try {
      final file = File(track.path);
      track.fileSize = await file.length();
      if (track.fileSize > 0 && track.duration.inSeconds > 0) {
        track.bitrateKbps = ((track.fileSize * 8) ~/ 1000) ~/ track.duration.inSeconds;
        if (track.bitrateKbps < 128) track.bitrateKbps = 1411;
      }
      final readSize = track.fileSize < (2560 * 1024) ? track.fileSize : (2560 * 1024);
      final raf = await file.open(mode: FileMode.read);
      final data = await raf.read(readSize);
      await raf.close();

      if (data.length > 4 && data[0] == 0x66 && data[1] == 0x4C && data[2] == 0x61 && data[3] == 0x43) {
        int offset = 4;
        while (offset + 4 < data.length) {
          int header = data[offset];
          bool isLast = (header & 0x80) != 0;
          int blockType = header & 0x7F;
          int length = (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
          offset += 4;
          if (blockType == 0 && length >= 18 && offset + length <= data.length) {
            int sr = (data[offset + 10] << 12) | (data[offset + 11] << 4) | ((data[offset + 12] & 0xF0) >> 4);
            int bps = (((data[offset + 12] & 0x01) << 4) | ((data[offset + 13] & 0xF0) >> 4)) + 1;
            int totalSamples = ((data[offset + 13] & 0x0F) << 32) | (data[offset + 14] << 24) | (data[offset + 15] << 16) | (data[offset + 16] << 8) | data[offset + 17];
            if (sr > 0) {
              track.sampleRateHz = sr;
              if (totalSamples > 0) { final secs = totalSamples ~/ sr; if (secs > 0) { track.duration = Duration(seconds: secs); track.bitrateKbps = ((track.fileSize * 8) ~/ 1000) ~/ secs; } }
            }
            if (bps >= 16) track.bitDepth = bps;
          } else if (blockType == 4 && offset + length <= data.length) {
            int p = offset; final blockEnd = offset + length;
            if (p + 4 <= blockEnd) {
              int vendorLen = data[p] | (data[p + 1] << 8) | (data[p + 2] << 16) | (data[p + 3] << 24);
              p += 4 + vendorLen;
              if (p + 4 <= blockEnd) {
                int commentCount = data[p] | (data[p + 1] << 8) | (data[p + 2] << 16) | (data[p + 3] << 24);
                p += 4;
                for (int c = 0; c < commentCount && p + 4 <= blockEnd; c++) {
                  int cLen = data[p] | (data[p + 1] << 8) | (data[p + 2] << 16) | (data[p + 3] << 24);
                  p += 4; if (cLen < 0 || p + cLen > blockEnd) break;
                  final commentStr = utf8.decode(data.sublist(p, p + cLen), allowMalformed: true);
                  p += cLen; final eqIdx = commentStr.indexOf('=');
                  if (eqIdx > 0) {
                    final key = commentStr.substring(0, eqIdx).trim().toUpperCase();
                    final val = _sanitizeMetadataText(commentStr.substring(eqIdx + 1));
                    if (val.isNotEmpty) {
                      if (key == 'TITLE') track.title = val;
                      else if (key == 'ARTIST' || key == 'ALBUMARTIST' || key == 'PERFORMER') {
                        if (track.artist == 'Unknown Artist' || track.artist.isEmpty) track.artist = val;
                        else if (!track.artist.contains(val)) track.artist = '${track.artist}, $val';
                      } else if (key == 'ALBUM') track.album = val;
                      else if (key == 'GENRE') track.genre = val;
                      else if (key == 'COMPOSER') track.composer = val;
                      else if (key == 'COMMENT') track.comment = val;
                      else if (key == 'DATE' || key == 'YEAR') track.year = val;
                      else if (key == 'TRACKNUMBER') track.trackNumber = val;
                      else if (key == 'LYRICS' || key == 'UNSYNCEDLYRICS') {
                        track.rawLyrics = commentStr.substring(eqIdx + 1).trim();
                        track.parsedLyrics = _parseLrc(track.rawLyrics);
                      }
                    }
                  }
                }
              }
            }
          } else if (blockType == 6 && offset + length <= data.length) {
            int picOffset = offset + 4;
            int mimeLen = (data[picOffset] << 24) | (data[picOffset + 1] << 16) | (data[picOffset + 2] << 8) | data[picOffset + 3];
            picOffset += 4 + mimeLen;
            int descLen = (data[picOffset] << 24) | (data[picOffset + 1] << 16) | (data[picOffset + 2] << 8) | data[picOffset + 3];
            picOffset += 4 + descLen + 16;
            int dataLen = (data[picOffset] << 24) | (data[picOffset + 1] << 16) | (data[picOffset + 2] << 8) | data[picOffset + 3];
            picOffset += 4;
            if (picOffset + dataLen <= data.length && dataLen > 0) track.albumArt = data.sublist(picOffset, picOffset + dataLen);
          }
          if (isLast) break;
          offset += length;
        }
      }

      if (data.length > 10 && data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) {
        int version = data[3];
        int tagSize = ((data[6] & 0x7F) << 21) | ((data[7] & 0x7F) << 14) | ((data[8] & 0x7F) << 7) | (data[9] & 0x7F);
        int offset = 10; int maxOffset = (tagSize + 10 < data.length) ? tagSize + 10 : data.length;
        while (offset + 10 < maxOffset) {
          String frameId = String.fromCharCodes(data.sublist(offset, offset + 4));
          if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;
          int frameSize;
          if (version == 4) frameSize = ((data[offset + 4] & 0x7F) << 21) | ((data[offset + 5] & 0x7F) << 14) | ((data[offset + 6] & 0x7F) << 7) | (data[offset + 7] & 0x7F);
          else frameSize = (data[offset + 4] << 24) | (data[offset + 5] << 16) | (data[offset + 6] << 8) | data[offset + 7];
          offset += 10;
          if (frameSize <= 0 || offset + frameSize > maxOffset) break;
          if (frameId == 'TIT2') track.title = _decodeId3Text(data.sublist(offset, offset + frameSize));
          else if (frameId == 'TPE1' || frameId == 'TPE2') {
            final a = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (a.isNotEmpty) { if (track.artist == 'Unknown Artist' || track.artist.isEmpty) track.artist = a; else if (!track.artist.contains(a)) track.artist = '${track.artist}, $a'; }
          } else if (frameId == 'TALB') track.album = _decodeId3Text(data.sublist(offset, offset + frameSize));
          else if (frameId == 'APIC' && track.albumArt == null) track.albumArt = _extractEmbeddedImageBytes(data, offset, offset + frameSize);
          offset += frameSize;
        }
      }

      if (track.artist == 'Unknown Artist' || track.artist.isEmpty) {
        final fileName = File(track.path).uri.pathSegments.last;
        if (fileName.contains(' - ')) track.artist = _sanitizeMetadataText(fileName.split(' - ')[0]);
      }
      if (track.albumArt == null) track.albumArt = _extractEmbeddedImageBytes(data, 0, data.length);
    } catch (_) {}
    track.isMetadataLoaded = true;
  }

  String _sanitizeMetadataText(String input) {
    String s = input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    return s.replaceAll(RegExp(r'[#<>%+^~|]+$'), '').trim();
  }

  String _decodeId3Text(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    int encoding = bytes[0]; Uint8List content = bytes.sublist(1);
    if (encoding == 0) {
      final nullIdx = content.indexOf(0); if (nullIdx >= 0) content = content.sublist(0, nullIdx);
      return _sanitizeMetadataText(latin1.decode(content, allowInvalid: true));
    } else if (encoding == 1 || encoding == 2) {
      int start = 0; bool littleEndian = true;
      if (content.length >= 2) {
        if (content[0] == 0xFF && content[1] == 0xFE) { littleEndian = true; start = 2; }
        else if (content[0] == 0xFE && content[1] == 0xFF) { littleEndian = false; start = 2; }
      }
      final List<int> codeUnits = [];
      for (int i = start; i + 1 < content.length; i += 2) {
        int unit = littleEndian ? (content[i] | (content[i + 1] << 8)) : ((content[i] << 8) | content[i + 1]);
        if (unit == 0) break; codeUnits.add(unit);
      }
      return _sanitizeMetadataText(String.fromCharCodes(codeUnits));
    } else {
      final nullIdx = content.indexOf(0); if (nullIdx >= 0) content = content.sublist(0, nullIdx);
      return _sanitizeMetadataText(utf8.decode(content, allowMalformed: true));
    }
  }

  Uint8List? _extractEmbeddedImageBytes(Uint8List data, int start, int end) {
    for (int j = start; j < end - 8; j++) {
      if (data[j] == 0xFF && data[j + 1] == 0xD8 && data[j + 2] == 0xFF) {
        int imgEnd = end;
        for (int k = j + 4; k < end - 1; k++) { if (data[k] == 0xFF && data[k + 1] == 0xD9) { imgEnd = k + 2; if (imgEnd - j > 2048) break; } }
        if (imgEnd - j > 1024) return data.sublist(j, imgEnd);
      }
      if (data[j] == 0x89 && data[j + 1] == 0x50 && data[j + 2] == 0x4E && data[j + 3] == 0x47) {
        int imgEnd = end;
        for (int k = j + 8; k < end - 4; k++) { if (data[k] == 0x49 && data[k + 1] == 0x45 && data[k + 2] == 0x4E && data[k + 3] == 0x44) { imgEnd = (k + 8 <= end) ? k + 8 : end; break; } }
        if (imgEnd - j > 1024) return data.sublist(j, imgEnd);
      }
    }
    return null;
  }

  List<LyricLine> _parseLrc(String raw) {
    final lines = raw.split('\n'); final List<LyricLine> result = [];
    final regExp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\](.*)');
    for (var line in lines) {
      final match = regExp.firstMatch(line.trim());
      if (match != null) {
        final min = int.tryParse(match.group(1)!) ?? 0; final sec = int.tryParse(match.group(2)!) ?? 0;
        final msStr = match.group(3) ?? '0'; final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
        final text = match.group(4)!.trim(); if (text.isNotEmpty) result.add(LyricLine(timestamp: Duration(minutes: min, seconds: sec, milliseconds: ms), text: text));
      }
    }
    if (result.isEmpty && raw.trim().isNotEmpty) {
      final plainLines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      for (int i = 0; i < plainLines.length; i++) { result.add(LyricLine(timestamp: Duration(seconds: i * 4), text: plainLines[i].trim())); }
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<void> _fetchLyricsOnline(AudioTrack song) async {
    if (song.isLyricsFetched && song.parsedLyrics.isNotEmpty) return;
    try {
      final lrcPath = '${song.path.substring(0, song.path.lastIndexOf('.'))}.lrc';
      if (await File(lrcPath).exists()) {
        final localLrc = await File(lrcPath).readAsString();
        if (localLrc.trim().isNotEmpty) { song.rawLyrics = localLrc; song.parsedLyrics = _parseLrc(localLrc); song.isLyricsFetched = true; if (mounted) setState(() {}); return; }
      }
    } catch (_) {}
    final cleanTitle = _sanitizeMetadataText(song.title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')).trim();
    final primaryArtist = _sanitizeMetadataText(song.artist.split(RegExp(r'[,&•/]|feat\.|ft\.', caseSensitive: false)).first).trim();
    try {
      final getRes = await http.get(Uri.parse('https://lrclib.net/api/get?track_name=${Uri.encodeComponent(cleanTitle)}&artist_name=${Uri.encodeComponent(primaryArtist)}')).timeout(const Duration(seconds: 5));
      if (getRes.statusCode == 200) {
        final data = jsonDecode(getRes.body); final synced = data['syncedLyrics']?.toString(); final plain = data['plainLyrics']?.toString();
        if ((synced != null && synced.isNotEmpty) || (plain != null && plain.isNotEmpty)) {
          song.rawLyrics = (synced != null && synced.isNotEmpty) ? synced : plain!;
          song.parsedLyrics = _parseLrc(song.rawLyrics); song.isLyricsFetched = true; if (mounted) setState(() {}); return;
        }
      }
    } catch (_) {}
    if (song.parsedLyrics.isEmpty) { song.rawLyrics = "[00:00.00] Instrumental / No Synced Lyrics Found"; song.parsedLyrics = _parseLrc(song.rawLyrics); }
    if (mounted) setState(() {});
  }

  Future<void> _searchMornyeCatalog(String query) async {
    if (query.trim().isEmpty) { setState(() => _mornyeResults = []); return; }
    setState(() => _isMornyeSearching = true);
    try {
      final res = await http.get(Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&limit=25')).timeout(const Duration(seconds: 7));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body); final results = decoded['results'] ?? [];
        final List<MornyeCatalogItem> items = []; final Set<String> seenArtists = {}; final Set<String> seenAlbums = {};
        for (var item in results) {
          if (item is Map) {
            final track = item['trackName']?.toString() ?? 'Unknown Track'; final artist = item['artistName']?.toString() ?? 'Unknown Artist'; final album = item['collectionName']?.toString() ?? 'Single'; final preview = item['previewUrl']?.toString(); final art = item['artworkUrl100']?.toString().replaceAll('100x100bb', '600x600bb'); final timeMs = int.tryParse(item['trackTimeMillis']?.toString() ?? '210000') ?? 210000;
            items.add(MornyeCatalogItem(title: track, artist: artist, album: album, subtitle: '$artist • $album • via $_selectedMornyeService', type: 'song', service: _selectedMornyeService, previewUrl: preview, artworkUrl: art, durationSeconds: timeMs ~/ 1000));
            if (!seenArtists.contains(artist)) { seenArtists.add(artist); items.add(MornyeCatalogItem(title: artist, artist: artist, album: '', subtitle: 'Artist • via $_selectedMornyeService', type: 'artist', service: _selectedMornyeService, artworkUrl: art)); }
            if (!seenAlbums.contains(album)) { seenAlbums.add(album); items.add(MornyeCatalogItem(title: album, artist: artist, album: album, subtitle: '$artist • via $_selectedMornyeService', type: 'album', service: _selectedMornyeService, artworkUrl: art)); }
          }
        }
        setState(() { _mornyeResults = items; _isMornyeSearching = false; });
      } else { setState(() => _isMornyeSearching = false); }
    } catch (_) { setState(() => _isMornyeSearching = false); }
  }

  void _showStatisticsScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Statistics & Charts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Library Insights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Row(children: [Expanded(child: _statBox('Tracks', '${_songs.length}')), const SizedBox(width: 10), Expanded(child: _statBox('Albums', '${_songs.map((s) => s.album).toSet().length}'))]),
                const SizedBox(height: 10),
                Row(children: [Expanded(child: _statBox('Artists', '${_songs.map((s) => s.artist).toSet().length}')), const SizedBox(width: 10), Expanded(child: _statBox('Total Duration', '${(_songs.fold(0, (sum, s) => sum + s.duration.inHours))}h'))]),
              ],
            ),
          ),
        ],
      ),
    )));
  }

  Widget _statBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF0A0A0E), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent)), const SizedBox(height: 4), Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey))]),
    );
  }

  Future<void> _downloadMornyeTrack(MornyeCatalogItem item) async {
    if (item.previewUrl == null || item.previewUrl!.isEmpty) return;
    setState(() => _downloadingTitles.add(item.title));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading "${item.title}" ($_mornyeAudioQuality)...'), backgroundColor: Colors.deepPurple));
    try {
      final dir = Directory(_mornyeDownloadFolder); if (!await dir.exists()) await dir.create(recursive: true);
      final savePath = '${dir.path}/${item.artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '')} - ${item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '')}.m4a';
      final res = await http.get(Uri.parse(item.previewUrl!)).timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        await File(savePath).writeAsBytes(res.bodyBytes);
        Uint8List? art;
        if (_mornyeEmbedArt && item.artworkUrl != null) {
          try { final artRes = await http.get(Uri.parse(item.artworkUrl!)); if (artRes.statusCode == 200) art = artRes.bodyBytes; } catch (_) {}
        }
        final newTrack = AudioTrack(title: item.title, artist: item.artist, album: item.album, path: savePath, albumArt: art, addedDate: "Sep 2026", duration: Duration(seconds: item.durationSeconds), isMetadataLoaded: true);
        if (_mornyeAutoLrc) _fetchLyricsOnline(newTrack);
        setState(() { _songs.insert(0, newTrack); _filteredSongs = List.from(_songs); _downloadingTitles.remove(item.title); });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to library!'), action: SnackBarAction(label: 'PLAY', textColor: Colors.white, onPressed: () => _playSong(newTrack))));
      } else { setState(() => _downloadingTitles.remove(item.title)); }
    } catch (_) { setState(() => _downloadingTitles.remove(item.title)); }
  }

  void _showExtensionRepoDialog() {
    final urlCtrl = TextEditingController(text: _mornyeRepoUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        title: const Text('Extension Repository'),
        content: TextField(controller: urlCtrl, decoration: const InputDecoration(hintText: 'Enter registry JSON URL...', filled: true, fillColor: Color(0xFF0A0A0E))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent), onPressed: () { if (urlCtrl.text.trim().isNotEmpty) setState(() => _mornyeRepoUrl = urlCtrl.text.trim()); Navigator.pop(context); }, child: const Text('Save')),
        ],
      ),
    );
  }

  void _showMornyePreferencesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12121A),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mornye Preferences', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Embed High-Res Cover Art'), value: _mornyeEmbedArt, activeColor: Colors.deepPurpleAccent, onChanged: (v) => setState(() => _mornyeEmbedArt = v)),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Auto-Fetch Synced .LRC Lyrics'), value: _mornyeAutoLrc, activeColor: Colors.deepPurpleAccent, onChanged: (v) => setState(() => _mornyeAutoLrc = v)),
            ],
          ),
        ),
      ),
    );
  }

  void _filterSongs(String query) {
    final q = query.toLowerCase();
    setState(() { _filteredSongs = _songs.where((s) => s.title.toLowerCase().contains(q) || s.artist.toLowerCase().contains(q) || s.album.toLowerCase().contains(q)).toList(); });
  }

  Future<void> _playSong(AudioTrack song) async {
    if (song.path.isEmpty) return;
    _currentSong = song;
    if (mounted) setState(() {});
    _fetchLyricsOnline(song);
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(song.path);
      await _audioPlayer.play();
      if (_audioPlayer.duration != null && _audioPlayer.duration!.inSeconds > 0) {
        song.duration = _audioPlayer.duration!;
        if (song.fileSize > 0) song.bitrateKbps = ((song.fileSize * 8) ~/ 1000) ~/ song.duration.inSeconds;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _playNextTrack() {
    if (_playNextQueue.isNotEmpty) { _playSong(_playNextQueue.removeAt(0)); return; }
    if (_filteredSongs.isNotEmpty && _currentSong != null) {
      int nextIdx = (_filteredSongs.indexOf(_currentSong!) + 1) % _filteredSongs.length;
      _playSong(_filteredSongs[nextIdx]);
    } else if (_filteredSongs.isNotEmpty) { _playSong(_filteredSongs.first); }
  }

  void _playPrevTrack() {
    if (_filteredSongs.isNotEmpty && _currentSong != null) {
      int prevIdx = (_filteredSongs.indexOf(_currentSong!) - 1 + _filteredSongs.length) % _filteredSongs.length;
      _playSong(_filteredSongs[prevIdx]);
    }
  }

  void _shufflePlay() {
    if (_songs.isNotEmpty) { List<AudioTrack> shuffled = List.from(_songs)..shuffle(); _playSong(shuffled.first); }
  }

  void _togglePlayPause() async {
    if (_audioPlayer.playing) await _audioPlayer.pause();
    else if (_currentSong == null && _filteredSongs.isNotEmpty) _playSong(_filteredSongs.first);
    else await _audioPlayer.play();
  }

  Widget _buildNamidaTrackTile(AudioTrack song, {VoidCallback? onStateUpdate}) {
    final isCurrent = _currentSong?.path == song.path;
    return Dismissible(
      key: Key(song.path),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: Colors.deepPurpleAccent, child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.playlist_add_rounded, color: Colors.white, size: 22), Text('Play Next', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))])),
      onDismissed: (_) { setState(() => _playNextQueue.add(song)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued "${song.title}" to play next'))); if (onStateUpdate != null) onStateUpdate(); },
      child: InkWell(
        onTap: () { _playSong(song); if (onStateUpdate != null) onStateUpdate(); },
        onLongPress: () => _showActionMenu(song),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildCoverArt(song, 52, 8),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: isCurrent ? Colors.deepPurpleAccent : Colors.white)), const SizedBox(height: 2), Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Colors.white70)), const SizedBox(height: 1), Text('${song.album} • ${song.addedDate}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white54))])),
              const SizedBox(width: 8),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [Text(_formatDurationPadded(song.duration), style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500)), const SizedBox(height: 4), GestureDetector(onTap: () { setState(() => song.isFavorite = !song.isFavorite); if (onStateUpdate != null) onStateUpdate(); }, child: Icon(song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: song.isFavorite ? Colors.deepPurpleAccent : Colors.white38, size: 19))]),
              const SizedBox(width: 16),
              GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _showActionMenu(song), child: const Padding(padding: EdgeInsets.fromLTRB(2, 8, 10, 8), child: Icon(Icons.more_vert_rounded, color: Colors.white70, size: 19))),
            ],
          ),
        ),
      ),
    );
  }

  void _showHomeProfileEditorDialog() {
    final nameCtrl = TextEditingController(text: _userName);
    final pathCtrl = TextEditingController(text: _userPhotoPath ?? '');
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF14141F),
          title: const Text('Edit Profile & Photo'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Your Name')), const SizedBox(height: 10), TextField(controller: pathCtrl, decoration: const InputDecoration(labelText: 'Photo Path'))]),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent), onPressed: () { setState(() { if (nameCtrl.text.trim().isNotEmpty) _userName = nameCtrl.text.trim(); _userPhotoPath = pathCtrl.text.trim().isNotEmpty ? pathCtrl.text.trim() : null; }); Navigator.pop(context); }, child: const Text('Save'))],
        ),
      ),
    );
  }

  void _showAudioPathDetails(AudioTrack song) {
    final kHz = (song.sampleRateHz / 1000.0).toStringAsFixed(1);
    final pcmKbps = (song.sampleRateHz * song.bitDepth * 2) ~/ 1000;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141418),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Audio path', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 16),
              _buildAudioPathNode(icon: Icons.music_note_outlined, title: 'Source • PCM', subtitle: '${song.bitDepth}-bit • $kHz kHz • 2 ch • $pcmKbps kbps', isAmber: false, showConnectorDown: true),
              _buildAudioPathNode(icon: Icons.explicit_outlined, useCustomWaveIcon: true, title: '32-bit float', subtitle: null, isAmber: false, showConnectorDown: true),
              _buildAudioPathNode(icon: Icons.blur_circular_rounded, title: _usbDacExclusive ? 'Direct USB DAC Bypass' : 'Android mixer', subtitle: '32-bit float • $kHz kHz', isAmber: !_usbDacExclusive, showConnectorDown: true),
              _buildAudioPathNode(icon: Icons.speaker_outlined, title: _connectedDacName, subtitle: null, isAmber: false, showConnectorDown: false),
            ],
          ),
        ),
      ),
    );
  }

  void _showTagEditorDialog(AudioTrack song) {
    final titleCtrl = TextEditingController(text: song.title);
    final artistCtrl = TextEditingController(text: song.artist);
    final albumCtrl = TextEditingController(text: song.album);
    final lyricsCtrl = TextEditingController(text: song.rawLyrics);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit Tags', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 10),
              TextField(controller: artistCtrl, decoration: const InputDecoration(labelText: 'Artist')),
              const SizedBox(height: 10),
              TextField(controller: albumCtrl, decoration: const InputDecoration(labelText: 'Album')),
              const SizedBox(height: 10),
              TextField(controller: lyricsCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Lyrics (.LRC timestamps)')),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent), onPressed: () { setState(() { song.title = titleCtrl.text.trim(); song.artist = artistCtrl.text.trim(); song.album = albumCtrl.text.trim(); song.rawLyrics = lyricsCtrl.text; song.parsedLyrics = _parseLrc(song.rawLyrics); }); Navigator.pop(context); }, child: const Text('Save'))]),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionMenu(AudioTrack song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.album_rounded, color: Colors.white70), title: const Text('Go to Album'), onTap: () { Navigator.pop(context); _showFilteredListScreen('Album: ${song.album}', _songs.where((s) => s.album == song.album).toList()); }),
            ListTile(leading: const Icon(Icons.person_rounded, color: Colors.white70), title: const Text('Go to Artist'), onTap: () { Navigator.pop(context); _showArtistDetailScreen(song.artist, _songs.where((s) => s.artist == song.artist).toList()); }),
            ListTile(leading: const Icon(Icons.edit_note_rounded, color: Colors.white70), title: const Text('Edit Tags'), onTap: () { Navigator.pop(context); _showTagEditorDialog(song); }),
            ListTile(leading: const Icon(Icons.play_arrow_rounded, color: Colors.deepPurpleAccent), title: const Text('Play Next'), onTap: () { Navigator.pop(context); setState(() => _playNextQueue.add(song)); }),
          ],
        ),
      ),
    );
  }

  Widget _buildReactiveMiniPlayer() {
    return ValueListenableBuilder<AudioTrack?>(
      valueListenable: _currentSongNotifier,
      builder: (context, activeSong, _) {
        return GestureDetector(
          onHorizontalDragEnd: (details) { if (details.primaryVelocity! < 0) _playNextTrack(); else if (details.primaryVelocity! > 0) _playPrevTrack(); },
          onTap: _showNowPlayingScreen,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: const Color(0xFF15151E).withOpacity(0.96), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12)),
            child: Row(
              children: [
                if (activeSong != null) _buildCoverArt(activeSong, 44, 8) else const Icon(Icons.album_rounded, size: 42, color: Colors.deepPurpleAccent),
                const SizedBox(width: 12),
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, CrossAxisAlignment: CrossAxisAlignment.start, children: [Text(activeSong?.title ?? 'Tap any song to play', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)), Text(activeSong?.artist ?? '24-bit / Lossless Ready', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.white60))])),
                StreamBuilder<bool>(
                  stream: _audioPlayer.playingStream,
                  builder: (ctx, snap) {
                    final playing = snap.data ?? false;
                    return Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 24), onPressed: _playPrevTrack), IconButton(icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28), onPressed: _togglePlayPause), IconButton(icon: const Icon(Icons.skip_next_rounded, size: 24), onPressed: _playNextTrack)]);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showArtistDetailScreen(String artistName, List<AudioTrack> artistTracks) {
    final firstArt = artistTracks.firstWhere((s) => s.albumArt != null, orElse: () => artistTracks.first).albumArt;
    final Map<String, List<AudioTrack>> albumsMap = {};
    for (var s in artistTracks) { albumsMap.putIfAbsent(s.album, () => []).add(s); }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setArtistScreenState) => Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              actions: [
                IconButton(icon: const Icon(Icons.search_rounded), onPressed: () {}),
                IconButton(icon: const Icon(Icons.photo_library_outlined), onPressed: () {}),
                IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () {}),
              ],
            ),
            body: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 130),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          CircleAvatar(radius: 56, backgroundColor: Colors.deepPurple.withOpacity(0.3), backgroundImage: firstArt != null ? MemoryImage(firstArt) : null, child: firstArt == null ? const Icon(Icons.person_rounded, size: 52, color: Colors.deepPurpleAccent) : null),
                          const SizedBox(width: 20),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(artistName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), const SizedBox(height: 4), const Text('2018 – 2026', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600))])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...artistTracks.map((song) => _buildNamidaTrackTile(song, onStateUpdate: () => setArtistScreenState(() {}))),
                  ],
                ),
                Positioned(left: 12, right: 12, bottom: 24, child: _buildReactiveMiniPlayer()),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              backgroundColor: const Color(0xFF0A0A0F),
              selectedIndex: 2,
              onDestinationSelected: (idx) { Navigator.pop(context); setState(() => _selectedIndex = idx); },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Tracks'),
                NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Artists'),
                NavigationDestination(icon: Icon(Icons.playlist_play_rounded), selectedIcon: Icon(Icons.playlist_add_check_rounded), label: 'Playlists'),
                NavigationDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension_rounded), label: 'Mornye'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFilteredListScreen(String title, List<AudioTrack> tracks) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setListState) => Scaffold(
            appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            body: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 130),
                  children: tracks.map((song) => _buildNamidaTrackTile(song, onStateUpdate: () => setListState(() {}))).toList(),
                ),
                Positioned(left: 12, right: 12, bottom: 24, child: _buildReactiveMiniPlayer()),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              backgroundColor: const Color(0xFF0A0A0F),
              selectedIndex: 1,
              onDestinationSelected: (idx) { Navigator.pop(context); setState(() => _selectedIndex = idx); },
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Tracks'),
                NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Artists'),
                NavigationDestination(icon: Icon(Icons.playlist_play_rounded), selectedIcon: Icon(Icons.playlist_add_check_rounded), label: 'Playlists'),
                NavigationDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension_rounded), label: 'Mornye'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNowPlayingScreen() {
    if (_currentSong == null && _filteredSongs.isNotEmpty) _playSong(_filteredSongs.first);
    else if (_currentSong != null) _fetchLyricsOnline(_currentSong!);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NowPlayingModal(
        audioPlayer: _audioPlayer,
        currentSongNotifier: _currentSongNotifier,
        playNextQueue: _playNextQueue,
        totalTrackCount: _songs.length,
        currentIndex: _currentSong != null ? (_songs.indexOf(_currentSong!) + 1) : 1,
        extensions: _extensions,
        onShowPath: () { if (_currentSong != null) _showAudioPathDetails(_currentSong!); },
        onToggleFavorite: () { if (_currentSong != null) { setState(() => _currentSong!.isFavorite = !_currentSong!.isFavorite); } },
        onRefreshLyrics: () { if (_currentSong != null) { _currentSong!.isLyricsFetched = false; _fetchLyricsOnline(_currentSong!); } },
        onPlayPause: _togglePlayPause,
        onNext: _playNextTrack,
        onPrevious: _playPrevTrack,
        onEditTags: () { if (_currentSong != null) _showTagEditorDialog(_currentSong!); },
      ),
    );
  }

  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => MainSettingsScreen(usbDacExclusive: _usbDacExclusive, gaplessPlayback: _gaplessPlayback, mediaNotificationEnabled: _mediaNotificationEnabled, connectedDacName: _connectedDacName, onUsbDacChanged: _toggleUsbDacMode, onGaplessChanged: (v) => setState(() => _gaplessPlayback = v), onNotificationChanged: (v) => setState(() => _mediaNotificationEnabled = v), onRescan: _fastScanDeviceMusic)));
  }

  Widget _buildCoverArt(AudioTrack song, double size, double radius) {
    if (song.albumArt != null && song.albumArt!.isNotEmpty) {
      return ClipRRect(borderRadius: BorderRadius.circular(radius), child: Image.memory(song.albumArt!, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => _defaultArtPlaceholder(size, radius)));
    }
    return _defaultArtPlaceholder(size, radius);
  }

  Widget _defaultArtPlaceholder(double size, double radius) {
    return Container(width: size, height: size, decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.25), borderRadius: BorderRadius.circular(radius)), child: Icon(Icons.album_rounded, size: size * 0.5, color: Colors.deepPurpleAccent));
  }

  @override
  void dispose() { _audioPlayer.dispose(); _searchController.dispose(); _mornyeSearchController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<AudioTrack>> artistGroups = {};
    for (var song in _songs) { artistGroups.putIfAbsent(song.artist, () => []).add(song); }
    final uniqueArtists = artistGroups.keys.toList()..sort((a, b) => _artistSortOrder == "Artist" ? a.toLowerCase().compareTo(b.toLowerCase()) : artistGroups[b]!.length.compareTo(artistGroups[a]!.length));
    final List<String> tabTitles = ['Nami', 'Tracks', 'Artists', 'Playlists', 'Mornye'];

    final List<Widget> pages = [
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _showHomeProfileEditorDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xFF12121A), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
                    child: Row(children: [CircleAvatar(radius: 26, backgroundColor: Colors.deepPurpleAccent, backgroundImage: (_userPhotoPath != null && File(_userPhotoPath!).existsSync()) ? FileImage(File(_userPhotoPath!)) : null, child: (_userPhotoPath == null || !File(_userPhotoPath!).existsSync()) ? Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'P', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)) : null), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Happy listening,', style: TextStyle(fontSize: 12, color: Colors.white60)), Text(_userName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))]))]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                style: IconButton.styleFrom(backgroundColor: const Color(0xFF12121A), padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10))),
                icon: const Icon(Icons.bar_chart_rounded, color: Colors.deepPurpleAccent, size: 24),
                onPressed: _showStatisticsScreen,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Mixes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(height: 170, child: ListView(scrollDirection: Axis.horizontal, children: [GestureDetector(onTap: () { if (_songs.isNotEmpty) _playSong(_songs.first); }, child: _buildHomeCard(_songs.isNotEmpty ? _songs.first.albumArt : null, 'Recommended', '${_songs.length} Local Tracks')), GestureDetector(onTap: _shufflePlay, child: _buildHomeCard(null, 'Infinite Mix', 'Dynamic Audio Flow'))])),
        ],
      ),
      _hasPermission
          ? (_isScanning ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent)) : (_filteredSongs.isEmpty ? const Center(child: Text('No tracks found.', style: TextStyle(color: Colors.grey))) : Column(children: [Expanded(child: ListView.builder(padding: const EdgeInsets.only(bottom: 90), itemCount: _filteredSongs.length, itemBuilder: (context, index) => _buildNamidaTrackTile(_filteredSongs[index])))])))
          : Center(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent), onPressed: _requestPermissionAndScanMusic, child: const Text('Grant Storage Permission'))),
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(18)), child: Row(children: [const Icon(Icons.person_outline_rounded, size: 15, color: Colors.white70), const SizedBox(width: 6), Text('${uniqueArtists.length} Artists', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(width: 2), const Icon(Icons.chevron_right_rounded, size: 15, color: Colors.grey)])),
                const Spacer(),
                GestureDetector(onTap: () { setState(() { _artistGridColumns = _artistGridColumns == 4 ? 3 : (_artistGridColumns == 3 ? 2 : 4); }); }, child: Row(children: [const Icon(Icons.grid_view_rounded, size: 18, color: Colors.white70), Text('$_artistGridColumns', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70))])),
                const SizedBox(width: 12),
                GestureDetector(onTap: () { setState(() { _artistSortOrder = _artistSortOrder == "Artist" ? "Tracks" : "Artist"; }); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(16)), child: Row(children: [Text(_artistSortOrder, style: const TextStyle(fontSize: 12, color: Colors.white70)), const SizedBox(width: 4), const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.grey)]))),
              ],
            ),
          ),
          Expanded(child: GridView.builder(padding: const EdgeInsets.fromLTRB(12, 6, 12, 95), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _artistGridColumns, childAspectRatio: 0.76, crossAxisSpacing: 10, mainAxisSpacing: 12), itemCount: uniqueArtists.length, itemBuilder: (context, index) { final artistName = uniqueArtists[index]; final artistSongs = artistGroups[artistName]!; final firstArt = artistSongs.firstWhere((s) => s.albumArt != null, orElse: () => artistSongs.first).albumArt; return GestureDetector(onTap: () => _showArtistDetailScreen(artistName, artistSongs), child: Column(children: [Expanded(child: AspectRatio(aspectRatio: 1, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF161622), image: firstArt != null ? DecorationImage(image: MemoryImage(firstArt), fit: BoxFit.cover) : null), child: firstArt == null ? const Icon(Icons.person_rounded, size: 32, color: Colors.white38) : null))), const SizedBox(height: 6), Text(artistName, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white))])); })),
        ],
      ),
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('${_songs.length} Library Tracks', style: const TextStyle(color: Colors.grey, fontSize: 13)), ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)), icon: const Icon(Icons.add, size: 16), label: const Text('Add'), onPressed: () {})]),
          const SizedBox(height: 16),
          Row(children: [_buildPlaylistStatCard('History', '${(_songs.length * 2.5).floor()}', Icons.history), const SizedBox(width: 12), _buildPlaylistStatCard('Most Played', '${_songs.length}', Icons.trending_up)]),
          const SizedBox(height: 12),
          Row(children: [_buildPlaylistStatCard('Favourites', '${_songs.where((s) => s.isFavorite).length}', Icons.favorite), const SizedBox(width: 12), _buildPlaylistStatCard('Queue', '${_songs.length}', Icons.queue_music)]),
        ],
      ),
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.deepPurple.shade900.withOpacity(0.85), const Color(0xFF14141F)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.35))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [const Icon(Icons.extension_rounded, color: Colors.deepPurpleAccent, size: 26), const SizedBox(width: 8), const Expanded(child: Text('Mornye Stream', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.link_rounded, color: Colors.redAccent, size: 22), onPressed: _showExtensionRepoDialog), IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20), onPressed: _showMornyePreferencesSheet)]),
                const SizedBox(height: 12),
                TextField(controller: _mornyeSearchController, onSubmitted: _searchMornyeCatalog, decoration: InputDecoration(hintText: 'Search songs, albums, artists...', filled: true, fillColor: const Color(0xFF08080C), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none), suffixIcon: IconButton(icon: const Icon(Icons.search_rounded, color: Colors.deepPurpleAccent), onPressed: () => _searchMornyeCatalog(_mornyeSearchController.text)))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isMornyeSearching) const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
          else if (_mornyeResults.isNotEmpty) ..._mornyeResults.map((item) => ListTile(title: Text(item.title), subtitle: Text(item.subtitle), trailing: IconButton(icon: const Icon(Icons.download_rounded, color: Colors.deepPurpleAccent), onPressed: () => _downloadMornyeTrack(item)))),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.menu_rounded, color: Colors.white70), onPressed: () {}), title: _isSearching ? TextField(controller: _searchController, autofocus: true, onChanged: _filterSongs, decoration: const InputDecoration(hintText: 'Search...', border: InputBorder.none)) : Text(tabTitles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)), actions: [IconButton(icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded), onPressed: () => setState(() { _isSearching = !_isSearching; if (!_isSearching) { _searchController.clear(); _filteredSongs = _songs; } })), IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white70), onPressed: _openSettings)]),
      body: Stack(children: [pages[_selectedIndex], Positioned(left: 12, right: 12, bottom: 10, child: _buildReactiveMiniPlayer())]),
      bottomNavigationBar: NavigationBar(backgroundColor: const Color(0xFF0A0A0F), selectedIndex: _selectedIndex, onDestinationSelected: (idx) => setState(() => _selectedIndex = idx), destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'), NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Tracks'), NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Artists'), NavigationDestination(icon: Icon(Icons.playlist_play_rounded), selectedIcon: Icon(Icons.playlist_add_check_rounded), label: 'Playlists'), NavigationDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension_rounded), label: 'Mornye')]),
    );
  }

  Widget _buildHomeCard(Uint8List? art, String title, String subtitle) {
    return Container(width: 160, margin: const EdgeInsets.only(right: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.25), borderRadius: BorderRadius.circular(16), image: art != null ? DecorationImage(image: MemoryImage(art), fit: BoxFit.cover, opacity: 0.3) : null), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 4), Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey))]));
  }

  Widget _buildPlaylistStatCard(String title, String count, IconData icon) {
    return Expanded(child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(16)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: Colors.deepPurpleAccent, size: 20), const SizedBox(height: 8), Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))]), Text(count, style: const TextStyle(fontSize: 16, color: Colors.grey))])));
  }

  String _formatDurationPadded(Duration d) {
    int minutes = d.inMinutes; int seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
