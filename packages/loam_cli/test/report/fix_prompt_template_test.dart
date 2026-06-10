@TestOn('vm')
library;

import 'package:loam/src/report/fix_prompt_template.dart';
import 'package:test/test.dart';

/// Fixer Ziel-Identifier für die Golden-/Determinismus-Tests.
const kTestTarget = 'demo_project';

/// Unit-Tests für FixPromptTemplate (issue 07).
///
/// Abgedeckt:
///  - prompt@ver-Marker vorhanden und korrekt
///  - Golden-Prompt: exakt erwarteter String für fixe Auswahl
///  - Determinismus: gleiche Auswahl ⇒ identischer String (zwei Aufrufe)
///  - Prompt enthält je Finding: ruleId, file:line, message, fix-hint
///  - Leere Auswahl: kein Crash, sinnvoller Rückgabe-String
///  - fixHintFor: bekannte Rule liefert spezifischen Hinweis, unbekannte → generisch

void main() {
  // -------------------------------------------------------------------------
  // AC2: prompt@ver-Marker
  // -------------------------------------------------------------------------
  group('prompt@ver marker', () {
    test('kPromptVersion contains "prompt@v"', () {
      expect(kPromptVersion, contains('prompt@v'));
    });

    test('kFixPromptTemplate contains the version marker', () {
      expect(kFixPromptTemplate, contains(kPromptVersion));
    });

    test('kPromptVersion is non-empty', () {
      expect(kPromptVersion, isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // AC3 + AC4: Golden-Prompt + Determinismus + Pflichtfelder
  // -------------------------------------------------------------------------

  /// Fixe Test-Auswahl für Golden-Tests.
  final fixedSelection = [
    {
      'ruleId': 'unused-public-exports',
      'filePath': 'lib/src/foo.dart',
      'line': 10,
      'message': 'Unused export: Foo',
    },
    {
      'ruleId': 'unused-public-exports',
      'filePath': 'lib/src/bar.dart',
      'line': 42,
      'message': 'Unused export: Bar',
    },
  ];

  /// Exakt erwarteter Prompt für die fixe Auswahl oben.
  ///
  /// Dient als Goldstandard: wenn sich dieser String ändert, muss auch
  /// kPromptVersion hochgezählt werden.
  const goldenFindingsBlock =
      '- [unused-public-exports] lib/src/foo.dart:10 — Unused export: Foo\n'
      '  Fix hint: Remove or internalize the unused public declaration, or add it to a '
      'library export if it is intentionally public.'
      '\n\n'
      '- [unused-public-exports] lib/src/bar.dart:42 — Unused export: Bar\n'
      '  Fix hint: Remove or internalize the unused public declaration, or add it to a '
      'library export if it is intentionally public.';

  final goldenPrompt = fillPromptTarget(
    kFixPromptTemplate,
    kTestTarget,
  ).replaceAll('{{FINDINGS}}', goldenFindingsBlock);

  group('Golden-Prompt', () {
    test(
      'assembleFixPrompt returns exact expected string for fixed selection',
      () {
        final result = assembleFixPrompt(
          selectedFindings: fixedSelection,
          target: kTestTarget,
        );
        expect(
          result,
          equals(goldenPrompt),
          reason:
              'assembleFixPrompt must return byte-identical result for fixed selection',
        );
      },
    );

    test('result contains ruleId for each finding', () {
      final result = assembleFixPrompt(
        selectedFindings: fixedSelection,
        target: kTestTarget,
      );
      expect(result, contains('unused-public-exports'));
    });

    test('result contains file:line for each finding', () {
      final result = assembleFixPrompt(
        selectedFindings: fixedSelection,
        target: kTestTarget,
      );
      expect(result, contains('lib/src/foo.dart:10'));
      expect(result, contains('lib/src/bar.dart:42'));
    });

    test('result contains message for each finding', () {
      final result = assembleFixPrompt(
        selectedFindings: fixedSelection,
        target: kTestTarget,
      );
      expect(result, contains('Unused export: Foo'));
      expect(result, contains('Unused export: Bar'));
    });

    test('result contains fix hint for each finding', () {
      final result = assembleFixPrompt(
        selectedFindings: fixedSelection,
        target: kTestTarget,
      );
      // The fix hint for 'unused-public-exports' must appear
      expect(
        result,
        contains('Remove or internalize the unused public declaration'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC3: Determinismus — gleiche Auswahl ⇒ byte-identischer String
  // -------------------------------------------------------------------------
  group('Determinism', () {
    test('two calls with same selection produce identical strings', () {
      final first = assembleFixPrompt(
        selectedFindings: fixedSelection,
        target: kTestTarget,
      );
      final second = assembleFixPrompt(
        selectedFindings: fixedSelection,
        target: kTestTarget,
      );
      expect(
        first,
        equals(second),
        reason: 'same selection must always produce byte-identical output',
      );
    });

    test('single-finding selection is also deterministic', () {
      final sel = [
        {
          'ruleId': 'unused-public-exports',
          'filePath': 'lib/x.dart',
          'line': 1,
          'message': 'Msg',
        },
      ];
      expect(
        assembleFixPrompt(selectedFindings: sel, target: kTestTarget),
        equals(assembleFixPrompt(selectedFindings: sel, target: kTestTarget)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC4: Pro Finding: ruleId + file:line + message + fix-hint
  // -------------------------------------------------------------------------
  group('Per-finding fields', () {
    test('single finding includes ruleId, file:line, message, fix hint', () {
      final result = assembleFixPrompt(
        target: kTestTarget,
        selectedFindings: [
          {
            'ruleId': 'unused-public-exports',
            'filePath': 'lib/src/baz.dart',
            'line': 7,
            'message': 'Unused export: Baz',
          },
        ],
      );
      expect(result, contains('unused-public-exports'));
      expect(result, contains('lib/src/baz.dart:7'));
      expect(result, contains('Unused export: Baz'));
      expect(result, contains('Fix hint:'));
    });

    test('unknown ruleId uses generic fix hint', () {
      final result = assembleFixPrompt(
        target: kTestTarget,
        selectedFindings: [
          {
            'ruleId': 'some-future-rule',
            'filePath': 'lib/x.dart',
            'line': 1,
            'message': 'Some message',
          },
        ],
      );
      expect(result, contains(kGenericFixHint));
    });
  });

  // -------------------------------------------------------------------------
  // Edge: empty selection
  // -------------------------------------------------------------------------
  group('Empty selection', () {
    test('empty selection does not throw', () {
      expect(
        () => assembleFixPrompt(selectedFindings: [], target: kTestTarget),
        returnsNormally,
      );
    });

    test('empty selection returns a non-empty string', () {
      expect(
        assembleFixPrompt(selectedFindings: [], target: kTestTarget),
        isNotEmpty,
      );
    });

    test('empty selection result contains "no findings selected"', () {
      expect(
        assembleFixPrompt(selectedFindings: [], target: kTestTarget),
        contains('no findings selected'),
      );
    });
  });

  // -------------------------------------------------------------------------
  // fixHintFor helper
  // -------------------------------------------------------------------------
  group('fixHintFor', () {
    test('returns specific hint for unused-public-exports', () {
      expect(
        fixHintFor('unused-public-exports'),
        isNot(equals(kGenericFixHint)),
      );
      expect(
        fixHintFor('unused-public-exports'),
        contains('Remove or internalize'),
      );
    });

    test('returns kGenericFixHint for unknown ruleId', () {
      expect(fixHintFor('nonexistent-rule-xyz'), equals(kGenericFixHint));
    });
  });

  // -------------------------------------------------------------------------
  // prompt@v2: Ziel-Identifier im Prompt-Kopf
  // -------------------------------------------------------------------------
  group('Target identifier (prompt@v2)', () {
    test('assembled prompt names the target project', () {
      final result = assembleFixPrompt(
        selectedFindings: fixedSelection,
        target: kTestTarget,
      );
      expect(
        result,
        contains('Target project: `demo_project`'),
        reason: 'the prompt head must document which project it refers to',
      );
    });

    test('empty selection still names the target project', () {
      final result = assembleFixPrompt(selectedFindings: [], target: 'svc_api');
      expect(result, contains('Target project: `svc_api`'));
    });

    test('no {{TARGET}} placeholder survives in the output', () {
      final result = assembleFixPrompt(
        selectedFindings: fixedSelection,
        target: kTestTarget,
      );
      expect(result, isNot(contains('{{TARGET}}')));
    });

    test('fillPromptTarget substitutes the placeholder', () {
      final filled = fillPromptTarget('head `{{TARGET}}` tail', 'my_pkg');
      expect(filled, equals('head `my_pkg` tail'));
    });

    test('fillPromptTarget falls back for empty/blank target', () {
      expect(
        fillPromptTarget('`{{TARGET}}`', ''),
        equals('`the analysed project`'),
      );
      expect(
        fillPromptTarget('`{{TARGET}}`', '   '),
        equals('`the analysed project`'),
      );
    });
  });
}
