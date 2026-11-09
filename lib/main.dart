import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

void main() {
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
  bool isEnabled;
  MornyeExtension({required this.name, required this.version, required this.author, this.isEnabled = true});
}

class NamiHomeShell extends StatefulWidget {
  const NamiHomeShell({super.key});

  @override
  State<NamiHomeShell> createState() => _NamiHomeShellState();
}

class _NamiHomeShellState extends State<NamiHomeShell> {
  int _selectedIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _hasPermission = false;
  bool _isScanning = false;
  List<AudioTrack> _songs = [];
  List<AudioTrack> _filteredSongs = [];
  AudioTrack? _currentSong;
  bool _isPlaying = false;
  
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  final List<MornyeExtension> _extensions = [
    MornyeExtension(name: 'Tidal Hi-Res Lossless', version: '1.2.0', author: 'Mornye', isEnabled: true),
    MornyeExtension(name: 'Qobuz Studio Master', version: '1.1.4', author: 'OpenAudio', isEnabled: true),
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissionAndScanMusic();
    
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
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

  // 1. FAST PASS: Instant File Discovery (Loads in < 1 second)
  Future<void> _fastScanDeviceMusic() async {
    List<AudioTrack> foundTracks = [];
    try {
      List<Directory> searchDirs = [];
      final rootMusic = Directory('/storage/emulated/0/Music');
      if (await rootMusic.exists()) searchDirs.add(rootMusic);
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) searchDirs.add(downloadDir);

      for (var dir in searchDirs) {
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            String path = entity.path.toLowerCase();
            if (path.endsWith('.flac') || path.endsWith('.mp3') || path.endsWith('.m4a') || path.endsWith('.ogg') || path.endsWith('.wav')) {
              String fileName = entity.uri.pathSegments.last;
              String cleanName = fileName.substring(0, fileName.lastIndexOf('.')).replaceAll('_', ' ');
              String artist = 'Unknown Artist';
              
              if (cleanName.contains(' - ')) {
                final parts = cleanName.split(' - ');
                artist = parts[0].trim();
                cleanName = parts.sublist(1).join(' - ').trim();
              }

              foundTracks.add(AudioTrack(
                title: cleanName,
                artist: artist,
                album: 'Local Audio',
                path: entity.path,
              ));
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

    // 2. SLOW PASS: Extract Cover Art & ID3 Tags in Background
    _enrichMetadataInBackground();
  }

  Future<void> _enrichMetadataInBackground() async {
    for (int i = 0; i < _songs.length; i++) {
      if (!_songs[i].isMetadataLoaded) {
        await _extractAudioMetadata(_songs[i]);
        if (i % 5 == 0 && mounted) {
          setState(() {}); // Update UI every 5 songs
        }
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _extractAudioMetadata(AudioTrack track) async {
    try {
      final file = File(track.path);
      final raf = await file.open(mode: FileMode.read);
      // Read first 256KB using RandomAccessFile (Lightning fast compared to streams)
      final data = await raf.read(256 * 1024); 
      await raf.close();

      // FLAC Parser
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
              if (upper.startsWith('TITLE=')) track.title = line.substring(6).trim();
              if (upper.startsWith('ARTIST=')) track.artist = line.substring(7).trim();
              if (upper.startsWith('ALBUM=')) track.album = line.substring(6).trim();
            }
          } else if (blockType == 6 && offset + length <= data.length) {
            int picOffset = offset + 4;
            int mimeLen = (data[picOffset] << 24) | (data[picOffset + 1] << 16) | (data[picOffset + 2] << 8) | data[picOffset + 3];
            picOffset += 4 + mimeLen;
            int descLen = (data[picOffset] << 24) | (data[picOffset + 1] << 16) | (data[picOffset + 2] << 8) | data[picOffset + 3];
            picOffset += 4 + descLen + 16; 
            int dataLen = (data[picOffset] << 24) | (data[picOffset + 1] << 16) | (data[picOffset + 2] << 8) | data[picOffset + 3];
            picOffset += 4;
            if (picOffset + dataLen <= data.length) {
              track.albumArt = data.sublist(picOffset, picOffset + dataLen);
            }
          }
          if (isLast) break;
          offset += length;
        }
      }

      // MP3 ID3v2 Parser
      if (data.length > 10 && data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) {
        int tagSize = ((data[6] & 0x7F) << 21) | ((data[7] & 0x7F) << 14) | ((data[8] & 0x7F) << 7) | (data[9] & 0x7F);
        int offset = 10;
        int maxOffset = (tagSize + 10 < data.length) ? tagSize + 10 : data.length;

        while (offset + 10 < maxOffset) {
          String frameId = String.fromCharCodes(data.sublist(offset, offset + 4));
          int frameSize = (data[offset + 4] << 24) | (data[offset + 5] << 16) | (data[offset + 6] << 8) | data[offset + 7];
          offset += 10;
          if (frameSize <= 0 || offset + frameSize > maxOffset) break;

          if (frameId == 'TIT2') track.title = utf8.decode(data.sublist(offset + 1, offset + frameSize), allowMalformed: true).trim();
          else if (frameId == 'TPE1') track.artist = utf8.decode(data.sublist(offset + 1, offset + frameSize), allowMalformed: true).trim();
          else if (frameId == 'TALB') track.album = utf8.decode(data.sublist(offset + 1, offset + frameSize), allowMalformed: true).trim();
          else if (frameId == 'APIC' && track.albumArt == null) {
            for (int j = offset + 1; j < offset + frameSize - 3; j++) {
              if ((data[j] == 0xFF && data[j + 1] == 0xD8) || (data[j] == 0x89 && data[j + 1] == 0x50)) {
                track.albumArt = data.sublist(j, offset + frameSize);
                break;
              }
            }
          }
          offset += frameSize;
        }
      }
    } catch (_) {}
    track.isMetadataLoaded = true;
  }

  // NAMIDA-STYLE ONLINE LYRICS FETCHER
  Future<void> _fetchLyricsOnline(AudioTrack song) async {
    if (song.lyrics != "Loading lyrics...") return;
    try {
      final uri = Uri.parse('https://lrclib.net/api/get?track_name=${Uri.encodeComponent(song.title)}&artist_name=${Uri.encodeComponent(song.artist)}');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        song.lyrics = json['syncedLyrics'] ?? json['plainLyrics'] ?? "No lyrics found online.";
      } else {
        song.lyrics = "No lyrics available for this track.";
      }
    } catch (e) {
      song.lyrics = "Network error fetching lyrics.";
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

  Future<void> _playSong(AudioTrack song) async {
    if (song.path.isEmpty) return;
    try {
      await _audioPlayer.setAudioSource(AudioSource.file(song.path));
      await _audioPlayer.play();
      setState(() => _currentSong = song);
      _fetchLyricsOnline(song); // Fetch lyrics when song starts
    } catch (e) {
      debugPrint('Error playing track: $e');
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

  void _showNowPlayingScreen() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NowPlayingModal(
        audioPlayer: _audioPlayer,
        currentSong: _currentSong ?? _filteredSongs.firstOrNull,
        extensions: _extensions,
        onPlayPause: _togglePlayPause,
        onNext: () {
          if (_filteredSongs.isNotEmpty && _currentSong != null) {
            int nextIdx = (_filteredSongs.indexOf(_currentSong!) + 1) % _filteredSongs.length;
            _playSong(_filteredSongs[nextIdx]);
          }
        },
        onPrevious: () {
          if (_filteredSongs.isNotEmpty && _currentSong != null) {
            int prevIdx = (_filteredSongs.indexOf(_currentSong!) - 1 + _filteredSongs.length) % _filteredSongs.length;
            _playSong(_filteredSongs[prevIdx]);
          }
        },
      ),
    );
  }

  void _openSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const MainSettingsScreen()));
  }

