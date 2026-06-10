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
/// Layout: a terminal-styled masthead (inline brand mark, no external image),
/// a scrollable findings column on the left, and a sticky side panel on the
/// right that keeps the severity summary, the toolchain facts, and the
/// always-visible Fix-Prompt in view without scrolling to the page foot.
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
  /// Creates a [HtmlReporter].
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

    // Count by severity for the summary panel.
    final counts = <Severity, int>{
      Severity.error: 0,
      Severity.warning: 0,
      Severity.info: 0,
    };
    for (final f in payload.findings) {
      counts[f.severity] = (counts[f.severity] ?? 0) + 1;
    }
    final total = payload.findings.length;
    final errors = counts[Severity.error] ?? 0;
    final warnings = counts[Severity.warning] ?? 0;
    final infos = counts[Severity.info] ?? 0;

    // Severity bar: flex weights are deterministic (counts only); a zero-finding
    // run shows a single "clean" segment instead of an empty rail.
    final sevBar = total == 0
        ? '<span class="seg seg-clean" style="flex:1"></span>'
        : '<span class="seg seg-error" style="flex:$errors"></span>'
              '<span class="seg seg-warning" style="flex:$warnings"></span>'
              '<span class="seg seg-info" style="flex:$infos"></span>';

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
<div class="app">
  <header class="topbar">
    <a class="brand" href="https://getloam.dev" target="_blank" rel="noopener" aria-label="loam.dev website">
      ${_logoSvg()}
      <div class="brand-text">
        <span class="wordmark">loam<span class="tld">.dev</span></span>
        <span class="tagline">codebase intelligence &middot; anti-AI-slop</span>
      </div>
    </a>
    <div class="cmdline" aria-hidden="true">
      <span class="cmd-prompt"></span>loam scan <span class="flag">--format html</span>
    </div>
    <div class="topbar-right">
      <a class="sponsor-link" href="https://github.com/sponsors/silvio-l" target="_blank" rel="noopener" title="Support loam.dev development">&#10084; Sponsor</a>
      <div class="chips">
        <span class="chip">loam ${payload.toolVersion}</span>
        <span class="chip chip-ruleset">${payload.rulesetVersion}</span>
      </div>
    </div>
  </header>

  <div class="layout">
    <main class="main">
      <div class="toolbar" role="group" aria-label="Filter findings">
        <label class="field">Group by
          <select id="groupBy" aria-label="Group by">
            <option value="rule">Rule</option>
            <option value="severity">Severity</option>
            <option value="file">File</option>
          </select>
        </label>
        <label class="field">Severity
          <select id="filterSeverity" aria-label="Filter by severity">
            <option value="">All</option>
            <option value="error">error</option>
            <option value="warning">warning</option>
            <option value="info">info</option>
          </select>
        </label>
        <label class="field search-field">Search
          <input type="search" id="searchInput" placeholder="file, rule or message&hellip;" aria-label="Search findings">
        </label>
        <span class="showing" id="showing-count"></span>
        <span class="toolbar-spacer"></span>
        <button id="selectAllBtn" class="btn" type="button">Select all</button>
        <button id="clearSelBtn" class="btn" type="button">Clear</button>
      </div>
      <div id="findings-container"></div>
    </main>

    <aside class="sidebar">
      <section class="card summary-card">
        <h2 class="card-title">Summary</h2>
        <p class="total">$total finding${total == 1 ? '' : 's'}</p>
        <div class="sev-bar">$sevBar</div>
        <ul class="sev-legend">
          <li><span class="dot dot-error"></span> error <b>$errors</b></li>
          <li><span class="dot dot-warning"></span> warning <b>$warnings</b></li>
          <li><span class="dot dot-info"></span> info <b>$infos</b></li>
        </ul>
      </section>

      <section class="card tooling-card">
        <h2 class="card-title">Toolchain</h2>
        <dl class="kv">
          <dt>tool</dt><dd>loam ${payload.toolVersion}</dd>
          <dt>ruleset</dt><dd>${payload.rulesetVersion}</dd>
          <dt>report</dt><dd>self-contained &middot; offline</dd>
        </dl>
        <ol class="howto">
          <li>Filter &amp; select the findings you want to act on</li>
          <li>Copy the assembled, versioned Fix-Prompt</li>
          <li>Paste it into your AI coding agent</li>
        </ol>
      </section>

      <section class="card prompt-card" id="fix-prompt-section" aria-label="Fix-Prompt">
        <div class="prompt-head">
          <h2 class="card-title">Fix-Prompt</h2>
          <span class="chip chip-prompt">$kPromptVersion</span>
        </div>
        <p class="card-meta" id="fix-prompt-count">No findings selected</p>
        <textarea id="fix-prompt-output" readonly aria-label="Generated Fix-Prompt" placeholder="Select one or more findings to assemble a deterministic, copy-ready Fix-Prompt for your AI agent."></textarea>
        <div class="prompt-actions">
          <button id="copyPromptBtn" class="btn btn-primary" type="button" disabled>Copy to clipboard</button>
          <span id="copy-feedback" aria-live="polite"></span>
        </div>
      </section>
    </aside>
  </div>

  <footer class="appfoot">
    <span class="foot-tag">Generated by <a href="https://getloam.dev" target="_blank" rel="noopener">loam.dev</a> &middot; codebase intelligence &amp; anti-AI-slop for Dart &amp; Flutter</span>
    <nav class="foot-links" aria-label="loam.dev links">
      <a href="https://getloam.dev" target="_blank" rel="noopener">Website</a>
      <a href="https://getloam.dev/rules" target="_blank" rel="noopener">Rules</a>
      <a href="https://github.com/silvio-l/loam" target="_blank" rel="noopener">&#9733; GitHub</a>
      <a href="https://github.com/sponsors/silvio-l" target="_blank" rel="noopener">&#10084; Sponsor</a>
    </nav>
  </footer>
