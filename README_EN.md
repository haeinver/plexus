# Plexus

[中文](README.md) | [English](README_EN.md)

Plexus is a YouTube TV client built with Flutter and Material 3. It supports Android, Windows, Linux, macOS, iOS, and Web, with real TV HTML5 browse data for home feeds, categories, search, subscriptions, and video details.

## Disclaimer and Copyright Notice

> This section provides general project information and does not constitute legal advice.

- **Plexus is an unofficial, independent third-party client.** It is not affiliated with, endorsed by, or sponsored by YouTube, Google LLC, or any related entity. YouTube, Google, and associated trademarks, names, logos, and services belong to their respective owners.
- **The project is not commercialized.** The maintainer does not charge for the project, display advertising, accept paid sponsorship, sell user data, or directly profit from it. There are no commercial sponsors, sponsorship arrangements, or paid endorsements unless explicitly stated in future public, written project documentation.
- **The project does not host or mirror YouTube content.** Plexus does not store third-party videos, audio, subtitles, thumbnails, or uploader-owned content, and it does not operate or provide media downloading, offline caching, or playback proxy services.
- Playback works only when a user opens content. Plexus may resolve and request corresponding media addresses through public or user-authorized network interfaces. Playback, buffering, and availability are controlled by YouTube or other third-party services and their terms.
- The project does not bypass or circumvent access controls, digital rights management, age verification, geographic restrictions, or platform safeguards. Interfaces, data, or services may change and may make features unavailable.
- The application may store account state, account identifiers, search history, theme preferences, and other local user data. Sensitive account information should use secure platform storage. See the current source and granted platform permissions for exact behavior.
- Users must comply with YouTube terms, applicable copyright and privacy laws, and local laws. Users are solely responsible for accessing, sharing, saving, or playing protected content through this project.
- No content, links, interfaces, playback addresses, or features are guaranteed to remain available, lawful, accurate, or free from infringement. The project is provided "as is" and "as available," without express or implied warranties.
- **Infringement notices and takedown requests:** If you believe code, documentation, assets, or links in this repository infringe your rights, please contact the maintainer first through the public contact method, Issues, or the relevant platform channel. The maintainer does not intend to escalate disputes or generate publicity. Include the rights-holder's information, proof of authorization, the exact location of the allegedly infringing material, and the requested action. After receiving a valid, verifiable notice, the maintainer will stop related distribution and begin review immediately, then remove affected code, assets, or repository copies promptly. If the rights holder requests removal of the entire repository, the maintainer will cooperate and take the repository down immediately rather than prolong or escalate the matter.
- The maintainer cannot control third-party platforms, external links, or third-party content and is not responsible for actions taken by those services or rights holders. The maintainer reserves the right to modify, restrict, suspend, or remove any part of the project to comply with law or platform requirements.
- Users must not use this project to upload, distribute, or transmit unauthorized copyrighted material or to bypass platform protections, facilitate commercial piracy, or pursue unlawful purposes.

The project is intended for personal learning, research, and technical exchange without any profit motive. Good-faith infringement notices will receive a non-confrontational, fast, and direct response, but that does not guarantee legal exemption or eliminate risks imposed by third-party platforms.

## Features

- Home: progressive YouTube TV feed sections and pagination.
- Categories: browse All, Music, Gaming, and Live content.
- Search: keywords, suggestions, search history, and per-section continuation.
- Subscriptions: signed-in channel tabs and subscription feed browsing.
- Video details: play, pause, seek, switch quality, and enter fullscreen through `media_kit`.
- Playback sources: adaptive video and audio streams, up to 1080p, with HLS/muxed fallback.
- Item routing: separate destinations for regular videos, live events, Shorts, playlists, channels, and browse entries.
- Interface: light/dark themes and Material 3 navigation.

## Playback Notes

Plexus uses `youtube_explode_dart` and an Android SDK-less YouTube client to resolve media manifests, then `media_kit` to play the resolved direct streams.

- If authenticated manifest requests fail, the app retries anonymously.
- YouTube bot checks, region restrictions, age restrictions, or network exit restrictions may prevent playback URLs from being returned.
- Source failures show a real error and retry action instead of displaying a thumbnail as playback.
- The project does not currently implement TV PO-token, SABR decoding, or proxy playback.
- Full live-stream and Shorts playback are not part of the current implementation guarantee.

## Requirements

- Flutter 3.47 or a compatible newer stable release
- Dart 3.13.5 or a compatible SDK
- JDK 17 and a configured Android SDK for Android builds
- The corresponding Flutter desktop toolchain for Windows builds

## Installation and Running

```powershell
flutter pub get
flutter run
```

Run on a specific device:

```powershell
flutter devices
flutter run -d <device-id>
```

Common release builds:

```powershell
flutter build apk --release
flutter build windows --release
flutter build web --release
```

The Android release APK is normally written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Testing and Analysis

Run all tests:

```powershell
flutter test
```

Run playback service tests:

```powershell
flutter test test/video_playback_service_test.dart
```

Run static analysis:

```powershell
flutter analyze
```

## Project Structure

```text
lib/
  app.dart                  Root app widget and theme switching
  main.dart                 Startup and media_kit initialization
  models/                   Video, channel, and pagination models
  pages/
    home/                   Home feeds, browse destinations, and item routing
    category/               Categories, music, gaming, and live feeds
    subscription/           Account login and subscription channels
    search/                 Search, suggestions, and history
    player/                 Regular video, live event, and Shorts pages
    profile/                Account and theme settings
  services/                 YouTube data, authentication, and source resolution
  theme/                    Material theme
  widgets/                  Cards, loading, and continuation status widgets
 test/                       Widget, parser, and playback service tests
 assets/icon/                Application icons
```

## Stack

- Flutter / Dart
- Material 3
- `media_kit` and `media_kit_video`
- `youtube_explode_dart`
- `flutter_secure_storage`
- `flutter_inappwebview`
- HTTP / YouTube TV HTML5 APIs

## Development Conventions

- Preserve existing user and workspace changes.
- Do not invent playback URLs, titles, thumbnails, badges, or continuation tokens.
- Unknown renderers or missing required fields should produce explicit errors rather than silent fallback behavior.
- Keep source resolution and playback controls separate from page UI code.
- Format Dart changes and run relevant tests and analysis.

## License

Plexus source code is licensed under the [GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE). The complete license text is available in [LICENSE](LICENSE).

Under AGPL-3.0, modified versions distributed to others or made available to users over a network must provide corresponding source code to those recipients and preserve license and copyright notices. License notices must not be removed, replaced, or hidden.

AGPL-3.0 does not alter the rights of YouTube, Google, Flutter, or any other third-party provider. Libraries used by this project remain governed by their respective licenses. Review dependency licenses, trademarks, and third-party service terms before distribution.