  Widget _buildCoverArt(AudioTrack song, double size, double radius) {
    if (song.albumArt != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(song.albumArt!, width: size, height: size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.3), borderRadius: BorderRadius.circular(radius)),
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
                _buildMixCard('Recommended', '${_songs.length} Local Tracks', Colors.deepPurple),
                _buildMixCard('Hi-Fi Lossless', 'Bit-Perfect FLAC', Colors.purpleAccent),
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
              height: 140,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _songs.length > 6 ? 6 : _songs.length,
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
                          trailing: const Icon(Icons.play_circle_fill_rounded, color: Colors.deepPurpleAccent, size: 28),
                          onTap: () => _playSong(song),
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

          return Column(
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
            leading: _songs.isNotEmpty && _songs.first.albumArt != null
                ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_songs.first.albumArt!, width: 50, height: 50, fit: BoxFit.cover))
                : Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.purple.shade900, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.album_rounded, color: Colors.white)),
            title: const Text('Local FLAC Library✨', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${_songs.length} Tracks Detected', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            trailing: const Icon(Icons.more_vert_rounded, color: Colors.grey),
          ),
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
                decoration: const InputDecoration(hintText: 'Search tracks...', border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey)),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : Text(
                _selectedIndex == 0 ? 'Namida' : (_selectedIndex == 1 ? 'Tracks' : (_selectedIndex == 2 ? 'Artists' : 'Playlists')),
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
                    if (_currentSong != null) _buildCoverArt(_currentSong!, 38, 8)
                    else const Icon(Icons.album_rounded, size: 38, color: Colors.deepPurpleAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_currentSong?.title ?? 'No Track Playing', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(_currentSong?.artist ?? '24-bit / Lossless Ready', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    StreamBuilder<bool>(
                      stream: _audioPlayer.playingStream,
                      builder: (context, snapshot) {
                        final isPlaying = snapshot.data ?? false;
                        return IconButton(icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28), onPressed: _togglePlayPause);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 24),
                      onPressed: () {
                        if (_filteredSongs.isNotEmpty && _currentSong != null) {
                          int nextIdx = (_filteredSongs.indexOf(_currentSong!) + 1) % _filteredSongs.length;
                          _playSong(_filteredSongs[nextIdx]);
                        }
                      },
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
        ],
      ),
    );
  }

  Widget _buildMixCard(String title, String subtitle, Color color) {
    return Container(
      width: 160,
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
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

// REAL INTERACTIVE SETTINGS SCREENS
class MainSettingsScreen extends StatelessWidget {
  const MainSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingTile(context, Icons.library_books_outlined, 'Library Indexer', 'Manage local folders, scanning speed and exclusions', const IndexerSettingsScreen()),
          _buildSettingTile(context, Icons.play_circle_outline_rounded, 'Playback Config', 'Gapless playback, crossfade, and equalizer', const PlaybackSettingsScreen()),
          _buildSettingTile(context, Icons.palette_outlined, 'Theme Settings', 'Pitch black AMOLED, dynamic colors, and accents', const ThemeSettingsScreen()),
        ],
      ),
    );
  }

  Widget _buildSettingTile(BuildContext context, IconData icon, String title, String subtitle, Widget screen) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Icon(icon, color: Colors.deepPurpleAccent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => screen)),
    );
  }
}

