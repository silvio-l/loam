# loam

> Codebase intelligence & anti-AI-slop for Dart & Flutter.

`loam` is the CLI command and pub.dev package name for **loam.dev** — a Dart-native,
semantically accurate, project-wide quality tool. It surfaces what `dart analyze`
misses: structural drift (dead code, duplication, circular dependencies, complexity
hotspots, architecture boundary violations) **and** AI-slop — with a baseline/ratchet
CI gate.

Built on the Dart `analyzer` package. Deterministic core (offline, free) plus an
optional, cache-stabilised LLM layer.

This is the CLI package of the loam.dev monorepo. For the project overview, the
founding spec and the domain glossary, see the
[repository root](https://github.com/silvio-l/loam).

## Install

```
dart pub global activate loam
```

## Commands (target)

```
loam scan      # all active rules across the whole project
loam health    # score + hotspots
loam gate      # CI: baseline/ratchet (default) | --absolute
loam slop      # anti-AI-slop layer (--llm opt-in)
loam init      # materialise config + inferred layers
loam fix       # safe auto-fixes (--safe)
```

Output format is chosen with `--format` (`human` | `sarif` | `json` | `markdown` |
`html`). `--format html` writes a self-contained `loam-report.html` you can open in a
browser to toggle findings and copy a fix-prompt for an AI agent.

## Develop

```
dart pub get
dart format --output=none --set-exit-if-changed bin lib test
dart analyze --fatal-infos --fatal-warnings
dart test
dart run bin/loam.dart scan
```

## License

MIT © 2026 Silvio Lindstedt
