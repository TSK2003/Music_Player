import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glow_button.dart';
import '../widgets/neon_seek_bar.dart';
import '../widgets/waveform_painter.dart';
import '../widgets/animated_background.dart'
    show AnimatedBackground;

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final currentSong = playerService.currentSong;

    if (currentSong == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: Text('No song selected')),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AnimatedBackground(
        accentColor: currentSong.artColor,
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeController,
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context, currentSong),
                const Spacer(flex: 2),
                // Album art
                _buildAlbumArt(context, currentSong),
                const Spacer(flex: 2),
                // Song info
                _buildSongInfo(context, currentSong),
                const Spacer(flex: 2),
                // Seek bar
                _buildSeekBar(playerService, currentSong),
                const Spacer(flex: 1),
                // Controls
                _buildControls(context, playerService),
                const Spacer(flex: 1),
                // Waveform
                _buildWaveform(context, playerService, currentSong),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, SongModel song) {
    final favoritesService = context.watch<FavoritesService>();
    final themeService = context.watch<ThemeService>();
    final isFavorite = favoritesService.isFavorite(song.id);
    final isDark = themeService.isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                border: Border.all(
                  color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Theme.of(context).textTheme.bodyLarge?.color,
                size: 28,
              ),
            ),
          ),
          // Title
          Column(
            children: [
              Text(
                'NOW PLAYING',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      letterSpacing: 2,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          // Action buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Download button (YouTube songs only)
              if (song.isYouTube)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _downloadCurrentSong(context, song),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                        border: Border.all(
                          color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.download_rounded,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              // Favorite button
              GestureDetector(
                onTap: () => favoritesService.toggleFavorite(song.id),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                    border: Border.all(
                      color: isFavorite
                          ? AppColors.accentPink.withValues(alpha: 0.4)
                          : (isDark ? AppColors.glassBorder : AppColors.lightGlassBorder),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavorite
                        ? AppColors.accentPink
                        : Theme.of(context).textTheme.bodyLarge?.color,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _downloadCurrentSong(BuildContext context, SongModel song) async {
    if (!song.isYouTube) return;
    final videoId = song.id.replaceFirst('yt_', '');
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloading "${song.title}"...'),
        backgroundColor: const Color(0xFFFF4444).withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final result = YouTubeResult(
        videoId: videoId,
        title: song.title,
        author: song.artist,
        duration: song.duration,
        thumbnailUrl: song.thumbnailUrl ?? '',
      );
      await YouTubeService.downloadPermanently(result);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Downloaded "${song.title}" ✓'),
            backgroundColor: Colors.green.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Download failed: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.accentPink.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Widget _buildAlbumArt(BuildContext context, SongModel song) {
    final isDark = context.watch<ThemeService>().isDark;

    return Center(
      child: StreamBuilder<bool>(
          stream: context.read<PlayerService>().playingStream,
          builder: (context, snapshot) {
            final isPlaying = snapshot.data ?? false;

            if (isPlaying && !_rotationController.isAnimating) {
              _rotationController.repeat();
            } else if (!isPlaying && _rotationController.isAnimating) {
              _rotationController.stop();
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isPlaying ? 280 : 260,
              height: isPlaying ? 280 : 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [song.artColor, song.artColorSecondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: song.artColor.withValues(alpha: isPlaying ? 0.5 : 0.3),
                    blurRadius: isPlaying ? 50 : 30,
                    spreadRadius: isPlaying ? 8 : 4,
                  ),
                  if (isDark)
                    BoxShadow(
                      color: song.artColorSecondary.withValues(alpha: 0.2),
                      blurRadius: 60,
                      spreadRadius: 2,
                      offset: const Offset(20, 20),
                    ),
                ],
              ),
                child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // YouTube thumbnail or gradient background
                    if (song.thumbnailUrl != null)
                      CachedNetworkImage(
                        imageUrl: song.thumbnailUrl!,
                        fit: BoxFit.cover,
                        width: isPlaying ? 280 : 260,
                        height: isPlaying ? 280 : 260,
                        placeholder: (context, url) => Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.1),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.music_note_rounded,
                            size: 80,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.1),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.music_note_rounded,
                            size: 80,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      )
                    else ...[
                      // Gradient background for non-YouTube
                      Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.1),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      // Music icon
                      Icon(
                        Icons.music_note_rounded,
                        size: 80,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ],
                    // Glass overlay
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // YouTube badge
                    if (song.isYouTube)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF0000).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFFF0000).withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: Color(0xFFFF4444),
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'YOUTUBE',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFFFF4444),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Local file badge
                    if (song.isLocal)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentCyan.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.accentCyan.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.folder_rounded,
                                color: AppColors.accentCyan,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'LOCAL',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.accentCyan,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
    );
  }

  Widget _buildSongInfo(BuildContext context, SongModel song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            song.title,
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            song.artist,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar(PlayerService playerService, SongModel song) {
    return StreamBuilder<PositionData>(
      stream: playerService.positionDataStream,
      builder: (context, snapshot) {
        final data = snapshot.data ??
            PositionData(Duration.zero, Duration.zero, Duration.zero);

        return NeonSeekBar(
          position: data.position,
          duration: data.duration,
          bufferedPosition: data.bufferedPosition,
          activeColor: song.artColor,
          onChangeEnd: (position) {
            playerService.seekTo(position);
          },
        );
      },
    );
  }

  Widget _buildControls(BuildContext context, PlayerService playerService) {
    final isDark = context.watch<ThemeService>().isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Shuffle
          _ShuffleButton(
            isShuffleModeEnabled: playerService.shuffleEnabled,
            onPressed: () => playerService.toggleShuffle(),
            isDark: isDark,
          ),
          // Previous
          GestureDetector(
            onTap: playerService.hasPrevious ? playerService.previous : null,
            child: Icon(
              Icons.skip_previous_rounded,
              color: playerService.hasPrevious
                  ? Theme.of(context).textTheme.bodyLarge?.color
                  : Theme.of(context).textTheme.bodySmall?.color,
              size: 42,
            ),
          ),
          // Play/Pause
          StreamBuilder<bool>(
            stream: playerService.playingStream,
            builder: (context, snapshot) {
              final isPlaying = snapshot.data ?? false;
              final song = playerService.currentSong;
              return GlowButton(
                icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: song?.artColor ?? AppColors.neonBlue,
                onPressed: playerService.togglePlayPause,
                size: 76,
              );
            },
          ),
          // Next
          GestureDetector(
            onTap: playerService.hasNext ? playerService.next : null,
            child: Icon(
              Icons.skip_next_rounded,
              color: playerService.hasNext
                  ? Theme.of(context).textTheme.bodyLarge?.color
                  : Theme.of(context).textTheme.bodySmall?.color,
              size: 42,
            ),
          ),
          // Repeat
          _RepeatButton(
            loopMode: playerService.loopMode,
            onPressed: () => playerService.cycleLoopMode(),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform(BuildContext context, PlayerService playerService, SongModel song) {

    return StreamBuilder<bool>(
      stream: playerService.playingStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        return SizedBox(
          height: 40,
          width: 200,
          child: WaveformPainter(
            color: song.artColor.withValues(alpha: isPlaying ? 0.8 : 0.3),
            isPlaying: isPlaying,
          ),
        );
      },
    );
  }
}

class _ShuffleButton extends StatelessWidget {
  final bool isShuffleModeEnabled;
  final VoidCallback onPressed;
  final bool isDark;

  const _ShuffleButton({
    required this.isShuffleModeEnabled,
    required this.onPressed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isShuffleModeEnabled
              ? AppColors.neonBlue.withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: Icon(
          Icons.shuffle_rounded,
          color: isShuffleModeEnabled 
              ? AppColors.neonBlue 
              : Theme.of(context).textTheme.bodySmall?.color,
          size: 20,
        ),
      ),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  final LoopMode loopMode;
  final VoidCallback onPressed;
  final bool isDark;

  const _RepeatButton({
    required this.loopMode,
    required this.onPressed,
    required this.isDark,
  });

  bool get isActive => loopMode != LoopMode.off;

  IconData get icon {
    switch (loopMode) {
      case LoopMode.one:
        return Icons.repeat_one_rounded;
      case LoopMode.all:
      case LoopMode.off:
        return Icons.repeat_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? AppColors.neonPurple.withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          color: isActive 
              ? AppColors.neonPurple 
              : Theme.of(context).textTheme.bodySmall?.color,
          size: 20,
        ),
      ),
    );
  }
}
