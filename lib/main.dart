import 'package:flutter/material.dart';
import 'ui/screens/home_shell.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/accent_service.dart';
import 'core/services/library_service.dart';
import 'core/services/lyrics_service.dart';
import 'core/services/player_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/user_data_service.dart';
import 'extensions/extension_api.dart';
import 'extensions/extension_manager.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.nami.channel.audio',
    androidNotificationChannelName: 'Nami Playback',
    androidNotificationOngoing: true,
  );

  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final userData = UserDataService(prefs);
  final library = LibraryService();
  final lyricsService = LyricsService();

  await library.loadCache();

  final player = PlayerService(
    library: library,
    userData: userData,
    lyricsService: lyricsService,
  );
  final accent = AccentService(player);

  final extensionManager = ExtensionManager(
    context: ExtensionContext(
      library: library,
      player: player,
      userData: userData,
      settings: settings,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: userData),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider.value(value: accent),
        ChangeNotifierProvider.value(value: extensionManager),
      ],
      child: const NamiApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await library.scan(minSeconds: settings.minTrackSeconds);
    await player.restoreSavedQueue();
    await accent.refreshForCurrent();
  });
}

class NamiApp extends StatelessWidget {
  const NamiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final accent = context.watch<AccentService>();
    final seed = (settings.dynamicAccent && accent.color != null)
        ? accent.color!
        : settings.seedColor;

    return MaterialApp(
      title: 'Nami',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(
        seed,
        Brightness.light,
        amoled: false,
        liquidGlass: settings.liquidGlass,
      ),
      darkTheme: buildTheme(
        seed,
        Brightness.dark,
        amoled: settings.amoledBlack,
        liquidGlass: settings.liquidGlass,
      ),
      home: const HomeShell(),
    );
  }
}
