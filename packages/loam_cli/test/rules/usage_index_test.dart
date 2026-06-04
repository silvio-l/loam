@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/usage_index.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test helper — loads the unused_exports_fixture and exposes the index.
// ---------------------------------------------------------------------------

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );

  late ProjectLoadResult loadResult;
  late UsageIndex index;

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(fixturePath);
    expect(
      loadResult.errors,
      isEmpty,
      reason: 'Fixture must load cleanly; errors: ${loadResult.errors}',
    );
    index = UsageIndex.build(loadResult);
  });

  // ---------------------------------------------------------------------------
  // Cross-file reference: UsedClass is referenced from consumer.dart
  // ---------------------------------------------------------------------------
  test('cross-file reference: UsedClass is marked as referenced', () {
    final usedClassElement = _findElement(loadResult, 'UsedClass');
    expect(
      usedClassElement,
      isNotNull,
      reason: 'UsedClass element must be findable in the resolved units',
    );
    expect(
      index.isReferenced(usedClassElement!),
      isTrue,
      reason: 'UsedClass is referenced from consumer.dart',
    );
  });

  // ---------------------------------------------------------------------------
  // Unreferenced: UnusedClass is never referenced
  // ---------------------------------------------------------------------------
  test('no reference: UnusedClass is not marked as referenced', () {
    final element = _findElement(loadResult, 'UnusedClass');
    expect(element, isNotNull);
    expect(
      index.isReferenced(element!),
      isFalse,
      reason: 'UnusedClass must not be referenced anywhere',
    );
  });

  // ---------------------------------------------------------------------------
  // Test-only reference: TestOnlyClass is referenced only from test/
  // This counts as usage per the spec.
  // ---------------------------------------------------------------------------
  test('test-file reference: TestOnlyClass is marked as referenced', () {
    final element = _findElement(loadResult, 'TestOnlyClass');
    expect(element, isNotNull);
    expect(
      index.isReferenced(element!),
      isTrue,
      reason:
          'TestOnlyClass is referenced from test/ — counts as usage per spec',
    );
  });

  // ---------------------------------------------------------------------------
  // Tool-only reference: ToolOnlyClass is referenced only from tool/
  // This counts as usage per the spec.
  // ---------------------------------------------------------------------------
  test('tool-file reference: ToolOnlyClass is marked as referenced', () {
    final element = _findElement(loadResult, 'ToolOnlyClass');
    expect(element, isNotNull);
    expect(
      index.isReferenced(element!),
      isTrue,
      reason:
          'ToolOnlyClass is referenced from tool/ — counts as usage per spec',
    );
  });

  // ---------------------------------------------------------------------------
  // Self-reference does not count: Consumer declares itself but that's a
  // declaration, not a usage. However, Consumer IS referenced (implicitly used
  // in bin/main.dart). Test self-reference exclusion via _PrivateClass which
  // has no references at all outside its own declaration.
  // ---------------------------------------------------------------------------
  test('unreferenced: AnotherUnusedClass is not marked as referenced', () {
    final element = _findElement(loadResult, 'AnotherUnusedClass');
    expect(element, isNotNull);
    expect(
      index.isReferenced(element!),
      isFalse,
      reason: 'AnotherUnusedClass has no references anywhere',
    );
  });

  // ---------------------------------------------------------------------------
  // Cross-file: Consumer is referenced from bin/main.dart
  // ---------------------------------------------------------------------------
  test('cross-file: Consumer (lib) is referenced from bin/main.dart', () {
    final element = _findElement(loadResult, 'Consumer');
    expect(element, isNotNull);
    expect(
      index.isReferenced(element!),
      isTrue,
      reason: 'Consumer is referenced from bin/main.dart',
    );
  });

  // ---------------------------------------------------------------------------
  // No double-counting — calling isReferenced twice on same element is stable
  // ---------------------------------------------------------------------------
  test('isReferenced is idempotent (deterministic)', () {
    final element = _findElement(loadResult, 'UnusedClass');
    expect(element, isNotNull);
    final r1 = index.isReferenced(element!);
    final r2 = index.isReferenced(element);
    expect(r1, equals(r2));
  });

  // ---------------------------------------------------------------------------
  // Empty ProjectLoadResult does not crash
  // ---------------------------------------------------------------------------
  test('UsageIndex.build handles empty ProjectLoadResult without crash', () {
    const emptyResult = ProjectLoadResult(resolved: [], errors: []);
    final emptyIndex = UsageIndex.build(emptyResult);
    // No elements to query — just ensure no exception is thrown.
    expect(emptyIndex, isNotNull);
  });
}

// ---------------------------------------------------------------------------
// Helper: finds a top-level element by name across all resolved lib files.
// ---------------------------------------------------------------------------
Element? _findElement(ProjectLoadResult loadResult, String name) {
  for (final file in loadResult.resolved) {
    final library = file.result.libraryElement;
    final clazz = library.getClass(name);
    if (clazz != null) return clazz;
    final fn = library.getTopLevelFunction(name);
    if (fn != null) return fn;
    final enm = library.getEnum(name);
    if (enm != null) return enm;
    final mixin = library.getMixin(name);
    if (mixin != null) return mixin;
  }
  return null;
}
