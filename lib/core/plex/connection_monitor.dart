import 'dart:async';

import 'connection_health.dart';

/// Why a reconnect was attempted. Shown on the Sync status screen, because
/// "it reconnected" is far less useful when diagnosing than "it reconnected
/// because the network changed".
enum ReconnectReason {
  networkChanged,
  connectionLost,

  /// There is no connection at all, and never was one this session.
  ///
  /// Distinct from [connectionLost] because nothing failed — a launch that
  /// could not resolve a server has no client, makes no requests, and so can
  /// never produce a failure to notice.
  neverConnected,

  manual,
}

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
/// * **There is no connection at all.** The third trigger, and the one that
///   closes a genuine dead end: both of the above need something to be
///   *happening*. A launch that resolved nothing has no server, therefore no
///   client, therefore no requests, therefore no failures — so neither of the
///   other two can ever fire, and the app sits disconnected until the OS
///   volunteers an event or the user finds the button. Reachable on a cold
///   start with the network still settling, which is exactly a phone opened
///   moments after wifi was switched off.
///
/// Neither is sufficient alone, which is why all three feed the same single
/// re-resolve rather than each getting its own recovery path.
class ConnectionMonitor {
  ConnectionMonitor({
    required ConnectionHealth health,
    required Future<bool> Function() reconnect,
    Stream<void>? networkChanges,
    bool Function()? needsConnection,
    this.cooldown = const Duration(seconds: 10),
    this.networkCooldown = const Duration(seconds: 2),
    this.retryWhenDisconnected = const Duration(seconds: 15),
    this.maxRetryDelay = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _health = health,
       _reconnect = reconnect,
       _networkChanges = networkChanges,
       _needsConnection = needsConnection,
       _now = now ?? DateTime.now;

  final ConnectionHealth _health;

  /// Re-races the connections and reports **whether the address changed**.
  ///
  /// The boolean is what stops a failed re-resolve from looking like a
  /// successful one. Discovery is deliberately sticky: when nothing answers it
  /// keeps the last address that worked, so the future completes happily with
  /// the same dead address it started from.
  final Future<bool> Function() _reconnect;
  final Stream<void>? _networkChanges;
  final DateTime Function() _now;

  /// Minimum gap between automatic reconnects.
  ///
  /// Tearing down a client cancels its in-flight requests, which fail, which
  /// looks exactly like the connection being lost again. Without a cooldown a
  /// single reconnect can feed itself indefinitely.
  final Duration cooldown;

  /// The same, for a transport change — and far shorter, because the two are
  /// not the same kind of event.
  ///
  /// **A handover emits several, and the useful one is never the first.** Wifi
  /// going away is reported the moment it goes, while cellular is still coming
  /// up, so that attempt finds nothing and keeps the dead address. The event
  /// that *can* succeed arrives a second or two later, when mobile data
  /// attaches — and under the ten-second cooldown it was refused, leaving
  /// recovery to the failure path, which is slow by design. That is why
  /// toggling wifi off appeared to wait out a timeout rather than reconnecting
  /// immediately.
  ///
  /// Short but not zero: Android emits bursts of connectivity events during a
  /// handover, and collapsing the ones that arrive together is the whole reason
  /// there is a cooldown here at all.
  final Duration networkCooldown;

  /// How soon to try again when there is no connection at all.
  ///
  /// Shorter than the cooldown would be pointless and longer would make a
  /// launch that missed by a second feel broken. Doubles up to
  /// [maxRetryDelay] for as long as nothing is reachable, so a phone genuinely
  /// out of signal is not re-racing LAN, remote and relay every fifteen seconds
  /// for an hour.
  final Duration retryWhenDisconnected;
  final Duration maxRetryDelay;

  /// Whether the app wants a connection and does not have one.
  ///
  /// A callback rather than a stream because it is asked, never awaited: the
  /// answer is read at the moment of a tick and never held. Signed out counts
  /// as *not* needing one, or the retry would run forever on the login screen.
  final bool Function()? _needsConnection;

  StreamSubscription<void>? _lostSubscription;
  StreamSubscription<void>? _networkSubscription;
  Timer? _retryTimer;

  /// How long the *next* disconnected retry will wait. Doubles while nothing is
  /// reachable and resets the moment something is.
  Duration _retryBackoff = Duration.zero;

  bool _reconnecting = false;
  DateTime? _lastAttemptAt;

  final _reconnectingChanges = StreamController<bool>.broadcast();

  /// Emits whenever a reconnect starts or finishes, so the UI can say so.
  ///
  /// A reconnect takes seconds — three waves of connection probes, each with
  /// its own timeout — and during it playback has usually just stopped. Silence
  /// for that long is indistinguishable from the app being broken, which is
  /// what makes this worth publishing rather than leaving as a field the Sync
  /// status screen happens to read.
  Stream<bool> get reconnectingChanges => _reconnectingChanges.stream;

  DateTime? get lastAttemptAt => _lastAttemptAt;
  ReconnectReason? get lastReason => _lastReason;
  ReconnectReason? _lastReason;
  int get attempts => _attempts;
  int _attempts = 0;
  bool get isReconnecting => _reconnecting;

  /// Whether the last attempt actually landed somewhere new.
  ///
  /// Worth surfacing rather than inferring: "Reconnects: 4" beside an unchanged
  /// address is a completely different situation from four real moves, and the
  /// two look identical from the library screen.
  bool get lastChangedAddress => _lastChangedAddress;
  bool _lastChangedAddress = false;

  void start() {
    _lostSubscription ??= _health.lost.listen(
      (_) => unawaited(_attempt(ReconnectReason.connectionLost)),
    );
    _networkSubscription ??= _networkChanges?.listen(
      (_) => unawaited(_attempt(ReconnectReason.networkChanged)),
    );
    // Armed only while a connection is actually missing, never as a standing
    // heartbeat. On the login screen and on a healthy launch there is nothing
    // to retry, and a timer running anyway is one more thing keeping a phone
    // awake for no reason.
    if (_needsConnection?.call() ?? false) {
      _retryBackoff = retryWhenDisconnected;
      _arm(retryWhenDisconnected);
    }
  }

  Future<void> stop() async {
    await _lostSubscription?.cancel();
    await _networkSubscription?.cancel();
    _retryTimer?.cancel();
    _lostSubscription = null;
    _networkSubscription = null;
    _retryTimer = null;
    await _reconnectingChanges.close();
  }

  /// Checks now whether a connection is still missing, ignoring the schedule.
  ///
  /// Exposed for the app-resume hook and for tests, which would otherwise have
  /// to wait out a real timer.
  /// Tries again from a standing start, and keeps trying while there is nothing
  /// to lose.
  ///
  /// Self-arming while disconnected and self-cancelling once something answers.
  /// Called by [start] when a launch has no server, by the timer it sets, and
  /// by whoever notices the app has dropped back to having none — see
  /// `connectionMonitorProvider`, which watches for exactly that.
  Future<void> retryIfDisconnected() async {
    if (!(_needsConnection?.call() ?? false)) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryBackoff = retryWhenDisconnected;
      return;
    }

    await _attempt(ReconnectReason.neverConnected);

    // Re-checked after the attempt, so a successful one stops the loop here
    // rather than arming a timer that will only cancel itself later.
    if (!(_needsConnection?.call() ?? false)) {
      _retryBackoff = retryWhenDisconnected;
      return;
    }

    final next = _retryBackoff * 2;
    _retryBackoff = next > maxRetryDelay ? maxRetryDelay : next;
    _arm(_retryBackoff);
  }

  void _arm(Duration delay) {
    if (_reconnectingChanges.isClosed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(retryIfDisconnected()));
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

    // Per reason, not one number for everything. The cooldown exists to stop a
    // reconnect *feeding itself* — tearing down a client fails its in-flight
    // requests, which looks exactly like the connection dropping again — and
    // that loop only runs through the failure trigger. The OS does not emit
    // connectivity events because we reconnected, so holding a transport change
    // to the same delay suppresses real news to prevent an echo that cannot
    // reach it.
    final wait = reason == ReconnectReason.networkChanged
        ? networkCooldown
        : cooldown;
    final last = _lastAttemptAt;
    if (!force && last != null && _now().difference(last) < wait) return;

    _reconnecting = true;
    _lastAttemptAt = _now();
    _lastReason = reason;
    _attempts++;
    _publish();

    try {
      _lastChangedAddress = await _reconnect();
      // **Only when there is genuinely a replacement.** Failures recorded
      // against an address we just abandoned, including those caused by closing
      // it mid-request, must not count against the one that replaced it. But
      // discovery is sticky: with nothing reachable it keeps the last address
      // that worked, and the future completes just as happily. Resetting there
      // throws away the evidence that the connection is still dead, and then
      // the cooldown holds off the next attempt — so a re-resolve that ran a
      // moment too early, while the OS was still reporting the old transport,
      // leaves playback stuck on a dead address with nothing left to notice.
      // That is exactly what a wifi to cellular handover produces.
      if (_lastChangedAddress) _health.reset();
    } catch (_) {
      // Nothing reachable. Normal when genuinely offline; the next trigger
      // tries again. Deliberately not rethrown: this runs from a stream
      // listener with nobody to catch it.
    } finally {
      _reconnecting = false;
      _publish();
    }
  }

  void _publish() {
    if (!_reconnectingChanges.isClosed) _reconnectingChanges.add(_reconnecting);
  }
}
