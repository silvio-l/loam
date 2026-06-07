import 'dart:convert';

import 'package:path/path.dart' as p;

import '../model/finding.dart';
import 'fix_prompt_template.dart';
import 'reporter.dart';

/// Self-contained, interactive HTML reporter.
///
/// Emits a single, self-contained HTML page — no CDN, no external fonts,
/// no external scripts or stylesheets. Findings are embedded as a structured
/// JSON block (`<script type="application/json">`) and rendered client-side
/// via inline JavaScript.
///
/// Browsable by Rule ID, Severity, and file. Each Finding shows file, line,
/// and message as code-context. Findings are individually selectable; the
/// selection feeds a deterministic Fix-Prompt (versioniertes Template,
/// `prompt@ver`) that can be copied to the clipboard via an inline button.
///
/// Issue 07 extensions (additive):
/// - Per-finding selection checkboxes (AC1).
/// - `FixPromptTemplate` embedded as a `<script type="text/x-loam-template">`
///   block (AC2); the JS reads it and fills `{{FINDINGS}}` client-side.
/// - Deterministic JS assembly mirrors [assembleFixPrompt] from
///   [fix_prompt_template.dart] (AC3); same selection ⇒ byte-identical prompt.
/// - Per-finding: ruleId, file:line, message, fix-hint in prompt (AC4).
/// - Copy-to-Clipboard button (AC5).
/// - No logic/thresholds/LLM-calls added (Invariante 4 / D9) (AC6).
///
/// Invariant 4 (pure renderer): no I/O, no exit-code logic, no thresholds.
/// Invariant 5 (reproducible): no timestamps, no absolute paths in content;
/// same input always produces a byte-identical string.
class HtmlReporter implements Reporter {
  const HtmlReporter();

