import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Top-level sections of the app.
enum ShellDestination {
  home('Home', Icons.home_outlined, Icons.home),
  search('Search', Icons.search_outlined, Icons.search),
  library('Library', Icons.library_music_outlined, Icons.library_music);

  const ShellDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

final shellDestinationProvider = StateProvider<ShellDestination>(
  (ref) => ShellDestination.home,
);
