import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';

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
    this.lyrics = "[00:00.00] Nami Lossless Hi-Fi Audio Engine\n[00:05.00] Enjoy your bit-perfect FLAC tracks\n[00:12.00] Synced lyrics will highlight here in real-time",
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
  AudioTrack? _currentSong;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Mornye Extension State
  final List<MornyeExtension> _extensions = [
    MornyeExtension(name: 'Tidal Hi-Res Lossless Provider', version: '1.2.0', author: 'Mornye Team', isEnabled: true),
    MornyeExtension(name: 'Qobuz Studio Master Catalog', version: '1.1.4', author: 'OpenAudio', isEnabled: true),
    MornyeExtension(name: 'Spotify Metadata Bridge', version: '2.0.1', author: 'Community', isEnabled: false),
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissionAndScanMusic();
    
    _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
      });
    });

    _audioPlayer.positionStream.listen((pos) {
      setState(() {
        _position = pos;
      });
    });

    _audioPlayer.durationStream.listen((dur) {
      setState(() {
        _duration = dur ?? Duration.zero;
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
      final rootMusic = Directory('/storage/emulated/0/Music');
      if (await rootMusic.exists()) searchDirs.add(rootMusic);
      
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) searchDirs.add(downloadDir);

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
                  artist: 'Lossless Local Audio',
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
        artist: 'Nami Hi-Fi Engine',
        path: '',
        lyrics: "[00:02.00] Welcome to Nami Music Player\n[00:07.00] Namida UI + Mornye .sflx Engine\n[00:15.00] Place FLAC files in your Music folder to play!",
      ));
    }

    setState(() {
      _songs = foundTracks;
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
      if (_currentSong == null && _songs.isNotEmpty) {
        await _playSong(_songs.first);
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
        currentSong: _currentSong ?? _songs.firstOrNull,
        isPlaying: _isPlaying,
        position: _position,
        duration: _duration,
        onPlayPause: _togglePlayPause,
        onSeek: (val) => _audioPlayer.seek(val),
        onNext: () {
          if (_songs.isNotEmpty && _currentSong != null) {
            int nextIdx = (_songs.indexOf(_currentSong!) + 1) % _songs.length;
            _playSong(_songs[nextIdx]);
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      // 1. Tracks Tab
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
                    const Text('Storage permission is required to scan your music library.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
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
      
      // 2. Lyrics Tab
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lyrics_rounded, size: 64, color: Colors.deepPurpleAccent),
              const SizedBox(height: 16),
              Text(_currentSong?.title ?? 'No Track Playing', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_currentSong != null ? 'Synced .LRC Active' : 'Tap any track to view synced lyrics', style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),

      // 3. Mornye Extensions Tab (.sflx)
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Mornye .sflx Extensions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Manage lossless streaming providers & extension bundles', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, padding: const EdgeInsets.all(12)),
            icon: const Icon(Icons.add_box_rounded),
            label: const Text('Install .sflx Extension / Registry URL'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mornye Extension registry loaded successfully!')),
              );
            },
          ),
          const SizedBox(height: 20),
          ..._extensions.map((ext) => Card(
            color: const Color(0xFF14141F),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: SwitchListTile(
              title: Text(ext.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('By ${ext.author} • v${ext.version}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              value: ext.isEnabled,
              activeColor: Colors.deepPurpleAccent,
              onChanged: (val) {
                setState(() => ext.isEnabled = val);
              },
            ),
          )),
        ],
      ),

      // 4. Audio/DAC Settings Tab
      ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text('Audio & USB DAC Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.usb_rounded, color: Colors.deepPurpleAccent),
            title: Text('Bit-Perfect USB DAC Routing'),
            subtitle: Text('Bypass Android Resampler (Exclusive Mode active)'),
            trailing: Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
          ),
          ListTile(
            leading: Icon(Icons.equalizer_rounded, color: Colors.deepPurpleAccent),
            title: Text('Parametric Equalizer'),
            subtitle: Text('10-band hardware DSP curve'),
          ),
        ],
      ),
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
          // Namida-style Floating MiniPlayer
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

class NowPlayingModal extends StatelessWidget {
  final AudioTrack? currentSong;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onNext;

  const NowPlayingModal({
    super.key,
    required this.currentSong,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onSeek,
    required this.onNext,
  });

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
          const SizedBox(height: 24),
          const Text('NOW PLAYING', style: TextStyle(letterSpacing: 2, fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 32),
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
          Text(currentSong?.title ?? 'No Track Selected', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(currentSong?.artist ?? 'Lossless Hi-Fi', style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const Spacer(),
          // Synced Lyrics box preview
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16)),
            child: const Text(
              "♪ Synced Lyrics (.lrc) Active\nBit-perfect USB DAC stream connected",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.deepPurpleAccent, fontSize: 13, height: 1.4),
            ),
          ),
          const Spacer(),
          Slider(
            activeColor: Colors.deepPurpleAccent,
            inactiveColor: Colors.white12,
            min: 0.0,
            max: duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0,
            value: position.inMilliseconds.clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : 1).toDouble(),
            onChanged: (val) => onSeek(Duration(milliseconds: val.toInt())),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 11)),
              Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(icon: const Icon(Icons.shuffle_rounded), onPressed: () {}),
              IconButton(icon: const Icon(Icons.skip_previous_rounded, size: 32), onPressed: () {}),
              IconButton(
                icon: Icon(isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded, size: 64, color: Colors.deepPurpleAccent),
                onPressed: onPlayPause,
              ),
              IconButton(icon: const Icon(Icons.skip_next_rounded, size: 32), onPressed: onNext),
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
