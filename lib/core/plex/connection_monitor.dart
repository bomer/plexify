import 'dart:async';

import 'connection_health.dart';

/// Why a reconnect was attempted. Shown on the Sync status screen, because
/// "it reconnected" is far less useful when diagnosing than "it reconnected
/// because the network changed".
enum ReconnectReason { networkChanged, connectionLost, manual }

/// Decides when to throw away the current server connection and pick again.
///
/// Discovery races LAN, then remote, then relay, and keeps the first address
/// that answers. That is the right choice at the moment it is made and can stop
/// being right at any time — walking out of the house is the obvious case, but
/// a server restart, a DHCP change or a VPN coming up all do it too.
///
/// Two triggers, one path:
///
/// * **The network changed.** Fast but not trustworthy — the OS reports that a
///   transport appeared, not that anything is reachable through it. Treated as
///   a reason to check, never as evidence.
/// * **Requests stopped arriving.** Trustworthy but slower, and the only signal
///   available on a desktop whose transport never changes.
///
/// Neither is sufficient alone, which is why both feed the same single
/// re-resolve rather than each getting its own recovery path.
class ConnectionMonitor {
  ConnectionMonitor({
    required ConnectionHealth health,
    required Future<void> Function() reconnect,
    Stream<void>? networkChanges,
    this.cooldown = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _health = health,
       _reconnect = reconnect,
       _networkChanges = networkChanges,
       _now = now ?? DateTime.now;

  final ConnectionHealth _health;
  final Future<void> Function() _reconnect;
  final Stream<void>? _networkChanges;
  final DateTime Function() _now;

  /// Minimum gap between automatic reconnects.
  ///
  /// Tearing down a client cancels its in-flight requests, which fail, which
  /// looks exactly like the connection being lost again. Without a cooldown a
  /// single reconnect can feed itself indefinitely.
  final Duration cooldown;

  StreamSubscription<void>? _lostSubscription;
  StreamSubscription<void>? _networkSubscription;

  bool _reconnecting = false;
  DateTime? _lastAttemptAt;

  DateTime? get lastAttemptAt => _lastAttemptAt;
  ReconnectReason? get lastReason => _lastReason;
  ReconnectReason? _lastReason;
  int get attempts => _attempts;
  int _attempts = 0;
  bool get isReconnecting => _reconnecting;

  void start() {
    _lostSubscription ??= _health.lost.listen(
      (_) => unawaited(_attempt(ReconnectReason.connectionLost)),
    );
    _networkSubscription ??= _networkChanges?.listen(
      (_) => unawaited(_attempt(ReconnectReason.networkChanged)),
    );
  }

  Future<void> stop() async {
    await _lostSubscription?.cancel();
    await _networkSubscription?.cancel();
    _lostSubscription = null;
    _networkSubscription = null;
  }

  /// Reconnects on demand, ignoring the cooldown.
  ///
  /// The cooldown exists to stop automatic triggers feeding each other; someone
  /// pressing a button in Settings has already decided to wait.
  Future<void> reconnectNow() => _attempt(ReconnectReason.manual, force: true);

  Future<void> _attempt(ReconnectReason reason, {bool force = false}) async {
    // Single-flight. A network change and a run of failures routinely arrive
    // together — they are two symptoms of one event, not two events.
    if (_reconnecting) return;

    final last = _lastAttemptAt;
    if (!force && last != null && _now().difference(last) < cooldown) return;

    _reconnecting = true;
    _lastAttemptAt = _now();
    _lastReason = reason;
    _attempts++;

    try {
      await _reconnect();
      // Failures recorded against the address we just abandoned — including
      // those caused by closing it mid-request — must not count against its
      // replacement.
      _health.reset();
    } catch (_) {
      // Nothing reachable. Normal when genuinely offline; the next trigger
      // tries again. Deliberately not rethrown: this runs from a stream
      // listener with nobody to catch it.
    } finally {
      _reconnecting = false;
    }
  }
}
