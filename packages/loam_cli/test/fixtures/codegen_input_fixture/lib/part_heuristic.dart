/// Library with a generated part directive — structural fallback heuristic.
///
/// Any public class in a library that declares `part '*.g.dart'` is treated
/// as a code-gen input via the fallback heuristic path.
library;

part 'part_heuristic.g.dart';

/// A class whose library has a `part '*.g.dart'` directive.
/// Its public members should be classified as code-gen inputs (fallback).
class PartHeuristicClass {
  /// A public method — classified as code-gen input via fallback.
  String heuristicMethod() => 'heuristic';
}
