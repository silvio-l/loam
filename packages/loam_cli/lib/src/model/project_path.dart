import 'package:path/path.dart' as p;

/// The project-relative POSIX form of [absolutePath], the format of
/// `Finding.filePath`, baseline entries and inline suppression directives.
///
/// `p.relative` alone yields backslashes on Windows, so a finding would never
/// match its `// loam-ignore:` directive there. [context] defaults to the
/// host's path style; tests pass `p.windows` to cover Windows on any host.
String projectRelativePosixPath(
  String absolutePath,
  String projectRoot, {
  p.Context? context,
}) {
  final ctx = context ?? p.context;
  final rel = ctx.relative(absolutePath, from: projectRoot);
  return p.posix.joinAll(ctx.split(rel));
}
