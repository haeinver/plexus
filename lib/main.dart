import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'services/youtube_auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Initialize YouTube Auth Service & restore persisted accounts on startup
  await YouTubeAuthService().init();

  runApp(const PlexusApp());
}
