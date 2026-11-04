import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import 'core/services/library_service.dart';
import 'core/services/player_service.dart';
import 'core/services/settings_service.dart';
import 'extensions/extension_manager.dart';

class NamidaLayout extends StatefulWidget {
  const NamidaLayout({super.key});

  @override
  State<NamidaLayout> createState() => _NamidaLayoutState();
}

class _NamidaLayoutState extends State<NamidaLayout> {
  int _selectedTab = 0;
  String _searchQuery = '';
  String _sortBy = 'title';
  final TextEditingController _searchController = TextEditingController();

  String _getNamidaGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    if (hour < 21) return 'Good Evening';
    return 'Late Night Vibes';
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final player = context.watch<PlayerService>();
    final settings = context.watch<SettingsService>();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isAmoled = settings.amoledBlack;

    final bgColor = isAmoled ? Colors.black : const Color(0xFF0A0C10);

    return Theme(
      data: theme.copyWith(
        textTheme: GoogleFonts.outfitTextTheme(theme.textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            // Ambient Jellyfish top glow (Namida signature header aura)
            Positioned(
              top: -90,
              right: -60,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withAlpha(55),
                      accent.withAlpha(15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Main Namida Sliver Scroll View
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildNamidaHeader(context, library, accent, bgColor),
                if (_selectedTab == 0) ..._buildSongsSlivers(context, library, player, accent),
                if (_selectedTab == 1) ..._buildAlbumsSlivers(context, library, player, accent),
                if (_selectedTab == 2) ..._buildArtistsSlivers(context, library, player, accent),
                if (_selectedTab == 3) ..._buildFoldersSlivers(context, library, player, accent),
                if (_selectedTab == 4) ..._buildSettingsSlivers(context, settings, accent),
                const SliverToBoxAdapter(child: SizedBox(height: 170)),
              ],
            ),

            // Namida Floating Blur Mini-Player + Bottom Pill Nav
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNamidaMiniPlayer(context, player, accent),
                  const SizedBox(height: 10),
                  _buildNamidaBottomNav(accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNamidaHeader(
    BuildContext context,
    LibraryService library,
    Color accent,
    Color bgColor,
  ) {
    return SliverAppBar(
      backgroundColor: bgColor.withAlpha(210),
      surfaceTintColor: Colors.transparent,
      expandedHeight: 195.0,
      pinned: true,
      stretch: true,
      elevation: 0,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: FlexibleSpaceBar(
            stretchModes: const [StretchMode.zoomBackground, StretchMode.fadeTitle],
            titlePadding: const EdgeInsets.only(left: 20, right: 20, bottom: 72),
            title: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getNamidaGreeting(),
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    letterSpacing: -0.5,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            background: Stack(
              children: [
                Positioned(
                  right: 20,
                  top: 48,
                  child: Icon(
                    TablerIcons.wave_sine,
                    size: 96,
                    color: accent.withAlpha(22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Shuffle All',
          icon: Icon(TablerIcons.arrows_shuffle, color: accent, size: 22),
          onPressed: () {
            if (library.songs.isNotEmpty) {
              final shuffled = List.of(library.songs)..shuffle();
              context.read<PlayerService>().playSong(shuffled.first, queue: shuffled);
            }
          },
        ),
        IconButton(
          tooltip: 'Rescan Library',
          icon: const Icon(TablerIcons.refresh, color: Colors.white70, size: 22),
          onPressed: () => library.scanLibrary(),
        ),
        const SizedBox(width: 6),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(14),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withAlpha(24), width: 1),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search ${library.songs.length} hi-res tracks...',
                    hintStyle: TextStyle(color: Colors.white.withAlpha(110), fontSize: 14),
                    prefixIcon: Icon(TablerIcons.search, color: accent, size: 19),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(TablerIcons.x, color: Colors.white54, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : Icon(TablerIcons.sparkles, color: Colors.white.withAlpha(80), size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSongsSlivers(
    BuildContext context,
    LibraryService library,
    PlayerService player,
    Color accent,
  ) {
    var songs = library.songs.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.title.toLowerCase().contains(_searchQuery) ||
          (s.artist ?? '').toLowerCase().contains(_searchQuery) ||
          (s.album ?? '').toLowerCase().contains(_searchQuery);
    }).toList();

    if (_sortBy == 'title') {
      songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_sortBy == 'artist') {
      songs.sort((a, b) => (a.artist ?? '').toLowerCase().compareTo((b.artist ?? '').toLowerCase()));
    } else if (_sortBy == 'album') {
      songs.sort((a, b) => (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase()));
    } else if (_sortBy == 'duration') {
      songs.sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0));
    }

    return [
      // Namida Quick Action Pills + Mornye Glass Card
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mornye Hub Liquid Glass Banner
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accent.withAlpha(38),
                          Colors.white.withAlpha(10),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: accent.withAlpha(70), width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(35),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(TablerIcons.puzzle, color: accent, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mornye Hub (.sflx)',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Import hi-res FLAC modules & stream lossless',
                                style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent.withAlpha(45),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            setState(() => _selectedTab = 4);
                          },
                          icon: const Icon(TablerIcons.download, size: 16),
                          label: const Text('Open'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Namida Sort Chips Row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final sort in ['title', 'artist', 'album', 'duration'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(sort),
                          selected: _sortBy == sort,
                          onSelected: (_) => setState(() => _sortBy = sort),
                          selectedColor: accent.withAlpha(65),
                          backgroundColor: Colors.white.withAlpha(12),
                          labelStyle: TextStyle(
                            color: _sortBy == sort ? Colors.white : Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: _sortBy == sort ? accent : Colors.white.withAlpha(24),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // Namida Track List with Chunky Rounded Square Artwork & Codec Badges
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = songs[index];
            final isPlaying = player.currentSong?.id == song.id;
            final ext = (song.fileExtension ?? 'FLAC').toUpperCase();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => player.playSong(song, queue: songs),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isPlaying ? accent.withAlpha(32) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: isPlaying
                        ? Border.all(color: accent.withAlpha(80), width: 1)
                        : null,
                  ),
                  child: Row(
                    children: [
                      // Namida Rounded Square Artwork (12px radius instead of circle)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: QueryArtworkWidget(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            artworkBorder: BorderRadius.circular(12),
                            nullArtworkWidget: Container(
                              color: Colors.white.withAlpha(18),
                              child: Icon(TablerIcons.music, color: accent, size: 24),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: isPlaying ? accent : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                // Namida Hi-Res Codec Pill Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: accent.withAlpha(35),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    ext,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: accent,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${song.artist ?? "Unknown"} • ${song.album ?? ""}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withAlpha(155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isPlaying ? TablerIcons.Volume : TablerIcons.dots_vertical,
                          color: isPlaying ? accent : Colors.white54,
                          size: 20,
                        ),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: songs.length,
        ),
      ),
    ];
  }

  List<Widget> _buildAlbumsSlivers(
    BuildContext context,
    LibraryService library,
    PlayerService player,
    Color accent,
  ) {
    final albumMap = <String, List<SongModel>>{};
    for (final s in library.songs) {
      final key = s.album ?? 'Unknown Album';
      albumMap.putIfAbsent(key, () => []).add(s);
    }
    final albums = albumMap.entries.toList();

    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.80,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final entry = albums[index];
              final firstSong = entry.value.first;
              return GestureDetector(
                onTap: () => player.playSong(firstSong, queue: entry.value),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withAlpha(20)),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: double.infinity,
                            child: QueryArtworkWidget(
                              id: firstSong.id,
                              type: ArtworkType.AUDIO,
                              artworkBorder: BorderRadius.circular(14),
                              nullArtworkWidget: Container(
                                color: Colors.white.withAlpha(14),
                                child: Icon(TablerIcons.disc, color: accent, size: 42),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      Text(
                        '${firstSong.artist ?? "Unknown"} • ${entry.value.length} tracks',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: albums.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildArtistsSlivers(
    BuildContext context,
    LibraryService library,
    PlayerService player,
    Color accent,
  ) {
    final artistMap = <String, List<SongModel>>{};
    for (final s in library.songs) {
      final key = s.artist ?? 'Unknown Artist';
      artistMap.putIfAbsent(key, () => []).add(s);
    }
    final artists = artistMap.entries.toList();

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = artists[index];
            final firstSong = entry.value.first;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: SizedBox(
                width: 50,
                height: 50,
                child: QueryArtworkWidget(
                  id: firstSong.id,
                  type: ArtworkType.AUDIO,
                  artworkBorder: BorderRadius.circular(25),
                  nullArtworkWidget: CircleAvatar(
                    backgroundColor: accent.withAlpha(35),
                    child: Icon(TablerIcons.user_music, color: accent),
                  ),
                ),
              ),
              title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${entry.value.length} tracks',
                style: TextStyle(color: Colors.white.withAlpha(150), fontSize: 12),
              ),
              trailing: Icon(TablerIcons.player_play, color: accent, size: 20),
              onTap: () => player.playSong(firstSong, queue: entry.value),
            );
          },
          childCount: artists.length,
        ),
      ),
    ];
  }

  List<Widget> _buildFoldersSlivers(
    BuildContext context,
    LibraryService library,
    PlayerService player,
    Color accent,
  ) {
    final folderMap = <String, List<SongModel>>{};
    for (final s in library.songs) {
      final path = s.data;
      final folder = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : 'Internal';
      folderMap.putIfAbsent(folder, () => []).add(s);
    }
    final folders = folderMap.entries.toList();

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = folders[index];
            final folderName = entry.key.split('/').last;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(TablerIcons.folder_music, color: accent),
              ),
              title: Text(folderName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${entry.key} (${entry.value.length} tracks)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withAlpha(140), fontSize: 11),
              ),
              onTap: () => player.playSong(entry.value.first, queue: entry.value),
            );
          },
          childCount: folders.length,
        ),
      ),
    ];
  }

  List<Widget> _buildSettingsSlivers(
    BuildContext context,
    SettingsService settings,
    Color accent,
  ) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Namida Visual & Audio Engine',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                secondary: Icon(TablerIcons.moon_stars, color: accent),
                title: const Text('Pitch-Black AMOLED Mode'),
                subtitle: const Text('True #000000 surfaces'),
                value: settings.amoledBlack,
                onChanged: (v) => settings.setAmoledBlack(v),
              ),
              SwitchListTile(
                secondary: Icon(TablerIcons.sparkles, color: accent),
                title: const Text('Jellyfish / Liquid Glass Cards'),
                subtitle: const Text('Translucent neon-bordered surfaces'),
                value: settings.liquidGlass,
                onChanged: (v) => settings.setLiquidGlass(v),
              ),
              SwitchListTile(
                secondary: Icon(TablerIcons.palette, color: accent),
                title: const Text('Dynamic Artwork Accent Color'),
                value: settings.dynamicAccent,
                onChanged: (v) => settings.setDynamicAccent(v),
              ),
              SwitchListTile(
                secondary: Icon(TablerIcons.usb, color: accent),
                title: const Text('Direct USB DAC / Bit-Perfect Routing'),
                subtitle: const Text('Bypass Android mixer for lossless FLAC'),
                value: settings.bitPerfectDac,
                onChanged: (v) => settings.setBitPerfectDac(v),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildNamidaMiniPlayer(
    BuildContext context,
    PlayerService player,
    Color accent,
  ) {
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(18),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withAlpha(75), width: 1),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: QueryArtworkWidget(
                    id: song.id,
                    type: ArtworkType.AUDIO,
                    artworkBorder: BorderRadius.circular(14),
                    nullArtworkWidget: Container(
                      color: accent.withAlpha(40),
                      child: Icon(TablerIcons.music, color: accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist ?? 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withAlpha(165), fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  player.isPlaying ? TablerIcons.player_pause_filled : TablerIcons.player_play_filled,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () => player.togglePlayPause(),
              ),
              IconButton(
                icon: const Icon(TablerIcons.player_track_next_filled, color: Colors.white70, size: 22),
                onPressed: () => player.next(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNamidaBottomNav(Color accent) {
    final items = [
      (TablerIcons.music, 'Songs'),
      (TablerIcons.disc, 'Albums'),
      (TablerIcons.user_music, 'Artists'),
      (TablerIcons.folder, 'Folders'),
      (TablerIcons.adjustments_horizontal, 'Nami & Ext'),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(195),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withAlpha(24), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final selected = _selectedTab == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedTab = i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? accent.withAlpha(45) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        items[i].$1,
                        size: 21,
                        color: selected ? accent : Colors.white60,
                      ),
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
