#!/usr/bin/env python3
"""Generate dashboard/analysis_report.html -- the client-facing report.

    python3 dashboard/generators/analysis_report.py

Assembles one page from the charts already built in dashboard/. It does NOT
recompute anything: every figure is lifted from its own generated HTML, so a
number can only change here by changing it at source and rebuilding that chart
first. Run the chart generators before this one.

WHY THE CSS IS SCOPED, AND WHY REMOVING THAT WILL BREAK THINGS SILENTLY.
Nineteen class names are defined differently across the nine charts, and `.key`
is a flex container in one chart and an SVG text fill in another. Dropping the
stylesheets onto one page unchanged lets whichever loads last win, which does
not error -- it quietly repaints an earlier figure with the wrong rules. Every
chart's rules are therefore prefixed with that chart's own wrapper class.

Colour tokens are the exception and are hoisted, not scoped: 26 of the 27
`:root` custom properties are identical across all charts, so they are declared
once for the page in all three theme states. The single disagreement, `--rest`,
is redefined inside the one wrapper that wants the other grey.

NO RECOMMENDATIONS. This pass carries findings only. Q3's recommendations were
dismantled by testing and Q1's have not been through the same scrutiny, so the
report states what is true and stops there. If that changes, the place to add it
is a section per finding, not a sentence smuggled into "why it matters".

The client is invented. See the plan file; the mission is what makes the three
questions hang together, so do not reword it casually.
"""
import os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DASH = os.path.join(ROOT, 'dashboard')
OUT  = os.path.join(DASH, 'analysis_report.html')

# page chrome belonging to each chart's own standalone page -- never wanted here
CHROME = {'body', '.wrap', 'h1', 'h2', '.lede', '.sub', '.take', '.note',
          '.lims', '.lims li', '.fine', '.note.fine', 'strong', 'code',
          '.note strong', '.colhd'}


def _blocks(css):
    """Split a stylesheet into (theme_blocks, [(selector, body)])."""
    theme, rules, i, n = [], [], 0, len(css)
    while i < n:
        while i < n and css[i] in ' \n\t\r':
            i += 1
        if i >= n:
            break
        if css[i] == '@':                       # @media { :root { ... } }
            depth, j = 0, i
            while j < n:
                if css[j] == '{':
                    depth += 1
                elif css[j] == '}':
                    depth -= 1
                    if depth == 0:
                        j += 1
                        break
                j += 1
            theme.append(css[i:j].strip())
            i = j
            continue
        m = re.compile(r'([^{}]+)\{([^}]*)\}').match(css, i)
        if not m:
            i += 1
            continue
        sel, body = m.group(1).strip(), m.group(2).strip()
        (theme if sel.startswith(':root') else rules).append(
            css[i:m.end()].strip() if sel.startswith(':root') else (sel, body))
        i = m.end()
    return theme, rules


def scope_css(css, wrap):
    """Prefix every rule with `.wrap`, dropping the chart's own page chrome."""
    theme, rules = _blocks(css)
    out = []
    for sel, body in rules:
        parts = [p.strip() for p in sel.split(',') if p.strip()]
        keep = [p for p in parts if p not in CHROME]
        if not keep:
            continue
        out.append('.%s %s{%s}' % (wrap, (', .%s ' % wrap).join(keep), body))
    return theme, out


def _matched_div(s, start):
    """The full <div>...</div> beginning at `start`, respecting nesting."""
    depth, i = 0, start
    while i < len(s):
        if s.startswith('<div', i):
            depth += 1
        elif s.startswith('</div>', i):
            depth -= 1
            if depth == 0:
                return s[start:i + 6]
            i += 5
        i += 1
    return s[start:]


def figure_of(name):
    """Return (css, [(figure_html, legend_html), ...]) for a built chart.

    Legends are paired to figures BY POSITION, not by index. A multi-panel chart
    can have a legend on one panel and none on another -- where_the_money_goes
    has three panels and only two legends -- so zipping the two lists by index
    silently files a legend under the wrong figure. That produced a legend
    reading "counted only for hospitalised patients" beneath a bar chart whose
    blue bar meant nothing of the kind.
    """
    with open(os.path.join(DASH, name + '.html')) as fh:
        s = fh.read()
    css = re.search(r'<style>(.*?)</style>', s, re.S).group(1)
    figs = [(m.start(), m.group(0))
            for m in re.finditer(r'<div class="figure">.*?</svg></div>', s, re.S)]
    keys = [(m.start(), _matched_div(s, m.start()))
            for m in re.finditer(r'<div class="key">', s)]
    out = []
    for i, (pos, html) in enumerate(figs):
        nxt = figs[i + 1][0] if i + 1 < len(figs) else len(s)
        mine = [k for kpos, k in keys if pos < kpos < nxt]
        out.append((html, mine[0] if mine else ''))
    return css, out


# figure key -> (source chart, which figure in it, wrapper class)
FIGURES = {
    'donut':     ('q1_donut',                             0, 'fig-donut'),
    'top20':     ('where_the_money_goes',                 0, 'fig-top20'),
    'whobears':  ('q2_who_bears_the_cost',                0, 'fig-whobears'),
    'cheapcare': ('q2_share_vs_cost_per_person',          0, 'fig-cheapcare'),
    'insurance': ('q2_same_condition_different_insurance', 0, 'fig-insurance'),
    'places':    ('places_not_people',                    0, 'fig-places'),
    'lorenz':    ('concentration',                        0, 'fig-lorenz'),
    'hospitals': ('two_ways_expensive',                   0, 'fig-hospitals'),
}


def collect():
    """Pull every figure and its scoped CSS. Returns (theme_css, css, figs)."""
    theme, css, figs = [], [], {}
    for key, (chart, idx, wrap) in FIGURES.items():
        raw, found = figure_of(chart)
        t, rules = scope_css(raw, wrap)
        for b in t:
            if b not in theme:
                theme.append(b)          # tokens are shared; declare each once
        css.extend(rules)
        fig, legend = found[idx]
        figs[key] = '<div class="%s">%s%s</div>' % (wrap, fig, legend)
    return theme, css, figs


def figure(n, key, title, caption, figs):
    """A figure is a takeaway title, the chart, then its numbered caption."""
    return ('<figure class="fig"><h4 class="figtitle">{}</h4>{}\n'
            '<figcaption><span class="fignum">Figure {}.</span> {}</figcaption>'
            '</figure>').format(title, figs[key], n, caption)


_HATCH_IDS = {'s1': 'hatch-s1', 's2': 'hatch-s2', 's3': 'hatch-s3'}


def _hypothetical_wrap(svg_body, viewbox_w, viewbox_h, label):
    """Wraps a chart body in the shared 'this is not the data' styling: a
    dashed border, one diagonal-hatch pattern per scenario colour (SVG
    <pattern> content does not inherit a referencing element's local custom
    properties, only :root-level ones, so each scenario needs its own named
    pattern rather than one pattern parameterised by class), and an explicit
    banner. Used only for sensitivity-test charts -- never for a primary
    finding, which must stay visually distinct at a glance, not just by
    reading the caption."""
    patterns = ''.join(
        '<pattern id="{pid}" width="6" height="6" patternTransform="rotate(45)" '
        'patternUnits="userSpaceOnUse"><rect width="6" height="6" fill="var(--{cls}-fill)" '
        'fill-opacity=".28"/><line x1="0" y1="0" x2="0" y2="6" stroke="var(--{cls}-fill)" '
        'stroke-width="2.5"/></pattern>'.format(pid=pid, cls=cls)
        for cls, pid in _HATCH_IDS.items())
    return (
        '<div class="hypothetical">'
        '<p class="hyplabel">HYPOTHETICAL: SENSITIVITY TEST, NOT THE UNDERLYING DATA</p>'
        '<div class="figure"><svg viewBox="0 0 {w} {h}" role="img" aria-label="{label}">'
        '<defs>{patterns}</defs>'
        '{body}</svg></div></div>'
    ).format(w=viewbox_w, h=viewbox_h, label=label, patterns=patterns, body=svg_body)


def scenario_chart():
    """Grouped bars: five conditions' share of diagnosed spend across the
    three pricing scenarios (as billed / pregnancy-only-repriced / all-eleven
    -repriced). Data from q1_scenario_comparison_2020_2024.csv, itself
    q1_multi_condition_sensitivity.sql part 3."""
    rows = [
        ('Pregnancy', 39.81, 7.15, 14.74),
        ('Allergy', 11.88, 18.33, 0.42),
        ('Gingivitis', 11.74, 18.11, 2.98),
        ('Kidney disease st.4', 6.04, 9.32, 19.21),
        ('NSCLC stage 1', 4.64, 7.16, 1.34),
    ]
    W, H = 700, 420
    left, right, top, bot = 150, 40, 20, 50
    plot_w, plot_h = W - left - right, H - top - bot
    max_v = 46.0
    group_h = plot_h / len(rows)
    bar_h = group_h / 4.2
    scen_labels = ['As billed', 'Pregnancy only', 'All eleven']
    scen_class = ['s1', 's2', 's3']
    body = []
    for gx in (0, 10, 20, 30, 40):
        x = left + (gx / max_v) * plot_w
        body.append('<line x1="{0:.1f}" y1="{1}" x2="{0:.1f}" y2="{2}" class="grid"/>'
                     '<text x="{0:.1f}" y="{2}" dy="16" class="axis">{3}%</text>'
                     .format(x, top, top + plot_h, gx))
    for i, (name, v1, v2, v3) in enumerate(rows):
        gy = top + i * group_h
        body.append('<text x="{0}" y="{1:.1f}" class="catlabel">{2}</text>'
                     .format(left - 12, gy + group_h / 2 + 4, name))
        for j, (val, cls) in enumerate(zip((v1, v2, v3), scen_class)):
            by = gy + 6 + j * (bar_h + 4)
            bw = (val / max_v) * plot_w
            body.append('<rect x="{0}" y="{1:.1f}" width="{2:.1f}" height="{3:.1f}" '
                        'rx="2" class="bar" fill="url(#{4})"/>'
                        '<text x="{5:.1f}" y="{6:.1f}" class="barval">{7:.1f}%</text>'
                        .format(left, by, bw, bar_h, _HATCH_IDS[cls],
                                left + bw + 6, by + bar_h / 2 + 4, val))
    legy = top + plot_h + 22
    for k, (lbl, cls) in enumerate(zip(scen_labels, scen_class)):
        lx = left + k * 170
        body.append('<rect x="{0}" y="{1}" width="12" height="12" class="bar" '
                     'fill="url(#{2})"/>'
                     '<text x="{3}" y="{4}" class="leglabel">{5}</text>'
                     .format(lx, legy, _HATCH_IDS[cls], lx + 18, legy + 10, lbl))
    return _hypothetical_wrap(''.join(body), W, H,
        'Five conditions\' share of diagnosed spend under three pricing scenarios')


