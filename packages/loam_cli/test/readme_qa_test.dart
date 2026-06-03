@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Public-Docs-QS im Gate: die deterministischen Struktur-Invarianten der
/// Root-README (Pflicht-Marker aus docs/readme-spec.md, Bild-/Link-Existenz,
/// Anti-Vokabular) laufen bei jedem `dart test` mit — 0 Token, scheitert bei Drift.
///
/// Die bewusste Push-Attestierung (`attest` + pre-push-Hook) sitzt bewusst NICHT
/// hier — Testläufe sollen nicht an einem fehlenden Push-ack scheitern.
void main() {
  test('public docs structure holds (tool/docs-attest.sh check)', () {
    // `dart test` läuft aus packages/loam_cli/ -> Repo-Wurzel ist zwei hoch.
    final repoRoot = Directory.current.uri.resolve('../../').toFilePath();
    final qa = File('${repoRoot}tool/docs-attest.sh');
    if (!qa.existsSync()) {
      // Im veröffentlichten Paket (pub.dev) liegt das Repo-Tool nicht bei —
      // dann ist dieser Repo-QS-Test gegenstandslos und wird übersprungen.
      markTestSkipped('tool/docs-attest.sh nicht vorhanden — Repo-only-Test übersprungen');
      return;
    }

    final r = Process.runSync(
      'bash',
      ['tool/docs-attest.sh', 'check'],
      workingDirectory: repoRoot,
    );

    if (r.exitCode != 0) {
      fail('Public-Docs-QS check fehlgeschlagen:\n${r.stdout}\n${r.stderr}');
    }
  });
}
