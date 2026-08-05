import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-level sections of the app.
enum ShellDestination {
  home('Home', Icons.home_outlined, Icons.home),
  search('Search', Icons.search_outlined, Icons.search),
  library('Library', Icons.library_music_outlined, Icons.library_music),
  // A destination rather than a pushed route, so Settings keeps its own
  // navigation stack: opening Sync status, switching to Library and coming back
  // returns to Sync status rather than to the top of Settings.
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const ShellDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

final shellDestinationProvider = StateProvider<ShellDestination>(
  (ref) => ShellDestination.home,
);
