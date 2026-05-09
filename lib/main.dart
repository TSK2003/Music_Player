import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';
import 'services/audio_handler.dart';
import 'services/favorites_service.dart';
import 'services/player_service.dart';
import 'services/theme_service.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';
import 'services/drive_service.dart';

late AudioPlayerHandler _audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load Drive Config from local storage
  await DriveService.loadConfig();

  // Initialize media_kit for Windows/Linux audio support
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    JustAudioMediaKit.ensureInitialized(
      windows: true,
      linux: true,
      macOS: true,
    );
  }

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Lock to portrait mode for optimal experience
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize audio service
  _audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.aescion.music_player.channel.audio',
      androidNotificationChannelName: 'Music Player',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );

  // Pre-load preferences
  final favoritesService = FavoritesService();
  await favoritesService.load();

  final themeService = ThemeService();
  await themeService.load();

  runApp(MusicPlayerApp(
    favoritesService: favoritesService,
    themeService: themeService,
  ));
}

class MusicPlayerApp extends StatelessWidget {
  final FavoritesService favoritesService;
  final ThemeService themeService;

  const MusicPlayerApp({
    super.key,
    required this.favoritesService,
    required this.themeService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final service = PlayerService(_audioHandler);
            service.startListening();
            return service;
          },
        ),
        ChangeNotifierProvider.value(value: favoritesService),
        ChangeNotifierProvider.value(value: themeService),
      ],
      child: Consumer<ThemeService>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Music Player',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.themeMode,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
