import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plexify/core/audio/quality_policy.dart';
import 'package:plexify/core/plex/plex_server.dart';

/// #8 left this policy with nothing to tune — the transcoder ignores every
/// bitrate cap it was asked for — so the only thing worth testing is *which
/// way the binary decision falls* for each combination of the three signals
/// it's built from.
void main() {
  const policy = QualityPolicy();

  const lan = PlexServer(
    name: 'Tower',
    baseUrl: 'https://192-168-1-10.plex.direct:32400',
    token: 't',
    isLocal: true,
    isRelay: false,
  );
  const remote = PlexServer(
    name: 'Tower',
    baseUrl: 'https://82-1-2-3.plex.direct:32400',
    token: 't',
    isLocal: false,
    isRelay: false,
  );
  const relay = PlexServer(
    name: 'Tower',
    baseUrl: 'https://relay.plex.direct:443',
    token: 't',
    isLocal: false,
    isRelay: true,
  );

  group('server locality', () {
    test('direct-plays on the LAN regardless of connectivity', () {
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.mobile],
          server: lan,
          sourceKbps: 900,
        ),
        QualityDecision.directPlay,
      );
    });

    test('transcodes over a relay even on wifi', () {
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.wifi],
          server: relay,
          sourceKbps: 900,
        ),
        QualityDecision.transcode,
      );
    });
  });

  group('remote, not relayed', () {
    test('direct-plays on wifi', () {
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.wifi],
          server: remote,
          sourceKbps: 900,
        ),
        QualityDecision.directPlay,
      );
    });

    test('direct-plays on ethernet', () {
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.ethernet],
          server: remote,
          sourceKbps: 900,
        ),
        QualityDecision.directPlay,
      );
    });

    test('transcodes on cellular', () {
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.mobile],
          server: remote,
          sourceKbps: 900,
        ),
        QualityDecision.transcode,
      );
    });

    test('counts a wifi entry alongside others as unmetered', () {
      // Android can report more than one transport at once — a VPN riding
      // over wifi still shows up with wifi in the list.
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.vpn, ConnectivityResult.wifi],
          server: remote,
          sourceKbps: 900,
        ),
        QualityDecision.directPlay,
      );
    });

    test('transcodes when nothing in the list is wifi or ethernet', () {
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.bluetooth],
          server: remote,
          sourceKbps: 900,
        ),
        QualityDecision.transcode,
      );
    });
  });

  group('source rate floor', () {
    test('direct-plays a file already at the transcoder\'s own output, even '
        'on cellular through a relay', () {
      // Transcoding an mp3 already at ~240kbps would spend more data for
      // worse audio — #8's finding that makes this floor exist at all.
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.mobile],
          server: relay,
          sourceKbps: 190,
        ),
        QualityDecision.directPlay,
      );
    });

    test('transcodes a lossless file over the same connection', () {
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.mobile],
          server: remote,
          sourceKbps: 1000,
        ),
        QualityDecision.transcode,
      );
    });

    test('treats an unknown source rate as nothing measured, not a floor', () {
      // A null sourceKbps is what a track looks like before its part size has
      // synced — it must not silently pin every such track to direct play.
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.mobile],
          server: remote,
          sourceKbps: null,
        ),
        QualityDecision.transcode,
      );
    });
  });

  group('override', () {
    test('wins over every other signal', () {
      expect(
        policy.decide(
          connectivity: const [ConnectivityResult.wifi],
          server: lan,
          sourceKbps: 190,
          override: QualityDecision.transcode,
        ),
        QualityDecision.transcode,
      );
    });
  });
}
