#!/usr/bin/env bash
# Regenerates the interactive demo report embedded on the website
# (web/public/demo-report.html). Scaffolds a small, deliberately-messy demo
# Dart package ("shopcart") that triggers one finding of every live rule —
# unused public API, a circular dependency and a complexity hotspot — then
# runs loam from source to render the self-contained HTML report.
#
# Deterministic: same source + ruleset => byte-identical report. Re-run after
# changing the report renderer or the rule set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/web/public/demo-report.html"
# The report titles itself after the project-root basename, so build under one.
WORK="$(mktemp -d)/shopcart"
mkdir -p "$WORK/lib/models" "$WORK/lib/services"
trap 'rm -rf "$(dirname "$WORK")"' EXIT

cat > "$WORK/pubspec.yaml" <<'EOF'
name: shopcart
description: Demo project for the loam.dev report preview.
environment:
  sdk: ">=3.0.0 <4.0.0"
EOF

cat > "$WORK/lib/models/order.dart" <<'EOF'
/// A customer order.
class Order {
  Order(this.id, this.totalCents);
  final String id;
  final int totalCents;
}

/// Left over from a migration that already shipped — nothing references it.
class LegacyOrderDraft {
  LegacyOrderDraft(this.ref);
  final String ref;
  String describe() => 'draft:$ref';
}
EOF

cat > "$WORK/lib/services/cart_service.dart" <<'EOF'
import '../models/order.dart';
import 'checkout_service.dart';
import 'pricing_engine.dart';

/// Builds a cart and hands it to checkout.
class CartService {
  CartService(this._checkout, this._pricing);
  final CheckoutService _checkout;
  final PricingEngine _pricing;

  Order place(String id, int cents, String tier) {
    final discount = _pricing.discountFor(
      Order(id, cents), tier, true, 1200,
      const ['SAVE10', 'VIP-X', 'SEASON-Q4'], const ['EU', 'US'],
    );
    return _checkout.finalize(Order(id, cents - discount));
  }
}
EOF

cat > "$WORK/lib/services/checkout_service.dart" <<'EOF'
import '../models/order.dart';
import 'cart_service.dart';

/// Finalizes an order. Imports CartService back -> circular dependency.
class CheckoutService {
  CartService? boundCart;
  Order finalize(Order o) => o;
}
EOF

cat > "$WORK/lib/services/pricing_engine.dart" <<'EOF'
import '../models/order.dart';

/// Computes discounts. Grew one special case at a time — now a god-function.
class PricingEngine {
  int discountFor(Order order, String tier, bool firstTime, int loyaltyPoints,
      List<String> coupons, List<String> regions) {
    var pct = 0;
    if (tier == 'gold') {
      pct += 15;
    } else if (tier == 'silver') {
      pct += 10;
    } else if (tier == 'bronze') {
      pct += 5;
    }
    if (firstTime) pct += 5;
    if (loyaltyPoints > 1000) {
      pct += 8;
    } else if (loyaltyPoints > 500) {
      pct += 4;
    } else if (loyaltyPoints > 100) {
      pct += 2;
    }
    for (final c in coupons) {
      if (c == 'SAVE10') {
        pct += 10;
      } else if (c == 'SAVE20') {
        pct += 20;
      } else if (c.startsWith('VIP')) {
        if (tier == 'gold') {
          pct += 12;
        } else if (tier == 'silver') {
          pct += 8;
        } else {
          pct += 4;
        }
      } else if (c.startsWith('SEASON')) {
        for (final r in regions) {
          if (r == 'EU') {
            pct += 3;
          } else if (r == 'US') {
            if (firstTime) {
              pct += 5;
            } else {
              pct += 2;
            }
          } else if (r == 'APAC') {
            pct += 1;
          }
        }
      }
    }
    if (order.totalCents > 100000) {
      pct += 5;
    } else if (order.totalCents > 50000) {
      pct += 3;
    }
    if (tier == 'gold' && firstTime && loyaltyPoints > 500) pct += 3;
    if (pct > 50) pct = 50;
    if (pct < 0) pct = 0;
    return (order.totalCents * pct) ~/ 100;
  }
}
EOF

echo "Generating demo report -> $OUT"
( cd "$ROOT/packages/loam_cli" \
  && dart run bin/loam.dart scan "$WORK" --format html --no-open \
       --no-update-check --output "$OUT" )
echo "Done."
