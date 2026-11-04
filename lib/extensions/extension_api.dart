import 'package:flutter/widgets.dart';

import '../core/models/track.dart';
import '../core/services/library_service.dart';
import '../core/services/player_service.dart';
import '../core/services/settings_service.dart';
import '../core/services/user_data_service.dart';

class ExtensionContext {
  const ExtensionContext({
    required this.library,
    required this.player,
    required this.userData,
    required this.settings,
  });

  final LibraryService library;
  final PlayerService player;
  final UserDataService userData;
  final SettingsService settings;
}

abstract class NamiExtension {
  const NamiExtension();

  String get id;
  String get name;
  String get description;

  void onEnable(ExtensionContext context) {}
  void onDisable() {}
  void onTrackChanged(Track track) {}
  void onTrackPlayed(Track track) {}

  Widget? buildHomeCard(BuildContext context, ExtensionContext extension) => null;
}
