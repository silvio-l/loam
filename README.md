# Loam

> Codebase intelligence & anti-AI-slop for Dart & Flutter.

**Loam.dev** — a Dart-native, semantically accurate, project-wide quality tool.
It surfaces what `dart analyze` misses: structural drift (dead code, duplication,
circular dependencies, complexity hotspots, architecture boundary violations)
**and** AI-slop — with a baseline/ratchet CI gate.

Built on the Dart `analyzer` package. Deterministic core (offline, free) plus an
optional, cache-stabilised LLM layer.

## Status

🚧 Early development — walking skeleton. See the founding spec in
`.scratch/loam-mvp/PRD.md` and the domain glossary in [`CONTEXT.md`](./CONTEXT.md).

## Commands (target)

```
loam scan      # all active rules across the whole project
loam health    # score + hotspots
loam gate      # CI: baseline/ratchet (default) | --absolute
loam slop      # anti-AI-slop layer (--llm opt-in)
loam init      # materialise config + inferred layers
loam fix       # safe auto-fixes (--safe)
```

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
