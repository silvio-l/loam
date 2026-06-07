# loam.dev — examples

`loam` is a command-line tool. The primary way to use it is the `loam` executable;
it also exposes a small public Dart library for programmatic use.

> The product is **loam.dev**; `loam` is the CLI command and the pub.dev package name.

## Install

```bash
dart pub global activate loam
# or, on Apple Silicon macOS / Linux:
brew install silvio-l/loam/loam
```

## Onboard an existing repository

Turn an established codebase green, then keep it green via the baseline/ratchet gate:

```bash
loam scan                 # full audit: project-wide unused public API, whole repo
loam baseline --write     # freeze today's accepted findings to baseline.json
loam gate                 # CI from now on — ratchet: only NEW findings fail (exit 1)
```

Greenfield project? Skip the baseline and enforce zero findings directly:

```bash
loam gate --absolute      # all findings evaluated against threshold 0
```

## Output formats

Every command that produces findings honours the global `--format` flag:

```bash
loam scan --format human                       # default, readable terminal output
loam scan --format json                        # machine-readable, for tooling/agents
loam scan --format sarif                       # CI code-scanning (GitHub, GitLab, …)
loam scan --format markdown                     # PR / docs embedding
loam scan --format html > loam-report.html      # self-contained, offline report
```

The HTML report is a single offline file: browse findings by rule, severity and
file, select findings, and copy a deterministic, versioned fix-prompt for an AI
coding agent. It is a pure renderer — no server, no hosting, no LLM calls.

## Configure with `loam.yaml`

Scaffold a commented config in the project root (existing files are never
overwritten):

```bash
loam init
```

```yaml
# loam.yaml
rules:
  unused-public-exports: false   # disable a rule project-wide (it is not run at all)

ignore:
  - "lib/generated/**"            # drop whole paths from the audit (project-relative globs)
  - "**/*.g.dart"
```

Suppress a single finding at its source — same line or the line immediately above,
reason mandatory, only the named rule:

```dart
final unusedHelper = 42; // loam-ignore: unused-public-exports – kept for the public 1.x API
```

Suppression acts before the baseline/gate, so suppressed findings never fill the
baseline nor trip the gate. A rule toggle changes the `rulesetVersion`; path and
inline suppression do not.

## Programmatic use (Dart library)

The package also exports a small public surface (`Finding`, `Severity`, `Rule`,
`ProjectLoader`, …) for embedding analysis in your own tooling:

```dart
import 'package:loam/loam.dart';

void main() {
  // Findings are the core value type produced by every rule.
  const finding = Finding(
    ruleId: 'unused-public-exports',
    severity: Severity.warning,
    filePath: 'lib/widgets/old_button.dart',
    line: 12,
    message: 'Public class OldButton is never referenced in the project.',
    fingerprint: 'a1b2c3d4e5f60718',
  );

  print('${finding.severity.name}: ${finding.message} '
      '(${finding.filePath}:${finding.line})');
}
```

See the [Developer & Tool Guide](https://github.com/silvio-l/loam/blob/main/docs/developer-guide.md)
for the full command reference and concepts.
