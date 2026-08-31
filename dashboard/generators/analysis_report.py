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


def build():
    verify_sources()
    theme, css, figs = collect()
    o = ['<title>Calder Health — Five-Year Claims Analysis</title>',
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
        o.append('<div class="examined"><p class="exhd">What was examined</p><ul>%s</ul></div>'
                 % ''.join('<li>%s</li>' % b for b in f['examined']))
        o.append(sources_block(i - 1))
        o.append('</section>')

    o.append(FOOTER)
    o.append('</div>')
    return '\n'.join(o) + '\n'


PAGE_CSS = '''
:root{--surface-1:#fcfcfb;--surface-2:#fff;--text-primary:#0b0b0b;--text-secondary:#52514e;
--text-muted:#78766f;--rule:#e6e5e1;--accent:#2a78d6;--warn:#eb6834;--card:#fff;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface-1:#171716;
--surface-2:#1f1f1e;--text-primary:#fff;--text-secondary:#c3c2b7;--text-muted:#9a988f;
--rule:#33322f;--accent:#3987e5;--warn:#d95926;--card:#232322;}}
:root[data-theme="dark"]{--surface-1:#171716;--surface-2:#1f1f1e;--text-primary:#fff;
--text-secondary:#c3c2b7;--text-muted:#9a988f;--rule:#33322f;--accent:#3987e5;
--warn:#d95926;--card:#232322;}
body{background:var(--surface-1);color:var(--text-primary);margin:0;padding:40px 20px 72px;
font:16px/1.65 ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;}
.wrap{max-width:860px;margin:0 auto;}
.eyebrow{font-size:11.5px;letter-spacing:.13em;text-transform:uppercase;color:var(--text-muted);
font-weight:650;margin:0 0 10px;}
h1.title{font-size:31px;line-height:1.2;letter-spacing:-.02em;margin:0 0 10px;}
.standfirst{font-size:17px;color:var(--text-secondary);margin:0 0 6px;max-width:64ch;}
.meta{font-size:13px;color:var(--text-muted);margin:14px 0 0;}
h2.sec{font-size:12px;letter-spacing:.11em;text-transform:uppercase;color:var(--text-muted);
font-weight:650;margin:52px 0 16px;padding-bottom:8px;border-bottom:1px solid var(--rule);}
h3{font-size:20px;line-height:1.3;letter-spacing:-.01em;margin:0 0 22px;}
h3.subsec{font-size:15px;line-height:1.35;font-weight:650;letter-spacing:0;
margin:26px 0 10px;color:var(--text-primary);}
.fno{display:block;font-size:11px;letter-spacing:.1em;text-transform:uppercase;
color:var(--accent);font-weight:700;margin-bottom:5px;}
p{margin:0 0 13px;}
.mission{border-left:3px solid var(--accent);padding:2px 0 2px 18px;margin:0 0 20px;
font-size:17px;line-height:1.55;color:var(--text-primary);}
.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin:0 0 8px;}
@media (max-width:700px){.cards{grid-template-columns:1fr;}}
.card{background:var(--card);border:1px solid var(--rule);border-radius:10px;padding:17px 18px;}
.card .lbl{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--text-muted);
font-weight:650;margin-bottom:8px;}
.card .big{font-size:27px;font-weight:700;letter-spacing:-.02em;line-height:1.1;}
.card .sub2{font-size:12.5px;color:var(--text-secondary);margin-top:7px;line-height:1.45;}
.callout{background:var(--card);border:1px solid var(--rule);border-left:3px solid var(--warn);
border-radius:8px;padding:16px 18px;margin:0 0 8px;}
.callout p{font-size:14px;color:var(--text-secondary);margin:0 0 9px;}
.callout p:last-child{margin:0;}
.callout strong{color:var(--text-primary);}
ul{margin:0 0 13px;padding-left:20px;}
li{margin-bottom:7px;color:var(--text-secondary);}
li strong{color:var(--text-primary);}
.summary li{font-size:15.5px;margin-bottom:11px;}
section.finding{margin:0 0 46px;padding:0 0 6px;}
figure.fig{margin:0 0 22px;}
.figtitle{font-size:15.5px;line-height:1.4;font-weight:650;letter-spacing:-.005em;
margin:0 0 11px;padding-left:11px;border-left:2px solid var(--accent);
color:var(--text-primary);}
figure.fig + figure.fig{margin-top:30px;}
h3 + figure.fig .figtitle{margin-top:2px;}
figcaption{font-size:12.5px;color:var(--text-muted);margin-top:9px;line-height:1.5;}
.fignum{color:var(--text-primary);font-weight:650;}
.prose{margin-top:20px;}
.prose p{font-size:15.5px;color:var(--text-secondary);}
.prose strong{color:var(--text-primary);}
.examined{margin-top:16px;background:var(--card);border:1px solid var(--rule);
border-radius:8px;padding:15px 18px 8px;}
.exhd{font-size:11px;letter-spacing:.09em;text-transform:uppercase;color:var(--text-muted);
font-weight:650;margin:0 0 10px;}
.examined li{font-size:14px;}
details.sources{margin-top:12px;border:1px solid var(--rule);border-radius:8px;
background:var(--card);padding:0 16px;}
details.sources summary{cursor:pointer;font-size:12px;letter-spacing:.06em;
text-transform:uppercase;color:var(--text-muted);font-weight:650;padding:12px 0;
list-style:none;}
details.sources summary::-webkit-details-marker{display:none;}
details.sources summary::before{content:"\25B8";display:inline-block;margin-right:8px;
transition:transform .15s;}
details.sources[open] summary::before{transform:rotate(90deg);}
details.sources ul{margin:0 0 12px;padding-left:20px;}
details.sources li{font-size:13.5px;margin-bottom:8px;color:var(--text-secondary);}
details.sources a{color:var(--accent);text-decoration:none;}
details.sources a:hover{text-decoration:underline;}
details.sources a.csv{font-size:11.5px;letter-spacing:.04em;text-transform:uppercase;
color:var(--text-muted);margin-left:2px;}
.card .src{margin-top:9px;font-size:11.5px;}
.card .src a{color:var(--text-muted);text-decoration:none;}
.card .src a:hover{color:var(--accent);text-decoration:underline;}
footer{margin-top:56px;padding-top:18px;border-top:1px solid var(--rule);
font-size:12.5px;color:var(--text-muted);}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;}
'''

HEADER = '''<p class="eyebrow">Calder Health &middot; Prepared for the 2026 planning cycle</p>
<h1 class="title">Where five years of spend went, and who carried it</h1>
<p class="standfirst">An analysis of 68.6 million claims across 1.26 million members,
2020&ndash;2024.</p>
<p class="meta">Findings only. Recommendations follow in a later pass.</p>'''

ABOUT = '''<h2 class="sec">About Calder Health</h2>
<p class="mission"><strong>Mission.</strong> To keep comprehensive cover affordable for every
member, in every place they seek care &mdash; measuring affordability by what a member actually
pays rather than by what a plan spends, and holding that standard equally across commercial and
government lines.</p>
<p>Calder Health is a non-profit health plan headquartered in Cleveland, serving <strong>1.26
million members</strong> with further concentrations in Chicago, Detroit and Northeast Ohio.
Members are treated across a network of <strong>3,918 facilities</strong>, from single-site
clinics to large teaching hospitals. The plan operates two lines of business, and they are
designed differently:</p>
<ul>
<li><strong>Commercial</strong> &mdash; employer group plans, built on a deductible and
coinsurance with an annual out-of-pocket maximum. A member pays a share of each bill until the
annual maximum is reached, after which the plan pays everything.</li>
<li><strong>Government</strong> &mdash; Medicaid and Medicare managed care, built on a flat copay
per visit. A member pays the same small amount whatever the bill comes to.</li>
</ul>
<p>That difference turns out to matter more than almost anything else in this report. The same
condition can cost a commercial member ten times what it costs a government member, and it is the
plan&rsquo;s own benefit design producing the gap.</p>
<p>The mission sets the shape of the analysis. Affordability measured by what members pay &mdash;
rather than by total spend &mdash; is why member cost burden sits among the headline metrics
instead of in an appendix. &ldquo;In every place they seek care&rdquo; is why facilities are
examined separately from conditions. &ldquo;Equally across both lines&rdquo; is why every figure
that can be split by line of business has been.</p>
<p><strong>The brief.</strong> Before benefits are set and networks negotiated for 2026, establish
three things: where the money went, who bore it, and where it concentrates.</p>'''

DATASECTION = '''<h2 class="sec">About the data</h2>
<p>Claims were drawn from a read-only Snowflake share,
<code>SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER</code>, containing Synthea-generated
synthetic healthcare records &mdash; 887 million claim transactions across 124 million claims and
1.4 million simulated patients in total.</p>
<p><strong>Time frame.</strong> All figures cover <strong>1 January 2020 to 31 December 2024</strong>,
five complete years. The window matters: unfiltered, the source spans simulated history back to
1914, and cumulative totals taken across it are not meaningful. Within the window the analysis
covers <strong>68.6 million claims, 1,259,375 patients and $99.11 billion billed</strong>.</p>
<p><strong>Tables used.</strong></p>
<ul>
<li><code>SILVER.CLAIMS</code> &mdash; diagnosis fields, used to attach spend to a condition.</li>
<li><code>SILVER.ENCOUNTERS</code> &mdash; visit class, dates and the facility each visit belongs
to.</li>
<li><code>SILVER.ORGANIZATIONS</code> &mdash; facility name and city.</li>
<li><code>SILVER.PATIENTS</code> &mdash; dates of birth, used only for the age check behind the
preventive-care question.</li>
</ul>
<p>Two curated objects sit in front of the raw share and every query reads through them, because
the source carries traps that return confident, plausible, wrong answers rather than errors:</p>
<ul>
<li><code>V_CLAIMS_TX_CLEAN</code> &mdash; claim transactions with the money columns corrected,
payer collapsed to type, administrative rows flagged, and the date window applied.</li>
<li><code>CODE_DICTIONARY</code> &mdash; 1,453 rows mapping every clinical code to one canonical
name and category, resolving all nine code fields.</li>
</ul>
<p><strong>Data dictionary.</strong> Full table and column references, together with the known
traps in the source data, are documented in
<a href="../DATA_ANALYSIS_CONTEXT.md">DATA_ANALYSIS_CONTEXT.md</a> &sect;25&ndash;26. Every figure
in this report traces to a saved query in <code>sql/analysis/</code> and a result file in
<code>sql/results/</code>.</p>'''

HOWTOREAD = '''<h2 class="sec">How to read these numbers</h2>
<div class="callout">
<p><strong>This analysis runs on simulated claims data, and some of it is not realistic.</strong>
Read the shape, not the price tag.</p>
<p><strong>Trust:</strong> rankings, shares, ratios, and how concentrated things are. Which
conditions dominate, who pays what proportion, how few sites carry the spend &mdash; these hold up
and are the basis of everything below.</p>
<p><strong>Do not trust:</strong> absolute dollar amounts. A pregnancy bills <strong>8.6&times;
what it costs in reality</strong>. No per-case figure from this report should be quoted
elsewhere.</p>
<p><strong>Cannot be answered here at all:</strong> anything about negotiated rates, denials, bad
debt or collections. In this data every claim is paid in full, and no provider is charged a
different price from any other. Those are properties of the simulation, not findings about
Calder.</p>
</div>'''

NORTHSTAR = '''<h2 class="sec">The three numbers Calder steers by</h2>
<div class="cards">
<div class="card"><div class="lbl">Total cost of care</div><div class="big">$99.1B</div>
<div class="sub2">Billed across five years. $72.7B of it attaches to a specific diagnosis; the
rest is care recorded without one.</div>
<div class="src"><a href="../sql/analysis/q1_cost_drivers.sql">q1_cost_drivers.sql</a></div></div>
<div class="card"><div class="lbl">Member cost burden</div><div class="big">20.4%</div>
<div class="sub2">$20.3B paid out of pocket &mdash; $16,084 per member over five years. This is
the number the mission lives or dies on.</div><div class="src"><a href="../sql/analysis/q2_who_pays.sql">q2_who_pays.sql</a></div></div>
<div class="card"><div class="lbl">Spend concentration</div><div class="big">86 sites</div>
<div class="sub2">Of 3,918 facilities, 86 carry half of all spending. A list short enough to work
through by hand.</div><div class="src"><a href="../sql/analysis/q3_concentration.sql">q3_concentration.sql</a></div></div>
</div>'''

SUMMARY = '''<h2 class="sec">Executive summary</h2>
<ul class="summary">
<li><strong>Twenty conditions carry 91% of the bill that can be attributed to a diagnosis</strong>
&mdash; and pregnancy alone is 39.8% of it. Spending is not spread thin; it sits in a handful of
places.</li>
<li><strong>Members carry a fifth of the total, and it lands hardest on the cheapest care.</strong>
They pay 41.6% of a wellness visit and 8.6% of an inpatient stay. The inexpensive, routine things
are what people actually feel.</li>
<li><strong>Which plan a member holds matters more than what is wrong with them.</strong>
Prediabetes costs a commercial member 85.0% of the bill and a government member 8.5% &mdash; the
same care, a ten-fold difference, produced by benefit design rather than by illness.</li>
<li><strong>Spending concentrates in places, not in people.</strong> 86 of 3,918 sites carry half
the money, but it takes 134,198 members to reach the same half. There is no small group of
high-cost members to manage.</li>
<li><strong>The most expensive facilities are not charging more.</strong> Reprice every procedure
identically and the gap between sites barely moves &mdash; only 7.8% of a site&rsquo;s cost per
visit is its prices. Facilities differ in what they treat, not in what they charge.</li>
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

FOOTER = '''<footer>Calder Health is an illustrative client. The analysis is real and reproducible;
every figure traces to a saved query in <code>sql/analysis/</code> and a result file in
<code>sql/results/</code>. Generated by <code>dashboard/generators/analysis_report.py</code> &mdash;
edit the script, not this page.</footer>'''


# Which saved query established which numbers in each finding. Keep this honest:
# if a figure appears in the narrative, the query that produced it belongs here.
# Paths are relative to dashboard/, so the links work from a file:// open and
# from GitHub Pages alike. verify_sources() fails the build if one goes stale.
SOURCES = [
 [('q1_cost_drivers', 'the twenty largest conditions, their 90.8% and 66.6% shares, and pregnancy at $28.9B'),
  ('q1_spend_decomposition', 'the three drivers behind each condition, and the per-member re-ranking that moves gingivitis above lung cancer'),
  ('q1_condition_procedures', 'the check on whether pregnancy at 39.8% is credible',
   'q1_pregnancy_procedures_2020_2024.csv'),
  ('q1_hospital_cost_spread', 'whether facilities charge differently for the same condition')],
 [('q2_who_pays', 'the 20.4% member share, $20.3B, $16,084 each, and the 41.6% against 8.6% split by kind of visit'),
  ('q2_patient_cost_by_care_type', 'member share by type of care, including blood disorders at 38.9% and dental at 27.9% of $11.83B'),
  ('q2_pattern_within_payer', 'that the pattern strengthens rather than dissolves inside a single line of business'),
  ('q2_pattern_breakers', 'the two care types that appear to break the rule, and why neither does')],
 [('q2_top10_share_by_payer_type', 'the ten conditions split by line of business, and the 12.9-point minimum gap'),
  ('q2_share_by_payer_type_yearly', 'that the gap holds in all five years rather than one'),
  ('q2_who_pays', 'the five-year totals of $19,178, $2,118 and $61,742'),
  ('q2_commercial_cap_by_care_type', 'the mechanism, measured by grouping claims into $500 bands'),
  ('q2_care_type_share_by_payer_type', 'the ranges a blended figure would hide')],
 [('q3_concentration', 'the 86 facilities and 134,198 members, and the 2.2% against 10.7% comparison'),
  ('q3_lorenz_points', 'the curve coordinates behind Figure 7'),
  ('q3_top_entities', 'which specific facilities and conditions make up the concentrated half')],
 [('q3_hospital_cost_intensity', 'the $4,401 to $144,422 range across facilities'),
  ('q3_price_vs_casemix', 'the repricing test: 15.8x to 15.2x, and prices as a median 7.8% of cost per visit'),
  ('q3_utilisation_or_composition', 'the 0.027 typical spread in procedures per claim across 119 conditions'),
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
        '&mdash; {what}</li>'.format(q=e[0], csv=_result_of(e), what=e[1])
        for e in SOURCES[i])
    return ('<details class="sources"><summary>Sources for this finding '
            '&mdash; {n} queries</summary><ul>{items}</ul></details>'
            .format(n=len(SOURCES[i]), items=items))


FINDINGS = [{'title': 'Twenty conditions carry nearly all of the bill, and one of them is pregnancy',
  'figures': [(1,
               'donut',
               'Pregnancy alone is two fifths of all diagnosed spending',
               'Diagnosed spend split by condition, 2020&ndash;2024. Each slice is one '
               'condition&rsquo;s share of the $72.7B that carries a diagnosis; pregnancy is '
               'the largest at 39.8%.'),
              (2,
               'top20',
               'Five conditions are three quarters of the bill, and the sixth drops below 2%',
               'The twenty largest conditions by total billed. The highlighted top bar is '
               'pregnancy, marked only because it is the outlier &mdash; every bar is measured '
               'the same way.')],
  'para': 'Both charts rank conditions by total billed, and the distribution they describe is '
          'severely top-heavy at every level. Normal pregnancy accounts for $28.9B on its own, '
          '39.8% of the $72.7B that carries a diagnosis, which is more than three times the '
          'second-placed condition and larger than the next three combined. The concentration '
          'does not stop at first place. Reading the cumulative column down the ranking, the '
          'top three reach 63.4%, five reach 74.1%, and the sixth contributes 1.8% &mdash; the '
          'point at which the distribution flattens into a tail. The fifteen bars after the '
          'fifth are worth $12.1B between them, less than half of pregnancy alone. Across the '
          'full twenty the total is 90.8% of diagnosed spend and 66.6% of the $99.1B billed '
          'overall, two denominators worth stating together because the first alone overstates '
          'this chart&rsquo;s reach by about a third: roughly a quarter of spending carries no '
          'diagnosis and sits outside these bars entirely. The ranking&rsquo;s limitation is '
          'that it flattens two different mechanisms into one order. Dividing each '
          'condition&rsquo;s spend by the members it affects reorders the list completely: '
          'gingivitis spreads $10,661 across 800,465 members, while non-small cell lung '
          'carcinoma concentrates $1,416,145 into 2,384. Both sit in the top five by total, '
          'but one arrives there through reach across a large population and the other through '
          'intensity within a very small one, and the decomposition behind the chart shows the '
          'top twenty are not extreme on any single driver &mdash; they are moderately extreme '
          'on members reached, visits each, and cost per visit simultaneously, with the '
          'multiplication producing the rest.',
  'examined': ['Total billed per condition, ranked, against total billed per member &mdash; '
               'the two rankings disagree sharply and the disagreement is the point.',
               'Whether pregnancy at 39.8% is credible. The number of visits per pregnancy is '
               'plausible (11.1, against a real-world 10&ndash;15); the price per visit is '
               'not.',
               'Whether the top twenty are extreme on one driver or several. They are '
               'moderately extreme on all three at once &mdash; members reached, visits each, '
               'cost per visit &mdash; and the multiplication does the rest.',
               'Whether facilities differ in what they charge for the same condition. For '
               'eight of the ten largest, barely at all.']},
 {'title': 'Members carry a fifth of the bill, and it falls hardest on the cheapest care',
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
               'only types that sit away from that trend &mdash; both were tested and neither '
               'is a real exception, as the notes below record.')],
  'para': 'Both charts measure the proportion of a bill met by the member rather than the '
          'plan, and both describe the same inverse relationship: as care gets cheaper, the '
          'member&rsquo;s share rises. Across the fifteen types of care that share ranges from '
          '8.3% to 38.9%, with a median of 20.6%. The types at the top are not the clinically '
          'severe ones. Blood disorders lead at 38.9% on a cost of $1,802 per person, followed '
          'by diabetes and metabolic conditions at 36.6% on $1,675 &mdash; the two cheapest '
          'categories in the set. At the other end, cancer sits at 8.3% on $104,622 per person '
          'and allergy and immune conditions at 10.0% on $175,111. The scatter plots that '
          'relationship directly and the slope runs down and to the right without a single '
          'exception across all fifteen points. Aggregating everything, members bear 20.4% of '
          'spending, $20.3B, or $16,084 each across five years once divided across the 1.26 '
          'million members. Splitting the same spend by kind of visit rather than by condition '
          'reproduces the pattern more sharply still: 41.6% of a wellness visit against 8.6% '
          'of an inpatient stay. The relationship also survives disaggregation, which is the '
          'stronger test &mdash; it holds more clearly inside the commercial book and inside '
          'the government book separately than it does across both pooled, so it is not an '
          'artefact of mixing two differently-designed populations. Size on the scatter shows '
          'how many people each category reaches, and the two are largely independent: dental '
          'sits high on share at 27.9% and also reaches the most people at 938,009, while '
          'blood disorders lead on share while touching only 67,419.',
  'examined': ['Member share by type of care, with total bill and number of people alongside '
               '&mdash; share alone says nothing about size.',
               'Whether the pattern survives inside one line of business, or was an artefact '
               'of mixing them. It strengthens: the relationship is clearer within commercial '
               'and within government than across both together.',
               'The two care types that appeared to break the pattern. Neither does &mdash; '
               'one is skewed by a handful of very large claims, the other is 90.2% '
               'government-funded.',
               'Why the mechanism differs by line of business, which is Finding 3.']},
 {'title': 'Which plan a member holds matters more than what is wrong with them',
  'figures': [(5,
               'insurance',
               'The same condition, ten times the cost, depending only on the plan',
               'The ten conditions where members carry the most, split by line of business. '
               'Each row is one condition; the two dots are the typical commercial and '
               'government member and <strong>the line between them is the gap</strong>. Dots '
               'are the median of the five annual figures, not the five years pooled.')],
  'para': 'Each row places one condition&rsquo;s commercial member against its government '
          'member, with the line between them measuring the difference in the share of an '
          'identical bill. No row closes. Commercial members carry the larger share on all '
          'ten, and the gaps range from 12.9 to 78.1 percentage points, so even the narrowest '
          'is substantial. The distribution of those gaps is itself uneven. Two metabolic '
          'conditions separate sharply from the rest &mdash; obesity at 86.8% against 8.7%, '
          'and prediabetes at 85.0% against 8.5% &mdash; both near a 78-point spread, while '
          'the remaining eight cluster between 13 and 48 points. The two populations barely '
          'overlap at all: commercial shares run from 61.5% to 86.8%, government shares from '
          '8.5% to 58.4%, so the lowest commercial figure still sits above all but the very '
          'highest government one. Every figure here is the typical year rather than the five '
          'pooled, which is what keeps the year-to-year range visible &mdash; prediabetes '
          'moves only between 83.8% and 86.1% for commercial members across the five years, so '
          'the gap is a standing feature rather than one unusual year. Aggregating '
          'differently, as five-year totals in money rather than proportion, produces the same '
          'divide: $19,178 out of pocket for a commercial member, $2,118 for a government one, '
          'and $61,742 for someone uninsured. The mechanism was established rather than '
          'inferred, by grouping claims into $500 bands and tracking what members paid as '
          'bills grew. Government members pay a flat $0&ndash;50 per claim regardless of size, '
          'so their share falls arithmetically as the bill rises, while commercial members pay '
          'coinsurance until an annual out-of-pocket maximum is reached, and cheap routine '
          'care never accumulates enough within a single year to reach it.',
  'examined': ['The ten highest-burden conditions, split three ways, using the typical year '
               'rather than five years pooled so the range is visible.',
               'Whether the gap is stable or a single bad year. It holds in all five.',
               'The mechanism behind it, measured rather than assumed &mdash; a flat '
               '$0&ndash;50 per claim on one side, a deductible and annual cap on the other.',
               'Where a blended figure would mislead. Commercial members span 6.7% to 74.4% by '
               'care type, government members 0.6% to 8.1%; the blend describes neither.']},
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
               'spending would look like</strong> &mdash; the further a curve bows above it, '
               'the more concentrated that group is.')],
  'para': 'Both charts answer the same question &mdash; how much of a group is required to '
          'reach half of all spending &mdash; and the two groupings behave very differently. '
          'By facility it takes 86 of 3,918; by member it takes 134,198 of 1,259,375. Because '
          'there are 321 times more members than facilities, the raw counts are not '
          'comparable, so the bars are drawn as a share of each group: 2.2% against 10.7%, '
          'making facilities roughly five times more concentrated rather than a thousand. The '
          'curves describe the same relationship continuously rather than at a single '
          'threshold, and the separation widens as you move along them. The priciest 1% of '
          'facilities account for 32.5% of spending where the priciest 1% of members account '
          'for 11.8%; by the 10% mark the figures are 86.2% and 48.2%. The facility curve '
          'therefore bows sharply away from the diagonal along its whole length, while the '
          'member curve stays comparatively close to even distribution. Measuring the same '
          'concentration across four different groupings shows the result is not an artefact '
          'of how the data was cut: conditions concentrate hardest of all, with the top 1% of '
          '185 conditions carrying 39.8% and the top 5% carrying 80.1%. The member curve is '
          'the flattest of the four, and flatter than real claims books, where the top 1% '
          'typically carry 20&ndash;25% against 11.8% here.',
  'examined': ['Concentration measured four ways &mdash; by member, by facility, by condition, '
               'by type of care &mdash; to check the answer was not an artefact of one '
               'grouping.',
               'Whether comparing 86 against 134,198 is fair. It is not on its own: there are '
               '321 times more members than facilities, so the fair comparison is 2.2% against '
               '10.7%.',
               'How the member concentration compares with real claims data. This population '
               'is flatter &mdash; the top 1% carry 11.8% where real books run 20&ndash;25% '
               '&mdash; so if anything this understates how few members matter.',
               'Whether the facility concentration is actionable, which is Finding 5.']},
 {'title': 'The most expensive facilities are not charging more',
  'figures': [(8,
               'hospitals',
               'The dearest facilities charge ordinary prices &mdash; their patients simply '
               'return fifty times',
               'Every facility placed by what an average visit costs and how often members '
               'return. Colour marks the two groups that separate out, identified by facility '
               'name; the axis is a log scale, so each step right is a tenfold increase.')],
  'para': 'The chart places every facility by what an average visit costs against how often '
          'members return, and three groups separate rather than forming a single continuous '
          'spread. Cost per member ranges from $4,401 to $144,422, a thirty-three-fold '
          'difference, and the initial reading of such a range is that some facilities charge '
          'far more than others. Testing that directly does not support it. Recomputing every '
          'facility&rsquo;s cost per visit with each procedure repriced to its all-facility '
          'average moves the spread only from 15.8&times; to 15.2&times;, which puts a median '
          'of 7.8% of a facility&rsquo;s cost per visit down to its prices and the remaining '
          '92% down to what it treats. Volume of work behaves the same way: across 119 '
          'conditions the typical difference between facilities in procedures performed per '
          'claim is 0.027, effectively none. What separates the three groups is therefore case '
          'mix. Breaking the top group of 12 facilities down by condition shows two thirds of '
          'their visits are kidney failure, with chronic kidney disease alone at 53.1% of '
          'visits and members returning 129 times across five years, a pattern consistent with '
          'dialysis three times weekly. The 22 facilities extending to the right are hospices '
          'and nursing homes, where end-of-life stays are only 18.1% of visits but run 22 days '
          'each and carry roughly half the billing, so a long admission is recorded as one '
          'very expensive visit. The remaining 697 facilities form the mass at the lower left. '
          'Pregnancy is the single condition where facilities genuinely differ, and it divides '
          'on whether the birth happens on site: 95.5% of women deliver at the cheapest '
          'quarter of facilities against 6.8% at the dearest, which is the difference between '
          'a delivery unit and an antenatal clinic rather than between two prices for the same '
          'service.',
  'examined': ['Whether the spread is price or case mix, by repricing every procedure to its '
               'all-facility average and remeasuring. It is case mix.',
               'Whether facilities differ in how much they do for the same condition. For the '
               'typical condition, no &mdash; and the one big exception is pregnancy.',
               'What separates cheap from expensive pregnancy sites. At the cheapest, 95.5% of '
               'women give birth on site; at the most expensive, 6.8%. Delivery units against '
               'antenatal clinics.',
               'The two groups that stand out on the chart, both identified by facility name '
               'rather than by anything in the data itself.']}]

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