</div>
<script type="application/json" id="loam-data">
$jsonData
</script>
<script type="application/json" id="loam-fix-hints">
$fixHintsJson
</script>
<script type="text/x-loam-template" id="loam-fix-prompt-template">
${fillPromptTarget(kFixPromptTemplate, _targetName(payload.projectRoot))}</script>
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

  /// Stable, checkout-location-independent identifier of the analysed project.
  ///
  /// Uses the project root's directory name (never the absolute path) so the
  /// embedded Fix-Prompt names its target without violating Invariant 5
  /// (reproducibility: same input ⇒ byte-identical report regardless of where
  /// the project happens to live on disk). [fillPromptTarget] handles the
  /// degenerate empty/`.` case.
  String _targetName(String projectRoot) {
    final base = p.basename(p.normalize(projectRoot));
    return (base.isEmpty || base == '.') ? '' : base;
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

  /// Inline brand mark — the simplest loam.dev logo (soil strata + sprout),
  /// embedded as inline SVG so the page stays self-contained. No `xmlns`
  /// attribute on purpose: HTML5 parses inline SVG without it, and any
  /// `http://...` namespace URI would break the "no external URL" guarantee.
  String _logoSvg() =>
      r'''<svg class="logo" viewBox="150 301 405 405" width="36" height="36" role="img" aria-label="loam.dev">
<g fill="#564F47"><g transform="translate(0,1024) scale(0.1,-0.1)">
<path d="M2455 5175 c-49 -17 -90 -61 -104 -112 -6 -21 -11 -79 -11 -128 0 -102 22 -162 73 -199 28 -21 36 -21 1108 -24 1206 -3 1115 -8 1166 70 25 37 28 52 31 145 6 155 -30 227 -126 252 -23 7 -419 10 -1067 10 -853 0 -1037 -3 -1070 -14z"/>
<path d="M2431 4623 c-18 -9 -45 -34 -60 -57 -24 -37 -26 -46 -26 -160 0 -103 3 -126 20 -155 26 -44 62 -70 111 -81 22 -5 491 -10 1066 -10 1133 0 1078 -3 1133 62 36 42 48 100 43 209 -3 84 -7 102 -30 136 -52 78 32 73 -1160 73 -968 0 -1066 -2 -1097 -17z"/>
<path d="M2434 4080 c-62 -31 -86 -82 -92 -194 -7 -143 21 -210 102 -247 39 -18 90 -19 1086 -19 996 0 1047 1 1086 19 82 37 108 103 102 251 -4 115 -25 157 -92 189 -42 21 -51 21 -1097 21 -1037 0 -1055 0 -1095 -20z"/>
</g></g>
<g fill="#88C840"><g transform="translate(0,1024) scale(0.1,-0.1)">
<path d="M2356 6761 c-14 -16 -15 -29 -7 -103 13 -117 36 -198 82 -297 117 -251 326 -410 599 -456 193 -32 216 -37 262 -57 58 -25 123 -93 137 -144 6 -23 11 -135 11 -264 0 -162 3 -229 12 -238 7 -7 40 -12 78 -12 38 0 71 5 78 12 9 9 12 76 12 238 0 124 5 241 10 261 15 54 80 122 142 149 29 12 109 31 178 41 214 33 325 76 450 176 174 139 282 343 310 590 7 63 6 82 -6 101 -14 21 -19 22 -182 22 -284 0 -413 -23 -563 -101 -190 -99 -347 -299 -397 -506 -9 -41 -22 -73 -29 -73 -7 0 -17 19 -23 43 -54 216 -169 383 -341 496 -162 106 -316 141 -632 141 -147 0 -166 -2 -181 -19z"/>
</g></g>
</svg>''';

  /// Inline CSS — no external resources.
  String _css() => r'''
:root {
  --bg: #101014;
  --panel: #16161c;
  --panel-2: #1c1c22;
  --ink: #ECEAE3;
  --dim: #8D8A7E;
  --line: #26262e;
  --green: #88C840;
  --soil: #564F47;
  --error: #ff6b6b;
  --warning: #ffc24b;
  --info: #5cc8ff;
  --mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html { scrollbar-color: #2a2a32 transparent; }
body {
  font-family: var(--mono);
  color: var(--ink);
  line-height: 1.5;
  background:
    radial-gradient(900px 400px at 12% -8%, rgba(136,200,64,0.07), transparent 60%),
    radial-gradient(700px 360px at 100% 0%, rgba(86,79,71,0.18), transparent 55%),
    var(--bg);
  background-attachment: fixed;
  -webkit-font-smoothing: antialiased;
}
::selection { background: rgba(136,200,64,0.28); }

@keyframes rise { from { opacity: 0; transform: translateY(7px); } to { opacity: 1; transform: none; } }

/* ---- masthead ---------------------------------------------------------- */
.topbar {
  display: flex; align-items: center; gap: 1.25rem; flex-wrap: wrap;
  padding: 1.1rem 1.75rem;
  border-bottom: 1px solid var(--line);
  background: linear-gradient(180deg, rgba(28,28,34,0.6), rgba(16,16,20,0));
  animation: rise .45s ease both;
}
.brand { display: flex; align-items: center; gap: 0.8rem; text-decoration: none; color: inherit; }
.brand:hover .wordmark { color: var(--green); }
.brand:hover .logo { filter: drop-shadow(0 1px 7px rgba(136,200,64,0.45)); }
.logo { filter: drop-shadow(0 1px 4px rgba(136,200,64,0.25)); flex-shrink: 0; }
.brand-text { display: flex; flex-direction: column; line-height: 1.15; }
.wordmark { font-size: 1.25rem; font-weight: 600; letter-spacing: -0.01em; }
.wordmark .tld { color: var(--green); }
.tagline { font-size: 0.7rem; color: var(--dim); letter-spacing: 0.02em; }
.cmdline {
  font-size: 0.82rem; color: var(--dim);
  background: #0d0d11; border: 1px solid var(--line); border-radius: 7px;
  padding: 0.35rem 0.7rem; white-space: nowrap;
}
.cmd-prompt::before { content: "$ "; color: var(--green); }
.cmdline .flag { color: var(--ink); }
.topbar-right { margin-left: auto; display: flex; align-items: center; gap: 0.85rem; flex-wrap: wrap; }
.sponsor-link {
  display: inline-flex; align-items: center; gap: 0.35rem;
  font-size: 0.74rem; text-decoration: none; white-space: nowrap;
  color: var(--green);
  background: rgba(136,200,64,0.08);
  border: 1px solid rgba(136,200,64,0.32);
  border-radius: 999px; padding: 0.26rem 0.72rem;
  transition: background .15s ease, border-color .15s ease, transform .08s ease;
}
.sponsor-link:hover { background: rgba(136,200,64,0.18); border-color: rgba(136,200,64,0.55); }
.sponsor-link:active { transform: translateY(1px); }
.chips { display: flex; gap: 0.5rem; flex-wrap: wrap; }
.chip {
  font-size: 0.72rem; color: var(--dim);
  background: var(--panel-2); border: 1px solid var(--line);
  border-radius: 999px; padding: 0.2rem 0.65rem; white-space: nowrap;
}
.chip-ruleset { color: var(--green); border-color: rgba(136,200,64,0.3); }

/* ---- layout ------------------------------------------------------------ */
.layout {
  max-width: 1440px; margin: 0 auto; padding: 1.5rem 1.75rem 3rem;
  display: grid; grid-template-columns: minmax(0,1fr) clamp(320px, 30vw, 400px);
  gap: 1.5rem; align-items: start;
}
.main { min-width: 0; }

/* ---- toolbar ----------------------------------------------------------- */
.toolbar {
  display: flex; align-items: center; gap: 1rem; flex-wrap: wrap;
  background: var(--panel); border: 1px solid var(--line); border-radius: 10px;
  padding: 0.7rem 1rem; margin-bottom: 1rem;
  position: sticky; top: 0.75rem; z-index: 5;
  box-shadow: 0 8px 24px -18px rgba(0,0,0,0.9);
}
.field { display: flex; align-items: center; gap: 0.45rem; font-size: 0.72rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--dim); }
select {
  font-family: var(--mono);
  background: var(--panel-2); color: var(--ink);
  border: 1px solid var(--line); border-radius: 6px;
  padding: 0.25rem 0.5rem; font-size: 0.8rem; cursor: pointer;
}
select:focus-visible, .btn:focus-visible, textarea:focus-visible, input:focus-visible { outline: 2px solid var(--green); outline-offset: 1px; }
.search-field { text-transform: none; letter-spacing: 0; }
input[type="search"] {
  font-family: var(--mono); font-size: 0.8rem;
  background: var(--panel-2); color: var(--ink);
  border: 1px solid var(--line); border-radius: 6px;
  padding: 0.25rem 0.55rem; min-width: 13rem;
}
input[type="search"]::placeholder { color: #565248; }
.showing { font-size: 0.76rem; color: var(--dim); font-variant-numeric: tabular-nums; }
.toolbar-spacer { flex: 1; }

.btn {
  font-family: var(--mono); font-size: 0.76rem;
  background: var(--panel-2); color: var(--ink);
  border: 1px solid var(--line); border-radius: 6px;
  padding: 0.35rem 0.8rem; cursor: pointer;
  transition: border-color .15s ease, background .15s ease, transform .05s ease;
}
.btn:hover { border-color: #3c3c48; background: #23232c; }
.btn:active { transform: translateY(1px); }

/* ---- findings ---------------------------------------------------------- */
.group { margin-bottom: 1.4rem; animation: rise .4s ease both; }
.group-header {
  display: flex; align-items: center; gap: 0.5rem;
  font-size: 0.82rem; font-weight: 600;
  padding: 0.4rem 0.2rem; margin-bottom: 0.5rem;
  border-bottom: 1px solid var(--line); cursor: pointer; user-select: none;
}
.group-header .count { color: var(--dim); font-weight: 400; }
.group-header .toggle { margin-left: auto; color: #555; font-size: 0.7rem; transition: transform .15s ease; }
.group-header.collapsed .toggle { transform: rotate(-90deg); }
.group-body.collapsed { display: none; }

.finding {
  display: flex; align-items: flex-start; gap: 0.7rem;
  background: var(--panel); border: 1px solid var(--line); border-left: 3px solid var(--line);
  border-radius: 8px; padding: 0.6rem 0.85rem; margin-bottom: 0.45rem;
  font-size: 0.84rem; cursor: pointer;
  transition: border-color .15s ease, background .15s ease, transform .08s ease;
}
.finding:hover { background: #1a1a21; border-left-color: var(--soil); }
.finding.sev-error { border-left-color: var(--error); }
.finding.sev-warning { border-left-color: var(--warning); }
.finding.sev-info { border-left-color: var(--info); }
.finding.selected { border-color: rgba(136,200,64,0.55); border-left-color: var(--green); background: #161d12; }
.finding-check { margin-top: 0.15rem; flex-shrink: 0; accent-color: var(--green); width: 1rem; height: 1rem; cursor: pointer; }
.finding-body { flex: 1; min-width: 0; }
.finding-top { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; }
.loc { font-family: var(--mono); color: var(--green); font-size: 0.8rem; word-break: break-all; }
.rule-id { font-size: 0.7rem; color: var(--dim); background: var(--panel-2); border: 1px solid var(--line); border-radius: 4px; padding: 0.05rem 0.4rem; text-decoration: none; transition: color .15s ease, border-color .15s ease; }
a.rule-id:hover { color: var(--green); border-color: rgba(136,200,64,0.45); }
a.rule-id::after { content: " \2197"; opacity: 0.5; font-size: 0.65rem; }
.msg { margin-top: 0.3rem; color: var(--ink); }
.badge {
  display: inline-block; border-radius: 4px; padding: 0.05rem 0.4rem;
  font-size: 0.65rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em;
}
.badge-error { background: rgba(255,107,107,0.16); color: var(--error); }
.badge-warning { background: rgba(255,194,75,0.16); color: var(--warning); }
.badge-info { background: rgba(92,200,255,0.16); color: var(--info); }

.empty { text-align: center; padding: 3rem 1rem; color: var(--dim); }
.empty-mark { font-size: 2rem; color: var(--green); margin-bottom: 0.5rem; }

/* ---- sidebar ----------------------------------------------------------- */
.sidebar {
  position: sticky; top: 0.75rem; align-self: start;
  display: flex; flex-direction: column; gap: 1rem;
  max-height: calc(100vh - 1.5rem); overflow-y: auto;
  padding-right: 2px;
}
.card {
  background: var(--panel); border: 1px solid var(--line); border-radius: 11px;
  padding: 1rem 1.1rem; animation: rise .45s ease both;
}
.summary-card { animation-delay: .05s; }
.tooling-card { animation-delay: .1s; }
.prompt-card { animation-delay: .15s; }
.card-title { font-size: 0.68rem; text-transform: uppercase; letter-spacing: 0.13em; color: var(--dim); font-weight: 600; margin-bottom: 0.7rem; }

.total { font-size: 1.15rem; font-weight: 600; color: var(--ink); }
.sev-bar { display: flex; height: 9px; border-radius: 5px; overflow: hidden; background: #0d0d11; border: 1px solid var(--line); margin: 0.7rem 0 0.85rem; }
.seg { display: block; min-width: 0; }
.seg-error { background: var(--error); }
.seg-warning { background: var(--warning); }
.seg-info { background: var(--info); }
.seg-clean { background: var(--green); }
.sev-legend { list-style: none; display: flex; flex-direction: column; gap: 0.4rem; font-size: 0.8rem; }
.sev-legend li { display: flex; align-items: center; gap: 0.55rem; color: var(--dim); }
.sev-legend b { margin-left: auto; color: var(--ink); font-variant-numeric: tabular-nums; font-weight: 600; }
.dot { width: 0.6rem; height: 0.6rem; border-radius: 50%; flex-shrink: 0; }
.dot-error { background: var(--error); }
.dot-warning { background: var(--warning); }
.dot-info { background: var(--info); }

.kv { display: grid; grid-template-columns: auto 1fr; gap: 0.3rem 0.8rem; font-size: 0.8rem; margin-bottom: 0.9rem; }
.kv dt { color: var(--dim); }
.kv dd { color: var(--ink); text-align: right; word-break: break-all; }
.howto { list-style: none; counter-reset: step; display: flex; flex-direction: column; gap: 0.45rem; }
.howto li { position: relative; padding-left: 1.7rem; font-size: 0.78rem; color: var(--dim); }
.howto li::before {
  counter-increment: step; content: counter(step);
  position: absolute; left: 0; top: -1px;
  width: 1.2rem; height: 1.2rem; border-radius: 50%;
  background: var(--panel-2); border: 1px solid var(--line);
  color: var(--green); font-size: 0.68rem; font-weight: 700;
  display: grid; place-items: center;
}

/* ---- fix-prompt -------------------------------------------------------- */
.prompt-head { display: flex; align-items: center; gap: 0.6rem; margin-bottom: 0.3rem; }
.prompt-head .card-title { margin-bottom: 0; }
.chip-prompt { color: var(--green); border-color: rgba(136,200,64,0.3); margin-left: auto; }
.card-meta { font-size: 0.76rem; color: var(--dim); margin-bottom: 0.6rem; }
#fix-prompt-output {
  width: 100%; min-height: 12rem; max-height: 42vh; resize: vertical;
  font-family: var(--mono); font-size: 0.76rem; line-height: 1.55;
  background: #0c0c10; color: #cfcdc4;
  border: 1px solid var(--line); border-radius: 8px; padding: 0.7rem 0.8rem;
}
#fix-prompt-output::placeholder { color: #565248; }
.prompt-actions { display: flex; align-items: center; gap: 0.7rem; margin-top: 0.6rem; }
.btn-primary {
  background: linear-gradient(180deg, #9ddc50, #79b536);
  color: #0a1604; border-color: #6da32f; font-weight: 700;
}
.btn-primary:hover { background: linear-gradient(180deg, #a8e85c, #84c23d); border-color: #7cb436; }
.btn-primary:disabled { opacity: 0.35; cursor: not-allowed; filter: saturate(0.4); }
#copy-feedback { font-size: 0.78rem; color: var(--green); }

/* ---- scrollbars (webkit) ---------------------------------------------- */
.sidebar::-webkit-scrollbar, #fix-prompt-output::-webkit-scrollbar { width: 8px; height: 8px; }
.sidebar::-webkit-scrollbar-thumb, #fix-prompt-output::-webkit-scrollbar-thumb { background: #2a2a32; border-radius: 4px; }

/* ---- footer ------------------------------------------------------------ */
.appfoot {
  max-width: 1440px; margin: 0 auto;
  border-top: 1px solid var(--line);
  padding: 1.3rem 1.75rem 2.2rem;
  display: flex; align-items: center; justify-content: space-between; gap: 1rem 1.5rem; flex-wrap: wrap;
  font-size: 0.76rem; color: var(--dim);
}
.appfoot a { color: var(--dim); text-decoration: none; border-bottom: 1px solid transparent; transition: color .15s ease, border-color .15s ease; }
.appfoot a:hover { color: var(--green); border-bottom-color: rgba(136,200,64,0.4); }
.foot-tag a { color: var(--ink); }
.foot-links { display: flex; gap: 1.2rem; flex-wrap: wrap; }

/* ---- responsive -------------------------------------------------------- */
@media (max-width: 920px) {
  .layout { grid-template-columns: 1fr; }
  .sidebar { position: static; max-height: none; overflow: visible; }
  .toolbar { position: static; }
  .chips { margin-left: 0; width: 100%; }
}
@media (prefers-reduced-motion: reduce) {
  .topbar, .card, .group { animation: none; }
}
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
  var fixOutput = document.getElementById('fix-prompt-output');
  var fixCount = document.getElementById('fix-prompt-count');
  var copyBtn = document.getElementById('copyPromptBtn');
  var copyFeedback = document.getElementById('copy-feedback');
  var selectAllBtn = document.getElementById('selectAllBtn');
  var clearSelBtn = document.getElementById('clearSelBtn');
  var showingEl = document.getElementById('showing-count');
  var searchInput = document.getElementById('searchInput');

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

  // Mirror of Dart assembleFixPrompt: same algorithm, same output format.
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
    var n = sel.length;
    if (n === 0) {
      fixCount.textContent = 'No findings selected';
      fixOutput.value = '';
      copyBtn.disabled = true;
      return;
    }
    fixCount.textContent = n + ' finding' + (n === 1 ? '' : 's') + ' selected';
    fixOutput.value = assemblePrompt(sel);
    copyBtn.disabled = false;
  }

  function setSelected(fp, on) {
    selected[fp] = on;
    var fdEl = document.getElementById('fd-' + fp);
    if (fdEl) fdEl.classList.toggle('selected', on);
    var chk = document.getElementById('chk-' + fp);
    if (chk) chk.checked = on;
    updatePrompt();
  }

  function render() {
    var by = groupSel.value;
    var sevFilter = sevSel.value;
    var q = ((searchInput && searchInput.value) || '').trim().toLowerCase();
    var visible = findings.filter(function(f) {
      if (sevFilter && f.severity !== sevFilter) return false;
      if (q) {
        var hay = (f.filePath + ' ' + f.ruleId + ' ' + f.message).toLowerCase();
        if (hay.indexOf(q) === -1) return false;
      }
      return true;
    });

    if (showingEl) {
      showingEl.textContent = visible.length + ' of ' + findings.length + ' shown';
    }

    var order = [];
    var groups = {};
    visible.forEach(function(f) {
      var k = groupKey(f, by);
      if (!groups[k]) { groups[k] = []; order.push(k); }
      groups[k].push(f);
    });

    if (visible.length === 0) {
      container.innerHTML = '<div class="empty"><div class="empty-mark">&#10003;</div>'
        + '<p>' + (findings.length === 0 ? 'No findings &mdash; this project is clean.' : 'No findings match the current filter.') + '</p></div>';
      updatePrompt();
      return;
    }

    var html = '';
    order.forEach(function(k) {
      var gFindings = groups[k];
      var id = 'grp-' + encodeURIComponent(k);
      html += '<div class="group"><div class="group-header" onclick="toggleGroup(this, \'' + escHtml(id) + '\')">'
           + '<span class="group-name">' + escHtml(k) + '</span> <span class="count">(' + gFindings.length + ')</span>'
           + '<span class="toggle">&#9660;</span></div>'
           + '<div class="group-body" id="' + escHtml(id) + '">';
      gFindings.forEach(function(f) {
        var loc = f.filePath + ':' + f.line + (f.column ? ':' + f.column : '');
        var fp = escHtml(f.fingerprint);
        var chkId = 'chk-' + fp;
        var chkd = selected[f.fingerprint] ? ' checked' : '';
        var selCls = selected[f.fingerprint] ? ' selected' : '';
        html += '<div class="finding sev-' + escHtml(f.severity) + selCls + '" id="fd-' + fp + '" data-fp="' + fp + '">'
             + '<input type="checkbox" class="finding-check" id="' + chkId + '" data-fp="' + fp + '"' + chkd + ' aria-label="Select finding ' + escHtml(loc) + '">'
             + '<div class="finding-body">'
             + '<div class="finding-top">'
             + '<span class="badge badge-' + escHtml(f.severity) + '">' + escHtml(f.severity) + '</span>'
             + '<span class="loc">' + escHtml(loc) + '</span>'
             + '<a class="rule-id" href="https://getloam.dev/rules#' + encodeURIComponent(f.ruleId) + '" target="_blank" rel="noopener" title="Open rule reference on getloam.dev">' + escHtml(f.ruleId) + '</a>'
             + '</div>'
             + '<div class="msg">' + escHtml(f.message) + '</div>'
             + '</div>'
             + '</div>';
      });
      html += '</div></div>';
    });
    container.innerHTML = html;

    // Checkbox change → selection.
    container.querySelectorAll('.finding-check').forEach(function(chk) {
      chk.addEventListener('change', function() {
        setSelected(chk.getAttribute('data-fp'), chk.checked);
      });
    });

    // Whole-row click toggles selection (ignoring clicks on the checkbox itself).
    container.querySelectorAll('.finding').forEach(function(row) {
      row.addEventListener('click', function(ev) {
        // Let links (rule reference) and the checkbox handle their own clicks.
        if (ev.target && ev.target.closest && ev.target.closest('a, .finding-check')) return;
        var fp = row.getAttribute('data-fp');
        setSelected(fp, !selected[fp]);
      });
    });

    updatePrompt();
  }

  window.toggleGroup = function(headerEl, id) {
    var el = document.getElementById(id);
    if (el) el.classList.toggle('collapsed');
    if (headerEl) headerEl.classList.toggle('collapsed');
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
  if (searchInput) searchInput.addEventListener('input', render);
  render();
})();
''';
}
