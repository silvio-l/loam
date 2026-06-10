import 'package:path/path.dart' as p;

/// Returns `true` when [path] refers to a generated Dart file.
///
/// The check is purely path-based (no I/O, no element model). Recognised
/// generated artefacts:
/// - `*.g.dart` — build_runner JSON/serialisation output
/// - `*.freezed.dart` — Freezed union/value class output
/// - `*.mocks.dart` — Mockito/mocktail generated mocks
/// - Flutter `gen-l10n` output (`app_localizations.dart` +
///   `app_localizations_<locale>.dart`) — see [_isFlutterGenL10n].
///
/// This is the single source of truth used by [ImportGraph] and
/// [PublicApiCollector] to exclude generated files from analysis.
bool isGeneratedDartFile(String path) {
  final basename = p.basename(path);
  return basename.endsWith('.g.dart') ||
      basename.endsWith('.freezed.dart') ||
      basename.endsWith('.mocks.dart') ||
      _isFlutterGenL10n(basename);
}

/// Recognises Flutter `gen-l10n` output by its **default** naming convention:
/// the umbrella file `app_localizations.dart` plus one
/// `app_localizations_<locale>.dart` per locale.
///
/// These files are emitted by `flutter gen-l10n` (the umbrella class imports
/// every locale subclass via `lookupAppLocalizations`, while each subclass
/// `extends AppLocalizations` and imports the umbrella back). That mutual
/// import is an *inherent*, non-actionable cycle in generated code — excluding
/// these files prevents a `circular-dependencies` false positive (and keeps
/// `unused-public-exports` from flagging generated localisation members).
///
/// Limitation (documented on purpose): `output-localization-file` /
/// `output-class` in `l10n.yaml` are configurable. Non-default names are not
/// recognised here without reading `l10n.yaml`; the default convention covers
/// the overwhelming majority of projects and keeps this check I/O-free.
bool _isFlutterGenL10n(String basename) {
  return basename == 'app_localizations.dart' ||
      (basename.startsWith('app_localizations_') && basename.endsWith('.dart'));
}