def concentration_chart():
    """Three bars: the priciest 1% of members' share of total spend, under
    the same three scenarios. Data from q1_pregnancy_sensitivity.sql part 2
    and q1_multi_condition_sensitivity.sql part 2."""
    rows = [('As billed', 11.8), ('Pregnancy only repriced', 15.4),
            ('All eleven repriced', 12.5)]
    W, H = 700, 220
    left, right, top, bot = 190, 60, 20, 30
    plot_w, plot_h = W - left - right, H - top - bot
    max_v = 18.0
    bar_h = plot_h / len(rows) / 1.8
    gap = plot_h / len(rows)
    body = []
    for gx in (0, 5, 10, 15):
        x = left + (gx / max_v) * plot_w
        body.append('<line x1="{0:.1f}" y1="{1}" x2="{0:.1f}" y2="{2}" class="grid"/>'
                     '<text x="{0:.1f}" y="{2}" dy="16" class="axis">{3}%</text>'
                     .format(x, top, top + plot_h, gx))
    for i, (name, val) in enumerate(rows):
        y = top + i * gap + gap / 2 - bar_h / 2
        bw = (val / max_v) * plot_w
        cls = 's2' if 'Pregnancy' in name else ('s3' if 'eleven' in name else 's1')
        body.append('<text x="{0}" y="{1:.1f}" class="catlabel">{2}</text>'
                     '<rect x="{3}" y="{4:.1f}" width="{5:.1f}" height="{6:.1f}" '
                     'rx="2" class="bar" fill="url(#{7})"/>'
                     '<text x="{8:.1f}" y="{9:.1f}" class="barval">{10:.1f}%</text>'
                     .format(left - 12, y + bar_h / 2 + 4, name,
                             left, y, bw, bar_h, _HATCH_IDS[cls],
                             left + bw + 8, y + bar_h / 2 + 4, val))
    return _hypothetical_wrap(''.join(body), W, H,
        'Priciest 1% of members\' share of total spend under three pricing scenarios')


def build():
    verify_sources()
    theme, css, figs = collect()
    o = ['<title>Calder Health: Five-Year Claims Analysis</title>',
         '<style>', PAGE_CSS, '\n'.join(theme), '\n'.join(css),
         # the one token the charts disagree on
         '.fig-places .rest{fill:#d2d0ca;}',
         '@media (prefers-color-scheme:dark){:root:not([data-theme="light"]) '
         '.fig-places .rest{fill:#3a3936;}}',
         '</style>',
         '<div class="wrap">', HEADER, ABOUT, DATASECTION, HOWTOREAD, NOTANSWERED,
         NORTHSTAR, SUMMARY,
         '<h2 class="sec">The findings</h2>']

    for i, f in enumerate(FINDINGS, 1):
        o.append('<section class="finding"><h3><span class="fno">Finding %d</span>%s</h3>'
                 % (i, f['title']))
        for n, key, title, cap in f['figures']:
            o.append(figure(n, key, title, cap, figs))
        o.append('<div class="prose"><p>%s</p></div>' % f['para'])
        if f.get('extra'):
            o.append(f['extra'])
        o.append('<div class="sowhat"><p class="swhd">So what</p><p>%s</p></div>'
                 % f['sowhat'])
        o.append('<div class="examined"><p class="exhd">What was examined</p><ul>%s</ul></div>'
                 % ''.join('<li>%s</li>' % b for b in f['examined']))
        o.append(sources_block(i - 1))
        o.append('</section>')

    o.append(RECOMMENDATIONS)
    o.append(APPENDIX)
    o.append(FOOTER)
    o.append('</div>')
    return '\n'.join(o) + '\n'


PAGE_CSS = '''
/* Spacing is one 4px scale: 4 8 12 16 24 32 48 64. No value off it. */
:root{--surface-1:#fcfcfb;--surface-2:#fff;--text-primary:#111110;--text-secondary:#4a4946;
--text-muted:#63625c;--rule:#d8d6d0;--rule-strong:#94928b;--accent:#1d64b8;--card:#fff;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#171716;
--surface-2:#1f1f1e;--text-primary:#fff;--text-secondary:#c9c8bd;--text-muted:#a3a199;
--rule:#403f3b;--rule-strong:#6b6962;--accent:#7fb0ea;--card:#212120;}}
:root[data-theme="dark"]{--surface-1:#171716;--surface-2:#1f1f1e;--text-primary:#fff;
--text-secondary:#c9c8bd;--text-muted:#a3a199;--rule:#403f3b;--rule-strong:#6b6962;
--accent:#7fb0ea;--card:#212120;}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:48px 24px 64px;
font:16px/1.65 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:860px;margin:0 auto;}
h1.title{font-size:30px;line-height:1.2;letter-spacing:-.02em;margin:0 0 12px;}
.standfirst{font-size:17px;color:var(--text-secondary);margin:0 0 8px;max-width:64ch;}
.meta{font-size:13px;color:var(--text-muted);margin:0;}
h2.sec{font-size:19px;letter-spacing:-.01em;margin:48px 0 16px;padding-bottom:8px;
border-bottom:1px solid var(--rule-strong);}
h3.subsec{font-size:16px;font-weight:650;margin:24px 0 8px;color:var(--text-primary);}
h3{font-size:20px;line-height:1.3;letter-spacing:-.01em;margin:0 0 24px;}
.fno{display:block;font-size:13px;color:var(--text-muted);font-weight:400;margin-bottom:4px;}
p{margin:0 0 12px;}
ul{margin:0 0 12px;padding-left:24px;}
li{margin-bottom:8px;color:var(--text-secondary);}
li strong,p strong{color:var(--text-primary);}
.mission{font-size:15px;line-height:1.55;margin:0 0 16px;padding:16px;
background:var(--card);border:1px solid var(--rule);border-radius:4px;}
/* Metrics are a plain three-row table, not a row of boxes. */
table.metrics{width:100%;border-collapse:collapse;margin:0 0 8px;}
table.metrics th{text-align:left;font-size:13px;font-weight:650;color:var(--text-secondary);
padding:12px 16px 12px 0;border-bottom:1px solid var(--rule);white-space:nowrap;
vertical-align:baseline;}
table.metrics td.val{font-size:24px;font-weight:650;letter-spacing:-.02em;padding:12px 24px 12px 0;
border-bottom:1px solid var(--rule);white-space:nowrap;vertical-align:baseline;}
table.metrics td.note{font-size:14px;color:var(--text-secondary);padding:12px 0;
border-bottom:1px solid var(--rule);vertical-align:baseline;}
table.metrics td.note a{color:var(--text-muted);font-size:12.5px;text-decoration:none;}
table.metrics td.note a:hover{color:var(--accent);text-decoration:underline;}
@media (max-width:640px){table.metrics,table.metrics tbody,table.metrics tr,
table.metrics th,table.metrics td{display:block;width:auto;border:0;padding:0;white-space:normal;}
table.metrics tr{border-bottom:1px solid var(--rule);padding:12px 0;}
table.metrics td.val{font-size:24px;padding:4px 0;}}
.callout{background:var(--card);border:1px solid var(--rule);border-radius:4px;
padding:24px;margin:0 0 8px;}
.callout p{font-size:15px;color:var(--text-secondary);margin:0 0 12px;}
.callout p:last-child{margin:0;}
.callout strong{color:var(--text-primary);}
.decisionbox{border:1px solid var(--rule-strong);border-radius:4px;padding:20px 24px;margin:16px 0 8px;}
.dbhd{font-size:13px;font-weight:650;letter-spacing:.04em;text-transform:uppercase;
color:var(--text-primary);margin:0 0 12px;}
.dbcols{display:grid;grid-template-columns:1fr 1fr;gap:24px;}
@media (max-width:640px){.dbcols{grid-template-columns:1fr;}}
.dblbl{font-size:13px;font-weight:650;color:var(--text-primary);margin:0 0 6px;}
.dbcols ul{margin:0;padding-left:18px;}
.dbcols li{font-size:14px;margin-bottom:6px;}
.summary li{font-size:16px;margin-bottom:12px;}
section.finding{margin:0 0 48px;}
figure.fig{margin:0 0 24px;}
.figtitle{font-size:16px;line-height:1.4;font-weight:650;margin:0 0 12px;
color:var(--text-primary);}
figure.fig + figure.fig{margin-top:32px;}
figcaption{font-size:13px;color:var(--text-secondary);margin:8px 0 0;line-height:1.5;}
.fignum{color:var(--text-primary);font-weight:650;}
.prose{margin-top:24px;}
.prose p{font-size:16px;color:var(--text-secondary);}
.hypothetical{margin-top:16px;border:2px dashed var(--rule-strong);border-radius:6px;
padding:16px;background:var(--surface-1);}
.hyplabel{font-size:11px;font-weight:700;letter-spacing:.06em;color:var(--text-muted);
margin:0 0 12px;}
.hypothetical .figure{overflow-x:auto;}
.hypothetical svg{display:block;width:100%;height:auto;min-width:520px;}
:root{--s1-fill:#8a8778;--s2-fill:#b0723e;--s3-fill:#3f6674;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
--s1-fill:#a5a293;--s2-fill:#cf9a68;--s3-fill:#6ea2b3;}}
:root[data-theme="dark"]{--s1-fill:#a5a293;--s2-fill:#cf9a68;--s3-fill:#6ea2b3;}
.hypothetical .grid{stroke:var(--rule);stroke-width:1;}
.hypothetical .axis{fill:var(--text-muted);font-size:11px;text-anchor:middle;}
.hypothetical .catlabel{fill:var(--text-primary);font-size:12.5px;text-anchor:end;
dominant-baseline:middle;}
.hypothetical .barval{fill:var(--text-secondary);font-size:11.5px;}
.hypothetical .leglabel{fill:var(--text-secondary);font-size:12px;}
.hypothetical .bar{stroke:var(--rule-strong);stroke-width:1;}
h3.apphd{font-size:16px;font-weight:650;margin:32px 0 12px;color:var(--text-primary);}
table.apptable{width:100%;border-collapse:collapse;font-size:14.5px;margin:0 0 4px;}
table.apptable th{text-align:left;color:var(--text-muted);font-weight:650;font-size:12.5px;
letter-spacing:.03em;text-transform:uppercase;padding:8px 14px 8px 0;border-bottom:1px solid var(--rule-strong);}
table.apptable td{padding:10px 14px 10px 0;border-bottom:1px solid var(--rule);color:var(--text-secondary);}
table.apptable td:first-child{color:var(--text-primary);font-weight:600;}
.appnote{font-size:13.5px;color:var(--text-muted);margin:10px 0 28px;line-height:1.55;}
.minitable{margin-top:16px;}
.mtcap{font-size:13px;font-weight:650;color:var(--text-primary);margin:0 0 8px;}
.minitable table{width:100%;border-collapse:collapse;font-size:14px;}
.minitable th{text-align:left;color:var(--text-muted);font-weight:650;font-size:12.5px;
padding:6px 12px 6px 0;border-bottom:1px solid var(--rule-strong);}
.minitable td{padding:8px 12px 8px 0;border-bottom:1px solid var(--rule);color:var(--text-secondary);}
.minitable td:first-child{color:var(--text-primary);}
.mtnote{font-size:13.5px;color:var(--text-muted);margin:10px 0 0;line-height:1.5;}
.sowhat{margin-top:16px;padding:16px;background:var(--card);
border:1px solid var(--rule);border-radius:4px;}
.swhd{font-size:13px;font-weight:650;color:var(--text-primary);margin:0 0 4px;}
.sowhat p:last-child{font-size:16px;line-height:1.6;color:var(--text-secondary);margin:0;}
.examined{margin-top:16px;}
.exhd{font-size:13px;font-weight:650;color:var(--text-primary);margin:0 0 8px;}
.examined ul{margin:0;}
.examined li{font-size:15px;}
.rec-block{margin:0 0 24px;padding:16px 20px;background:var(--card);
border:1px solid var(--rule);border-radius:4px;}
.rec-block:last-child{margin-bottom:0;}
.rec-block h4{font-size:16px;font-weight:650;margin:0 0 12px;color:var(--text-primary);
line-height:1.4;}
.rec-body{font-size:15px;line-height:1.6;color:var(--text-secondary);margin:0 0 10px;}
.rec-body:last-child{margin-bottom:0;}
.rec-label{color:var(--text-primary);font-weight:650;}
.recgate{margin:0 0 24px;padding:12px 16px;border-left:3px solid var(--accent);
background:var(--card);font-size:14.5px;color:var(--text-secondary);line-height:1.55;}
details.sources{margin-top:16px;border-top:1px solid var(--rule);padding-top:12px;}
details.sources summary{cursor:pointer;font-size:13px;color:var(--text-muted);
font-weight:650;list-style:none;}
details.sources summary::-webkit-details-marker{display:none;}
details.sources summary::before{content:"+";display:inline-block;width:16px;font-weight:400;}
details.sources[open] summary::before{content:"\2212";}
details.sources ul{margin:12px 0 0;}
details.sources li{font-size:14px;margin-bottom:8px;}
details.sources a{color:var(--accent);}
details.sources a.csv{font-size:13px;color:var(--text-muted);margin-left:4px;}
footer{margin-top:48px;padding-top:16px;border-top:1px solid var(--rule-strong);
font-size:13px;color:var(--text-muted);}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;}
'''

