/// The in-code mirror of the package version.
///
/// **Single source of truth is `packages/loam_cli/pubspec.yaml` (`version:`).**
/// This constant exists because a compiled AOT binary (Homebrew / pub global)
/// has no pubspec beside it to read at runtime, so the version must be baked in.
///
/// It can never silently drift from the pubspec: `tool/docs-attest.sh check`
/// (run by the pre-commit hook, the `dart test` gate, and the pre-push hook)
/// fails the build if this constant differs from the pubspec version. Bump both
/// together with `tool/set-version.sh X.Y.Z`.
const String loamVersion = '0.1.2';
