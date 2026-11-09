import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
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
  AudioTrack({required this.title, required this.artist, required this.path});
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
  AudioTrack? _currentSong;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndScanMusic();
    
    _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });
  }

  Future<void> _requestPermissionAndScanMusic() async {
    PermissionStatus status = await Permission.audio.request();
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }

    if (status.isGranted || await Permission.storage.isGranted) {
      setState(() => _hasPermission = true);
      await _scanDeviceMusic();
    }
  }

  Future<void> _scanDeviceMusic() async {
    List<AudioTrack> foundTracks = [];
    try {
      List<Directory> searchDirs = [];
      
      final externalDirs = await getExternalStorageDirectories(type: StorageDirectory.music);
      if (externalDirs != null) searchDirs.addAll(externalDirs);

      final rootMusic = Directory('/storage/emulated/0/Music');
      if (await rootMusic.exists()) {
        searchDirs.add(rootMusic);
      }
      
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        searchDirs.add(downloadDir);
      }

      for (var dir in searchDirs) {
        if (await dir.exists()) {
          await for (var entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              String path = entity.path.toLowerCase();
              if (path.endsWith('.flac') || path.endsWith('.mp3') || path.endsWith('.m4a') || path.endsWith('.ogg') || path.endsWith('.wav')) {
                String fileName = entity.uri.pathSegments.last;
                String cleanName = fileName.substring(0, fileName.lastIndexOf('.')).replaceAll('_', ' ');
                foundTracks.add(AudioTrack(
                  title: cleanName,
                  artist: 'Lossless Audio / Local Storage',
                  path: entity.path,
                ));
              }
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
        artist: 'Nami Hi-Fi Audio Engine',
        path: '',
      ));
    }

    setState(() {
      _songs = foundTracks;
    });
  }

  Future<void> _playSong(AudioTrack song) async {
    if (song.path.isEmpty) return;
    try {
      await _audioPlayer.setAudioSource(AudioSource.file(song.path));
      await _audioPlayer.play();
      setState(() {
        _currentSong = song;
      });
    } catch (e) {
      debugPrint('Error playing track: $e');
    }
  }

  void _togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      if (_currentSong == null && _songs.isNotEmpty && _songs.first.path.isNotEmpty) {
        await _playSong(_songs.first);
      } else {
        await _audioPlayer.play();
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _hasPermission
          ? (_songs.isEmpty
              ? const Center(child: Text('Scanning music storage...', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    final isCurrent = _currentSong?.path == song.path;
                    return ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Colors.deepPurpleAccent),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? Colors.deepPurpleAccent : Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.play_circle_fill_rounded, color: Colors.deepPurpleAccent, size: 28),
                      onTap: () => _playSong(song),
                    );
                  },
                ))
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Storage permission is required to scan your FLAC & music library.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent),
                      onPressed: _requestPermissionAndScanMusic,
                      child: const Text('Grant Permission'),
                    ),
                  ],
                ),
              ),
            ),
      const Center(child: Text('Synced Lyrics (.lrc) Engine', style: TextStyle(fontSize: 18, color: Colors.grey))),
      const Center(child: Text('Mornye (.sflx) Extension Manager', style: TextStyle(fontSize: 18, color: Colors.grey))),
      const Center(child: Text('USB DAC & Audio Output Settings', style: TextStyle(fontSize: 18, color: Colors.grey))),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'NAMI',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2.0),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search_rounded), onPressed: () {}),
          IconButton(icon: const Icon(Icons.equalizer_rounded), onPressed: () {}),
        ],
      ),
      body: Stack(
        children: [
          pages[_selectedIndex],
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A26).withOpacity(0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.deepPurpleAccent.withOpacity(0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurpleAccent.withOpacity(0.15),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
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
                        Text(
                          _currentSong?.title ?? 'No Track Playing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          _currentSong != null ? 'Playing Lossless Audio' : '24-bit / Lossless FLAC Ready',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
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
                      if (_songs.isNotEmpty && _currentSong != null) {
                        int nextIdx = (_songs.indexOf(_currentSong!) + 1) % _songs.length;
                        _playSong(_songs[nextIdx]);
                      } else if (_songs.isNotEmpty) {
                        _playSong(_songs.first);
                      }
                    },
                  ),
                ],
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
          NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Tracks'),
          NavigationDestination(icon: Icon(Icons.lyrics_outlined), selectedIcon: Icon(Icons.lyrics_rounded), label: 'Lyrics'),
          NavigationDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension_rounded), label: 'Mornye'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Audio/DAC'),
        ],
      ),
    );
  }
}
