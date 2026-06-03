@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// README-QS im Gate: die deterministischen Inhalts-Invarianten der
/// Repo-README (Bild-/Link-Existenz, Anti-Vokabular, Pflichtsektionen) laufen
/// bei jedem `dart test` mit — 0 Token, scheitert bei Drift.
///
/// Die Attestierungs-Schranke (`freshness`/`ack`) sitzt bewusst NUR im
/// git pre-commit-Hook, nicht hier — Testläufe sollen nicht an einem fehlenden
/// bewussten ack scheitern.
void main() {
  test('README content invariants hold (tool/readme-qa.sh check)', () {
    // `dart test` läuft aus packages/loam_cli/ -> Repo-Wurzel ist zwei hoch.
    final repoRoot = Directory.current.uri.resolve('../../').toFilePath();
    final qa = File('${repoRoot}tool/readme-qa.sh');
    if (!qa.existsSync()) {
      fail('tool/readme-qa.sh nicht gefunden unter $repoRoot');
    }

    final r = Process.runSync(
      'bash',
      ['tool/readme-qa.sh', 'check'],
      workingDirectory: repoRoot,
    );

    if (r.exitCode != 0) {
      fail('README-QS check fehlgeschlagen:\n${r.stdout}\n${r.stderr}');
    }
  });
}
