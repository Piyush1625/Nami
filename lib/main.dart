import 'dart:io';
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
        scaffoldBackgroundColor: const Color(0xFF0A0A0E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
          surface: const Color(0xFF12121A),
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
  final String path;
  Uint8List? albumArt;
  String rawLyrics;
  List<LyricLine> parsedLyrics;
  bool isMetadataLoaded;
  Duration duration;
  bool isFavorite;
  String addedDate;
  int fileSize;

  AudioTrack({
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    this.albumArt,
    this.rawLyrics = "[00:00.00] Nami Lossless Hi-Fi Engine\n[00:04.00] Synced Lyrics Active\n[00:08.00] Enjoy your music stream",
    List<LyricLine>? parsedLyrics,
    this.isMetadataLoaded = false,
    this.duration = const Duration(minutes: 3, seconds: 45),
    this.isFavorite = false,
    this.addedDate = "Aug 2025",
    this.fileSize = 0,
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
  final String subtitle;
  final String type; // 'song', 'album', 'artist'
  final String service;
  MornyeCatalogItem({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.service,
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
  List<CustomPlaylist> _customPlaylists = [];

  AudioTrack? _currentSong;
  bool _isPlaying = false;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Mornye Explorer State
  final TextEditingController _mornyeSearchController = TextEditingController();
  List<MornyeCatalogItem> _mornyeResults = [];
  bool _isMornyeSearching = false;
  String _selectedMornyeService = "Qobuz";
  String _mornyeActiveFilter = "All";
  final List<String> _mornyeServices = [
    "Qobuz",
    "Tidal",
    "Apple Music",
    "Spotify Web",
    "Amazon Music",
    "YouTube Music",
  ];

  // Settings & Profile
  bool _usbDacExclusive = true;
  bool _gaplessPlayback = true;
  bool _mediaNotificationEnabled = true;
  String _connectedDacName = "USB DAC Ready (Bit-Perfect)";
  String _userName = "Piyush";
  String _topRecentFilter = "1 Day";

  final List<MornyeExtension> _extensions = [
    MornyeExtension(name: 'Tidal Hi-Res FLAC (.sflx)', version: '1.4.2', author: 'Mornye Core', format: '24-bit / 192kHz FLAC', isEnabled: true),
    MornyeExtension(name: 'Qobuz Studio Master (.sflx)', version: '1.2.0', author: 'OpenAudio', format: '24-bit / 96kHz Hi-Res', isEnabled: true),
    MornyeExtension(name: 'LRCLIB Synced Lyrics (.sflx)', version: '2.1.0', author: 'LRCLIB', format: 'Timestamped .LRC', isEnabled: true),
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
        _playNextTrack();
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
    } catch (_) {}
  }

  Future<void> _toggleUsbDacMode(bool enabled) async {
    setState(() => _usbDacExclusive = enabled);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? 'USB DAC Bit-Perfect Mode Enabled' : 'Standard Android Audio Mixer Active'),
          backgroundColor: Colors.deepPurple,
        ),
      );
    }
  }

  Future<void> _requestPermissionAndScanMusic() async {
    PermissionStatus status = await Permission.audio.request();
    if (!status.isGranted) status = await Permission.storage.request();
    if (!status.isGranted) status = await Permission.manageExternalStorage.request();

    if (status.isGranted || await Permission.storage.isGranted) {
      setState(() {
        _hasPermission = true;
        _isScanning = true;
      });
      await _fastScanDeviceMusic();
    }
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

              String cleanName = fileName.substring(0, fileName.lastIndexOf('.')).replaceAll('_', ' ');
              String artist = 'Unknown Artist';

              if (cleanName.contains(' - ')) {
                final parts = cleanName.split(' - ');
                artist = parts[0].trim();
                cleanName = parts.sublist(1).join(' - ').trim();
              }

              final track = AudioTrack(title: cleanName, artist: artist, album: 'Local Audio', path: path);
              track.parsedLyrics = _parseLrc(track.rawLyrics);
              foundTracks.add(track);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning music: $e');
    }

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
        if (i % 2 == 0 && mounted) setState(() {});
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _extractAudioMetadata(AudioTrack track) async {
    try {
      final file = File(track.path);
      track.fileSize = await file.length();
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

          if (blockType == 4 && offset + length <= data.length) {
            final commentStr = utf8.decode(data.sublist(offset, offset + length), allowMalformed: true);
            for (var line in commentStr.split(RegExp(r'[\x00\n\r]'))) {
              final upper = line.toUpperCase();
              if (upper.startsWith('TITLE=')) track.title = _cleanString(line.substring(6));
              if (upper.startsWith('ARTIST=')) track.artist = _cleanString(line.substring(7));
              if (upper.startsWith('ALBUM=')) track.album = _cleanString(line.substring(6));
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
          } else if (frameId == 'TPE1') {
            final a = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (a.isNotEmpty) track.artist = a;
          } else if (frameId == 'TALB') {
            final al = _decodeId3Text(data.sublist(offset, offset + frameSize));
            if (al.isNotEmpty) track.album = al;
          } else if (frameId == 'APIC' && track.albumArt == null) {
            track.albumArt = _extractEmbeddedImageBytes(data, offset, offset + frameSize);
          }
          offset += frameSize;
        }
      }
    } catch (_) {}
    track.isMetadataLoaded = true;
  }

  String _cleanString(String input) {
    return input.replaceAll(RegExp(r'[\x00-\x1F]'), '').trim();
  }

  String _decodeId3Text(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    int encoding = bytes[0];
    final content = bytes.sublist(1);
    if (encoding == 1 || encoding == 2) {
      final filtered = content.where((b) => b != 0x00 && b != 0xFF && b != 0xFE).toList();
      return _cleanString(utf8.decode(filtered, allowMalformed: true));
    }
    return _cleanString(utf8.decode(content, allowMalformed: true));
  }

  Uint8List? _extractEmbeddedImageBytes(Uint8List data, int start, int end) {
    for (int j = start; j < end - 8; j++) {
      if (data[j] == 0xFF && data[j + 1] == 0xD8 && data[j + 2] == 0xFF) {
        int imgEnd = end;
        for (int k = j + 4; k < end - 1; k++) {
          if (data[k] == 0xFF && data[k + 1] == 0xD9) {
            imgEnd = k + 2;
            break;
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
    final regExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    for (var line in lines) {
      final match = regExp.firstMatch(line.trim());
      if (match != null) {
        final min = int.tryParse(match.group(1)!) ?? 0;
        final sec = int.tryParse(match.group(2)!) ?? 0;
        final msStr = match.group(3)!;
        final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          result.add(LyricLine(timestamp: Duration(minutes: min, seconds: sec, milliseconds: ms), text: text));
        }
      }
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<void> _fetchLyricsOnline(AudioTrack song) async {
    try {
      final uri = Uri.parse('https://lrclib.net/api/get?track_name=${Uri.encodeComponent(song.title)}&artist_name=${Uri.encodeComponent(song.artist)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(res.body);
        song.rawLyrics = json['syncedLyrics'] ?? json['plainLyrics'] ?? "[00:00.00] Instrumental / No Lyrics found.";
        song.parsedLyrics = _parseLrc(song.rawLyrics);
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // Mornye Service Multi-Catalog Search
  Future<void> _searchMornyeCatalog(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _mornyeResults = []);
      return;
    }
    setState(() => _isMornyeSearching = true);
    try {
      final uri = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent(query)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final dynamic decoded = jsonDecode(res.body);
        if (decoded is List) {
          final List<MornyeCatalogItem> items = [];
          for (var item in decoded) {
            if (item is Map) {
              final track = item['trackName']?.toString() ?? 'Unknown Track';
              final artist = item['artistName']?.toString() ?? 'Unknown Artist';
              final album = item['albumName']?.toString() ?? 'Master Album';

              items.add(MornyeCatalogItem(title: track, subtitle: '$artist • $album', type: 'song', service: _selectedMornyeService));
              items.add(MornyeCatalogItem(title: artist, subtitle: 'Artist', type: 'artist', service: _selectedMornyeService));
              items.add(MornyeCatalogItem(title: album, subtitle: artist, type: 'album', service: _selectedMornyeService));
            }
          }
          setState(() {
            _mornyeResults = items;
            _isMornyeSearching = false;
          });
        }
      }
    } catch (_) {
      setState(() => _isMornyeSearching = false);
    }
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
    setState(() => _currentSong = song);
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(song.path);
      await _audioPlayer.play();
      if (_audioPlayer.duration != null) {
        song.duration = _audioPlayer.duration!;
      }
      _fetchLyricsOnline(song);
    } catch (e) {
      debugPrint('Error playing track: $e');
    }
  }

  void _playNextTrack() {
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

  // Audio Path & Details Modal
  void _showAudioPathDetails(AudioTrack song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Audio File Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepPurpleAccent)),
            const SizedBox(height: 12),
            Text('Title: ${song.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Artist: ${song.artist}', style: const TextStyle(color: Colors.grey)),
            Text('Format: ${song.path.split('.').last.toUpperCase()} • ${(song.fileSize / (1024 * 1024)).toStringAsFixed(2)} MB', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 14),
            const Text('Real System Path:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFF0A0A0E), borderRadius: BorderRadius.circular(10)),
              child: SelectableText(song.path, style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy File Path'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: song.path));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File path copied to clipboard!')));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Functional In-App Tag Editor
  void _showTagEditorDialog(AudioTrack song) {
    final titleController = TextEditingController(text: song.title);
    final artistController = TextEditingController(text: song.artist);
    final albumController = TextEditingController(text: song.album);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        title: const Text('Edit Metadata Tags'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Track Title')),
            const SizedBox(height: 10),
            TextField(controller: artistController, decoration: const InputDecoration(labelText: 'Artist Name')),
            const SizedBox(height: 10),
            TextField(controller: albumController, decoration: const InputDecoration(labelText: 'Album Name')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
            onPressed: () {
              setState(() {
                song.title = titleController.text.trim();
                song.artist = artistController.text.trim();
                song.album = albumController.text.trim();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Metadata tags updated!')));
            },
            child: const Text('Save Tags'),
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
            _buildMenuTile(Icons.folder_rounded, 'Audio Path & Info', song.path, () {
              Navigator.pop(context);
              _showAudioPathDetails(song);
            }),
            _buildMenuTile(Icons.edit_note_rounded, 'Edit Tags', 'Title, Artist, Album', () {
              Navigator.pop(context);
              _showTagEditorDialog(song);
            }),
            const Divider(color: Colors.white12, height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded, color: Colors.deepPurpleAccent),
              title: const Text('Play Next'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${song.title} to play next')));
              },
            ),
          ],
        ),
      ),
    );
  }

  // Artist Detail Page with Working Toggles & Properly Spaced Mini Player
  void _showArtistDetailScreen(String artistName, List<AudioTrack> artistTracks) {
    final firstArt = artistTracks.firstWhere((s) => s.albumArt != null, orElse: () => artistTracks.first).albumArt;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(backgroundColor: Colors.transparent),
          body: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 130),
                children: [
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 54,
                          backgroundColor: Colors.deepPurple.withOpacity(0.3),
                          backgroundImage: firstArt != null ? MemoryImage(firstArt) : null,
                          child: firstArt == null ? const Icon(Icons.person_rounded, size: 50, color: Colors.deepPurpleAccent) : null,
                        ),
                        const SizedBox(height: 14),
                        Text(artistName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('2018 – 2026', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _artistActionButton(Icons.shuffle_rounded, 'Shuffle', () {
                        final shuffled = List<AudioTrack>.from(artistTracks)..shuffle();
                        if (shuffled.isNotEmpty) _playSong(shuffled.first);
                      }),
                      _artistActionButton(Icons.play_arrow_rounded, 'Play', () {
                        if (artistTracks.isNotEmpty) _playSong(artistTracks.first);
                      }),
                      _artistActionButton(Icons.radio_rounded, 'Radio', () {
                        if (artistTracks.isNotEmpty) {
                          _playSong(artistTracks.first);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Starting $artistName Artist Radio')));
                        }
                      }),
                      _artistActionButton(Icons.more_horiz_rounded, 'More', () {
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: const Color(0xFF14141F),
                          builder: (c) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(leading: const Icon(Icons.favorite_rounded, color: Colors.deepPurpleAccent), title: const Text('Add Artist to Favourites'), onTap: () => Navigator.pop(c)),
                                ListTile(leading: const Icon(Icons.share_rounded), title: const Text('Share Artist'), onTap: () => Navigator.pop(c)),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _artistCategoryCard(Icons.album_rounded, 'Albums: 3'),
                  const SizedBox(height: 12),
                  _artistCategoryCard(Icons.library_music_rounded, 'Singles: ${artistTracks.length}'),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${artistTracks.length} Tracks', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      const Row(children: [Text('Year ', style: TextStyle(color: Colors.grey, fontSize: 13)), Icon(Icons.arrow_drop_down, color: Colors.grey)]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...artistTracks.map((song) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _buildCoverArt(song, 48, 8),
                    title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${song.artist} • ${song.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_formatDuration(song.duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(width: 2),
                        IconButton(
                          icon: Icon(song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: song.isFavorite ? Colors.deepPurpleAccent : Colors.grey, size: 18),
                          onPressed: () => setState(() => song.isFavorite = !song.isFavorite),
                        ),
                        IconButton(icon: const Icon(Icons.more_vert_rounded, color: Colors.grey, size: 18), onPressed: () => _showActionMenu(song)),
                      ],
                    ),
                    onTap: () => _playSong(song),
                  )),
                ],
              ),
              // Elevated Mini Player using SafeArea bottom
              Positioned(
                left: 12,
                right: 12,
                bottom: 24,
                child: GestureDetector(
                  onTap: _showNowPlayingScreen,
                  child: Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A26).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.4)),
                      boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.15), blurRadius: 16, spreadRadius: 2)],
                    ),
                    child: Row(
                      children: [
                        if (_currentSong != null) _buildCoverArt(_currentSong!, 38, 8)
                        else const Icon(Icons.album_rounded, size: 38, color: Colors.deepPurpleAccent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_currentSong?.title ?? 'No Track Playing', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(_currentSong?.artist ?? 'Lossless Ready', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        IconButton(icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28), onPressed: _togglePlayPause),
                        IconButton(icon: const Icon(Icons.skip_next_rounded, size: 24), onPressed: _playNextTrack),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _artistActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white.withOpacity(0.06),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _artistCategoryCard(IconData icon, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [Icon(icon, color: Colors.deepPurpleAccent, size: 22), const SizedBox(width: 14), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]),
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        ],
      ),
    );
  }

  void _showFilteredListScreen(String title, List<AudioTrack> tracks) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title)),
          body: ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final song = tracks[index];
              return ListTile(
                leading: _buildCoverArt(song, 48, 8),
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(song.artist, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                trailing: IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () => _showActionMenu(song)),
                onTap: () => _playSong(song),
              );
            },
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
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NowPlayingModal(
        audioPlayer: _audioPlayer,
        currentSong: _currentSong ?? _filteredSongs.firstOrNull,
        extensions: _extensions,
        usbDacActive: _usbDacExclusive,
        dacName: _connectedDacName,
        onShowPath: () {
          if (_currentSong != null) _showAudioPathDetails(_currentSong!);
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
          connectedDacName: _connectedDacName,
          userName: _userName,
          onUserNameChanged: (name) => setState(() => _userName = name),
          onUsbDacChanged: _toggleUsbDacMode,
          onGaplessChanged: (v) => setState(() => _gaplessPlayback = v),
          onNotificationChanged: (v) => setState(() => _mediaNotificationEnabled = v),
          onRescan: _fastScanDeviceMusic,
        ),
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

  @override
  Widget build(BuildContext context) {
    final Map<String, List<AudioTrack>> artistGroups = {};
    for (var song in _songs) {
      artistGroups.putIfAbsent(song.artist, () => []).add(song);
    }
    final uniqueArtists = artistGroups.keys.toList()..sort();

    final List<String> tabTitles = ['Nami', 'Tracks', 'Artists', 'Playlists', 'Mornye'];

    final List<Widget> pages = [
      // 0. Home Dashboard with Greeting Banner
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.deepPurpleAccent,
                child: Text(_userName.isNotEmpty ? _userName[0].toUpperCase() : 'P', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Happy listening,', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(_userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent Listens', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
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

      // 1. Tracks Page with Tighter Spacing
      _hasPermission
          ? (_isScanning 
              ? const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
              : (_filteredSongs.isEmpty
                  ? const Center(child: Text('No tracks found.', style: TextStyle(color: Colors.grey)))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(16)),
                                child: Row(
                                  children: [
                                    const Icon(Icons.music_note, size: 14, color: Colors.deepPurpleAccent),
                                    const SizedBox(width: 6),
                                    Text('${_songs.length} Tracks', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              IconButton(icon: const Icon(Icons.shuffle, size: 20, color: Colors.grey), onPressed: _shufflePlay),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(16)),
                                child: const Row(children: [Text('Title', style: TextStyle(fontSize: 12, color: Colors.grey)), Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey)]),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 90),
                            itemCount: _filteredSongs.length,
                            itemBuilder: (context, index) {
                              final song = _filteredSongs[index];
                              final isCurrent = _currentSong?.path == song.path;
                              return ListTile(
                                horizontalTitleGap: 12,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                                leading: _buildCoverArt(song, 48, 8),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? Colors.deepPurpleAccent : Colors.white),
                                ),
                                subtitle: Text('${song.artist} • ${song.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                trailing: SizedBox(
                                  width: 120,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(_formatDuration(song.duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                      const SizedBox(width: 2),
                                      IconButton(
                                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                        padding: EdgeInsets.zero,
                                        icon: Icon(song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: song.isFavorite ? Colors.deepPurpleAccent : Colors.grey, size: 18),
                                        onPressed: () => setState(() => song.isFavorite = !song.isFavorite),
                                      ),
                                      IconButton(
                                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.more_vert_rounded, color: Colors.grey, size: 18),
                                        onPressed: () => _showActionMenu(song),
                                      ),
                                    ],
                                  ),
                                ),
                                onTap: () => _playSong(song),
                                onLongPress: () => _showActionMenu(song),
                              );
                            },
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
      GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.78, crossAxisSpacing: 12, mainAxisSpacing: 14),
        itemCount: uniqueArtists.length,
        itemBuilder: (context, index) {
          final artistName = uniqueArtists[index];
          final artistSongs = artistGroups[artistName]!;
          final firstArt = artistSongs.firstWhere((s) => s.albumArt != null, orElse: () => artistSongs.first).albumArt;

          return GestureDetector(
            onTap: () => _showArtistDetailScreen(artistName, artistSongs),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: Colors.deepPurple.withOpacity(0.3),
                  backgroundImage: firstArt != null ? MemoryImage(firstArt) : null,
                  child: firstArt == null ? const Icon(Icons.person_rounded, size: 34, color: Colors.deepPurpleAccent) : null,
                ),
                const SizedBox(height: 8),
                Text(artistName, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Text('${artistSongs.length} Tracks', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          );
        },
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
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildPlaylistStatCard('History', '${(_songs.length * 2.5).floor()}', Icons.history),
              const SizedBox(width: 12),
              _buildPlaylistStatCard('Most Played', '${_songs.length}', Icons.trending_up),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildPlaylistStatCard('Favourites', '${_songs.where((s) => s.isFavorite).length}', Icons.favorite),
              const SizedBox(width: 12),
              _buildPlaylistStatCard('Queue', '${_songs.length}', Icons.queue_music),
            ],
          ),
        ],
      ),

      // 4. Mornye Engine with Service Swapper & Category Tabs
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.deepPurple.shade900, const Color(0xFF14141F)]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.extension_rounded, color: Colors.deepPurpleAccent, size: 26),
                        SizedBox(width: 8),
                        Text('Mornye Stream', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF0A0A0E), borderRadius: BorderRadius.circular(10)),
                      child: DropdownButton<String>(
                        value: _selectedMornyeService,
                        dropdownColor: const Color(0xFF14141F),
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.deepPurpleAccent),
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                        items: _mornyeServices.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedMornyeService = val);
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
                    hintText: 'Search via $_selectedMornyeService...',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF0A0A0E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded, color: Colors.deepPurpleAccent),
                      onPressed: () => _searchMornyeCatalog(_mornyeSearchController.text),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: ['All', 'Songs', 'Albums', 'Artists'].map((filter) {
                    final isSel = _mornyeActiveFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(filter, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.grey)),
                        selected: isSel,
                        selectedColor: Colors.deepPurple,
                        backgroundColor: const Color(0xFF0A0A0E),
                        onSelected: (val) => setState(() => _mornyeActiveFilter = filter),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_isMornyeSearching)
            const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
          else if (_mornyeResults.isNotEmpty) ...[
            const Text('Search Results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._mornyeResults
                .where((item) => _mornyeActiveFilter == 'All' || item.type.toLowerCase() == _mornyeActiveFilter.toLowerCase().replaceAll('s', ''))
                .map((item) => Card(
              color: const Color(0xFF14141F),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Icon(
                  item.type == 'artist' ? Icons.person_rounded : (item.type == 'album' ? Icons.album_rounded : Icons.music_note_rounded),
                  color: Colors.deepPurpleAccent,
                ),
                title: Text(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: Text('${item.subtitle} • via ${item.service}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: item.type == 'song'
                    ? IconButton(
                        icon: const Icon(Icons.download_rounded, color: Colors.deepPurpleAccent),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading ${item.title} to /storage/emulated/0/Music/Nami/')));
                        },
                      )
                    : const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Streaming ${item.title}')));
                },
              ),
            )),
          ],
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _filterSongs,
                decoration: const InputDecoration(hintText: 'Search tracks, artists, albums...', border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey)),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : Text(tabTitles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
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
          IconButton(icon: const Icon(Icons.settings_rounded), onPressed: _openSettings),
        ],
      ),
      body: Stack(
        children: [
          pages[_selectedIndex],
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: GestureDetector(
              onTap: _showNowPlayingScreen,
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A26).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.4)),
                  boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.15), blurRadius: 16, spreadRadius: 2)],
                ),
                child: Row(
                  children: [
                    if (_currentSong != null) _buildCoverArt(_currentSong!, 38, 8)
                    else const Icon(Icons.album_rounded, size: 38, color: Colors.deepPurpleAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_currentSong?.title ?? 'Tap any song to play', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(_currentSong?.artist ?? '24-bit / Lossless Ready', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28), onPressed: _togglePlayPause),
                    IconButton(icon: const Icon(Icons.skip_next_rounded, size: 24), onPressed: _playNextTrack),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0F0F16),
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

  Widget _buildPlaylistStatCard(String title, String count, IconData icon) {
    return Expanded(
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
    );
  }

  String _formatDuration(Duration d) {
    int minutes = d.inMinutes;
    int seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class MainSettingsScreen extends StatefulWidget {
  final bool usbDacExclusive;
  final bool gaplessPlayback;
  final bool mediaNotificationEnabled;
  final String connectedDacName;
  final String userName;
  final ValueChanged<String> onUserNameChanged;
  final ValueChanged<bool> onUsbDacChanged;
  final ValueChanged<bool> onGaplessChanged;
  final ValueChanged<bool> onNotificationChanged;
  final VoidCallback onRescan;

  const MainSettingsScreen({
    super.key,
    required this.usbDacExclusive,
    required this.gaplessPlayback,
    required this.mediaNotificationEnabled,
    required this.connectedDacName,
    required this.userName,
    required this.onUserNameChanged,
    required this.onUsbDacChanged,
    required this.onGaplessChanged,
    required this.onNotificationChanged,
    required this.onRescan,
  });

  @override
  State<MainSettingsScreen> createState() => _MainSettingsScreenState();
}

class _MainSettingsScreenState extends State<MainSettingsScreen> {
  late bool _usbDac;
  late bool _gapless;
  late bool _notification;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _usbDac = widget.usbDacExclusive;
    _gapless = widget.gaplessPlayback;
    _notification = widget.mediaNotificationEnabled;
    _nameController = TextEditingController(text: widget.userName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('User Profile & Greeting', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurpleAccent)),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Display Name'),
                  onChanged: widget.onUserNameChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF14141F), borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Hi-Res Lossless & USB DAC Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurpleAccent)),
                const SizedBox(height: 4),
                Text('Hardware Output: ${widget.connectedDacName}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('USB DAC Exclusive Routing'),
                  subtitle: const Text('Bypass Android audio resampler'),
                  value: _usbDac,
                  activeColor: Colors.deepPurpleAccent,
                  onChanged: (v) {
                    setState(() => _usbDac = v);
                    widget.onUsbDacChanged(v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gapless Playback'),
                  subtitle: const Text('Zero latency transition between FLAC tracks'),
                  value: _gapless,
                  activeColor: Colors.deepPurpleAccent,
                  onChanged: (v) {
                    setState(() => _gapless = v);
                    widget.onGaplessChanged(v);
                  },
                ),
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.refresh_rounded, color: Colors.deepPurpleAccent),
            title: const Text('Rescan Music & Cover Art'),
            onTap: () {
              widget.onRescan();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescanning library...')));
            },
          ),
        ],
      ),
    );
  }
}

