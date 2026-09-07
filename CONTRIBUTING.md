# Contributing to loam.dev

Thanks for your interest! **loam.dev** is a Dart CLI for codebase intelligence &
anti-AI-slop on Dart/Flutter projects.

> **Naming.** The product is **loam.dev**; `loam` (no `.dev`) is only the CLI
> command and the pub.dev package name.

loam.dev is solo-maintained. **Bug reports and feature ideas** are welcome via
[GitHub Issues](https://github.com/silvio-l/loam/issues) or
silvio-lindstedt@outlook.com. Pull requests are welcome too — for anything
beyond a small fix, please open an issue first to align on the approach
before you invest the work. The notes below keep changes consistent.

Participation is governed by the [Code of Conduct](./CODE_OF_CONDUCT.md).

## Project layout

This is a monorepo; the Dart package lives in `packages/loam_cli/`. See the
**[Developer & Tool Guide](docs/developer-guide.md)** for core concepts, CLI
commands, and output formats.

## Local quality gates

Run from `packages/loam_cli/`:

```bash
dart pub get
dart format --output=none --set-exit-if-changed bin lib test
dart analyze --fatal-infos --fatal-warnings
dart test
```

loam.dev **dogfoods itself**: it must report no dead/unused public code in its own
CLI. Keep this green —

```bash
dart run bin/loam.dart gate --absolute --project-root .
```

The same checks run in CI (`.github/workflows/qa.yml`) and as a local pre-push
gate.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org/) — `feat:`, `fix:`,
  `chore:`, `docs:`, `ci:`, …
- No AI co-author / `Co-Authored-By` trailers and no AI author/committer
  identities — these are stripped and blocked by git hooks.

## Activate the repo hooks (once per clone)

```bash
git config core.hooksPath .githooks
```
