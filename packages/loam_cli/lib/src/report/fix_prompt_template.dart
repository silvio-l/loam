/// Versioniertes Fix-Prompt-Template für den interaktiven HTML-Report.
///
/// Das Template ist eine Dart-Konstante und trägt den expliziten `prompt@ver`-
/// Marker gemäß CONTEXT.md (`VerdictCache`, `prompt@ver`, Invariante 5).
///
/// Design-Entscheidung (issue 07):
/// - Das Template-String-Format wird sowohl von der Dart-Funktion
///   [assembleFixPrompt] als auch vom inline JS im HTML-Report umgesetzt.
/// - Beide implementieren dieselbe triviale Assemblierung: Template-Platzhalter
///   werden einmal gesetzt, dann folgen die ausgewählten Findings in der
///   deterministischen Reihenfolge (wie vom Reporter eingebettet).
/// - Das JS im Report muss die GLEICHE Assemblierung produzieren — keep it
///   trivial (kein Sortieren, keine Transformation, nur Iteration in der
///   Einbettungsreihenfolge).
///
/// Fix-Hinweis (Determinismus):
/// - Fix-Hinweise sind per `ruleId` definiert (stabile, versionierte Map
///   [kFixHints]). Unbekannte `ruleId`s erhalten den generischen Hinweis
///   [kGenericFixHint]. Die Map ist Teil der Versionierung (`prompt@ver`):
///   eine Änderung hier erfordert eine neue `prompt@ver`.
///
/// Invariante 4 (pure renderer): Keine I/O, keine Schwellen, keine LLM-Calls.
/// Invariante 5 (reproduzierbar): Gleiche Auswahl ⇒ byte-identischer Prompt.
library;

/// Expliziter Versions-Marker für das Fix-Prompt-Template.
///
/// Bei jeder inhaltlichen Änderung am Template oder an [kFixHints] muss
/// dieser Marker auf eine neue Version gesetzt werden (z. B. `prompt@v3`).
///
/// `prompt@v2`: Zielprojekt-Identifier (`{{TARGET}}`) im Prompt-Kopf ergänzt,
/// damit der Prompt jederzeit selbst dokumentiert, gegen welches Projekt die
/// relativen Finding-Pfade aufgelöst werden müssen.
const String kPromptVersion = 'prompt@v2';

/// Das versionierte Fix-Prompt-Template.
///
/// Enthält zwei Platzhalter:
/// - `{{TARGET}}` — der Identifier des analysierten Projekts (siehe
///   [fillPromptTarget]); wird einmal je Report gesetzt.
/// - `{{FINDINGS}}` — die assemblierten Finding-Zeilen.
///
/// Kanonischer Marker `prompt@v2` ist im Text eingebettet, damit das
/// ausgegebene Template selbst seinen Version-Stamp trägt.
const String kFixPromptTemplate =
    '''
# loam.dev Fix-Prompt ($kPromptVersion)

Target project: `{{TARGET}}` — every file path below is relative to this project's root.

Please fix the following findings identified by loam.dev.
For each finding, the rule ID, file location, message, and a fix hint are provided.

## Findings

{{FINDINGS}}

## Instructions

- Fix each finding listed above.
- Do not change unrelated code.
- Preserve existing formatting and style conventions.
- If a fix requires a larger refactor, explain why and propose the smallest safe change.
''';

/// Fix-Hinweise je Rule-ID.
///
/// Diese Map ist Teil der `prompt@ver`-Versionierung. Änderungen hier
/// erfordern ein Hochzählen von [kPromptVersion].
const Map<String, String> kFixHints = {
  'unused-public-exports':
      'Remove or internalize the unused public declaration, or add it to a '
      'library export if it is intentionally public.',
};

/// Generischer Fix-Hinweis für unbekannte Rule-IDs.
const String kGenericFixHint =
    'Consult the loam.dev documentation for this rule and apply the '
    'recommended fix.';

/// Gibt den Fix-Hinweis für [ruleId] zurück.
///
/// Fällt auf [kGenericFixHint] zurück, wenn keine spezifische Beschreibung
/// vorliegt. Deterministisch: gleicher Input ⇒ gleicher Output.
String fixHintFor(String ruleId) => kFixHints[ruleId] ?? kGenericFixHint;

/// Ersetzt den `{{TARGET}}`-Platzhalter in [template] durch den Identifier des
/// analysierten Projekts.
///
/// [target] muss ein stabiler, vom Checkout-Ort unabhängiger Identifier sein
/// (typisch der Verzeichnisname des Projekt-Roots), **niemals** ein absoluter
/// Pfad — sonst bricht Invariante 5 (Reproduzierbarkeit: gleicher Code ⇒
/// byte-identischer Report). Leere Werte fallen auf einen neutralen Text
/// zurück, damit der Prompt-Kopf nie mit leeren Backticks ausgegeben wird.
///
/// Single source of truth: sowohl [assembleFixPrompt] (Dart) als auch der
/// HTML-Reporter (der den Identifier zur Embed-Zeit setzt) rufen diese
/// Funktion auf, damit beide Pfade byte-identisch bleiben.
String fillPromptTarget(String template, String target) {
  final label = target.trim().isEmpty ? 'the analysed project' : target.trim();
  return template.replaceAll('{{TARGET}}', label);
}

/// Assembliert den fertigen Fix-Prompt aus [template] und [selectedFindings].
///
/// [selectedFindings] ist eine geordnete Liste von Maps mit den Schlüsseln:
///   - `ruleId`   — String
///   - `filePath` — String (relative Pfad)
///   - `line`     — int
///   - `message`  — String
///
/// Die Reihenfolge der Einträge im Prompt entspricht exakt der Reihenfolge
/// in [selectedFindings] (deterministisch, kein internes Sortieren).
///
/// [target] ist der Identifier des analysierten Projekts (siehe
/// [fillPromptTarget]); er wird in den `{{TARGET}}`-Platzhalter des Kopfes
/// gesetzt, damit der Prompt selbst dokumentiert, worauf sich die relativen
/// Finding-Pfade beziehen.
///
/// Das inline JS im HTML-Report muss dieselbe Logik implementieren:
///   1. Den `{{TARGET}}`-Platzhalter füllen (im HTML-Report bereits zur
///      Embed-Zeit über [fillPromptTarget] gesetzt — das JS sieht ihn nicht
///      mehr).
///   2. Für jedes ausgewählte Finding eine Zeile der Form
///      `- [ruleId] filePath:line — message\n  Fix hint: <hint>`
///      erzeugen.
///   3. Die Zeilen mit `\n\n` verbinden.
///   4. Den Platzhalter `{{FINDINGS}}` im Template ersetzen.
///
/// Gleiche [selectedFindings] (+ [target]) in gleicher Reihenfolge ⇒
/// byte-identischer Rückgabe-String (Invariante 5).
String assembleFixPrompt({
  String template = kFixPromptTemplate,
  required List<Map<String, dynamic>> selectedFindings,
  required String target,
}) {
  final targeted = fillPromptTarget(template, target);

  if (selectedFindings.isEmpty) {
    return targeted.replaceAll('{{FINDINGS}}', '(no findings selected)');
  }

  final lines = selectedFindings.map((f) {
    final ruleId = f['ruleId'] as String;
    final filePath = f['filePath'] as String;
    final line = f['line'];
    final message = f['message'] as String;
    final hint = fixHintFor(ruleId);
    return '- [$ruleId] $filePath:$line — $message\n  Fix hint: $hint';
  });

  final findingsBlock = lines.join('\n\n');
  return targeted.replaceAll('{{FINDINGS}}', findingsBlock);
}
