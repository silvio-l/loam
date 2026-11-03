import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/architecture_config.dart';

/// The result of [LayerDetector.detect]: the detected **Layers**
/// (`name -> project-relative dir`) and the **Boundaries** derived from them.
class DetectedArchitecture {
  /// Creates a detection result.
  const DetectedArchitecture({required this.layers, required this.boundaries});

  /// No layers detected: nothing is written, nothing is enforced.
  const DetectedArchitecture.none() : layers = const {}, boundaries = const [];

  /// Layer name -> project-relative directory (posix separators), sorted by name.
  final Map<String, String> layers;

  /// Forbidden edges between the detected layers, sorted by importing layer.
  final List<LayerBoundary> boundaries;

  /// Whether nothing was detected.
  bool get isEmpty => layers.isEmpty;
}

/// Detects architecture **Layers** from the directory structure under `lib/`
/// (Zero-Config, deterministic, no I/O beyond listing directories).
///
/// Conservative by design (internal-notes: a missing layer is better than
/// a wrong one): only well-known layer directory names directly under `lib/`
/// count, a directory must contain Dart files, and a result needs at least one
/// derivable forbidden edge - otherwise nothing is detected. Boundaries
/// are derived only for the unambiguous downward-dependency direction.
abstract final class LayerDetector {
  /// Tier of every recognised directory name. Lower tiers are the stable
  /// foundation; higher tiers sit on top of them.
  static const Map<String, int> _tierByName = {
    // 0 - foundation
    'core': 0, 'common': 0, 'shared': 0, 'utils': 0,
    // 1 - domain
    'domain': 1, 'models': 1, 'entities': 1,
    // 2 - data / infrastructure
    'data': 2, 'repositories': 2, 'services': 2,
    // 3 - presentation
    'presentation': 3, 'ui': 3, 'features': 3, 'screens': 3, 'pages': 3,
  };

  /// Which higher tiers a layer of the given tier must not import. The
  /// foundation tier only forbids the presentation tier: foundation code
  /// often legitimately touches models or services (e.g. a core HTTP client).
  static const Map<int, List<int>> _deniedTiers = {
    0: [3],
    1: [2, 3],
    2: [3],
  };

  /// Detects layers under [projectRoot]`/lib`.
  static DetectedArchitecture detect(String projectRoot) {
    final lib = Directory(p.join(projectRoot, 'lib'));
    if (!lib.existsSync()) return const DetectedArchitecture.none();

    final layers = <String, String>{};
    for (final entity in lib.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (!_tierByName.containsKey(name)) continue;
      if (!_containsDart(entity)) continue;
      layers[name] = 'lib/$name';
    }
    if (layers.length < 2) return const DetectedArchitecture.none();

    final names = layers.keys.toList()..sort();
    final boundaries = <LayerBoundary>[];
    for (final from in names) {
      final denied = _deniedTiers[_tierByName[from]!];
      if (denied == null) continue;
      final deny = [
        for (final to in names)
          if (denied.contains(_tierByName[to])) to,
      ];
      if (deny.isNotEmpty) {
        boundaries.add(LayerBoundary(from: from, deny: deny));
      }
    }
    // Layers without a single forbidden edge protect nothing: write nothing.
    if (boundaries.isEmpty) return const DetectedArchitecture.none();
    return DetectedArchitecture(
      layers: {for (final n in names) n: layers[n]!},
      boundaries: boundaries,
    );
  }

  static bool _containsDart(Directory dir) => dir
      .listSync(recursive: true, followLinks: false)
      .any((e) => e is File && e.path.endsWith('.dart'));
}
