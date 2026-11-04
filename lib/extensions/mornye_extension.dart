import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'extension_api.dart';

class MornyeExtension extends NamiExtension {
  const MornyeExtension();

  @override
  String get id => 'mornye_sflx';

  @override
  String get name => 'Mornye (.sflx) Downloader';

  @override
  String get description =>
      'Import .sflx extension modules to search, stream, and download '
      'high-resolution FLAC/audio tracks directly into your Nami library.';

  @override
  Widget? buildHomeCard(BuildContext context, ExtensionContext extension) {
    final sourcesCount = extension.settings.sflxSources.length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ListTile(
        leading: const Icon(Icons.extension_outlined),
        title: const Text('Mornye Hub (.sflx)'),
        subtitle: Text(
          sourcesCount == 0
              ? 'Tap to import a .sflx module or download tracks'
              : '$sourcesCount active .sflx module(s) ready',
        ),
        trailing: FilledButton.tonalIcon(
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Open'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MornyeHubScreen(extContext: extension),
              ),
            );
          },
        ),
      ),
    );
  }
}

class MornyeHubScreen extends StatefulWidget {
  const MornyeHubScreen({super.key, required this.extContext});
  final ExtensionContext extContext;

  @override
  State<MornyeHubScreen> createState() => _MornyeHubScreenState();
}

class _MornyeHubScreenState extends State<MornyeHubScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _directUrlCtrl = TextEditingController();
  bool _loading = false;
  String? _status;
  List> _results = [];

  Future<void> _importSflxFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    if (picked == null || picked.files.single.path == null) return;
    final file = File(picked.files.single.path!);
    final raw = await file.readAsString();
    await widget.extContext.settings.addSflxSource(raw);
    if (mounted) {
      setState(() {
        _status = 'Imported ${p.basename(file.path)}';
      });
    }
  }

  Future<void> _runSearch() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _status = null;
      _results = [];
    });

    final collected = >[];
    for (final raw in widget.extContext.settings.sflxSources) {
      try {
        final cfg = jsonDecode(raw) as Map<String, dynamic>;
        final searchUrl = (cfg['searchUrl'] as String? ?? '')
            .replaceAll('{query}', Uri.encodeQueryComponent(query));
        if (searchUrl.isEmpty) continue;
        final resp = await http.get(Uri.parse(searchUrl));
        if (resp.statusCode == 200) {
          final decoded = jsonDecode(resp.body);
          final list = decoded is List
              ? decoded
              : (decoded['results'] as List? ?? decoded['data'] as List? ?? []);
          for (final item in list) {
            if (item is Map) {
              collected.add(Map<String, dynamic>.from(item));
            }
          }
        }
      } catch (e) {
        debugPrint('Mornye search error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _results = collected;
        if (collected.isEmpty) {
          _status = 'No results returned from loaded .sflx modules.';
        }
      });
    }
  }

  Future<void> _downloadTrack(String url, String suggestedTitle) async {
    setState(() {
      _loading = true;
      _status = 'Downloading $suggestedTitle...';
    });
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      Directory targetDir = Directory('/storage/emulated/0/Music/Nami');
      if (!await targetDir.exists()) {
        try {
          await targetDir.create(recursive: true);
        } catch (_) {
          targetDir = await getApplicationDocumentsDirectory();
        }
      }
      final safeName = suggestedTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final ext = url.toLowerCase().contains('.flac') ? '.flac' : '.mp3';
      final outFile = File(p.join(targetDir.path, '$safeName$ext'));
      await outFile.writeAsBytes(resp.bodyBytes, flush: true);
      await widget.extContext.library.scan(
        minSeconds: widget.extContext.settings.minTrackSeconds,
      );
      if (mounted) {
        setState(() {
          _status = 'Saved to ${outFile.path}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Download failed: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.extContext.settings.sflxSources;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mornye (.sflx) Extension'),
        actions: [
          IconButton(
            tooltip: 'Import .sflx file',
            icon: const Icon(Icons.file_open_outlined),
            onPressed: _importSflxFile,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Search via loaded .sflx modules',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _runSearch(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loading ? null : _runSearch,
                child: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _directUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Direct FLAC / Audio URL Download',
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loading
                    ? null
                    : () {
                        final url = _directUrlCtrl.text.trim();
                        if (url.isNotEmpty) {
                          _downloadTrack(
                            url,
                            'nami_${DateTime.now().millisecondsSinceEpoch}',
                          );
                        }
                      },
                child: const Text('Fetch'),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ],
          const SizedBox(height: 16),
          Text('Loaded .sflx Modules (${sources.length})',
              style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < sources.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.extension),
              title: Text('Module #${i + 1}'),
              subtitle: Text(
                sources[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await widget.extContext.settings.removeSflxSourceAt(i);
                  setState(() {});
                },
              ),
            ),
          const Divider(height: 24),
          for (final item in _results)
            ListTile(
              title: Text((item['title'] ?? item['name'] ?? 'Track').toString()),
              subtitle: Text((item['artist'] ?? item['quality'] ?? 'FLAC').toString()),
              trailing: IconButton(
                icon: const Icon(Icons.download),
                onPressed: () {
                  final dlUrl = (item['url'] ?? item['downloadUrl'] ?? '').toString();
                  if (dlUrl.isNotEmpty) {
                    _downloadTrack(
                      dlUrl,
                      (item['title'] ?? 'track').toString(),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
