import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song_model.dart';
import '../services/player_service.dart';
import '../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart' show AnimatedBackground;
import '../widgets/mini_player.dart';
import 'player_screen.dart';

class YouTubeSearchScreen extends StatefulWidget {
  const YouTubeSearchScreen({super.key});

  @override
  State<YouTubeSearchScreen> createState() => _YouTubeSearchScreenState();
}

class _YouTubeSearchScreenState extends State<YouTubeSearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<YouTubeResult> _results = [];
  List<YouTubeResult> _trendingResults = [];
  bool _isSearching = false;
  bool _isLoadingTrending = true;
  String? _extractingId;
  String? _error;
  Timer? _debounce;

  // Selection mode for batch download
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isBatchDownloading = false;
  int _batchTotal = 0;
  int _batchDone = 0;

  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeController.forward();
    _loadTrending();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    setState(() => _isLoadingTrending = true);
    try {
      final results = await YouTubeService.fetchTrending();
      if (mounted) {
        setState(() {
          _trendingResults = results;
          _isLoadingTrending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingTrending = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 600), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      // Check if it's a YouTube URL
      if (query.startsWith('http') && (query.contains('youtube.com') || query.contains('youtu.be'))) {
        setState(() {
          _extractingId = 'url';
        });

        final song = await YouTubeService.extractFromUrl(query);
        if (mounted) {
          final playerService = Provider.of<PlayerService>(context, listen: false);
          playerService.addSongs([song]);
          await playerService.playSong(song);
          _searchController.clear();
          setState(() {
            _isSearching = false;
            _extractingId = null;
          });
        }
        return;
      }

      final results = await YouTubeService.search(query);
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _extractingId = null;
          _error = 'Search failed: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _playYouTubeResult(YouTubeResult result) async {
    if (_extractingId != null) return; // Prevent concurrent downloads

    setState(() {
      _extractingId = result.videoId;
    });

    try {
      final song = await YouTubeService.extractAudio(result);
      if (mounted) {
        final playerService = Provider.of<PlayerService>(context, listen: false);
        playerService.addSongs([song]);
        await playerService.playSong(song);
        setState(() {
          _extractingId = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _extractingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Play failed: ${e.toString().split('\n').first}'),
            backgroundColor: AppColors.accentPink.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _downloadSong(YouTubeResult result) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading "${result.title}"...'),
        backgroundColor: const Color(0xFFFF4444).withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      await YouTubeService.downloadPermanently(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded "${result.title}" ✓'),
            backgroundColor: Colors.green.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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

  void _toggleSelection(String videoId) {
    setState(() {
      if (_selectedIds.contains(videoId)) {
        _selectedIds.remove(videoId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(videoId);
      }
    });
  }

  void _selectAll() {
    final list = _results.isNotEmpty ? _results : _trendingResults;
    setState(() {
      if (_selectedIds.length == list.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(list.map((r) => r.videoId));
      }
    });
  }

  Future<void> _batchDownload() async {
    final list = _results.isNotEmpty ? _results : _trendingResults;
    final toDownload = list.where((r) => _selectedIds.contains(r.videoId)).toList();
    if (toDownload.isEmpty) return;

    setState(() {
      _isBatchDownloading = true;
      _batchTotal = toDownload.length;
      _batchDone = 0;
    });

    int success = 0;
    int failed = 0;

    for (final result in toDownload) {
      try {
        await YouTubeService.downloadPermanently(result);
        success++;
      } catch (e) {
        failed++;
      }
      if (mounted) {
        setState(() => _batchDone++);
      }
    }

    if (mounted) {
      setState(() {
        _isBatchDownloading = false;
        _selectionMode = false;
        _selectedIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded $success songs${failed > 0 ? ' ($failed failed)' : ''} ✓'),
          backgroundColor: Colors.green.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
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
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final currentSong = playerService.currentSong;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: AnimatedBackground(
        accentColor: currentSong?.artColor ?? AppColors.accentPink,
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Top bar with back button and title
                  _buildTopBar(isDark),
                  // Search bar
                  _buildSearchBar(isDark),
                  // URL hint
                  if (_searchController.text.isEmpty && !_selectionMode)
                    _buildUrlHint(isDark),
                  // Selection toolbar
                  if (_selectionMode || _isBatchDownloading)
                    _buildSelectionToolbar(isDark),
                  // Batch download progress
                  if (_isBatchDownloading)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _batchTotal > 0 ? _batchDone / _batchTotal : 0,
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.06),
                          color: const Color(0xFFFF4444),
                          minHeight: 4,
                        ),
                      ),
                    ),
                  // Results
                  Expanded(
                    child: _buildContent(isDark, currentSong),
                  ),
                  // Bottom spacing for mini player
                  SizedBox(height: currentSong != null ? 88 : 0),
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

  Widget _buildTopBar(bool isDark) {
    return FadeTransition(
      opacity: _fadeController,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            // Back button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  border: Border.all(
                    color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // YouTube icon and title
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF0000), Color(0xFFCC0000)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFF4444), Color(0xFFFF0000)],
                  ).createShader(bounds),
                  child: Text(
                    'YouTube Music',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                  ),
                ),
                Text(
                  'Search & stream ad-free',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                        letterSpacing: 0.5,
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return FadeTransition(
      opacity: _fadeController,
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
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.6),
                border: Border.all(
                  color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                onSubmitted: (query) => _performSearch(query.trim()),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                    ),
                decoration: InputDecoration(
                  hintText: 'Search songs or paste YouTube URL...',
                  hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                      ),
                  prefixIcon: _isSearching
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.search_rounded,
                          color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                          size: 22,
                        ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() {
                              _results = [];
                              _error = null;
                            });
                          },
                          child: Icon(
                            Icons.close_rounded,
                            color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
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

  Widget _buildUrlHint(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Row(
        children: [
          Icon(
            Icons.tips_and_updates_rounded,
            size: 14,
            color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
          ),
          const SizedBox(width: 6),
          Text(
            'Tip: Paste a YouTube URL to play instantly',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar(bool isDark) {
    final list = _results.isNotEmpty ? _results : _trendingResults;
    final allSelected = _selectedIds.length == list.length && list.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFFF4444).withValues(alpha: 0.1)
            : const Color(0xFFFF4444).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF4444).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Select All / Deselect All
          GestureDetector(
            onTap: _isBatchDownloading ? null : _selectAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                  size: 18,
                  color: const Color(0xFFFF4444),
                ),
                const SizedBox(width: 4),
                Text(
                  allSelected ? 'Deselect All' : 'Select All',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFF4444),
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
          // Download button
          if (!_isBatchDownloading)
            GestureDetector(
              onTap: _selectedIds.isNotEmpty ? _batchDownload : null,
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
                    const Icon(Icons.download_rounded, size: 14, color: Colors.white),
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
          if (_isBatchDownloading)
            Text(
              '$_batchDone / $_batchTotal',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFFF4444),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          const SizedBox(width: 8),
          // Cancel
          if (!_isBatchDownloading)
            GestureDetector(
              onTap: () => setState(() {
                _selectionMode = false;
                _selectedIds.clear();
              }),
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

  Widget _buildContent(bool isDark, SongModel? currentSong) {
    if (_error != null) {
      return _buildError(isDark);
    }

    if (_results.isEmpty && !_isSearching) {
      return _buildTrendingSection(isDark, currentSong);
    }

    if (_isSearching && _results.isEmpty) {
      return _buildSearchingState(isDark);
    }

    return _buildResults(isDark, currentSong);
  }

  Widget _buildTrendingSection(bool isDark, SongModel? currentSong) {
    if (_isLoadingTrending) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: const Color(0xFFFF4444).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading trending songs...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                  ),
            ),
          ],
        ),
      );
    }

    if (_trendingResults.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      itemCount: _trendingResults.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.trending_up_rounded,
                    color: Color(0xFFFF4444),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Trending Now',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _loadTrending,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 14,
                          color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Refresh',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
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

        final result = _trendingResults[index - 1];
        final isCurrentlyPlaying = currentSong?.id == 'yt_${result.videoId}';
        final isExtracting = _extractingId == result.videoId;

        return _YouTubeResultCard(
          result: result,
          isPlaying: isCurrentlyPlaying,
          isExtracting: isExtracting,
          isSelected: _selectedIds.contains(result.videoId),
          selectionMode: _selectionMode,
          onTap: _selectionMode
              ? () => _toggleSelection(result.videoId)
              : () => _playYouTubeResult(result),
          onLongPress: () {
            setState(() => _selectionMode = true);
            _toggleSelection(result.videoId);
          },
          onDownload: () => _downloadSong(result),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: FadeTransition(
        opacity: _fadeController,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF0000).withValues(alpha: 0.15),
                    const Color(0xFFFF4444).withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFFF0000).withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.play_circle_outline_rounded,
                size: 40,
                color: const Color(0xFFFF4444).withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Search YouTube',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 18,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find any song and play it ad-free',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: const Color(0xFFFF4444).withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Searching YouTube...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.accentPink.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                setState(() => _error = null);
                _performSearch(_searchController.text.trim());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF4444), Color(0xFFFF0000)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Retry',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(bool isDark, SongModel? currentSong) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      itemCount: _results.length + 1, // +1 for the results count header
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFF4444), Color(0xFFFF0000)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_results.length} Results',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                        letterSpacing: 0.5,
                      ),
                ),
                if (_isSearching) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: isDark ? AppColors.textMuted : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        final result = _results[index - 1];
        final isCurrentlyPlaying = currentSong?.id == 'yt_${result.videoId}';
        final isExtracting = _extractingId == result.videoId;

        return _YouTubeResultCard(
          result: result,
          isPlaying: isCurrentlyPlaying,
          isExtracting: isExtracting,
          isSelected: _selectedIds.contains(result.videoId),
          selectionMode: _selectionMode,
          onTap: _selectionMode
              ? () => _toggleSelection(result.videoId)
              : () => _playYouTubeResult(result),
          onLongPress: () {
            setState(() => _selectionMode = true);
            _toggleSelection(result.videoId);
          },
          onDownload: () => _downloadSong(result),
        );
      },
    );
  }
}

