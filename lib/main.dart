import 'package:flutter/material.dart';

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

class NamiHomeShell extends StatefulWidget {
  const NamiHomeShell({super.key});

  @override
  State<NamiHomeShell> createState() => _NamiHomeShellState();
}

class _NamiHomeShellState extends State<NamiHomeShell> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    Center(child: Text('Library & Local FLAC Tracks', style: TextStyle(fontSize: 18))),
    Center(child: Text('Synced Lyrics (.lrc)', style: TextStyle(fontSize: 18))),
    Center(child: Text('Mornye (.sflx) Extensions & Downloader', style: TextStyle(fontSize: 18))),
    Center(child: Text('USB DAC & Audio Output Settings', style: TextStyle(fontSize: 18))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'NAMI',
          style: TextStyle( fontWeight: FontWeight.w800, letterSpacing: 2.0),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search_rounded), onPressed: () {}),
          IconButton(icon: const Icon(Icons.equalizer_rounded), onPressed: () {}),
        ],
      ),
      body: Stack(
        children: [
          _pages[_selectedIndex],
          // Namida-style Floating MiniPlayer Placeholder
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
              child: const Row(
                children: [
                  Icon(Icons.album_rounded, size: 38, color: Colors.deepPurpleAccent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No Track Playing', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('24-bit / 96kHz • Bit-Perfect Ready', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Icon(Icons.play_arrow_rounded, size: 30),
                  SizedBox(width: 8),
                  Icon(Icons.skip_next_rounded, size: 26),
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
