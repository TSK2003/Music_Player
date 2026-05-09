# Antigravity Music Player 🎵✨

A stunning, premium music player application built with Flutter, designed with an **"Antigravity Experience"** in mind.

## ✨ Features

- **Beautiful UI**: Modern glassmorphic design with subtle glows, neon gradients, and dynamic fluid animations.
- **YouTube Integration**: Search any song on YouTube and stream it ad-free directly in the app. Features trending songs, thumbnail previews, and direct URL paste support.
- **Google Drive Integration**: Stream music directly from your Google Drive by pasting your public folder's link or using the API!
- **Local Music**: Select local audio files or an entire folder to add to your library.
- **Mini Player**: Always accessible mini-player that floats elegantly across screens, with all necessary controls (Previous, Play/Pause, Next).
- **Dark & Light Mode**: Fluid transition between deep cosmic dark mode and clean pristine light mode.
- **Favorites System**: Keep your most-loved tracks one tap away.
- **Profile System**: Personalize your app by uploading your own profile avatar and reviewing your music stats.
- **Desktop Ready**: Tailor-made for Windows with proper audio backends (`just_audio_media_kit`), full responsiveness, and smooth native-like behavior.

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `^3.11.4`
- Dart SDK (bundled with Flutter)
- For Windows: Visual Studio with Desktop development with C++ workload

### Setup & Run

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd "Music Player"
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Analyze code for issues (optional):**
   ```bash
   flutter analyze
   ```

4. **Run on Windows:**
   ```bash
   flutter run -d windows
   ```

5. **Run on Android:**
   ```bash
   flutter run -d <device-id>
   ```
   To list connected devices:
   ```bash
   flutter devices
   ```

6. **Build release APK (Android):**
   ```bash
   flutter build apk --release
   ```

7. **Build release Windows executable:**
   ```bash
   flutter build windows --release
   ```

### Other Useful Commands

```bash
# Check outdated packages
flutter pub outdated

# Clean build cache
flutter clean

# Hot restart (during flutter run)
# Press 'R' in the terminal

# Update dependencies
flutter pub upgrade
```

## 🛠 Tech Stack

- **Framework**: Flutter
- **Audio Handling**: `audio_service`, `just_audio`, and `just_audio_media_kit` (for Windows/Linux support).
- **YouTube Integration**: `youtube_explode_dart` for search, metadata extraction, and ad-free audio stream URLs.
- **State Management**: `provider`
- **Image Caching**: `cached_network_image` for YouTube thumbnails.
- **File System**: `file_picker` for local file and image selection.
- **Storage**: `shared_preferences` for preserving state across app restarts.
- **Design Elements**: High-end shaders, backdrop filters, hero animations, and `flutter_shimmer` effects.

## 📁 Project Structure

```
lib/
├── main.dart                          # App entry point
├── models/
│   └── song_model.dart                # Song data model (Drive, Local, YouTube)
├── screens/
│   ├── home_screen.dart               # Main screen with tabs
│   ├── player_screen.dart             # Full-screen player
│   ├── profile_screen.dart            # Profile & settings
│   └── youtube_search_screen.dart     # YouTube search & trending
├── services/
│   ├── audio_handler.dart             # Audio playback handler
│   ├── drive_service.dart             # Google Drive API
│   ├── favorites_service.dart         # Favorites persistence
│   ├── local_file_service.dart        # Local file management
│   ├── player_service.dart            # Player state management
│   ├── theme_service.dart             # Theme persistence
│   └── youtube_service.dart           # YouTube search & audio extraction
├── theme/
│   └── app_theme.dart                 # App theme & colors
└── widgets/
    ├── animated_background.dart       # Animated gradient background
    ├── glass_card.dart                # Glassmorphism card
    ├── glow_button.dart               # Neon glow button
    ├── mini_player.dart               # Floating mini player
    ├── neon_seek_bar.dart             # Custom seek bar
    ├── shimmer_loading.dart           # Loading shimmer effect
    ├── song_card.dart                 # Song list card
    └── waveform_painter.dart          # Audio waveform visualizer
```

## ⚠️ Notes

- **YouTube streaming** uses `youtube_explode_dart` which extracts audio-only streams from YouTube. This is for **personal use only** and may violate YouTube's Terms of Service if published to app stores.
- YouTube audio stream URLs are temporary (~6 hours) — the app extracts a fresh URL each time you play a song.
- An active internet connection is required for YouTube and Google Drive features.

---
*Created by AESCION*
