// Positive fixture: Image.asset without semanticLabel → rule MUST fire.
import 'package:flutter/widgets.dart';

/// A widget that uses Image.asset without a semantic label.
/// The rule should report a finding here.
Object buildUnlabeledAsset() => Image.asset('assets/logo.png');

/// A widget that uses Image.network without a semantic label.
/// The rule should report a finding here too.
Object buildUnlabeledNetwork() => Image.network('https://example.com/img.png');

/// A widget that uses Image.file without a semantic label.
Object buildUnlabeledFile() => Image.file(Object());

/// A widget that uses Image.memory without a semantic label.
Object buildUnlabeledMemory() => Image.memory([0, 1, 2]);

/// A widget that uses the unnamed Image constructor without a semantic label.
Object buildUnlabeledUnnamed() => const Image();
