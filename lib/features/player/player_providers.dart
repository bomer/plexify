import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the Now Playing view is expanded over the current screen.
///
/// Lives in shared state rather than in the shell's widget state so the mini
/// player can expand it and the back handler can collapse it, without either
/// needing a reference to the other.
final nowPlayingExpandedProvider = StateProvider<bool>((ref) => false);
