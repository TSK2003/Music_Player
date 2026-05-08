import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/drive_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart' show AnimatedBackground;
import '../widgets/glass_card.dart';
import '../widgets/mini_player.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/song_card.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  double _scrollOffset = 0.0;
  bool _isLoading = true;
  String _searchQuery = '';
  String? _error;
  late AnimationController _titleController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _titleController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _titleController.forward();
    _loadSongs();
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final songs = await DriveService.fetchSongs();
      if (mounted) {
        final playerService =
            Provider.of<PlayerService>(context, listen: false);
        playerService.setSongs(songs);
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load songs: ${e.toString()}';
        });
      }
    }
  }

  List<SongModel> get _filteredSongs {
    final playerService = Provider.of<PlayerService>(context, listen: false);
    if (_searchQuery.isEmpty) return playerService.songs;
    final query = _searchQuery.toLowerCase();
    return playerService.songs
        .where((song) =>
            song.title.toLowerCase().contains(query) ||
            song.artist.toLowerCase().contains(query))
        .toList();
  }

  void _openPlayer() {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const PlayerScreen();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final currentSong = playerService.currentSong;
    final filteredSongs = _filteredSongs;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBackground(
        scrollOffset: _scrollOffset,
        accentColor: currentSong?.artColor,
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  // App title
                  SliverToBoxAdapter(
                    child: _buildTitle(),
                  ),
                  // Search bar
                  SliverToBoxAdapter(
                    child: _buildSearchBar(),
                  ),
                  // Songs count
                  if (!_isLoading)
                    SliverToBoxAdapter(
                      child: _buildSongsCount(filteredSongs.length),
                    ),
                  // Song list or loading
                  if (_isLoading)
                    const SliverToBoxAdapter(
                      child: ShimmerLoading(),
                    )
                  else if (_error != null)
                    SliverToBoxAdapter(
                      child: _buildError(),
                    )
                  else if (filteredSongs.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildEmpty(),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final song = filteredSongs[index];
                          final isPlaying = currentSong?.id == song.id;

                          return SongCard(
                            song: song,
                            isPlaying: isPlaying,
                            index: index,
                            onTap: () {
                              playerService.playSong(
                                song,
                                playlist: filteredSongs,
                              );
                            },
                          );
                        },
                        childCount: filteredSongs.length,
                      ),
                    ),
                  // Bottom padding for mini player
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: currentSong != null ? 100 : 20,
                    ),
                  ),
                ],
              ),
              // Mini player
              if (currentSong != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MiniPlayer(
                    onTap: _openPlayer,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _titleController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _titleController,
          curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
        )),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: Row(
            children: [
              // App icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.neonPurple, AppColors.neonBlue],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonPurple.withValues(alpha: 0.3),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.headphones_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [AppColors.neonBlue, AppColors.neonPurple],
                    ).createShader(bounds),
                    child: Text(
                      'Music Player',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                color: Colors.white,
                                fontSize: 22,
                              ),
                    ),
                  ),
                  Text(
                    'Antigravity Experience',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 1.5,
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _titleController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: AppColors.glassBorder,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                decoration: InputDecoration(
                  hintText: 'Search songs...',
                  hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textMuted,
                      ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.textMuted,
                    size: 22,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          child: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textMuted,
                            size: 20,
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongsCount(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.neonBlue, AppColors.neonPurple],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _searchQuery.isEmpty
                ? '$count Songs'
                : '$count Results',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: GlassCard(
        enableLiftEffect: false,
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.accentPink,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Connection Error',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Failed to load songs from Google Drive',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _loadSongs,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.neonGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Retry',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: GlassCard(
        enableLiftEffect: false,
        child: Column(
          children: [
            Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.music_off_rounded,
              color: AppColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No songs found'
                  : 'No songs available',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Add some music to your Drive folder',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
