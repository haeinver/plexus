import 'package:flutter/material.dart';
import 'app.dart';
import 'services/youtube_auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize YouTube Auth Service & restore persisted accounts on startup
  await YouTubeAuthService().init();

  runApp(const PlexusApp());
}
