/// Pure, side-effect-free helpers for delivering the HTML report: the default
/// file name, the platform command that opens a file in the default browser,
/// and the decision of whether auto-open is appropriate at all.
///
/// Kept deliberately free of I/O so the policy is unit-testable. The CLI layer
/// (`bin/loam.dart`) performs the actual file write and process launch — the
/// [Reporter] interface stays a pure renderer (see `reporter.dart`).
library;

/// Default file name for the self-contained HTML report when `--output` is not
/// given. Written into the current working directory.
const String defaultHtmlReportFileName = 'loam-report.html';

/// Returns the platform command (executable + arguments) that opens [filePath]
/// in the system default browser, or `null` for an unsupported platform.
///
/// Pure: it only selects the command, it never runs anything. [operatingSystem]
/// is `Platform.operatingSystem` (`'macos'`, `'linux'`, `'windows'`, …).
List<String>? browserOpenCommand(
  String filePath, {
  required String operatingSystem,
}) {
  switch (operatingSystem) {
    case 'macos':
      return ['open', filePath];
    case 'linux':
      return ['xdg-open', filePath];
    case 'windows':
      // `start` is a cmd builtin; the empty "" is the (ignored) window-title
      // argument that `start` consumes before the path.
      return ['cmd', '/c', 'start', '', filePath];
    default:
      return null;
  }
}

/// Decides whether to auto-open the report in a browser.
///
/// Interactive use only: never when output is piped/redirected ([isTty] is
/// `false`), never under CI (a non-empty `CI` environment variable), and never
/// when the user passed `--no-open` ([noOpenFlag]).
bool shouldOpenBrowser({
  required bool isTty,
  required bool noOpenFlag,
  required Map<String, String> environment,
}) {
  if (noOpenFlag) return false;
  if (!isTty) return false;
  if ((environment['CI'] ?? '').isNotEmpty) return false;
  return true;
}
