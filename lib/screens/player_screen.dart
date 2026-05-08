import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
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
      return const Scaffold(
        body: Center(child: Text('No song selected')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBackground(
        accentColor: currentSong.artColor,
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeController,
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context, currentSong),
                const Spacer(flex: 1),
                // Album art
                _buildAlbumArt(currentSong),
                const SizedBox(height: 36),
                // Song info
                _buildSongInfo(context, currentSong),
                const SizedBox(height: 32),
                // Seek bar
                _buildSeekBar(playerService, currentSong),
                const SizedBox(height: 24),
                // Controls
                _buildControls(playerService),
                const SizedBox(height: 24),
                // Waveform
                _buildWaveform(playerService, currentSong),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, SongModel song) {
    final favoritesService = context.watch<FavoritesService>();
    final isFavorite = favoritesService.isFavorite(song.id);

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
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.glassBorder,
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textPrimary,
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
                      color: AppColors.textMuted,
                    ),
              ),
            ],
          ),
          // Favorite button
          GestureDetector(
            onTap: () => favoritesService.toggleFavorite(song.id),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: isFavorite
                      ? AppColors.accentPink.withValues(alpha: 0.4)
                      : AppColors.glassBorder,
                  width: 1,
                ),
              ),
              child: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: isFavorite
                    ? AppColors.accentPink
                    : AppColors.textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt(SongModel song) {
    return Center(
      child: Hero(
        tag: 'album_art_${song.id}',
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
                    // Gradient background
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
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.accentCyan,
                                      fontSize: 9,
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
                  color: AppColors.textSecondary,
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

  Widget _buildControls(PlayerService playerService) {
    return StreamBuilder<bool>(
      stream: playerService.playingStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;
        final shuffleOn = playerService.shuffleEnabled;
        final loopMode = playerService.loopMode;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shuffle — now functional
            _ShuffleButton(
              isActive: shuffleOn,
              onPressed: () => playerService.toggleShuffle(),
            ),
            const SizedBox(width: 20),
            // Previous
            ControlButton(
              icon: Icons.skip_previous_rounded,
              size: 52,
              onPressed: () => playerService.previous(),
            ),
            const SizedBox(width: 20),
            // Play/Pause
            GlowButton(
              icon: isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 72,
              color: playerService.currentSong?.artColor ?? AppColors.neonBlue,
              enableGlow: isPlaying,
              onPressed: () => playerService.togglePlayPause(),
            ),
            const SizedBox(width: 20),
            // Next
            ControlButton(
              icon: Icons.skip_next_rounded,
              size: 52,
              onPressed: () => playerService.next(),
            ),
            const SizedBox(width: 20),
            // Repeat — now functional
            _RepeatButton(
              loopMode: loopMode,
              onPressed: () => playerService.cycleLoopMode(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWaveform(PlayerService playerService, SongModel song) {
    return StreamBuilder<bool>(
      stream: playerService.playingStream,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: WaveformPainter(
            isPlaying: isPlaying,
            color: song.artColor,
            height: 50,
          ),
        );
      },
    );
  }
}

/// Shuffle button with active state glow
class _ShuffleButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onPressed;

  const _ShuffleButton({required this.isActive, required this.onPressed});

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
              ? AppColors.neonBlue.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: isActive
                ? AppColors.neonBlue.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.neonBlue.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.shuffle_rounded,
          color: isActive ? AppColors.neonBlue : AppColors.textPrimary,
          size: 20,
        ),
      ),
    );
  }
}

/// Repeat button with cycling state (off → all → one)
class _RepeatButton extends StatelessWidget {
  final LoopMode loopMode;
  final VoidCallback onPressed;

  const _RepeatButton({required this.loopMode, required this.onPressed});

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
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: isActive
                ? AppColors.neonPurple.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.neonPurple.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: isActive ? AppColors.neonPurple : AppColors.textPrimary,
          size: 20,
        ),
      ),
    );
  }
}
