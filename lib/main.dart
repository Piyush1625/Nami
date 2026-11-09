import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

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
  final String title;
  final String artist;
  final String path;
  final String lyrics;
  AudioTrack({
    required this.title,
    required this.artist,
    required this.path,
    this.lyrics = "[00:00.00] Nami Lossless Hi-Fi Audio Engine\n[00:05.00] Bit-perfect FLAC streaming active\n[00:12.00] Synced lyrics rendered behind cover art",
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
  List<AudioTrack> _songs = [];
  List<AudioTrack> _filteredSongs = [];
  AudioTrack? _currentSong;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  final List<MornyeExtension> _extensions = [
    MornyeExtension(name: 'Tidal Hi-Res Lossless Provider', version: '1.2.0', author: 'Mornye Team', isEnabled: true),
    MornyeExtension(name: 'Qobuz Studio Master Catalog', version: '1.1.4', author: 'OpenAudio', isEnabled: true),
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissionAndScanMusic();
    
    _audioPlayer.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
    });

    _audioPlayer.positionStream.listen((pos) {
      setState(() => _position = pos);
    });

    _audioPlayer.durationStream.listen((dur) {
      setState(() => _duration = dur ?? Duration.zero);
    });
  }

  Future<void> _requestPermissionAndScanMusic() async {
    PermissionStatus status = await Permission.audio.request();
    if (!status.isGranted) status = await Permission.storage.request();
    if (!status.isGranted) status = await Permission.manageExternalStorage.request();

    if (status.isGranted || await Permission.storage.isGranted) {
      setState(() => _hasPermission = true);
      await _scanDeviceMusic();
    }
  }

  Future<void> _scanDeviceMusic() async {
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
              foundTracks.add(AudioTrack(title: cleanName, artist: 'Lossless Local Audio', path: entity.path));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning music: $e');
    }

    if (foundTracks.isEmpty) {
      foundTracks.add(AudioTrack(
        title: 'Sample Lossless FLAC Track',
        artist: 'Nami Hi-Fi Engine',
        path: '',
        lyrics: "[00:02.00] Welcome to Nami Music Player\n[00:07.00] Namida UI + Mornye .sflx Engine\n[00:15.00] Tap cover art to toggle lyrics & extensions!",
      ));
    }

    setState(() {
      _songs = foundTracks;
      _filteredSongs = foundTracks;
    });
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
    if (song.path.isEmpty) {
      setState(() => _currentSong = song);
      return;
    }
    try {
      await _audioPlayer.setAudioSource(AudioSource.file(song.path));
      await _audioPlayer.play();
      setState(() => _currentSong = song);
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
        currentSong: _currentSong ?? _filteredSongs.firstOrNull,
        isPlaying: _isPlaying,
        position: _position,
        duration: _duration,
        extensions: _extensions,
        onPlayPause: _togglePlayPause,
        onSeek: (val) => _audioPlayer.seek(val),
        onNext: () {
          if (_filteredSongs.isNotEmpty && _currentSong != null) {
            int nextIdx = (_filteredSongs.indexOf(_currentSong!) + 1) % _filteredSongs.length;
            _playSong(_filteredSongs[nextIdx]);
          }
        },
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
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
    final List<Widget> pages = [
      // 0. Home Feed (Matches Screenshot 1)
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
                _buildMixCard('Recommended', 'Local FLAC & Hi-Fi Mix', Colors.deepPurple),
                _buildMixCard('Top Listens', 'Most Played Tracks', Colors.purpleAccent),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Recent Listens', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _songs.length > 5 ? 5 : _songs.length,
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
                        Container(
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(child: Icon(Icons.music_note_rounded, size: 36, color: Colors.deepPurpleAccent)),
                        ),
                        const SizedBox(height: 6),
                        Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text('Top Recents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: ['1 Day', '3 Days', '6 Days', '9 Days', '12 Days'].map((tag) => Chip(
              backgroundColor: const Color(0xFF1A1A26),
              label: Text(tag, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            )).toList(),
          ),
        ],
      ),

      // 1. Tracks Page
      _hasPermission
          ? (_filteredSongs.isEmpty
              ? const Center(child: Text('No matching audio files found.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: _filteredSongs.length,
                  itemBuilder: (context, index) {
                    final song = _filteredSongs[index];
                    final isCurrent = _currentSong?.path == song.path;
                    return ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.music_note_rounded, color: Colors.deepPurpleAccent),
                      ),
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
                ))
          : Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                onPressed: _requestPermissionAndScanMusic,
                child: const Text('Grant Storage Permission'),
              ),
            ),

      // 2. Artists Page (Matches Screenshot 2)
      GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.8, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.deepPurple.withOpacity(0.3),
                child: const Icon(Icons.person_rounded, size: 32, color: Colors.deepPurpleAccent),
              ),
              const SizedBox(height: 6),
              Text('Artist ${index + 1}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          );
        },
      ),

      // 3. Playlists Page (Matches Screenshot 3)
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('1 Playlist', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
                onPressed: {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildPlaylistStatCard('History', '778', Icons.history),
              const SizedBox(width: 12),
              _buildPlaylistStatCard('Most Played', '342', Icons.trending_up),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildPlaylistStatCard('Favourites', '3', Icons.favorite),
              const SizedBox(width: 12),
              _buildPlaylistStatCard('Queues', '217', Icons.queue_music),
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: Colors.purple.shade900, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.album_rounded, color: Colors.white),
            ),
            title: const Text('classic✨', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('3 Tracks • 14min', style: TextStyle(fontSize: 11, color: Colors.grey)),
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
                decoration: const InputDecoration(hintText: 'Search music...', border: InputBorder.none, hintStyle: TextStyle(color: Colors.grey)),
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
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openSettings,
          ),
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
                    const Icon(Icons.album_rounded, size: 38, color: Colors.deepPurpleAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_currentSong?.title ?? 'No Track Playing', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(_currentSong != null ? 'Playing Lossless Audio' : '24-bit / Lossless FLAC Ready', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
                      onPressed: _togglePlayPause,
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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSettingTile(Icons.folder_outlined, 'Add Folder', 'Local, (Open) Subsonic, Jellyfin, WebDAV...'),
          _buildSettingTile(Icons.people_outline_rounded, 'Listening party', 'Listen together with others, in sync'),
          _buildSettingTile(Icons.palette_outlined, 'Theme', 'The overall vibe of your player'),
          _buildSettingTile(Icons.library_books_outlined, 'Indexer', 'Manage your music Library'),
          _buildSettingTile(Icons.play_circle_outline_rounded, 'Playback', 'Can be accessed directly in the player by long pressing audio button'),
          _buildSettingTile(Icons.tune_rounded, 'Customizations', 'Customize how your player looks, make it yours'),
          _buildSettingTile(Icons.video_library_outlined, 'YouTube', 'Customize YouTube experience'),
          _buildSettingTile(Icons.extension_outlined, 'Extras', 'Extra Settings to fine your experience'),
          _buildSettingTile(Icons.backup_outlined, 'Backup & Restore', 'Backup your database and settings'),
          _buildSettingTile(Icons.admin_panel_settings_outlined, 'Advanced', 'Advanced Settings, don\'t touch'),
          _buildSettingTile(Icons.info_outline_rounded, 'About', 'App information and version details'),
        ],
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, String subtitle) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Icon(icon, color: Colors.deepPurpleAccent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: () {},
    );
  }
}