HEADER = '''<h1 class="title">Where five years of spend went, and who carried it</h1>
<p class="standfirst">An analysis of 68.6 million claims across 1.26 million members,
2020 to 2024.</p>
<p class="meta">Prepared for Calder Health, 2026 planning cycle.</p>'''

ABOUT = '''<h2 class="sec">Client background</h2>
<p><strong>The brief.</strong> Before benefits are set and networks negotiated for 2026, Calder
Health asked three questions: where did the money go, who bore it, and where does it
concentrate?
Everything below answers those three and stops there.</p>
<p>Calder Health is a non-profit health plan headquartered in Cleveland, serving 1.26 million
members, with further concentrations in Chicago, Detroit and Northeast Ohio. Members are treated
across a network of 3,918 facilities, from single-site clinics to large teaching hospitals. That
network size is the reason the third question is worth asking at all: with nearly four thousand
places to look, knowing whether spending is spread across them or pooled in a few changes what any
review of the network would involve.</p>
<p>Calder runs two lines of business, and the difference between them is not administrative
detail. Finding 3 shows it produces one of the largest gaps in what members pay for identical
diagnoses that this analysis found, which makes it central to the second question rather than
background to it. (This report has not measured how that gap compares in size to other drivers of
member-paid share, such as condition or claim size, so it is described here as large, not as
largest.)</p>
<ul>
<li><strong>Commercial:</strong> employer group plans, built on a deductible and coinsurance with
an annual out-of-pocket maximum. A member pays a share of each bill until the annual maximum is
reached, after which the plan pays everything.</li>
<li><strong>Government:</strong> Medicaid and Medicare managed care, built on a flat copay per
visit. A member pays the same small amount whatever the bill comes to.</li>
</ul>
<p>Those two designs behave in opposite directions as a bill grows, so a single figure for
&ldquo;what members pay&rdquo; would average across two populations that never overlap. Every
figure below that can be split by line of business has been.</p>
<p class="mission"><strong>The mission this is measured against.</strong> To keep comprehensive
cover affordable for every member, in every place they seek care, measuring affordability by what
a member actually pays rather than by what a plan spends, and holding that standard equally across
commercial and government lines. That is why member-paid share sits among the headline metrics
rather than in an appendix, and why facilities are examined separately from conditions. Member-paid
share is a percentage of the bill, not a measure of hardship: a high share of a small bill and a
high share of a large one are different things, and this report is explicit about which is which
where it matters.</p>
<p>This analysis covered 68.6 million claims across five years in Snowflake, then focused on
diagnostic patterns and facility-level concentration to answer those three questions. What follows
is what that showed, together with the queries behind every figure so any of it can be
checked.</p>'''

DATASECTION = '''<h2 class="sec">About the data</h2>
<p>Claims were drawn from a read-only Snowflake share,
<code>SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER</code>, containing Synthea-generated
synthetic healthcare records: 887 million claim transactions across 124 million claims and
1.4 million simulated patients in total.</p>
<p><strong>Time frame.</strong> All figures cover <strong>1 January 2020 to 31 December 2024</strong>,
five complete years. The window matters: unfiltered, the source spans simulated history back to
1914, and cumulative totals taken across it are not meaningful. Within the window the analysis
covers <strong>68.6 million claims, 1,259,375 patients and $99.11 billion billed</strong>.</p>
<p><strong>Tables used.</strong></p>
<ul>
<li><code>SILVER.CLAIMS</code>: diagnosis fields, used to attach spend to a condition.</li>
<li><code>SILVER.ENCOUNTERS</code>: visit class, dates and the facility each visit belongs
to.</li>
<li><code>SILVER.ORGANIZATIONS</code>: facility name and city.</li>
<li><code>SILVER.PATIENTS</code>: dates of birth, used only for the age check behind the
preventive-care question.</li>
</ul>
<p>Two curated objects sit in front of the raw share and every query reads through them, because
the source carries traps that return confident, plausible, wrong answers rather than errors:</p>
<ul>
<li><code>V_CLAIMS_TX_CLEAN</code>: claim transactions with the money columns corrected,
payer collapsed to type, administrative rows flagged, and the date window applied.</li>
<li><code>CODE_DICTIONARY</code>: 1,453 rows mapping every clinical code to one canonical
name and category, resolving all nine code fields.</li>
</ul>
<p><strong>Data dictionary.</strong> Full table and column references, together with the known
traps in the source data, are documented in
<a href="../DATA_ANALYSIS_CONTEXT.md">DATA_ANALYSIS_CONTEXT.md</a> &sect;25&ndash;26. Every figure
in this report traces to a saved query in <code>sql/analysis/</code> and a result file in
<code>sql/results/</code>.</p>'''

