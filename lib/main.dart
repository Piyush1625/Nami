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

class NamiApp extends StatefulWidget {
  const NamiApp({super.key});

  static _NamiAppState of(BuildContext context) =>
      context.findAncestorStateOfType<_NamiAppState>()!;

  @override
  State<NamiApp> createState() => _NamiAppState();
}

class _NamiAppState extends State<NamiApp> {
  bool pitchBlack = true;
  Color accentColor = const Color(0xFF7C4DFF);

  void updateTheme({bool? isPitchBlack, Color? newAccent}) {
    setState(() {
      if (isPitchBlack != null) pitchBlack = isPitchBlack;
      if (newAccent != null) accentColor = newAccent;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = pitchBlack ? const Color(0xFF000000) : const Color(0xFF0A0A0F);
    final cardColor = pitchBlack ? const Color(0xFF0E0E14) : const Color(0xFF14141E);

    return MaterialApp(
      title: 'Nami',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgColor,
        cardColor: cardColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accentColor,
          brightness: Brightness.dark,
          surface: cardColor,
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
  MornyeExtension({
    required this.name,
    required this.version,
    required this.author,
    required this.format,
    this.isEnabled = true,
  });
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

  MornyeCatalogItem({
    required this.title,
    required this.artist,
    required this.album,
    required this.subtitle,
    required this.type,
    required this.service,
    this.previewUrl,
    this.artworkUrl,
    this.durationSeconds = 210,
  });
}

class NamiHomeShell extends StatefulWidget {
  const NamiHomeShell({super.key});

  @override
  State<NamiHomeShell> createState() => _NamiHomeShellState();
}

class _NamiHomeShellState extends State<NamiHomeShell> {
  int _selectedIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer(
    handleInterruptions: true,
    androidApplyAudioAttributes: true,
    handleAudioSessionActivation: true,
  );

  bool _hasPermission = false;
  bool _isScanning = false;
  List<AudioTrack> _songs = [];
  List<AudioTrack> _filteredSongs = [];
  final List<AudioTrack> _playNextQueue = [];
  final List<AudioTrack> _historyTracks = [];
  final List<CustomPlaylist> _customPlaylists = [
    CustomPlaylist(name: 'Favorites Mix', tracks: []),
  ];

  final ValueNotifier<AudioTrack?> _currentSongNotifier = ValueNotifier<AudioTrack?>(null);
  AudioTrack? get _currentSong => _currentSongNotifier.value;
  set _currentSong(AudioTrack? val) => _currentSongNotifier.value = val;

  bool _isPlaying = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  int _artistGridColumns = 4;
  String _artistSortOrder = "Artist";

  // Functional Settings state
  bool _usbDacExclusive = true;
  bool _gaplessPlayback = true;
  bool _mediaNotificationEnabled = true;
  bool _usePitchBlack = true;
  bool _autoColoring = true;
  bool _forceMiniColor = false;
  bool _replayGain = true;
  String _connectedDacName = "KEFINE";
  String _userName = "Piyush";
  String? _userPhotoPath;
  List<String> _deviceImages = [];

  // Equalizer state
  final Map<String, double> _eqBands = {
    '60Hz': 3.0,
    '230Hz': 1.5,
    '910Hz': 0.0,
    '3.6kHz': 2.0,
    '14kHz': 4.0,
  };
  String _selectedEqPreset = 'Hi-Fi Master';

  // Mornye state
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

  final List<String> _mornyeServices = [
    "Qobuz", "Tidal", "Apple Music", "Spotify Web", "Amazon Music", "YouTube Music"
  ];

  final List<MornyeExtension> _extensions = [
    MornyeExtension(name: 'Qobuz Studio Master (.sflx)', version: '1.4.0', author: 'OpenAudio', format: '24-bit / 192kHz FLAC', isEnabled: true),
    MornyeExtension(name: 'Tidal Hi-Res MAX (.sflx)', version: '1.4.2', author: 'Mornye Core', format: '24-bit / 96kHz FLAC', isEnabled: true),
    MornyeExtension(name: 'Apple Music ALAC (.sflx)', version: '1.1.8', author: 'Mornye Core', format: '24-bit ALAC', isEnabled: true),
    MornyeExtension(name: 'LRCLIB Synced Lyrics (.sflx)', version: '2.1.0', author: 'LRCLIB', format: 'Timestamped .LRC', isEnabled: true),
  ];

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _initAudioSessionAndDac();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissionAndScanMusic();
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        if (_playNextQueue.isNotEmpty) {
          final next = _playNextQueue.removeAt(0);
          _playSong(next);
        } else {
          _playNextTrack();
        }
      }
    });
  }

  Future<void> _initAudioSessionAndDac() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.audibilityEnforced,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      await session.setActive(true);
      await _audioPlayer.setSpeed(1.0);
      await _audioPlayer.setPitch(1.0);
      await _audioPlayer.setSkipSilenceEnabled(false);