class NowPlayingModal extends StatefulWidget {
  final AudioTrack? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<MornyeExtension> extensions;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onNext;

  const NowPlayingModal({
    super.key,
    required this.currentSong,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.extensions,
    required this.onPlayPause,
    required this.onSeek,
    required this.onNext,
  });

  @override
  State<NowPlayingModal> createState() => _NowPlayingModalState();
}

class _NowPlayingModalState extends State<NowPlayingModal> {
  int _viewMode = 0; // 0 = Cover Art, 1 = Synced Lyrics, 2 = Mornye Extensions

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
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
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [Colors.deepPurpleAccent, Colors.purple.shade900], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: Colors.deepPurpleAccent.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)],
                          ),
                          child: const Icon(Icons.album_rounded, size: 90, color: Colors.white70),
                        ),
                        const SizedBox(height: 32),
                        Text(widget.currentSong?.title ?? 'No Track Selected', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(widget.currentSong?.artist ?? 'Lossless Hi-Fi', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    )
                  : _viewMode == 1
                      ? Container(
                          padding: const EdgeInsets.all(20),
                          width: double.infinity,
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(20)),
                          child: SingleChildScrollView(
                            child: Text(
                              widget.currentSong?.lyrics ?? 'No lyrics available.',
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
          Slider(
            activeColor: Colors.deepPurpleAccent,
            inactiveColor: Colors.white12,
            min: 0.0,
            max: widget.duration.inMilliseconds > 0 ? widget.duration.inMilliseconds.toDouble() : 1.0,
            value: widget.position.inMilliseconds.clamp(0, widget.duration.inMilliseconds > 0 ? widget.duration.inMilliseconds : 1).toDouble(),
            onChanged: (val) => widget.onSeek(Duration(milliseconds: val.toInt())),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(widget.position), style: const TextStyle(color: Colors.grey, fontSize: 11)),
              Text(_formatDuration(widget.duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(icon: const Icon(Icons.shuffle_rounded), onPressed: () {}),
              IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 32), onPressed: () {}),
              IconButton(icon: Icon(widget.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 64, color: Colors.deepPurpleAccent), onPressed: widget.onPlayPause),
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
