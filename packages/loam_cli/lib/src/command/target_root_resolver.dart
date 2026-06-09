import 'dart:io';

import 'package:args/args.dart';

/// Result of resolving the effective project root from command arguments.
///
/// Exactly one of [root] or [usageError] is non-null.
sealed class TargetRootResult {
  const TargetRootResult();
}

/// The resolved project root path.
final class ResolvedRoot extends TargetRootResult {
  /// Creates a [ResolvedRoot] with the given [root] path.
  const ResolvedRoot(this.root);

  /// The effective project root directory path.
  final String root;
}

/// A usage error message to be emitted on stderr with exit code 64.
final class RootUsageError extends TargetRootResult {
  /// Creates a [RootUsageError] with the given human-readable [message].
  const RootUsageError(this.message);

  /// The human-readable usage error message for stderr output.
  final String message;
}

/// Resolves the effective project root from parsed command arguments.
///
/// Precedence (locked):
/// 1. `--project-root`/`-p` explicitly set → wins (backward-compatible).
/// 2. Exactly one positional argument (`rest`) → that path is the root.
/// 3. Neither → `Directory.current.path` (current working directory).
///
/// Error case: two or more positional arguments → [RootUsageError].
/// Providing both `--project-root` and a positional is NOT an error;
/// the explicit option wins.
///
/// This class is pure (no file I/O beyond reading [Directory.current.path])
/// and fully testable with synthetic [ArgResults].
abstract final class TargetRootResolver {
  /// Resolves the project root from [argResults].
  ///
  /// Returns a [ResolvedRoot] with the effective path, or a [RootUsageError]
  /// when more than one positional argument is provided.
  static TargetRootResult resolve(ArgResults? argResults) {
    final explicitRoot = argResults?['project-root'] as String?;

    // Precedence 1: explicit --project-root wins over everything.
    if (explicitRoot != null) {
      return ResolvedRoot(explicitRoot);
    }

    final rest = argResults?.rest ?? const <String>[];

    // Error: more than one positional argument.
    if (rest.length > 1) {
      return RootUsageError(
        'Too many arguments: expected at most one project path, '
        'got ${rest.length}: ${rest.join(', ')}.\n'
        'Usage: loam <command> [<project-path>] [options]',
      );
    }

    // Precedence 2: exactly one positional → use it.
    if (rest.length == 1) {
      return ResolvedRoot(rest.first);
    }

    // Precedence 3: default to current working directory.
    return ResolvedRoot(Directory.current.path);
  }
}