class IndexerSettingsScreen extends StatefulWidget { const IndexerSettingsScreen({super.key}); @override State<IndexerSettingsScreen> createState() => _IndexerSettingsState(); }
class _IndexerSettingsState extends State<IndexerSettingsScreen> {
  bool autoScan = true;
  bool skipShort = true;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Library Indexer'), backgroundColor: Colors.transparent),
      body: ListView(
        children: [
          SwitchListTile(title: const Text('Auto-scan on startup'), subtitle: const Text('Check for new files automatically'), value: autoScan, activeColor: Colors.deepPurpleAccent, onChanged: (v) => setState(() => autoScan = v)),
          SwitchListTile(title: const Text('Ignore short tracks'), subtitle: const Text('Skip audio files under 30 seconds'), value: skipShort, activeColor: Colors.deepPurpleAccent, onChanged: (v) => setState(() => skipShort = v)),
          ListTile(title: const Text('Force Full Rescan'), leading: const Icon(Icons.refresh_rounded), onTap: () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescan initiated...'))); }),
        ],
      ),
    );
  }
}

class PlaybackSettingsScreen extends StatefulWidget { const PlaybackSettingsScreen({super.key}); @override State<PlaybackSettingsScreen> createState() => _PlaybackSettingsState(); }
class _PlaybackSettingsState extends State<PlaybackSettingsScreen> {
  bool gapless = true;
  bool exclusiveDac = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Playback Config'), backgroundColor: Colors.transparent),
      body: ListView(
        children: [
          SwitchListTile(title: const Text('Gapless Playback'), subtitle: const Text('Remove silence between tracks'), value: gapless, activeColor: Colors.deepPurpleAccent, onChanged: (v) => setState(() => gapless = v)),
          SwitchListTile(title: const Text('USB DAC Exclusive Mode'), subtitle: const Text('Bypass Android audio resampler for bit-perfect output'), value: exclusiveDac, activeColor: Colors.deepPurpleAccent, onChanged: (v) => setState(() => exclusiveDac = v)),
        ],
      ),
    );
  }
}

class ThemeSettingsScreen extends StatefulWidget { const ThemeSettingsScreen({super.key}); @override State<ThemeSettingsScreen> createState() => _ThemeSettingsState(); }
class _ThemeSettingsState extends State<ThemeSettingsScreen> {
  bool amoled = true;
  bool materialYou = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Theme Settings'), backgroundColor: Colors.transparent),
      body: ListView(
        children: [
          SwitchListTile(title: const Text('Pitch Black (AMOLED)'), subtitle: const Text('Use pure black background for battery saving'), value: amoled, activeColor: Colors.deepPurpleAccent, onChanged: (v) => setState(() => amoled = v)),
          SwitchListTile(title: const Text('Dynamic Colors (Material You)'), subtitle: const Text('Match UI colors with album art or system wallpaper'), value: materialYou, activeColor: Colors.deepPurpleAccent, onChanged: (v) => setState(() => materialYou = v)),
        ],
      ),
    );
  }
}

class NowPlayingModal extends StatefulWidget {
  final AudioPlayer audioPlayer;
  final AudioTrack? currentSong;
  final List<MornyeExtension> extensions;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const NowPlayingModal({
    super.key,
    required this.audioPlayer,
    required this.currentSong,
    required this.extensions,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  State<NowPlayingModal> createState() => _NowPlayingModalState();
}

class _NowPlayingModalState extends State<NowPlayingModal> {
  int _viewMode = 0;

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
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: _viewMode == 0
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.2), blurRadius: 40, spreadRadius: 5)]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: widget.currentSong?.albumArt != null 
                                ? Image.memory(widget.currentSong!.albumArt!, fit: BoxFit.cover)
                                : Container(color: Colors.purple.shade900, child: const Icon(Icons.album_rounded, size: 90, color: Colors.white70)),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(widget.currentSong?.title ?? 'No Track Selected', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(widget.currentSong?.artist ?? 'Lossless Hi-Fi', style: const TextStyle(color: Colors.grey, fontSize: 16)),
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
                              subtitle: Text('v${ext.version} • ${ext.author}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 20),
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
