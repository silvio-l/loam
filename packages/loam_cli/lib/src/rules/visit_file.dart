import 'package:analyzer/dart/ast/ast.dart';

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/project_path.dart';
import 'generated_file.dart';

/// Runs the findings-collecting visitor built by [create] over [file]'s unit
/// and returns what it collected — the shared [FileRule.runFile] body of the
/// visitor-based rules.
///
/// Generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, gen-l10n)
/// are skipped. [create] receives the project-relative POSIX path (relative
/// to [projectRoot]) and the list the visitor appends its findings to.
List<Finding> visitFile(
  LoadedFile file,
  String projectRoot,
  AstVisitor<void> Function(String relativePath, List<Finding> findings) create,
) {
  if (isGeneratedDartFile(file.path)) return const [];
  final findings = <Finding>[];
  file.parsed.unit.accept<void>(
    create(projectRelativePosixPath(file.path, projectRoot), findings),
  );
  return findings;
}

/// Runs the visitor built by [create] over the resolved unit of every
/// non-generated file in [result] and returns the collected findings — the
/// shared [Rule.run] body of visitor-based rules that need resolved elements.
List<Finding> visitResolvedFiles(
  ProjectLoadResult result,
  String projectRoot,
  AstVisitor<void> Function(String relativePath, List<Finding> findings) create,
) {
  final findings = <Finding>[];
  for (final file in result.resolved) {
    if (isGeneratedDartFile(file.path)) continue;
    file.result.unit.accept<void>(
      create(projectRelativePosixPath(file.path, projectRoot), findings),
    );
  }
  return findings;
}
