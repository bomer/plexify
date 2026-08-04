import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'sync_status_screen.dart';

/// Refresh, and a way into the sync status screen.
///
/// The refresh button is not a duplicate of pull-to-refresh: that gesture needs
/// a drag, and a mouse wheel produces none, so on the desktop there was no way
/// to ask for a sync at all.
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Refresh from Plex',
          onPressed: _busy ? null : _refresh,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Sync status',
          icon: const Icon(Icons.info_outline),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SyncStatusScreen()),
          ),
        ),
      ],
    );
  }
}
