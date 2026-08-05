import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Refresh.
///
/// Not a duplicate of pull-to-refresh: that gesture needs a drag, and a mouse
/// wheel produces none, so on the desktop there was no way to ask for a sync at
/// all.
///
/// Sync status used to sit beside this as an `info` button. It moved into
/// Settings — it is a diagnostic, and an icon in the corner of Home is not
/// where anyone looks for one.
class SyncActions extends ConsumerStatefulWidget {
  const SyncActions({super.key});

  @override
  ConsumerState<SyncActions> createState() => _SyncActionsState();
}

class _SyncActionsState extends ConsumerState<SyncActions> {
  bool _busy = false;

  Future<void> _refresh() async {
    final scheduler = ref.read(syncSchedulerProvider);
    if (scheduler == null || _busy) return;

    setState(() => _busy = true);
    try {
      await scheduler.refreshNow();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Refresh from Plex',
      onPressed: _busy ? null : _refresh,
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );
  }
}
