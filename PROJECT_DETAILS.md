# Antigravity Music Player - Project Details

## Overview
**Antigravity Music Player** is a premium, high-performance, cross-platform music streaming application built using Flutter. It is designed to provide an ad-free, cinematic user experience reminiscent of modern top-tier streaming services (like Spotify or Apple Music) while combining three major audio sources into one seamless application:
1. **YouTube Music Streaming & Searching**
2. **Google Drive Cloud Streaming**
3. **Local Device Audio**

## Core Features & Options

### 1. Instant YouTube Streaming (Zero Wait Time)
Instead of waiting for an entire video to download before playback, the application utilizes a **Custom Local Proxy Server** to fetch YouTube audio chunks and feed them directly into the native media engine (`media_kit`). This results in instantaneous playback of any YouTube song globally.

### 2. Batch Downloads & Caching
Users can enter **Selection Mode** on the home screen or YouTube search screen to select multiple tracks at once. Selected tracks can be:
- **Added to Queue** for immediate playlist playback.
- **Downloaded** directly to the local file system. 
  - YouTube songs are downloaded as `.m4a` audio files.
  - Drive songs are downloaded directly via HTTP streams.
  - Downloads are permanently stored in `%APPDATA%\com.aescion\music_player\yt_downloads` (on Windows).

### 3. Google Drive Integration
Users can securely stream their private collections directly from Google Drive. The app parses the Google Drive API, retrieves valid audio files (`.mp3`, `.m4a`, `.wav`), and seamlessly merges them into the library.

### 4. Cinematic Dynamic UI
The player screen features a state-of-the-art aesthetic:
- **Reactive Gradients:** The app dynamically extracts primary and secondary colors from the currently playing album art and applies them to the background with smooth animated transitions.
- **Glassmorphism:** Frosted glass UI elements blur the background gradients for a premium feel.
- **Audio Visualizer:** A custom-painted animated audio waveform that pulses and reacts when music is actively playing.
- **Mini-Player:** A persistent, universally accessible mini-player that hovers across all screens when a song is active.

### 5. Smart Rate-Limiting & Caching
To prevent YouTube from blocking the user's IP due to excessive requests:
- Search inputs are intelligently debounced (1.5 seconds) and require a minimum of 3 characters.
- Trending songs are cached locally for 5 minutes to prevent redundant API queries.
- **Exponential Backoff:** If YouTube triggers a `429 Too Many Requests` error, the app automatically pauses, creates a fresh HTTP client, and retries the connection in the background without crashing.

### 6. System Integration
- Supports Windows system-level media controls (Play/Pause/Skip via keyboard media keys).
- Background playback support using `audio_service`.

---

## Technical Architecture & Services

### Technology Stack
- **Framework:** Flutter / Dart
- **Audio Engine:** `media_kit` + `just_audio` + `just_audio_media_kit` (for low-latency, cross-platform codec support)
- **YouTube API:** `youtube_explode_dart`
- **State Management:** `Provider`

### Key Services

#### `AudioPlayerHandler` (lib/services/audio_handler.dart)
A custom background audio handler extending `BaseAudioHandler`. It acts as the bridge between the UI and the low-level `just_audio` player. It broadcasts playback states, handles system hardware media keys, and routes audio sources.

#### `YouTubeService` (lib/services/youtube_service.dart)
The powerhouse behind the YouTube integration.
- **`search()` & `fetchTrending()`**: Queries the YouTube Explode API and returns `SongModel` objects.
- **`getStreamUrl()`**: Uses a custom built-in `HttpServer` proxy that fetches YouTube audio bytes using standard Chrome browser headers, appends a `.m4a` extension, and serves it locally. This bypasses MPV's format recognition errors and YouTube's strict connection dropping.
- **`downloadPermanently()`**: Writes audio streams chunk-by-chunk to the local disk safely, avoiding Windows file-locking crashes.

#### `PlayerService` (lib/services/player_service.dart)
The central nervous system for state management.
- Manages the Playback Queue, Shuffle, and Repeat modes.
- Listens to the `AudioPlayerHandler` and updates the UI in real-time.
- Determines whether a song should be streamed from a URL, played from a proxy, or loaded from local disk.

#### `DriveService` (lib/services/drive_service.dart)
Interfaces with the Google Drive v3 REST API. Validates API keys, filters folders for valid MIME types, and returns direct download/stream URLs.

#### `ThemeService` (lib/services/theme_service.dart)
Responsible for fetching images over the network, rendering them into a byte canvas, and running a color quantization algorithm to extract the dominant dynamic colors used throughout the app's cinematic backgrounds.

---

## Summary of File Structure
- `lib/main.dart` -> App entry point and service initialization.
- `lib/models/song_model.dart` -> Universal data structure for Local, Drive, and YouTube songs.
- `lib/screens/` -> Contains all user interfaces (`home_screen`, `player_screen`, `youtube_search_screen`).
- `lib/services/` -> Core backend logic, networking, and audio piping.
- `lib/theme/` -> Global color palettes, typography, and styling tokens.
