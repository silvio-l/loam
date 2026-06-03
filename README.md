# loam.dev

> Codebase intelligence & anti-AI-slop for Dart & Flutter.

**loam.dev** — a Dart-native, semantically accurate, project-wide quality tool.
(`loam` is the CLI command and pub.dev package name; the tool itself is **loam.dev**.)
It surfaces what `dart analyze` misses: structural drift (dead code, duplication,
circular dependencies, complexity hotspots, architecture boundary violations)
**and** AI-slop — with a baseline/ratchet CI gate.

Built on the Dart `analyzer` package. Deterministic core (offline, free) plus an
optional, cache-stabilised LLM layer.

## Monorepo layout

This repository holds everything that makes up loam.dev:

| Path | What |
|---|---|
| [`packages/loam_cli/`](./packages/loam_cli/) | The Dart CLI (pub.dev package `loam`). The actual tool. |
| [`web/`](./web/) | Promotional / documentation website (static, free-tier hosting). Scaffold. |
| [`skill/`](./skill/) | Claude skill/plugin that drives the `loam` CLI for agents. Scaffold. |
| [`docs/`](./docs/) | Founding spec ([`PRD.md`](./docs/PRD.md)) and architecture decisions ([`adr/`](./docs/adr/)). |
| [`CONTEXT.md`](./CONTEXT.md) | Domain glossary — canonical vocabulary. Read before changing code. |

## Status

🚧 Early development — walking skeleton. See the founding spec in
[`docs/PRD.md`](./docs/PRD.md) and the domain glossary in [`CONTEXT.md`](./CONTEXT.md).

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

The Dart package lives in `packages/loam_cli/`:

```
cd packages/loam_cli
dart pub get
dart format --output=none --set-exit-if-changed bin lib test
dart analyze --fatal-infos --fatal-warnings
dart test
dart run bin/loam.dart scan
```

## License

MIT © 2026 Silvio Lindstedt