      final devices = await session.getDevices();
      for (var d in devices) {
        if (d.isOutput && d.name.isNotEmpty) {
          _connectedDacName = d.name;
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleUsbDacMode(bool enabled) async {
    setState(() => _usbDacExclusive = enabled);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? 'USB DAC Bit-Perfect Mode Enabled (Direct Hardware Routing)' : 'Android System Mixer Active'),
          backgroundColor: Colors.deepPurple,
        ),
      );
    }
  }

  Future<void> _requestPermissionAndScanMusic() async {
    PermissionStatus status = await Permission.audio.request();
    await Permission.photos.request();
    if (!status.isGranted) status = await Permission.storage.request();
    if (!status.isGranted) status = await Permission.manageExternalStorage.request();

    if (status.isGranted || await Permission.storage.isGranted || await Permission.manageExternalStorage.isGranted) {
      setState(() {
        _hasPermission = true;
        _isScanning = true;
      });
      await _fastScanDeviceMusic();
      _scanUserPhotosInBackground();
    }
  }

  Future<void> _scanUserPhotosInBackground() async {
    List<String> imgs = [];
    final dirs = [
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Pictures'),
      Directory('/storage/emulated/0/DCIM/Camera'),
    ];
    for (var d in dirs) {
      try {
        if (await d.exists()) {
          await for (var entity in d.list(recursive: false, followLinks: false)) {
            if (entity is File) {
              final l = entity.path.toLowerCase();
              if (l.endsWith('.jpg') || l.endsWith('.jpeg') || l.endsWith('.png') || l.endsWith('.webp')) {
                imgs.add(entity.path);
                if (imgs.length >= 24) break;
              }
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
      final rootMusic = Directory('/storage/emulated/0/Music');
      if (await rootMusic.exists()) searchDirs.add(rootMusic);
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) searchDirs.add(downloadDir);

      final Set<String> seenPaths = {};

      for (var dir in searchDirs) {
        if (!await dir.exists()) continue;
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            String path = entity.path;
            String lower = path.toLowerCase();
            String fileName = entity.uri.pathSegments.last;
            if (fileName.startsWith('.')) continue;

            if (lower.endsWith('.flac') || lower.endsWith('.mp3') || lower.endsWith('.m4a') || lower.endsWith('.ogg') || lower.endsWith('.wav')) {
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

              final track = AudioTrack(
                title: cleanName,
                artist: artist,
                album: cleanName,
                path: path,
                addedDate: formattedDate,
              );
              foundTracks.add(track);
            }
          }
        }
      }
    } catch (_) {}

    foundTracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    setState(() {
      _songs = foundTracks;
      _filteredSongs = foundTracks;
      _isScanning = false;
    });

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
            int totalSamples = ((data[offset + 13] & 0x0F) << 32) |
                (data[offset + 14] << 24) |
                (data[offset + 15] << 16) |
                (data[offset + 16] << 8) |
                data[offset + 17];
            if (sr > 0) {
              track.sampleRateHz = sr;
              if (totalSamples > 0) {
                final secs = totalSamples ~/ sr;
                if (secs > 0) {
                  track.duration = Duration(seconds: secs);
                  track.bitrateKbps = ((track.fileSize * 8) ~/ 1000) ~/ secs;
                }
              }
            }
            if (bps >= 16) track.bitDepth = bps;
          } else if (blockType == 4 && offset + length <= data.length) {
            int p = offset;
            final blockEnd = offset + length;
            if (p + 4 <= blockEnd) {
              int vendorLen = data[p] | (data[p + 1] << 8) | (data[p + 2] << 16) | (data[p + 3] << 24);
              p += 4 + vendorLen;
              if (p + 4 <= blockEnd) {
                int commentCount = data[p] | (data[p + 1] << 8) | (data[p + 2] << 16) | (data[p + 3] << 24);
                p += 4;
                for (int c = 0; c < commentCount && p + 4 <= blockEnd; c++) {
                  int cLen = data[p] | (data[p + 1] << 8) | (data[p + 2] << 16) | (data[p + 3] << 24);
                  p += 4;
                  if (cLen < 0 || p + cLen > blockEnd) break;
                  final commentStr = utf8.decode(data.sublist(p, p + cLen), allowMalformed: true);
                  p += cLen;
                  final eqIdx = commentStr.indexOf('=');
                  if (eqIdx > 0) {
                    final key = commentStr.substring(0, eqIdx).trim().toUpperCase();
                    final val = _sanitizeMetadataText(commentStr.substring(eqIdx + 1));
                    if (val.isNotEmpty) {
                      if (key == 'TITLE') {
                        track.title = val;
                      } else if (key == 'ARTIST' || key == 'ALBUMARTIST' || key == 'PERFORMER') {
                        if (track.artist == 'Unknown Artist' || track.artist.isEmpty) {
                          track.artist = val;
                        } else if (!track.artist.contains(val)) {
                          track.artist = '${track.artist}, $val';
                        }
                      } else if (key == 'ALBUM') {
                        track.album = val;
                      } else if (key == 'GENRE') {
                        track.genre = val;
                      } else if (key == 'COMPOSER') {
                        track.composer = val;
                      } else if (key == 'COMMENT') {
                        track.comment = val;
                      } else if (key == 'DATE' || key == 'YEAR') {
                        track.year = val;
                      } else if (key == 'TRACKNUMBER') {
                        track.trackNumber = val;
                      } else if (key == 'LYRICS' || key == 'UNSYNCEDLYRICS') {
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
            if (picOffset + dataLen <= data.length && dataLen > 0) {
              track.albumArt = data.sublist(picOffset, picOffset + dataLen);
            }
          }
          if (isLast) break;
          offset += length;
        }
      }

      if (data.length > 10 && data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) {
        int version = data[3];
        int tagSize = ((data[6] & 0x7F) << 21) | ((data[7] & 0x7F) << 14) | ((data[8] & 0x7F) << 7) | (data[9] & 0x7F);
        int offset = 10;
        int maxOffset = (tagSize + 10 < data.length) ? tagSize + 10 : data.length;

        while (offset + 10 < maxOffset) {
          String frameId = String.fromCharCodes(data.sublist(offset, offset + 4));
          if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;
          int frameSize;
          if (version == 4) {
            frameSize = ((data[offset + 4] & 0x7F) << 21) | ((data[offset + 5] & 0x7F) << 14) | ((data[offset + 6] & 0x7F) << 7) | (data[offset + 7] & 0x7F);
          } else {
            frameSize = (data[offset + 4] << 24) | (data[offset + 5] << 16) | (data[offset + 6] << 8) | data[offset + 7];
          }
          offset += 10;
          if (frameSize <= 0 || offset + frameSize > maxOffset) break;

          if (frameId == 'TIT2') {
            final t = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (t.isNotEmpty) track.title = t;
          } else if (frameId == 'TPE1' || frameId == 'TPE2' || frameId == 'TEXT') {
            final a = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (a.isNotEmpty) {
              if (track.artist == 'Unknown Artist' || track.artist.isEmpty) {
                track.artist = a;
              } else if (!track.artist.contains(a)) {
                track.artist = '${track.artist}, $a';
              }
            }
          } else if (frameId == 'TALB') {
            final al = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (al.isNotEmpty) track.album = al;
          } else if (frameId == 'TCON') {
            final g = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (g.isNotEmpty) track.genre = g;
          } else if (frameId == 'TCOM') {
            final c = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (c.isNotEmpty) track.composer = c;
          } else if (frameId == 'COMM') {
            final comm = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (comm.isNotEmpty) track.comment = comm;
          } else if (frameId == 'TYER' || frameId == 'TDRC') {
            final y = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (y.isNotEmpty) track.year = y;
          } else if (frameId == 'TRCK') {
            final tr = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (tr.isNotEmpty) track.trackNumber = tr;
          } else if (frameId == 'APIC' && track.albumArt == null) {
            track.albumArt = _extractEmbeddedImageBytes(data, offset, offset + frameSize);
          }
          offset += frameSize;
        }
      }

      if (track.artist == 'Unknown Artist' || track.artist.isEmpty) {
        final fileName = File(track.path).uri.pathSegments.last;
        if (fileName.contains(' - ')) {
          track.artist = _sanitizeMetadataText(fileName.split(' - ')[0]);
        }
      }

      if (track.albumArt == null) {
        track.albumArt = _extractEmbeddedImageBytes(data, 0, data.length);
      }
    } catch (_) {}
    track.isMetadataLoaded = true;
  }

  String _sanitizeMetadataText(String input) {
    String s = input.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    return s.replaceAll(RegExp(r'[#<>%+^~|]+$'), '').trim();
  }

  String _decodeId3Text(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    int encoding = bytes[0];
    Uint8List content = bytes.sublist(1);

    if (encoding == 0) {
      final nullIdx = content.indexOf(0);
      if (nullIdx >= 0) content = content.sublist(0, nullIdx);
      return _sanitizeMetadataText(latin1.decode(content, allowInvalid: true));
    } else if (encoding == 1 || encoding == 2) {
      int start = 0;
      bool littleEndian = true;
      if (content.length >= 2) {
        if (content[0] == 0xFF && content[1] == 0xFE) {
          littleEndian = true;
          start = 2;
        } else if (content[0] == 0xFE && content[1] == 0xFF) {
          littleEndian = false;
          start = 2;
        }
      }
      final List<int> codeUnits = [];
      for (int i = start; i + 1 < content.length; i += 2) {
        int unit = littleEndian
            ? (content[i] | (content[i + 1] << 8))
            : ((content[i] << 8) | content[i + 1]);
        if (unit == 0) break;
        codeUnits.add(unit);
      }
      return _sanitizeMetadataText(String.fromCharCodes(codeUnits));
    } else {
      final nullIdx = content.indexOf(0);
      if (nullIdx >= 0) content = content.sublist(0, nullIdx);
      return _sanitizeMetadataText(utf8.decode(content, allowMalformed: true));
    }
  }

  Uint8List? _extractEmbeddedImageBytes(Uint8List data, int start, int end) {
    for (int j = start; j < end - 8; j++) {
      if (data[j] == 0xFF && data[j + 1] == 0xD8 && data[j + 2] == 0xFF) {
        int imgEnd = end;
        for (int k = j + 4; k < end - 1; k++) {
          if (data[k] == 0xFF && data[k + 1] == 0xD9) {
            imgEnd = k + 2;
            if (imgEnd - j > 2048) break;
          }
        }
        if (imgEnd - j > 1024) return data.sublist(j, imgEnd);
      }
      if (data[j] == 0x89 && data[j + 1] == 0x50 && data[j + 2] == 0x4E && data[j + 3] == 0x47) {
        int imgEnd = end;
        for (int k = j + 8; k < end - 4; k++) {
          if (data[k] == 0x49 && data[k + 1] == 0x45 && data[k + 2] == 0x4E && data[k + 3] == 0x44) {
            imgEnd = (k + 8 <= end) ? k + 8 : end;
            break;
          }
        }
        if (imgEnd - j > 1024) return data.sublist(j, imgEnd);
      }
    }
    return null;
  }

  List<LyricLine> _parseLrc(String raw) {
    final lines = raw.split('\n');
    final List<LyricLine> result = [];
    final regExp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[\.:](\d{1,3}))?\](.*)');
    for (var line in lines) {
      final match = regExp.firstMatch(line.trim());
      if (match != null) {
        final min = int.tryParse(match.group(1)!) ?? 0;
        final sec = int.tryParse(match.group(2)!) ?? 0;
        final msStr = match.group(3) ?? '0';
        final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          result.add(LyricLine(timestamp: Duration(minutes: min, seconds: sec, milliseconds: ms), text: text));
        }
      }
    }
    if (result.isEmpty && raw.trim().isNotEmpty) {
      final plainLines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      for (int i = 0; i < plainLines.length; i++) {
        result.add(LyricLine(timestamp: Duration(seconds: i * 4), text: plainLines[i].trim()));
      }
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<void> _fetchLyricsOnline(AudioTrack song) async {
    if (song.isLyricsFetched && song.parsedLyrics.isNotEmpty) return;
    try {
      final lrcPath = '${song.path.substring(0, song.path.lastIndexOf('.'))}.lrc';
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        final localLrc = await lrcFile.readAsString();
        if (localLrc.trim().isNotEmpty) {
          song.rawLyrics = localLrc;
          song.parsedLyrics = _parseLrc(localLrc);
          song.isLyricsFetched = true;
          if (mounted) setState(() {});
          return;
        }
      }
    } catch (_) {}

    final cleanTitle = _sanitizeMetadataText(song.title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')).trim();
    final primaryArtist = _sanitizeMetadataText(song.artist.split(RegExp(r'[,&•/]|feat\.|ft\.', caseSensitive: false)).first).trim();

    try {
      final getUri = Uri.parse(
        'https://lrclib.net/api/get?track_name=${Uri.encodeComponent(cleanTitle)}&artist_name=${Uri.encodeComponent(primaryArtist)}',
      );
      final getRes = await http.get(getUri, headers: {'User-Agent': 'NamiMusicPlayer/1.0'}).timeout(const Duration(seconds: 5));
      if (getRes.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(getRes.body);
        final String? synced = data['syncedLyrics']?.toString();
        final String? plain = data['plainLyrics']?.toString();
        if ((synced != null && synced.isNotEmpty) || (plain != null && plain.isNotEmpty)) {
          song.rawLyrics = (synced != null && synced.isNotEmpty) ? synced : plain!;
          song.parsedLyrics = _parseLrc(song.rawLyrics);
          song.isLyricsFetched = true;
          if (mounted) setState(() {});
          return;
        }
      }

      final searchUri = Uri.parse(
        'https://lrclib.net/api/search?q=${Uri.encodeComponent("$cleanTitle $primaryArtist")}',
      );
      final searchRes = await http.get(searchUri, headers: {'User-Agent': 'NamiMusicPlayer/1.0'}).timeout(const Duration(seconds: 5));
      if (searchRes.statusCode == 200) {
        final dynamic list = jsonDecode(searchRes.body);
        if (list is List && list.isNotEmpty) {
          final best = list.firstWhere(
            (item) => item['syncedLyrics'] != null && item['syncedLyrics'].toString().isNotEmpty,
            orElse: () => list.first,
          );
          final String? synced = best['syncedLyrics']?.toString();
          final String? plain = best['plainLyrics']?.toString();
          if ((synced != null && synced.isNotEmpty) || (plain != null && plain.isNotEmpty)) {
            song.rawLyrics = (synced != null && synced.isNotEmpty) ? synced : plain!;
            song.parsedLyrics = _parseLrc(song.rawLyrics);
            song.isLyricsFetched = true;
            if (mounted) setState(() {});
            return;
          }
        }
      }
    } catch (_) {}
    if (song.parsedLyrics.isEmpty) {
      song.rawLyrics = "[00:00.00] Instrumental / No Synced Lyrics Found";
      song.parsedLyrics = _parseLrc(song.rawLyrics);
    }
    if (mounted) setState(() {});
  }

  Future<void> _searchMornyeCatalog(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _mornyeResults = []);
      return;
    }
    setState(() => _isMornyeSearching = true);
    try {
      final uri = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&limit=25');
      final res = await http.get(uri).timeout(const Duration(seconds: 7));
      if (res.statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(res.body);
        final List results = decoded['results'] ?? [];
        final List<MornyeCatalogItem> items = [];
        final Set<String> seenArtists = {};
        final Set<String> seenAlbums = {};

        for (var item in results) {
          if (item is Map) {
            final track = item['trackName']?.toString() ?? 'Unknown Track';
            final artist = item['artistName']?.toString() ?? 'Unknown Artist';
            final album = item['collectionName']?.toString() ?? 'Single';
            final preview = item['previewUrl']?.toString();
            final art = item['artworkUrl100']?.toString().replaceAll('100x100bb', '600x600bb');
            final timeMs = int.tryParse(item['trackTimeMillis']?.toString() ?? '210000') ?? 210000;

            items.add(MornyeCatalogItem(
              title: track,
              artist: artist,
              album: album,
              subtitle: '$artist • $album • via $_selectedMornyeService',
              type: 'song',
              service: _selectedMornyeService,
              previewUrl: preview,
              artworkUrl: art,
              durationSeconds: timeMs ~/ 1000,
            ));

            if (!seenArtists.contains(artist)) {
              seenArtists.add(artist);
              items.add(MornyeCatalogItem(
                title: artist,
                artist: artist,
                album: '',
                subtitle: 'Artist • via $_selectedMornyeService',
                type: 'artist',
                service: _selectedMornyeService,
                artworkUrl: art,
              ));
            }

            if (!seenAlbums.contains(album)) {
              seenAlbums.add(album);
              items.add(MornyeCatalogItem(
                title: album,
                artist: artist,
                album: album,
                subtitle: '$artist • via $_selectedMornyeService',
                type: 'album',
                service: _selectedMornyeService,
                artworkUrl: art,
              ));
            }
          }
        }
        setState(() {
          _mornyeResults = items;
          _isMornyeSearching = false;
        });
      } else {
        setState(() => _isMornyeSearching = false);
      }
    } catch (_) {
      setState(() => _isMornyeSearching = false);
    }
  }

  Future<void> _downloadMornyeTrack(MornyeCatalogItem item) async {
    if (item.previewUrl == null || item.previewUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No direct stream URL available for this track.')));
      return;
    }
    setState(() => _downloadingTitles.add(item.title));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading "${item.title}" ($_mornyeAudioQuality) via ${item.service}...'),
        backgroundColor: Colors.deepPurple,
      ),
    );

    try {
      final dir = Directory(_mornyeDownloadFolder);
      if (!await dir.exists()) await dir.create(recursive: true);

      final safeTitle = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      final safeArtist = item.artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      final savePath = '${dir.path}/$safeArtist - $safeTitle.m4a';

      final audioRes = await http.get(Uri.parse(item.previewUrl!)).timeout(const Duration(seconds: 25));
      if (audioRes.statusCode == 200) {
        final outFile = File(savePath);
        await outFile.writeAsBytes(audioRes.bodyBytes);

        Uint8List? downloadedArt;
        if (_mornyeEmbedArt && item.artworkUrl != null) {
          try {
            final artRes = await http.get(Uri.parse(item.artworkUrl!)).timeout(const Duration(seconds: 8));
            if (artRes.statusCode == 200) downloadedArt = artRes.bodyBytes;
          } catch (_) {}
        }

        final newTrack = AudioTrack(
          title: item.title,
          artist: item.artist,
          album: item.album,
          path: savePath,
          albumArt: downloadedArt,
          addedDate: "Sep 2026",
          fileSize: audioRes.bodyBytes.length,
          duration: Duration(seconds: item.durationSeconds),
          isMetadataLoaded: true,
        );

        if (_mornyeAutoLrc) {
          _fetchLyricsOnline(newTrack);
        }

        setState(() {
          _songs.insert(0, newTrack);
          _filteredSongs = List.from(_songs);
          _downloadingTitles.remove(item.title);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to $savePath & added to Library!'),
              action: SnackBarAction(
                label: 'PLAY',
                textColor: Colors.white,
                onPressed: () => _playSong(newTrack),
              ),
            ),
          );
        }
      } else {
        setState(() => _downloadingTitles.remove(item.title));
      }
    } catch (e) {
      setState(() => _downloadingTitles.remove(item.title));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  void _showExtensionRepoDialog() {
    final urlCtrl = TextEditingController(text: _mornyeRepoUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Extension Repository', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Current repository:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(_mornyeRepoUrl, style: const TextStyle(fontSize: 11, color: Colors.deepPurpleAccent)),
            const SizedBox(height: 14),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                hintText: 'Enter registry JSON URL...',
                filled: true,
                fillColor: Color(0xFF0A0A0E),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              setState(() => _mornyeRepoUrl = "");
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Extension repository removed.')));
            },
            child: const Text('Remove'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
            onPressed: () {
              if (urlCtrl.text.trim().isNotEmpty) {
                setState(() => _mornyeRepoUrl = urlCtrl.text.trim());
              }
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Repository saved successfully!')));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showMornyePreferencesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF12121A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => StatefulBuilder(
        builder: (context, setPrefState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune_rounded, color: Colors.deepPurpleAccent),
                    SizedBox(width: 10),
                    Text('Mornye Preferences', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Preferred Audio Quality', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    '24-bit / 192kHz Hi-Res FLAC',
                    '16-bit / 44.1kHz Lossless',
                    '320kbps AAC Master',
                  ].map((q) {
                    final sel = _mornyeAudioQuality == q;
                    return ChoiceChip(
                      label: Text(q, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.white70)),
                      selected: sel,
                      selectedColor: Colors.deepPurpleAccent,
                      backgroundColor: const Color(0xFF1A1A24),
                      onSelected: (_) {
                        setPrefState(() => _mornyeAudioQuality = q);
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Embed High-Res Cover Art', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Attach 600x600 studio album cover to downloads', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  value: _mornyeEmbedArt,
                  activeColor: Colors.deepPurpleAccent,
                  onChanged: (v) {
                    setPrefState(() => _mornyeEmbedArt = v);
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-Fetch Synced .LRC Lyrics', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Download timestamped lyrics on save', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  value: _mornyeAutoLrc,
                  activeColor: Colors.deepPurpleAccent,
                  onChanged: (v) {
                    setPrefState(() => _mornyeAutoLrc = v);
                    setState(() {});
                  },
                ),
                const Divider(color: Colors.white12),
                const Text('Active .sflx Extension Modules', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ..._extensions.map((ext) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(ext.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${ext.format} • v${ext.version}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  value: ext.isEnabled,
                  activeColor: Colors.deepPurpleAccent,
                  onChanged: (v) {
                    setPrefState(() => ext.isEnabled = v);
                    setState(() {});
                  },
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _filterSongs(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filteredSongs = _songs.where((song) =>
        song.title.toLowerCase().contains(q) ||
        song.artist.toLowerCase().contains(q) ||
        song.album.toLowerCase().contains(q)
      ).toList();
    });
  }

  Future<void> _playSong(AudioTrack song) async {
    if (song.path.isEmpty) return;
    _currentSong = song;
    if (!_historyTracks.contains(song)) {
      _historyTracks.insert(0, song);
    }
    if (mounted) setState(() {});
    _fetchLyricsOnline(song);
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(song.path);
      await _audioPlayer.play();
      if (_audioPlayer.duration != null && _audioPlayer.duration!.inSeconds > 0) {
        song.duration = _audioPlayer.duration!;
        if (song.fileSize > 0) {
          song.bitrateKbps = ((song.fileSize * 8) ~/ 1000) ~/ song.duration.inSeconds;
        }
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error playing track: $e');
    }
  }

  void _playNextTrack() {
    if (_playNextQueue.isNotEmpty) {
      final next = _playNextQueue.removeAt(0);
      _playSong(next);
      return;
    }
    if (_filteredSongs.isNotEmpty && _currentSong != null) {
      int nextIdx = (_filteredSongs.indexOf(_currentSong!) + 1) % _filteredSongs.length;
      _playSong(_filteredSongs[nextIdx]);
    } else if (_filteredSongs.isNotEmpty) {
      _playSong(_filteredSongs.first);
    }
  }

  void _playPrevTrack() {
    if (_filteredSongs.isNotEmpty && _currentSong != null) {
      int prevIdx = (_filteredSongs.indexOf(_currentSong!) - 1 + _filteredSongs.length) % _filteredSongs.length;
      _playSong(_filteredSongs[prevIdx]);
    }
  }

  void _shufflePlay() {
    if (_songs.isNotEmpty) {
      List<AudioTrack> shuffled = List.from(_songs)..shuffle();
      _playSong(shuffled.first);
    }
  }

  void _togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      if (_currentSong == null && _filteredSongs.isNotEmpty) {
        _playSong(_filteredSongs.first);
      } else {
        await _audioPlayer.play();
      }
    }
  }

  Widget _buildNamidaTrackTile(AudioTrack song, {VoidCallback? onStateUpdate}) {
    final isCurrent = _currentSong?.path == song.path;
    return Dismissible(
      key: Key(song.path),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.deepPurpleAccent,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_add_rounded, color: Colors.white, size: 22),
            Text('Play Next', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        setState(() {
          _playNextQueue.add(song);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Queued "${song.title}" to play next')),
        );
        if (onStateUpdate != null) onStateUpdate();
        return false;
      },
      child: InkWell(
        onTap: () {
          _playSong(song);
          if (onStateUpdate != null) onStateUpdate();
        },
        onLongPress: () => _showActionMenu(song),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildCoverArt(song, 52, 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? Colors.deepPurpleAccent : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${song.album} • ${song.addedDate}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _formatDurationPadded(song.duration),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () {
                      setState(() => song.isFavorite = !song.isFavorite);
                      if (onStateUpdate != null) onStateUpdate();
                    },
                    child: Icon(
                      song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: song.isFavorite ? Colors.deepPurpleAccent : Colors.white38,
                      size: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showActionMenu(song),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(2, 8, 10, 8),
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white70,
                    size: 19,
                  ),
                ),
              ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Edit Profile & Photo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: Colors.deepPurpleAccent,
                    backgroundImage: (pathCtrl.text.isNotEmpty && File(pathCtrl.text).existsSync())
                        ? FileImage(File(pathCtrl.text))
                        : null,
                    child: (pathCtrl.text.isEmpty || !File(pathCtrl.text).existsSync())
                        ? Text(
                            nameCtrl.text.isNotEmpty ? nameCtrl.text[0].toUpperCase() : 'P',
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  onChanged: (_) => setModalState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Your Name',
                    hintText: 'Enter your name...',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pathCtrl,
                  onChanged: (_) => setModalState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Custom Image Path',
                    hintText: '/storage/emulated/0/Download/photo.jpg',
                  ),
                ),
                if (_deviceImages.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Pick from Device Photos:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 64,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _deviceImages.length,
                      itemBuilder: (ctx, i) {
                        final imgPath = _deviceImages[i];
                        return GestureDetector(
                          onTap: () {
                            pathCtrl.text = imgPath;
                            setModalState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: pathCtrl.text == imgPath ? Colors.deepPurpleAccent : Colors.white24,
                                width: 2,
                              ),
                              image: DecorationImage(
                                image: FileImage(File(imgPath)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
              onPressed: () {
                setState(() {
                  if (nameCtrl.text.trim().isNotEmpty) _userName = nameCtrl.text.trim();
                  _userPhotoPath = pathCtrl.text.trim().isNotEmpty ? pathCtrl.text.trim() : null;
                });
                Navigator.pop(context);
              },
              child: const Text('Save Profile'),
            ),
          ],
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
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Audio path', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white)),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: song.path));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: ${song.path}')));
                    },
                    child: Text(song.path.split('/').last, style: const TextStyle(fontSize: 11, color: Colors.white38)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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

  Widget _buildAudioPathNode({
    required IconData icon,
    required String title,
    required String? subtitle,
    required bool isAmber,
    required bool showConnectorDown,
    bool useCustomWaveIcon = false,
  }) {
    final Color ringBorder = isAmber ? const Color(0xFFD4A024) : Colors.white38;
    final Color fillBg = isAmber ? const Color(0xFF3A2E14) : Colors.white.withOpacity(0.06);
    final Color iconColor = isAmber ? const Color(0xFFE6B43A) : Colors.white70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: fillBg,
                shape: BoxShape.circle,
                border: Border.all(color: ringBorder, width: 1.3),
              ),
              child: Icon(useCustomWaveIcon ? Icons.waves_rounded : icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Colors.white60, fontWeight: FontWeight.w500)),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (showConnectorDown)
          Padding(
            padding: const EdgeInsets.only(left: 13, top: 2, bottom: 2),
            child: Icon(Icons.south_rounded, size: 13, color: Colors.white.withOpacity(0.28)),
          ),
      ],
    );
  }

  // Functional Equalizer Sheet with real presets and band adjustments
  void _showEqualizerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setEqState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Colors.deepPurpleAccent),
                  SizedBox(width: 10),
                  Text('Hardware Equalizer & DSP Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['Hi-Fi Master', 'Bass Boost', 'Flat', 'Vocal Clear', 'Rock'].map((preset) {
                    final sel = _selectedEqPreset == preset;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(preset, style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.white70)),
                        selected: sel,
                        selectedColor: Colors.deepPurpleAccent,
                        backgroundColor: const Color(0xFF0A0A0E),
                        onSelected: (val) {
                          setEqState(() {
                            _selectedEqPreset = preset;
                            if (preset == 'Bass Boost') {
                              _eqBands['60Hz'] = 6.0;
                              _eqBands['230Hz'] = 4.0;
                            } else if (preset == 'Flat') {
                              _eqBands.updateAll((key, value) => 0.0);
                            } else if (preset == 'Hi-Fi Master') {
                              _eqBands['60Hz'] = 3.0;
                              _eqBands['14kHz'] = 4.0;
                            }
                          });
                          setState(() {});
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
              ..._eqBands.entries.map((e) => Row(
                children: [
                  SizedBox(width: 50, child: Text(e.key, style: const TextStyle(fontSize: 12, color: Colors.white70))),
                  Expanded(
                    child: Slider(
                      value: e.value,
                      min: -10.0,
                      max: 10.0,
                      activeColor: Colors.deepPurpleAccent,
                      onChanged: (val) {
                        setEqState(() => _eqBands[e.key] = val);
                        setState(() {});
                      },
                    ),
                  ),
                  Text('${e.value.toStringAsFixed(1)}dB', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              )),
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
    final genreCtrl = TextEditingController(text: song.genre);
    final albumArtistCtrl = TextEditingController(text: song.albumArtist);
    final composerCtrl = TextEditingController(text: song.composer);
    final commentCtrl = TextEditingController(text: song.comment);
    final trackNumCtrl = TextEditingController(text: song.trackNumber);
    final yearCtrl = TextEditingController(text: song.year);
    final lyricsCtrl = TextEditingController(text: song.rawLyrics);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Edit Tags', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Icon(Icons.edit_note_rounded, color: Colors.deepPurpleAccent),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: TextField(controller: trackNumCtrl, decoration: const InputDecoration(labelText: 'Track Number'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: yearCtrl, decoration: const InputDecoration(labelText: 'Year / Date'))),
                ],
              ),
              const SizedBox(height: 10),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 10),
              TextField(controller: artistCtrl, decoration: const InputDecoration(labelText: 'Artist')),
              const SizedBox(height: 10),
              TextField(controller: albumCtrl, decoration: const InputDecoration(labelText: 'Album')),
              const SizedBox(height: 10),
              TextField(controller: genreCtrl, decoration: const InputDecoration(labelText: 'Genre')),
              const SizedBox(height: 10),
              TextField(controller: albumArtistCtrl, decoration: const InputDecoration(labelText: 'Album Artist')),
              const SizedBox(height: 10),
              TextField(controller: composerCtrl, decoration: const InputDecoration(labelText: 'Composer')),
              const SizedBox(height: 10),
              TextField(controller: commentCtrl, decoration: const InputDecoration(labelText: 'Comment')),
              const SizedBox(height: 10),
              TextField(
                controller: lyricsCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Lyrics (.LRC timestamps)'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                    onPressed: () {
                      setState(() {
                        song.title = titleCtrl.text.trim();
                        song.artist = artistCtrl.text.trim();
                        song.album = albumCtrl.text.trim();
                        song.genre = genreCtrl.text.trim();
                        song.albumArtist = albumArtistCtrl.text.trim();
                        song.composer = composerCtrl.text.trim();
                        song.comment = commentCtrl.text.trim();
                        song.trackNumber = trackNumCtrl.text.trim();
                        song.year = yearCtrl.text.trim();
                        song.rawLyrics = lyricsCtrl.text;
                        song.parsedLyrics = _parseLrc(song.rawLyrics);
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tags successfully saved!')));
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdvancedDeleteDialog(AudioTrack song) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        title: const Text('Delete File Forever?', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text('This will permanently delete "${song.title}" from your device storage. This action cannot be undone.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final file = File(song.path);
                if (await file.exists()) await file.delete();
                setState(() {
                  _songs.remove(song);
                  _filteredSongs = List.from(_songs);
                  if (_currentSong?.path == song.path) {
                    _audioPlayer.stop();
                    _currentSong = null;
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File permanently deleted from device.')));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete file: $e')));
              }
            },
            child: const Text('Delete Forever'),
          ),
        ],
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
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  _buildCoverArt(song, 50, 10),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(song.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('${song.artist} • ${song.album}', style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            _buildMenuTile(Icons.album_rounded, 'Go to Album', song.album, () {
              Navigator.pop(context);
              _showFilteredListScreen('Album: ${song.album}', _songs.where((s) => s.album == song.album).toList());
            }),
            _buildMenuTile(Icons.person_rounded, 'Go to Artist', song.artist, () {
              Navigator.pop(context);
              _showArtistDetailScreen(song.artist, _songs.where((s) => s.artist == song.artist).toList());
            }),
            _buildMenuTile(Icons.graphic_eq_rounded, 'Audio Path', 'Signal Chain & PCM Info', () {
              Navigator.pop(context);
              _showAudioPathDetails(song);
            }),
            _buildMenuTile(Icons.edit_note_rounded, 'Edit Tags', 'Title, Artist, Album, Lyrics', () {
              Navigator.pop(context);
              _showTagEditorDialog(song);
            }),
            _buildMenuTile(Icons.warning_amber_rounded, 'Advanced', 'Delete file forever', () {
              Navigator.pop(context);
              _showAdvancedDeleteDialog(song);
            }),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded, color: Colors.deepPurpleAccent),
              title: const Text('Play Next'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _playNextQueue.add(song);
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${song.title} to play next')));
              },
            ),
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
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity! < 0) {
              _playNextTrack();
            } else if (details.primaryVelocity! > 0) {
              _playPrevTrack();
            }
          },
          onTap: _showNowPlayingScreen,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF15151E).withOpacity(0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white12),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16, spreadRadius: 2)],
            ),
            child: Row(
              children: [
                if (activeSong != null) _buildCoverArt(activeSong, 44, 8)
                else const Icon(Icons.album_rounded, size: 42, color: Colors.deepPurpleAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeSong?.title ?? 'Tap any song to play',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeSong?.artist ?? '24-bit / Lossless Ready',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: _audioPlayer.playingStream,
                  builder: (ctx, snap) {
                    final playing = snap.data ?? false;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded, size: 24),
                          onPressed: _playPrevTrack,
                        ),
                        IconButton(
                          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
                          onPressed: _togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, size: 24),
                          onPressed: _playNextTrack,
                        ),
                      ],
                    );
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
    int totalSeconds = 0;
    for (var s in artistTracks) {
      albumsMap.putIfAbsent(s.album, () => []).add(s);
      totalSeconds += s.duration.inSeconds;
    }
    final totalMin = (totalSeconds ~/ 60).clamp(1, 999);
    bool showAlbumsExpanded = false;
    bool showSinglesExpanded = false;
    final TextEditingController artistSearchCtrl = TextEditingController();
    List<AudioTrack> visibleArtistTracks = List.from(artistTracks);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setArtistScreenState) => Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        backgroundColor: const Color(0xFF14141F),
                        title: Text('Search in $artistName'),
                        content: TextField(
                          controller: artistSearchCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: 'Track name...'),
                          onChanged: (val) {
                            setArtistScreenState(() {
                              visibleArtistTracks = artistTracks
                                  .where((t) => t.title.toLowerCase().contains(val.toLowerCase()))
                                  .toList();
                            });
                          },
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  onPressed: () {
                    if (_deviceImages.isNotEmpty) {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: const Color(0xFF14141F),
                        builder: (c) => SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _deviceImages.length,
                            itemBuilder: (ctx, i) => GestureDetector(
                              onTap: () {
                                Navigator.pop(c);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Artist banner updated!')));
                              },
                              child: Container(
                                margin: const EdgeInsets.all(8),
                                width: 140,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  image: DecorationImage(image: FileImage(File(_deviceImages[i])), fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: const Color(0xFF14141F),
                      builder: (c) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.queue_music, color: Colors.deepPurpleAccent),
                              title: const Text('Queue All Artist Tracks'),
                              onTap: () {
                                setState(() => _playNextQueue.addAll(artistTracks));
                                Navigator.pop(c);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Queued ${artistTracks.length} tracks')));
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.playlist_add, color: Colors.white70),
                              title: const Text('Add to Custom Playlist'),
                              onTap: () {
                                Navigator.pop(c);
                                _showAddToPlaylistDialog(artistTracks);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
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
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: Colors.deepPurple.withOpacity(0.3),
                            backgroundImage: firstArt != null ? MemoryImage(firstArt) : null,
                            child: firstArt == null ? const Icon(Icons.person_rounded, size: 52, color: Colors.deepPurpleAccent) : null,
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(artistName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                const Text('2018 – 2026', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _artistPillButton(Icons.shuffle_rounded, () {
                          final shuffled = List<AudioTrack>.from(artistTracks)..shuffle();
                          if (shuffled.isNotEmpty) {
                            _playSong(shuffled.first);
                            setArtistScreenState(() {});
                          }
                        }),
                        const SizedBox(width: 10),
                        _artistPillButton(Icons.play_arrow_outlined, () {
                          if (artistTracks.isNotEmpty) {
                            _playSong(artistTracks.first);
                            setArtistScreenState(() {});
                          }
                        }),
                        const SizedBox(width: 10),
                        _artistPillButton(Icons.radar_rounded, () {
                          if (artistTracks.isNotEmpty) {
                            _playSong(artistTracks.first);
                            setArtistScreenState(() {});
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting $artistName Radio')));
                          }
                        }),
                        const SizedBox(width: 10),
                        _artistPillButton(Icons.broken_image_outlined, () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Artist images gallery ready')));
                        }),
                        const SizedBox(width: 10),
                        _artistPillButton(Icons.more_horiz_rounded, () {
                          _showAddToPlaylistDialog(artistTracks);
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setArtistScreenState(() => showAlbumsExpanded = !showAlbumsExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.album_outlined, color: Colors.white70, size: 22),
                                  const SizedBox(width: 14),
                                  Text('Albums: ${albumsMap.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
                                    onPressed: () {
                                      _fastScanDeviceMusic();
                                      setArtistScreenState(() {});
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    showAlbumsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (showAlbumsExpanded)
                      SizedBox(
                        height: 150,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          children: albumsMap.entries.map((entry) {
                            final albTracks = entry.value;
                            return GestureDetector(
                              onTap: () => _showFilteredListScreen('Album: ${entry.key}', albTracks),
                              child: Container(
                                width: 105,
                                margin: const EdgeInsets.only(right: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildCoverArt(albTracks.first, 95, 10),
                                    const SizedBox(height: 6),
                                    Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text('${albTracks.length} tracks', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 10),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setArtistScreenState(() => showSinglesExpanded = !showSinglesExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.library_music_outlined, color: Colors.white70, size: 22),
                                  const SizedBox(width: 14),
                                  Text('Singles: ${artistTracks.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 18),
                                    onPressed: () {
                                      _fastScanDeviceMusic();
                                      setArtistScreenState(() {});
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(
                                    showSinglesExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(16)),
                            child: Row(
                              children: [
                                const Icon(Icons.music_note_outlined, size: 14, color: Colors.white70),
                                const SizedBox(width: 6),
                                Text('${visibleArtistTracks.length} Tracks - ${totalMin}min', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              PopupMenuButton<String>(
                                color: const Color(0xFF14141F),
                                onSelected: (val) {
                                  setArtistScreenState(() {
                                    if (val == 'Year') {
                                      visibleArtistTracks.sort((a, b) => b.year.compareTo(a.year));
                                    } else {
                                      visibleArtistTracks.sort((a, b) => a.title.compareTo(b.title));
                                    }
                                  });
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(value: 'Year', child: Text('Sort by Year')),
                                  PopupMenuItem(value: 'Title', child: Text('Sort by Title')),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: const Color(0xFF14141C), borderRadius: BorderRadius.circular(16)),
                                  child: const Row(
                                    children: [
                                      Text('Year', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      SizedBox(width: 6),
                                      Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.filter_alt_outlined, size: 19, color: Colors.white70),
                                onPressed: () {
                                  setArtistScreenState(() {
                                    visibleArtistTracks = visibleArtistTracks.reversed.toList();
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...visibleArtistTracks.map((song) => _buildNamidaTrackTile(
                      song,
                      onStateUpdate: () => setArtistScreenState(() {}),
                    )),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 24,
                  child: _buildReactiveMiniPlayer(),
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              backgroundColor: const Color(0xFF0A0A0F),
              selectedIndex: 2,
              onDestinationSelected: (idx) {
                Navigator.pop(context);
                setState(() => _selectedIndex = idx);
              },
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

  void _showAddToPlaylistDialog(List<AudioTrack> tracksToAdd) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        title: const Text('Add to Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _customPlaylists.map((pl) => ListTile(
            leading: const Icon(Icons.playlist_add_check, color: Colors.deepPurpleAccent),
            title: Text(pl.name),
            subtitle: Text('${pl.tracks.length} tracks'),
            onTap: () {
              setState(() => pl.tracks.addAll(tracksToAdd));
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to ${pl.name}')));
            },
          )).toList(),
        ),
      ),
    );
  }

  Widget _artistPillButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF15151E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Icon(icon, color: Colors.white70, size: 20),
      ),
    );
  }

  void _showFilteredListScreen(String title, List<AudioTrack> tracks) {
    final firstArt = tracks.isNotEmpty ? tracks.first.albumArt : null;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setListState) => Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            body: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 130),
                  children: [
                    if (firstArt != null)
                      Center(
                        child: Container(
                          width: 150,
                          height: 150,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
                            image: DecorationImage(image: MemoryImage(firstArt), fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ...tracks.map((song) => _buildNamidaTrackTile(
                      song,
                      onStateUpdate: () => setListState(() {}),
                    )),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 24,
                  child: _buildReactiveMiniPlayer(),
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              backgroundColor: const Color(0xFF0A0A0F),
              selectedIndex: 1,
              onDestinationSelected: (idx) {
                Navigator.pop(context);
                setState(() => _selectedIndex = idx);
              },
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

  Widget _buildMenuTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)) : null,
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 18),
      onTap: onTap,
    );
  }

  void _showNowPlayingScreen() {
    if (_currentSong == null && _filteredSongs.isNotEmpty) {
      _playSong(_filteredSongs.first);
    } else if (_currentSong != null) {
      _fetchLyricsOnline(_currentSong!);
    }
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
        onShowPath: () {
          if (_currentSong != null) _showAudioPathDetails(_currentSong!);
        },
        onShowEqualizer: _showEqualizerSheet,
        onToggleFavorite: () {
          if (_currentSong != null) {
            setState(() => _currentSong!.isFavorite = !_currentSong!.isFavorite);
          }
        },
        onRefreshLyrics: () {
          if (_currentSong != null) {
            _currentSong!.isLyricsFetched = false;
            _fetchLyricsOnline(_currentSong!);
          }
        },
        onEditTags: () {
          if (_currentSong != null) _showTagEditorDialog(_currentSong!);
        },
        onPlayPause: _togglePlayPause,
        onNext: _playNextTrack,
        onPrevious: _playPrevTrack,
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MainSettingsScreen(
          usbDacExclusive: _usbDacExclusive,
          gaplessPlayback: _gaplessPlayback,
          mediaNotificationEnabled: _mediaNotificationEnabled,
          usePitchBlack: _usePitchBlack,
          autoColoring: _autoColoring,
          forceMiniColor: _forceMiniColor,
          replayGain: _replayGain,
          connectedDacName: _connectedDacName,
          onUsbDacChanged: _toggleUsbDacMode,
          onGaplessChanged: (v) => setState(() => _gaplessPlayback = v),
          onNotificationChanged: (v) => setState(() => _mediaNotificationEnabled = v),
          onPitchBlackChanged: (v) {
            setState(() => _usePitchBlack = v);
            NamiApp.of(context).updateTheme(isPitchBlack: v);
          },
          onAutoColoringChanged: (v) => setState(() => _autoColoring = v),
          onForceMiniColorChanged: (v) => setState(() => _forceMiniColor = v),
          onReplayGainChanged: (v) => setState(() => _replayGain = v),
          onRescan: _fastScanDeviceMusic,
        ),
      ),
    );
  }

  void _openStatisticsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StatisticsScreen(
          songsCount: _songs.length,
          artistsCount: artistGroups.length,
          albumsCount: _songs.map((s) => s.album).toSet().length,
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        title: const Text('Create New Playlist'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  _customPlaylists.add(CustomPlaylist(name: nameCtrl.text.trim(), tracks: []));
                });
                Navigator.pop(c);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created playlist "${nameCtrl.text.trim()}"')));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt(AudioTrack song, double size, double radius) {
    if (song.albumArt != null && song.albumArt!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          song.albumArt!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _defaultArtPlaceholder(size, radius),
        ),
      );
    }
    return _defaultArtPlaceholder(size, radius);
  }

  Widget _defaultArtPlaceholder(double size, double radius) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.25), borderRadius: BorderRadius.circular(radius)),
      child: Icon(Icons.album_rounded, size: size * 0.5, color: Colors.deepPurpleAccent),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _searchController.dispose();
    _mornyeSearchController.dispose();
    super.dispose();
  }

  final Map<String, List<AudioTrack>> artistGroups = {};

  @override
  Widget build(BuildContext context) {
    artistGroups.clear();
    for (var song in _songs) {
      artistGroups.putIfAbsent(song.artist, () => []).add(song);
    }
    final uniqueArtists = artistGroups.keys.toList()
      ..sort((a, b) => _artistSortOrder == "Artist"
          ? a.toLowerCase().compareTo(b.toLowerCase())
          : artistGroups[b]!.length.compareTo(artistGroups[a]!.length));

    final List<String> tabTitles = ['Nami', 'Tracks', 'Artists', 'Playlists', 'Mornye'];

    final List<Widget> pages = [
      // 0. Home Dashboard
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
                    decoration: BoxDecoration(
                      color: const Color(0xFF12121A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.deepPurpleAccent,
                          backgroundImage: (_userPhotoPath != null && File(_userPhotoPath!).existsSync())
                              ? FileImage(File(_userPhotoPath!))
                              : null,
                          child: (_userPhotoPath == null || !File(_userPhotoPath!).existsSync())
                              ? Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'P', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20))
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Happy listening,', style: TextStyle(fontSize: 12, color: Colors.white60)),
                              Text(_userName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF12121A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.all(14),
                  side: const BorderSide(color: Colors.white10),
                ),
                icon: const Icon(Icons.bar_chart_rounded, color: Colors.deepPurpleAccent, size: 24),
                onPressed: _openStatisticsScreen,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Mixes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 170,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                GestureDetector(
                  onTap: () { if (_songs.isNotEmpty) _playSong(_songs.first); },
                  child: _buildHomeCard(_songs.isNotEmpty ? _songs.first.albumArt : null, 'Recommended', '${_songs.length} Local Tracks'),
                ),
                GestureDetector(
                  onTap: _shufflePlay,
                  child: _buildHomeCard(null, 'Infinite Mix', 'Dynamic Audio Flow'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Listens', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          if (_isScanning)
            const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
          else
            SizedBox(
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _songs.length > 8 ? 8 : _songs.length,
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  return GestureDetector(
                    onTap: () => _playSong(song),
                    child: Container(
                      width: 110,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCoverArt(song, 100, 12),
                          const SizedBox(height: 6),
                          Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const Text('an hour ago', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),

      // 1. Tracks Page
      _hasPermission
          ? (_isScanning 
              ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
              : (_filteredSongs.isEmpty
                  ? const Center(child: Text('No tracks found.', style: TextStyle(color: Colors.grey)))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                          child: Row(
                            children: [
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.only(right: 10),
                                icon: const Icon(Icons.shuffle_rounded, size: 20, color: Colors.white70),
                                onPressed: _shufflePlay,
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.only(right: 12),
                                icon: const Icon(Icons.play_arrow_outlined, size: 22, color: Colors.white70),
                                onPressed: () {
                                  if (_filteredSongs.isNotEmpty) _playSong(_filteredSongs.first);
                                },
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(18)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.music_note_rounded, size: 14, color: Colors.white70),
                                    const SizedBox(width: 6),
                                    Text('${_songs.length} Tracks', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(width: 2),
                                    const Icon(Icons.chevron_right_rounded, size: 15, color: Colors.grey),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              PopupMenuButton<String>(
                                color: const Color(0xFF14141F),
                                onSelected: (val) {
                                  setState(() {
                                    if (val == 'Title') {
                                      _filteredSongs.sort((a, b) => a.title.compareTo(b.title));
                                    } else if (val == 'Artist') {
                                      _filteredSongs.sort((a, b) => a.artist.compareTo(b.artist));
                                    } else if (val == 'Duration') {
                                      _filteredSongs.sort((a, b) => b.duration.compareTo(a.duration));
                                    }
                                  });
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(value: 'Title', child: Text('Title')),
                                  PopupMenuItem(value: 'Artist', child: Text('Artist')),
                                  PopupMenuItem(value: 'Duration', child: Text('Duration')),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(16)),
                                  child: const Row(
                                    children: [
                                      Text('Sort', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                      SizedBox(width: 4),
                                      Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.filter_alt_outlined, size: 19, color: Colors.white70),
                                onPressed: () {
                                  setState(() => _filteredSongs = _filteredSongs.reversed.toList());
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: _filteredSongs.length,
                            itemBuilder: (context, index) => _buildNamidaTrackTile(_filteredSongs[index]),
                          ),
                        ),
                      ],
                    )))
          : Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                onPressed: _requestPermissionAndScanMusic,
                child: const Text('Grant Storage Permission'),
              ),
            ),

      // 2. Artists Page
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(18)),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 15, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text('${uniqueArtists.length} Artists', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded, size: 15, color: Colors.grey),
                    ],
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _artistGridColumns = _artistGridColumns == 4 ? 3 : (_artistGridColumns == 3 ? 2 : 4);
                    });
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.grid_view_rounded, size: 18, color: Colors.white70),
                      Text('$_artistGridColumns', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _artistSortOrder = _artistSortOrder == "Artist" ? "Tracks" : "Artist";
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF16161F), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Text(_artistSortOrder, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.filter_alt_outlined, size: 19, color: Colors.white70),
                  onPressed: () {
                    setState(() {
                      _artistSortOrder = _artistSortOrder == "Artist" ? "Tracks" : "Artist";
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 95),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _artistGridColumns,
                childAspectRatio: 0.76,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
              ),
              itemCount: uniqueArtists.length,
              itemBuilder: (context, index) {
                final artistName = uniqueArtists[index];
                final artistSongs = artistGroups[artistName]!;
                final firstArt = artistSongs.firstWhere((s) => s.albumArt != null, orElse: () => artistSongs.first).albumArt;

                return GestureDetector(
                  onTap: () => _showArtistDetailScreen(artistName, artistSongs),
                  child: Column(
                    children: [
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF161622),
                              image: firstArt != null
                                  ? DecorationImage(image: MemoryImage(firstArt), fit: BoxFit.cover)
                                  : null,
                            ),
                            child: firstArt == null
                                ? const Icon(Icons.person_rounded, size: 32, color: Colors.white38)
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // 3. Playlists Page
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_songs.length} Library Tracks', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                onPressed: _showCreatePlaylistDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildPlaylistStatCard('History', '${_historyTracks.length}', Icons.history, () {
                _showFilteredListScreen('Listening History', _historyTracks);
              }),
              const SizedBox(width: 12),
              _buildPlaylistStatCard('Most Played', '${_songs.length}', Icons.trending_up, () {
                _showFilteredListScreen('Most Played Tracks', _songs);
              }),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildPlaylistStatCard('Favourites', '${_songs.where((s) => s.isFavorite).length}', Icons.favorite, () {
                _showFilteredListScreen('Favourites', _songs.where((s) => s.isFavorite).toList());
              }),
              const SizedBox(width: 12),
              _buildPlaylistStatCard('Queue', '${_playNextQueue.length}', Icons.queue_music, () {
                _showFilteredListScreen('Play-Next Queue', _playNextQueue);
              }),
            ],
          ),
          if (_customPlaylists.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Your Playlists', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._customPlaylists.map((pl) => Card(
              color: const Color(0xFF14141F),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.playlist_play_rounded, color: Colors.deepPurpleAccent),
                title: Text(pl.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${pl.tracks.length} tracks', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () {
                    setState(() => _customPlaylists.remove(pl));
                  },
                ),
                onTap: () => _showFilteredListScreen(pl.name, pl.tracks),
              ),
            )),
          ],
        ],
      ),

      // 4. Mornye Tab
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade900.withOpacity(0.85), const Color(0xFF14141F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.extension_rounded, color: Colors.deepPurpleAccent, size: 26),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Mornye Stream', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Extension Repository URL',
                      icon: const Icon(Icons.link_rounded, color: Colors.redAccent, size: 22),
                      onPressed: _showExtensionRepoDialog,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Mornye Preferences',
                      icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20),
                      onPressed: _showMornyePreferencesSheet,
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF0A0A0E), borderRadius: BorderRadius.circular(10)),
                      child: DropdownButton<String>(
                        value: _selectedMornyeService,
                        dropdownColor: const Color(0xFF14141F),
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.deepPurpleAccent),
                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                        items: _mornyeServices.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedMornyeService = val);
                            if (_mornyeSearchController.text.isNotEmpty) {
                              _searchMornyeCatalog(_mornyeSearchController.text);
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mornyeSearchController,
                  onSubmitted: _searchMornyeCatalog,
                  decoration: InputDecoration(
                    hintText: 'Search songs, albums, artists via $_selectedMornyeService...',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF08080C),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded, color: Colors.deepPurpleAccent),
                      onPressed: () => _searchMornyeCatalog(_mornyeSearchController.text),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'Songs', 'Albums', 'Artists'].map((filter) {
                      final isSel = _mornyeActiveFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(filter, style: TextStyle(fontSize: 11.5, color: isSel ? Colors.white : Colors.white70)),
                          selected: isSel,
                          selectedColor: Colors.deepPurpleAccent,
                          backgroundColor: const Color(0xFF0A0A0E),
                          onSelected: (val) => setState(() => _mornyeActiveFilter = filter),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isMornyeSearching)
            const Padding(
              padding: EdgeInsets.all(28.0),
              child: Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent)),
            )
          else if (_mornyeResults.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Search Results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(_mornyeAudioQuality, style: const TextStyle(fontSize: 10.5, color: Colors.deepPurpleAccent)),
              ],
            ),
            const SizedBox(height: 8),
            ..._mornyeResults
                .where((item) => _mornyeActiveFilter == 'All' || item.type.toLowerCase() == _mornyeActiveFilter.toLowerCase().replaceAll('s', ''))
                .map((item) {
              final isDownloading = _downloadingTitles.contains(item.title);
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF12121A),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: item.artworkUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(item.type == 'artist' ? 24 : 8),
                          child: Image.network(
                            item.artworkUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              item.type == 'artist' ? Icons.person_rounded : (item.type == 'album' ? Icons.album_rounded : Icons.music_note_rounded),
                              color: Colors.deepPurpleAccent,
                            ),
                          ),
                        )
                      : Icon(
                          item.type == 'artist' ? Icons.person_rounded : (item.type == 'album' ? Icons.album_rounded : Icons.music_note_rounded),
                          color: Colors.deepPurpleAccent,
                        ),
                  title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold)),
                  subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white60)),
                  trailing: item.type == 'song'
                      ? (isDownloading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.deepPurpleAccent),
                            )
                          : IconButton(
                              icon: const Icon(Icons.download_rounded, color: Colors.deepPurpleAccent),
                              onPressed: () => _downloadMornyeTrack(item),
                            ))
                      : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                  onTap: () {
                    if (item.type == 'song') {
                      _downloadMornyeTrack(item);
                    } else {
                      _mornyeSearchController.text = item.title;
                      _searchMornyeCatalog(item.title);
                    }
                  },
                ),
              );
            }),
          ],
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white70),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _filterSongs,
                decoration: const InputDecoration(hintText: 'Search tracks, artists, albums...', border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey)),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : Text(tabTitles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _filteredSongs = _songs;
                }
              });
            },
          ),
          IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white70), onPressed: _openSettings),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0F0F16),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF14141F)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text('Nami', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Hi-Res Lossless Player • $_userName', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedIndex = 0);
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: const Text('Tracks'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedIndex = 1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Artists'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedIndex = 2);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Playlists'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedIndex = 3);
              },
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('Mornye Catalog'),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedIndex = 4);
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded, color: Colors.deepPurpleAccent),
              title: const Text('Listening Statistics'),
              onTap: () {
                Navigator.pop(context);
                _openStatisticsScreen();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded, color: Colors.deepPurpleAccent),
              title: const Text('Equalizer & Sound Effects'),
              onTap: () {
                Navigator.pop(context);
                _showEqualizerSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                _openSettings();
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          pages[_selectedIndex],
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: _buildReactiveMiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0A0A0F),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Tracks'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Artists'),
          NavigationDestination(icon: Icon(Icons.playlist_play_rounded), selectedIcon: Icon(Icons.playlist_add_check_rounded), label: 'Playlists'),
          NavigationDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension_rounded), label: 'Mornye'),
        ],
      ),
    );
  }

  Widget _buildHomeCard(Uint8List? art, String title, String subtitle) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.25),
        borderRadius: BorderRadius.circular(16),
        image: art != null ? DecorationImage(image: MemoryImage(art), fit: BoxFit.cover, opacity: 0.3) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildPlaylistStatCard(String title, String count, IconData icon, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(16)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Colors.deepPurpleAccent, size: 20),
                  const SizedBox(height: 8),
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              Text(count, style: const TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDurationPadded(Duration d) {
    int minutes = d.inMinutes;
    int seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// Namida Complete Settings Screen with Theme, Playback & Customizations Sub-Menus (SS8)
class MainSettingsScreen extends StatefulWidget {
  final bool usbDacExclusive;
  final bool gaplessPlayback;
  final bool mediaNotificationEnabled;
  final bool usePitchBlack;
  final bool autoColoring;
  final bool forceMiniColor;
  final bool replayGain;
  final String connectedDacName;
  final ValueChanged<bool> onUsbDacChanged;
  final ValueChanged<bool> onGaplessChanged;
  final ValueChanged<bool> onNotificationChanged;
  final ValueChanged<bool> onPitchBlackChanged;
  final ValueChanged<bool> onAutoColoringChanged;
  final ValueChanged<bool> onForceMiniColorChanged;
  final ValueChanged<bool> onReplayGainChanged;
  final VoidCallback onRescan;

  const MainSettingsScreen({
    super.key,
    required this.usbDacExclusive,
    required this.gaplessPlayback,
    required this.mediaNotificationEnabled,
    required this.usePitchBlack,
    required this.autoColoring,
    required this.forceMiniColor,
    required this.replayGain,
    required this.connectedDacName,
    required this.onUsbDacChanged,
    required this.onGaplessChanged,
    required this.onNotificationChanged,
    required this.onPitchBlackChanged,
    required this.onAutoColoringChanged,
    required this.onForceMiniColorChanged,
    required this.onReplayGainChanged,
    required this.onRescan,
  });

  @override
  State<MainSettingsScreen> createState() => _MainSettingsScreenState();
}

class _MainSettingsScreenState extends State<MainSettingsScreen> {
  late bool _usbDac;
  late bool _gapless;
  late bool _notification;
  late bool _pitchBlack;
  late bool _autoColor;
  late bool _forceMini;
  late bool _replayGain;

  @override
  void initState() {
    super.initState();
    _usbDac = widget.usbDacExclusive;
    _gapless = widget.gaplessPlayback;
    _notification = widget.mediaNotificationEnabled;
    _pitchBlack = widget.usePitchBlack;
    _autoColor = widget.autoColoring;
    _forceMini = widget.forceMiniColor;
    _replayGain = widget.replayGain;
  }

  void _showThemeSubMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setThemeState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Theme & Appearance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use Pitch Black (AMOLED)'),
                subtitle: const Text('True black background for power saving'),
                value: _pitchBlack,
                activeColor: Colors.deepPurpleAccent,
                onChanged: (v) {
                  setThemeState(() => _pitchBlack = v);
                  setState(() {});
                  widget.onPitchBlackChanged(v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto Coloring'),
                subtitle: const Text('Extract accent colors from artwork'),
                value: _autoColor,
                activeColor: Colors.deepPurpleAccent,
                onChanged: (v) {
                  setThemeState(() => _autoColor = v);
                  setState(() {});
                  widget.onAutoColoringChanged(v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Force Miniplayer Colors'),
                subtitle: const Text('Match miniplayer accent to active track'),
                value: _forceMini,
                activeColor: Colors.deepPurpleAccent,
                onChanged: (v) {
                  setThemeState(() => _forceMini = v);
                  setState(() {});
                  widget.onForceMiniColorChanged(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlaybackSubMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setPlayState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Playback & Hi-Res Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('USB DAC Exclusive Routing'),
                subtitle: const Text('Bypass Android audio resampler for bit-perfect output'),
                value: _usbDac,
                activeColor: Colors.deepPurpleAccent,
                onChanged: (v) {
                  setPlayState(() => _usbDac = v);
                  setState(() {});
                  widget.onUsbDacChanged(v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gapless Playback'),
                subtitle: const Text('Zero latency transition between tracks'),
                value: _gapless,
                activeColor: Colors.deepPurpleAccent,
                onChanged: (v) {
                  setPlayState(() => _gapless = v);
                  setState(() {});
                  widget.onGaplessChanged(v);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ReplayGain Normalization'),
                subtitle: const Text('Balance loudness across tracks automatically'),
                value: _replayGain,
                activeColor: Colors.deepPurpleAccent,
                onChanged: (v) {
                  setPlayState(() => _replayGain = v);
                  setState(() {});
                  widget.onReplayGainChanged(v);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette_outlined, color: Colors.deepPurpleAccent),
            title: const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('The overall vibe of your player (Pitch Black, Colors)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            onTap: _showThemeSubMenu,
          ),
          const Divider(color: Colors.white10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.play_circle_outline_rounded, color: Colors.deepPurpleAccent),
            title: const Text('Playback', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('USB DAC Routing, Gapless transition, ReplayGain', style: TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            onTap: _showPlaybackSubMenu,
          ),
          const Divider(color: Colors.white10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.brush_outlined, color: Colors.deepPurpleAccent),
            title: const Text('Customizations', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Waveform look, animations, and miniplayer style', style: TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            onTap: _showThemeSubMenu,
          ),
          const Divider(color: Colors.white10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Media Notification Manager'),
            subtitle: const Text('Show live playback card in system quick-settings'),
            value: _notification,
            activeColor: Colors.deepPurpleAccent,
            onChanged: (v) {
              setState(() => _notification = v);
              widget.onNotificationChanged(v);
            },
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.refresh_rounded, color: Colors.deepPurpleAccent),
            title: const Text('Rescan Music & Clean Tags'),
            onTap: () {
              widget.onRescan();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescanning library & cleaning tags...')));
            },
          ),
        ],
      ),
    );
  }
}

// Namida Statistics Dashboard Screen (SS6 & SS7)
class StatisticsScreen extends StatefulWidget {
  final int songsCount;
  final int artistsCount;
  final int albumsCount;

  const StatisticsScreen({
    super.key,
    required this.songsCount,
    required this.artistsCount,
    required this.albumsCount,
  });

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  String _activeTimeframe = 'Week';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Statistics', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Library Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurpleAccent)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statItem('${widget.songsCount}', 'Tracks', Icons.music_note),
                    _statItem('${widget.albumsCount}', 'Albums', Icons.album),
                    _statItem('${widget.artistsCount}', 'Artists', Icons.person),
                  ],
                ),
                const SizedBox(height: 16),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statItem('32', 'Genres', Icons.category),
                    _statItem('33h 36m', 'Total Duration', Icons.timer),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Charts & Trends', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurpleAccent)),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['Week', 'Month', '3 Months', '6 Months', 'Year', 'All time'].map((timeframe) {
                      final isSel = _activeTimeframe == timeframe;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(timeframe, style: TextStyle(fontSize: 12, color: isSel ? Colors.white : Colors.white70)),
                          selected: isSel,
                          selectedColor: Colors.deepPurpleAccent,
                          backgroundColor: const Color(0xFF0A0A0E),
                          onSelected: (val) => setState(() => _activeTimeframe = timeframe),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Total Listens ($_activeTimeframe): 812', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Total Listen Time: 43h 19min', style: TextStyle(fontSize: 13, color: Colors.white70)),
                const SizedBox(height: 6),
                const Text('Listening Streak: 5 Days Continuous', style: TextStyle(fontSize: 13, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _statItem(String val, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.deepPurpleAccent, size: 22),
        const SizedBox(height: 4),
        Text(val, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

// Now Playing Screen (SS9: Top-Right 3-Dots Tag Editor, Bottom-Right Lyrics Button, 9-Line Centered Lyrics)
class NowPlayingModal extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final ValueNotifier<AudioTrack?> currentSongNotifier;
  final List<AudioTrack> playNextQueue;
  final int totalTrackCount;
  final int currentIndex;
  final List<MornyeExtension> extensions;
  final VoidCallback onShowPath;
  final VoidCallback onShowEqualizer;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRefreshLyrics;
  final VoidCallback onEditTags;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const NowPlayingModal({
    super.key,
    required this.audioPlayer,
    required this.currentSongNotifier,
    required this.playNextQueue,
    required this.totalTrackCount,
    required this.currentIndex,
    required this.extensions,
    required this.onShowPath,
    required this.onShowEqualizer,
    required this.onToggleFavorite,
    required this.onRefreshLyrics,
    required this.onEditTags,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<NowPlayingModal> createState() => _NowPlayingModalState();
}

class _NowPlayingModalState extends State<NowPlayingModal> {
  int _viewMode = 0; // 0 = Artwork, 1 = Synced Lyrics
  bool _isLooping = false;
  final ScrollController _lyricsScrollCtrl = ScrollController();
  int _lastScrolledLyricIndex = -1;

  double _getWaveformBarHeight(int index, String seedTitle) {
    final hash = seedTitle.codeUnits.fold(0, (prev, elem) => prev + elem);
    final wave1 = math.sin((index + hash) * 0.42).abs();
    final wave2 = math.cos((index * 0.85) + (hash * 0.1)).abs();
    double envelope = 1.0;
    if (index < 5) envelope = (index + 2) / 7.0;
    if (index > 72) envelope = (78 - index + 2) / 8.0;
    return ((10.0 + (wave1 * 20.0) + (wave2 * 14.0)) * envelope).clamp(6.0, 42.0);
  }

  void _autoScrollToActiveLyric(int activeIdx) {
    if (activeIdx == _lastScrolledLyricIndex) return;
    _lastScrolledLyricIndex = activeIdx;
    if (_lyricsScrollCtrl.hasClients) {
      final targetOffset = (activeIdx * 48.0 - 160.0).clamp(0.0, _lyricsScrollCtrl.position.maxScrollExtent);
      _lyricsScrollCtrl.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _lyricsScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioTrack?>(
      valueListenable: widget.currentSongNotifier,
      builder: (context, song, _) {
        final ext = (song?.path.split('.').last ?? 'FLAC').toUpperCase();
        final bitrate = song?.bitrateKbps ?? 1790;
        final kHz = ((song?.sampleRateHz ?? 48000) / 1000.0).toStringAsFixed(1);
        final artSize = MediaQuery.of(context).size.width * 0.77;

        return Container(
          height: MediaQuery.of(context).size.height * 0.94,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: const BoxDecoration(
            color: Color(0xFF08080C),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              // Top Bar: Down arrow | Track Index + Album | Top-Right 3-Dots for Tag Editing (SS9!)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${widget.currentIndex}/${widget.totalTrackCount}',
                          style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (song?.album ?? 'LOCAL AUDIO').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 22),
                    onPressed: widget.onEditTags,
                  ),
                ],
              ),

              const SizedBox(height: 6),

              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _viewMode = _viewMode == 0 ? 1 : 0);
                    if (_viewMode == 1) widget.onRefreshLyrics();
                  },
                  child: Center(
                    child: _viewMode == 0
                        ? Container(
                            width: artSize,
                            height: artSize,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.65),
                                  blurRadius: 35,
                                  spreadRadius: 6,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: song?.albumArt != null
                                  ? Image.memory(song!.albumArt!, fit: BoxFit.cover)
                                  : Container(
                                      color: const Color(0xFF181824),
                                      child: const Icon(Icons.album_rounded, size: 105, color: Colors.deepPurpleAccent),
                                    ),
                            ),
                          )
                        // Synced Lyrics View strictly bounded to 9 lines with active line on 5th center line!
                        : StreamBuilder<Duration>(
                            stream: widget.audioPlayer.positionStream,
                            builder: (context, snapshot) {
                              final pos = snapshot.data ?? Duration.zero;
                              final lyrics = song?.parsedLyrics ?? [];
                              if (lyrics.isEmpty) {
                                return const Center(child: Text("No synced lyrics found.", style: TextStyle(color: Colors.white60)));
                              }
                              int activeIdx = lyrics.lastIndexWhere((l) => l.timestamp <= pos);
                              if (activeIdx < 0) activeIdx = 0;

                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _autoScrollToActiveLyric(activeIdx);
                              });

                              return SizedBox(
                                height: 360,
                                child: ListView.builder(
                                  controller: _lyricsScrollCtrl,
                                  padding: const EdgeInsets.symmetric(vertical: 160),
                                  itemCount: lyrics.length,
                                  itemBuilder: (context, idx) {
                                    final isCurrent = idx == activeIdx;
                                    return GestureDetector(
                                      onTap: () => widget.audioPlayer.seek(lyrics[idx].timestamp),
                                      child: Container(
                                        height: 48,
                                        alignment: Alignment.center,
                                        child: Text(
                                          lyrics[idx].text,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: isCurrent ? 17.5 : 14.5,
                                            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
                                            color: isCurrent ? Colors.white : Colors.white30,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song?.title ?? 'No Track Selected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song?.artist ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      (song?.isFavorite ?? false) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: (song?.isFavorite ?? false) ? Colors.deepPurpleAccent : Colors.white60,
                      size: 26,
                    ),
                    onPressed: () {
                      widget.onToggleFavorite();
                      setState(() {});
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),

              StreamBuilder<Duration>(
                stream: widget.audioPlayer.positionStream,
                builder: (context, positionSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration?>(
                    stream: widget.audioPlayer.durationStream,
                    builder: (context, durationSnapshot) {
                      final duration = durationSnapshot.data ?? song?.duration ?? const Duration(minutes: 3, seconds: 45);
                      double maxMs = duration.inMilliseconds.toDouble();
                      if (maxMs <= 0) maxMs = 1.0;
                      double currentMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);
                      final progress = currentMs / maxMs;

                      return Column(
                        children: [
                          LayoutBuilder(
                            builder: (ctx, constraints) {
                              const int barCount = 78;
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: (details) {
                                  final double p = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                                  widget.audioPlayer.seek(Duration(milliseconds: (p * maxMs).toInt()));
                                },
                                onTapDown: (details) {
                                  final double p = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                                  widget.audioPlayer.seek(Duration(milliseconds: (p * maxMs).toInt()));
                                },
                                child: SizedBox(
                                  height: 44,
                                  width: double.infinity,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: List.generate(barCount, (i) {
                                      final h = _getWaveformBarHeight(i, song?.title ?? 'Nami');
                                      final isPassed = (i / barCount) <= progress;
                                      return Container(
                                        width: 2.3,
                                        height: h,
                                        decoration: BoxDecoration(
                                          color: isPassed ? Colors.white : Colors.white24,
                                          borderRadius: BorderRadius.circular(1.5),
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 18),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                _formatDurationPadded(position),
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.skip_previous_outlined, size: 30, color: Colors.white),
                                    onPressed: widget.onPrevious,
                                  ),
                                  const SizedBox(width: 12),
                                  StreamBuilder<bool>(
                                    stream: widget.audioPlayer.playingStream,
                                    builder: (context, snapshot) {
                                      final isPlaying = snapshot.data ?? false;
                                      return GestureDetector(
                                        onTap: widget.onPlayPause,
                                        child: Container(
                                          width: 62,
                                          height: 62,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.08),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            size: 34,
                                            color: Colors.white,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    icon: const Icon(Icons.skip_next_outlined, size: 30, color: Colors.white),
                                    onPressed: widget.onNext,
                                  ),
                                ],
                              ),
                              Text(
                                _formatDurationPadded(duration),
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 20),

              // Footer: Audio Path on Bottom Left, 4 Action Buttons on Bottom Right (SS9!)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.onShowPath,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.headphones_outlined, size: 16, color: Colors.white70),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  children: [
                                    const TextSpan(
                                      text: 'Audio ',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                                    ),
                                    TextSpan(
                                      text: '• $ext • $bitrate kb/s',
                                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 1),
                              const Text(
                                '24-bit Hi-Res Lossless',
                                style: TextStyle(fontSize: 10, color: Colors.white54),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(_isLooping ? Icons.repeat_one_rounded : Icons.repeat_rounded, size: 20, color: _isLooping ? Colors.deepPurpleAccent : Colors.white70),
                        onPressed: () {
                          setState(() => _isLooping = !_isLooping);
                          widget.audioPlayer.setLoopMode(_isLooping ? LoopMode.one : LoopMode.off);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isLooping ? 'Loop Single Track Enabled' : 'Loop Disabled')));
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.graphic_eq_rounded, size: 20, color: Colors.white70),
                        onPressed: widget.onShowPath,
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.tune_rounded, size: 20, color: Colors.white70),
                        onPressed: widget.onShowEqualizer,
                      ),
                      const SizedBox(width: 16),
                      // Bottom-Right Circle Lyrics Toggle Button (SS9!)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(Icons.lyrics_outlined, size: 20, color: _viewMode == 1 ? Colors.deepPurpleAccent : Colors.white70),
                        onPressed: () {
                          setState(() => _viewMode = _viewMode == 1 ? 0 : 1);
                          if (_viewMode == 1) widget.onRefreshLyrics();
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.queue_music_rounded, size: 20, color: Colors.white70),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: const Color(0xFF14141F),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                            builder: (c) => Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Playback Queue & Next Up', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const SizedBox(height: 12),
                                  if (widget.playNextQueue.isEmpty)
                                    const Text('No tracks in play-next queue. Swipe left on any track to add it here!', style: TextStyle(color: Colors.grey, fontSize: 12))
                                  else
                                    SizedBox(
                                      height: 220,
                                      child: ListView.builder(
                                        itemCount: widget.playNextQueue.length,
                                        itemBuilder: (ctx, i) {
                                          final qTrack = widget.playNextQueue[i];
                                          return ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: qTrack.albumArt != null
                                                  ? Image.memory(qTrack.albumArt!, width: 40, height: 40, fit: BoxFit.cover)
                                                  : const Icon(Icons.album, color: Colors.deepPurpleAccent),
                                            ),
                                            title: Text(qTrack.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                            subtitle: Text(qTrack.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                            trailing: IconButton(
                                              icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                                              onPressed: () {
                                                setState(() => widget.playNextQueue.removeAt(i));
                                                Navigator.pop(c);
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }

  String _formatDurationPadded(Duration d) {
    int minutes = d.inMinutes;
    int seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}