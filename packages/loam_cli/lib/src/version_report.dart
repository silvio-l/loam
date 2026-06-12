import 'update/install_channel.dart';
import 'version.dart';

/// Renders the `loam --version` output (a pure function — no I/O).
///
/// Line 1 is the bare, greppable `loam <version>` (so `loam --version` parses
/// cleanly for agents and humans alike). Line 2 names the install channel and
/// the resolved executable path, so a reader can immediately tell **which**
/// binary just ran and **how** to upgrade it — the exact ambiguity that let a
/// stale Homebrew binary masquerade as freshly updated.
///
/// The version comes from [loamVersion] — the **same** constant the scan footer
/// renders (`toolVersion: loamVersion`). The two can therefore never disagree:
/// `loam --version` and the footer are one source of truth by construction.
String formatVersionInfo(InstallInfo info) =>
    'loam $loamVersion\n'
    'install: ${info.channelLabel} · ${info.executablePath}';
