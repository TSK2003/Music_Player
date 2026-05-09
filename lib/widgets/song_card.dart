import 'package:cached_network_image/cached_network_image.dart';
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
  final VoidCallback? onLongPress;
  final bool isPlaying;
  final bool isSelected;
  final bool selectionMode;
  final int index;

  const SongCard({
    super.key,
    required this.song,
    required this.onTap,
    this.onLongPress,
    this.isPlaying = false,
    this.isSelected = false,
    this.selectionMode = false,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final favoritesService = context.watch<FavoritesService>();
    final isFavorite = favoritesService.isFavorite(song.id);

    return GlassCard(
        onTap: onTap,
        onLongPress: onLongPress,
        glowColor: isPlaying ? AppColors.neonBlue : (isSelected ? AppColors.neonPurple : null),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Selection checkbox
            if (selectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? AppColors.neonBlue
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.neonBlue
                          : (Theme.of(context).brightness == Brightness.dark
                              ? AppColors.textMuted
                              : AppColors.lightTextMuted),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            // Album art
            Hero(
              tag: 'album_art_${song.id}',
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: song.thumbnailUrl == null
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [song.artColor, song.artColorSecondary],
                        )
                      : null,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Thumbnail or gradient fallback
                      if (song.thumbnailUrl != null)
                        CachedNetworkImage(
                          imageUrl: song.thumbnailUrl!,
                          fit: BoxFit.cover,
                          width: 52,
                          height: 52,
                          placeholder: (context, url) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [song.artColor, song.artColorSecondary],
                              ),
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              color: Colors.white.withValues(alpha: 0.7),
                              size: 24,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [song.artColor, song.artColorSecondary],
                              ),
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              color: Colors.white.withValues(alpha: 0.7),
                              size: 24,
                            ),
                          ),
                        )
                      else
                        Icon(
                          isPlaying ? Icons.equalizer_rounded : Icons.music_note_rounded,
                          color: Colors.white.withValues(alpha: 0.9),
                          size: 24,
                        ),
                      // Playing overlay for thumbnails
                      if (isPlaying && song.thumbnailUrl != null)
                        Container(
                          color: Colors.black.withValues(alpha: 0.4),
                          child: Icon(
                            Icons.equalizer_rounded,
                            color: Colors.white.withValues(alpha: 0.9),
                            size: 24,
                          ),
                        ),
                      // YouTube badge
                      if (song.isYouTube)
                        Positioned(
                          bottom: 3,
                          right: 3,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF0000).withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.black.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 8,
                            ),
                          ),
                        ),
                      // Local file indicator
                      if (song.isLocal)
                        Positioned(
                          bottom: 3,
                          right: 3,
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
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? AppColors.textPrimary
                                  : AppColors.lightTextPrimary),
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
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? AppColors.textSecondary
                                  : AppColors.lightTextSecondary),
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
