// Negative fixture: excludeFromSemantics: true → rule must NOT fire.
import 'package:flutter/widgets.dart';

/// Decorative image explicitly excluded from semantics — no finding expected.
Object buildExcluded() =>
    Image.asset('assets/decoration.png', excludeFromSemantics: true);

/// Network image excluded from semantics — no finding.
Object buildNetworkExcluded() =>
    Image.network('https://example.com/bg.png', excludeFromSemantics: true);

/// Unnamed constructor with excludeFromSemantics — no finding.
Object buildUnnamedExcluded() => const Image(excludeFromSemantics: true);
