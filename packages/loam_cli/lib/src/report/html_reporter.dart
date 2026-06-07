import 'dart:convert';

import 'package:path/path.dart' as p;

import '../model/finding.dart';
import 'reporter.dart';

/// Self-contained, interactive HTML reporter.
///
/// Emits a single, self-contained HTML page — no CDN, no external fonts,
/// no external scripts or stylesheets. Findings are embedded as a structured
/// JSON block (`<script type="application/json">`) and rendered client-side
/// via inline JavaScript.
///
/// Browsable by Rule ID, Severity, and file. Each Finding shows file, line,
/// and message as code-context.
///
/// NOTE (issue 07): finding-selection, Fix-Prompt generation, and
/// copy-to-clipboard are intentionally NOT implemented here — they are
/// scope for the next issue.
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
  </div>
  <div id="findings-container"></div>
</main>
<script type="application/json" id="loam-data">
$jsonData
</script>
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
.group { margin-bottom: 1.5rem; }
.group-header { font-size: 1rem; font-weight: 600; padding: 0.4rem 0; border-bottom: 1px solid #2a2a30; margin-bottom: 0.5rem; cursor: pointer; user-select: none; display: flex; justify-content: space-between; }
.group-header .toggle { color: #555; font-size: 0.75rem; }
.group-body.collapsed { display: none; }
.finding { background: #16161c; border: 1px solid #2a2a30; border-radius: 6px; padding: 0.6rem 0.9rem; margin-bottom: 0.4rem; font-size: 0.85rem; }
.finding .loc { font-family: monospace; color: #88C840; font-size: 0.8rem; }
.finding .msg { margin-top: 0.2rem; color: #ECEAE3; }
.finding .badge { display: inline-block; border-radius: 3px; padding: 0 0.35rem; font-size: 0.7rem; font-weight: 700; text-transform: uppercase; margin-right: 0.4rem; vertical-align: middle; }
.badge-error { background: #7a1c1c; color: #f5a0a0; }
.badge-warning { background: #5a4200; color: #ffd070; }
.badge-info { background: #0f3050; color: #80c8f0; }
.empty { color: #666; text-align: center; padding: 2rem; }
''';

  /// Inline JavaScript — no external resources, no runtime.
  String _js() => r'''
(function() {
  'use strict';

  var dataEl = document.getElementById('loam-data');
  var data;
  try { data = JSON.parse(dataEl.textContent); } catch(e) { return; }

  var findings = data.findings || [];
  var groupSel = document.getElementById('groupBy');
  var sevSel = document.getElementById('filterSeverity');
  var container = document.getElementById('findings-container');

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
        html += '<div class="finding">'
             + '<span class="badge badge-' + escHtml(f.severity) + '">' + escHtml(f.severity) + '</span>'
             + '<span class="loc">' + escHtml(loc) + '</span>'
             + ' &mdash; <span class="rule-id">' + escHtml(f.ruleId) + '</span>'
             + '<div class="msg">' + escHtml(f.message) + '</div>'
             + '</div>';
      });
      html += '</div></div>';
    });
    container.innerHTML = html;
  }

  window.toggleGroup = function(id) {
    var el = document.getElementById(id);
    if (el) el.classList.toggle('collapsed');
  };

  groupSel.addEventListener('change', render);
  sevSel.addEventListener('change', render);
  render();
})();
''';
}
