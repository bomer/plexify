import 'package:http/http.dart' as http;

/// Puts a timeout on every request through it, including ones added later.
///
/// **A server that is simply not there accepts nothing and says nothing.**
/// Wrong address, not on the LAN, machine asleep: `package:http` waits forever,
/// and a flow whose first call never returns has no error to show and nothing
/// to time out. That is what "it just comes up Searching and stays there"
/// looked like from the outside, and it cost an afternoon to find because
/// nothing had failed.
///
/// Wrapped rather than applied at each call site so every endpoint on a client
/// is covered by construction, including the ones written next. `QbitClient`
/// grew from four endpoints to eight without anyone revisiting this, and
/// `HealthReportingClient` in `plex/connection_health.dart` takes the same
/// shape for the same reason.
///
/// Shared rather than copied because this is now the fourth HTTP client in the
/// app to need it, and the third and fourth would otherwise have been the same
/// twelve lines twice.
class BoundedClient extends http.BaseClient {
  BoundedClient(this._inner, this._timeout);

  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request).timeout(_timeout);

  @override
  void close() => _inner.close();
}