HOWTOREAD = '''<h2 class="sec">Things to be aware of before proceeding</h2>
<div class="callout">
<p><strong>The patterns are internally consistent within this synthetic dataset, but real claims
validation is required before using them for operational, pricing, or benefit decisions.</strong>
Nothing below is safe to treat as a forecast or a budgeting input on its own.</p>
<p><strong>What is internally consistent.</strong> Rankings, shares, ratios and concentration hold
together and were each tested more than one way inside this dataset: the concentration result
was measured across four separate groupings, the member-paid-share pattern was re-checked inside
each line of business on its own, and the facility spread was retested with every procedure
repriced to a common rate. That is evidence the patterns are not an artefact of one calculation.
It is not evidence they match the real world, which this dataset cannot supply on its own.</p>
<p><strong>A known pricing defect, tested at two widths.</strong> This data prices a normal
pregnancy at roughly 8.6&times; a comparable real-world figure (Peterson-KFF Health System Tracker,
2022: ~$18,865 for a full pregnancy episode, against $161,988 here). That is not the only condition
priced this way. Checked one at a time against a named benchmark, eleven of the twenty highest-cost
conditions carry a similar, well-grounded defect, from 3.8&times; (stroke) to roughly 90&times;
(allergy immunotherapy, at the procedure level). Three bounded &ldquo;what if&rdquo; tests were
run, none of which rescales anything in the underlying data:</p>
<p><strong>Test 1: correct pregnancy alone</strong> (<code>q1_pregnancy_sensitivity.sql</code>).
Pregnancy&rsquo;s rank drops from 1st to 5th and its share of diagnosed spend from 39.8% to 7.1%.
Patient-level concentration (Finding 4) moves the opposite way from what a reader might expect:
repriced, the top 1% of members carry MORE of total spend, 15.4% against 11.8% as billed.</p>
<p><strong>Test 2: correct all eleven together</strong>
(<code>q1_multi_condition_sensitivity.sql</code>). Five more conditions with a similarly large gap
(cardiac imaging findings, small cell lung cancer, child ADHD, ischemic heart disease, dependent
drug abuse) were deliberately left uncorrected: each carries many claims spread across the
five-year window with no fixed visit cadence to anchor a correction on, unlike dialysis&rsquo;s
known three-times-weekly schedule, so no defensible single factor exists for them. Even with only
eleven of twenty corrected, the ranking reshuffles far more than test 1 alone suggested. Pregnancy
falls to 2nd (14.7%). Chronic kidney disease, never touched because it was already checked and
found NOT inflated, rises to 1st (19.2%) purely because everything around it got smaller. The
top-5 share of diagnosed spend falls from 74.1% as billed to 47.2%; the top-20 share falls from
90.8% to 78.3%, a much larger movement than test 1&rsquo;s 90.8%-to-85.8%. And patient-level
concentration REVERSES test 1&rsquo;s result: correcting all eleven brings the top 1% back down to
12.5%, close to the as-billed 11.8%, not the 15.4% test 1 found. <strong>The direction of that
specific effect is itself sensitive to how many conditions are corrected, and should not be read
as settled in either direction.</strong> An earlier version of this disclosure treated
test 1&rsquo;s result as evidence Finding 4 was conservative; that does not hold once more of the
known defects are corrected together, and is not asserted below.</p>
<p><strong>Test 3: what the correction does to the other two headline numbers</strong>
(<code>q1_robustness_three_findings.sql</code>). The member-paid share of 20.4% does NOT hold:
corrected, it rises to <strong>23.3%</strong>. That reads backwards at first, because the dollars
members pay fall at the same time, from $20.3B to $11.4B. Both are true and the reason is mix, not
members paying more. The eleven corrected conditions carry $54.9B at a 17.7% member share, while
everything untouched carries $44.2B at 23.8%; shrinking the low-share group by around ninety per
cent leaves the blend dominated by the high-share remainder, landing just under that
remainder&rsquo;s own figure. The commercial-against-government gap behaves in the opposite way and
is <strong>exactly unchanged</strong>, to the decimal, for every condition tested: pregnancy stays
at 25.2 times, gingivitis at 17.1, allergy at 9.4. Scaling a bill and what was paid on it by the
same factor cancels in a ratio, so that finding is immune to this entire class of defect rather
than merely surviving it.</p>
<p><strong>What actually survives these tests, and what does not.</strong> That roughly twenty
conditions account for most (not all) diagnosed spend holds under both, though "most" ranges from
78% to 91% depending on which correction is applied. Which single condition leads, and by how
much, does not survive either test, and does not survive consistently in the same direction:
pregnancy, allergy and NSCLC all lose their as-billed rank; CKD-4 gains one it never had.
Patient-level concentration survives as a qualitative fact (spend is concentrated in a minority of
patients either way) but its exact magnitude moves in different directions depending on the test,
so no specific percentage for it should be treated as final. Each finding below states which of
these categories it falls into. No number in this report has been rescaled to correct for any of
this outside these three clearly labeled tests; none of Synthea&rsquo;s other procedure prices have
been checked against a real-world benchmark at all, and the five conditions above were left
uncorrected because no defensible factor exists for them, not because they are known to be
fine.</p>
<p><strong>Outside the scope of this data entirely.</strong> Negotiated rates, denials, bad debt and
collections. Every claim here is paid in full and no provider is charged differently from any
other, so those are properties of the simulation rather than findings about Calder. Answering
them, and any business conclusion about whether a given facility&rsquo;s prices are fair,
negotiable, or otherwise actionable, would need real contract and remittance data.</p>
</div>
<div class="decisionbox">
<p class="dbhd">Decision-use boundary</p>
<div class="dbcols">
<div><p class="dblbl">Safe to use for</p><ul>
<li>Internal pattern discovery: where spend and member cost concentrate, and along which
lines</li>
<li>Prioritising what to investigate next with real claims and contract data</li>
<li>Demonstrating the analytical method on a full five-year dataset before it is pointed at
production data</li>
</ul></div>
<div><p class="dblbl">Not safe to use for</p><ul>
<li>Negotiated-rate or provider-pricing decisions</li>
<li>Actuarial pricing or reserving</li>
<li>Benefit-design changes made on these figures alone</li>
<li>Real-world cost forecasts without separate validation against actual claims</li>
</ul></div>
</div>
</div>'''

NORTHSTAR = '''<h2 class="sec">The three numbers Calder steers by</h2>
<table class="metrics"><tbody>
<tr><th>Total cost of care</th><td class="val">$99.1B</td>
<td class="note">Billed across five years. $72.7B of it attaches to a specific diagnosis; the rest
is care recorded without one.
<a href="../sql/analysis/q1_cost_drivers.sql">q1_cost_drivers.sql</a></td></tr>
<tr><th>Member-paid share</th><td class="val">20.4%</td>
<td class="note">$20.3B paid out of pocket: $16,084 average member-paid spending per enrolled
member over five years (median $7,026: the average sits well above the typical member's
figure, pulled up by a right-skewed tail). This is the number the mission lives or dies on.
Corrected for known pricing defects it rises to 23.3%, while the dollars members pay fall to
$11.4B, which is a change in the mix rather than in what members pay (Finding 2).
<a href="../sql/analysis/q2_who_pays.sql">q2_who_pays.sql</a>,
<a href="../sql/analysis/q2_member_paid_percentiles.sql">q2_member_paid_percentiles.sql</a></td></tr>
<tr><th>Spend concentration</th><td class="val">86 sites</td>
<td class="note">Of 3,918 facilities, 86 carry half of all spending. A list short enough to work
through by hand.
<a href="../sql/analysis/q3_concentration.sql">q3_concentration.sql</a></td></tr>
</tbody></table>'''

SUMMARY = '''<h2 class="sec">Executive summary</h2>
<ul class="summary">
<li><strong>Diagnosed spend concentrates in about twenty conditions, not hundreds.</strong> They
carry 91% of the $72.7B that can be attributed to a diagnosis. Which single condition leads, and by
how much, is sensitive to a known pricing defect: as billed, pregnancy is 39.8% of that total, but
correcting the eleven conditions with a documented pricing gap drops it to 2nd place and 14.7%,
and puts chronic kidney disease first at 19.2% without it ever being corrected
(<code>q1_multi_condition_sensitivity.sql</code>). The twenty-conditions concentration is the
finding to carry forward; the identity and size of the single largest one is not.</li>
<li><strong>Members pay a larger share of the bill for cheaper care.</strong> Member-paid share runs
from 8.3% to 38.9% of the bill by type of care and is highest for the least expensive kinds, a
pattern that holds under price correction (the median stays at 20.6% and the top at 38.9%; only
the bottom of the range moves, to 7.4%). That is a statement about percentage share, not about
dollars paid: the categories with the highest share are not the ones with the highest typical
dollar amount paid, which is a separate result (Finding 2).</li>
<li><strong>Member-paid share differs sharply by plan type, even within the same condition.</strong>
On all ten of the conditions where members carry the most, commercial members pay a larger
share than government members, by between 12.9 and 78.1 percentage points. Obesity and
prediabetes show the widest gap, at 86.8% against 8.7% and 85.0% against 8.5% within the same
condition, not necessarily matched on setting, severity or the specific services billed. This is
the one finding here that price correction leaves exactly unchanged, because scaling a bill and
what was paid on it by the same factor cancels in a ratio.</li>
<li><strong>Member spending is less concentrated than facility spending in this synthetic
population.</strong> 86 of 3,918 facilities carry half the money; reaching the same half through
members takes 134,198 people. Real claims populations concentrate member spending more heavily at
the very top (roughly 20&ndash;25% in the top 1%, against 11.8% here), so this comparison may
understate how concentrated member spending would look against real claims data.</li>
<li><strong>Within this simulated pricing structure, facility cost differences are driven mainly by
case mix, not by modelled price variation.</strong> Repricing every procedure to a common rate
barely moves the spread between the cheapest and priciest facility. This dataset does not model
realistic, provider-specific negotiated rates, so it cannot support a conclusion about whether any
facility's real prices are negotiable or fair; assessing that would need real negotiated-rate
data.</li>
</ul>'''

