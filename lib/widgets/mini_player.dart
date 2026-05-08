import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';

class MiniPlayer extends StatefulWidget {
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    required this.onTap,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final currentSong = playerService.currentSong;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (currentSong == null) return const SizedBox.shrink();

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeOutCubic,
      )),
      child: GestureDetector(
        onTap: widget.onTap,
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! < -200) {
            widget.onTap();
          }
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  // Extremely clean glass background
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.7),
                  border: Border.all(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.6),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark 
                          ? Colors.black.withValues(alpha: 0.4)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Progress bar at top
                    _MiniProgressBar(playerService: playerService, isDark: isDark),
                    // Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                        child: Row(
                          children: [
                            // Album art
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    currentSong.artColor,
                                    currentSong.artColorSecondary,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: currentSong.artColor.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white70,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Song info
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentSong.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currentSong.artist,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: 12,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            // Controls
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Previous
                                GestureDetector(
                                  onTap: playerService.hasPrevious ? playerService.previous : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.skip_previous_rounded,
                                      color: playerService.hasPrevious
                                          ? Theme.of(context).textTheme.bodyMedium?.color
                                          : Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                                      size: 26,
                                    ),
                                  ),
                                ),
                                // Play/Pause
                                StreamBuilder<bool>(
                                  stream: playerService.playingStream,
                                  builder: (context, snapshot) {
                                    final isPlaying = snapshot.data ?? false;
                                    return GestureDetector(
                                      onTap: playerService.togglePlayPause,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        child: Icon(
                                          isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Theme.of(context).textTheme.bodyLarge?.color,
                                          size: 32,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                // Next
                                GestureDetector(
                                  onTap: playerService.hasNext ? playerService.next : null,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.skip_next_rounded,
                                      color: playerService.hasNext
                                          ? Theme.of(context).textTheme.bodyMedium?.color
                                          : Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                                      size: 26,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
  final PlayerService playerService;
  final bool isDark;

  const _MiniProgressBar({
    required this.playerService,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final song = playerService.currentSong;
    if (song == null) return const SizedBox.shrink();

    return StreamBuilder<PositionData>(
      stream: playerService.positionDataStream,
      builder: (context, snapshot) {
        final data = snapshot.data ??
            PositionData(Duration.zero, Duration.zero, Duration.zero);

        double progress = 0.0;
        if (data.duration.inMilliseconds > 0) {
          progress = data.position.inMilliseconds / data.duration.inMilliseconds;
        }

        return Container(
          height: 2,
          width: double.infinity,
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          alignment: Alignment.centerLeft,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      song.artColor,
                      song.artColorSecondary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: song.artColor.withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
