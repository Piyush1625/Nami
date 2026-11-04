import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/services/player_service.dart';
import '../core/services/settings_service.dart';
import 'extension_api.dart';
import 'morning_mix.dart';
import 'mornye_extension.dart';

const List<NamiExtension> builtInExtensions = <NamiExtension>[
  MorningMixExtension(),
  MornyeExtension(),
];

class ExtensionManager extends ChangeNotifier {
  ExtensionManager({
    required this.context,
    List<NamiExtension> extensions = builtInExtensions,
  }) : _extensions = List.unmodifiable(extensions) {
    _settings.addListener(_syncEnabled);
    _subs.add(_player.onTrackChanged.listen((track) {
      _forEachEnabled((e) => e.onTrackChanged(track));
    }));
    _subs.add(_player.onTrackPlayed.listen((track) {
      _forEachEnabled((e) => e.onTrackPlayed(track));
    }));
    _syncEnabled();
  }

  final ExtensionContext context;
  final List<NamiExtension> _extensions;
  final Set<String> _active = <String>{};
  final List<StreamSubscription<dynamic>> _subs = [];

  SettingsService get _settings => context.settings;
  PlayerService get _player => context.player;

  List<NamiExtension> get all => _extensions;

  bool isEnabled(String id) => _settings.enabledExtensions.contains(id);

  Future<void> setEnabled(String id, bool enabled) =>
      _settings.setExtensionEnabled(id, enabled);

  List<Widget> homeCards(BuildContext buildContext) {
    final cards = <Widget>[];
    for (final extension in _extensions) {
      if (!isEnabled(extension.id)) continue;
      try {
        final card = extension.buildHomeCard(buildContext, context);
        if (card != null) cards.add(card);
      } catch (e) {
        debugPrint('Extension ${extension.id} failed to build its card: $e');
      }
    }
    return cards;
  }

  void _syncEnabled() {
    final wanted = _settings.enabledExtensions;
    var changed = false;

    for (final extension in _extensions) {
      final shouldRun = wanted.contains(extension.id);
      final isRunning = _active.contains(extension.id);
      if (shouldRun && !isRunning) {
        _active.add(extension.id);
        _guard(extension, () => extension.onEnable(context));
        changed = true;
      } else if (!shouldRun && isRunning) {
        _active.remove(extension.id);
        _guard(extension, extension.onDisable);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _forEachEnabled(void Function(NamiExtension) action) {
    for (final extension in _extensions) {
      if (_active.contains(extension.id)) {
        _guard(extension, () => action(extension));
      }
    }
  }

  void _guard(NamiExtension extension, VoidCallback action) {
    try {
      action();
    } catch (e, st) {
      debugPrint('Extension ${extension.id} threw an error: $e\n$st');
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_syncEnabled);
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }
}