NOTANSWERED = '''<h3 class="subsec">What this analysis could not answer</h3>
<p>Stated plainly so that silence is not mistaken for a clean bill of health.</p>
<ul>
<li><strong>Whether members skip preventive care.</strong> Wellness visits reach 1,259,199 of the
1,259,375 members, and the small variation that exists tracks who is in each group rather than
what they received. The data schedules these visits by protocol, so it cannot show anyone
declining or missing care. The answerable neighbour of this question is Finding 2.
(<code>q3_preventive_access.sql</code>)</li>
<li><strong>Whether any facility is efficient.</strong> Every difference between sites resolves to
what they treat. Prices barely vary, and neither does the amount of work done for a given
condition.</li>
<li><strong>Anything about denials, collections or bad debt.</strong> Every claim in this data is
paid in full.</li>
<li><strong>Whether this membership is sicker or healthier than the market.</strong> The
population is generated, not observed, and its very sickest members are under-represented compared
with real claims data.</li>
</ul>'''

RECOMMENDATIONS = '''<h2 class="sec">Recommendations</h2>
<p>Six priorities, each tied directly to the evidence above. They are ordered by what has to
happen first, not by size of prize: recommendation 1 is a gate on several of the others, and
where that is true it is said explicitly. Consistent with the decision-use boundary set out
earlier, these are investigation and validation priorities against real claims data, not benefit
or pricing changes to make on these figures alone.</p>

<div class="recgate"><strong>Read 1 first.</strong> Eleven of the twenty highest-cost conditions
carry a documented pricing gap, and correcting them reorders Finding 1 and moves Finding 2&rsquo;s
dollar figures substantially. Recommendations 2 and 4 depend on numbers that recommendation 1 is
designed to settle. Recommendations 3, 5 and 6 do not, and can proceed in parallel.</div>

<div class="rec-block">
<h4>1. Reprice the eleven flagged conditions against real claims before any 2026 budgeting</h4>
<p class="rec-body"><span class="rec-label">Getting started:</span> Pull real per-episode costs
for maternity and allergy immunotherapy from actual claims and contract data over the same
2020&ndash;2024 window, then re-run <code>q1_multi_condition_sensitivity.sql</code> substituting
those real factors for the benchmark-derived ones already in it. The query is written to take a
factor per condition, so this is a substitution rather than a rebuild.</p>
<p class="rec-body"><span class="rec-label">Why it matters:</span> As billed, pregnancy is 39.8%
of diagnosed spend and leads by more than three times (<strong><em>Figure 1</em></strong>).
Corrected, it falls to 2nd at 14.7% and chronic kidney disease takes 1st at 19.2% without ever
being corrected itself. That is not a refinement of the priority list, it is a different list.
Allergy immunotherapy leaves the top twenty altogether once corrected, and eight conditions that
appear nowhere in <strong><em>Figure 2</em></strong> enter it.</p>
<p class="rec-body"><span class="rec-label">How this helps:</span> This is the one item that
unblocks others rather than standing alone. Until it is done, any 2026 budget line built on the
as-billed condition ranking is built on a number known to be roughly 8.6&times; wrong for the
single largest contributor, and the maternity out-of-pocket figure behind recommendation 4 is
unsettled in the same way.</p>
</div>

<div class="rec-block">
<h4>2. Start clinical review with chronic kidney disease, not with the largest as-billed line</h4>
<p class="rec-body"><span class="rec-label">Getting started:</span> Convene clinical review of the
CKD stage 4 and end-stage renal cohort, 37,037 members at 258.5 claims each, and frame the
question as whether the dialysis pathway sits at the right site of care rather than whether the
spend is too high.</p>
<p class="rec-body"><span class="rec-label">Why it matters:</span> CKD rises to first place under
correction precisely because it was checked and found not inflated
(<strong><em>Figure 2</em></strong>), so it is the top-of-list condition least likely to be an
artefact. Its cost is volume, not price: 258.5 claims per member is a patient on dialysis three
times a week, which is care working as intended. That makes it a capacity and network question
with a real answer, unlike the conditions whose position depends on recommendation 1.</p>
<p class="rec-body"><span class="rec-label">How this helps:</span> This is deliberately narrower
than a review of the whole top twenty. A 37,037-member cohort is small enough for actual case
review; gingivitis, at 800,475 members and 6.9 claims each, is expensive for the opposite reason
and would need a population-level intervention rather than clinical review. Starting where the
number is trustworthy and the cohort is reviewable avoids spending the first review cycle on a
condition recommendation 1 may reorder.</p>
</div>

<div class="rec-block">
<h4>3. Reopen commercial cost-sharing for the two metabolic conditions with the widest gap</h4>
<p class="rec-body"><span class="rec-label">Getting started:</span> Model what an obesity or
prediabetes claim costs a commercial member against a government member under the current
deductible-and-coinsurance design, and test a capped-coinsurance or copay carve-out variant for
those two conditions in the 2026 benefit modelling.</p>
<p class="rec-body"><span class="rec-label">Why it matters:</span> Commercial members carry 86.8%
of an obesity bill against 8.7% for government members, and 85.0% against 8.5% for prediabetes
(<strong><em>Figure 5</em></strong>). Those two separate furthest from the other eight, which sit
between 13 and 48 points, and the gap holds in all five years measured. It is also the one
finding in this report that price correction leaves exactly unchanged, to the decimal, because
scaling a bill and what was paid on it by the same factor cancels in a ratio.</p>
<p class="rec-body"><span class="rec-label">How this helps:</span> Of the six, this is the
recommendation to pursue with the most confidence, and the reason is structural rather than a
matter of degree: it is immune to the defect that reshapes recommendations 1, 2 and 4 rather than
merely surviving it. It can therefore run in parallel with the repricing work instead of waiting
behind it. What this analysis has not established is how much of member-paid share plan type
explains against condition, care type or claim size, so the modelling should treat the gap as
real and large, not as proof that plan design is the dominant driver.</p>
</div>

<div class="rec-block">
<h4>4. Check maternity&rsquo;s real out-of-pocket exposure before the share ranking drives design</h4>
<p class="rec-body"><span class="rec-label">Getting started:</span> Pull the actual member
out-of-pocket distribution for maternity from real claims, median and 90th percentile, and
compare it against the annual out-of-pocket maximum currently set on the commercial plans.</p>
<p class="rec-body"><span class="rec-label">Why it matters:</span> Member-paid share is highest on
the cheapest care (<strong><em>Figures 3 and 4</em></strong>), so a benefit review organised
around the share ranking would start with blood disorders at 38.9% and diabetes at 36.6%. Both
have among the lowest typical dollar exposure measured, $179 and $233. Maternity ranks only 10th
by share at 17.0% and carries the highest, $10,765 median and $64,681 at the 90th percentile. The
share ranking and the dollar ranking point at different categories.</p>
<p class="rec-body"><span class="rec-label">How this helps:</span> It is also the clearest case
for doing recommendation 1 first, and the honest reason to check rather than act: corrected for
the pricing defect, maternity&rsquo;s median falls to $1,308 and it loses the top dollar-exposure
position entirely. So the finding that share and dollars diverge holds, but the specific category
at the top of the dollar ranking does not survive correction, and this check is what settles
which one belongs there.</p>
</div>

<div class="rec-block">
<h4>5. Build the facility review around the 86-site list, and do not build the member equivalent</h4>
<p class="rec-body"><span class="rec-label">Getting started:</span> Name the 86 facilities from
<code>q3_top_entities.sql</code> and split them into the three groups
<strong><em>Figure 8</em></strong> separates &mdash; the 12 dialysis-heavy sites, the 22 hospices
and nursing homes, and the rest &mdash; before any network conversation begins, since the three
groups are expensive for unrelated reasons.</p>
<p class="rec-body"><span class="rec-label">Why it matters:</span> 86 of 3,918 facilities carry
half of all spending, against 134,198 of 1,259,375 members for the same half
(<strong><em>Figures 6 and 7</em></strong>). Corrected for group size that is 2.2% against 10.7%,
and the facility curve bows sharply along its whole length while the member curve stays close to
even. 86 is a list a team can finish; 134,198 is not.</p>
<p class="rec-body"><span class="rec-label">How this helps:</span> The second half of this
recommendation matters as much as the first. Member-level concentration moved in both directions
under testing, 11.8% as billed, 15.4% correcting pregnancy alone, 12.5% correcting all eleven, so
it is not settled enough to size a high-cost-member program against. Published real-world figures
put the top 1% at roughly 20&ndash;25% against 11.8% here, which means real claims may support
member-level targeting that this synthetic population cannot &mdash; another reason to run that
question against real data rather than to conclude it is unavailable.</p>
</div>

<div class="rec-block">
<h4>6. Treat facility cost differences as case mix and site of care, not as a pricing lever</h4>
<p class="rec-body"><span class="rec-label">Getting started:</span> Investigate the pregnancy
site-of-delivery split &mdash; 95.5% of women give birth on site at the cheapest facilities
against 6.8% at the most expensive &mdash; to establish whether antenatal-clinic against
delivery-unit routing is a network design choice worth making deliberately. Do not open price
negotiations on the strength of this analysis.</p>
<p class="rec-body"><span class="rec-label">Why it matters:</span> Repricing every procedure to
its all-facility average moves the spread between cheapest and priciest facility only from
15.8&times; to 15.2&times; (<strong><em>Figure 8</em></strong>), so within this dataset&rsquo;s
own simulated prices the thirty-three-fold range in cost per member is what facilities treat, not
what they charge. The 7.8% figure quoted for this test is a median absolute deviation with no
consistent direction: 298 of 730 facilities, 41%, price below the case-mix benchmark rather than
above it.</p>
<p class="rec-body"><span class="rec-label">How this helps:</span> This is the finding most likely
to be misread as a negotiation opportunity, and the misreading is expensive in wasted effort. It
redirects the same attention somewhere it can pay: the dialysis group for capacity planning
against a fixed three-times-weekly schedule, which is where recommendation 2 also lands, and the
site-of-delivery split for routing. Assessing whether any real facility&rsquo;s prices are
negotiable would need real negotiated-rate data, which this dataset does not contain at all.</p>
</div>'''