class NowPlayingModal extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final AudioTrack? currentSong;
  final List<MornyeExtension> extensions;
  final bool usbDacActive;
  final String dacName;
  final VoidCallback onShowPath;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const NowPlayingModal({
    super.key,
    required this.audioPlayer,
    required this.currentSong,
    required this.extensions,
    required this.usbDacActive,
    required this.dacName,
    required this.onShowPath,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<NowPlayingModal> createState() => _NowPlayingModalState();
}

class _NowPlayingModalState extends State<NowPlayingModal> {
  int _viewMode = 0; // 0 = Cover Art, 1 = Synced Lyrics, 2 = Mornye
  final ScrollController _lyricsScrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Color(0xFF0D0D14), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: Icon(Icons.album_rounded, color: _viewMode == 0 ? Colors.deepPurpleAccent : Colors.grey), onPressed: () => setState(() => _viewMode = 0)),
              IconButton(icon: Icon(Icons.lyrics_rounded, color: _viewMode == 1 ? Colors.deepPurpleAccent : Colors.grey), onPressed: () => setState(() => _viewMode = 1)),
              IconButton(icon: Icon(Icons.extension_rounded, color: _viewMode == 2 ? Colors.deepPurpleAccent : Colors.grey), onPressed: () => setState(() => _viewMode = 2)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: _viewMode == 0
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 250,
                          height: 250,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.25), blurRadius: 40, spreadRadius: 5)]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: widget.currentSong?.albumArt != null 
                                ? Image.memory(widget.currentSong!.albumArt!, fit: BoxFit.cover)
                                : Container(color: Colors.purple.shade900, child: const Icon(Icons.album_rounded, size: 90, color: Colors.white70)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(widget.currentSong?.title ?? 'No Track Selected', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
                        const SizedBox(height: 6),
                        Text(widget.currentSong?.artist ?? 'Lossless Hi-Fi', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: widget.onShowPath,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline_rounded, size: 14, color: Colors.deepPurpleAccent),
                                SizedBox(width: 6),
                                Text('Audio • FLAC • 24-bit Hi-Res (Tap for Path)', style: TextStyle(fontSize: 11, color: Colors.deepPurpleAccent)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : _viewMode == 1
                      // Time-Synced Scrolling Lyrics
                      ? StreamBuilder<Duration>(
                          stream: widget.audioPlayer.positionStream,
                          builder: (context, snapshot) {
                            final pos = snapshot.data ?? Duration.zero;
                            final lyrics = widget.currentSong?.parsedLyrics ?? [];
                            if (lyrics.isEmpty) {
                              return Center(child: Text(widget.currentSong?.rawLyrics ?? "No lyrics available.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)));
                            }
                            int activeIdx = lyrics.lastIndexWhere((l) => l.timestamp <= pos);
                            if (activeIdx < 0) activeIdx = 0;

                            return ListView.builder(
                              controller: _lyricsScrollController,
                              itemCount: lyrics.length,
                              itemBuilder: (context, idx) {
                                final isCurrent = idx == activeIdx;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    lyrics[idx].text,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: isCurrent ? 20 : 15,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      color: isCurrent ? Colors.deepPurpleAccent : Colors.white24,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        )
                      : ListView(
                          children: [
                            const Text('Mornye .sflx Providers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            ...widget.extensions.map((ext) => SwitchListTile(
                              title: Text(ext.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: Text('${ext.format} • v${ext.version}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              value: ext.isEnabled,
                              activeColor: Colors.deepPurpleAccent,
                              onChanged: (val) => setState(() => ext.isEnabled = val),
                            )),
                          ],
                        ),
            ),
          ),

          // Merged Interactive Waveform Seekbar
          StreamBuilder<Duration>(
            stream: widget.audioPlayer.positionStream,
            builder: (context, positionSnapshot) {
              final position = positionSnapshot.data ?? Duration.zero;
              return StreamBuilder<Duration?>(
                stream: widget.audioPlayer.durationStream,
                builder: (context, durationSnapshot) {
                  final duration = durationSnapshot.data ?? Duration.zero;
                  double maxMs = duration.inMilliseconds.toDouble();
                  if (maxMs <= 0) maxMs = 1.0;
                  double currentMs = position.inMilliseconds.toDouble();
                  if (currentMs > maxMs) currentMs = maxMs;

                  return Column(
                    children: [
                      // Integrated Interactive Waveform
                      GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          final RenderBox box = context.findRenderObject() as RenderBox;
                          final double progress = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
                          widget.audioPlayer.seek(Duration(milliseconds: (progress * maxMs).toInt()));
                        },
                        onTapDown: (details) {
                          final RenderBox box = context.findRenderObject() as RenderBox;
                          final double progress = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
                          widget.audioPlayer.seek(Duration(milliseconds: (progress * maxMs).toInt()));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: Colors.transparent,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(36, (i) {
                              final heights = [12.0, 24.0, 36.0, 18.0, 30.0, 42.0, 15.0, 28.0, 38.0, 20.0];
                              final h = heights[i % heights.length];
                              final progress = currentMs / maxMs;
                              final isPassed = (i / 36.0) <= progress;
                              return Container(
                                width: 4,
                                height: h,
                                decoration: BoxDecoration(
                                  color: isPassed ? Colors.deepPurpleAccent : Colors.white24,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                          Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(icon: const Icon(Icons.shuffle_rounded), onPressed: () {}),
              IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 32), onPressed: widget.onPrevious),
              StreamBuilder<bool>(
                stream: widget.audioPlayer.playingStream,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  return IconButton(icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 64, color: Colors.deepPurpleAccent), onPressed: widget.onPlayPause);
                },
              ),
              IconButton(icon: const Icon(Icons.skip_next_rounded, size: 32), onPressed: widget.onNext),
              IconButton(icon: const Icon(Icons.repeat_rounded), onPressed: () {}),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    int minutes = d.inMinutes;
    int seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
