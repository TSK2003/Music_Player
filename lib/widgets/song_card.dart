import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/favorites_service.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';
import 'glow_button.dart' show NeonAnimatedBuilder;

class SongCard extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;
  final bool isPlaying;
  final int index;

  const SongCard({
    super.key,
    required this.song,
    required this.onTap,
    this.isPlaying = false,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final favoritesService = context.watch<FavoritesService>();
    final isFavorite = favoritesService.isFavorite(song.id);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * 80)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: GlassCard(
        onTap: onTap,
        glowColor: isPlaying ? AppColors.neonBlue : null,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Album art circle
            Hero(
              tag: 'album_art_${song.id}',
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [song.artColor, song.artColorSecondary],
                  ),
                  boxShadow: isPlaying
                      ? AppColors.neonGlow(song.artColor, intensity: 0.3)
                      : [
                          BoxShadow(
                            color: song.artColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 24,
                    ),
                    // Local file indicator
                    if (song.isLocal)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.accentCyan.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            color: Colors.white,
                            size: 8,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Song info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isPlaying
                              ? AppColors.neonBlue
                              : AppColors.textPrimary,
                          fontWeight:
                              isPlaying ? FontWeight.w600 : FontWeight.w500,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isPlaying
                              ? AppColors.neonBlue.withValues(alpha: 0.7)
                              : AppColors.textSecondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Favorite button
            _FavoriteButton(
              isFavorite: isFavorite,
              onTap: () => favoritesService.toggleFavorite(song.id),
            ),
            const SizedBox(width: 8),
            // Playing indicator or play icon
            if (isPlaying)
              _PlayingIndicator()
            else
              Icon(
                Icons.play_circle_outline_rounded,
                color: AppColors.textMuted,
                size: 28,
              ),
          ],
        ),
      ),
    );
  }
}

/// Animated heart button for favorites
class _FavoriteButton extends StatefulWidget {
  final bool isFavorite;
  final VoidCallback onTap;

  const _FavoriteButton({required this.isFavorite, required this.onTap});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(_FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFavorite && !oldWidget.isFavorite) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.3).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.elasticOut,
          ),
        ),
        child: Icon(
          widget.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: widget.isFavorite
              ? AppColors.accentPink
              : AppColors.textMuted.withValues(alpha: 0.6),
          size: 22,
        ),
      ),
    );
  }
}

class _PlayingIndicator extends StatefulWidget {
  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        duration: Duration(milliseconds: 400 + (index * 150)),
        vsync: this,
      )..repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return NeonAnimatedBuilder(
          animation: _controllers[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 8 + (_controllers[index].value * 12),
              decoration: BoxDecoration(
                color: AppColors.neonBlue,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.neonBlue.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}
