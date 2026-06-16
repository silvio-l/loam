/// Decides whether live progress should be displayed.
///
/// Pure function — no I/O. Mirrors the [shouldOpenBrowser] pattern in
/// `report/browser_launcher.dart`.
///
/// Precedence (highest to lowest):
/// 1. [noProgressFlag] — CLI `--no-progress` passed: always off.
/// 2. `LOAM_NO_PROGRESS` env var (non-empty): off.
/// 3. `CI` env var (non-empty): off (running under CI).
/// 4. [isTty] is `false` (pipe / redirect): off.
/// 5. Default: on.
bool shouldShowProgress({
  required bool isTty,
  required bool noProgressFlag,
  required Map<String, String> environment,
}) {
  if (noProgressFlag) return false;
  if ((environment['LOAM_NO_PROGRESS'] ?? '').isNotEmpty) return false;
  if ((environment['CI'] ?? '').isNotEmpty) return false;
  if (!isTty) return false;
  return true;
}
