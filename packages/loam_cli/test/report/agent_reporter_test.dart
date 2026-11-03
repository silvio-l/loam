@TestOn('vm')
library;

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/report/agent_reporter.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:test/test.dart';

Finding _f(
  String id,
  Severity severity,
  String path,
  int line, {
  String? remedy,
}) => Finding(
  ruleId: id,
  severity: severity,
  filePath: path,
  line: line,
  message: 'm-$id-$line',
  fingerprint: 'fp-$id-$path-$line',
  remedy: remedy,
);

ReportPayload _payload(List<Finding> findings, {int? maxFindings}) =>
    ReportPayload(
      findings: findings,
      projectRoot: '/project',
      rulesetVersion: 'ruleset@x',
      toolVersion: '0.0.0',
      isTty: false,
      maxFindings: maxFindings,
      suppressedCount: 2,
    );

/// Finding lines are the ones that start with a severity name.
List<String> _findingLines(String out) => out
    .split('\n')
    .where((l) => RegExp(r'^(error|warning|info) ').hasMatch(l))
    .toList();

void main() {
  final mixed = [
    _f('b-rule', Severity.info, '/project/lib/z.dart', 1),
    _f('a-rule', Severity.warning, '/project/lib/b.dart', 9),
    _f('a-rule', Severity.warning, '/project/lib/b.dart', 2),
    _f('c-rule', Severity.error, '/project/lib/y.dart', 5, remedy: 'do it'),
    _f('a-rule', Severity.warning, '/project/lib/a.dart', 7),
  ];

  test('lists highest severity first, then rule, path, line', () {
    final lines = _findingLines(
      const AgentReporter().render(_payload(mixed, maxFindings: 0)),
    );
    expect(lines.map((l) => l.split(' ').take(3).join(' ')).toList(), [
      'error c-rule lib/y.dart:5',
      'warning a-rule lib/a.dart:7',
      'warning a-rule lib/b.dart:2',
      'warning a-rule lib/b.dart:9',
      'info b-rule lib/z.dart:1',
    ]);
  });

  test('output does not depend on input order', () {
    final a = const AgentReporter().render(_payload(mixed, maxFindings: 3));
    final b = const AgentReporter().render(
      _payload(mixed.reversed.toList(), maxFindings: 3),
    );
    expect(b, a);
  });

  test('caps the list and reports the omitted count and the way to all', () {
    final out = const AgentReporter().render(_payload(mixed, maxFindings: 2));
    expect(_findingLines(out), hasLength(2));
    final footer = out.trim().split('\n').last;
    expect(footer, contains('3'));
    expect(footer, contains('--max-findings 0'));
  });

  test('0 lists everything and prints no omitted footer', () {
    final out = const AgentReporter().render(_payload(mixed, maxFindings: 0));
    expect(_findingLines(out), hasLength(mixed.length));
    expect(out, isNot(contains('--max-findings')));
  });

  test('default cap applies when none is given', () {
    final many = [
      for (var i = 0; i < AgentReporter.defaultMaxFindings + 5; i++)
        _f('r', Severity.warning, '/project/lib/f.dart', i + 1),
    ];
    final out = const AgentReporter().render(_payload(many));
    expect(_findingLines(out), hasLength(AgentReporter.defaultMaxFindings));
    expect(out.trim().split('\n').last, contains('5'));
  });

  test('a fix hint follows the finding that has a remedy', () {
    final out = const AgentReporter().render(_payload(mixed, maxFindings: 1));
    expect(out, contains('do it'));
  });

  test('clean run is a single line that still counts suppressed findings', () {
    final out = const AgentReporter().render(_payload(const []));
    expect(out.trim().split('\n'), hasLength(1));
    expect(out, contains('2 suppressed'));
  });

  test('control characters in message and path cannot forge lines', () {
    final nasty = Finding(
      ruleId: 'r',
      severity: Severity.error,
      filePath: '/project/lib/a\nerror forged.dart',
      line: 1,
      message: 'bad\nerror fake lib/x.dart:1 \x1b[31mred\u202Eevil',
      fingerprint: 'fp',
      remedy: 'fix\nit',
    );
    final out = const AgentReporter().render(_payload([nasty]));
    expect(out, isNot(contains('\x1b')));
    expect(out, isNot(contains('\u202E')));
    expect(_findingLines(out), hasLength(1));
    // header, blank line, finding, fix hint: nothing else
    expect(out.trim().split('\n'), hasLength(4));
  });
}
