import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/drive_service.dart';
import '../services/favorites_service.dart';
import '../services/local_file_service.dart';
import '../services/player_service.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart' show AnimatedBackground;
import '../widgets/glass_card.dart';
import '../widgets/mini_player.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/song_card.dart';
import 'player_screen.dart';
import 'profile_screen.dart';
import 'youtube_search_screen.dart';

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

  // Tab state: 0 = All, 1 = Favorites, 2 = YouTube, 3 = Local
  int _activeTab = 0;

  // Selection mode
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

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
        final playerService = Provider.of<PlayerService>(
          context,
          listen: false,
        );
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
      final playerService = Provider.of<PlayerService>(context, listen: false);
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
      final playerService = Provider.of<PlayerService>(context, listen: false);
      playerService.addSongs(songs);
      setState(() {
        _activeTab = 0;
      });
    }
  }

  void _toggleSelection(String songId) {
    setState(() {
      if (_selectedIds.contains(songId)) {
        _selectedIds.remove(songId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(songId);
      }
    });
  }

  void _selectAll(List<SongModel> songs) {
    setState(() {
      if (_selectedIds.length == songs.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(songs.map((s) => s.id));
      }
    });
  }

  void _playSelected(List<SongModel> allSongs) {
    final selected = allSongs
        .where((s) => _selectedIds.contains(s.id))
        .toList();
    if (selected.isEmpty) return;
    final playerService = Provider.of<PlayerService>(context, listen: false);
    playerService.playSong(selected.first, playlist: selected);
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _downloadSelected(List<SongModel> allSongs) async {
    final selected = allSongs
        .where((s) => _selectedIds.contains(s.id))
        .toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No songs selected'),
          backgroundColor: AppColors.accentPink.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    // Filter out songs that are already local files
    final localSongs = selected.where((s) => s.isLocal).toList();
    final downloadable = selected.where((s) => !s.isLocal).toList();

    if (downloadable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${localSongs.length} song(s) already on device'),
          backgroundColor: Colors.green.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      return;
    }

    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Downloading ${downloadable.length} song(s)...'),
        backgroundColor: const Color(0xFFFF4444).withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );

    int success = 0;
    int failed = 0;

    final dlDir = await YouTubeService.getDownloadsDir();

    for (final song in downloadable) {
      try {
        if (song.isYouTube) {
          // YouTube songs: use YouTubeService
          final videoId = song.id.replaceFirst('yt_', '');
          final result = YouTubeResult(
            videoId: videoId,
            title: song.title,
            author: song.artist,
            duration: song.duration,
            thumbnailUrl: song.thumbnailUrl ?? '',
          );
          await YouTubeService.downloadPermanently(result);
        } else {
          // Drive/cloud songs: download via HTTP
          final uri = song.streamUrl;
          if (uri.startsWith('http')) {
            final response = await http.get(Uri.parse(uri));
            if (response.statusCode == 200) {
              final safeName = song.title.replaceAll(
                RegExp(r'[<>:"/\\|?*]'),
                '_',
              );
              final filePath =
                  '${dlDir.path}${Platform.pathSeparator}$safeName.m4a';
              await File(filePath).writeAsBytes(response.bodyBytes);
              debugPrint('[HomeScreen] Downloaded Drive song: $filePath');
            } else {
              throw Exception('HTTP ${response.statusCode}');
            }
          }
        }
        success++;
      } catch (e) {
        failed++;
        debugPrint('[HomeScreen] Download failed for ${song.title}: $e');
      }
    }

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? 'Downloaded $success song(s) ✓'
                : 'Downloaded $success, failed $failed',
          ),
          backgroundColor: failed == 0
              ? Colors.green.withValues(alpha: 0.9)
              : AppColors.accentPink.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  List<SongModel> get _filteredSongs {
    final playerService = Provider.of<PlayerService>(context, listen: false);
    final favoritesService = Provider.of<FavoritesService>(
      context,
      listen: false,
    );

    List<SongModel> base;
    switch (_activeTab) {
      case 1: // Favorites
        base = playerService.songs
            .where((s) => favoritesService.isFavorite(s.id))
            .toList();
        break;
      case 2: // YouTube
        base = playerService.songs.where((s) => s.isYouTube).toList();
        break;
      case 3: // Local
        base = playerService.songs.where((s) => s.isLocal).toList();
        break;
      default: // All
        base = playerService.songs;
    }

    if (_searchQuery.isEmpty) return base;
    final query = _searchQuery.toLowerCase();
    return base
        .where(
          (song) =>
              song.title.toLowerCase().contains(query) ||
              song.artist.toLowerCase().contains(query) ||
              (song.category?.toLowerCase().contains(query) ?? false),
        )
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
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: FadeTransition(opacity: animation, child: child),
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
                  SliverToBoxAdapter(child: _buildTitle()),
                  // Search bar
                  SliverToBoxAdapter(child: _buildSearchBar()),
                  // Tab bar
                  if (!_selectionMode)
                    SliverToBoxAdapter(child: _buildTabBar()),
                  // Selection toolbar
                  if (_selectionMode)
                    SliverToBoxAdapter(
                      child: _buildSelectionToolbar(filteredSongs),
                    ),
                  // Categories
                  if (!_selectionMode)
                    SliverToBoxAdapter(child: _buildCategories()),
                  // Songs count
                  if (!_isLoading)
                    SliverToBoxAdapter(
                      child: _buildSongsCount(filteredSongs.length),
                    ),
                  // Song list or loading
                  if (_isLoading)
                    const SliverToBoxAdapter(child: ShimmerLoading())
                  else if (_error != null)
                    SliverToBoxAdapter(child: _buildError())
                  else if (filteredSongs.isEmpty)
                    SliverToBoxAdapter(child: _buildEmpty())
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = filteredSongs[index];
                        final isPlaying = currentSong?.id == song.id;
                        final isSelected = _selectedIds.contains(song.id);

                        return SongCard(
                          song: song,
                          isPlaying: isPlaying,
                          isSelected: isSelected,
                          selectionMode: _selectionMode,
                          index: index,
                          onTap: _selectionMode
                              ? () => _toggleSelection(song.id)
                              : () {
                                  playerService.playSong(
                                    song,
                                    playlist: filteredSongs,
                                  );
                                },
                          onLongPress: () {
                            if (!_selectionMode) {
                              setState(() => _selectionMode = true);
                            }
                            _toggleSelection(song.id);
                          },
                        );
                      }, childCount: filteredSongs.length),
                    ),
                  // Bottom padding for mini player
                  SliverToBoxAdapter(
                    child: SizedBox(height: currentSong != null ? 100 : 20),
                  ),
                ],
              ),
              // Mini player
              if (currentSong != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MiniPlayer(onTap: _openPlayer),
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
        position: Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
            .animate(
              CurvedAnimation(
                parent: _titleController,
                curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
              ),
            ),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [AppColors.neonBlue, AppColors.neonPurple],
                      ).createShader(bounds),
                      child: Text(
                        'Music Player',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(color: Colors.white, fontSize: 22),
                      ),
                    ),
                    Text(
                      'Antigravity Experience',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        letterSpacing: 1.5,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // YouTube search button
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 400),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 300,
                      ),
                      pageBuilder: (context, animation, secondaryAnimation) {
                        return const YouTubeSearchScreen();
                      },
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(0, 0.1),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
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
                        const Color(0xFFFF0000).withValues(alpha: 0.2),
                        const Color(0xFFFF4444).withValues(alpha: 0.15),
                      ],
                    ),
                    border: Border.all(
                      color: const Color(0xFFFF0000).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_circle_rounded,
                    color: Color(0xFFFF4444),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                      reverseTransitionDuration: const Duration(
                        milliseconds: 300,
                      ),
                      pageBuilder: (context, animation, secondaryAnimation) {
                        return const ProfileScreen();
                      },
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(1, 0),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
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
                            color:
                                Theme.of(context).brightness == Brightness.dark
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
      _TabItem(label: 'YouTube', icon: Icons.play_circle_rounded),
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
                      size: 14,
                      color: isActive
                          ? AppColors.neonBlue
                          : (Theme.of(context).brightness == Brightness.dark
                                ? AppColors.textMuted
                                : AppColors.lightTextSecondary),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
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
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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
    final uniqueCategories =
        playerService.songs
            .map((s) => s.category)
            .whereType<String>() // Filters out nulls
            .where(
              (c) => c != 'Demo Tracks' && c != 'Local',
            ) // Optional: ignore specific tags
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
            final isActive = category == 'All'
                ? _searchQuery.isEmpty
                : _searchQuery.toLowerCase() == category.toLowerCase();
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
            _searchQuery.isEmpty ? '$count Songs' : '$count Results',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.textMuted
                  : AppColors.lightTextSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (!_selectionMode && count > 0)
            GestureDetector(
              onTap: () {
                setState(() => _selectionMode = true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.glassBorder
                        : AppColors.lightGlassBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      size: 14,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.textMuted
                          : AppColors.lightTextMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Select',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.textMuted
                            : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar(List<SongModel> songs) {
    final allSelected = _selectedIds.length == songs.length && songs.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.neonBlue.withValues(alpha: 0.1)
            : AppColors.neonBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.neonBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Select All / Deselect All
          GestureDetector(
            onTap: () => _selectAll(songs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                  size: 18,
                  color: AppColors.neonBlue,
                ),
                const SizedBox(width: 4),
                Text(
                  allSelected ? 'Deselect' : 'Select All',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.neonBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Count
          Text(
            '${_selectedIds.length} selected',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          // Download selected button
          GestureDetector(
            onTap: _selectedIds.isNotEmpty
                ? () => _downloadSelected(songs)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _selectedIds.isNotEmpty
                    ? const Color(0xFFFF4444)
                    : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.download_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Download',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Play selected button
          GestureDetector(
            onTap: _selectedIds.isNotEmpty ? () => _playSelected(songs) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _selectedIds.isNotEmpty
                    ? AppColors.neonBlue
                    : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_arrow_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Play',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Close selection
          GestureDetector(
            onTap: _exitSelectionMode,
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
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
    final isLocalTab = _activeTab == 3;
    final isFavTab = _activeTab == 1;
    final isYouTubeTab = _activeTab == 2;

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
                  : isYouTubeTab
                  ? Icons.play_circle_outline_rounded
                  : isLocalTab
                  ? Icons.folder_open_rounded
                  : Icons.music_off_rounded,
              color: _searchQuery.isNotEmpty
                  ? AppColors.textMuted
                  : isFavTab
                  ? AppColors.accentPink
                  : isYouTubeTab
                  ? const Color(0xFFFF4444)
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
                  : isYouTubeTab
                  ? 'No YouTube songs yet'
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
                  : isYouTubeTab
                  ? 'Search YouTube to play songs ad-free'
                  : isLocalTab
                  ? 'Tap + to browse your music files'
                  : 'Add some music to your Drive folder',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (isYouTubeTab && _searchQuery.isEmpty) ...[
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 400),
                      reverseTransitionDuration: const Duration(
                        milliseconds: 300,
                      ),
                      pageBuilder: (context, animation, secondaryAnimation) {
                        return const YouTubeSearchScreen();
                      },
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position:
                                    Tween<Offset>(
                                      begin: const Offset(0, 0.1),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    ),
                                child: child,
                              ),
                            );
                          },
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF4444), Color(0xFFFF0000)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF0000).withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Search YouTube',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
                      const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
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

  const _AddMusicButton({required this.onAddFiles, required this.onAddFolder});

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: AppColors.surface.withValues(alpha: 0.95),
      elevation: 12,
      shadowColor: AppColors.neonBlue.withValues(alpha: 0.2),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'files',
          child: Row(
            children: [
              Icon(
                Icons.audio_file_rounded,
                color: AppColors.neonBlue,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Add Music Files',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'folder',
          child: Row(
            children: [
              Icon(Icons.folder_rounded, color: AppColors.accentCyan, size: 20),
              const SizedBox(width: 12),
              Text(
                'Add Music Folder',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
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
