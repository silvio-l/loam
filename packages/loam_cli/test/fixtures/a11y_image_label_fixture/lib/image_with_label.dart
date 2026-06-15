// Negative fixture: semanticLabel present → rule must NOT fire.
import 'package:flutter/widgets.dart';

/// Has semanticLabel: 'Company logo' — no finding expected.
Object buildWithLabel() =>
    Image.asset('assets/logo.png', semanticLabel: 'Company logo');

/// Has semanticLabel: '' (empty string, conscious choice) — no finding.
Object buildWithEmptyLabel() =>
    Image.asset('assets/decoration.png', semanticLabel: '');

/// Network image with a semantic label — no finding.
Object buildNetworkWithLabel() =>
    Image.network('https://example.com/img.png', semanticLabel: 'Hero banner');
