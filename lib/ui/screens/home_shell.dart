import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/track.dart';
import '../../core/services/library_service.dart';
import '../../core/services/player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/user_data_service.dart';
import '../../extensions/extension_manager.dart';
import '../widgets/artwork_widget.dart';
import 'now_playing_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _navIndex = 0;
  TrackSort _sort = TrackSort.title;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final player = context.watch<PlayerService>();
    final userData = context.watch<UserDataService>();
    final settings = context.watch<SettingsService>();
    final extensions = context.watch<ExtensionManager>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nami'),
        actions: [
          IconButton(
            tooltip: 'Rescan Library',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                library.scan(minSeconds: settings.minTrackSeconds),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _navIndex,
              children: [
                _buildLibraryTab(context, library, player, userData, extensions),
                _buildGroupsTab(context, library.albums, player, 'Albums'),
                _buildGroupsTab(context, library.artists, player, 'Artists'),
                _buildGroupsTab(context, library.folders, player, 'Folders'),
                _buildSettingsAndExtensionsTab(
                    context, settings, extensions, userData),
              ],
            ),
          ),
          if (player.currentTrack != null) _MiniPlayer(player: player),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (idx) => setState(() => _navIndex = idx),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.library_music_outlined), label: 'Songs'),
          NavigationDestination(
              icon: Icon(Icons.album_outlined), label: 'Albums'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Artists'),
          NavigationDestination(
              icon: Icon(Icons.folder_outlined), label: 'Folders'),
          NavigationDestination(
              icon: Icon(Icons.tune_rounded), label: 'Nami & Ext'),
        ],
      ),
    );
  }

  Widget _buildLibraryTab(
    BuildContext context,
    LibraryService library,
    PlayerService player,
    UserDataService userData,
    ExtensionManager extensions,
  ) {
    if (library.scanning && library.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (library.permissionDenied) {
      return Center(
        child: FilledButton(
          onPressed: library.scan,
          child: const Text('Grant Audio Permission'),
        ),
      );
    }

    final tracks = _searchQuery.trim().isEmpty
        ? library.sortedTracks(_sort)
        : library.search(_searchQuery).tracks;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search ${library.tracks.length} tracks...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
        for (final card in extensions.homeCards(context))
          SliverToBoxAdapter(child: card),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                for (final s in TrackSort.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.name),
                      selected: _sort == s,
                      onSelected: (_) => setState(() => _sort = s),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final t = tracks[index];
            final active = player.currentTrack?.id == t.id;
            return ListTile(
              selected: active,
              leading: ArtworkWidget(trackId: t.id),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${t.artist} • ${t.album}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'fav') userData.toggleFavorite(t.id);
                  if (action == 'next') player.playNext(t);
                  if (action == 'queue') player.addToQueue(t);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'fav',
                    child: Text(userData.isFavorite(t.id)
                        ? 'Remove Favorite'
                        : 'Add Favorite'),
                  ),
                  const PopupMenuItem(value: 'next', child: Text('Play Next')),
                  const PopupMenuItem(value: 'queue', child: Text('Add to Queue')),
                ],
              ),
              onTap: () => player.playTracks(tracks, startIndex: index),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGroupsTab(
    BuildContext context,
    List<TrackGroup> groups,
    PlayerService player,
    String emptyLabel,
  ) {
    if (groups.isEmpty) {
      return Center(child: Text('No $emptyLabel found'));
    }
    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final g = groups[index];
        return ListTile(
          leading: ArtworkWidget(trackId: g.cover.id),
          title: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${g.subtitle} • ${g.tracks.length} tracks',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _GroupDetailPage(group: g),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsAndExtensionsTab(
    BuildContext context,
    SettingsService settings,
    ExtensionManager extensions,
    UserDataService userData,
  ) {
    return ListView(
      children: [
        const ListTile(
          title: Text('Visual & Audio Engine',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        SwitchListTile(
          title: const Text('Pitch-Black AMOLED Mode'),
          subtitle: const Text('True #000000 surfaces'),
          value: settings.amoledBlack,
          onChanged: settings.setAmoledBlack,
        ),
        SwitchListTile(
          title: const Text('Jellyfish / Liquid Glass Cards'),
          subtitle: const Text('Translucent neon-bordered surfaces'),
          value: settings.liquidGlass,
          onChanged: settings.setLiquidGlass,
        ),
        SwitchListTile(
          title: const Text('Dynamic Artwork Accent Color'),
          value: settings.dynamicAccent,
          onChanged: settings.setDynamicAccent,
        ),
        SwitchListTile(
          title: const Text('Direct USB DAC / Bit-Perfect Badge'),
          subtitle: const Text('Flag high-res lossless routing'),
          value: settings.bitPerfectUsbDac,
          onChanged: settings.setBitPerfectUsbDac,
        ),
        const Divider(),
        const ListTile(
          title: Text('Extensions (Mornye & Built-ins)',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final ext in extensions.all)
          SwitchListTile(
            title: Text(ext.name),
            subtitle: Text(ext.description),
            value: extensions.isEnabled(ext.id),
            onChanged: (v) => extensions.setEnabled(ext.id, v),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.upload_file_outlined),
          title: const Text('Export Nami Backup (JSON)'),
          onTap: () => Share.share(userData.exportBackupJson()),
        ),
      ],
    );
  }
}

class _GroupDetailPage extends StatelessWidget {
  const _GroupDetailPage({required this.group});
  final TrackGroup group;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(group.title),
        actions: [
          IconButton(
            tooltip: 'Shuffle All',
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: () {
              final copy = List<Track>.of(group.tracks)..shuffle();
              player.playTracks(copy);
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: group.tracks.length,
        itemBuilder: (context, i) {
          final t = group.tracks[i];
          return ListTile(
            leading: ArtworkWidget(trackId: t.id),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: const Icon(Icons.playlist_add),
              onPressed: () => player.addToQueue(t),
            ),
            onTap: () => player.playTracks(group.tracks, startIndex: i),
          );
        },
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.player});
  final PlayerService player;

  @override
  Widget build(BuildContext context) {
    final track = player.currentTrack!;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
        ),
        leading: Hero(
          tag: 'art_${track.id}',
          child: ArtworkWidget(trackId: track.id, size: 44),
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle:
            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              onPressed: player.togglePlayPause,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: player.next,
            ),
          ],
        ),
      ),
    );
  }
}
