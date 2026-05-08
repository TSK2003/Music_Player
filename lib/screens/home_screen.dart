import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/drive_service.dart';
import '../services/favorites_service.dart';
import '../services/local_file_service.dart';
import '../services/player_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart' show AnimatedBackground;
import '../widgets/glass_card.dart';
import '../widgets/mini_player.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/song_card.dart';
import 'player_screen.dart';
import 'profile_screen.dart';

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

  // Tab state: 0 = All, 1 = Favorites, 2 = Local
  int _activeTab = 0;

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
    // Only update if significantly changed to avoid excessive rebuilds
    final newOffset = _scrollController.offset;
    if ((newOffset - _scrollOffset).abs() > 20) {
      setState(() {
        _scrollOffset = newOffset;
      });
    }
  }

  Future<void> _loadSongs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load from both Drive and local files in parallel
      final results = await Future.wait([
        DriveService.fetchSongs(),
        LocalFileService.loadSavedFiles(),
      ]);

      if (mounted) {
        final playerService =
            Provider.of<PlayerService>(context, listen: false);
        final allSongs = [...results[0], ...results[1]];
        playerService.setSongs(allSongs);
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

  /// Pick local files and add them
  Future<void> _addLocalFiles() async {
    final songs = await LocalFileService.pickFiles();
    if (songs.isNotEmpty && mounted) {
      final playerService =
          Provider.of<PlayerService>(context, listen: false);
      playerService.addSongs(songs);
      setState(() {
        _activeTab = 0; // Switch to "All" to show the new songs
      });
    }
  }

  /// Pick a folder of audio files
  Future<void> _addLocalFolder() async {
    final songs = await LocalFileService.pickFolder();
    if (songs.isNotEmpty && mounted) {
      final playerService =
          Provider.of<PlayerService>(context, listen: false);
      playerService.addSongs(songs);
      setState(() {
        _activeTab = 0;
      });
    }
  }

  List<SongModel> get _filteredSongs {
    final playerService = Provider.of<PlayerService>(context, listen: false);
    final favoritesService = Provider.of<FavoritesService>(context, listen: false);
    
    List<SongModel> base;
    switch (_activeTab) {
      case 1: // Favorites
        base = playerService.songs
            .where((s) => favoritesService.isFavorite(s.id))
            .toList();
        break;
      case 2: // Local
        base = playerService.songs.where((s) => s.isLocal).toList();
        break;
      default: // All
        base = playerService.songs;
    }

    if (_searchQuery.isEmpty) return base;
    final query = _searchQuery.toLowerCase();
    return base
        .where((song) =>
            song.title.toLowerCase().contains(query) ||
            song.artist.toLowerCase().contains(query) ||
            (song.category?.toLowerCase() == query))
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
    // Watch favorites to rebuild when they change
    context.watch<FavoritesService>();
    final filteredSongs = _filteredSongs;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  // Tab bar
                  SliverToBoxAdapter(
                    child: _buildTabBar(),
                  ),
                  // Categories
                  SliverToBoxAdapter(
                    child: _buildCategories(),
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
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.neonPurple.withValues(alpha: 0.3),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/ic_launcher.png',
                    fit: BoxFit.cover,
                  ),
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
              const Spacer(),
              // Add music button
              _AddMusicButton(
                onAddFiles: _addLocalFiles,
                onAddFolder: _addLocalFolder,
              ),
              const SizedBox(width: 10),
              // Profile button
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 400),
                      reverseTransitionDuration: const Duration(milliseconds: 300),
                      pageBuilder: (context, animation, secondaryAnimation) {
                        return const ProfileScreen();
                      },
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            )),
                            child: child,
                          ),
                        );
                      },
                    ),
                  );
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.neonPurple.withValues(alpha: 0.3),
                        AppColors.neonBlue.withValues(alpha: 0.3),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.neonPurple.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    size: 20,
                  ),
                ),
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
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.6),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.glassBorder
                      : AppColors.lightGlassBorder,
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
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.textPrimary
                          : AppColors.lightTextPrimary,
                    ),
                decoration: InputDecoration(
                  hintText: 'Search songs...',
                  hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.textMuted
                            : AppColors.lightTextMuted,
                      ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.textMuted
                        : AppColors.lightTextSecondary,
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
                          child: Icon(
                            Icons.close_rounded,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.textMuted
                                : AppColors.lightTextSecondary,
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

  Widget _buildTabBar() {
    final tabs = [
      _TabItem(label: 'All', icon: Icons.library_music_rounded),
      _TabItem(label: 'Favorites', icon: Icons.favorite_rounded),
      _TabItem(label: 'Local', icon: Icons.folder_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isActive = _activeTab == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isActive
                      ? AppColors.neonBlue.withValues(alpha: 0.15)
                      : (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03)),
                  border: Border.all(
                    color: isActive
                        ? AppColors.neonBlue.withValues(alpha: 0.4)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? AppColors.glassBorder
                            : AppColors.lightGlassBorder),
                    width: 1,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.neonBlue.withValues(alpha: 0.15),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tabs[index].icon,
                      size: 16,
                      color: isActive
                          ? AppColors.neonBlue
                          : (Theme.of(context).brightness == Brightness.dark
                              ? AppColors.textMuted
                              : AppColors.lightTextSecondary),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tabs[index].label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isActive
                                ? AppColors.neonBlue
                                : (Theme.of(context).brightness == Brightness.dark
                                    ? AppColors.textMuted
                                    : AppColors.lightTextSecondary),
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCategories() {
    final playerService = Provider.of<PlayerService>(context);
    
    // Extract unique categories from loaded songs
    final uniqueCategories = playerService.songs
        .map((s) => s.category)
        .whereType<String>() // Filters out nulls
        .where((c) => c != 'Demo Tracks' && c != 'Local') // Optional: ignore specific tags
        .toSet()
        .toList()
      ..sort();

    if (uniqueCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    final categories = ['All', ...uniqueCategories];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 36,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final isActive = category == 'All' ? _searchQuery.isEmpty : _searchQuery.toLowerCase() == category.toLowerCase();
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (category == 'All') {
                    _searchQuery = '';
                    _searchController.clear();
                  } else {
                    _searchQuery = category;
                    _searchController.text = category;
                  }
                });
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: isActive 
                      ? AppColors.neonPurple.withValues(alpha: 0.2) 
                      : (Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.05) 
                          : Colors.black.withValues(alpha: 0.03)),
                  border: Border.all(
                    color: isActive 
                        ? AppColors.neonPurple 
                        : (Theme.of(context).brightness == Brightness.dark 
                            ? AppColors.glassBorder 
                            : AppColors.lightGlassBorder),
                  ),
                ),
                child: Center(
                  child: Text(
                    category,
                    style: TextStyle(
                      color: isActive 
                          ? AppColors.neonPurple 
                          : Theme.of(context).textTheme.bodyMedium?.color,
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          },
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
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textMuted
                      : AppColors.lightTextSecondary,
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
    final isLocalTab = _activeTab == 2;
    final isFavTab = _activeTab == 1;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: GlassCard(
        enableLiftEffect: false,
        child: Column(
          children: [
            Icon(
              _searchQuery.isNotEmpty
                  ? Icons.search_off_rounded
                  : isFavTab
                      ? Icons.favorite_border_rounded
                      : isLocalTab
                          ? Icons.folder_open_rounded
                          : Icons.music_off_rounded,
              color: _searchQuery.isNotEmpty
                  ? AppColors.textMuted
                  : isFavTab
                      ? AppColors.accentPink
                      : isLocalTab
                          ? AppColors.accentCyan
                          : AppColors.textMuted,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No songs found'
                  : isFavTab
                      ? 'No favorites yet'
                      : isLocalTab
                          ? 'No local files'
                          : 'No songs available',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : isFavTab
                      ? 'Tap ♥ on songs to add them here'
                      : isLocalTab
                          ? 'Tap + to browse your music files'
                          : 'Add some music to your Drive folder',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (isLocalTab && _searchQuery.isEmpty) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _addLocalFiles,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.neonGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Browse Files',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  const _TabItem({required this.label, required this.icon});
}

/// Floating action button for adding local music
class _AddMusicButton extends StatelessWidget {
  final VoidCallback onAddFiles;
  final VoidCallback onAddFolder;

  const _AddMusicButton({
    required this.onAddFiles,
    required this.onAddFolder,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'files') {
          onAddFiles();
        } else if (value == 'folder') {
          onAddFolder();
        }
      },
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: AppColors.surface.withValues(alpha: 0.95),
      elevation: 12,
      shadowColor: AppColors.neonBlue.withValues(alpha: 0.2),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'files',
          child: Row(
            children: [
              Icon(Icons.audio_file_rounded, color: AppColors.neonBlue, size: 20),
              const SizedBox(width: 12),
              Text('Add Music Files',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      )),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'folder',
          child: Row(
            children: [
              Icon(Icons.folder_rounded, color: AppColors.accentCyan, size: 20),
              const SizedBox(width: 12),
              Text('Add Music Folder',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      )),
            ],
          ),
        ),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.neonBlue.withValues(alpha: 0.2),
              AppColors.neonPurple.withValues(alpha: 0.2),
            ],
          ),
          border: Border.all(
            color: AppColors.neonBlue.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: const Icon(
          Icons.add_rounded,
          color: AppColors.neonBlue,
          size: 22,
        ),
      ),
    );
  }
}
