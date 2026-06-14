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
      markTestSkipped(
        'tool/docs-attest.sh nicht vorhanden — Repo-only-Test übersprungen',
      );
      return;
    }

    final r = Process.runSync('bash', [
      'tool/docs-attest.sh',
      'check',
    ], workingDirectory: repoRoot);

    if (r.exitCode != 0) {
      fail('Public-Docs-QS check fehlgeschlagen:\n${r.stdout}\n${r.stderr}');
    }
  });

  group('devguide-rules check (bidirektional)', () {
    final repoRoot = Directory.current.uri.resolve('../../').toFilePath();
    final qa = File('${repoRoot}tool/docs-attest.sh');
    final guide = File('${repoRoot}docs/developer-guide.md');

    /// Führt `docs-attest.sh check` mit einer temporären Kopie des Guides als
    /// Override aus (LOAM_DEVGUIDE_OVERRIDE) — die eingecheckte Datei bleibt
    /// unangetastet. Liefert das Process-Ergebnis zurück.
    ProcessResult runWithGuide(String guideContents) {
      final tmp = File(
        '${Directory.systemTemp.path}/loam_devguide_${DateTime.now().microsecondsSinceEpoch}.md',
      );
      tmp.writeAsStringSync(guideContents);
      try {
        return Process.runSync(
          'bash',
          ['tool/docs-attest.sh', 'check'],
          workingDirectory: repoRoot,
          environment: {'LOAM_DEVGUIDE_OVERRIDE': tmp.path},
        );
      } finally {
        if (tmp.existsSync()) tmp.deleteSync();
      }
    }

    test('fehlende Live-Rule in der Guide-Tabelle erzwingt Rot', () {
      if (!qa.existsSync() || !guide.existsSync()) {
        markTestSkipped('Repo-only-Test übersprungen (Tool/Guide fehlt)');
        return;
      }
      // Entferne die Tabellenzeile einer Live-Rule (eine pro Zeile in der Tabelle).
      final lines = guide.readAsLinesSync();
      final mutated = lines
          .where((l) => !l.contains('`unused-public-exports`'))
          .join('\n');
      final r = runWithGuide(mutated);
      expect(
        r.exitCode,
        isNot(0),
        reason: 'Fehlende Live-Rule muss den Check rot machen:\n${r.stdout}',
      );
      expect('${r.stdout}', contains('devguide-rules'));
      expect('${r.stdout}', contains('unused-public-exports'));
    });

    test('erfundene Rule-ID in der Guide-Tabelle erzwingt Rot', () {
      if (!qa.existsSync() || !guide.existsSync()) {
        markTestSkipped('Repo-only-Test übersprungen (Tool/Guide fehlt)');
        return;
      }
      // Füge eine Backtick-Rule-ID-Zeile in die Rules-Tabelle ein, die NICHT in
      // fullRegistryIds steht.
      final lines = guide.readAsLinesSync();
      final out = <String>[];
      for (final l in lines) {
        out.add(l);
        if (l.contains('Currently active rules:')) {
          out.add('');
          out.add('| `bogus-rule` | not a real rule |');
        }
      }
      final r = runWithGuide(out.join('\n'));
      expect(
        r.exitCode,
        isNot(0),
        reason: 'Erfundene Rule-ID muss den Check rot machen:\n${r.stdout}',
      );
      expect('${r.stdout}', contains('devguide-rules'));
      expect('${r.stdout}', contains('bogus-rule'));
    });
  });
}
