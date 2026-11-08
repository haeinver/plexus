import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/main_screen.dart';

/// Root Widget of Plexus App
class PlexusApp extends StatefulWidget {
  const PlexusApp({super.key});

  @override
  State<PlexusApp> createState() => _PlexusAppState();
}

class _PlexusAppState extends State<PlexusApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme(bool isDark) {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plexus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: MainScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onThemeModeChanged: _toggleTheme,
      ),
    );
  }
}
