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
        o.append('<div class="sowhat"><p class="swhd">So what</p><p>%s</p></div>'
                 % f['sowhat'])
        o.append('<div class="examined"><p class="exhd">What was examined</p><ul>%s</ul></div>'
                 % ''.join('<li>%s</li>' % b for b in f['examined']))
        o.append(sources_block(i - 1))
        o.append('</section>')

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
.mission{font-size:17px;line-height:1.55;margin:0 0 16px;padding:16px;
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
.sowhat{margin-top:16px;padding:16px;background:var(--card);
border:1px solid var(--rule);border-radius:4px;}
.swhd{font-size:13px;font-weight:650;color:var(--text-primary);margin:0 0 4px;}
.sowhat p:last-child{font-size:16px;line-height:1.6;color:var(--text-secondary);margin:0;}
.examined{margin-top:16px;}
.exhd{font-size:13px;font-weight:650;color:var(--text-primary);margin:0 0 8px;}
.examined ul{margin:0;}
.examined li{font-size:15px;}
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
<p class="meta">Prepared for Calder Health, 2026 planning cycle. Findings only;
recommendations follow in a later pass.</p>'''

ABOUT = '''<h2 class="sec">About Calder Health</h2>
<p class="mission"><strong>Mission.</strong> To keep comprehensive cover affordable for every
member, in every place they seek care, measuring affordability by what a member actually
pays rather than by what a plan spends, and holding that standard equally across commercial and
government lines.</p>
<p>Calder Health is a non-profit health plan headquartered in Cleveland, serving <strong>1.26
million members</strong> with further concentrations in Chicago, Detroit and Northeast Ohio.
Members are treated across a network of <strong>3,918 facilities</strong>, from single-site
clinics to large teaching hospitals. The plan operates two lines of business, and they are
designed differently:</p>
<ul>
<li><strong>Commercial</strong>: employer group plans, built on a deductible and
coinsurance with an annual out-of-pocket maximum. A member pays a share of each bill until the
annual maximum is reached, after which the plan pays everything.</li>
<li><strong>Government</strong>: Medicaid and Medicare managed care, built on a flat copay
per visit. A member pays the same small amount whatever the bill comes to.</li>
</ul>
<p>That difference turns out to matter more than almost anything else in this report. The same
condition can cost a commercial member ten times what it costs a government member, and it is the
plan&rsquo;s own benefit design producing the gap.</p>
<p>The mission sets the shape of the analysis. Affordability measured by what members pay,
rather than by total spend, is why member cost burden sits among the headline metrics
instead of in an appendix. &ldquo;In every place they seek care&rdquo; is why facilities are
examined separately from conditions. &ldquo;Equally across both lines&rdquo; is why every figure
that can be split by line of business has been.</p>
<p><strong>The brief.</strong> Before benefits are set and networks negotiated for 2026, establish
three things: where the money went, who bore it, and where it concentrates.</p>'''

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

HOWTOREAD = '''<h2 class="sec">How to read these numbers</h2>
<div class="callout">
<p><strong>The relative patterns here are solid. Use this to steer strategy, not for line-item
budgeting.</strong></p>
<p><strong>What holds.</strong> Rankings, shares, ratios and concentration: which conditions
dominate and by how much, what proportion of a bill members carry and how that differs by line of
business, how few facilities carry the spend. Every finding below rests on these, and each was
tested more than one way: the concentration result was measured across four separate groupings, the
member-burden pattern was re-checked inside each line of business on its own, and the facility
spread was retested with every procedure repriced to a common rate. All three held.</p>
<p><strong>Where the boundary sits.</strong> Absolute per-case dollar amounts. This is simulated
claims data and it prices a pregnancy at roughly 8.6&times; the real-world figure. That leaves
everything above intact: pregnancy is genuinely the largest cost centre, and the shares and
rankings are unaffected. But a per-case figure from this report is not a budgeting input.
Read the shape rather than the price tag.</p>
<p><strong>Outside the scope of this data.</strong> Negotiated rates, denials, bad debt and
collections. Every claim here is paid in full and no provider is charged differently from any
other, so those are properties of the simulation rather than findings about Calder, and answering
them would need real contract and remittance data.</p>
</div>'''

NORTHSTAR = '''<h2 class="sec">The three numbers Calder steers by</h2>
<table class="metrics"><tbody>
<tr><th>Total cost of care</th><td class="val">$99.1B</td>
<td class="note">Billed across five years. $72.7B of it attaches to a specific diagnosis; the rest
is care recorded without one.
<a href="../sql/analysis/q1_cost_drivers.sql">q1_cost_drivers.sql</a></td></tr>
<tr><th>Member cost burden</th><td class="val">20.4%</td>
<td class="note">$20.3B paid out of pocket, or $16,084 per member over five years. This is the
number the mission lives or dies on.
<a href="../sql/analysis/q2_who_pays.sql">q2_who_pays.sql</a></td></tr>
<tr><th>Spend concentration</th><td class="val">86 sites</td>
<td class="note">Of 3,918 facilities, 86 carry half of all spending. A list short enough to work
through by hand.
<a href="../sql/analysis/q3_concentration.sql">q3_concentration.sql</a></td></tr>
</tbody></table>'''

SUMMARY = '''<h2 class="sec">Executive summary</h2>
<ul class="summary">
<li><strong>Twenty conditions carry 91% of the bill that can be attributed to a diagnosis</strong>, and pregnancy alone is 39.8% of it. Spending is not spread thin; it sits in a handful of
places.</li>
<li><strong>Members carry a fifth of the total, and it lands hardest on the cheapest care.</strong>
They pay 41.6% of a wellness visit and 8.6% of an inpatient stay. The inexpensive, routine things
are what people actually feel.</li>
<li><strong>Which plan a member holds matters more than what is wrong with them.</strong>
Prediabetes costs a commercial member 85.0% of the bill and a government member 8.5%: the
same care, a ten-fold difference, produced by benefit design rather than by illness.</li>
<li><strong>Spending concentrates in places, not in people.</strong> 86 of 3,918 sites carry half
the money, but it takes 134,198 members to reach the same half. There is no small group of
high-cost members to manage.</li>
<li><strong>The most expensive facilities are not charging more.</strong> Reprice every procedure
identically and the gap between sites barely moves: only 7.8% of a site&rsquo;s cost per
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
        ': {what}</li>'.format(q=e[0], csv=_result_of(e), what=e[1])
        for e in SOURCES[i])
    return ('<details class="sources"><summary>Sources for this finding '
            ', {n} queries</summary><ul>{items}</ul></details>'
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
               'pregnancy, marked only because it is the outlier; every bar is measured '
               'the same way.')],
  'para': 'Both charts rank conditions by total billed, one as shares of the whole and one as '
          'a ranked bar for each. The distribution they describe is severely top-heavy. Normal '
          'pregnancy takes $28.9B on its own, 39.8% of the $72.7B that carries a diagnosis, '
          'more than three times the second-placed condition. Following the cumulative total '
          'down the ranking, three conditions reach 63.4% and five reach 74.1%, at which point '
          'the distribution flattens: the sixth adds 1.8%, and the fifteen bars after it are '
          'worth $12.1B between them. All twenty together are 90.8% of diagnosed spend, and '
          '66.6% of the $99.1B billed overall. The gap between those two figures is the '
          'roughly quarter of spending that carries no diagnosis and sits outside these charts '
          'entirely.',
  'examined': ['Total billed per condition, ranked, against total billed per member: '
               'the two rankings disagree sharply and the disagreement is the point.',
               'Whether pregnancy at 39.8% is credible. The number of visits per pregnancy is '
               'plausible (11.1, against a real-world 10&ndash;15); the price per visit is '
               'not.',
               'Whether the top twenty are extreme on one driver or several. They are '
               'moderately extreme on all three at once ( members reached, visits each, '
               'cost per visit), and the multiplication does the rest.',
               'Whether facilities differ in what they charge for the same condition. For '
               'eight of the ten largest, barely at all.'],
  'sowhat': 'Cost work has a small and well-defined target: five conditions and most of the '
            'bill is covered. But the five reach the top by different routes: some '
            'through the number of members affected, others through intensity within a few '
            ', so they will not respond to one common approach.'},
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
               'only types that sit away from that trend; both were tested and neither '
               'is a real exception, as the notes below record.')],
  'para': 'Both charts measure the proportion of a bill met by the member rather than the '
          'plan. The bars rank the fifteen types of care by that share; the scatter plots the '
          'same share against what the care costs per person, sized by how many people it '
          'reaches. Share runs from 8.3% to 38.9%, median 20.6%, and it moves inversely with '
          'cost. The categories at the top are the cheapest ones: blood disorders at '
          '38.9% on $1,802 a person, diabetes at 36.6% on $1,675, while cancer sits at '
          '8.3% on $104,622 and allergy and immune conditions at 10.0% on $175,111. The '
          'scatter shows that slope holding across all fifteen points without exception. Size '
          'and share are largely independent: dental is high on both at 27.9% and 938,009 '
          'people, while blood disorders lead on share while reaching only 67,419.',
  'examined': ['Member share by type of care, with total bill and number of people alongside '
               ': share alone says nothing about size.',
               'Whether the pattern survives inside one line of business, or was an artefact '
               'of mixing them. It strengthens: the relationship is clearer within commercial '
               'and within government than across both together.',
               'The two care types that appeared to break the pattern. Neither does: '
               'one is skewed by a handful of very large claims, the other is 90.2% '
               'government-funded.',
               'Why the mechanism differs by line of business, which is Finding 3.'],
  'sowhat': 'What members experience as the cost of cover is the routine care, not the serious '
            'care. Because the categories carrying the highest member share are also among the '
            'widest-reaching ( dental alone touches 938,009 people), a small '
            'change in cost-sharing there reaches far more members than the same change made '
            'anywhere else.'},
 {'title': 'Which plan a member holds matters more than what is wrong with them',
  'figures': [(5,
               'insurance',
               'The same condition, ten times the cost, depending only on the plan',
               'The ten conditions where members carry the most, split by line of business. '
               'Each row is one condition; the two dots are the typical commercial and '
               'government member and <strong>the line between them is the gap</strong>. Dots '
               'are the median of the five annual figures, not the five years pooled.')],
  'para': 'Each row is one condition, with a dot for the typical commercial member and another '
          'for the typical government member; the line between them is the difference in the '
          'share of an identical bill. No row closes. Commercial members carry more on all '
          'ten, by between 12.9 and 78.1 percentage points. Two metabolic conditions separate '
          'from the rest: obesity at 86.8% against 8.7%, prediabetes at 85.0% against '
          '8.5%, while the other eight sit between 13 and 48 points. The two '
          'populations barely overlap: commercial shares run 61.5% to 86.8%, government shares '
          '8.5% to 58.4%, so the lowest commercial figure still exceeds all but the highest '
          'government one. These are typical-year figures, and the year-to-year movement is '
          'small: prediabetes stays between 83.8% and 86.1% for commercial members '
          'across all five years.',
  'examined': ['The ten highest-burden conditions, split three ways, using the typical year '
               'rather than five years pooled so the range is visible.',
               'Whether the gap is stable or a single bad year. It holds in all five.',
               'The mechanism behind it, measured rather than assumed: a flat '
               '$0&ndash;50 per claim on one side, a deductible and annual cap on the other.',
               'Where a blended figure would mislead. Commercial members span 6.7% to 74.4% by '
               'care type, government members 0.6% to 8.1%; the blend describes neither.'],
  'sowhat': 'This gap is a design choice rather than a market condition, which places it '
            'within Calder&rsquo;s control in a way that almost nothing else in this report '
            'is. It also means a single blended member-cost figure describes neither line of '
            'business, and any board pack quoting one is reporting an average that matches no '
            'actual member.'},
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
  'examined': ['Concentration measured four ways ( by member, by facility, by condition, '
               'by type of care) to check the answer was not an artefact of one '
               'grouping.',
               'Whether comparing 86 against 134,198 is fair. It is not on its own: there are '
               '321 times more members than facilities, so the fair comparison is 2.2% against '
               '10.7%.',
               'How the member concentration compares with real claims data. This population '
               'is flatter ( the top 1% carry 11.8% where real books run 20&ndash;25% '
               '), so if anything this understates how few members matter.',
               'Whether the facility concentration is few enough to work through, which is Finding 5.'],
  'sowhat': 'Attention aimed at facilities can be exhaustive, because 86 is a list a team can '
            'finish. Attention aimed at members cannot: reaching the same half of spending '
            'means reaching 134,198 people, so member-level work has to be selective on some '
            'basis this analysis does not supply.'},
 {'title': 'The most expensive facilities are not charging more',
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
          '$4,401 to $144,422, a thirty-three-fold difference. That range is case mix rather '
          'than pricing: repricing every procedure to its all-facility average moves the '
          'spread only from 15.8&times; to 15.2&times;, leaving a median of 7.8% of a '
          'facility&rsquo;s cost per visit attributable to what it charges. The top group is '
          'dialysis, with chronic kidney disease at 53.1% of visits; the group on the right is '
          'hospices, where stays run 22 days and are billed as single visits.',
  'examined': ['Whether the spread is price or case mix, by repricing every procedure to its '
               'all-facility average and remeasuring. It is case mix.',
               'Whether facilities differ in how much they do for the same condition. For the '
               'typical condition, no, and the one big exception is pregnancy.',
               'What separates cheap from expensive pregnancy sites. At the cheapest, 95.5% of '
               'women give birth on site; at the most expensive, 6.8%. Delivery units against '
               'antenatal clinics.',
               'The two groups that stand out on the chart, both identified by facility name '
               'rather than by anything in the data itself.'],
  'sowhat': 'There is no pricing problem at these facilities to correct, so a negotiation '
            'aimed at rates would be working on 7.8% of the difference. What separates the '
            'expensive sites from the rest is the clinical work they do, which is a question '
            'about where care happens rather than what it costs.'}]

if __name__ == '__main__':
    open(OUT, 'w').write(build())
    print('wrote', OUT)
