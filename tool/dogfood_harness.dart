#!/usr/bin/env dart

// ignore_for_file: avoid_print
/// Dogfood harness — drives the installed `loam` CLI and prints categorized findings.
///
/// Usage:
///   dart tool/dogfood_harness.dart <project-root>
///
/// The harness:
///   1. Resolves the `loam` binary (checks ~/.pub-cache/bin/loam first,
///      falls back to `dart pub global run loam:loam`).
///   2. Calls `loam --format sarif scan --project-root <target>`.
///   3. Parses the SARIF JSON output.
///   4. Prints a categorized findings table (total + file/line/message per finding).
///
/// This file is NOT part of the dart test gate.
/// No internal loam APIs are used — only the installed CLI binary.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _usage();
    exit(0);
  }

  final projectRoot = args.first;
  if (!Directory(projectRoot).existsSync()) {
    stderr.writeln('Error: project root not found: $projectRoot');
    exit(1);
  }

  final loamBin = _resolveLoamBin();
  print('loam binary : $loamBin');
  print('target      : $projectRoot');
  print('');

  final sarifJson = await _runLoamSarif(loamBin, projectRoot);
  final findings = _parseSarif(sarifJson);

  _printFindings(findings);
}

// ---------------------------------------------------------------------------
// Resolve loam binary
// ---------------------------------------------------------------------------

String _resolveLoamBin() {
  final home = Platform.environment['HOME'] ?? '';
  final pubCacheBin = '$home/.pub-cache/bin/loam';
  if (File(pubCacheBin).existsSync()) return pubCacheBin;

  // Fallback: dart pub global run
  return 'dart';
}

// ---------------------------------------------------------------------------
// Invoke loam CLI
// ---------------------------------------------------------------------------

Future<String> _runLoamSarif(String loamBin, String projectRoot) async {
  final List<String> cmd;
  if (loamBin == 'dart') {
    cmd = [
      'dart',
      'pub',
      'global',
      'run',
      'loam:loam',
      '--format',
      'sarif',
      'scan',
      '--project-root',
      projectRoot,
    ];
  } else {
    cmd = [loamBin, '--format', 'sarif', 'scan', '--project-root', projectRoot];
  }

  print('Running: ${cmd.join(' ')}');
  print('');

  final result = await Process.run(
    cmd.first,
    cmd.sublist(1),
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  if (result.stderr.toString().isNotEmpty) {
    stderr.writeln('[loam stderr] ${result.stderr}');
  }

  // Exit code 1 means findings present (correct per spec) — not an error.
  if (result.exitCode != 0 && result.exitCode != 1) {
    stderr.writeln(
      'loam exited with unexpected code ${result.exitCode}. '
      'stderr: ${result.stderr}',
    );
    exit(result.exitCode);
  }

  return result.stdout as String;
}

// ---------------------------------------------------------------------------
// Parse SARIF
// ---------------------------------------------------------------------------

class _Finding {
  final String ruleId;
  final String level;
  final String message;
  final String uri;
  final int? startLine;

  const _Finding({
    required this.ruleId,
    required this.level,
    required this.message,
    required this.uri,
    this.startLine,
  });
}

List<_Finding> _parseSarif(String sarifJson) {
  final dynamic doc = jsonDecode(sarifJson);
  final List<dynamic> runs = (doc as Map<String, dynamic>)['runs'] as List;
  if (runs.isEmpty) return [];

  final List<dynamic> results =
      (runs.first as Map<String, dynamic>)['results'] as List? ?? [];

  return results.map((dynamic r) {
    final result = r as Map<String, dynamic>;
    final ruleId = result['ruleId'] as String? ?? '?';
    final level = result['level'] as String? ?? 'warning';
    final message =
        (result['message'] as Map<String, dynamic>?)?['text'] as String? ?? '';

    String uri = '';
    int? startLine;
    final locations = result['locations'] as List?;
    if (locations != null && locations.isNotEmpty) {
      final physLoc =
          (locations.first as Map<String, dynamic>)['physicalLocation']
              as Map<String, dynamic>?;
      if (physLoc != null) {
        uri =
            (physLoc['artifactLocation'] as Map<String, dynamic>?)?['uri']
                as String? ??
            '';
        startLine =
            (physLoc['region'] as Map<String, dynamic>?)?['startLine'] as int?;
      }
    }

    return _Finding(
      ruleId: ruleId,
      level: level,
      message: message,
      uri: uri,
      startLine: startLine,
    );
  }).toList();
}

// ---------------------------------------------------------------------------
// Print findings
// ---------------------------------------------------------------------------

void _printFindings(List<_Finding> findings) {
  print('=== loam dogfood harness — findings ===');
  print('Total: ${findings.length}');
  print('');

  // Group by rule
  final byRule = <String, List<_Finding>>{};
  for (final f in findings) {
    byRule.putIfAbsent(f.ruleId, () => []).add(f);
  }

  for (final entry in byRule.entries) {
    print('Rule: ${entry.key}  (${entry.value.length} findings)');
    print('-' * 72);
    for (final f in entry.value) {
      final lineStr = f.startLine != null ? ':${f.startLine}' : '';
      print('  ${f.uri}$lineStr');
      print('    ${f.level}  ${f.message}');
    }
    print('');
  }

  print('--- classification columns (fill in manually) ---');
  print('# idx | rule                    | file:line | category (real/FP/FN)');
  print('');
  for (var i = 0; i < findings.length; i++) {
    final f = findings[i];
    final lineStr = f.startLine != null ? ':${f.startLine}' : '';
    print(
      '  ${(i + 1).toString().padLeft(3)}  ${f.ruleId.padRight(24)} '
      '${f.uri}$lineStr',
    );
  }
}

// ---------------------------------------------------------------------------
// Usage
// ---------------------------------------------------------------------------

void _usage() {
  print('Usage: dart tool/dogfood_harness.dart <project-root>');
  print('');
  print('  Drives the installed loam CLI (--format sarif scan) against');
  print('  <project-root> and prints a categorized findings table.');
  print('');
  print('  The loam binary is resolved from ~/.pub-cache/bin/loam');
  print('  or falls back to `dart pub global run loam:loam`.');
}