APPENDIX = '''<h2 class="sec">Appendix: sensitivity to the known pricing defect</h2>
<p>The findings above show real, as-billed data throughout. Eleven of the twenty highest-cost
conditions carry a documented pricing gap against a named real-world benchmark (see &ldquo;Things
to be aware of before proceeding&rdquo;); this appendix tests each finding against a corrected
version of those eleven, side by side with the as-billed figure, rather than replacing any chart
with one. Full detail and every number here is sourced to
<code>q1_multi_condition_sensitivity.sql</code>, <code>q1_robustness_three_findings.sql</code> and
<code>q2_care_type_breakdown_repriced.sql</code>.</p>

<h3 class="apphd">Finding 1: which condition leads</h3>
<table class="apptable"><thead><tr><th>Measure</th><th>As billed</th><th>Price-corrected</th></tr></thead><tbody>
<tr><td>Largest condition</td><td>Normal pregnancy, 39.8%</td><td>Chronic kidney disease st.4, 19.2% (never itself corrected)</td></tr>
<tr><td>Pregnancy&rsquo;s rank</td><td>1st</td><td>2nd, at 14.7%</td></tr>
<tr><td>Top 5 share of diagnosed spend</td><td>74.1%</td><td>47.2%</td></tr>
<tr><td>Top 20 share of diagnosed spend</td><td>90.8%</td><td>78.3%</td></tr>
</tbody></table>
<p class="appnote">Eight conditions enter the corrected top twenty that were nowhere near the
as-billed one, including fracture of bone and infection of tooth. Allergy immunotherapy, whose own
gap (roughly 89&times;) is larger than pregnancy&rsquo;s, drops out of the top twenty entirely.
What survives either way: a minority of conditions carries most of diagnosed spend. What does not:
which one, and how large its lead is.</p>

<h3 class="apphd">Finding 2: what members pay</h3>
<table class="apptable"><thead><tr><th>Measure</th><th>As billed</th><th>Price-corrected</th></tr></thead><tbody>
<tr><td>Member-paid share, overall</td><td>20.4% ($20.3B)</td><td>23.3% ($11.4B)</td></tr>
<tr><td>Care-type share range</td><td>8.3% to 38.9%, median 20.6%</td><td>7.4% to 38.9%, median 20.6%</td></tr>
<tr><td>Maternity, median $ paid per member</td><td>$10,765</td><td>$1,308</td></tr>
<tr><td>Highest median $ exposure</td><td>Maternity</td><td>Infections (other), $1,456, unchanged</td></tr>
</tbody></table>
<p class="appnote">The share rises while the dollars fall, and both are true at once: the eleven
corrected conditions carry $54.9B at a 17.7% member share against $44.2B at 23.8% for everything
untouched, so shrinking the low-share group reweights the blend upward. Members are not paying
more. Separately, maternity&rsquo;s out-of-pocket figure, cited earlier in this project as the
clearest example of real dollar exposure, turns out to be mostly the pricing defect rather than a
finding about members.</p>

<h3 class="apphd">Finding 3: commercial against government</h3>
<table class="apptable"><thead><tr><th>Condition</th><th>As billed</th><th>Price-corrected</th></tr></thead><tbody>
<tr><td>Normal pregnancy</td><td>25.2&times;</td><td>25.2&times; (unchanged)</td></tr>
<tr><td>Gingivitis</td><td>17.1&times;</td><td>17.1&times; (unchanged)</td></tr>
<tr><td>Allergy to substance</td><td>9.4&times;</td><td>9.4&times; (unchanged)</td></tr>
</tbody></table>
<p class="appnote">Exactly unchanged, to the decimal, on every condition tested. Scaling a bill and
what was paid on it by the same factor cancels in a ratio, so this finding is immune to the entire
class of defect the other two are sensitive to, rather than merely robust to it.</p>
'''

FOOTER = '''<footer>Calder Health is an illustrative client. The analysis is real and reproducible;
every figure traces to a saved query in <code>sql/analysis/</code> and a result file in
<code>sql/results/</code>. Generated by <code>dashboard/generators/analysis_report.py</code>.
Edit the script, not this page.</footer>'''


# Which saved query established which numbers in each finding. Keep this honest:
# if a figure appears in the narrative, the query that produced it belongs here.
# Paths are relative to dashboard/, so the links work from a file:// open and
# from GitHub Pages alike. verify_sources() fails the build if one goes stale.
SOURCES = [
 [('q1_cost_drivers', 'the twenty largest conditions, their 90.8% and 66.6% shares, and pregnancy at $28.9B'),
  ('q1_spend_decomposition', 'the three drivers behind each condition, and the per-member re-ranking that moves gingivitis above lung cancer'),
  ('q1_condition_procedures', 'the check on whether pregnancy at 39.8% is credible',
   'q1_pregnancy_procedures_2020_2024.csv'),
  ('q1_hospital_cost_spread', 'whether facilities charge differently for the same condition'),
  ('q1_pregnancy_sensitivity', 'the sensitivity test: repricing pregnancy down 8.6x drops it to '
   '5th place and 7.1% of diagnosed spend, and moves patient-level concentration UP, not down'),
  ('q1_multi_condition_sensitivity', 'the extended test: correcting all eleven confidently-'
   'inflated conditions together puts kidney disease in 1st, drops the top-20 share to 78.3%, '
   'and moves patient-level concentration back DOWN, close to as-billed',
   'q1_multi_condition_sensitivity_ranking_2020_2024.csv')],
 [('q2_who_pays', 'the 20.4% member share, $20.3B, $16,084 each, and the 41.6% against 8.6% split by kind of visit'),
  ('q2_patient_cost_by_care_type', 'member share by type of care, including blood disorders at 38.9% and dental at 27.9% of $11.83B'),
  ('q2_pattern_within_payer', 'that the pattern strengthens rather than dissolves inside a single line of business'),
  ('q2_pattern_breakers', 'the two care types that appear to break the rule, and why neither does'),
  ('q2_oop_percentiles_by_care_type', 'the dollar side: median/P75/P90 out-of-pocket per affected '
   'member by type of care, which reorders the finding sharply'),
  ('q1_robustness_three_findings', 'that the 20.4% headline does NOT survive price correction: it '
   'rises to 23.3% while the dollars members pay fall to $11.4B, a mix effect')],
 [('q2_top10_share_by_payer_type', 'the ten conditions split by line of business, and the 12.9-point minimum gap'),
  ('q2_share_by_payer_type_yearly', 'that the gap holds in all five years rather than one'),
  ('q2_who_pays', 'the five-year totals of $19,178, $2,118 and $61,742'),
  ('q2_commercial_cap_by_care_type', 'the mechanism, measured by grouping claims into $500 bands'),
  ('q2_care_type_share_by_payer_type', 'the ranges a blended figure would hide'),
  ('q1_robustness_three_findings', 'that the commercial-against-government ratio is EXACTLY '
   'unchanged by price correction, on every condition tested, because scaling a bill and what '
   'was paid on it by the same factor cancels in a ratio')],
 [('q3_concentration', 'the 86 facilities and 134,198 members, and the 2.2% against 10.7% comparison'),
  ('q3_lorenz_points', 'the curve coordinates behind Figure 7'),
  ('q3_top_entities', 'which specific facilities and conditions make up the concentrated half')],
 [('q3_hospital_cost_intensity', 'the $4,401 to $144,422 range across facilities'),
  ('q3_price_vs_casemix', 'the repricing test: 15.8x to 15.2x, and the median ABSOLUTE deviation '
   'of 7.8% between actual and case-mix-equalised cost per visit (41% of facilities price below '
   'the benchmark, not above it -- the signed median is only 3.0%)'),
  ('q3_utilisation_or_composition', 'the typical spread in procedures per claim across sites for '
   'the median condition (IQR divided by median, i.e. (P75-P25)/median): 0.027'),
  ('q3_site_group_conditions', 'the top group broken down by condition, giving kidney disease at 53.1% of visits'),
  ('q3_site_group_top_conditions', 'which conditions specifically bring members into each kind of site'),
  ('q3_hospice_site_encounter_mix', 'the hospice group: 18.1% of visits, running 22 days and carrying half the billing'),
  ('q3_pregnancy_pathway_split', 'the pregnancy split, 95.5% delivering on site against 6.8%')],
]

NORTHSTAR_SRC = [('q1_cost_drivers', 'q2_who_pays'), ('q2_who_pays',), ('q3_concentration',)]


def _result_of(entry):
    """A query's result file. Usually <name>_2020_2024.csv, but not always --
    q1_condition_procedures writes q1_pregnancy_procedures, so entries may carry
    an explicit third element."""
    return entry[2] if len(entry) > 2 else '%s_2020_2024.csv' % entry[0]


def verify_sources():
    """Every cited query and result must exist. A dead citation is worse than none."""
    missing = []
    for group in SOURCES:
        for entry in group:
            q, csv = entry[0], _result_of(entry)
            for path in ('sql/analysis/%s.sql' % q, 'sql/results/%s' % csv):
                if not os.path.exists(os.path.join(ROOT, path)):
                    missing.append(path)
    if missing:
        raise SystemExit('cited sources do not exist:\n  ' + '\n  '.join(missing))


def sources_block(i):
    items = ''.join(
        '<li><a href="../sql/analysis/{q}.sql"><code>{q}.sql</code></a> '
        '<a class="csv" href="../sql/results/{csv}">results</a> '
        ': {what}</li>'.format(q=e[0], csv=_result_of(e), what=e[1])
        for e in SOURCES[i])
    return ('<details class="sources"><summary>Sources for this finding '
            ', {n} queries</summary><ul>{items}</ul></details>'
            .format(n=len(SOURCES[i]), items=items))


