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
///   [kGenericFixHint]. Die Map ist Teil der Versionierung (`prompt@v1`):
///   eine Änderung hier erfordert eine neue `prompt@ver`.
///
/// Invariante 4 (pure renderer): Keine I/O, keine Schwellen, keine LLM-Calls.
/// Invariante 5 (reproduzierbar): Gleiche Auswahl ⇒ byte-identischer Prompt.
library;

/// Expliziter Versions-Marker für das Fix-Prompt-Template.
///
/// Bei jeder inhaltlichen Änderung am Template oder an [kFixHints] muss
/// dieser Marker auf eine neue Version gesetzt werden (z. B. `prompt@v2`).
const String kPromptVersion = 'prompt@v1';

/// Das versionierte Fix-Prompt-Template.
///
/// Enthält einen einzigen Platzhalter `{{FINDINGS}}`, der durch die
/// assemblierten Finding-Zeilen ersetzt wird.
///
/// Kanonischer Marker `prompt@v1` ist im Text eingebettet, damit das
/// ausgegebene Template selbst seinen Version-Stamp trägt.
const String kFixPromptTemplate =
    '''
# loam.dev Fix-Prompt ($kPromptVersion)

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
/// Diese Map ist Teil der `prompt@v1`-Versionierung. Änderungen hier
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
/// Das inline JS im HTML-Report muss dieselbe Logik implementieren:
///   1. Für jedes ausgewählte Finding eine Zeile der Form
///      `- [ruleId] filePath:line — message\n  Fix hint: <hint>`
///      erzeugen.
///   2. Die Zeilen mit `\n\n` verbinden.
///   3. Den Platzhalter `{{FINDINGS}}` im Template ersetzen.
///
/// Gleiche [selectedFindings] in gleicher Reihenfolge ⇒ byte-identischer
/// Rückgabe-String (Invariante 5).
String assembleFixPrompt({
  String template = kFixPromptTemplate,
  required List<Map<String, dynamic>> selectedFindings,
}) {
  if (selectedFindings.isEmpty) {
    return template.replaceAll('{{FINDINGS}}', '(no findings selected)');
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
  return template.replaceAll('{{FINDINGS}}', findingsBlock);
}
