/// Fixture library for ComplexityHotspotsRule tests.
///
/// Default thresholds: cyclomatic > 20, cognitive > 30.
///
/// Contains:
/// - [trivialFunction]: cyclomatic=1, cognitive=0 → must NOT be reported.
/// - [justUnderCyclomatic]: cyclomatic=20, cognitive=19 → must NOT be reported
///   (threshold is strictly-above 20).
/// - [justOverCyclomatic]: cyclomatic=21, cognitive=20 → MUST be reported
///   (cyclomatic 21 > 20 breaches the threshold).
/// - [highCognitive]: cyclomatic=8, cognitive=21 — breaches cognitive when
///   threshold is lowered for testing. Also breaches default cognitive (21>15)
///   when lower threshold used. With the default cognitive threshold of 30,
///   this is below the threshold and used only for threshold-boundary tests.
///   See [veryHighCognitive] for the default-threshold cognitive fixture.
/// - [veryHighCognitive]: cognitive=31 → MUST be reported (cognitive 31 > 30).
/// - [suppressedHotspot]: cyclomatic=21 → suppressed via loam-ignore.
library;

/// Trivial function — no decision points.
/// cyclomatic=1, cognitive=0. Must NOT be reported.
void trivialFunction() {
  final x = 42;
  print(x);
}

/// cyclomatic=20, cognitive=19 — just UNDER the default cyclomatic threshold.
/// Must NOT be reported (20 is not > 20).
int justUnderCyclomatic(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
) {
  // 19 if-statements + base 1 = cyclomatic 20
  if (a > 0) print('a1');
  if (b > 0) print('b1');
  if (c > 0) print('c1');
  if (d > 0) print('d1');
  if (e > 0) print('e1');
  if (f > 0) print('f1');
  if (g > 0) print('g1');
  if (h > 0) print('h1');
  if (a + b > 10) print('ab');
  if (b + c > 10) print('bc');
  if (c + d > 10) print('cd');
  if (d + e > 10) print('de');
  if (e + f > 10) print('ef');
  if (f + g > 10) print('fg');
  if (g + h > 10) print('gh');
  if (a + c > 20) print('ac');
  if (b + d > 20) print('bd');
  if (c + e > 20) print('ce');
  if (d + f > 20) print('df');
  return a + b + c + d + e + f + g + h;
}

/// cyclomatic=21 — just OVER the default cyclomatic threshold of 20.
/// MUST be reported (cyclomatic 21 > 20).
int justOverCyclomatic(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
  int i,
) {
  // 20 if-statements + base 1 = cyclomatic 21
  if (a > 0) print('a1');
  if (b > 0) print('b1');
  if (c > 0) print('c1');
  if (d > 0) print('d1');
  if (e > 0) print('e1');
  if (f > 0) print('f1');
  if (g > 0) print('g1');
  if (h > 0) print('h1');
  if (i > 0) print('i1');
  if (a + b > 10) print('ab');
  if (b + c > 10) print('bc');
  if (c + d > 10) print('cd');
  if (d + e > 10) print('de');
  if (e + f > 10) print('ef');
  if (f + g > 10) print('fg');
  if (g + h > 10) print('gh');
  if (h + i > 10) print('hi');
  if (a + c > 20) print('ac');
  if (b + d > 20) print('bd');
  if (c + e > 20) print('ce');
  return a + b + c + d + e + f + g + h + i;
}

/// High cognitive complexity via deep nesting.
///
/// Cognitive trace (ComplexityCalculator rules):
///   depth=0: if → 1+0=1, enter depth 1
///   depth=1: for → 1+1=2, enter depth 2
///   depth=2: if → 1+2=3, enter depth 3
///   depth=3: if → 1+3=4, enter depth 4
///   depth=4: if → 1+4=5, enter depth 5
///   depth=5: if → 1+5=6, enter depth 6
///   depth=6: if → 1+6=7, enter depth 7
///   Running total: 1+2+3+4+5+6+7 = 28 (not > 30 default threshold)
///
/// Used for threshold-boundary tests with a lower cognitive threshold (e.g.
/// [kDefaultCognitiveThreshold] = 15 for the lowered-threshold test).
/// cyclomatic = 1 + 7 (seven ifs + one for) = 9. cognitive = 28.
String highCognitive(int n, List<int> items) {
  if (n > 0) {
    for (final item in items) {
      if (item > n) {
        if (item > n * 2) {
          if (item > n * 3) {
            if (item > n * 4) {
              if (item > n * 5) {
                return 'extreme: $item';
              }
              return 'very large: $item';
            }
            return 'large: $item';
          }
          return 'medium: $item';
        }
        return 'small-medium: $item';
      }
    }
  }
  return 'small';
}

/// Very high cognitive complexity via deep nesting — breaches default threshold.
///
/// Cognitive trace (ComplexityCalculator rules):
///   depth=0: if → 1+0=1, enter depth 1
///   depth=1: for → 1+1=2, enter depth 2
///   depth=2: if → 1+2=3, enter depth 3
///   depth=3: if → 1+3=4, enter depth 4
///   depth=4: if → 1+4=5, enter depth 5
///   depth=5: if → 1+5=6, enter depth 6
///   depth=6: if → 1+6=7, enter depth 7
///   depth=7: if → 1+7=8, enter depth 8
///   Running total: 1+2+3+4+5+6+7+8 = 36 (> 30 default threshold)
///
/// cyclomatic = 1 + 8 (eight ifs + one for) = 10. cognitive = 36.
/// MUST be reported with default thresholds (cognitive 36 > 30).
String veryHighCognitive(int n, List<int> items) {
  if (n > 0) {
    for (final item in items) {
      if (item > n) {
        if (item > n * 2) {
          if (item > n * 3) {
            if (item > n * 4) {
              if (item > n * 5) {
                if (item > n * 6) {
                  return 'extreme: $item';
                }
                return 'very large: $item';
              }
              return 'large: $item';
            }
            return 'medium-large: $item';
          }
          return 'medium: $item';
        }
        return 'small-medium: $item';
      }
    }
  }
  return 'small';
}

/// A function that breaches the cyclomatic threshold but is suppressed.
/// cyclomatic=21. Suppressed via loam-ignore on the immediately preceding line.
// loam-ignore: complexity-hotspots – test: intentional hotspot, suppressed for fixture
int suppressedHotspot(
  int a,
  int b,
  int c,
  int d,
  int e,
  int f,
  int g,
  int h,
  int i,
) {
  // 20 if-statements + base 1 = cyclomatic 21
  if (a > 0) print('a1');
  if (b > 0) print('b1');
  if (c > 0) print('c1');
  if (d > 0) print('d1');
  if (e > 0) print('e1');
  if (f > 0) print('f1');
  if (g > 0) print('g1');
  if (h > 0) print('h1');
  if (i > 0) print('i1');
  if (a + b > 10) print('ab');
  if (b + c > 10) print('bc');
  if (c + d > 10) print('cd');
  if (d + e > 10) print('de');
  if (e + f > 10) print('ef');
  if (f + g > 10) print('fg');
  if (g + h > 10) print('gh');
  if (h + i > 10) print('hi');
  if (a + c > 20) print('ac');
  if (b + d > 20) print('bd');
  if (c + e > 20) print('ce');
  return a + b + c + d + e + f + g + h + i;
}
