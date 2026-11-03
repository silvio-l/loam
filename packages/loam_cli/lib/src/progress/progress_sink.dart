/// Abstract sink that receives semantic progress events from compute layers.
///
/// Compute layers ([ProjectLoader], [AnalysisRunner]) fire events into this
/// interface — they have no knowledge of stderr, ANSI codes, or terminal
/// geometry (Invariant 1: no CLI coupling in the loader/runner layer).
///
/// Implementations:
/// - [NoopProgressSink] — default for library callers, drops everything.
/// - `NoticeOnlySink` — CLI runs with progress display off: only notices.
/// - `TtyProgressRenderer` — renders a live bar to stderr in the CLI layer.
abstract class ProgressSink {
  /// Called when a new phase begins.
  ///
  /// [label] is the human-readable phase name (e.g. `'Lade Projekt'`).
  /// [total] is the expected number of [advance] calls for this phase,
  /// or `null` for indeterminate phases.
  void startPhase(String label, {int? total});

  /// Records one unit of progress within the current phase.
  ///
  /// [delta] is the number of units completed (default 1).
  void advance([int delta = 1]);

  /// Signals that the current phase has ended.
  ///
  /// Implementations typically clear the progress line here so that subsequent
  /// output (report, error messages) is not interleaved with the bar.
  void endPhase();

  /// A one-line message the user should see even without a progress bar
  /// (e.g. the analyzer store failed and the run continues without it).
  /// The CLI prints it to stderr; compute layers never write there directly.
  void notice(String message);
}

/// A no-op implementation of [ProgressSink] used when progress display is off.
///
/// All methods are empty; no I/O is performed. This is the default sink
/// injected into [ProjectLoader] and [AnalysisRunner], so callers never need
/// a `null` check (Design: no `if (progress != null)` in compute paths).
class NoopProgressSink implements ProgressSink {
  /// Creates a [NoopProgressSink].
  const NoopProgressSink();

  @override
  void startPhase(String label, {int? total}) {}

  @override
  void advance([int delta = 1]) {}

  @override
  void endPhase() {}

  @override
  void notice(String message) {}
}
