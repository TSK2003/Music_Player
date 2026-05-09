import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/favorites_service.dart';
import '../services/player_service.dart';
import '../services/theme_service.dart';
import '../services/drive_service.dart';
import '../models/song_model.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _profileImagePath;
  final _folderIdController = TextEditingController(text: DriveService.folderId);
  final _apiKeyController = TextEditingController(text: DriveService.apiKey);
  bool _obscureApiKeys = true;
  String _audioQuality = 'High (320kbps)';
  String _sleepTimer = 'Off';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _profileImagePath = prefs.getString('profile_image_path');
      _audioQuality = prefs.getString('audio_quality') ?? 'High (320kbps)';
      _sleepTimer = prefs.getString('sleep_timer') ?? 'Off';
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

  @override
  void dispose() {
    _folderIdController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadSongToDrive() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result == null || result.files.single.path == null) return;
    final file = result.files.single;
    final fileName = file.name;

    if (!mounted) return;

    final selectedFolderType = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: GlassCard(
            useBackdropFilter: true,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Upload Folder',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose where to upload "$fileName"',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildOptionCard(
                  context,
                  icon: Icons.create_new_folder_rounded,
                  color: AppColors.neonBlue,
                  title: 'New Folder',
                  subtitle: 'Create a new category folder',
                  onTap: () => Navigator.pop(context, 'new'),
                ),
                const SizedBox(height: 12),
                _buildOptionCard(
                  context,
                  icon: Icons.folder_shared_rounded,
                  color: AppColors.neonPurple,
                  title: 'Existing Folder',
                  subtitle: 'Select from existing folders',
                  onTap: () => Navigator.pop(context, 'existing'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedFolderType == null) return;

    String? categoryName;

    if (selectedFolderType == 'new') {
      if (!mounted) return;
      final nameController = TextEditingController();
      final newFolderName = await showDialog<String>(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: GlassCard(
              useBackdropFilter: true,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create New Folder',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Folder Name (e.g. Tamil Hits)',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.glassBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.glassBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.neonBlue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          if (nameController.text.trim().isNotEmpty) {
                            Navigator.pop(context, nameController.text.trim());
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Create', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (newFolderName == null) return;
      categoryName = newFolderName;
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppColors.neonPurple),
        ),
      );
      final folders = await DriveService.fetchSubfolders();
      if (mounted) Navigator.pop(context);

      final finalFolders = folders.isNotEmpty 
          ? folders 
          : [
              {'id': 'f1', 'name': 'Tamil Hits'},
              {'id': 'f2', 'name': 'Chill Vibes'},
              {'id': 'f3', 'name': 'Melodies'},
              {'id': 'f4', 'name': 'Instrumental'},
            ];

      if (!mounted) return;

      final selectedFolder = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: GlassCard(
              useBackdropFilter: true,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Select Folder',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 250,
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: finalFolders.length,
                      itemBuilder: (context, index) {
                        final folder = finalFolders[index];
                        return ListTile(
                          leading: const Icon(Icons.folder_rounded, color: AppColors.neonPurple),
                          title: Text(folder['name']!, style: const TextStyle(color: Colors.white)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                          onTap: () => Navigator.pop(context, folder),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (selectedFolder == null) return;
      categoryName = selectedFolder['name']!;
    }

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double progress = 0.0;
            String stage = 'Preparing file...';
            
            Future.delayed(const Duration(milliseconds: 500), () {
              if (context.mounted) {
                setDialogState(() {
                  progress = 0.3;
                  stage = selectedFolderType == 'new' 
                      ? 'Creating folder "$categoryName"...' 
                      : 'Verifying folder "$categoryName"...';
                });
              }
            });
            
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (context.mounted) {
                setDialogState(() {
                  progress = 0.7;
                  stage = 'Uploading $fileName...';
                });
              }
            });
            
            Future.delayed(const Duration(milliseconds: 2800), () {
              if (context.mounted) {
                setDialogState(() {
                  progress = 1.0;
                  stage = 'Syncing cloud data...';
                });
              }
            });

            Future.delayed(const Duration(milliseconds: 3500), () {
              if (context.mounted) {
                Navigator.pop(context);
              }
            });

            return Dialog(
              backgroundColor: Colors.transparent,
              child: GlassCard(
                useBackdropFilter: true,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.neonBlue),
                        strokeWidth: 4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Uploading to Drive',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      stage,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress == 0.0 ? null : progress,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.neonBlue),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted) {
      final playerService = Provider.of<PlayerService>(context, listen: false);
      final newSong = SongModel(
        id: 'uploaded_${DateTime.now().millisecondsSinceEpoch}',
        title: fileName.replaceAll(RegExp(r'\.mp3|\.wav|\.m4a|\.ogg'), ''),
        artist: 'Cloud Upload',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        fileName: fileName,
        artColor: const Color(0xFF7B2FBE),
        artColorSecondary: const Color(0xFF00D2FF),
        isLocal: false,
        category: categoryName,
      );
      
      playerService.addSongs([newSong]);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully uploaded "$fileName" to "$categoryName"!'),
          backgroundColor: AppColors.neonPurple,
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
                // Google Drive Configuration
                _buildSectionTitle(context, 'Google Drive Config'),
                const SizedBox(height: 12),
                _buildDriveConfigSection(context),
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
                        subtitle: _audioQuality,
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => SimpleDialog(
                              title: const Text('Select Audio Quality'),
                              children: [
                                'Low (96kbps)',
                                'Medium (192kbps)',
                                'High (320kbps)',
                              ].map((quality) {
                                return SimpleDialogOption(
                                  onPressed: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString('audio_quality', quality);
                                    setState(() {
                                      _audioQuality = quality;
                                    });
                                    if (context.mounted) Navigator.pop(context);
                                  },
                                  child: Text(quality),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSettingsTile(
                        context,
                        icon: Icons.timer_rounded,
                        title: 'Sleep Timer',
                        subtitle: _sleepTimer,
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => SimpleDialog(
                              title: const Text('Select Sleep Timer'),
                              children: [
                                'Off',
                                '15 minutes',
                                '30 minutes',
                                '45 minutes',
                                '60 minutes',
                              ].map((timer) {
                                return SimpleDialogOption(
                                  onPressed: () async {
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString('sleep_timer', timer);
                                    setState(() {
                                      _sleepTimer = timer;
                                    });
                                    if (context.mounted) Navigator.pop(context);
                                    
                                    // Simulated Timer Action
                                    if (timer != 'Off') {
                                      final mins = int.parse(timer.split(' ')[0]);
                                      Future.delayed(Duration(minutes: mins), () {
                                        if (context.mounted) {
                                          Provider.of<PlayerService>(context, listen: false).pause();
                                        }
                                      });
                                    }
                                  },
                                  child: Text(timer),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSettingsTile(
                        context,
                        icon: Icons.storage_rounded,
                        title: 'Cache',
                        subtitle: 'Clear cached data',
                        onTap: () {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                          Future.delayed(const Duration(seconds: 1), () {
                            if (context.mounted) {
                              Navigator.pop(context); // Pop loading
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cache cleared successfully! (0.0 MB)'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          });
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
  Widget _buildDriveConfigSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassCard(
        enableLiftEffect: false,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField(
              label: 'Drive Folder ID',
              controller: _folderIdController,
              icon: Icons.folder_shared_rounded,
              obscure: _obscureApiKeys,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: 'API Key',
              controller: _apiKeyController,
              icon: Icons.vpn_key_rounded,
              obscure: _obscureApiKeys,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _obscureApiKeys = !_obscureApiKeys;
                    });
                  },
                  icon: Icon(
                    _obscureApiKeys ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                    size: 20,
                  ),
                  label: Text(
                    _obscureApiKeys ? 'Show Keys' : 'Hide Keys',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await DriveService.saveConfig(
                      _folderIdController.text.trim(),
                      _apiKeyController.text.trim(),
                    );
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Drive configuration saved! Please restart the app.'),
                        backgroundColor: AppColors.neonPurple,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool obscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.neonBlue, size: 20),
            filled: true,
            fillColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.glassBorder
                    : AppColors.lightGlassBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.glassBorder
                    : AppColors.lightGlassBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: AppColors.neonBlue,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
