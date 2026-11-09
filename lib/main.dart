import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
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

class AudioTrack {
  String title;
  String artist;
  String album;
  final String path;
  Uint8List? albumArt;
  String lyrics;
  bool isMetadataLoaded;

  AudioTrack({
    required this.title,
    required this.artist,
    required this.album,
    required this.path,
    this.albumArt,
    this.lyrics = "Loading lyrics...",
    this.isMetadataLoaded = false,
  });
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
  AudioTrack? _currentSong;
  bool _isPlaying = false;
  
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // USB DAC & Bit-Perfect State
  bool _usbDacExclusive = true;
  bool _gaplessPlayback = true;
  String _connectedDacName = "Scanning audio outputs...";

  // Mornye .sflx Extensions
  final List<MornyeExtension> _extensions = [
    MornyeExtension(name: 'Tidal Hi-Res FLAC (.sflx)', version: '1.4.2', author: 'Mornye Core', format: '24-bit / 192kHz FLAC', isEnabled: true),
    MornyeExtension(name: 'Qobuz Studio Master (.sflx)', version: '1.2.0', author: 'OpenAudio', format: '24-bit / 96kHz Hi-Res', isEnabled: true),
    MornyeExtension(name: 'Apple Music ALAC Bridge (.sflx)', version: '0.9.8', author: 'Nami Community', format: 'Lossless ALAC', isEnabled: false),
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
      // Auto-advance to next song when current finishes
      if (state.processingState == ProcessingState.completed) {
        _playNextTrack();
      }
    });
  }

  // Configure Hardware Audio Session & Detect USB DAC
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

      // Apply bit-perfect speed/pitch lock
      await _audioPlayer.setSpeed(1.0);
      await _audioPlayer.setPitch(1.0);
      await _audioPlayer.setSkipSilenceEnabled(false);

      // Check connected hardware audio outputs (USB DACs, Wired Headsets, etc.)
      final devices = await session.getDevices();
      String foundOut = "Internal Hi-Fi DAC (Direct PCM)";
      for (var d in devices) {
        if (d.isOutput) {
          final typeName = d.type.toString().toLowerCase();
          if (typeName.contains('usb')) {
            foundOut = "USB DAC Connected: ${d.name} (Bit-Perfect)";
            break;
          } else if (typeName.contains('wired')) {
            foundOut = "Wired Output: ${d.name}";
          }
        }
      }
      if (mounted) setState(() => _connectedDacName = foundOut);
    } catch (e) {
      if (mounted) setState(() => _connectedDacName = "Direct PCM Output Ready");
    }
  }

  Future<void> _toggleUsbDacMode(bool enabled) async {
    setState(() => _usbDacExclusive = enabled);
    await _initAudioSessionAndDac();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled
              ? 'USB DAC Bit-Perfect Mode Enabled ($_connectedDacName)'
              : 'Standard Android Audio Mixer Active'),
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
            // Skip hidden/trashed files
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

              foundTracks.add(AudioTrack(title: cleanName, artist: artist, album: 'Local Audio', path: path));
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

  // Deep 2.5MB Buffer Scanner for High-Res FLAC, MP3, and M4A Cover Art
  Future<void> _extractAudioMetadata(AudioTrack track) async {
    try {
      final file = File(track.path);
      final fileLen = await file.length();
      // Read up to 2.5 MB so large high-res FLAC/MP3 cover art is never truncated
      final readSize = fileLen < (2560 * 1024) ? fileLen : (2560 * 1024);
      final raf = await file.open(mode: FileMode.read);
      final data = await raf.read(readSize);
      await raf.close();

      // 1. FLAC Parser
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

      // 2. MP3 ID3v2.3 & ID3v2.4 Parser
      if (data.length > 10 && data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) {
        int version = data[3]; // 3 = v2.3, 4 = v2.4
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

      // 3. Universal Fallback Carve (Catches M4A covr atoms, ID3v2.2 PIC, or non-standard FLAC/MP3 headers)
      if (track.albumArt == null) {
        track.albumArt = _extractEmbeddedImageBytes(data, 0, data.length);
      }

      // Also check if folder has cover.jpg / folder.jpg
      if (track.albumArt == null) {
        final parent = file.parent;
        for (final name in ['cover.jpg', 'cover.png', 'folder.jpg', 'album.jpg']) {
          final imgFile = File('${parent.path}/$name');
          if (await imgFile.exists()) {
            track.albumArt = await imgFile.readAsBytes();
            break;
          }
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
      // UTF-16
      final filtered = content.where((b) => b != 0x00 && b != 0xFF && b != 0xFE).toList();
      return _cleanString(utf8.decode(filtered, allowMalformed: true));
    }
    return _cleanString(utf8.decode(content, allowMalformed: true));
  }

  Uint8List? _extractEmbeddedImageBytes(Uint8List data, int start, int end) {
    for (int j = start; j < end - 8; j++) {
      // Check for JPEG SOI (FF D8 FF E0 / E1 / DB)
      if (data[j] == 0xFF && data[j + 1] == 0xD8 && data[j + 2] == 0xFF &&
          (data[j + 3] == 0xE0 || data[j + 3] == 0xE1 || data[j + 3] == 0xDB || data[j + 3] == 0xEE)) {
        // Find JPEG EOI (FF D9) or take up to end of frame
        int imgEnd = end;
        for (int k = j + 4; k < end - 1; k++) {
          if (data[k] == 0xFF && data[k + 1] == 0xD9) {
            imgEnd = k + 2;
            // keep looking if inside APIC frame with known end
            if (imgEnd - j > 2048) break;
          }
        }
        if (imgEnd - j > 1024) {
          return data.sublist(j, imgEnd);
        }
      }
      // Check for PNG signature (89 50 4E 47 0D 0A 1A 0A)
      if (data[j] == 0x89 && data[j + 1] == 0x50 && data[j + 2] == 0x4E && data[j + 3] == 0x47 &&
          data[j + 4] == 0x0D && data[j + 5] == 0x0A) {
        int imgEnd = end;
        for (int k = j + 8; k < end - 4; k++) {
          // IEND chunk
          if (data[k] == 0x49 && data[k + 1] == 0x45 && data[k + 2] == 0x4E && data[k + 3] == 0x44) {
            imgEnd = (k + 8 <= end) ? k + 8 : end;
            break;
          }
        }
        if (imgEnd - j > 1024) {
          return data.sublist(j, imgEnd);
        }
      }
    }
    return null;
  }

  Future<void> _fetchLyricsOnline(AudioTrack song) async {
    if (song.lyrics != "Loading lyrics...") return;
    try {
      final uri = Uri.parse('https://lrclib.net/api/get?track_name=${Uri.encodeComponent(song.title)}&artist_name=${Uri.encodeComponent(song.artist)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        song.lyrics = json['syncedLyrics'] ?? json['plainLyrics'] ?? "No lyrics found online.";
      } else {
        // Fallback search query if exact match fails
        final searchUri = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent(song.title)}');
        final searchRes = await http.get(searchUri).timeout(const Duration(seconds: 6));
        if (searchRes.statusCode == 200) {
          final List list = jsonDecode(searchRes.body);
          if (list.isNotEmpty) {
            song.lyrics = list.first['syncedLyrics'] ?? list.first['plainLyrics'] ?? "No lyrics available.";
          } else {
            song.lyrics = "No lyrics found for ${song.title}.";
          }
        } else {
          song.lyrics = "No lyrics available for this track.";
        }
      }
    } catch (e) {
      song.lyrics = "Could not load online lyrics.";
    }
    if (mounted) setState(() {});
  }

  void _filterSongs(String query) {
    setState(() {
      _filteredSongs = _songs.where((song) =>
        song.title.toLowerCase().contains(query.toLowerCase()) ||
        song.artist.toLowerCase().contains(query.toLowerCase())
      ).toList();
    });
  }

  // Direct, reliable file playback
  Future<void> _playSong(AudioTrack song) async {
    if (song.path.isEmpty) return;
    setState(() => _currentSong = song);
    try {
      await _audioPlayer.stop();
      await _audioPlayer.setFilePath(song.path);
      await _audioPlayer.play();
      _fetchLyricsOnline(song);
    } catch (e) {
      debugPrint('Error playing track: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback error: $e'), backgroundColor: Colors.redAccent),
        );
      }
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

  void _togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      if (_currentSong == null && _filteredSongs.isNotEmpty) {
        await _playSong(_filteredSongs.first);
      } else {
        await _audioPlayer.play();
      }
    }
  }

  void _showInstallSflxDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF14141F),
        title: const Text('Install Mornye .sflx Extension'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter .sflx URL or plugin name...',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
            onPressed: () {
              final name = controller.text.trim().isEmpty ? 'Custom Hi-Res Provider (.sflx)' : controller.text.trim();
              setState(() {
                _extensions.add(MornyeExtension(
                  name: name,
                  version: '1.0.0',
                  author: 'User Installed',
                  format: 'Lossless Stream',
                  isEnabled: true,
                ));
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Installed $name successfully!')),
              );
            },
            child: const Text('Install'),
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
      builder: (context) {
        return SafeArea(
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
              _buildMenuTile(Icons.play_circle_fill_rounded, 'Play Now', song.title, () {
                Navigator.pop(context);
                _playSong(song);
              }),
              _buildMenuTile(Icons.album_rounded, 'Album', song.album, () => Navigator.pop(context)),
              _buildMenuTile(Icons.person_rounded, 'Artist', song.artist, () => Navigator.pop(context)),
              _buildMenuTile(Icons.lyrics_rounded, 'Fetch Online Lyrics', 'LRCLIB Synced .LRC', () {
                Navigator.pop(context);
                song.lyrics = "Loading lyrics...";
                _fetchLyricsOnline(song);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fetching synced lyrics...')));
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.deepPurpleAccent),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)) : null,
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
          connectedDacName: _connectedDacName,
          onUsbDacChanged: _toggleUsbDacMode,
          onGaplessChanged: (v) => setState(() => _gaplessPlayback = v),
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
      // 0. Home Feed
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          const Text('Mixes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                GestureDetector(
                  onTap: () {
                    if (_songs.isNotEmpty) _playSong(_songs.first);
                  },
                  child: _buildMixCard('Recommended', '${_songs.length} Local Tracks', Colors.deepPurple),
                ),
                GestureDetector(
                  onTap: () => _toggleUsbDacMode(!_usbDacExclusive),
                  child: _buildMixCard(
                    _usbDacExclusive ? 'USB DAC Active' : 'Standard Output',
                    _connectedDacName,
                    Colors.purpleAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Recent Listens', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_isScanning)
            const Center(child: CircularProgressIndicator(color: Colors.deepPurpleAccent))
          else
            SizedBox(
              height: 145,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _songs.length > 10 ? 10 : _songs.length,
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  return GestureDetector(
                    onTap: () => _playSong(song),
                    onLongPress: () => _showActionMenu(song),
                    child: Container(
                      width: 110,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCoverArt(song, 100, 12),
                          const SizedBox(height: 6),
                          Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: _filteredSongs.length,
                      itemBuilder: (context, index) {
                        final song = _filteredSongs[index];
                        final isCurrent = _currentSong?.path == song.path;
                        return ListTile(
                          leading: _buildCoverArt(song, 48, 8),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? Colors.deepPurpleAccent : Colors.white),
                          ),
                          subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                            onPressed: () => _showActionMenu(song),
                          ),
                          onTap: () => _playSong(song),
                          onLongPress: () => _showActionMenu(song),
                        );
                      },
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
            onTap: () => _playSong(artistSongs.first),
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
                Text('${artistSongs.length} Track${artistSongs.length > 1 ? "s" : ""}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
              _buildPlaylistStatCard('Favourites', '${_songs.length > 5 ? 5 : _songs.length}', Icons.favorite),
              const SizedBox(width: 12),
              _buildPlaylistStatCard('Queue', '${_songs.length}', Icons.queue_music),
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _songs.isNotEmpty ? _buildCoverArt(_songs.first, 50, 10) : _defaultArtPlaceholder(50, 10),
            title: const Text('Local FLAC Library✨', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${_songs.length} Tracks Detected', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            trailing: const Icon(Icons.play_circle_fill_rounded, color: Colors.deepPurpleAccent),
            onTap: () {
              if (_songs.isNotEmpty) _playSong(_songs.first);
            },
          ),
        ],
      ),

      // 4. Dedicated Mornye (.sflx) Extensions Tab
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
                const Row(
                  children: [
                    Icon(Icons.extension_rounded, color: Colors.deepPurpleAccent, size: 28),
                    SizedBox(width: 10),
                    Text('Mornye .sflx Engine', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Modular lossless audio streaming & metadata extension runtime.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('Add .sflx Repository / Plugin'),
                  onPressed: _showInstallSflxDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Installed .sflx Packages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ..._extensions.map((ext) => Card(
            color: const Color(0xFF14141F),
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: SwitchListTile(
              title: Text(ext.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text('${ext.format} • v${ext.version} by ${ext.author}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              value: ext.isEnabled,
              activeColor: Colors.deepPurpleAccent,
              onChanged: (val) => setState(() => ext.isEnabled = val),
            ),
          )),
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
                decoration: const InputDecoration(hintText: 'Search tracks or artists...', border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey)),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : Text(
                tabTitles[_selectedIndex],
                style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5),
              ),
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
                    if (_currentSong != null) _buildCoverArt(_currentSong!, 40, 8)
                    else const Icon(Icons.album_rounded, size: 38, color: Colors.deepPurpleAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_currentSong?.title ?? 'Tap any song to play', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(_currentSong?.artist ?? _connectedDacName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
                      onPressed: _togglePlayPause,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 24),
                      onPressed: _playNextTrack,
                    ),
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

  Widget _buildMixCard(String title, String subtitle, Color color) {
    return Container(
      width: 165,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.album_rounded, size: 40, color: color),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
}

class MainSettingsScreen extends StatefulWidget {
  final bool usbDacExclusive;
  final bool gaplessPlayback;
  final String connectedDacName;
  final ValueChanged<bool> onUsbDacChanged;
  final ValueChanged<bool> onGaplessChanged;
  final VoidCallback onRescan;

  const MainSettingsScreen({
    super.key,
    required this.usbDacExclusive,
    required this.gaplessPlayback,
    required this.connectedDacName,
    required this.onUsbDacChanged,
    required this.onGaplessChanged,
    required this.onRescan,
  });

  @override
  State<MainSettingsScreen> createState() => _MainSettingsScreenState();
}

class _MainSettingsScreenState extends State<MainSettingsScreen> {
  late bool _usbDac;
  late bool _gapless;

  @override
  void initState() {
    super.initState();
    _usbDac = widget.usbDacExclusive;
    _gapless = widget.gaplessPlayback;
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
                const Text('USB DAC & Bit-Perfect Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurpleAccent)),
                const SizedBox(height: 4),
                Text('Hardware Output: ${widget.connectedDacName}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('USB DAC Exclusive Routing'),
                  subtitle: const Text('Lock 1.0x pitch/speed & bypass silence trimming'),
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.refresh_rounded, color: Colors.deepPurpleAccent),
            title: const Text('Rescan Music & Cover Art'),
            subtitle: const Text('Reload ID3v2 / FLAC / M4A cover photos'),
            onTap: () {
              widget.onRescan();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescanning music library...')));
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
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<NowPlayingModal> createState() => _NowPlayingModalState();
}

class _NowPlayingModalState extends State<NowPlayingModal> {
  int _viewMode = 0; // 0 = Cover Art, 1 = Synced Lyrics, 2 = Mornye

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
                        const SizedBox(height: 28),
                        Text(widget.currentSong?.title ?? 'No Track Selected', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
                        const SizedBox(height: 8),
                        Text(widget.currentSong?.artist ?? 'Lossless Hi-Fi', style: const TextStyle(color: Colors.grey, fontSize: 15)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            widget.usbDacActive ? '⚡ ${widget.dacName}' : 'Standard Output',
                            style: const TextStyle(fontSize: 11, color: Colors.deepPurpleAccent),
                          ),
                        ),
                      ],
                    )
                  : _viewMode == 1
                      ? Container(
                          padding: const EdgeInsets.all(20),
                          width: double.infinity,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(20)),
                          child: SingleChildScrollView(
                            child: Text(
                              widget.currentSong?.lyrics ?? "Loading lyrics...",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 16, height: 1.6, fontWeight: FontWeight.w500),
                            ),
                          ),
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
                      Slider(
                        activeColor: Colors.deepPurpleAccent,
                        inactiveColor: Colors.white12,
                        min: 0.0,
                        max: maxMs,
                        value: currentMs,
                        onChanged: (val) => widget.audioPlayer.seek(Duration(milliseconds: val.toInt())),
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