FINDINGS = [{'title': 'Diagnosed spend concentrates in about twenty conditions',
  'figures': [(1,
               'donut',
               'Pregnancy alone is two fifths of all diagnosed spending',
               'Diagnosed spend split by condition, 2020&ndash;2024, as billed. Each slice is '
               'one condition&rsquo;s share of the $72.7B that carries a diagnosis; pregnancy '
               'is the largest at 39.8% as billed, but its price is known to be inflated (see '
               'the paragraph below).'),
              (2,
               'top20',
               'Five conditions are three quarters of the bill, and the sixth drops below 2%',
               'The twenty largest conditions by total billed, as billed. The highlighted '
               'top bar is pregnancy, marked only because it is the outlier; every bar is '
               'measured the same way. Correcting known pricing defects reorders this list '
               'substantially, as the paragraph below sets out.')],
  'para': 'Both charts rank conditions by total billed, one as shares of the whole and one as '
          'a ranked bar for each. As billed, the distribution is severely top-heavy: normal '
          'pregnancy takes $28.9B on its own, 39.8% of the $72.7B that carries a diagnosis, '
          'more than three times the second-placed condition. That specific figure carries a '
          'known caveat, tested rather than assumed (see &ldquo;Things to be aware of&rdquo; '
          'above): correcting pregnancy alone against a real-world benchmark drops it to 5th '
          'place and 7.1% of diagnosed spend (<code>q1_pregnancy_sensitivity.sql</code>).'
          ' Ten more of the top twenty carry a similarly documented pricing gap, and correcting '
          'all eleven together moves the ranking much further '
          '(<code>q1_multi_condition_sensitivity.sql</code>): pregnancy falls to 2nd place '
          '(14.7%), and chronic kidney disease, never touched because it was already checked '
          'and found not inflated, rises to 1st (19.2%) purely because the conditions around '
          'it shrank. Allergy immunotherapy, whose own price gap is proportionally larger than '
          'pregnancy&rsquo;s ($11,122 a shot against a real-world $50&ndash;200), drops out of '
          'the top twenty entirely once corrected rather than moving up into it. What holds '
          'under both tests is the shape, not the identity of the leader, and even the shape '
          'moves more than a single-condition test suggests: all twenty conditions together '
          'are 90.8% of diagnosed spend as billed, 85.8% correcting pregnancy alone, and 78.3% '
          'correcting all eleven, against 66.6% of the $99.1B billed overall as billed. The '
          'gap between the diagnosed-spend and all-spend figures is the roughly quarter of '
          'spending that carries no diagnosis and sits outside these charts entirely.',
  'extra': scenario_chart(),
  'examined': ['Total billed per condition, ranked, against total billed per member: '
               'the two rankings disagree sharply and the disagreement is the point.',
               'Whether pregnancy at 39.8% is credible, and whether the ranking survives '
               'correcting it. The number of visits per pregnancy is plausible (11.1, against '
               'a historical ACOG standard of 12&ndash;14 in-person visits for a normal, '
               'low-risk pregnancy); the price per visit is not, and repricing it changes the '
               'ranking materially (<code>q1_pregnancy_sensitivity.sql</code>).',
               'Whether the top twenty are extreme on one driver or several. They are '
               'moderately extreme on all three at once ( members reached, visits each, '
               'cost per visit), and the multiplication does the rest.',
               'Whether facilities differ in what they charge for the same condition. For '
               'eight of the ten largest, barely at all.',
               'Whether correcting more than pregnancy changes the ranking further. It does, '
               'substantially: eleven of the top twenty conditions carry a similarly '
               'documented pricing gap, and correcting all eleven together drops the top-20 '
               'share to 78.3% and puts chronic kidney disease, not pregnancy, in first place '
               '(<code>q1_multi_condition_sensitivity.sql</code>).'],
  'sowhat': 'Five conditions are the first places to investigate, but they reach the top '
            'through very different combinations of prevalence and care intensity, and high '
            'spend does not automatically mean reducible or avoidable spend. Gingivitis '
            'reaches 800,475 members at 6.9 claims each: it is expensive because of how many '
            'people it touches. Chronic kidney disease and lung cancer are the opposite: '
            '37,037 and 2,384 members respectively, but 258.5 and 255.8 claims each, which for '
            'kidney disease is a patient on dialysis three times a week, care working as '
            'intended rather than a problem to reduce. This analysis does not show which, if '
            'any, of the twenty represents avoidable spend rather than necessary and already '
            'appropriate care; that would need clinical review this dataset cannot supply.'},
 {'title': 'Member-paid share is highest on the cheapest care, but the highest DOLLAR exposure sits elsewhere',
  'figures': [(3,
               'whobears',
               'The smaller the bill, the more of it members pay',
               'Share of each bill paid by members rather than the plan, by type of care. The '
               'coloured segment is the member&rsquo;s share, the grey remainder the '
               'plan&rsquo;s; total bill and number of people affected are printed alongside '
               'because share alone says nothing about size.'),
              (4,
               'cheapcare',
               'Every step down in cost is a step up in what members carry',
               'Cost per member against the share members carry, one circle per type of care. '
               '<strong>Circle size is the number of people affected</strong> (1,802 to '
               '938,009). The <strong>dashed line is a fitted trend</strong> through all '
               'fifteen points. The <strong>two circles picked out in purple</strong> are the '
               'only types that sit away from that trend; both were tested and neither '
               'is a real exception, as the notes below record. Positions are as billed: '
               'the allergy circle in particular sits at $175,111 a person here against '
               '$2,432 once its price is corrected, so read its place on the horizontal '
               'axis with that in mind.')],
  'para': 'Both charts measure member-paid SHARE: the proportion of a bill met by the member '
          'rather than the plan, not a dollar amount and not a measure of financial hardship '
          'on its own. The bars rank the fifteen types of care by that share; the scatter '
          'plots the same share against cost per person, sized by how many people it reaches. '
          'Share runs from 8.3% to 38.9%, median 20.6%, and it moves inversely with cost: blood '
          'disorders leads at 38.9% on $1,802 average cost a person, diabetes follows at 36.6% '
          'on $1,675, while cancer sits at 8.3% on $104,622. That slope holds across all fifteen '
          'points without exception, and it survives price correction: the rank correlation '
          'between share and cost per person stays at about &minus;0.6 either way (the second '
          'decimal depends on how one tied pair is ranked, so it is not quoted), the median '
          'share stays at 20.6% and the top at 38.9%, with only the bottom of the range '
          'shifting to 7.4%. One illustration does NOT survive it, and is left out above for '
          'that reason: '
          'allergy and immune care reads as 10.0% on $175,111 a person as billed, a textbook '
          'expensive-care-low-share case, but its price carries the largest documented gap in '
          'this dataset (roughly 89 times), and corrected it becomes 15.0% on $2,432, which is '
          'cheap care at a middling share and illustrates nothing. Cancer is used instead '
          'because it holds its shape, at 7.4% on $41,007 corrected. But share and the actual '
          'dollar amount an affected member pays are a separate question, answered in the table '
          'below rather than by either chart above.',
  'extra': '<div class="minitable"><p class="mtcap">What an affected member actually paid, '
           'by type of care (five-year total; <code>q2_oop_percentiles_by_care_type.sql</code>)'
           '</p><table><thead><tr><th>Type of care</th><th>Share rank</th>'
           '<th>Median $ paid</th><th>P90 $ paid</th></tr></thead><tbody>'
           '<tr><td>Maternity</td><td>10th by share (17.0%)</td><td>$10,765</td><td>$64,681</td></tr>'
           '<tr><td>Dental &amp; oral</td><td>4th by share (27.9%)</td><td>$1,358</td><td>$9,497</td></tr>'
           '<tr><td>Diabetes &amp; metabolic</td><td>2nd by share (36.6%)</td><td>$233</td><td>$1,502</td></tr>'
           '<tr><td>Blood disorders</td><td>1st by share (38.9%)</td><td>$179</td><td>$2,049</td></tr>'
           '</tbody></table><p class="mtnote">The two categories with the highest SHARE (blood '
           'disorders, diabetes) have the lowest typical dollar exposure of the four shown. '
           'Maternity, 10th by share, has by far the highest, both typically (median) and '
           'at the high end (P90). Share and dollar exposure are different findings and should '
           'not be described with the same word.</p></div>',
  'examined': ['Member share by type of care, with total bill and number of people alongside '
               ': share alone says nothing about size.',
               'Whether the pattern survives inside one line of business, or was an artefact '
               'of mixing them. It strengthens: the relationship is clearer within commercial '
               'and within government than across both together.',
               'The two care types that appeared to break the pattern. Neither does: '
               'one is skewed by a handful of very large claims, the other is 90.2% '
               'government-funded.',
               'What an affected member actually paid in dollars, not just the share, for each '
               'type of care: the result is the table above, and it does not track the share '
               'ranking (<code>q2_oop_percentiles_by_care_type.sql</code>).',
               'Why the mechanism differs by line of business, which is Finding 3.',
               'Whether the 20.4% headline survives correcting known pricing defects. It does '
               'not: corrected, it rises to 23.3%, while the dollars members pay fall from '
               '$20.3B to $11.4B. Both at once, because the eleven corrected conditions carry '
               '$54.9B at a 17.7% member share against $44.2B at 23.8% for everything '
               'untouched, so shrinking the low-share group reweights the blend upward. The '
               'share is a mix effect, not members paying more '
               '(<code>q1_robustness_three_findings.sql</code>).'],
  'sowhat': 'Member-paid share is highest on the cheapest, most routine care, and reach sets '
            'a ceiling on how many members a change to any one category could affect: dental, '
            'the widest-reaching high-share category, could reach up to 938,009 members, '
            'against 67,419 for blood disorders. But share is not dollar exposure. The category '
            'with the highest real financial exposure at the tail is maternity, whose share '
            'ranks only 10th, so a plan built around the share ranking alone would look past '
            'the largest dollar amounts members are actually paying. This analysis does not '
            'measure hardship directly (income, savings, or ability to pay are not in this '
            'dataset), so &ldquo;highest dollar exposure&rdquo; here means the largest amount '
            'paid, not the largest burden felt.'},
 {'title': 'Member-paid share differs sharply by plan type, even within the same condition',
  'figures': [(5,
               'insurance',
               'The same condition, but member-paid share moves sharply with the plan',
               'The ten conditions where members carry the most, split by line of business. '
               'Each row is one condition; the two dots are the typical commercial and '
               'government member and <strong>the line between them is the gap</strong>. Dots '
               'are the median of the five annual figures, not the five years pooled.')],
  'para': 'Each row is one condition, with a dot for the typical commercial member and another '
          'for the typical government member; the line between them is the difference in '
          'member-paid share for a bill within the same condition code (not independently '
          'matched on setting, severity, utilisation or the specific services billed). No row '
          'closes. Commercial members carry more on all ten, by between 12.9 and 78.1 '
          'percentage points. Two metabolic conditions separate from the rest: obesity at '
          '86.8% against 8.7%, prediabetes at 85.0% against 8.5%, while the other eight sit '
          'between 13 and 48 points. The two populations barely overlap: commercial shares run '
          '61.5% to 86.8%, government shares 8.5% to 58.4%, so the lowest commercial figure '
          'still exceeds all but the highest government one. These are typical-year figures, '
          'and the year-to-year movement is small: prediabetes stays between 83.8% and 86.1% '
          'for commercial members across all five years.',
  'examined': ['The ten conditions with the highest member-paid share, split three ways, using '
               'the typical year rather than five years pooled so the range is visible.',
               'Whether the gap is stable or a single bad year. It holds in all five.',
               'The mechanism behind it, measured rather than assumed: a flat '
               '$0&ndash;50 per claim on one side, a deductible and annual cap on the other.',
               'Where a blended figure would mislead. Commercial members span 6.7% to 74.4% by '
               'care type, government members 0.6% to 8.1%; the blend describes neither.',
               'Whether plan type is the largest driver of member-paid share compared with '
               'condition, care type or claim size. Not tested here: this finding shows the '
               'gap is real and consistent within a condition, not that plan type outweighs '
               'other factors in general.',
               'Whether the gap survives correcting the pricing defects that reshaped Finding '
               '1. It is exactly unchanged, to the decimal, on every condition tested: '
               'pregnancy stays at 25.2 times, gingivitis at 17.1, allergy at 9.4. Scaling a '
               'bill and what was paid on it by the same factor cancels in a ratio, so this '
               'finding is immune to that entire class of defect rather than merely surviving '
               'it, and is the most robust of the five on that measure '
               '(<code>q1_robustness_three_findings.sql</code>).'],
  'sowhat': 'The gap is persistent and closely aligned with the two benefit designs, making '
            'plan design an important factor to examine. It is measured, not assumed: a flat '
            'copay on the government side against a deductible and coinsurance on the '
            'commercial side, and it holds across all five years and all ten conditions. This '
            'analysis has not decomposed how much of member-paid share is explained by plan '
            'type against condition, care type, or claim size, so it does not show that plan '
            'type is the dominant driver overall, only that the gap is real, large and stable '
            'for these ten conditions.'},
 {'title': 'Spending concentrates in places, not in people',
  'figures': [(6,
               'places',
               '86 facilities carry what it takes 134,198 members to reach',
               'How much of each group is needed to reach half of all spending. <strong>The '
               'coloured portion is that few</strong>; the grey remainder is everyone else. '
               'Bars are drawn as a share of each group, not as raw counts, because there are '
               '321 times more members than facilities.'),
              (7,
               'lorenz',
               'Facilities bow sharply away from the line; members barely do',
               'The same finding drawn as curves: working down each ranked list, how fast '
               'spending accumulates. <strong>The dashed diagonal is what perfectly even '
               'spending would look like</strong>. The further a curve bows above it, '
               'the more concentrated that group is.')],
  'para': 'Both charts show how much of a group is needed to reach half of all spending. The '
          'bars give the threshold: 86 of 3,918 facilities, against 134,198 of 1,259,375 '
          'members. They are drawn as a share of each group rather than as counts, because '
          'there are 321 times more members than facilities: 2.2% against 10.7%. The '
          'curves show the same relationship continuously, with the dashed diagonal marking '
          'perfectly even spending, and the separation widens along their whole length: the '
          'priciest 1% of facilities account for 32.5% of spending against 11.8% for the '
          'priciest 1% of members, and by the 10% mark the figures are 86.2% and 48.2%. The '
          'facility curve bows sharply throughout; the member curve stays close to even.',
  'extra': concentration_chart(),
  'examined': ['Concentration measured four ways ( by member, by facility, by condition, '
               'by type of care) to check the answer was not an artefact of one '
               'grouping.',
               'Whether comparing 86 against 134,198 is fair. It is not on its own: there are '
               '321 times more members than facilities, so the fair comparison is 2.2% against '
               '10.7%.',
               'How the member concentration compares with real claims data. This is a '
               'limitation, not a reassurance: this population is flatter than published '
               'real-world figures (the top 1% carry 11.8% here; AHRQ MEPS statistical briefs '
               'put the U.S. top 1% at roughly 20&ndash;25% of total expenditure in most '
               'years). If real claims concentrate spending more heavily at the top than this '
               'synthetic population does, the true member-level concentration could be '
               'tighter than reported here, meaning a smaller, more identifiable group might '
               'carry a larger share of spend in reality than this analysis shows.',
               'Whether the 11.8% figure survives correcting known pricing defects. It moves in '
               'BOTH directions depending on the test, not consistently in one: correcting '
               'pregnancy alone raises it to 15.4%; correcting all eleven confidently-inflated '
               'conditions brings it back down to 12.5%, close to the as-billed figure '
               '(<code>q1_pregnancy_sensitivity.sql</code>, '
               '<code>q1_multi_condition_sensitivity.sql</code>). The exact percentage should '
               'not be treated as settled; that spend concentrates in a minority of patients at '
               'all is the more durable part of this finding.',
               'Whether the facility concentration is few enough to work through, which is Finding 5.'],
  'sowhat': 'Attention aimed at facilities can be exhaustive, because 86 is a list a team can '
            'finish. Attention aimed at members cannot: reaching the same half of spending '
            'means reaching 134,198 people, so member-level work has to be selective on some '
            'basis this analysis does not supply.'},
 {'title': 'Within this simulated pricing structure, facility differences are driven mainly by case mix',
  'figures': [(8,
               'hospitals',
               'The dearest facilities charge ordinary prices: their patients come '
               'back fifty times in five years',
               'Every facility placed by what an average visit costs and how often members '
               'return. Colour marks the two groups that separate out, identified by facility '
               'name; the axis is a log scale, so each step right is a tenfold increase.')],
  'para': 'The chart places every facility by what an average visit costs against how often '
          'members return, on a log scale. Three groups separate rather than forming one '
          'continuous spread: 12 facilities high on the vertical axis whose members return '
          'around fifty times across the five years, 22 extending far to the right at high '
          'cost per visit, and the '
          'remaining 697 massed at the lower left. Cost per member across them ranges from '
          '$4,401 to $144,422, a thirty-three-fold difference. Within this dataset&rsquo;s own '
          'simulated prices, that range tracks case mix rather than price: repricing every '
          'procedure to its all-facility average moves the spread only from 15.8&times; to '
          '15.2&times;. The 7.8% figure often quoted for this test is computed per facility as '
          '|actual cost per visit &minus; cost per visit with prices equalised| &divide; '
          'actual, and 7.8% is the MEDIAN OF THAT ABSOLUTE VALUE across facilities, not a '
          'one-directional markup: 41% of facilities actually price BELOW the all-facility '
          'benchmark for the procedures they perform, not above it, so there is no consistent '
          'direction to a &ldquo;price effect&rdquo; here even before asking whether these '
          'simulated prices resemble real negotiated rates at all. The top group is dialysis, '
          'with chronic kidney disease at 53.1% of visits; the group on the right is hospices, '
          'where stays run 22 days and are billed as single visits.',
  'examined': ['Whether the spread is price or case mix, by repricing every procedure to its '
               'all-facility average and remeasuring, within this dataset&rsquo;s own simulated '
               'prices. It is case mix.',
               'Whether facilities differ in how much they do for the same condition. For the '
               'typical condition, no, and the one big exception is pregnancy.',
               'What separates cheap from expensive pregnancy sites. At the cheapest, 95.5% of '
               'women give birth on site; at the most expensive, 6.8%. Delivery units against '
               'antenatal clinics.',
               'The two groups that stand out on the chart, both identified by facility name '
               'rather than by anything in the data itself.',
               'Whether the 7.8% price-share figure has a consistent direction. It does not: '
               '298 of 730 facilities (41%) price below the case-mix benchmark, not above it '
               '(<code>q3_price_vs_casemix.sql</code>).'],
  'sowhat': 'Within the simulated pricing structure in this dataset, facility spending '
            'differences are driven mainly by case mix rather than modelled price variation. '
            'That is a fact about this dataset&rsquo;s own internal pricing, not a business '
            'conclusion about real providers: this dataset does not model realistic, '
            'provider-specific negotiated rates (see &ldquo;Things to be aware of&rdquo; '
            'above), so it cannot show whether any real facility&rsquo;s prices are fair, '
            'high, or negotiable. Assessing that would need real negotiated-rate data, which '
            'is outside what this analysis can supply.'}]

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
