@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/rules/rule_profile.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:test/test.dart';

void main() {
  group('RuleProfile.resolve precedence', () {
    test('nothing set → core', () {
      expect(RuleProfile.resolve(), RuleProfile.core);
    });

    test('config beats default', () {
      expect(
        RuleProfile.resolve(config: RuleProfile.strict),
        RuleProfile.strict,
      );
    });

    test('CLI beats config in both directions', () {
      expect(
        RuleProfile.resolve(cli: RuleProfile.core, config: RuleProfile.strict),
        RuleProfile.core,
      );
      expect(
        RuleProfile.resolve(cli: RuleProfile.strict, config: RuleProfile.core),
        RuleProfile.strict,
      );
    });
  });

  group('RuleProfile.tryParse', () {
    test('known names parse, unknown and empty give null', () {
      expect(RuleProfile.tryParse('core'), RuleProfile.core);
      expect(RuleProfile.tryParse('strict'), RuleProfile.strict);
      expect(RuleProfile.tryParse('standard'), isNull);
      expect(RuleProfile.tryParse(''), isNull);
    });
  });

  group('rule assignment', () {
    test('every shipped rule is classified and nothing else is', () {
      expect(
        kRuleProfiles.keys.toSet(),
        AnalysisRunner.fullRegistryIds.toSet(),
        reason: 'a new rule must be placed in kRuleProfiles on purpose',
      );
    });

    test('core rules block in both profiles, strict rules only in strict', () {
      expect(RuleProfile.core.blocks('slop-empty-catch'), isTrue);
      expect(RuleProfile.strict.blocks('slop-empty-catch'), isTrue);
      expect(RuleProfile.core.blocks('code-duplicates'), isFalse);
      expect(RuleProfile.strict.blocks('code-duplicates'), isTrue);
    });

    test('an unclassified rule never blocks in core', () {
      expect(RuleProfile.core.blocks('not-yet-classified'), isFalse);
      expect(RuleProfile.strict.blocks('not-yet-classified'), isTrue);
    });
  });

  group('website drift', () {
    for (final page in ['rules.astro', 'de/rules.astro']) {
      final file = File('../../web/src/pages/$page');
      test(
        '$page shows the profile from kRuleProfiles for every live rule',
        () {
          final shown = <String, String>{};
          final card = RegExp(
            r'ruleId="([^"]+)".*?profile="(\w+)"',
            dotAll: true,
          );
          for (final m in card.allMatches(file.readAsStringSync())) {
            shown[m.group(1)!] = m.group(2)!;
          }
          expect(shown, {
            for (final e in kRuleProfiles.entries) e.key: e.value.name,
          });
        },
        skip: file.existsSync() ? false : 'web/ not part of this checkout',
      );
    }
  });
}
