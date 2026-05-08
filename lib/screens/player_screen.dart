import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
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
                _buildTopBar(context),
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

  Widget _buildTopBar(BuildContext context) {
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
          // More button
          Container(
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
              Icons.more_vert_rounded,
              color: AppColors.textPrimary,
              size: 20,
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

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Shuffle (decorative for now)
            ControlButton(
              icon: Icons.shuffle_rounded,
              size: 42,
              onPressed: () {},
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
            // Repeat (decorative for now)
            ControlButton(
              icon: Icons.repeat_rounded,
              size: 42,
              onPressed: () {},
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
