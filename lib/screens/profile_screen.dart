import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _profileImagePath = prefs.getString('profile_image_path');
    });
  }

  Future<void> _pickProfileImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_image_path', path);
      setState(() {
        _profileImagePath = path;
      });
    }
  }

  Future<void> _removeProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_image_path');
    setState(() {
      _profileImagePath = null;
    });
  }

  Future<void> _uploadSongToDrive() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null && mounted) {
      // Mock upload process
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploading ${result.files.single.name} to Drive... (Requires OAuth setup)'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerService = context.watch<PlayerService>();
    final favoritesService = context.watch<FavoritesService>();
    final themeService = context.watch<ThemeService>();
    
    final totalSongs = playerService.songs.length;
    final localSongs = playerService.songs.where((s) => s.isLocal).length;
    final driveSongs = totalSongs - localSongs;
    final favCount = favoritesService.favoriteIds.length;

    final isDark = themeService.isDark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: isDark
            ? const BoxDecoration(gradient: AppColors.backgroundRadial)
            : null,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context),
                const SizedBox(height: 20),
                // Profile avatar
                _buildAvatar(context),
                const SizedBox(height: 16),
                // User name
                Text(
                  'Music Lover',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Antigravity Experience',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        letterSpacing: 1.5,
                      ),
                ),
                const SizedBox(height: 16),
                // Add / Remove buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _pickProfileImage,
                      icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                      label: const Text('Add'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.neonBlue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: _profileImagePath != null ? _removeProfileImage : null,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accentPink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Stats row
                _buildStatsRow(
                  context,
                  totalSongs: totalSongs,
                  favCount: favCount,
                  localSongs: localSongs,
                  isDark: isDark,
                ),
                const SizedBox(height: 28),
                // Music Library section
                _buildSectionTitle(context, 'Music Library'),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildLibraryTile(
                        context,
                        icon: Icons.cloud_upload_rounded,
                        iconColor: AppColors.neonPurple,
                        title: 'Upload to Drive',
                        subtitle: 'Add new songs to cloud',
                        onTap: _uploadSongToDrive,
                      ),
                      const SizedBox(height: 8),
                      _buildLibraryTile(
                        context,
                        icon: Icons.cloud_rounded,
                        iconColor: AppColors.neonBlue,
                        title: 'Drive Songs',
                        subtitle: '$driveSongs tracks from Google Drive',
                      ),
                      const SizedBox(height: 8),
                      _buildLibraryTile(
                        context,
                        icon: Icons.folder_rounded,
                        iconColor: AppColors.accentCyan,
                        title: 'Local Songs',
                        subtitle: '$localSongs tracks from device',
                      ),
                      const SizedBox(height: 8),
                      _buildLibraryTile(
                        context,
                        icon: Icons.favorite_rounded,
                        iconColor: AppColors.accentPink,
                        title: 'Favorites',
                        subtitle: '$favCount liked songs',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                // Settings section
                _buildSectionTitle(context, 'Settings'),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        context,
                        icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        title: 'Theme',
                        subtitle: isDark ? 'Dark Mode' : 'Light Mode',
                        onTap: () {
                          themeService.toggleTheme();
                        },
                        trailing: Switch(
                          value: isDark,
                          onChanged: (val) => themeService.toggleTheme(),
                          activeThumbColor: AppColors.neonBlue,
                          activeTrackColor: AppColors.neonBlue.withValues(alpha: 0.3),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSettingsTile(
                        context,
                        icon: Icons.equalizer_rounded,
                        title: 'Audio Quality',
                        subtitle: 'High (320kbps)',
                      ),
                      const SizedBox(height: 8),
                      _buildSettingsTile(
                        context,
                        icon: Icons.timer_rounded,
                        title: 'Sleep Timer',
                        subtitle: 'Off',
                      ),
                      const SizedBox(height: 8),
                      _buildSettingsTile(
                        context,
                        icon: Icons.storage_rounded,
                        title: 'Cache',
                        subtitle: 'Clear cached data',
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Cache cleared!'),
                              backgroundColor: Theme.of(context).colorScheme.surface,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                // About section
                _buildSectionTitle(context, 'About'),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        context,
                        icon: Icons.info_outline_rounded,
                        title: 'Version',
                        subtitle: '1.0.0',
                      ),
                      const SizedBox(height: 8),
                      _buildSettingsTile(
                        context,
                        icon: Icons.code_rounded,
                        title: 'Developer',
                        subtitle: 'AESCION',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
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
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.withValues(alpha: 0.08),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.2),
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
          const Spacer(),
          Text(
            'PROFILE',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  letterSpacing: 2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.neonBlue, AppColors.neonPurple],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.neonPurple.withValues(alpha: 0.4),
            blurRadius: 24,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: AppColors.neonBlue.withValues(alpha: 0.2),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50),
        child: _profileImagePath != null && File(_profileImagePath!).existsSync()
            ? Image.file(
                File(_profileImagePath!),
                fit: BoxFit.cover,
              )
            : const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 48,
              ),
      ),
    );
  }

  Widget _buildStatsRow(
    BuildContext context, {
    required int totalSongs,
    required int favCount,
    required int localSongs,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.03),
              border: Border.all(
                color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStat(context, '$totalSongs', 'Songs', AppColors.neonBlue),
                _buildDivider(isDark),
                _buildStat(context, '$favCount', 'Favorites', AppColors.accentPink),
                _buildDivider(isDark),
                _buildStat(context, '$localSongs', 'Local', AppColors.accentCyan),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String value, String label, Color color) {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [color, color.withValues(alpha: 0.7)],
          ).createShader(bounds),
          child: Text(
            value,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                letterSpacing: 0.5,
              ),
        ),
      ],
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      width: 1,
      height: 36,
      color: isDark ? AppColors.glassBorder : AppColors.lightGlassBorder,
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              gradient: AppColors.neonGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return GlassCard(
      enableLiftEffect: onTap != null,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: iconColor.withValues(alpha: 0.15),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GlassCard(
      enableLiftEffect: onTap != null,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            icon, 
            color: Theme.of(context).textTheme.bodyMedium?.color, 
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          trailing ?? Icon(
            Icons.chevron_right_rounded,
            color: Theme.of(context).textTheme.bodySmall?.color,
            size: 20,
          ),
        ],
      ),
    );
  }
}