/// A card widget for displaying YouTube search results
class _YouTubeResultCard extends StatelessWidget {
  final YouTubeResult result;
  final bool isPlaying;
  final bool isExtracting;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onLongPress;

  const _YouTubeResultCard({
    required this.result,
    this.isPlaying = false,
    this.isExtracting = false,
    this.isSelected = false,
    this.selectionMode = false,
    required this.onTap,
    this.onDownload,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: isExtracting ? null : onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected
              ? (isDark
                  ? const Color(0xFFFF4444).withValues(alpha: 0.12)
                  : const Color(0xFFFF4444).withValues(alpha: 0.08))
              : isPlaying
                  ? (isDark
                      ? const Color(0xFFFF0000).withValues(alpha: 0.08)
                      : const Color(0xFFFF0000).withValues(alpha: 0.05))
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.white.withValues(alpha: 0.5)),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF4444).withValues(alpha: 0.5)
                : isPlaying
                    ? const Color(0xFFFF4444).withValues(alpha: 0.3)
                    : (isDark ? AppColors.glassBorder : AppColors.lightGlassBorder),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isPlaying
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF0000).withValues(alpha: 0.1),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Selection checkbox
            if (selectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? const Color(0xFFFF4444)
                        : Colors.transparent,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF4444)
                          : (isDark ? AppColors.textMuted : AppColors.lightTextMuted),
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
            // Thumbnail
            _buildThumbnail(isDark),
            const SizedBox(width: 12),
            // Song info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: isPlaying
                              ? const Color(0xFFFF4444)
                              : (isDark ? AppColors.textPrimary : AppColors.lightTextPrimary),
                          fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 14,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          result.author,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: isPlaying
                                    ? const Color(0xFFFF4444).withValues(alpha: 0.7)
                                    : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary),
                                fontSize: 12,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (result.durationText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            result.durationText,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Download button
            if (onDownload != null && !isExtracting)
              GestureDetector(
                onTap: onDownload,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                  ),
                  child: Icon(
                    Icons.download_rounded,
                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                    size: 16,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            // Play button or loading indicator
            _buildAction(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: result.thumbnailUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFFF4444).withValues(alpha: 0.3),
                      const Color(0xFFFF0000).withValues(alpha: 0.2),
                    ],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.music_note_rounded,
                    color: Colors.white54,
                    size: 24,
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFFF4444).withValues(alpha: 0.3),
                      const Color(0xFFFF0000).withValues(alpha: 0.2),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: Colors.white54,
                  size: 24,
                ),
              ),
            ),
            // YouTube indicator overlay
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                width: 16,
                height: 16,
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
                  size: 10,
                ),
              ),
            ),
            // Playing overlay
            if (isPlaying)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: const Center(
                  child: Icon(
                    Icons.equalizer_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(bool isDark) {
    if (isExtracting) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFF0000).withValues(alpha: 0.1),
        ),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFF4444),
          ),
        ),
      );
    }

    if (isPlaying) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFF0000).withValues(alpha: 0.15),
        ),
        child: const Icon(
          Icons.equalizer_rounded,
          color: Color(0xFFFF4444),
          size: 22,
        ),
      );
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        border: Border.all(
          color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
          width: 1,
        ),
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
        size: 22,
      ),
    );
  }
}
