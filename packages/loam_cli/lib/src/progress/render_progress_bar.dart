/// Returns a progress bar string of the form `[████░░░░]`.
///
/// [current] and [total] define the filled fraction.
/// [width] is the inner width in characters (between the brackets).
///
/// Edge cases:
/// - [width] <= 0 → returns `''` (empty string).
/// - [total] <= 0 → returns an indeterminate (empty) bar `[   ]`.
/// - [current] >= [total] → returns a fully-filled bar `[████]`.
///
/// The result is always exactly `width + 2` characters wide (brackets
/// included) when [width] > 0 and [total] > 0.
String renderProgressBar({
  required int current,
  required int total,
  required int width,
}) {
  if (width <= 0) return '';
  if (total <= 0) return '[${' ' * width}]';
  final ratio = (current / total).clamp(0.0, 1.0);
  final filled = (ratio * width).round();
  final empty = width - filled;
  // U+2588 FULL BLOCK (█), U+2591 LIGHT SHADE (░)
  return '[${'█' * filled}${'░' * empty}]';
}