  @override
  String render(ReportPayload payload) {
    final relFindings = payload.findings
        .map((f) => _buildFindingMap(f, payload.projectRoot))
        .toList();

    final jsonData = const JsonEncoder.withIndent('  ').convert({
      'tool': 'loam',
      'toolVersion': payload.toolVersion,
      'ruleset': payload.rulesetVersion,
      'findings': relFindings,
    });

    // Fix-hints map: embed as JSON so the JS can look them up without
    // hard-coding them. Built from the same source as the Dart assembler
    // (kFixHints + kGenericFixHint) — single source of truth, deterministic.
    final fixHintsJson = const JsonEncoder.withIndent(
      '  ',
    ).convert({...kFixHints, '__generic__': kGenericFixHint});

    // Count by severity for the summary header.
    final counts = <Severity, int>{
      Severity.error: 0,
      Severity.warning: 0,
      Severity.info: 0,
    };
    for (final f in payload.findings) {
      counts[f.severity] = (counts[f.severity] ?? 0) + 1;
    }
    final total = payload.findings.length;

    final title = 'loam.dev HTML-Report';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$title</title>
<style>
${_css()}
</style>
</head>
<body>
<header>
  <h1>loam.dev HTML-Report</h1>
  <p class="meta">loam ${payload.toolVersion} &middot; ${payload.rulesetVersion}</p>
  <p class="summary">$total finding${total == 1 ? '' : 's'} &mdash; error: ${counts[Severity.error]}, warning: ${counts[Severity.warning]}, info: ${counts[Severity.info]}</p>
</header>
<main>
  <div class="filters" role="group" aria-label="Filter findings">
    <label>Group by:
      <select id="groupBy" aria-label="Group by">
        <option value="rule">Rule</option>
        <option value="severity">Severity</option>
        <option value="file">File</option>
      </select>
    </label>
    <label>Severity:
      <select id="filterSeverity" aria-label="Filter by severity">
        <option value="">All</option>
        <option value="error">error</option>
        <option value="warning">warning</option>
        <option value="info">info</option>
      </select>
    </label>
    <button id="selectAllBtn" class="ctrl-btn" type="button">Select all</button>
    <button id="clearSelBtn" class="ctrl-btn" type="button">Clear selection</button>
  </div>
  <div id="findings-container"></div>
  <section id="fix-prompt-section" aria-label="Fix-Prompt" hidden>
    <h2 class="section-title">Fix-Prompt</h2>
    <p class="section-meta" id="fix-prompt-count"></p>
    <textarea id="fix-prompt-output" readonly aria-label="Generated Fix-Prompt"></textarea>
    <button id="copyPromptBtn" class="ctrl-btn copy-btn" type="button">Copy to clipboard</button>
    <span id="copy-feedback" aria-live="polite"></span>
  </section>
</main>
<script type="application/json" id="loam-data">
$jsonData
</script>
<script type="application/json" id="loam-fix-hints">
$fixHintsJson
</script>
<script type="text/x-loam-template" id="loam-fix-prompt-template">
$kFixPromptTemplate</script>
<script>
${_js()}
</script>
</body>
</html>''';
  }

  Map<String, dynamic> _buildFindingMap(Finding f, String projectRoot) {
    return {
      'ruleId': f.ruleId,
      'severity': f.severity.name,
      'filePath': _toRelativePath(f.filePath, projectRoot),
      'line': f.line,
      'column': f.column,
      'message': f.message,
      'fingerprint': f.fingerprint,
    };
  }

  /// Converts [filePath] to a forward-slash-normalised path relative to
  /// [projectRoot]. Mirrors [JsonReporter._toRelativePath] (Windows safety).
  String _toRelativePath(String filePath, String projectRoot) {
    final rel = p.isAbsolute(filePath)
        ? p.relative(filePath, from: projectRoot)
        : filePath;
    final forward = rel.replaceAll(r'\', '/');
    return forward.startsWith('/') ? forward.substring(1) : forward;
  }

  /// Inline CSS — no external resources.
  String _css() => r'''
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, -apple-system, sans-serif; background: #101014; color: #ECEAE3; line-height: 1.5; }
header { padding: 1.5rem 2rem 1rem; border-bottom: 1px solid #2a2a30; }
h1 { font-size: 1.4rem; color: #88C840; margin-bottom: 0.25rem; }
.meta { font-size: 0.8rem; color: #888; }
.summary { margin-top: 0.5rem; font-size: 0.95rem; }
main { padding: 1rem 2rem; }
.filters { display: flex; gap: 1.5rem; margin-bottom: 1rem; flex-wrap: wrap; align-items: center; }
.filters label { font-size: 0.85rem; color: #aaa; display: flex; gap: 0.4rem; align-items: center; }
select { background: #1c1c22; color: #ECEAE3; border: 1px solid #3a3a42; border-radius: 4px; padding: 0.2rem 0.4rem; font-size: 0.85rem; }
.ctrl-btn { background: #1c1c22; color: #ECEAE3; border: 1px solid #3a3a42; border-radius: 4px; padding: 0.2rem 0.7rem; font-size: 0.8rem; cursor: pointer; }
.ctrl-btn:hover { background: #2a2a36; }
.copy-btn { background: #1a3a1a; border-color: #3a7a3a; color: #88C840; margin-top: 0.5rem; }
.copy-btn:hover { background: #223a22; }
.group { margin-bottom: 1.5rem; }
.group-header { font-size: 1rem; font-weight: 600; padding: 0.4rem 0; border-bottom: 1px solid #2a2a30; margin-bottom: 0.5rem; cursor: pointer; user-select: none; display: flex; justify-content: space-between; }
.group-header .toggle { color: #555; font-size: 0.75rem; }
.group-body.collapsed { display: none; }
.finding { background: #16161c; border: 1px solid #2a2a30; border-radius: 6px; padding: 0.6rem 0.9rem; margin-bottom: 0.4rem; font-size: 0.85rem; display: flex; align-items: flex-start; gap: 0.6rem; }
.finding-check { margin-top: 0.15rem; flex-shrink: 0; accent-color: #88C840; width: 1rem; height: 1rem; cursor: pointer; }
.finding-body { flex: 1; min-width: 0; }
.finding .loc { font-family: monospace; color: #88C840; font-size: 0.8rem; }
.finding .msg { margin-top: 0.2rem; color: #ECEAE3; }
.finding .badge { display: inline-block; border-radius: 3px; padding: 0 0.35rem; font-size: 0.7rem; font-weight: 700; text-transform: uppercase; margin-right: 0.4rem; vertical-align: middle; }
.badge-error { background: #7a1c1c; color: #f5a0a0; }
.badge-warning { background: #5a4200; color: #ffd070; }
.badge-info { background: #0f3050; color: #80c8f0; }
.finding.selected { border-color: #88C840; background: #1a201a; }
.empty { color: #666; text-align: center; padding: 2rem; }
#fix-prompt-section { margin-top: 2rem; padding-top: 1.5rem; border-top: 1px solid #2a2a30; }
.section-title { font-size: 1rem; font-weight: 600; color: #88C840; margin-bottom: 0.4rem; }
.section-meta { font-size: 0.8rem; color: #888; margin-bottom: 0.6rem; }
#fix-prompt-output { width: 100%; min-height: 12rem; background: #0d0d11; color: #ccc; border: 1px solid #3a3a42; border-radius: 4px; padding: 0.7rem; font-family: monospace; font-size: 0.8rem; resize: vertical; }
#copy-feedback { margin-left: 0.7rem; font-size: 0.8rem; color: #88C840; }
''';

  /// Inline JavaScript — no external resources, no runtime.
  ///
  /// Assembly logic mirrors [assembleFixPrompt] from fix_prompt_template.dart:
  ///   1. For each selected finding (in embedded order), build a line:
  ///      `- [ruleId] filePath:line — message\n  Fix hint: <hint>`
  ///   2. Join lines with `\n\n`.
  ///   3. Replace `{{FINDINGS}}` in the embedded template.
  /// This ensures byte-identical output for the same selection (Invariante 5).
  String _js() => r'''
(function() {
  'use strict';

  var dataEl = document.getElementById('loam-data');
  var data;
  try { data = JSON.parse(dataEl.textContent); } catch(e) { return; }

  var fixHints = {};
  var fixHintsEl = document.getElementById('loam-fix-hints');
  try { fixHints = JSON.parse(fixHintsEl.textContent); } catch(e) {}

  var templateEl = document.getElementById('loam-fix-prompt-template');
  var promptTemplate = templateEl ? templateEl.textContent : '';

  var findings = data.findings || [];
  var groupSel = document.getElementById('groupBy');
  var sevSel = document.getElementById('filterSeverity');
  var container = document.getElementById('findings-container');
  var fixSection = document.getElementById('fix-prompt-section');
  var fixOutput = document.getElementById('fix-prompt-output');
  var fixCount = document.getElementById('fix-prompt-count');
  var copyBtn = document.getElementById('copyPromptBtn');
  var copyFeedback = document.getElementById('copy-feedback');
  var selectAllBtn = document.getElementById('selectAllBtn');
  var clearSelBtn = document.getElementById('clearSelBtn');

  // Selection state: keyed by fingerprint (stable identifier).
  var selected = {};

  function escHtml(s) {
    return String(s)
      .replace(/&/g,'&amp;').replace(/</g,'&lt;')
      .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  function groupKey(f, by) {
    if (by === 'severity') return f.severity;
    if (by === 'file') return f.filePath;
    return f.ruleId;
  }

  function fixHintFor(ruleId) {
    return fixHints[ruleId] || fixHints['__generic__'] || '';
  }

  /// Mirror of Dart assembleFixPrompt: same algorithm, same output format.
  function assemblePrompt(selFindings) {
    if (selFindings.length === 0) {
      return promptTemplate.replace('{{FINDINGS}}', '(no findings selected)');
    }
    var lines = selFindings.map(function(f) {
      var hint = fixHintFor(f.ruleId);
      return '- [' + f.ruleId + '] ' + f.filePath + ':' + f.line + ' — ' + f.message + '\n  Fix hint: ' + hint;
    });
    var block = lines.join('\n\n');
    return promptTemplate.replace('{{FINDINGS}}', block);
  }

  function updatePrompt() {
    // Collect selected findings in their embedded (deterministic) order.
    var sel = findings.filter(function(f) { return selected[f.fingerprint]; });
    if (sel.length === 0) {
      fixSection.hidden = true;
      return;
    }
    fixSection.hidden = false;
    fixCount.textContent = sel.length + ' finding' + (sel.length === 1 ? '' : 's') + ' selected';
    fixOutput.value = assemblePrompt(sel);
  }

  function render() {
    var by = groupSel.value;
    var sevFilter = sevSel.value;
    var visible = findings.filter(function(f) { return !sevFilter || f.severity === sevFilter; });

    var order = [];
    var groups = {};
    visible.forEach(function(f) {
      var k = groupKey(f, by);
      if (!groups[k]) { groups[k] = []; order.push(k); }
      groups[k].push(f);
    });

    if (visible.length === 0) {
      container.innerHTML = '<p class="empty">No findings.</p>';
      updatePrompt();
      return;
    }

    var html = '';
    order.forEach(function(k) {
      var gFindings = groups[k];
      var id = 'grp-' + encodeURIComponent(k);
      html += '<div class="group"><div class="group-header" onclick="toggleGroup(\'' + escHtml(id) + '\')">'
           + escHtml(k) + ' <span class="count">(' + gFindings.length + ')</span>'
           + '<span class="toggle">&#9660;</span></div>'
           + '<div class="group-body" id="' + escHtml(id) + '">';
      gFindings.forEach(function(f) {
        var loc = f.filePath + ':' + f.line + (f.column ? ':' + f.column : '');
        var chkId = 'chk-' + escHtml(f.fingerprint);
        var chkd = selected[f.fingerprint] ? ' checked' : '';
        var selCls = selected[f.fingerprint] ? ' selected' : '';
        html += '<div class="finding' + selCls + '" id="fd-' + escHtml(f.fingerprint) + '">'
             + '<input type="checkbox" class="finding-check" id="' + chkId + '" data-fp="' + escHtml(f.fingerprint) + '"' + chkd + ' aria-label="Select finding ' + escHtml(loc) + '">'
             + '<div class="finding-body">'
             + '<label for="' + chkId + '" style="cursor:pointer">'
             + '<span class="badge badge-' + escHtml(f.severity) + '">' + escHtml(f.severity) + '</span>'
             + '<span class="loc">' + escHtml(loc) + '</span>'
             + ' &mdash; <span class="rule-id">' + escHtml(f.ruleId) + '</span>'
             + '</label>'
             + '<div class="msg">' + escHtml(f.message) + '</div>'
             + '</div>'
             + '</div>';
      });
      html += '</div></div>';
    });
    container.innerHTML = html;

    // Attach checkbox listeners after DOM update.
    container.querySelectorAll('.finding-check').forEach(function(chk) {
      chk.addEventListener('change', function() {
        var fp = chk.getAttribute('data-fp');
        selected[fp] = chk.checked;
        var fdEl = document.getElementById('fd-' + fp);
        if (fdEl) fdEl.classList.toggle('selected', chk.checked);
        updatePrompt();
      });
    });

    updatePrompt();
  }

  window.toggleGroup = function(id) {
    var el = document.getElementById(id);
    if (el) el.classList.toggle('collapsed');
  };

  if (selectAllBtn) {
    selectAllBtn.addEventListener('click', function() {
      findings.forEach(function(f) { selected[f.fingerprint] = true; });
      render();
    });
  }

  if (clearSelBtn) {
    clearSelBtn.addEventListener('click', function() {
      selected = {};
      render();
    });
  }

  if (copyBtn) {
    copyBtn.addEventListener('click', function() {
      var text = fixOutput ? fixOutput.value : '';
      if (!text) return;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function() {
          copyFeedback.textContent = 'Copied!';
          setTimeout(function() { copyFeedback.textContent = ''; }, 2000);
        }).catch(function() {
          copyFeedback.textContent = 'Copy failed.';
        });
      } else {
        // Fallback for older browsers.
        fixOutput.select();
        try {
          document.execCommand('copy');
          copyFeedback.textContent = 'Copied!';
          setTimeout(function() { copyFeedback.textContent = ''; }, 2000);
        } catch(e) {
          copyFeedback.textContent = 'Copy failed.';
        }
      }
    });
  }

  groupSel.addEventListener('change', render);
  sevSel.addEventListener('change', render);
  render();
})();
''';
}
